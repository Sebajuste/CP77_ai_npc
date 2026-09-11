// Which output this process is already playing on.
//
// Cyberpunk has no output setting: Wwise plays wherever Windows routes the game, which is the
// default device unless the player assigned another one to the game in the volume mixer. The
// DLL runs inside the game's process, so the game's device is the endpoint holding an ACTIVE
// audio session of this process -- measured by asking Windows, never guessed from the default.
//
// No RED4ext dependency: plugin\test\run.ps1 asserts it outside the game, where the process
// playing is the test host itself.

#pragma once

#include <optional>

namespace ainpc::audio
{
// The waveOut id of that endpoint, or nothing when no session of this process is active or the
// endpoint has no waveOut twin. Callers fall back to WAVE_MAPPER.
//
// When several endpoints qualify, the Windows default wins, which is what the mapper would have
// picked anyway.
std::optional<unsigned> ProcessOutput();
}
