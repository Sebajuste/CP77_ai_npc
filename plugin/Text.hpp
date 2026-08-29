// The two string operations every backend needs, and neither of which belongs to any of them.
//
// They live here rather than being copied into each backend because they are not decisions:
// Widen has exactly one correct implementation, and a second copy of it is a second place for
// the code page to creep back in. The rule this file follows is the one in CLAUDE.md -- the
// bytes are UTF-8 from the mod to the CLI and back, and never go through the console code page.

#pragma once

#include <string>

namespace ainpc
{
// UTF-8 bytes to UTF-16, which is what every Windows API on this side of the boundary takes.
// An invalid sequence yields an empty string rather than a replacement character: a mangled
// command line is worse than a missing one, because it fails somewhere else.
std::wstring Widen(const std::string& aUtf8);

// The last non-empty line of whatever a CLI complained with, trimmed.
//
// The player sees this sentence. A stack trace's last line is the useful one, and a CLI that
// died before it could produce structured output usually says why in its last line -- often
// a shell or installer message that names its own cause.
std::string LastLine(const std::string& aText);
} // namespace ainpc
