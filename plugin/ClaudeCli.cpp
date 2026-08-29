// The Claude Code lane.
//
// ── WHY THE FLAGS ARE WHAT THEY ARE ─────────────────────────────────────────
//
// By default this CLI is a coding agent. It loads CLAUDE.md from the working directory and
// from the user's home, plus project settings, skills, plugins, hooks and MCP servers, and it
// carries a system prompt about editing code. Every one of those would bleed into what a
// Cyberpunk character says, and the failure is not a crash -- it is a fixer who starts
// talking about your repository.
//
// --safe-mode is the load-bearing one. It disables CLAUDE.md, skills, plugins, hooks, MCP
// servers, custom commands, agents and output styles, while leaving auth working normally.
//
// DO NOT SUBSTITUTE --bare. It disables more, and its own help states that authentication
// then becomes strictly ANTHROPIC_API_KEY and that OAuth is never read -- which defeats the
// entire reason this lane exists. The whole point is to use a subscription the player has
// already paid for.
//
// ── THE TOOL SET IS AN ALLOWLIST, AND THAT IS THE SECURITY BOUNDARY ─────────
//
// `--tools ""` states the complete set of built-in tools this session may use, and states it
// as empty. A character writes text; it has no business reading a file, running a command or
// reaching the network, and none of those tools exists in the session at all.
//
// It replaces a denylist, and the difference is the whole point: `--disallowed-tools` names
// what is forbidden, so a tool added by a future version of the CLI would be permitted by
// default -- silently, on a player's machine, in a build nobody rebuilt. An allowlist has the
// opposite failure mode. The denylist is kept below anyway, as a second line of defence: it costs
// nothing, and it still says no if a future version were to ignore the first flag.
//
// Measured 2026-08-24, same prompt, same model, prompt tokens including cache:
//
//     --disallowed-tools (the old set)   15691
//     --tools ""                          3600
//
// So the tool schemas were still in the prompt under the denylist. Closing the hole makes the
// request 4x smaller as a side effect, which is the rare case where the safe choice is also
// the cheap one.
//
// This set is carried over verbatim from tools/bridge/ai_npc_bridge.py, which ran it in
// production. The one thing that changed is where the system prompt goes: the bridge passed
// it as --system-prompt on the command line and had to guard its length, and this uses
// --system-prompt-file instead.

#include "ClaudeCli.hpp"

#include "Json.hpp"
#include "Process.hpp"
#include "Text.hpp"

