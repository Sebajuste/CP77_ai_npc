// The offline suite for the plugin.
//
// tools\compile-check.ps1 does not see C++, and that must not become a hole: everything on
// this side of the boundary would otherwise be checked only by launching the game, which is
// the one thing an agent cannot do.
//
// What is covered is the whole of what a backend decides: the command line it builds, the
// stdin it feeds, and what it makes of the four ways a CLI can answer -- a reply, a reply
// with usage, a refusal, and garbage. Each is a fixture, so none of it needs `claude`
// installed, a network, or a subscription.
//
// The streaming lane is here for the same reason and more of it: an SSE stream has three ways
// of going wrong that a launched game shows as one symptom -- "the character said nothing" --
// and every one of them is a fixture below.
//
// What is NOT covered, and cannot be from here: the RTTI registration, the callback reaching
// script, UTF-8 arriving intact in a bubble, and the socket itself. Those are the launch
// checklist.
//
// Build and run: powershell -File plugin\test\run.ps1

#include "../Audio.hpp"
#include "../Speech.hpp"
#include "../ClaudeCli.hpp"
#include "../CodexCli.hpp"
#include "../Json.hpp"
#include "../Process.hpp"
#include "../Registry.hpp"
#include "../Stream.hpp"
#include "../Transport.hpp"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

namespace
{
int g_failures = 0;
int g_checks = 0;

void Check(const char* aName, bool aCondition)
{
    ++g_checks;
    if (!aCondition)
    {
        ++g_failures;
        std::printf("  FAIL  %s\n", aName);
    }
}

void EqualString(const char* aName, const std::string& aActual, const std::string& aExpected)
{
    ++g_checks;
    if (aActual != aExpected)
    {
        ++g_failures;
        std::printf("  FAIL  %s\n        expected: %s\n        actual:   %s\n", aName, aExpected.c_str(),
                    aActual.c_str());
    }
}

bool Contains(const std::wstring& aHaystack, const wchar_t* aNeedle)
{
    return aHaystack.find(aNeedle) != std::wstring::npos;
}

bool Contains(const std::string& aHaystack, const char* aNeedle)
{
    return aHaystack.find(aNeedle) != std::string::npos;
}

// The reply text out of an OpenAI-shaped response, so the assertions read what the mod would.
std::string ReplyText(const std::string& aBody)
{
    ainpc::json::Value root;
    if (!ainpc::json::Parse(aBody, root))
    {
        return "<not json>";
    }
    const ainpc::json::Value* choices = root.Find("choices");
    if (!choices || !choices->IsArray() || choices->items.empty())
    {
        return "<no choices>";
    }
    const ainpc::json::Value* message = choices->items[0].Find("message");
    return message ? message->StringAt("content", "<no content>") : "<no message>";
}

std::string ErrorMessage(const std::string& aBody)
{
    ainpc::json::Value root;
    if (!ainpc::json::Parse(aBody, root))
    {
        return "<not json>";
    }
    const ainpc::json::Value* error = root.Find("error");
    return error ? error->StringAt("message", "<no message>") : "<no error>";
}

/// The dialect ///

void TestChatBody()
{
    std::printf("chat body\n");

    ainpc::ChatRequest request;
    std::string error;
    const bool ok = ainpc::ParseChatBody(
        R"({"model":"sonnet","messages":[{"role":"system","content":"You are Panam."},)"
        R"({"role":"user","content":"hey"}]})",
        request, error);

    Check("a chat body parses", ok);
    EqualString("the model comes through", request.model, "sonnet");
    EqualString("the system half is kept apart", request.system, "You are Panam.");
    EqualString("the user half is kept apart", request.user, "hey");

    // The whole point of keeping them apart: the backend decides where the system block goes,
    // and that decision settles the instruction hierarchy the safe-for-work tier rests on.
    Check("the two halves are not joined", request.system != request.user);

    ainpc::ChatRequest empty;
    Check("a body with no user message is refused",
          !ainpc::ParseChatBody(R"({"messages":[{"role":"system","content":"x"}]})", empty, error));
    Check("and it says why", Contains(error, "user"));
    Check("a body that is not JSON is refused", !ainpc::ParseChatBody("claude: not found", empty, error));

    // Accents survive the round trip. This is the bug class that is invisible until a reply
    // reaches a bubble, so it is asserted at every boundary it crosses.
    ainpc::ChatRequest accented;
    Check("an accented body parses",
          ainpc::ParseChatBody(R"({"messages":[{"role":"user","content":"o\u00f9 es-tu ?"}]})", accented, error));
    EqualString("an accented body keeps its accents", accented.user, "o\xC3\xB9 es-tu ?");
}

void TestResponseShape()
{
    std::printf("response shape\n");

    const std::string withUsage = ainpc::MakeChatResponse("OK", true, 4504, 312, 4000);
    EqualString("the text survives", ReplyText(withUsage), "OK");
    Check("usage is carried", Contains(withUsage, "\"prompt_tokens\":4504"));
    Check("the total is the sum", Contains(withUsage, "\"total_tokens\":4816"));
    Check("the cached half is reported", Contains(withUsage, "\"cached_tokens\":4000"));
    Check("a complete reply is a stop", Contains(withUsage, "\"finish_reason\":\"stop\""));

    // No usage means no usage block, not a row of zeroes: the mod prints "usage=absent" for
    // the first and would read the second as a request that cost nothing.
    const std::string without = ainpc::MakeChatResponse("OK", false, 0, 0, 0);
    Check("a missing usage block is absent, not zero", !Contains(without, "usage"));

    const ainpc::ChatReply failure = ainpc::Failure(401, "not signed in");
    Check("a failure carries its status", failure.status == 401);
    EqualString("a failure carries its sentence", ErrorMessage(failure.body), "not signed in");

    const std::string quoted = ainpc::MakeChatResponse("say \"hi\"\nplease", true, 1, 1, 0);
    EqualString("quotes and newlines survive", ReplyText(quoted), "say \"hi\"\nplease");
}

/// The Claude backend ///

void TestClaudeCommandLine()
{
    std::printf("claude command line\n");

    const ainpc::ClaudeCli claude;
    ainpc::ChatRequest request;
    request.model = "sonnet";
    request.system = "You are Panam.";
    request.user = "hey";

    const std::wstring line = claude.CommandLine(L"C:\\Program Files\\claude.exe", request, L"C:\\tmp\\system-1.txt");

    // The isolation set is load-bearing: without it the CLI is a coding agent that reads
    // CLAUDE.md, skills, plugins and MCP servers, and a fixer starts discussing your
    // repository. Each of these is asserted because each has been individually necessary.
    Check("print and exit", Contains(line, L" -p"));
    Check("safe mode", Contains(line, L"--safe-mode"));
    Check("no MCP config", Contains(line, L"--strict-mcp-config"));
    Check("no slash commands", Contains(line, L"--disable-slash-commands"));
    Check("nothing persisted", Contains(line, L"--no-session-persistence"));
    Check("json output", Contains(line, L"--output-format json"));

    // THE SECURITY BOUNDARY. An allowlist naming no tool at all, so a tool added by a future
    // version of the CLI cannot appear in a character's session by default. Measured
    // 2026-08-24: it also cuts the prompt from 15691 tokens to 3600, because the schemas were
    // still being sent under the denylist that came before it.
    Check("the tool set is an empty allowlist", Contains(line, L"--tools \"\""));
    Check("the denylist is kept as a second line of defence", Contains(line, L"--disallowed-tools"));
    Check("the model is passed", Contains(line, L"--model \"sonnet\""));

    // --bare is NOT --safe-mode. Its own help says auth becomes strictly ANTHROPIC_API_KEY
    // and OAuth is never read, which defeats the whole reason this lane exists.
    Check("--bare is never used", !Contains(line, L"--bare"));

    // The system prompt travels as a file, which is what removes the 32767-character command
    // line ceiling the old Python bridge had to guard against by hand.
    Check("the system prompt is a file", Contains(line, L"--system-prompt-file"));
    Check("the system prompt is not an argument", !Contains(line, L"You are Panam."));

    const std::wstring quoted = claude.CommandLine(L"C:\\Program Files\\claude.exe", request, L"");
    Check("a path with a space is quoted", Contains(quoted, L"\"C:\\Program Files\\claude.exe\""));
    Check("no file, no flag", !Contains(quoted, L"--system-prompt-file"));

    // stdin carries the user half and only the user half.
    EqualString("stdin is the user message", claude.StandardInput(request), "hey");
}

void TestClaudeReplies()
{
    std::printf("claude replies\n");

    const ainpc::ClaudeCli claude;

    // A normal reply.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = R"({"result":"Yeah, I'm around.","is_error":false})";
        const ainpc::ChatReply reply = claude.Interpret(result);
        Check("a normal reply is a 200", reply.status == 200);
        EqualString("its text comes through", ReplyText(reply.body), "Yeah, I'm around.");
        Check("no usage reported means none written", !Contains(reply.body, "usage"));
    }

