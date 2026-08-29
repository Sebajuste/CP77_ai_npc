#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "Process.hpp"

#include <thread>

namespace ainpc
{
namespace
{
struct Pipe
{
    HANDLE read = nullptr;
    HANDLE write = nullptr;

    ~Pipe()
    {
        Close();
    }

    void Close()
    {
        CloseRead();
        CloseWrite();
    }

    void CloseRead()
    {
        if (read)
        {
            CloseHandle(read);
            read = nullptr;
        }
    }

    void CloseWrite()
    {
        if (write)
        {
            CloseHandle(write);
            write = nullptr;
        }
    }
};

// The child's end must be inheritable and ours must NOT be: a handle we leak into the child
// keeps the pipe alive after the child exits, and the read below then blocks forever on a
// writer that is really us.
bool MakePipe(Pipe& aPipe, bool aChildWrites)
{
    SECURITY_ATTRIBUTES attributes{};
    attributes.nLength = sizeof(attributes);
    attributes.bInheritHandle = TRUE;

    if (!CreatePipe(&aPipe.read, &aPipe.write, &attributes, 0))
    {
        return false;
    }

    const HANDLE ours = aChildWrites ? aPipe.read : aPipe.write;
    return SetHandleInformation(ours, HANDLE_FLAG_INHERIT, 0) != FALSE;
}

// The most one child may hand back on one pipe.
//
// A reply is a few KB. A CLI stuck in a loop is bounded only by the timeout, and three minutes
// of output is measured in gigabytes -- allocated inside the game process, which is the part
// that matters. Past the cap the pipe is still drained, so the child never blocks on a full
// buffer and the timeout stays the thing that ends it; what stops is the appending.
//
// Truncated output is not silently accepted downstream: it will not parse as the JSON the
// backend expects, and the request comes back as the typed "returned output that was not
// JSON" failure, quoting what it did print.
constexpr size_t kMaxCapture = 8u * 1024u * 1024u;

void ReadAll(HANDLE aHandle, std::string& aOut)
{
    char buffer[4096];
    DWORD read = 0;
    while (ReadFile(aHandle, buffer, sizeof(buffer), &read, nullptr) && read > 0)
    {
        if (aOut.size() < kMaxCapture)
        {
            const size_t room = kMaxCapture - aOut.size();
            aOut.append(buffer, read < room ? read : room);
        }
    }
}

// The child's environment, minus what we refuse to pass on.
//
// Built from ours rather than from nothing: the CLI needs PATH, APPDATA, USERPROFILE and the
// rest to find its own installation and its credentials. What is removed is named by the
// caller, one variable at a time.
std::wstring BuildEnvironment(const std::vector<std::wstring>& aScrubbed)
{
    std::wstring block;

    LPWCH existing = GetEnvironmentStringsW();
    if (!existing)
    {
        return block;
    }

    for (LPWCH cursor = existing; *cursor; )
    {
        const std::wstring entry(cursor);
        cursor += entry.size() + 1;

        // The leading '=' entries are the per-drive current directories. They are not
        // variables and dropping them would confuse the child about relative paths.
        const size_t equals = entry.find(L'=', 1);
        if (equals == std::wstring::npos)
        {
            block += entry;
            block.push_back(L'\0');
            continue;
        }

        std::wstring name = entry.substr(0, equals);
        bool drop = false;
        for (const std::wstring& scrubbed : aScrubbed)
        {
            if (_wcsicmp(name.c_str(), scrubbed.c_str()) == 0)
            {
                drop = true;
                break;
            }
        }
        if (!drop)
        {
            block += entry;
            block.push_back(L'\0');
        }
    }

    FreeEnvironmentStringsW(existing);
    block.push_back(L'\0');
    return block;
}
} // namespace

ProcessResult RunCapture(const std::wstring& aExecutable, const std::wstring& aCommandLine,
                         const std::wstring& aWorkingDirectory, const std::string& aStandardInput,
                         unsigned long aTimeoutMs, void* aJob, const std::vector<std::wstring>& aScrubbedVariables)
{
    ProcessResult result;

    // A .cmd or .bat is not an executable: CreateProcess refuses it, and the npm installer
    // of these CLIs ships exactly that kind of shim. Route it through the command processor
    // instead. /s with one pair of outer quotes is what keeps cmd from re-parsing the inner
    // quoting it was handed.
    std::wstring executable = aExecutable;
    std::wstring commandText = aCommandLine;
    const size_t dot = executable.find_last_of(L'.');
    if (dot != std::wstring::npos)
    {
        const std::wstring extension = executable.substr(dot);
        if (_wcsicmp(extension.c_str(), L".cmd") == 0 || _wcsicmp(extension.c_str(), L".bat") == 0)
        {
            // ── THE PARSER CHANGES HERE, AND THAT IS THE WHOLE PROBLEM ───────
            //
            // QuoteArgument quotes for CommandLineToArgvW, which reads \" as an escaped quote.
            // cmd.exe does not: it sees a plain quote and closes the quoted region, so a value
            // carrying a quote of its own escapes into cmd's own grammar, where & and | start
            // a new command. That is CVE-2024-24576, and this is the one code path in the
            // plugin where two parsers read the same line.
            //
            // Nothing legitimate here contains a quote -- Windows forbids one in a file name,
            // and a model alias is a word. So the answer is not a second escaping scheme that
            // has to stay correct forever: it is to refuse a line that could only have been
            // built from a value that is not what it claims to be, and to say so.
            if (aCommandLine.find(L"\\\"") != std::wstring::npos)
            {
                result.refusal = "a value in r6\\storages\\AiNpc\\settings.json contains a quote character. The "
                                 "command was not run: remove the quote from the model or the command path";
                return result;
            }

            wchar_t comspec[MAX_PATH]{};
            const DWORD length = GetEnvironmentVariableW(L"ComSpec", comspec, MAX_PATH);
            executable = (length > 0 && length < MAX_PATH) ? comspec : L"C:\\Windows\\System32\\cmd.exe";
            commandText = L"\"" + executable + L"\" /s /c \"" + aCommandLine + L"\"";
        }
    }

    Pipe input;
    Pipe output;
    Pipe errors;
    if (!MakePipe(input, false) || !MakePipe(output, true) || !MakePipe(errors, true))
    {
        result.lastError = GetLastError();
        return result;
    }

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = input.read;
    startup.hStdOutput = output.write;
    startup.hStdError = errors.write;

    std::wstring environment = BuildEnvironment(aScrubbedVariables);

    // CreateProcessW may write to the command line buffer, so it gets a mutable copy.
    std::vector<wchar_t> commandLine(commandText.begin(), commandText.end());
    commandLine.push_back(L'\0');

    PROCESS_INFORMATION process{};

    // Suspended, so the child is inside the job before it can spawn anything of its own --
    // and a CLI spawns plenty. CREATE_NO_WINDOW keeps a console from flashing over the game,
    // and CREATE_UNICODE_ENVIRONMENT is required because the block above is wide.
    const BOOL created =
        CreateProcessW(executable.empty() ? nullptr : executable.c_str(), commandLine.data(), nullptr, nullptr, TRUE,
                       CREATE_NO_WINDOW | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT,
                       environment.empty() ? nullptr : environment.data(),
                       aWorkingDirectory.empty() ? nullptr : aWorkingDirectory.c_str(), &startup, &process);

    if (!created)
    {
        result.lastError = GetLastError();
        return result;
    }
    result.started = true;

    if (aJob && !AssignProcessToJobObject(static_cast<HANDLE>(aJob), process.hProcess))
    {
        result.gameJobError = GetLastError();
    }

    // A SECOND job, this one for the duration of this request alone.
    //
    // The reason is the pipes, not the lifetime. `claude` on Windows is a shim that runs
    // node; the shim can exit while node still holds the write end of our stdout pipe, and
    // the reader below would then wait on end-of-file that never comes -- after the process
    // we were waiting on has already gone. Terminating this job at the end kills whatever
    // the child left behind, which closes the pipes and releases the readers.
    //
    // Nested jobs are supported from Windows 8, so belonging to both this and the game-wide
    // one is fine, and the game-wide one keeps its crash guarantee.
    HANDLE requestJob = CreateJobObjectW(nullptr, nullptr);
    if (!requestJob)
    {
        result.requestJobError = GetLastError();
    }
    else
    {
        // All three steps are the one guarantee: a job that was created but never given the
        // limit, or never given the child, releases nothing when it closes.
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if (!SetInformationJobObject(requestJob, JobObjectExtendedLimitInformation, &limits, sizeof(limits)) ||
            !AssignProcessToJobObject(requestJob, process.hProcess))
        {
            result.requestJobError = GetLastError();
        }
    }

    ResumeThread(process.hThread);

    // Our copies of the child's ends, closed now. Held open, the reads below would never see
    // end-of-file because this process would still count as a writer.
    input.CloseRead();
    output.CloseWrite();
    errors.CloseWrite();

    // Three concurrent flows, and all three have to move at once or the child deadlocks:
    // it can block writing a large reply to a full stdout pipe while we block writing its
    // stdin. One thread each for stdin and stderr, stdout on this one.
    std::thread writer(
        [&]()
        {
            size_t at = 0;
            while (at < aStandardInput.size())
            {
                DWORD written = 0;
                const DWORD chunk = static_cast<DWORD>((aStandardInput.size() - at) > 32768u
                                                           ? 32768u
                                                           : (aStandardInput.size() - at));
                if (!WriteFile(input.write, aStandardInput.data() + at, chunk, &written, nullptr) || written == 0)
                {
                    break;
                }
                at += written;
            }
            // The close IS the end-of-input signal. Without it a CLI reading until EOF waits
            // for a prompt that has already been written in full.
            input.CloseWrite();
        });

    std::thread outputReader([&]() { ReadAll(output.read, result.out); });
    std::thread errorReader([&]() { ReadAll(errors.read, result.err); });

    // THE WAIT COMES BEFORE THE JOINS, and that ordering is the timeout.
    //
    // Reading on this thread instead would have made the budget unenforceable: a child that
    // hangs without writing leaves ReadFile blocked with no reader left to notice the clock.
    // Waiting on the process first means the deadline is always observed, and terminating it
    // is what breaks the pipes and releases the three threads below.
    const DWORD waited = WaitForSingleObject(process.hProcess, aTimeoutMs);
    if (waited == WAIT_TIMEOUT)
    {
        result.timedOut = true;
        // This PID and nothing else. Never a lookup by image name.
        TerminateProcess(process.hProcess, 1);
        WaitForSingleObject(process.hProcess, 5000);
    }
    else
    {
        DWORD code = 0;
        if (GetExitCodeProcess(process.hProcess, &code))
        {
            result.exitCode = code;
        }
    }

    // Whatever the child left running goes now, which is what lets the three joins below
    // return. Buffered output already written is not lost: the readers drain the pipe and
    // then see end-of-file, which is exactly the ending they were waiting for.
    if (requestJob)
    {
        TerminateJobObject(requestJob, 1);
        CloseHandle(requestJob);
    }

    writer.join();
    outputReader.join();
    errorReader.join();

    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return result;
}

std::wstring QuoteArgument(const std::wstring& aValue)
{
    std::wstring out;
    out.push_back(L'"');
    size_t backslashes = 0;
    for (const wchar_t c : aValue)
    {
        if (c == L'\\')
        {
            ++backslashes;
            continue;
        }
        if (c == L'"')
        {
            out.append(backslashes * 2 + 1, L'\\');
            backslashes = 0;
            out.push_back(c);
            continue;
        }
        out.append(backslashes, L'\\');
        backslashes = 0;
        out.push_back(c);
    }
    out.append(backslashes * 2, L'\\');
    out.push_back(L'"');
    return out;
}

std::wstring Locate(const std::wstring& aPreferred, const std::wstring& aCommand)
{
    if (!aPreferred.empty())
    {
        const DWORD attributes = GetFileAttributesW(aPreferred.c_str());
        if (attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY))
        {
            return aPreferred;
        }
        // A path that was configured and is not there is worth ignoring rather than
        // failing on: the CLI may have been reinstalled elsewhere since, and PATH will say.
    }

