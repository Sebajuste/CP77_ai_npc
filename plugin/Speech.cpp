#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <sapi.h>

#include "Speech.hpp"

#include "Audio.hpp"

#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace ainpc::speech
{
namespace
{
// Declared here rather than taken from sapi.lib: the Windows SDK ships the header everywhere
// and the import library nowhere reliable, and one GUID is cheaper than a build that works on
// one machine.
const CLSID kSpVoice = {0x96749377, 0x3391, 0x11D2, {0x9E, 0xE3, 0x00, 0xC0, 0x4F, 0x79, 0x73, 0x96}};
const CLSID kSpStream = {0x715D9C59, 0x4442, 0x11D2, {0x96, 0x05, 0x00, 0xC0, 0x4F, 0x8E, 0xE6, 0x28}};

// The format the samples come back in, and the one ainpc::audio is handed. Mono 22050 is what
// a phone voice sounds like anyway, and it is a quarter of the bytes of 44100 stereo.
constexpr uint32_t kSampleRate = 22050;
constexpr uint16_t kChannels = 1;
constexpr uint16_t kBits = 16;

// A queue and not a slot, and the streaming lane is what decided it. One reply arrives as
// several sentences, each handed over while the previous one is still being synthesised, and a
// single slot would keep the first and the last and silently lose everything between them.
//
// Bounded, because the queue is a character's next few seconds of speech: past a handful, what
// is waiting is no longer an answer to anything the player did. The oldest goes, not the newest
// -- the end of a reply is the part that carries what was decided.
constexpr size_t kQueueLimit = 16;

struct Worker
{
    std::mutex mutex;
    std::condition_variable wake;
    std::deque<std::string> pending;
    std::string result = "nothing said yet";
    bool running = false;
    bool stopping = false;
    std::thread thread;
};

Worker& TheWorker()
{
    static Worker worker;
    return worker;
}

void SetResult(const std::string& aText)
{
    Worker& worker = TheWorker();
    std::lock_guard<std::mutex> guard(worker.mutex);
    worker.result = aText;
}

std::wstring Wide(const std::string& aUtf8)
{
    if (aUtf8.empty())
    {
        return {};
    }
    const int count = MultiByteToWideChar(CP_UTF8, 0, aUtf8.c_str(), -1, nullptr, 0);
    if (count <= 1)
    {
        return {};
    }
    std::wstring out(static_cast<size_t>(count - 1), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, aUtf8.c_str(), -1, out.data(), count);
    return out;
}

// Synthesises into memory. Returns the bytes SAPI wrote, or nothing with a reason.
//
// The whole COM dance is here and validates as one: a caller gets samples or a sentence saying
// why not, never a half-built voice.
//
// COM must already be initialised on the calling thread. The worker does it once; Render()
// does it per call, because a test host has no thread of ours to do it in.
bool Synthesise(const std::wstring& aText, std::vector<uint8_t>& aOut, std::string& aWhy)
{
    IStream* memory = nullptr;
    if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &memory)))
    {
        aWhy = "no memory stream";
        return false;
    }

    WAVEFORMATEX format{};
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = kChannels;
    format.nSamplesPerSec = kSampleRate;
    format.wBitsPerSample = kBits;
    format.nBlockAlign = static_cast<WORD>(kChannels * (kBits / 8));
    format.nAvgBytesPerSec = kSampleRate * format.nBlockAlign;

    ISpStream* stream = nullptr;
    bool ok = false;
    if (SUCCEEDED(CoCreateInstance(kSpStream, nullptr, CLSCTX_ALL, __uuidof(ISpStream),
                                   reinterpret_cast<void**>(&stream))) &&
        SUCCEEDED(stream->SetBaseStream(memory, SPDFID_WaveFormatEx, &format)))
    {
        ISpVoice* voice = nullptr;
        if (SUCCEEDED(CoCreateInstance(kSpVoice, nullptr, CLSCTX_ALL, __uuidof(ISpVoice),
                                       reinterpret_cast<void**>(&voice))))
        {
            voice->SetOutput(stream, TRUE);
            // Synchronous on purpose: this is already the worker thread, and the buffer is not
            // complete until SAPI says it is.
            ok = SUCCEEDED(voice->Speak(aText.c_str(), SPF_DEFAULT, nullptr));
            if (!ok)
            {
                aWhy = "the voice refused the text";
            }
            voice->Release();
        }
        else
        {
            aWhy = "no SAPI voice is installed";
        }
        stream->Release();
    }
    else
    {
        aWhy = "no SAPI stream";
    }

    if (ok)
    {
        HGLOBAL handle = nullptr;
        if (SUCCEEDED(GetHGlobalFromStream(memory, &handle)) && handle != nullptr)
        {
            const SIZE_T size = GlobalSize(handle);
            const void* data = GlobalLock(handle);
            if (data != nullptr && size > 0)
            {
                aOut.assign(static_cast<const uint8_t*>(data), static_cast<const uint8_t*>(data) + size);
            }
            if (data != nullptr)
            {
                GlobalUnlock(handle);
            }
        }
        if (aOut.empty())
        {
            ok = false;
            aWhy = "the voice produced no samples";
        }
    }

    memory->Release();
    return ok;
}