    // A reply with usage. All three input kinds count as prompt tokens, because all three
    // are input the provider metered; the cached half is reported again on the side.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = R"({"result":"OK","usage":{"input_tokens":100,"cache_creation_input_tokens":50,)"
                     R"("cache_read_input_tokens":400,"output_tokens":12}})";
        const ainpc::ChatReply reply = claude.Interpret(result);
        Check("usage is forwarded", Contains(reply.body, "\"prompt_tokens\":550"));
        Check("the completion is forwarded", Contains(reply.body, "\"completion_tokens\":12"));
        Check("the cached half is kept", Contains(reply.body, "\"cached_tokens\":400"));
    }

    // An accented reply, arriving escaped as the CLI may well send it.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = R"({"result":"T'es o\u00f9 ?"})";
        const ainpc::ChatReply reply = claude.Interpret(result);
        EqualString("an escaped accent is decoded to UTF-8", ReplyText(reply.body), "T'es o\xC3\xB9 ?");
    }

    // The executable was never started.
    {
        ainpc::ProcessResult result;
        result.started = false;
        const ainpc::ChatReply reply = claude.Interpret(result);
        Check("a missing executable is a 503", reply.status == 503);
        Check("and it names the setting to fix", Contains(ErrorMessage(reply.body), "claudeCliPath"));
    }

    // It ran too long. A different gesture for the player than any other failure, which is
    // the whole reason the errors are typed.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.timedOut = true;
        const ainpc::ChatReply reply = claude.Interpret(result);
        Check("a timeout is a 504", reply.status == 504);
        Check("and it says so", Contains(ErrorMessage(reply.body), "in time"));
    }

    // It refused, and the last line of stderr is the useful one.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.exitCode = 1;
        result.err = "some stack trace\nInvalid API key - please run /login";
        const ainpc::ChatReply reply = claude.Interpret(result);
        Check("a non-zero exit is a 502", reply.status == 502);
        EqualString("the last line is quoted", ErrorMessage(reply.body), "Invalid API key - please run /login");
    }

    // Garbage on stdout: a shim that printed a shell error instead of JSON.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "'claude' is not recognized as an internal or external command";
        const ainpc::ChatReply reply = claude.Interpret(result);
        Check("garbage is a 502", reply.status == 502);
        Check("and the garbage itself is quoted", Contains(ErrorMessage(reply.body), "not recognized"));
    }

    // The CLI's own error flag, which arrives with exit code 0.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = R"({"is_error":true,"result":"Credit balance is too low"})";
        const ainpc::ChatReply reply = claude.Interpret(result);
        Check("a reported error is a 502", reply.status == 502);
        EqualString("its own words are used", ErrorMessage(reply.body), "Credit balance is too low");
    }

    // A 200 with nothing in it is not a reply.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = R"({"result":""})";
        Check("an empty result is a failure", claude.Interpret(result).status == 502);
    }
}

void TestClaudeAuth()
{
    std::printf("claude auth\n");

    const ainpc::ClaudeCli claude;

    // ── THE MEASUREMENT THIS WHOLE CHECK EXISTS FOR ──────────────────────────
    //
    // 2026-08-24, Claude Code 2.1.241, with ANTHROPIC_API_KEY set: loggedIn is still true and
    // authMethod still says "claude.ai". Neither field discriminates. An implementation that
    // trusted either would let a key bill the player per token on a lane whose menu entry
    // promises their subscription covers it.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = R"({"loggedIn":true,"authMethod":"claude.ai","apiKeySource":"ANTHROPIC_API_KEY",)"
                     R"("subscriptionType":null})";
        const std::string problem = claude.AuthProblem(result);
        Check("an API key is refused even when loggedIn is true", !problem.empty());
        Check("and the variable is named", Contains(problem, "ANTHROPIC_API_KEY"));
    }

    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = R"({"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"max"})";
        EqualString("a clean subscription passes", claude.AuthProblem(result), "");
    }

    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = R"({"loggedIn":false})";
        Check("not signed in is refused", Contains(claude.AuthProblem(result), "claude login"));
    }

    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = R"({"loggedIn":true,"subscriptionType":null})";
        Check("signed in with no subscription is refused", !claude.AuthProblem(result).empty());
    }

    // A check that cannot be read must never pass. Silence here is how a key slips through.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "who knows";
        Check("an unreadable check is refused", !claude.AuthProblem(result).empty());
    }
}

/// The Codex backend ///
//
// Nobody on this machine has the Codex CLI, so every assertion below is against OpenAI's
// published documentation rather than against a measurement -- which is exactly why they are
// written down. A fixture that encodes what the documentation says is what turns "the docs
// changed" into a failing test instead of a lane that stopped answering.

