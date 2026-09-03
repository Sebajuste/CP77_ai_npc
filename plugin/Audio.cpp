#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>

#include "Audio.hpp"

#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace ainpc::audio
{
namespace
{
// Un morceau de la prise de parole. waveOut veut que les echantillons ET l'en-tete restent en
// place jusqu'a ce qu'il rende le morceau -- longtemps apres que l'appelant est reparti -- donc
// chacun possede sa memoire et ne bouge plus. `unique_ptr` parce que la file grandit pendant
// que le pilote tient des pointeurs dedans : un vecteur qui se reallouerait les invaliderait.
struct Chunk
{
    std::vector<uint8_t> samples;
    WAVEHDR header{};
    bool prepared = false;
};

// One voice, and the state that outlives the call that started it.
struct Voice
{
    std::mutex mutex;
    HWAVEOUT device = nullptr;
    std::vector<std::unique_ptr<Chunk>> chunks;
    std::thread drain;
    // Le format de la prise en cours. Une phrase qui arrive au meme format continue la prise
    // ouverte ; un format different est une autre voix, et celle-la remplace.
    Format format{};
    bool playing = false;
    // Plus aucun morceau ne viendra. C'est ce qui autorise le fil de vidange a fermer : sans
    // cette marque il fermerait entre deux morceaux d'une meme phrase.
    bool closed = false;
    std::string device_name;

    // A LA FIN DU PROCESSUS, et c'est le fil de vidange qui l'exige.
    //
    // Il se termine tout seul quand la prise est finie, mais l'objet std::thread reste
    // JOIGNABLE tant que personne ne l'a joint -- et detruire un std::thread joignable appelle
    // std::terminate. Le mod ne le voyait pas parce que speech::Shutdown() appelle Stop(), qui
    // joint ; un banc qui sort sans Stop plantait a l'exit, apres avoir tout joue correctement.
    // Mesure du 2026-09-02, code de sortie 0xC0000409.
    ~Voice()
    {
        if (device != nullptr)
        {
            waveOutReset(device);
        }
        closed = true;
        if (drain.joinable())
        {
            drain.join();
        }
    }
};

Voice& TheVoice()
{
    static Voice voice;
    return voice;
}

// Closes the device and releases every buffer, on the drain thread or on Stop's caller.
// waveOutReset must have run first, or unpreparing a header still queued fails.
void Release(Voice& aVoice)
{
    if (aVoice.device == nullptr)
    {
        return;
    }
    for (auto& chunk : aVoice.chunks)
    {
        if (chunk->prepared)
        {
            waveOutUnprepareHeader(aVoice.device, &chunk->header, sizeof(WAVEHDR));
        }
    }
    waveOutClose(aVoice.device);
    aVoice.device = nullptr;
    aVoice.chunks.clear();
    aVoice.playing = false;
    aVoice.closed = false;
}

// Tout ce qui a ete ecrit a-t-il ete rendu ? Sous le verrou de l'appelant.
bool AllDone(const Voice& aVoice)
{
    for (const auto& chunk : aVoice.chunks)
    {
        if ((chunk->header.dwFlags & WHDR_DONE) == 0)
        {
            return false;
        }
    }
    return true;
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
        // FERMEE, et pas seulement reinitialisee. Le fil de vidange ne sort que sur « close et
        // tout rendu » : sans cette ligne, un Stop() au milieu d'une prise le laisserait tourner
        // pour toujours et le join ci-dessous ne reviendrait jamais. Un reset veut dire qu'il ne
        // viendra plus rien, ce qui est exactement ce que `closed` affirme.
        voice.closed = true;
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

Status Open(const Format& aFormat)
{
    if (aFormat.channels == 0 || aFormat.sampleRate == 0 ||
        (aFormat.bitsPerSample != 8 && aFormat.bitsPerSample != 16))
    {
        return Status::UnsupportedFormat;
    }

    Voice& voice = TheVoice();
    {
        // UNE REPLIQUE N'EST PAS UNE SUITE DE REPLIQUES. Le moteur rend phrase par phrase et la
        // file les recoit une par une ; chaque phrase ouvrait sa propre prise, et l'ouverture
        // commence par arreter ce qui joue. La deuxieme phrase coupait donc la premiere au
        // milieu d'un mot -- mesure en jeu le 2026-09-02, sur une reponse de deux phrases.
        //
        // Une prise encore vivante se poursuit : les morceaux de la phrase suivante se rangent
        // derriere ceux qui restent. `closed` retombe a faux avant que le fil de vidange ne
        // relise la marque, et il la relit sous ce meme verrou.
        std::lock_guard<std::mutex> guard(voice.mutex);
        if (voice.device != nullptr && voice.format.sampleRate == aFormat.sampleRate &&
            voice.format.channels == aFormat.channels &&
            voice.format.bitsPerSample == aFormat.bitsPerSample)
        {
            voice.closed = false;
            voice.playing = true;
            return Status::Ok;
        }
    }

    StopAndJoin();

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
    voice.format = aFormat;
    voice.playing = true;
    voice.closed = false;

    // Le peripherique possede chaque morceau jusqu'a WHDR_DONE. Attendre est ce que l'appelant
    // ne doit pas faire, donc cela se passe ici, sur un fil dont c'est tout le travail : rendre
    // la memoire au fur et a mesure, et fermer quand la prise est finie et vide.
    voice.drain = std::thread(
        []()
        {
            Voice& self = TheVoice();
            for (;;)
            {
                {
                    std::lock_guard<std::mutex> guard(self.mutex);
                    if (self.device == nullptr)
                    {
                        return;
                    }
                    if (self.closed && AllDone(self))
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

Status Push(const void* aSamples, size_t aBytes)
{
    if (aSamples == nullptr || aBytes == 0)
    {
        return Status::EmptyBuffer;
    }

    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);
    // Une file fermee ne se rouvre pas : un morceau ecrit apres la fin de sa prise jouerait
    // hors de son tour, ou derriere la suivante.
    if (voice.device == nullptr || voice.closed)
    {
        return Status::NoDevice;
    }

    auto chunk = std::make_unique<Chunk>();
    chunk->samples.assign(static_cast<const uint8_t*>(aSamples),
                          static_cast<const uint8_t*>(aSamples) + aBytes);
    chunk->header.lpData = reinterpret_cast<LPSTR>(chunk->samples.data());
    chunk->header.dwBufferLength = static_cast<DWORD>(chunk->samples.size());

    if (waveOutPrepareHeader(voice.device, &chunk->header, sizeof(WAVEHDR)) != MMSYSERR_NOERROR)
    {
        return Status::WriteFailed;
    }
    chunk->prepared = true;
    if (waveOutWrite(voice.device, &chunk->header, sizeof(WAVEHDR)) != MMSYSERR_NOERROR)
    {
        waveOutUnprepareHeader(voice.device, &chunk->header, sizeof(WAVEHDR));
        return Status::WriteFailed;
    }

    voice.chunks.push_back(std::move(chunk));
    return Status::Ok;
}

void Close()
{
    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);
    voice.closed = true;
}

// La replique entiere d'un coup : la meme file, ouverte, remplie et fermee sans respirer. Tout
// ce qui appelait Play() avant le streaming continue de marcher a l'identique -- y compris le
// remplacement, que l'arret explicite conserve maintenant que l'ouverture, elle, prolonge.
Status Play(const void* aSamples, size_t aBytes, const Format& aFormat)
{
    if (aSamples == nullptr || aBytes == 0)
    {
        return Status::EmptyBuffer;
    }

    Stop();
    const Status opened = Open(aFormat);
    if (opened != Status::Ok)
    {
        return opened;
    }
    const Status pushed = Push(aSamples, aBytes);
    Close();
    return pushed;
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
