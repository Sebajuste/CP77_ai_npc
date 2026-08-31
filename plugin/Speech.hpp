// Turning a line of text into something the player hears, with no file and no network.
//
// This is the proof-of-concept half of the voice lane: the synthesiser is Windows' own (SAPI,
// shipped with the OS, offline, no key, no install), and its output is captured into MEMORY
// rather than sent to its own audio device. That is deliberate and is the whole architectural
// point -- the samples come back as a buffer and are played through ainpc::audio, so:
//
//   - there is exactly one audio path in the mod, already measured in game;
//   - hanging up stops the voice, because Stop() belongs to that path;
//   - swapping SAPI for a real text-to-speech service later changes what fills the buffer and
//     nothing else. A network voice returns bytes too.
//
// SAPI is not the voice this mod wants. It is the shape of the lane, available today, and what
// it measures is the number that decides whether the lane is worth building: the delay between
// a line being handed over and the first sound.
//
// NEVER ON THE CALLING THREAD. Synthesis takes hundreds of milliseconds, and the caller is the
// game. Speak() queues and returns; one worker does the work and hands the buffer to the audio
// path itself.

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace ainpc::speech
{
// Queues one line. Returns false only when the line is empty or the worker cannot be started;
// a failure to SYNTHESISE is reported later, through the log, because by then the caller is
// gone.
//
// A second line replaces the one waiting: a character does not talk over itself.
bool Speak(const std::string& aUtf8Text);

// The samples for one line, without playing them. Blocking, and the reason it is public: it
// is the whole of the synthesis half, so it can be asserted outside the game -- the suite runs
// it on a fixture and checks that bytes come back, with no sound and no session.
//
// `aWhy` is filled only on a failure.
bool Render(const std::string& aUtf8Text, std::vector<uint8_t>& aSamples, std::string& aWhy);

// The format Render() writes in, so a caller can hand the buffer to ainpc::audio.
uint32_t SampleRate();
uint16_t Channels();
uint16_t BitsPerSample();

// What happened to the last line handed over, in words -- for the window and the log.
std::string LastResult();

// Stops the worker. Called when the plugin is unloading.
void Shutdown();
}