void TestCodexCommandLine()
{
    std::printf("codex command line\n");

    const ainpc::CodexCli codex;
    ainpc::ChatRequest request;
    request.model = "gpt-5.6-terra";
    request.system = "You are Panam.";
    request.user = "V: hey";

    // The system-prompt file argument is passed empty on purpose: this lane never asks for
    // one, and a backend that quietly used it anyway would be folding the block twice.
    const std::wstring line = codex.CommandLine(L"C:\\Program Files\\codex.exe", request, L"");

    Check("non-interactive mode", Contains(line, L" exec"));
    Check("the event stream, which is the only source of usage", Contains(line, L"--json"));

    // The load-bearing one: it is what removes the player's MCP servers, plugins, hooks and
    // profiles in a single documented flag, while leaving authentication on CODEX_HOME.
    Check("no user config", Contains(line, L"--ignore-user-config"));
    Check("no execpolicy rules", Contains(line, L"--ignore-rules"));
    Check("nothing persisted", Contains(line, L"--ephemeral"));

    // REQUIRED, not tidy: Codex refuses to run outside a git repository, and the scratch
    // directory it is given is not one. Without this the lane never answers at all.
    Check("the git repository check is skipped", Contains(line, L"--skip-git-repo-check"));

    // ── THE SECURITY BOUNDARY ON THIS LANE ───────────────────────────────────
    //
    // The shell is REMOVED, not confined, and the difference is not academic: Codex documents
    // its read-only sandbox as permitting "reading files anywhere on the filesystem", so a
    // confined shell can still read the player's documents and put them in a bubble -- which
    // the mod writes to its journal. Only taking the tool away closes that.
    Check("the shell is removed", Contains(line, L"--disable shell_tool"));
    Check("and said again in config form", Contains(line, L"-c \"features.shell_tool=false\""));
    Check("no subagent tools", Contains(line, L"-c \"features.multi_agent=false\""));
    Check("no lifecycle hooks", Contains(line, L"-c \"features.hooks=false\""));

    // Never the opposite of the flag above. An --enable of the same feature further along the
    // line would win, and nothing else in this file would look wrong.
    Check("the shell is never enabled", !Contains(line, L"--enable"));
    Check("the shell is never switched back on", !Contains(line, L"shell_tool=true"));

    // The second line of defence, behind the removal rather than in front of it.
    Check("the sandbox is read-only", Contains(line, L"--sandbox read-only"));
    Check("the sandbox is never opened up", !Contains(line, L"workspace-write"));
    Check("nothing is ever bypassed", !Contains(line, L"--dangerously-bypass"));
    Check("--yolo is never used", !Contains(line, L"--yolo"));

    // The config overrides, in the documented `-c key=value` form where the value is TOML --
    // so a string value carries its own quotes and a boolean does not.
    Check("no web search", Contains(line, L"-c \"tools.web_search=false\""));
    Check("no image tool", Contains(line, L"-c \"tools.view_image=false\""));
    Check("no AGENTS.md", Contains(line, L"-c \"project_doc_max_bytes=0\""));
    Check("no transcript on disk", Contains(line, L"-c \"history.persistence=\\\"none\\\"\""));
    Check("never stops to ask", Contains(line, L"-c \"approval_policy=\\\"never\\\"\""));

    Check("the model is passed", Contains(line, L"--model \"gpt-5.6-terra\""));

    // The prompt is on stdin, and the sentinel that says so has to be last: a flag after it
    // would be read as its value.
    Check("the prompt comes from stdin", line.size() > 2 && line.substr(line.size() - 2) == L" -");
    Check("the prompt is not an argument", !Contains(line, L"You are Panam."));
    Check("the transcript is not an argument", !Contains(line, L"hey"));

    ainpc::ChatRequest noModel;
    noModel.user = "hey";
    Check("no model, no flag", !Contains(codex.CommandLine(L"codex.exe", noModel, L""), L"--model"));
    Check("a path with a space is quoted", Contains(line, L"\"C:\\Program Files\\codex.exe\""));
}

void TestCodexInput()
{
    std::printf("codex input\n");

    const ainpc::CodexCli codex;

    // Codex has no system prompt at all, so this backend must not ask for a file: the block
    // has nowhere to go but the input.
    Check("codex wants no system prompt file", !codex.WantsSystemPromptFile());

    ainpc::ChatRequest request;
    request.system = "<system>You are Panam.</system>";
    request.user = "Panam: yeah?\nV: t'es ou ?";

    const std::string input = codex.StandardInput(request);

    Check("the system block is in the input", Contains(input, "You are Panam."));
    Check("the conversation is in the input", Contains(input, "V: t'es ou ?"));
    Check("the two halves are labelled", Contains(input, "INSTRUCTIONS") && Contains(input, "CONVERSATION"));
    Check("the instructions come first",
          input.find("You are Panam.") < input.find("V: t'es ou ?"));

    // The framing goes BEFORE both. The mod's transcript ends on V's own line and the reply is
    // meant to continue straight from it, so anything appended below would displace the point
    // the answer grows from -- which is the ordering the prompt is built on.
    Check("the framing is at the very top", input.rfind(ainpc::kCodexFraming, 0) == 0);
    Check("nothing follows the conversation",
          input.size() > request.user.size() &&
              input.compare(input.size() - request.user.size(), request.user.size(), request.user) == 0);

    // Accents reach the CLI as the UTF-8 bytes the mod built, never re-encoded.
    ainpc::ChatRequest accented;
    accented.system = "Parle francais.";
    accented.user = "o\xC3\xB9 es-tu ?";
    Check("accents survive the fold", Contains(codex.StandardInput(accented), "o\xC3\xB9 es-tu ?"));

    // A request with no system half is not framed at all: there would be nothing to separate.
    ainpc::ChatRequest bare;
    bare.user = "hey";
    EqualString("no system block, no framing", codex.StandardInput(bare), "hey");
}

