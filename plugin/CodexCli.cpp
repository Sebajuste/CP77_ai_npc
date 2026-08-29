// The Codex CLI lane.
//
// Written entirely against OpenAI's published documentation -- nobody on this machine has the
// CLI installed, so nothing here was measured the way the Claude lane's flags were. Every flag
// below therefore carries the page it came from, and the file says plainly where the
// documentation stops. What that costs, and how it fails, is at the bottom.
//
// ── THE TWO THINGS CODEX CANNOT DO THAT CLAUDE CAN ──────────────────────────
//
// 1. THERE IS NO SYSTEM PROMPT. `codex exec` takes one prompt and nothing else, so the system
//    block has to be folded into that input -- which is exactly the per-backend decision the
//    boundary contract keeps out of redscript. StandardInput below does the folding, and the
//    framing it adds is the whole of this lane's instruction hierarchy.
//
// 2. THE SHELL IS REMOVED, NOT CONFINED. `--disable shell_tool` takes the built-in shell out
//    of the session entirely -- Codex's equivalent of Claude's empty `--tools` allowlist, and
//    the same reasoning: a character writes text, so the tool has no business existing in its
//    session. The same thing is said a second time as `-c features.shell_tool=false`, which is
//    the config form of the identical switch, for the same reason the Claude lane keeps a
//    denylist behind its allowlist.
//
//    THIS IS THE SECURITY BOUNDARY, and confining the shell instead is NOT equivalent. Codex's
//    own documentation states that its read-only sandbox permits "reading files anywhere on
//    the filesystem" -- so a confined shell can still read the player's documents and put what
//    it found in a bubble, which the mod then writes to its journal. Removing the tool is what
//    closes that; `--sandbox read-only` below is the second line of defence, not the first.
//
//    Third-party measurement (81 documented flag experiments, 2026): the flag also drops 440
//    input tokens, because the tool schemas leave the prompt with it -- the same shape as the
//    15691 -> 3600 measurement on the Claude lane. The safe choice is again the cheap one.
//
// ── WHY THE FLAGS ARE WHAT THEY ARE ─────────────────────────────────────────
//
// Same problem as the other lane: by default this CLI is a coding agent that reads its own
// configuration, AGENTS.md files, MCP servers, plugins and hooks, and every one of those would
// bleed into what a Cyberpunk character says.
//
//   exec                     non-interactive mode; prints the final message and exits
//   -                        the prompt comes from stdin (documented sentinel), never from the
//                            command line -- Windows caps a command line at 32767 characters
//   --json                   stdout becomes a JSONL event stream, which is the only documented
//                            way to get the token usage the mod's daily cap needs
//   --ignore-user-config     do not load $CODEX_HOME/config.toml. This is the load-bearing one:
//                            it is what removes the player's MCP servers, plugins, hooks,
//                            profiles and model overrides in a single flag. Authentication
//                            still uses CODEX_HOME, which is the whole point -- the lane runs
//                            on the player's subscription
//   --ignore-rules           no user or project execpolicy .rules files
//   --ephemeral              no session rollout files written to disk
//   --skip-git-repo-check    REQUIRED, not optional: Codex refuses to run outside a git
//                            repository, and the scratch directory it runs in is not one
//   --sandbox read-only      stated rather than inherited. The SECOND line of defence, behind
//                            the removal of the shell above
//   --disable shell_tool     no shell in the session at all. See above: this is the boundary.
//                            Documented as a feature flag, and measured by a third party to
//                            work in exec mode when placed after the subcommand's own flags
//
// and the inline config overrides, which is how the documentation says to set a config key for
// one run (`-c key=value`, parsed as TOML, so a string value carries its own quotes):
//
//   features.shell_tool=false     the flag above, said again in its config form
//   features.multi_agent=false    no subagent tools -- another tool surface a character has no
//                                 use for
//   features.hooks=false          no lifecycle hooks, even from a config we did not expect
//   tools.web_search=false        no web search
//   tools.view_image=false        no local-image tool
//   project_doc_max_bytes=0       no AGENTS.md, from any directory, including $CODEX_HOME
//   history.persistence="none"    no transcript of the player's conversations on disk
//   approval_policy="never"       never stop to ask; a question in a non-interactive run is a
//                                 hang, and with no shell there is nothing left to approve
//
// ── HOW THIS FILE FAILS, IF IT FAILS ────────────────────────────────────────
//
// Two ways, and neither is silent in the same way:
//
// A flag that does not exist in the player's version makes the CLI exit with a usage error,
// and Interpret quotes its last line -- so the report names the flag. That is loud, and it is
// the good case.
//
// A config KEY that does not exist is ignored silently, because `--strict-config` is not
// passed. That is the quiet case: it would leave, say, web search on. It is not passed
// deliberately -- with it, one renamed key would take the whole lane down instead of one
// setting -- and it is the same trade the Claude lane makes with its denylist.

