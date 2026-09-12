// Reading what the plugin needs out of the mod's own settings.json.
//
// The plugin reads that file directly rather than being handed the values across the RTTI
// boundary, and the reason is the boundary itself: every value passed across is a parameter
// on a native function, and every native function is part of the surface that can stop the
// game booting when the DLL is absent. Send() takes three arguments because three is what
// the request needs; a path the plugin can read for itself is not one of them.
//
// The file lives at <game>\r6\storages\AiNpc\settings.json, found by walking up from this
// DLL's own directory rather than from the game's working directory -- which is not reliably
// the install root.

#pragma once

#include <string>

#include "Transport.hpp"

namespace ainpc
{
// Re-read on every request. It is a few hundred bytes next to a CLI invocation that takes
// seconds, and reading it once at load would mean a player who fixes a path has to restart
// the game to find out whether the fix worked.
Settings ReadSettings(const std::wstring& aPluginDirectory);

// "holoRadioFilter", as written. Empty when absent. Re-read on every spoken line, so the CET
// window's buttons are heard on the next one.
std::string ReadHoloRadioFilter(const std::wstring& aPluginDirectory);

// <plugin dir>\..\..\..\r6\storages\AiNpc\settings.json, resolved. Public so the log can
// name the file it failed to read.
std::wstring SettingsPath(const std::wstring& aPluginDirectory);
} // namespace ainpc