void TestCodexReplies()
{
    std::printf("codex replies\n");

    const ainpc::CodexCli codex;

    // A normal turn, in the documented JSONL shape.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "{\"type\":\"thread.started\",\"thread_id\":\"0199a213\"}\n"
                     "{\"type\":\"turn.started\"}\n"
                     "{\"type\":\"item.completed\",\"item\":{\"id\":\"item_1\",\"type\":\"reasoning\","
                     "\"text\":\"thinking\"}}\n"
                     "{\"type\":\"item.completed\",\"item\":{\"id\":\"item_2\",\"type\":\"agent_message\","
                     "\"text\":\"Yeah, I'm around.\"}}\n"
                     "{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":24763,"
                     "\"cached_input_tokens\":24448,\"output_tokens\":122,\"reasoning_output_tokens\":0}}\n";
        const ainpc::ChatReply reply = codex.Interpret(result);
        Check("a normal reply is a 200", reply.status == 200);
        EqualString("its text comes through", ReplyText(reply.body), "Yeah, I'm around.");
        Check("the reasoning item is not the reply", !Contains(reply.body, "thinking"));

        // ── THE ONE PLACE THE TWO LANES COUNT DIFFERENTLY ────────────────────
        //
        // Codex documents cached_input_tokens as PART OF input_tokens (its own example: 24763
        // of which 24448 cached). Claude reports its cache reads beside the input, so that
        // backend adds them. Adding them here would bill the player's daily ledger for twice
        // what was sent.
        Check("input tokens are the total, not a half", Contains(reply.body, "\"prompt_tokens\":24763"));
        Check("the cached half is reported on the side", Contains(reply.body, "\"cached_tokens\":24448"));
        Check("the completion is forwarded", Contains(reply.body, "\"completion_tokens\":122"));
        Check("the total is the sum of the two", Contains(reply.body, "\"total_tokens\":24885"));
    }

    // Several agent messages in one turn: the last is the reply, as in the CLI's own plain
    // mode, which prints only the final message.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"one moment\"}}\n"
                     "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"here you go\"}}\n"
                     "{\"type\":\"turn.completed\"}\n";
        EqualString("the last agent message wins", ReplyText(codex.Interpret(result).body), "here you go");
    }

    // Windows line endings, and a line of noise the CLI printed into its own stream. Neither
    // may take the reply down with it.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "not json at all\r\n"
                     "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"T'es o\\u00f9 ?\"}}\r\n";
        const ainpc::ChatReply reply = codex.Interpret(result);
        Check("a CRLF stream still parses", reply.status == 200);
        EqualString("an escaped accent is decoded to UTF-8", ReplyText(reply.body), "T'es o\xC3\xB9 ?");
    }

    // No usage block means no usage block, not a row of zeroes.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"OK\"}}\n";
        Check("a missing usage block is absent", !Contains(codex.Interpret(result).body, "usage"));
    }

    // The executable was never started.
    {
        ainpc::ProcessResult result;
        result.started = false;
        const ainpc::ChatReply reply = codex.Interpret(result);
        Check("a missing executable is a 503", reply.status == 503);
        Check("and it names the setting to fix", Contains(ErrorMessage(reply.body), "codexCliPath"));
    }

    // It ran too long.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.timedOut = true;
        const ainpc::ChatReply reply = codex.Interpret(result);
        Check("a timeout is a 504", reply.status == 504);
        Check("and it says so", Contains(ErrorMessage(reply.body), "in time"));
    }

    // The turn failed, and the stream said why. Its own words beat the last line of stderr.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.exitCode = 1;
        result.out = "{\"type\":\"turn.failed\",\"error\":{\"message\":\"You've hit your usage limit.\"}}\n";
        result.err = "Error: exiting";
        const ainpc::ChatReply reply = codex.Interpret(result);
        Check("a failed turn is a 502", reply.status == 502);
        EqualString("the stream's own words are used", ErrorMessage(reply.body), "You've hit your usage limit.");
    }

    // A flag this build passes and the player's version does not know. This is the loud
    // failure the header describes, and the report has to name the flag.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.exitCode = 2;
        result.err = "error: unexpected argument '--ephemeral' found";
        const ainpc::ChatReply reply = codex.Interpret(result);
        Check("an unknown flag is a 502", reply.status == 502);
        Check("and the flag is named", Contains(ErrorMessage(reply.body), "--ephemeral"));
    }

    // Garbage on stdout with a clean exit: a shim, or a version that does not know --json.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "'codex' is not recognized as an internal or external command";
        const ainpc::ChatReply reply = codex.Interpret(result);
        Check("garbage is a 502", reply.status == 502);
        Check("and the garbage itself is quoted", Contains(ErrorMessage(reply.body), "not recognized"));
    }

    // A stream that only ever reported a transient error, and no message.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "{\"type\":\"error\",\"message\":\"Reconnecting... 5/5\"}\n";
        const ainpc::ChatReply reply = codex.Interpret(result);
        Check("an error with no reply is a 502", reply.status == 502);
        Check("and it is quoted", Contains(ErrorMessage(reply.body), "Reconnecting"));
    }

    // An empty agent message is not a reply.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"\"}}\n";
        Check("an empty message is a failure", codex.Interpret(result).status == 502);
    }
}

void TestCodexAuth()
{
    std::printf("codex auth\n");

    const ainpc::CodexCli codex;

    // `codex login status` has no --json: it is documented as printing the active
    // authentication mode, and a machine-readable form is an open request upstream. So the
    // verdict reads sentences -- and refuses everything it does not recognise.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "Logged in using ChatGPT\n";
        EqualString("a ChatGPT sign-in passes", codex.AuthProblem(result), "");
    }

    // THE REASON THIS CHECK EXISTS. A key satisfies the same CLI and produces identical
    // replies, and bills per message for what the subscription already covers -- which is the
    // opposite of what the menu entry promises.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "Logged in using an API key - sk-proj-***00000\n";
        const std::string problem = codex.AuthProblem(result);
        Check("an API key is refused", !problem.empty());
        Check("and the way out is named", Contains(problem, "codex login"));
    }

    // A workload identity bills an organisation per message. Same refusal, different sentence.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "Logged in using Agent Identity\n";
        Check("a workload identity is refused", !codex.AuthProblem(result).empty());
    }

    {
        ainpc::ProcessResult result;
        result.started = true;
        result.exitCode = 1;
        result.out = "Not logged in\n";
        Check("not signed in is refused", Contains(codex.AuthProblem(result), "codex login"));
    }

    // A check that cannot be read must never pass. Silence here is how a key slips through.
    {
        ainpc::ProcessResult result;
        result.started = true;
        result.out = "who knows";
        Check("an unreadable check is refused", !codex.AuthProblem(result).empty());
    }

    {
        ainpc::ProcessResult result;
        result.started = false;
        Check("a missing executable is refused", !codex.AuthProblem(result).empty());
    }

    Check("the check runs the documented subcommand",
          Contains(codex.AuthCommandLine(L"codex.exe"), L"login status"));
}

/// The one place two parsers read the same line ///

