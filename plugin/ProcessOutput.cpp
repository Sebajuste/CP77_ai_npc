#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <mmdeviceapi.h>
#include <audiopolicy.h>
#include <wrl/client.h>

#include "ProcessOutput.hpp"

#include <string>
#include <thread>

using Microsoft::WRL::ComPtr;

namespace ainpc::audio
{
namespace
{
// mmddk.h, which the SDK does not expose to user mode: DRV_RESERVED + 17 and + 18.
constexpr UINT kQueryInstanceId = 0x0800 + 17;
constexpr UINT kQueryInstanceIdSize = 0x0800 + 18;

bool HasActiveSessionOf(IMMDevice* aDevice, DWORD aProcess)
{
    ComPtr<IAudioSessionManager2> manager;
    if (FAILED(aDevice->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL, nullptr,
                                 reinterpret_cast<void**>(manager.GetAddressOf()))))
    {
        return false;
    }
    ComPtr<IAudioSessionEnumerator> sessions;
    int count = 0;
    if (FAILED(manager->GetSessionEnumerator(&sessions)) || FAILED(sessions->GetCount(&count)))
    {
        return false;
    }

    for (int i = 0; i < count; ++i)
    {
        ComPtr<IAudioSessionControl> control;
        ComPtr<IAudioSessionControl2> identified;
        DWORD owner = 0;
        AudioSessionState state = AudioSessionStateInactive;
        if (SUCCEEDED(sessions->GetSession(i, &control)) && SUCCEEDED(control.As(&identified)) &&
            identified->GetProcessId(&owner) == S_OK && owner == aProcess &&
            SUCCEEDED(control->GetState(&state)) && state == AudioSessionStateActive)
        {
            return true;
        }
    }
    return false;
}

std::wstring EndpointId(IMMDevice* aDevice)
{
    LPWSTR raw = nullptr;
    if (FAILED(aDevice->GetId(&raw)) || raw == nullptr)
    {
        return {};
    }
    std::wstring id(raw);
    CoTaskMemFree(raw);
    return id;
}

// The waveOut device whose driver instance is that endpoint.
std::optional<unsigned> WaveOutIdOf(const std::wstring& aEndpoint)
{
    const UINT count = waveOutGetNumDevs();
    for (UINT i = 0; i < count; ++i)
    {
        const auto handle = reinterpret_cast<HWAVEOUT>(static_cast<UINT_PTR>(i));
        size_t bytes = 0;
        if (waveOutMessage(handle, kQueryInstanceIdSize, reinterpret_cast<DWORD_PTR>(&bytes), 0) ==
                MMSYSERR_NOERROR &&
            bytes >= sizeof(wchar_t))
        {
            std::wstring id(bytes / sizeof(wchar_t), L'\0');
            if (waveOutMessage(handle, kQueryInstanceId, reinterpret_cast<DWORD_PTR>(id.data()), bytes) ==
                    MMSYSERR_NOERROR &&
                _wcsicmp(id.c_str(), aEndpoint.c_str()) == 0)
            {
                return i;
            }
        }
    }
    return std::nullopt;
}

std::optional<unsigned> Query()
{
    ComPtr<IMMDeviceEnumerator> enumerator;
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                IID_PPV_ARGS(&enumerator))))
    {
        return std::nullopt;
    }

    std::wstring fallback;
    ComPtr<IMMDevice> defaultDevice;
    if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &defaultDevice)))
    {
        fallback = EndpointId(defaultDevice.Get());
    }

    ComPtr<IMMDeviceCollection> endpoints;
    UINT count = 0;
    if (FAILED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &endpoints)) ||
        FAILED(endpoints->GetCount(&count)))
    {
        return std::nullopt;
    }

    const DWORD self = GetCurrentProcessId();
    std::wstring chosen;
    for (UINT i = 0; i < count; ++i)
    {
        ComPtr<IMMDevice> device;
        if (SUCCEEDED(endpoints->Item(i, &device)) && HasActiveSessionOf(device.Get(), self))
        {
            const std::wstring id = EndpointId(device.Get());
            if (chosen.empty() || id == fallback)
            {
                chosen = id;
            }
        }
    }

    if (chosen.empty())
    {
        return std::nullopt;
    }
    return WaveOutIdOf(chosen);
}
}

// On a thread of its own, because the caller may be the game thread, whose COM apartment is the
// game's to choose: initialising it here could fail or, worse, succeed with the wrong model.
std::optional<unsigned> ProcessOutput()
{
    std::optional<unsigned> found;
    std::thread worker(
        [&found]()
        {
            if (SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED)))
            {
                found = Query();
                CoUninitialize();
            }
        });
    worker.join();
    return found;
}
}