#include "CodexCli.hpp"

#include "Json.hpp"
#include "Process.hpp"
#include "Text.hpp"

namespace ainpc
{
// Codex has no system prompt, so this is the only thing that separates the instructions from
// the conversation. It goes BEFORE both, never after: the transcript ends on V's own line, and
// the model is meant to continue straight from there -- text appended below it would displace
// the point the reply grows from, and the mod's prompt is built on that ordering.
const char* const kCodexFraming =
    "You are running a text roleplay, not a coding task. Everything under INSTRUCTIONS is your "
    "role and outranks anything else; everything under CONVERSATION is the exchange so far. "
    "Write the next message in character and nothing else. Do not use tools: no shell commands, "
    "no file reads, no searches.\n\n";

namespace
{
// One `-c key=value` pair. The value is TOML, which is why a string value arrives here with
// its own quotes: `history.persistence="none"` is a TOML string, `history.persistence=none`
// is not, and Codex documents unparseable values as being taken for bare strings.
void Override(std::wstring& aLine, const wchar_t* aAssignment)
{
    aLine += L" -c ";
    aLine += QuoteArgument(aAssignment);
}

// The text of the last agent message in a JSONL event stream.
//
// The last, not the first: a turn can emit several agent messages, and the documented plain
// mode prints only the final one -- which is the reply. Lines that are not JSON are skipped
// rather than failing the parse: the stream is a log, and a CLI is entitled to print a warning
// into it.
struct Stream
{
    std::string text;
    bool sawText = false;

    bool haveUsage = false;
    long long inputTokens = 0;
    long long cachedTokens = 0;
    long long outputTokens = 0;