void TestShimRefusal()
{
    std::printf("shim refusal\n");

    // A .cmd shim is what the npm installer of both CLIs ships, and it cannot be run by
    // CreateProcess: it goes through cmd.exe. cmd does NOT understand the \" that
    // QuoteArgument produces for CommandLineToArgvW -- it reads a plain quote, closes the
    // quoted region, and what follows lands in cmd's own grammar where & starts a command.
    //
    // So this fixture is a settings.json value that has broken out of its quotes. Nothing is
    // spawned: the guard returns before CreateProcess, which is why this runs offline.
    const std::wstring hostile =
        L"\"C:\\nowhere\\codex.cmd\" exec --model \"x\\\" & calc & rem \" -";
    const ainpc::ProcessResult refused =
        ainpc::RunCapture(L"C:\\nowhere\\codex.cmd", hostile, L"", "", 1000, nullptr, {});

    Check("a quote that escaped its argument is refused", !refused.refusal.empty());
    Check("and nothing was started", !refused.started);
    Check("and the file to fix is named", Contains(refused.refusal, "settings.json"));

    // The same line handed to a real executable is NOT refused: CommandLineToArgvW reads \"
    // correctly, and only cmd does not. The guard belongs to the shim path alone, or it would
    // be forbidding something that works.
    const ainpc::ProcessResult notRefused =
        ainpc::RunCapture(L"C:\\nowhere\\codex.exe", hostile, L"", "", 1000, nullptr, {});
    Check("an .exe is not held to cmd's grammar", notRefused.refusal.empty());

    // An ordinary line through the shim is not refused either.
    const ainpc::ProcessResult ordinary = ainpc::RunCapture(
        L"C:\\nowhere\\codex.cmd", L"\"C:\\nowhere\\codex.cmd\" exec --model \"gpt-5.6-terra\" -", L"", "", 1000,
        nullptr, {});
    Check("an ordinary shim call is allowed through", ordinary.refusal.empty());

    // Both backends report it as what it is. A refusal that arrived as "is it installed?"
    // would send the player to reinstall a CLI that is sitting right there.
    ainpc::ProcessResult carried;
    carried.refusal = "a value in settings.json contains a quote character";

    const ainpc::ClaudeCli claude;
    const ainpc::CodexCli codex;
    Check("claude reports a refusal as a 400", claude.Interpret(carried).status == 400);
    Check("codex reports a refusal as a 400", codex.Interpret(carried).status == 400);
    EqualString("and quotes it", ErrorMessage(codex.Interpret(carried).body), carried.refusal);
    Check("it is not reported as a missing executable",
          !Contains(ErrorMessage(claude.Interpret(carried).body), "installed"));

    // And the auth check refuses on it too, rather than running the same broken line.
    Check("the auth check refuses on it as well", !codex.AuthProblem(carried).empty());
    Check("on both lanes", !claude.AuthProblem(carried).empty());
}

void TestRegistry()
{
    std::printf("registry\n");

    Check("the claude lane resolves", ainpc::Find("ClaudeCli") != nullptr);
    Check("the codex lane resolves", ainpc::Find("CodexCli") != nullptr);

    // Two lanes, two backends. They answer to the names AiNpcProviderName produces, and each
    // is its own object: a registry that handed both names the same backend would spend the
    // wrong subscription without a word.
    Check("the two lanes are different backends", ainpc::Find("ClaudeCli") != ainpc::Find("CodexCli"));
    EqualString("the claude backend knows its name", ainpc::Find("ClaudeCli")->Name(), "ClaudeCli");
    EqualString("the codex backend knows its name", ainpc::Find("CodexCli")->Name(), "CodexCli");

    // An unknown name is an error, never a default. A settings bug that silently ran the
    // wrong backend would be indistinguishable from a working mod -- and would spend the
    // wrong subscription.
    Check("an unknown name resolves to nothing", ainpc::Find("OpenRouter") == nullptr);
    Check("an empty name resolves to nothing", ainpc::Find("") == nullptr);
    Check("an unknown name is quoted back", Contains(ainpc::ExplainUnknown("Nonsense"), "Nonsense"));
}

void TestScrub()
{
    std::printf("environment scrub\n");

    const auto& scrubbed = ainpc::ScrubbedVariables();
    const auto Scrubs = [&scrubbed](const wchar_t* aName) {
        for (const std::wstring& name : scrubbed)
        {
            if (name == aName)
            {
                return true;
            }
        }
        return false;
    };

    Check("the Anthropic key is scrubbed", Scrubs(L"ANTHROPIC_API_KEY"));
    Check("the OpenAI key is scrubbed", Scrubs(L"OPENAI_API_KEY"));
    Check("the gateway switches are scrubbed", Scrubs(L"CLAUDE_CODE_USE_BEDROCK"));

    // Codex documents its own ways to authenticate without a subscription, and every one of
    // them is a player billed per message on a lane whose menu entry says otherwise.
    Check("the Codex key is scrubbed", Scrubs(L"CODEX_API_KEY"));
    Check("the Codex access token is scrubbed", Scrubs(L"CODEX_ACCESS_TOKEN"));
    Check("the workload identity is scrubbed", Scrubs(L"OPENAI_IDENTITY_TOKEN_FILE"));

    // CODEX_HOME is where the Codex sign-in lives. Removing it would not protect the player,
    // it would sign them out of the subscription this lane exists to use.
    Check("CODEX_HOME is left alone", !Scrubs(L"CODEX_HOME"));
}

