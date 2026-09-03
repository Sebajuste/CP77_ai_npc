#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <sapi.h>

#include "SapiVoice.hpp"

namespace ainpc::sapi
{
namespace
{
// Declares ici plutot que pris dans sapi.lib : le SDK Windows livre l'en-tete partout et la
// bibliotheque d'import nulle part de facon fiable, et un GUID coute moins cher qu'une
// compilation qui ne marche que sur une machine.
const CLSID kSpVoice = {0x96749377, 0x3391, 0x11D2, {0x9E, 0xE3, 0x00, 0xC0, 0x4F, 0x79, 0x73, 0x96}};
const CLSID kSpStream = {0x715D9C59, 0x4442, 0x11D2, {0x96, 0x05, 0x00, 0xC0, 0x4F, 0x8E, 0xE6, 0x28}};

constexpr uint32_t kSampleRate = 22050;
constexpr uint16_t kChannels = 1;
constexpr uint16_t kBits = 16;

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

// Toute la danse COM tient ici et se valide d'un bloc : l'appelant recoit des echantillons ou
// une phrase qui dit pourquoi, jamais une voix a moitie construite.
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
            // Synchrone a dessein : le tampon n'est complet que quand SAPI le dit.
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
} // namespace

bool Render(const std::string& aUtf8Text, std::vector<uint8_t>& aSamples, std::string& aWhy)
{
    if (aUtf8Text.empty())
    {
        aWhy = "nothing to say";
        return false;
    }

    // Ouvert et referme autour de l'appel : ce peut etre n'importe quel fil, y compris un qui
    // n'a jamais vu COM. Un appartement deja ouvert repond RPC_E_CHANGED_MODE, ce qui n'est pas
    // un echec -- cela veut dire qu'il appartient a quelqu'un d'autre, et qu'il ne faut pas le
    // fermer.
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
} // namespace ainpc::sapi
