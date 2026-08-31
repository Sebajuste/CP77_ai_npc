#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "SettingsFile.hpp"

#include "Json.hpp"
#include "Text.hpp"

namespace ainpc
{
namespace
{
std::wstring Parent(const std::wstring& aPath)
{
    const size_t slash = aPath.find_last_of(L"\\/");
    return slash == std::wstring::npos ? L"" : aPath.substr(0, slash);
}
} // namespace

std::wstring SettingsPath(const std::wstring& aPluginDirectory)
{
    // red4ext\plugins\ai_npc -> red4ext\plugins -> red4ext -> the game root.
    const std::wstring root = Parent(Parent(Parent(aPluginDirectory)));
    if (root.empty())
    {
        return L"";
    }
    return root + L"\\r6\\storages\\AiNpc\\settings.json";
}

Settings ReadSettings(const std::wstring& aPluginDirectory)
{
    Settings settings;

    const std::wstring path = SettingsPath(aPluginDirectory);
    if (path.empty())
    {
        return settings;
    }

    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        // Absent is not an error. Both paths are optional -- empty means "look on PATH",
        // which is what works on most machines -- and a lane that needs the key reports its
        // absence itself, in the sentence that says where to put it.
        return settings;
    }

    std::string raw;
    char buffer[4096];
    DWORD read = 0;
    while (ReadFile(file, buffer, sizeof(buffer), &read, nullptr) && read > 0)
    {
        raw.append(buffer, read);
    }
    CloseHandle(file);

    // The mod writes this file as UTF-8 without a BOM, but a player who edited it by hand in
    // Notepad may have added one, and a BOM in front of '{' is not JSON.
    if (raw.size() >= 3 && static_cast<unsigned char>(raw[0]) == 0xEF &&
        static_cast<unsigned char>(raw[1]) == 0xBB && static_cast<unsigned char>(raw[2]) == 0xBF)
    {
        raw.erase(0, 3);
    }

    json::Value root;
    if (!json::Parse(raw, root) || !root.IsObject())
    {
        return settings;
    }

    settings.claudePath = Widen(root.StringAt("claudeCliPath"));
    settings.codexPath = Widen(root.StringAt("codexCliPath"));
    settings.openRouterKey = root.StringAt("openRouterApiKey");
    return settings;
}
} // namespace ainpc