void TestJson()
{
    std::printf("json\n");

    ainpc::json::Value root;
    Check("a surrogate pair decodes", ainpc::json::Parse(R"({"t":"\ud83d\ude00"})", root));
    EqualString("and produces four UTF-8 bytes", root.StringAt("t"), "\xF0\x9F\x98\x80");

    Check("trailing content is refused", !ainpc::json::Parse("{} trailing", root));
    Check("an unterminated string is refused", !ainpc::json::Parse(R"({"a":"b)", root));

    EqualString("control characters are escaped", ainpc::json::Quote(std::string("a\nb")), "\"a\\nb\"");
    EqualString("UTF-8 passes through", ainpc::json::Quote("\xC3\xA9"), "\"\xC3\xA9\"");

    // A crash guard, not a style rule. The reader is recursive descent, so nesting depth is
    // stack depth -- and it parses settings.json, which the player edits and which sits in a
    // folder any mod can write to. Without a limit, a file of ten thousand brackets takes the
    // game process down with it.
    Check("deep nesting is refused, not crashed", !ainpc::json::Parse(std::string(10000, '[') , root));
    Check("and so is the object form", !ainpc::json::Parse(std::string(10000, '{'), root));

    // Legitimate depth still parses: the real payloads nest three or four deep.
    Check("ordinary nesting still parses",
          ainpc::json::Parse(R"({"choices":[{"message":{"content":"ok"}}]})", root));

    // The grammar, now that the parser is a loop over an explicit stack rather than a
    // descent. Each of these is a way the state machine could accept something JSON does not.
    Check("an empty object parses", ainpc::json::Parse("{}", root));
    Check("an empty array parses", ainpc::json::Parse("[]", root));
    Check("nested empties parse", ainpc::json::Parse(R"({"a":[],"b":{}})", root));
    Check("a trailing comma in an object is refused", !ainpc::json::Parse(R"({"a":1,})", root));
    Check("a trailing comma in an array is refused", !ainpc::json::Parse("[1,]", root));
    Check("a leading comma is refused", !ainpc::json::Parse("[,1]", root));
    Check("mismatched brackets are refused", !ainpc::json::Parse("[1}", root));
    Check("an unclosed container is refused", !ainpc::json::Parse(R"({"a":1)", root));
    Check("a second document is refused", !ainpc::json::Parse("{} {}", root));
    Check("a bare comma is refused", !ainpc::json::Parse("1,2", root));
    Check("a missing colon is refused", !ainpc::json::Parse(R"({"a" 1})", root));
    Check("empty input is refused", !ainpc::json::Parse("", root));

    // And the values still come out of a nested document intact.
    Check("a nested document parses", ainpc::json::Parse(R"({"u":{"in":7,"ok":true}})", root));
    const ainpc::json::Value* nested = root.Find("u");
    Check("the nested object is there", nested != nullptr && nested->IsObject());
    Check("its number survived", nested && nested->IntAt("in") == 7);
    Check("its bool survived", nested && nested->BoolAt("ok"));
}

// Sound, from memory and never from a file.
//
// The device is real, so these run against whatever output the machine has. What is asserted
// is what code can see: the format was accepted, the buffer was taken, and it was handed back
// once it had played. Whether a human HEARD it is the one thing this cannot answer -- run with
// -Audible and listen.
//
// Silent by default: a suite that beeps during unrelated work is a suite people stop running.

// Waits for the device to hand the buffer back, and answers how long it took.
//
// Not a fixed sleep: opening an output device costs a start latency that belongs to the
// hardware -- a Bluetooth or HDMI sink that has gone idle takes noticeably longer than a warm
// one -- and a suite that fails on a slow speaker measures the speaker. What is asserted is
// the property, "the memory comes back", with a bound loose enough that only a stuck device
// crosses it.
int WaitUntilSilent(int aMaxMilliseconds)
{
    int waited = 0;
    while (ainpc::audio::IsPlaying() && waited < aMaxMilliseconds)
    {
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        waited += 10;
    }
    return waited;
}

void PutU32(std::vector<uint8_t>& aOut, uint32_t aValue)
{
    aOut.push_back(static_cast<uint8_t>(aValue & 0xFF));
    aOut.push_back(static_cast<uint8_t>((aValue >> 8) & 0xFF));
    aOut.push_back(static_cast<uint8_t>((aValue >> 16) & 0xFF));
    aOut.push_back(static_cast<uint8_t>((aValue >> 24) & 0xFF));
}

void PutU16(std::vector<uint8_t>& aOut, uint16_t aValue)
{
    aOut.push_back(static_cast<uint8_t>(aValue & 0xFF));
    aOut.push_back(static_cast<uint8_t>((aValue >> 8) & 0xFF));
}

void PutTag(std::vector<uint8_t>& aOut, const char* aTag)
{
    aOut.insert(aOut.end(), aTag, aTag + 4);
}

// A .wav exactly as a file would hold it, assembled in RAM and never written down.
std::vector<uint8_t> WavImage(const std::vector<uint8_t>& aPcm, uint32_t aRate)
{
    std::vector<uint8_t> image;
    PutTag(image, "RIFF");
    PutU32(image, static_cast<uint32_t>(36 + aPcm.size()));
    PutTag(image, "WAVE");
    PutTag(image, "fmt ");
    PutU32(image, 16);
    PutU16(image, 1);             // PCM
    PutU16(image, 1);             // mono
    PutU32(image, aRate);
    PutU32(image, aRate * 2);     // bytes per second
    PutU16(image, 2);             // block align
    PutU16(image, 16);            // bits per sample
    PutTag(image, "data");
    PutU32(image, static_cast<uint32_t>(aPcm.size()));
    image.insert(image.end(), aPcm.begin(), aPcm.end());
    return image;
}

// The synthesis half of the voice lane, with no sound and no game.
//
// It runs the machine's own SAPI voice into a buffer and checks that bytes come back. That is
// the whole offline claim: a line of text becomes samples. Whether those samples are worth
// listening to is a launch, and whether a real text-to-speech service is better is a different
// question -- what is asserted here is that the LANE works end to end without a file.
//
// The elapsed time is printed rather than asserted. It is the number the voice lane is judged
// on -- Mantella's players report latency as their first complaint, and all of it is synthesis
// -- but a threshold on somebody else's machine would fail for being slow rather than wrong.
void TestSpeech()
{
    std::printf("Speech (text to samples, in memory)\n");

    std::vector<uint8_t> samples;
    std::string why = "unset";

    Check("an empty line says nothing", !ainpc::speech::Render("", samples, why));

    const auto started = std::chrono::steady_clock::now();
    const bool rendered = ainpc::speech::Render("Testing, one two three.", samples, why);
    const auto elapsed =
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started)
            .count();

    Check("a line becomes samples", rendered);
    if (!rendered)
    {
        std::printf("        the voice said: %s\n", why.c_str());
        std::printf("        (no SAPI voice installed is a machine fact, not a code failure)\n");
        return;
    }

    Check("and there are enough of them to hear", samples.size() > 1000u);
    std::printf("        %zu bytes in %lld ms, %u Hz mono\n", samples.size(),
                static_cast<long long>(elapsed), ainpc::speech::SampleRate());

    // The buffer is handed to the audio path exactly as the worker hands it over, so a format
    // the player could never hear fails here rather than in game.
    ainpc::audio::Format format;
    format.sampleRate = ainpc::speech::SampleRate();
    format.channels = ainpc::speech::Channels();
    format.bitsPerSample = ainpc::speech::BitsPerSample();
    Check("the audio path accepts what the voice produced",
          ainpc::audio::Play(samples.data(), samples.size(), format) == ainpc::audio::Status::Ok);
    ainpc::audio::Stop();
}

