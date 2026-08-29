#pragma once

#include "Transport.hpp"

namespace ainpc
{
// The Codex CLI lane. See CodexCli.cpp for why each flag is there, and for the two places
// where this backend cannot do what the Claude one does: Codex has no system prompt slot and
// no way to take its tools away.
class CodexCli final : public ITransport
{
public:
    const char* Name() const override;
    std::wstring Executable(const Settings& aSettings) const override;
    bool WantsSystemPromptFile() const override;
    std::wstring CommandLine(const std::wstring& aExecutable, const ChatRequest& aRequest,
                             const std::wstring& aSystemPromptFile) const override;
    std::string StandardInput(const ChatRequest& aRequest) const override;
    ChatReply Interpret(const ProcessResult& aResult) const override;
    std::wstring AuthCommandLine(const std::wstring& aExecutable) const override;
    std::string AuthProblem(const ProcessResult& aResult) const override;
};

// The sentence that folds the system block into Codex's single input, exposed so the offline
// suite asserts the exact text rather than a paraphrase of it. See StandardInput.
extern const char* const kCodexFraming;
} // namespace ainpc
