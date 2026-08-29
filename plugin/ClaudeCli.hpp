#pragma once

#include "Transport.hpp"

namespace ainpc
{
// The Claude Code lane. See ClaudeCli.cpp for why each flag is there -- the isolation set is
// load-bearing, not decoration.
class ClaudeCli final : public ITransport
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
} // namespace ainpc
