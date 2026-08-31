#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>

#include "Audio.hpp"

#include <cmath>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace ainpc::audio
{
namespace
{
// One voice, and the state that outlives the call that started it. waveOut needs the sample
// memory and the WAVEHDR to stay put until the device reports it is done with them, which is
// long after Play() has returned to the game thread.
struct Voice
{
    std::mutex mutex;
    HWAVEOUT device = nullptr;
    WAVEHDR header{};
    std::vector<uint8_t> samples;
    std::thread drain;
    bool playing = false;
    std::string device_name;
};

Voice& TheVoice()
{
    static Voice voice;
    return voice;
}

// Closes the device and releases the buffer, on the drain thread or on Stop's caller.
// waveOutReset must have run first, or unpreparing a header still queued fails.
void Release(Voice& aVoice)
{
    if (aVoice.device == nullptr)
    {
        return;
    }
    waveOutUnprepareHeader(aVoice.device, &aVoice.header, sizeof(WAVEHDR));
    waveOutClose(aVoice.device);
    aVoice.device = nullptr;
    aVoice.header = WAVEHDR{};
    aVoice.samples.clear();
    aVoice.playing = false;
}

// Joins the previous voice before starting a new one. Called with the lock NOT held: the
// drain thread takes it to finish, so joining under the lock deadlocks.
void StopAndJoin()
{
    Voice& voice = TheVoice();
    std::thread previous;
    {
        std::lock_guard<std::mutex> guard(voice.mutex);
        if (voice.device != nullptr)
        {
            waveOutReset(voice.device);
        }
        previous = std::move(voice.drain);
    }
    if (previous.joinable())
    {
        previous.join();
    }
    {
        std::lock_guard<std::mutex> guard(voice.mutex);
        Release(voice);
    }
}

// Reads a little-endian value at an offset the caller has already bounds-checked.
uint32_t ReadU32(const uint8_t* aAt)
{
    return static_cast<uint32_t>(aAt[0]) | (static_cast<uint32_t>(aAt[1]) << 8) |
           (static_cast<uint32_t>(aAt[2]) << 16) | (static_cast<uint32_t>(aAt[3]) << 24);
}

uint16_t ReadU16(const uint8_t* aAt)
{
    return static_cast<uint16_t>(static_cast<uint16_t>(aAt[0]) | (static_cast<uint16_t>(aAt[1]) << 8));
}

bool FourCC(const uint8_t* aAt, const char* aTag)
{
    return std::memcmp(aAt, aTag, 4) == 0;
}

constexpr uint16_t kFormatPcm = 1;
constexpr uint16_t kFormatExtensible = 0xFFFE;

// Device names reach redscript through Beep(), and this folder's encoding rule is hard: the
// A variants of the waveOut calls hand back the system ANSI codepage, so an accented device
// name -- "Casque pour telephone" with its accents -- would cross the boundary as mojibake.
// The W variants and one conversion keep it UTF-8 all the way.
std::string Utf8(const wchar_t* aText)
{
    if (aText == nullptr || aText[0] == L'\0')
    {
        return {};
    }
    const int bytes = WideCharToMultiByte(CP_UTF8, 0, aText, -1, nullptr, 0, nullptr, nullptr);
    if (bytes <= 1)
    {
        return {};
    }
    std::string out(static_cast<size_t>(bytes - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, aText, -1, out.data(), bytes, nullptr, nullptr);
    return out;
}

// Where a sound actually went, in words -- the answer to the one report that costs the most
// time, "it says ok and I hear nothing".
//
// waveOutGetID is asked of the OPEN handle, because WAVE_MAPPER is a request rather than a
// device. It does not always answer: on this machine it hands back the mapper's own id, whose
// caps are named "Microsoft Sound Mapper" in the system language -- a name that identifies
// nothing. That case is reported as what it is instead of being dressed up, and the number of
// outputs goes with it either way, since "one output" and "four outputs" turn the same
// silence into two different problems.
std::string NameOfOutput(HWAVEOUT aHandle)
{
    const UINT count = waveOutGetNumDevs();
    std::string named = "the Windows default output, which the mapper would not name";

    UINT id = 0;
    WAVEOUTCAPSW caps{};
    if (waveOutGetID(aHandle, &id) == MMSYSERR_NOERROR && id != static_cast<UINT>(WAVE_MAPPER) &&
        waveOutGetDevCapsW(id, &caps, sizeof(caps)) == MMSYSERR_NOERROR)
    {
        named = Utf8(caps.szPname);
    }

    return named + " (" + std::to_string(count) + " output(s) on this machine)";
}
}

const char* Describe(Status aStatus)
{
    switch (aStatus)
    {
    case Status::Ok: return "ok";
    case Status::EmptyBuffer: return "empty buffer";
    case Status::UnsupportedFormat: return "unsupported format";
    case Status::NoDevice: return "no output device accepted the format";
    case Status::WriteFailed: return "the device refused the buffer";
    case Status::NotWave: return "not a RIFF/WAVE image";
    case Status::NotPcm: return "a WAVE, but not uncompressed PCM";
    case Status::Truncated: return "the image ends inside its own data chunk";
    }
    return "unknown";
}

Sound Tone(double aSeconds, double aHertz, double aAmplitude)
{
    Sound sound;
    sound.format = Format{};

    const size_t frames = static_cast<size_t>(aSeconds * sound.format.sampleRate);
    sound.samples.resize(frames * 2);
    for (size_t i = 0; i < frames; ++i)
    {
        const double t = static_cast<double>(i) / sound.format.sampleRate;
        const auto value =
            static_cast<int16_t>(aAmplitude * 32767.0 * std::sin(6.283185307179586 * aHertz * t));
        sound.samples[i * 2] = static_cast<uint8_t>(value & 0xFF);
        sound.samples[i * 2 + 1] = static_cast<uint8_t>((value >> 8) & 0xFF);
    }
    return sound;
}

Status Play(const void* aSamples, size_t aBytes, const Format& aFormat)
{
    if (aSamples == nullptr || aBytes == 0)
    {
        return Status::EmptyBuffer;
    }
    if (aFormat.channels == 0 || aFormat.sampleRate == 0 ||
        (aFormat.bitsPerSample != 8 && aFormat.bitsPerSample != 16))
    {
        return Status::UnsupportedFormat;
    }

    StopAndJoin();

    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);

    WAVEFORMATEX wave{};
    wave.wFormatTag = WAVE_FORMAT_PCM;
    wave.nChannels = aFormat.channels;
    wave.nSamplesPerSec = aFormat.sampleRate;
    wave.wBitsPerSample = aFormat.bitsPerSample;
    wave.nBlockAlign = static_cast<WORD>(aFormat.channels * (aFormat.bitsPerSample / 8));
    wave.nAvgBytesPerSec = aFormat.sampleRate * wave.nBlockAlign;

    if (waveOutOpen(&voice.device, WAVE_MAPPER, &wave, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR)
    {
        voice.device = nullptr;
        return Status::NoDevice;
    }

    voice.device_name = NameOfOutput(voice.device);

    voice.samples.assign(static_cast<const uint8_t*>(aSamples),
                         static_cast<const uint8_t*>(aSamples) + aBytes);
    voice.header = WAVEHDR{};
    voice.header.lpData = reinterpret_cast<LPSTR>(voice.samples.data());
    voice.header.dwBufferLength = static_cast<DWORD>(voice.samples.size());

    if (waveOutPrepareHeader(voice.device, &voice.header, sizeof(WAVEHDR)) != MMSYSERR_NOERROR ||
        waveOutWrite(voice.device, &voice.header, sizeof(WAVEHDR)) != MMSYSERR_NOERROR)
    {
        waveOutClose(voice.device);
        voice.device = nullptr;
        voice.samples.clear();
        return Status::WriteFailed;
    }

    voice.playing = true;
    // The device owns the buffer until WHDR_DONE. Waiting for it is what the caller must not
    // do, so it happens here, on a thread whose whole job is to hand the memory back.
    voice.drain = std::thread(
        []()
        {
            Voice& self = TheVoice();
            for (;;)
            {
                {
                    std::lock_guard<std::mutex> guard(self.mutex);
                    if (self.device == nullptr || (self.header.dwFlags & WHDR_DONE) != 0)
                    {
                        Release(self);
                        return;
                    }
                }
                Sleep(10);
            }
        });

    return Status::Ok;
}

Status PlayWav(const void* aImage, size_t aBytes)
{
    if (aImage == nullptr || aBytes < 44)
    {
        return Status::EmptyBuffer;
    }

    const uint8_t* image = static_cast<const uint8_t*>(aImage);
    if (!FourCC(image, "RIFF") || !FourCC(image + 8, "WAVE"))
    {
        return Status::NotWave;
    }

    Format format;
    const uint8_t* data = nullptr;
    size_t dataBytes = 0;
    bool sawFormat = false;

    // One walk, one verdict. A chunk header is 8 bytes and chunks are word-aligned; anything
    // that does not fit is a truncated image rather than a chunk to skip.
    size_t at = 12;
    while (at + 8 <= aBytes)
    {
        const uint32_t size = ReadU32(image + at + 4);
        const size_t body = at + 8;
        if (body + size > aBytes)
        {
            return Status::Truncated;
        }

        if (FourCC(image + at, "fmt ") && size >= 16)
        {
            const uint16_t tag = ReadU16(image + body);
            if (tag != kFormatPcm && tag != kFormatExtensible)
            {
                return Status::NotPcm;
            }
            format.channels = ReadU16(image + body + 2);
            format.sampleRate = ReadU32(image + body + 4);
            format.bitsPerSample = ReadU16(image + body + 14);
            sawFormat = true;
        }
        else if (FourCC(image + at, "data"))
        {
            data = image + body;
            dataBytes = size;
        }

        at = body + size + (size & 1u);
    }

    if (!sawFormat || data == nullptr)
    {
        return Status::NotWave;
    }
    if (dataBytes == 0)
    {
        return Status::EmptyBuffer;
    }
    return Play(data, dataBytes, format);
}

void Stop()
{
    StopAndJoin();
}

std::vector<std::string> Outputs()
{
    std::vector<std::string> names;
    const UINT count = waveOutGetNumDevs();
    for (UINT i = 0; i < count; ++i)
    {
        WAVEOUTCAPSW caps{};
        if (waveOutGetDevCapsW(i, &caps, sizeof(caps)) == MMSYSERR_NOERROR)
        {
            // szPname is 32 wide characters including the terminator, so a long name arrives
            // cut. That is the API's limit and not ours; a cut name still identifies a device
            // to the person reading it.
            names.emplace_back(Utf8(caps.szPname));
        }
        else
        {
            names.emplace_back("<unnamed>");
        }
    }
    return names;
}

std::string DeviceName()
{
    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);
    return voice.device_name;
}

bool IsPlaying()
{
    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);
    return voice.playing;
}
}