void TestAudio(bool aAudible)
{
    std::printf("Audio (from memory)\n");
    // Said out loud, because the listener is the instrument here: a run that plays nothing and
    // a run whose sound went to another device look identical from a chair.
    std::printf("        mode: %s\n", aAudible ? "AUDIBLE -- a tone is played below"
                                                : "silent (pass -Audible to hear it)");
    const std::vector<std::string> outputs = ainpc::audio::Outputs();
    std::printf("        outputs Windows can see (%zu):\n", outputs.size());
    for (size_t i = 0; i < outputs.size(); ++i)
    {
        std::printf("          [%zu] %s\n", i, outputs[i].c_str());
    }
    using ainpc::audio::Status;

    Check("an empty buffer is refused", ainpc::audio::Play(nullptr, 0, {}) == Status::EmptyBuffer);

    const std::vector<uint8_t> silence = ainpc::audio::Tone(0.2, 0.0, 0.0).samples;
    ainpc::audio::Format format;
    format.sampleRate = 22050;
    format.channels = 1;

    format.bitsPerSample = 24;
    Check("an unsupported sample width is refused",
          ainpc::audio::Play(silence.data(), silence.size(), format) == Status::UnsupportedFormat);
    format.bitsPerSample = 16;

    const Status status = ainpc::audio::Play(silence.data(), silence.size(), format);
    Check("the device takes a PCM buffer", status == Status::Ok);
    if (status != Status::Ok)
    {
        std::printf("        device said: %s\n", ainpc::audio::Describe(status));
    }
    Check("it reports playing", ainpc::audio::IsPlaying());

    const int waited = WaitUntilSilent(3000);
    Check("it hands the buffer back once it is done", !ainpc::audio::IsPlaying());
    if (ainpc::audio::IsPlaying())
    {
        std::printf("        still playing after %d ms of 200 ms of audio\n", waited);
    }

    // Long enough to be recognised rather than missed: a device that has just been opened
    // swallows the start, and a 150 ms blip is over before a listener knows it began.
    const double seconds = aAudible ? 0.7 : 0.2;
    const std::vector<uint8_t> image =
        WavImage(ainpc::audio::Tone(seconds, 440.0, aAudible ? 0.40 : 0.0).samples, 22050);
    if (aAudible)
    {
        std::printf("        playing 700 ms at 440 Hz now...\n");
    }
    Check("a WAV image in RAM plays", ainpc::audio::PlayWav(image.data(), image.size()) == Status::Ok);
    Check("and it too comes back", WaitUntilSilent(5000) < 5000);
    std::printf("        it went to: %s\n",
                ainpc::audio::DeviceName().empty() ? "<the device would not name itself>"
                                                   : ainpc::audio::DeviceName().c_str());

    std::vector<uint8_t> notWave = image;
    notWave[9] = 'X';
    Check("a non-WAVE image is refused",
          ainpc::audio::PlayWav(notWave.data(), notWave.size()) == Status::NotWave);

    std::vector<uint8_t> compressed = image;
    compressed[20] = 3;  // IEEE float, not PCM
    Check("a compressed WAVE is refused",
          ainpc::audio::PlayWav(compressed.data(), compressed.size()) == Status::NotPcm);

    const std::vector<uint8_t> cut(image.begin(), image.end() - 100);
    Check("an image ending inside its own data is refused",
          ainpc::audio::PlayWav(cut.data(), cut.size()) == Status::Truncated);

    ainpc::audio::Play(silence.data(), silence.size(), format);
    ainpc::audio::Stop();
    Check("Stop() silences it", !ainpc::audio::IsPlaying());
    ainpc::audio::Stop();
    Check("Stop() on silence is harmless", !ainpc::audio::IsPlaying());
}

/// The streaming lane ///

// Bytes in, complete `data:` payloads out, whatever the chunk boundaries are.
void TestSseReader()
{
    std::printf("sse reader\n");

    {
        ainpc::stream::SseReader reader;
        std::vector<std::string> payloads;
        const std::string wire = "data: {\"a\":1}\n\ndata: {\"a\":2}\n\n";
        reader.Feed(wire.data(), wire.size(), payloads);
        Check("two events, two payloads", payloads.size() == 2);
        if (payloads.size() == 2)
        {
            EqualString("the first payload", payloads[0], "{\"a\":1}");
            EqualString("the second payload", payloads[1], "{\"a\":2}");
        }
    }

    // The one that matters: an event arriving in two reads, cut inside its own JSON. A reader
    // that handed out what it had would give the chunk parser half an object and be told it is
    // not JSON -- for every chunk, on a fast connection.
    {
        ainpc::stream::SseReader reader;
        std::vector<std::string> payloads;
        const std::string head = "data: {\"choi";
        const std::string tail = "ces\":[]}\n\n";
        reader.Feed(head.data(), head.size(), payloads);
        Check("a half event yields nothing", payloads.empty());
        reader.Feed(tail.data(), tail.size(), payloads);
        Check("the read that completes it yields it", payloads.size() == 1);
        if (payloads.size() == 1)
        {
            EqualString("and it is whole", payloads[0], "{\"choices\":[]}");
        }
    }

    // OpenRouter's keep-alives. A parser that JSON-decodes every line dies here with
    // "unexpected end of JSON input", which is a real bug filed against a real client.
    {
        ainpc::stream::SseReader reader;
        std::vector<std::string> payloads;
        const std::string wire = ": OPENROUTER PROCESSING\n\n: OPENROUTER PROCESSING\n\ndata: {\"a\":1}\n\n";
        reader.Feed(wire.data(), wire.size(), payloads);
        Check("comment lines produce no payload", payloads.size() == 1);
        if (payloads.size() == 1)
        {
            EqualString("and the data still arrives", payloads[0], "{\"a\":1}");
        }
    }

    {
        ainpc::stream::SseReader reader;
        std::vector<std::string> payloads;
        const std::string wire = "data: [DONE]\r\n\r\n";
        reader.Feed(wire.data(), wire.size(), payloads);
        Check("CRLF line endings are read", payloads.size() == 1);
        if (payloads.size() == 1)
        {
            EqualString("[DONE] is handed on, not swallowed", payloads[0], "[DONE]");
        }
    }

    // A connection that closed without the blank line that ends the last event.
    {
        ainpc::stream::SseReader reader;
        std::vector<std::string> payloads;
        const std::string wire = "data: {\"a\":1}";
        reader.Feed(wire.data(), wire.size(), payloads);
        Check("an unterminated event waits", payloads.empty());
        reader.Finish(payloads);
        Check("and comes out at the end", payloads.size() == 1);
    }
}

void TestSentenceSplitter()
{
    std::printf("sentence splitter\n");

    {
        ainpc::stream::SentenceSplitter splitter;
        std::vector<std::string> out;
        splitter.Feed("Je suis devant le Afterlife. ", out);
        Check("a terminated sentence comes out", out.size() == 1);
        if (out.size() == 1)
        {
            EqualString("without its trailing space", out[0], "Je suis devant le Afterlife.");
        }
        EqualString("and nothing is left behind", splitter.Finish(), "");
    }

    // The abbreviation. "M." ends nothing, and a splitter without a minimum length hands the
    // voice two characters to say.
    {
        ainpc::stream::SentenceSplitter splitter;
        std::vector<std::string> out;
        splitter.Feed("M. Silverhand a dit non, et il avait raison. ", out);
        Check("an initial does not cut", out.size() == 1);
        if (out.size() == 1)
        {
            EqualString("the whole sentence survives", out[0], "M. Silverhand a dit non, et il avait raison.");
        }
    }

    // A terminator at the very end of a delta is not a cut: the next delta decides whether it
    // ended a sentence or sat in the middle of a number.
    {
        ainpc::stream::SentenceSplitter splitter;
        std::vector<std::string> out;
        splitter.Feed("On se retrouve au bar a 22h.", out);
        Check("a terminator at the edge waits", out.empty());
        splitter.Feed("30 comme convenu. ", out);
        Check("and the time was not a full stop", out.size() == 1);
        if (out.size() == 1)
        {
            EqualString("one sentence, not two", out[0], "On se retrouve au bar a 22h.30 comme convenu.");
        }
    }

    // The mandatory flush. A reply with no terminator at all lives entirely in the buffer, and
    // without this the last thing the character says is never said.
    {
        ainpc::stream::SentenceSplitter splitter;
        std::vector<std::string> out;
        splitter.Feed("faut que je te laisse", out);
        Check("no terminator, nothing delivered yet", out.empty());
        EqualString("the flush gives it back", splitter.Finish(), "faut que je te laisse");
        EqualString("and only once", splitter.Finish(), "");
    }

    {
        ainpc::stream::SentenceSplitter splitter;
        std::vector<std::string> out;
        splitter.Feed("Tu es serieux la, Johnny ? Parce que moi je le suis. Vraiment.", out);
        Check("several sentences in one delta", out.size() == 2);
        EqualString("what is left is the unterminated tail", splitter.Finish(), "Vraiment.");
    }

    // A closing guillemet belongs to the sentence it closes, not to the next one.
    {
        ainpc::stream::SentenceSplitter splitter;
        std::vector<std::string> out;
        splitter.Feed("Il a dit \xC2\xAB je m'en occupe.\xC2\xBB Et il est parti chez Vik. ", out);
        Check("two sentences", out.size() == 2);
        if (out.size() == 2)
        {
            Check("the quote closes the first", Contains(out[0], "\xC2\xBB"));
            Check("and does not open the second", !Contains(out[1], "\xC2\xBB"));
        }
    }
}