    // SearchPathW applies PATHEXT, so "claude" finds claude.exe, claude.cmd or claude.bat --
    // and the npm installer ships a .cmd shim, which a bare CreateProcess would refuse.
    wchar_t found[MAX_PATH]{};
    wchar_t* filePart = nullptr;
    const DWORD length = SearchPathW(nullptr, aCommand.c_str(), L".exe", MAX_PATH, found, &filePart);
    if (length > 0 && length < MAX_PATH)
    {
        return std::wstring(found, length);
    }

    const DWORD cmdLength = SearchPathW(nullptr, aCommand.c_str(), L".cmd", MAX_PATH, found, &filePart);
    if (cmdLength > 0 && cmdLength < MAX_PATH)
    {
        return std::wstring(found, cmdLength);
    }

    return L"";
}

bool WriteUtf8File(const std::wstring& aPath, const std::string& aContent)
{
    HANDLE file = CreateFileW(aPath.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        return false;
    }

    bool ok = true;
    size_t at = 0;
    while (at < aContent.size())
    {
        DWORD written = 0;
        const DWORD chunk =
            static_cast<DWORD>((aContent.size() - at) > 65536u ? 65536u : (aContent.size() - at));
        if (!WriteFile(file, aContent.data() + at, chunk, &written, nullptr) || written == 0)
        {
            ok = false;
            break;
        }
        at += written;
    }

    CloseHandle(file);
    return ok;
}

std::wstring MakeScratchDirectory()
{
    wchar_t base[MAX_PATH]{};
    const DWORD length = GetTempPathW(MAX_PATH, base);
    if (length == 0 || length >= MAX_PATH)
    {
        return L"";
    }

    std::wstring path(base, length);
    path += L"ai_npc_cli";

    // One directory for the whole session, not one per request: it is empty by construction
    // and stays empty, so there is nothing to keep apart and nothing to clean up between
    // requests.
    if (!CreateDirectoryW(path.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS)
    {
        return L"";
    }
    return path;
}
} // namespace ainpc
