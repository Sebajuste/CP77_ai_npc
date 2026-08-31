// What a CLI backend is, and the OpenAI dialect every lane in this plugin speaks.
//
// ITransport is for CLI backends and stays that way. There is one lane in here that is not
// one -- the streaming client in OpenRouterStream.hpp, which owns a socket instead of a
// process -- and it is deliberately not made to fit this interface: five of the seven methods
// would answer "not applicable", and an abstraction spanning both would be owned by neither.
// What the two share is the dialect below, which is the only thing they need to share.
//
// The dialect is the important half of this file. The plugin receives the same
// chat/completions body an HTTP lane would have posted and returns the same response shape,
// so the mod keeps one request builder and one response parser for every backend it will
// ever have. A backend's whole job is the bit in between: turn that request into a command
// line and a stdin, and turn what came back into that response.
//
// SYSTEM AND USER STAY APART all the way to the backend. Claude takes --system-prompt;
// Codex has no equivalent and must fold the system block into its input. Where that block
// goes decides the instruction hierarchy the safe-for-work tier depends on, so it is a
// per-backend decision -- which is why ChatRequest keeps the two halves separate instead of
// handing down one string.
//
// Everything declared here is free of RED4ext and of Windows UI, which is what lets the
// offline test host build a backend, feed it a canned stdout, and assert what it produced.

#pragma once

#include <string>
#include <vector>

#include "Process.hpp"

namespace ainpc
{
// One generation, taken apart from the OpenAI body.
struct ChatRequest
{
    std::string model;
    std::string system;
    std::string user;
};

// What goes back to script, in the shape AiNpcReply.FromCli expects.
//
// `status` plays the part of an HTTP status code, and that is not a metaphor for its own
// sake: a typed failure travels as a non-200 with {"error":{"message":...}} in the body, so
// a CLI that is not signed in reaches the player through the same lines of redscript as an
// OpenRouter 401 -- down to the sentence in the bubble.
struct ChatReply
{
    int status = 0;
    std::string body;
};

// What the plugin needs out of the mod's own settings.json: where the executables are, and the
// credential the streaming lane sends. Read here rather than passed across the boundary, for
// the reason SettingsFile.hpp gives.
struct Settings
{
    std::wstring claudePath;
    std::wstring codexPath;
    std::string openRouterKey;
};

struct ITransport
{
    virtual ~ITransport() = default;

    // The name script sends across, and the key this backend is found by.
    virtual const char* Name() const = 0;

    // Full path to the executable, or empty when it cannot be found.
    virtual std::wstring Executable(const Settings& aSettings) const = 0;

    // Whether the system block has to be on disk before the command line means anything.
    //
    // True for Claude, which takes --system-prompt-file. That flag is what keeps this lane
    // off the command line entirely: Windows caps a command line at 32767 characters, the
    // mod's system prompt is a few KB that a customised character can grow, and the old
    // Python bridge carried a MAX_SYSTEM_PROMPT_CHARS guard because it had nowhere else to
    // put it. A file has no such limit, so the guard is gone rather than moved.
    //
    // False for Codex, which has no system prompt at all and folds the block into its input.
    virtual bool WantsSystemPromptFile() const = 0;

    // Everything below is pure, and deliberately so: it is the whole of what the offline
    // suite can assert without a game, a network or a CLI installed. The system-prompt file
    // is passed in rather than created here for the same reason -- a function that writes to
    // disk cannot be asserted from a fixture.
    virtual std::wstring CommandLine(const std::wstring& aExecutable, const ChatRequest& aRequest,
                                     const std::wstring& aSystemPromptFile) const = 0;
    virtual std::string StandardInput(const ChatRequest& aRequest) const = 0;
    virtual ChatReply Interpret(const ProcessResult& aResult) const = 0;

    // The auth check, and its verdict. An empty string means the lane may run.
    //
    // It is a separate command because it has to be: reading the auth state from a config
    // file would describe a state that is not the one the request will use. Same scrub, same
    // spawn path, or the check lies.
    virtual std::wstring AuthCommandLine(const std::wstring& aExecutable) const = 0;
    virtual std::string AuthProblem(const ProcessResult& aResult) const = 0;
};

/// The dialect ///

// Takes an OpenAI chat/completions body apart. False when it is not one, and `aError` then
// says which part was missing.
bool ParseChatBody(const std::string& aBody, ChatRequest& aRequest, std::string& aError);

// The success shape. `aHaveUsage` false omits the usage block entirely rather than writing
// zeroes -- the mod prints "usage=absent" for a missing block, and a row of zeroes would let
// a request whose cost was never measured pass for a free one.
std::string MakeChatResponse(const std::string& aText, bool aHaveUsage, long long aPromptTokens,
                             long long aCompletionTokens, long long aCachedTokens);

// The failure shape, which is an OpenAI error body and nothing more exotic.
ChatReply Failure(int aStatus, const std::string& aMessage);

// The environment variables no CLI backend may inherit.
//
// The player's shell may be configured for their day job. An inherited ANTHROPIC_API_KEY
// does not fail -- it works, produces identical replies, and bills per token for what the
// subscription already covers, which is the opposite of what these lanes promise.
const std::vector<std::wstring>& ScrubbedVariables();
} // namespace ainpc