void TestStreamAssembly()
{
    std::printf("stream assembly\n");

    // A whole exchange as OpenRouter sends it: a comment, deltas, the chunk that carries
    // finish_reason, and THEN the usage block. The last one is the trap -- a client that stops
    // at finish_reason loses the numbers the ledger and the daily cap live on, silently, with a
    // reply that looks perfect.
    const std::string wire =
        ": OPENROUTER PROCESSING\n\n"
        "data: {\"choices\":[{\"delta\":{\"content\":\"Je suis devant le Afterlife. \"}}]}\n\n"
        "data: {\"choices\":[{\"delta\":{\"content\":\"Tu arrives quand ?\"}}]}\n\n"
        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
        "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":4504,\"completion_tokens\":312,"
        "\"prompt_tokens_details\":{\"cached_tokens\":4000}}}\n\n"
        "data: [DONE]\n\n";

    ainpc::stream::Assembler assembler;
    std::vector<std::string> sentences;
    // Fed one byte at a time, because that is the harshest chunking there is and the real one
    // is somewhere between it and a single read.
    for (size_t i = 0; i < wire.size(); ++i)
    {
        assembler.Feed(wire.data() + i, 1, sentences);
    }
    Check("the first sentence is out before the end", sentences.size() == 1);
    assembler.Finish(sentences);

    Check("both sentences arrived", sentences.size() == 2);
    if (sentences.size() == 2)
    {
        EqualString("the first", sentences[0], "Je suis devant le Afterlife.");
        EqualString("the second", sentences[1], "Tu arrives quand ?");
    }
    Check("the stream says it finished", assembler.Complete());
    Check("no error was reported", assembler.Error().empty());

    const std::string response = assembler.Response();
    EqualString("the reply reassembles whole", ReplyText(response),
                "Je suis devant le Afterlife. Tu arrives quand ?");
    Check("the usage block survived finish_reason", Contains(response, "\"prompt_tokens\":4504"));
    Check("and so did the completion count", Contains(response, "\"completion_tokens\":312"));
    Check("and the cached half", Contains(response, "\"cached_tokens\":4000"));
}

void TestStreamFailures()
{
    std::printf("stream failures\n");

    // A stream that stopped mid-reply. The speaking lane has a watchdog expecting one answer,
    // and a truncated reply handed over as a good one is written into the thread for good.
    {
        const std::string wire = "data: {\"choices\":[{\"delta\":{\"content\":\"Je suis devant le \"}}]}\n\n";
        ainpc::stream::Assembler assembler;
        std::vector<std::string> sentences;
        assembler.Feed(wire.data(), wire.size(), sentences);
        assembler.Finish(sentences);
        Check("a broken stream is not complete", !assembler.Complete());
        EqualString("and what arrived is still readable", assembler.Text(), "Je suis devant le ");
    }

    // An error object inside a 200 stream, which is how a provider reports a model that fell
    // over after it started answering.
    {
        const std::string wire = "data: {\"error\":{\"message\":\"upstream is overloaded\"}}\n\n";
        ainpc::stream::Assembler assembler;
        std::vector<std::string> sentences;
        assembler.Feed(wire.data(), wire.size(), sentences);
        assembler.Finish(sentences);
        EqualString("the error is carried out", assembler.Error(), "upstream is overloaded");
    }

    // Garbage on the wire is skipped rather than fatal: one unreadable chunk must not lose the
    // reply around it.
    {
        const std::string wire =
            "data: not json at all\n\n"
            "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n"
            "data: [DONE]\n\n";
        ainpc::stream::Assembler assembler;
        std::vector<std::string> sentences;
        assembler.Feed(wire.data(), wire.size(), sentences);
        assembler.Finish(sentences);
        EqualString("the readable chunks still assemble", assembler.Text(), "ok");
        Check("and [DONE] ends it", assembler.Complete());
    }
}

void TestStreamOptions()
{
    std::printf("stream options\n");

    const std::string body = "{\"model\":\"x\",\"messages\":[],\"temperature\":0.9}";
    const std::string asked = ainpc::stream::WithStreamOptions(body);
    Check("it asks for a stream", Contains(asked, "\"stream\":true"));
    // Not optional for this mod: without it the usage block never comes, and a reply whose cost
    // was never measured passes for a free one.
    Check("it asks for the usage block", Contains(asked, "\"include_usage\":true"));
    Check("what the slot set survives", Contains(asked, "\"temperature\":0.9"));

    ainpc::json::Value parsed;
    Check("and the result is still JSON", ainpc::json::Parse(asked, parsed) && parsed.IsObject());

    ainpc::json::Value empty;
    Check("an object with nothing in it gains no trailing comma",
          ainpc::json::Parse(ainpc::stream::WithStreamOptions("{}"), empty) && empty.IsObject());
}

} // namespace

int main(int argc, char** argv)
{
    bool audible = false;
    for (int i = 1; i < argc; ++i)
    {
        if (std::strcmp(argv[i], "-Audible") == 0)
        {
            audible = true;
        }
    }

    std::printf("ai_npc plugin, offline suite\n\n");

    TestJson();
    TestChatBody();
    TestResponseShape();
    TestClaudeCommandLine();
    TestClaudeReplies();
    TestClaudeAuth();
    TestCodexCommandLine();
    TestCodexInput();
    TestCodexReplies();
    TestCodexAuth();
    TestShimRefusal();
    TestRegistry();
    TestScrub();
    TestSseReader();
    TestSentenceSplitter();
    TestStreamAssembly();
    TestStreamFailures();
    TestStreamOptions();
    TestAudio(audible);
    TestSpeech();

    std::printf("\n%d check(s), %d failure(s)\n", g_checks, g_failures);
    if (g_failures == 0)
    {
        std::printf("PASS\n");
        return 0;
    }
    std::printf("FAIL\n");
    return 1;
}
