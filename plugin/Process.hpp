// Running a child process and reading everything it wrote.
//
// Two rules shape this file, and each of them cost something to learn:
//
//   * Never select a process by image name. Only the PID we created is ever touched. This
//     machine runs other `claude`, `node` and `python` processes that belong to the user or
//     to another agent, and a kill by image name takes those with it.
//
//   * Never leave an orphan. If the game crashes, the plugin's Unload never runs. Every
//     child is therefore assigned to a Job Object with JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
//     so Windows itself kills it when the game process dies, however it dies.
//
// Two more that are specific to what we run:
//
//   * The prompt goes on stdin, never on the command line. Windows caps a command line at
//     32767 characters, and the mod's system prompt is a few KB that a heavily customised
//     character can grow. The old Python bridge carried a MAX_SYSTEM_PROMPT_CHARS guard for
//     exactly this; feeding stdin removes the limit and the guard together.
//
//   * UTF-8 end to end, and never through the console code page. The pipes carry bytes, and
//     those bytes are UTF-8 in both directions. A child that inherited a console would
//     render its output in the active code page instead, and the damage is invisible until
//     an accented reply reaches a bubble.

#pragma once

#include <string>
#include <vector>

namespace ainpc
{
struct ProcessResult
{
    // False when CreateProcess itself failed -- a missing executable, a path that is not
    // executable, a denied ACL. `lastError` is then the only thing worth reporting.
    bool started = false;
    unsigned long lastError = 0;

    // Set, with `started` false, when the plugin refused to spawn the child rather than the
    // OS refusing to. The two are not the same sentence to a player: one says "install it",
    // the other says "a value in your settings.json is not what it claims to be". A backend
    // that reported this as a missing executable would send the report to the wrong place.
    std::string refusal;

    // True when the child outlived its budget and was terminated. `exitCode` is meaningless
    // in that case, and the distinction matters: a timeout is a different sentence to the
    // player than a CLI that ran and refused.
    bool timedOut = false;
    unsigned long exitCode = 0;

    // Captured whole, as bytes. stderr is kept even on success: it is where a CLI puts the
    // warning that explains a reply that is technically valid and obviously wrong.
    std::string out;
    std::string err;

    // A job assignment that did not take, as its Windows error code. Neither can fail the
    // request -- the child is already running and its answer may still be correct -- so they
    // are carried out rather than thrown, and the caller says which guarantee was lost.
    // Zero means the guarantee holds, or that it was never asked for.
    //
    // Reported rather than logged here because this file has no logger and must not acquire
    // one: keeping RED4ext out of it is what lets the offline test host build it.
    unsigned long gameJobError = 0;
    unsigned long requestJobError = 0;
};

// One child, start to finish, on the calling thread. Never call this from the game thread.
//
// `aJob` may be null, in which case the child is not tied to the game's lifetime -- which is
// only acceptable in the offline test host, where there is no game to outlive.
//
// `aScrubbedVariables` are removed from the child's environment. The player's shell may be
// configured for their day job, and an inherited ANTHROPIC_API_KEY would silently bill them
// per token for what their subscription already covers.
ProcessResult RunCapture(const std::wstring& aExecutable, const std::wstring& aCommandLine,
                         const std::wstring& aWorkingDirectory, const std::string& aStandardInput,
                         unsigned long aTimeoutMs, void* aJob, const std::vector<std::wstring>& aScrubbedVariables);

// One command-line argument, quoted the way CommandLineToArgvW will take it apart again.
//
// Not cosmetic, and it lives here rather than in a backend because the rule belongs to the
// command line itself: an executable path routinely contains "Program Files", a backslash
// before a closing quote escapes it, and a config override such as
// history.persistence="none" carries quotes of its own that have to survive intact.
std::wstring QuoteArgument(const std::wstring& aValue);

// The executable's full path, or empty when it cannot be found.
//
// `aPreferred` wins when it is set and exists -- that is the path the setup step resolved and
// wrote into settings.json. Otherwise the PATH the game process inherited is searched, which
// usually works and sometimes cannot: the native installer puts claude.exe in
// %USERPROFILE%\.local\bin, and a player who installs it while the game is running will never
// see that directory in this process's PATH.
std::wstring Locate(const std::wstring& aPreferred, const std::wstring& aCommand);

// Writes bytes to a file, replacing what was there. The content is already UTF-8 and is
// written unchanged -- no BOM, no code page, no newline translation. A CLI reading a system
// prompt back has to see the same bytes the mod built, or the accents arrive broken and
// nothing says so.
bool WriteUtf8File(const std::wstring& aPath, const std::string& aContent);

// A directory with nothing in it, for the child to run in.
//
// Not a nicety: a coding CLI discovers its configuration from the working directory upward --
// CLAUDE.md, .claude/, a git repository, project settings. Started in the game folder it
// would read whatever happens to be there. Started in an empty temporary directory it can
// only read what we passed it.
std::wstring MakeScratchDirectory();
} // namespace ainpc