namespace ainpc
{
const char* ClaudeCli::Name() const
{
    return "ClaudeCli";
}

std::wstring ClaudeCli::Executable(const Settings& aSettings) const
{
    return Locate(aSettings.claudePath, L"claude");
}

bool ClaudeCli::WantsSystemPromptFile() const
{
    return true;
}

std::wstring ClaudeCli::CommandLine(const std::wstring& aExecutable, const ChatRequest& aRequest,
                                    const std::wstring& aSystemPromptFile) const
{
    std::wstring line = QuoteArgument(aExecutable);

    line += L" -p";                          // non-interactive: print and exit
    line += L" --safe-mode";                 // no CLAUDE.md / skills / plugins / hooks / MCP
    line += L" --strict-mcp-config";         // ignore every MCP config on the machine
    line += L" --disable-slash-commands";    // no skills reachable via /name
    line += L" --no-session-persistence";    // nothing written to disk, nothing resumable
    line += L" --output-format json";

    if (!aRequest.model.empty())
    {
        line += L" --model ";
        line += QuoteArgument(Widen(aRequest.model));
    }

    if (!aSystemPromptFile.empty())
    {
        line += L" --system-prompt-file ";
        line += QuoteArgument(aSystemPromptFile);
    }

    // The allowlist: the complete set of built-in tools, and it is empty.
    line += L" --tools ";
    line += QuoteArgument(L"");

    // The denylist, kept as a second line of defence. See the header: it is redundant while the flag
    // above is honoured, and it is what still answers if one day it is not.
    line += L" --disallowed-tools ";
    line += QuoteArgument(L"Bash Read Write Edit MultiEdit Glob Grep WebFetch WebSearch Task "
                  L"TodoWrite NotebookEdit BashOutput KillShell SlashCommand ExitPlanMode AskUserQuestion");

    return line;
}

std::string ClaudeCli::StandardInput(const ChatRequest& aRequest) const
{
    // The user half only. The system half is the file above, and joining them here would be
    // the pre-concatenation the boundary contract forbids -- it would decide the instruction
    // hierarchy in the wrong layer.
    return aRequest.user;
}

ChatReply ClaudeCli::Interpret(const ProcessResult& aResult) const
{
    // The plugin refusing to spawn is not the OS failing to. First, because it is the more
    // precise sentence and it names the file the player has to edit.
    if (!aResult.refusal.empty())
    {
        return Failure(400, aResult.refusal);
    }
    if (!aResult.started)
    {
        return Failure(503, "claude could not be started - is Claude Code installed? Set claudeCliPath in "
                            "r6\\storages\\AiNpc\\settings.json if it is not on PATH");
    }
    if (aResult.timedOut)
    {
        return Failure(504, "claude did not answer in time and was stopped");
    }

    if (aResult.exitCode != 0)
    {
        std::string detail = LastLine(aResult.err);
        if (detail.empty())
        {
            detail = LastLine(aResult.out);
        }
        if (detail.empty())
        {
            detail = "claude exited with code " + std::to_string(aResult.exitCode);
        }
        return Failure(502, detail);
    }

    json::Value root;
    if (!json::Parse(aResult.out, root) || !root.IsObject())
    {
        // The single most useful thing to quote here is whatever it printed instead, because
        // it is usually a shell or installer message that names its own cause.
        std::string detail = LastLine(aResult.out);
        if (detail.empty())
        {
            detail = LastLine(aResult.err);
        }
        if (detail.empty())
        {
            detail = "claude returned nothing at all";
        }
        return Failure(502, "claude returned output that was not JSON: " + detail);
    }

    if (root.BoolAt("is_error"))
    {
        std::string detail = root.StringAt("result");
        if (detail.empty())
        {
            detail = "claude reported an error";
        }
        return Failure(502, detail);
    }

    const std::string text = root.StringAt("result");
    if (text.empty())
    {
        return Failure(502, "claude returned an empty result");
    }

    // Everything that was sent counts as prompt tokens -- fresh input, what was written to
    // cache, and what was read back from it -- because all three are input the provider
    // metered. The cached half is reported again on the side, where the mod keeps it as
    // prompt_tokens_details.cached_tokens: it is the one number that says a discount applied.
    const json::Value* usage = root.Find("usage");
    if (!usage || !usage->IsObject())
    {
        // No usage block means no usage block. The mod prints "usage=absent" for that, and a
        // row of zeroes here would let a request whose cost was never measured pass for a
        // free one.
        return {200, MakeChatResponse(text, false, 0, 0, 0)};
    }

    const long long cached = usage->IntAt("cache_read_input_tokens");
    const long long prompt = usage->IntAt("input_tokens") + usage->IntAt("cache_creation_input_tokens") + cached;
    const long long completion = usage->IntAt("output_tokens");
    return {200, MakeChatResponse(text, true, prompt, completion, cached)};
}

std::wstring ClaudeCli::AuthCommandLine(const std::wstring& aExecutable) const
{
    return QuoteArgument(aExecutable) + L" auth status --json";
}

std::string ClaudeCli::AuthProblem(const ProcessResult& aResult) const
{
    if (!aResult.refusal.empty())
    {
        return aResult.refusal;
    }
    if (!aResult.started)
    {
        return "claude could not be started - is Claude Code installed?";
    }
    if (aResult.timedOut)
    {
        return "claude auth status did not answer in time";
    }

    json::Value root;
    if (!json::Parse(aResult.out, root) || !root.IsObject())
    {
        // A check that cannot be read must not be treated as a pass. Silence here is how an
        // API key would slip through into a lane that promises a subscription.
        return "could not read the answer of `claude auth status --json`";
    }

    if (!root.BoolAt("loggedIn"))
    {
        return "not signed in to Claude - run `claude login` in a terminal, then try again";
    }

    // ── THE OBVIOUS CHECK DOES NOT WORK ──────────────────────────────────────
    //
    // Measured 2026-08-24 on Claude Code 2.1.241 with ANTHROPIC_API_KEY set: loggedIn is
    // still true and authMethod still says "claude.ai". Neither field discriminates. What
    // does is apiKeySource being absent AND subscriptionType being non-null, which is what a
    // clean environment returns.
    //
    // This matters because the failure is silent and expensive: a key satisfies the same CLI,
    // produces identical replies, and bills per token for what the subscription covers.
    const json::Value* keySource = root.Find("apiKeySource");
    if (keySource && keySource->kind == json::Kind::String && !keySource->text.empty())
    {
        return "this lane runs on your Claude subscription, but the CLI is using the API key in " +
               keySource->text +
               " and would bill you per message. Remove that variable, or switch to OpenRouter in Mod Settings";
    }

    const json::Value* subscription = root.Find("subscriptionType");
    if (!subscription || subscription->kind != json::Kind::String || subscription->text.empty())
    {
        return "the Claude CLI is signed in but reports no subscription - this lane needs one, or switch to "
               "OpenRouter in Mod Settings";
    }

    return "";
}
} // namespace ainpc
