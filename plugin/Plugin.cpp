// ai_npc.dll -- RED4ext lifecycle, and nothing else.
//
// What this plugin does now is run a CLI on behalf of the mod and hand back what it wrote.
// REDscript cannot spawn a process; a native DLL loaded into the game process can, and it can
// tie the child's lifetime to the game's. Everything about the boundary is in ScriptApi.cpp,
// everything about the child is in Process.cpp, and this file only starts and stops them.
//
// ── WHAT IT USED TO DO, AND WHY THAT IS GONE ────────────────────────────────
//
// It used to supervise a Python HTTP bridge on port 8787, because the mod could only reach a
// CLI through an HTTP client. That cost the player four things they had to get right --
// RedHttpClient's version, the -no-tls launch argument, Python on PATH, and a free port --
// and all four failed with the same symptom, [NO SIGNAL: HTTP 0]. Once the plugin returns the
// output as well as spawning the process, the loopback hop carries nothing but itself.
//
// ── THE VERSION DECLARATION IS A DELIBERATE OFF-LABEL CHOICE ────────────────
//
// This plugin registers RTTI now, and the SDK reserves RUNTIME_VERSION_INDEPENDENT for
// plugins that use RED4ext as a loader only. It is declared anyway, and the reasoning is in
// docs\PLAN_CLI_PROVIDERS.md, stage 4: since a rejected DLL means the game does not start at
// all -- the scripts declare a native class nobody registered -- the useful move is the one
// that maximises the chance of loading. A plugin refused on a declared version is a
// guaranteed block; an independent one resolves its addresses through RED4ext's own table.
//
// The rule that survives from the old file, unchanged, is the one about processes: never
// select one by image name, and never leave an orphan. The job object below is what makes the
// second one true even when the game crashes and Unload never runs.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <RED4ext/Common.hpp>
#include <RED4ext/Api/ApiVersion.hpp>
#include <RED4ext/Api/v1/EMainReason.hpp>
#include <RED4ext/Api/v1/PluginHandle.hpp>
#include <RED4ext/Api/v1/PluginInfo.hpp>
#include <RED4ext/Api/v1/Runtime.hpp>
#include <RED4ext/Api/v1/Sdk.hpp>
#include <RED4ext/Api/v1/Version.hpp>

#include "ScriptApi.hpp"

#include <string>

namespace
{
RED4ext::v1::PluginHandle g_handle = nullptr;
const RED4ext::v1::Sdk* g_sdk = nullptr;
HANDLE g_job = nullptr;

// This DLL's own directory, so settings.json is found relative to the install rather than to
// the game's working directory -- which is not reliably the install root.
std::wstring PluginDirectory()
{
    HMODULE self = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&PluginDirectory), &self))
    {
        return L"";
    }

    std::wstring path(MAX_PATH, L'\0');
    const DWORD length = GetModuleFileNameW(self, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0)
    {
        return L"";
    }
    path.resize(length);

    const size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? L"" : path.substr(0, slash);
}
} // namespace

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle, RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    switch (aReason)
    {
    case RED4ext::v1::EMainReason::Load:
    {
        g_handle = aHandle;
        g_sdk = aSdk;

        // Kill-on-close ties every child to this process even on a crash: when the game dies
        // its handles close, the job goes away, and Windows terminates whatever the CLI left
        // running. Unload is not guaranteed to run; this is.
        g_job = CreateJobObjectW(nullptr, nullptr);
        if (g_job)
        {
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
            limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            SetInformationJobObject(g_job, JobObjectExtendedLimitInformation, &limits, sizeof(limits));
        }
        else if (aSdk && aSdk->logger)
        {
            aSdk->logger->WarnF(aHandle, "could not create the job object (error %lu): a CLI left running by a "
                                         "crash would outlive the game",
                                GetLastError());
        }

        ainpc::script::Start(aHandle, aSdk, PluginDirectory(), g_job);
        break;
    }

    case RED4ext::v1::EMainReason::Unload:
        ainpc::script::Stop();
        if (g_job)
        {
            CloseHandle(g_job);
            g_job = nullptr;
        }
        break;
    }

    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"ai_npc";
    aInfo->author = L"Sebajuste";
    aInfo->version = RED4EXT_V1_SEMVER(0, 6, 0);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_INDEPENDENT;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}