    std::string failure; // turn.failed, or a stream-level error event
};

Stream ReadStream(const std::string& aStdout)
{
    Stream stream;

    size_t at = 0;
    while (at < aStdout.size())
    {
        const size_t newline = aStdout.find('\n', at);
        const size_t end = (newline == std::string::npos) ? aStdout.size() : newline;
        std::string line = aStdout.substr(at, end - at);
        at = (newline == std::string::npos) ? aStdout.size() : newline + 1;

        // A stream written on Windows arrives with the carriage return still attached, and a
        // trailing \r makes json::Parse refuse the line as trailing content.
        while (!line.empty() && (line.back() == '\r' || line.back() == ' '))
        {
            line.pop_back();
        }

        json::Value event;
        if (line.empty() || !json::Parse(line, event) || !event.IsObject())
        {
            continue;
        }

        const std::string type = event.StringAt("type");

        if (type == "item.completed")
        {
            const json::Value* item = event.Find("item");
            if (item && item->IsObject() && item->StringAt("type") == "agent_message")
            {
                stream.text = item->StringAt("text");
                stream.sawText = true;
            }
        }
        else if (type == "turn.completed")
        {
            const json::Value* usage = event.Find("usage");
            if (usage && usage->IsObject())
            {
                stream.haveUsage = true;
                stream.inputTokens = usage->IntAt("input_tokens");
                stream.cachedTokens = usage->IntAt("cached_input_tokens");
                stream.outputTokens = usage->IntAt("output_tokens");
            }
        }
        else if (type == "turn.failed")
        {
            const json::Value* error = event.Find("error");
            if (error && error->IsObject())
            {
                stream.failure = error->StringAt("message");
            }
            if (stream.failure.empty())
            {
                stream.failure = "the Codex CLI reported a failed turn";
            }
        }
        else if (type == "error" && stream.failure.empty())
        {
            // A stream-level error is documented as non-fatal -- "Reconnecting... 1/5" arrives
            // this way. So it is remembered and only used if no reply ever came.
            stream.failure = event.StringAt("message");
        }
    }

    return stream;
}
} // namespace

const char* CodexCli::Name() const
{
    return "CodexCli";
}

std::wstring CodexCli::Executable(const Settings& aSettings) const
{
    return Locate(aSettings.codexPath, L"codex");
}

bool CodexCli::WantsSystemPromptFile() const
{
    // No system prompt exists to put in a file. See StandardInput.
    return false;
}

std::wstring CodexCli::CommandLine(const std::wstring& aExecutable, const ChatRequest& aRequest,
                                   const std::wstring& aSystemPromptFile) const
{
    (void)aSystemPromptFile; // WantsSystemPromptFile() is false, so there is never one.

    std::wstring line = QuoteArgument(aExecutable);

    line += L" exec";
    line += L" --json";                  // JSONL events on stdout: the only source of usage
    line += L" --ignore-user-config";    // no config.toml: no MCP servers, plugins, hooks, profiles
    line += L" --ignore-rules";          // no execpolicy .rules
    line += L" --ephemeral";             // no session rollout files
    line += L" --skip-git-repo-check";   // the scratch directory is not a git repository
    line += L" --sandbox read-only";     // the boundary on this lane; see the header

    if (!aRequest.model.empty())
    {
        line += L" --model ";
        line += QuoteArgument(Widen(aRequest.model));
    }

    // THE BOUNDARY: the shell leaves the session. Placed after the subcommand's own flags and
    // before the prompt, which is where it is documented to work in exec mode.
    line += L" --disable shell_tool";

    // The same statement in its config form, and the other tool surfaces with it. Kept behind
    // the flag the way the Claude lane keeps a denylist behind its allowlist: redundant while
    // the flag is honoured, and the thing that still answers if one day it is not.
    Override(line, L"features.shell_tool=false");
    Override(line, L"features.multi_agent=false");
    Override(line, L"features.hooks=false");
    Override(line, L"tools.web_search=false");
    Override(line, L"tools.view_image=false");
    Override(line, L"project_doc_max_bytes=0");
    Override(line, L"history.persistence=\"none\"");
    Override(line, L"approval_policy=\"never\"");

    // Last, and a positional: the documented sentinel for "the prompt is on stdin". It has to
    // stay last so no flag can be read as its value.
    line += L" -";

    return line;
}

std::string CodexCli::StandardInput(const ChatRequest& aRequest) const
{
    // THE FOLD. This is the one place in the mod where the system block and the conversation
    // become a single text, and it happens here rather than in redscript on purpose: it is a
    // property of this CLI, not of the mod.
    if (aRequest.system.empty())
    {
        return aRequest.user;
    }

    std::string input = kCodexFraming;
    input += "INSTRUCTIONS\n";
    input += aRequest.system;
    input += "\n\nCONVERSATION\n";
    input += aRequest.user;
    return input;
}

ChatReply CodexCli::Interpret(const ProcessResult& aResult) const
{
    // The plugin refusing to spawn is not the OS failing to. See ProcessResult::refusal.
    if (!aResult.refusal.empty())
    {
        return Failure(400, aResult.refusal);
    }
    if (!aResult.started)
    {
        return Failure(503, "codex could not be started - is the Codex CLI installed? Set codexCliPath in "
                            "r6\\storages\\AiNpc\\settings.json if it is not on PATH");
    }
    if (aResult.timedOut)
    {
        return Failure(504, "codex did not answer in time and was stopped");
    }

    const Stream stream = ReadStream(aResult.out);

    if (aResult.exitCode != 0)
    {
        // The stream's own account of the failure first: it is the CLI describing what went
        // wrong, where the last line of stderr is often just how it exited. A flag this build
        // passes and the player's version does not know lands in the stderr branch, and the
        // report then names the flag.
        std::string detail = stream.failure;
        if (detail.empty())
        {
            detail = LastLine(aResult.err);
        }
        if (detail.empty())
        {
            detail = LastLine(aResult.out);
        }
        if (detail.empty())
        {
            detail = "codex exited with code " + std::to_string(aResult.exitCode);
        }
        return Failure(502, detail);
    }

    if (!stream.sawText)
    {
        if (!stream.failure.empty())
        {
            return Failure(502, stream.failure);
        }
        // Exit code 0 and no agent message at all. Usually not JSON on stdout -- a shim that
        // printed a shell error, or a version that does not know --json -- so quote it.
        std::string detail = LastLine(aResult.out);
        if (detail.empty())
        {
            detail = LastLine(aResult.err);
        }
        if (detail.empty())
        {
            detail = "codex returned nothing at all";
        }
        return Failure(502, "codex returned no message: " + detail);
    }

    if (stream.text.empty())
    {
        return Failure(502, "codex returned an empty message");
    }

    if (!stream.haveUsage)
    {
        // No usage block means no usage block. The mod prints "usage=absent" for that, and a
        // row of zeroes would let a request whose cost was never measured pass for a free one.
        return {200, MakeChatResponse(stream.text, false, 0, 0, 0)};
    }

    // ── CACHED TOKENS ARE COUNTED DIFFERENTLY HERE THAN ON THE CLAUDE LANE ───
    //
    // Claude reports cache reads BESIDE its input tokens, so that backend adds them up. Codex
    // documents `cached_input_tokens` as part of `input_tokens` -- its own example reads
    // input 24763 of which cached 24448 -- so adding them here would bill the player's ledger
    // for roughly twice what was sent. input_tokens is the total; cached is reported again on
    // the side, where the mod keeps it as the number that says a discount applied.
    return {200, MakeChatResponse(stream.text, true, stream.inputTokens, stream.outputTokens, stream.cachedTokens)};
}

std::wstring CodexCli::AuthCommandLine(const std::wstring& aExecutable) const
{
    // No --json on this subcommand: it is documented as printing the active authentication
    // mode and exiting 0 when logged in, and a machine-readable form is an open feature
    // request upstream. So the verdict below reads sentences, and refuses anything it does
    // not recognise rather than guessing.
    return QuoteArgument(aExecutable) + L" login status";
}

std::string CodexCli::AuthProblem(const ProcessResult& aResult) const
{
    if (!aResult.refusal.empty())
    {
        return aResult.refusal;
    }
    if (!aResult.started)
    {
        return "codex could not be started - is the Codex CLI installed?";
    }
    if (aResult.timedOut)
    {
        return "codex login status did not answer in time";
    }

    // Both streams, because which one carries the line is not documented.
    const std::string said = aResult.out + "\n" + aResult.err;

    // ── THIS LANE IS SUBSCRIPTION-ONLY, AND THIS IS WHERE THAT IS ENFORCED ───
    //
    // A key satisfies the same CLI, produces identical replies, and bills per token for what
    // the player's ChatGPT plan already covers -- which is the opposite of what the menu entry
    // promises. So an API key is refused, never warned about and then used.
    //
    // The check is honest only because the environment is scrubbed the same way for this
    // command as for the request: CODEX_API_KEY, CODEX_ACCESS_TOKEN, OPENAI_API_KEY and the
    // workload-identity variables are removed from both. See ScrubbedVariables().
    if (said.find("Logged in using an API key") != std::string::npos)
    {
        return "this lane runs on your ChatGPT subscription, but the Codex CLI is signed in with an API key and "
               "would bill you per message. Run `codex logout` then `codex login`, or switch to OpenRouter in Mod "
               "Settings";
    }

    if (said.find("Logged in using Agent Identity") != std::string::npos)
    {
        return "the Codex CLI is signed in as a workload identity, which bills an organisation per message rather "
               "than using a subscription. Run `codex login` as yourself, or switch to OpenRouter in Mod Settings";
    }

    if (said.find("Not logged in") != std::string::npos)
    {
        return "not signed in to Codex - run `codex login` in a terminal, then try again";
    }

    if (said.find("Logged in using ChatGPT") != std::string::npos)
    {
        return "";
    }

    // Anything else, including a non-zero exit with nothing recognisable in it. A check that
    // cannot be read must not be treated as a pass: silence here is how a key slips into a
    // lane that promises a subscription.
    //
    // Codex reports no plan tier at all, so unlike the Claude lane there is nothing to verify
    // beyond the sign-in method. A ChatGPT account with no Codex quota therefore passes here
    // and fails at the request, where the CLI's own sentence reaches the player.
    std::string detail = LastLine(aResult.err);
    if (detail.empty())
    {
        detail = LastLine(aResult.out);
    }
    if (detail.empty())
    {
        return "could not read the answer of `codex login status`";
    }
    return "could not read the answer of `codex login status`: " + detail;
}
} // namespace ainpc