void Run()
{
    // Multi-threaded apartment: this thread owns its COM objects and hands nobody a pointer.
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);

    for (;;)
    {
        std::string text;
        {
            Worker& worker = TheWorker();
            std::unique_lock<std::mutex> lock(worker.mutex);
            worker.wake.wait(lock, [&worker]() { return worker.stopping || !worker.pending.empty(); });
            if (worker.stopping)
            {
                break;
            }
            text = std::move(worker.pending.front());
            worker.pending.pop_front();
        }

        const auto started = std::chrono::steady_clock::now();
        std::vector<uint8_t> samples;
        std::string why = "unknown";
        if (!Synthesise(Wide(text), samples, why))
        {
            SetResult("no voice: " + why);
            continue;
        }

        // SAPI writes raw samples in the format it was given, but a stream that carried a RIFF
        // header would be silently unplayable as raw PCM -- so the shape is read rather than
        // assumed, and both are handled by the audio path we already have.
        audio::Status status;
        if (samples.size() > 4 && samples[0] == 'R' && samples[1] == 'I' && samples[2] == 'F' &&
            samples[3] == 'F')
        {
            status = audio::PlayWav(samples.data(), samples.size());
        }
        else
        {
            audio::Format format;
            format.sampleRate = kSampleRate;
            format.channels = kChannels;
            format.bitsPerSample = kBits;
            status = audio::Play(samples.data(), samples.size(), format);
        }

        // The number the voice lane lives or dies by: how long the player waits between a line
        // being handed over and the first sound. Mantella's players report latency as their
        // first complaint, and every second of it is synthesis rather than the model.
        const auto milliseconds =
            std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started)
                .count();
        SetResult(std::string(audio::Describe(status)) + " -- " + std::to_string(samples.size()) +
                  " bytes in " + std::to_string(milliseconds) + " ms");
    }

    CoUninitialize();
}
}

bool Render(const std::string& aUtf8Text, std::vector<uint8_t>& aSamples, std::string& aWhy)
{
    if (aUtf8Text.empty())
    {
        aWhy = "nothing to say";
        return false;
    }

    // Initialised and released around the call: this may be any thread, including one that has
    // never seen COM. An apartment that is already open answers RPC_E_CHANGED_MODE, which is
    // not a failure -- it means somebody else owns it, and we must not close it.
    const HRESULT opened = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool ours = SUCCEEDED(opened);

    const bool ok = Synthesise(Wide(aUtf8Text), aSamples, aWhy);

    if (ours)
    {
        CoUninitialize();
    }
    return ok;
}

uint32_t SampleRate()
{
    return kSampleRate;
}

uint16_t Channels()
{
    return kChannels;
}

uint16_t BitsPerSample()
{
    return kBits;
}

bool Speak(const std::string& aUtf8Text)
{
    if (aUtf8Text.empty())
    {
        return false;
    }

    Worker& worker = TheWorker();
    std::lock_guard<std::mutex> guard(worker.mutex);
    if (worker.stopping)
    {
        return false;
    }
    if (!worker.running)
    {
        worker.running = true;
        worker.thread = std::thread(&Run);
    }

    // Spoken in the order they were handed over: a character does not talk over itself, and the
    // sentences of one reply are one utterance cut into pieces.
    worker.pending.push_back(aUtf8Text);
    while (worker.pending.size() > kQueueLimit)
    {
        worker.pending.pop_front();
    }
    worker.wake.notify_one();
    return true;
}

std::string LastResult()
{
    Worker& worker = TheWorker();
    std::lock_guard<std::mutex> guard(worker.mutex);
    return worker.result;
}

void Shutdown()
{
    Worker& worker = TheWorker();
    std::thread thread;
    {
        std::lock_guard<std::mutex> guard(worker.mutex);
        worker.stopping = true;
        worker.wake.notify_all();
        thread = std::move(worker.thread);
    }
    if (thread.joinable())
    {
        thread.join();
    }
    audio::Stop();
}
}
