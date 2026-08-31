// The boundary: what redscript can call, and how an answer gets back to it.
//
// ── THREE RULES SHAPE THIS FILE ─────────────────────────────────────────────
//
// 1. NEVER BLOCK THE GAME THREAD. Send() returns immediately; one worker thread runs the CLI
//    and a queue carries the answer back. A CLI call takes seconds, and seconds on the game
//    thread is a frozen game.
//
// 2. THE RTTI SURFACE STAYS MINIMAL. Two classes, one static function each -- see
//    AiNpcCliNative.reds for what each declared type costs on a day the DLL fails to load.
//    Both are registered here, in one place, so the boot-blocking surface can be counted by
//    reading one file. The answer therefore
//    does NOT come back through a registered callback type: it is delivered by calling a
//    plain redscript global function, which needs nothing registered at all.
//
// 3. THE ANSWER IS DELIVERED ON THE GAME THREAD. Calling into the script VM from the worker
//    would corrupt it. RED4ext's Running state gives a per-frame tick on the right thread,
//    and that is where the completed queue is drained.
//
// The signature of AiNpcCliDeliver is a contract with AiNpcCliRequest.reds. If the two ever
// disagree the answer simply never arrives, and the lane's watchdog reports it as a provider
// that never replied -- which is why the function is looked up once and its absence logged
// loudly rather than passed over.
//
// The streaming lane adds a SECOND plain global, AiNpcStreamDeliver, and no second native class.
// It carries finished sentences to the voice while the reply is still being written, and it is a
// side channel: the reply itself still arrives once, whole, through AiNpcCliDeliver, and nothing
// downstream of it learns that anything was streamed. A build whose scripts do not declare it
// loses the sentences and keeps the replies.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/RTTITypes.hpp>

#include "ScriptApi.hpp"

#include "Audio.hpp"
#include "HttpStream.hpp"
#include "OpenRouterStream.hpp"
#include "Process.hpp"
#include "Registry.hpp"
#include "SettingsFile.hpp"
#include "Speech.hpp"
#include "Transport.hpp"

#include <atomic>
#include <cstdio>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>

namespace ainpc::script
{
namespace
{
struct Job
{
    std::string provider;
    std::string body;
    int requestId = 0;
};

// One thing to hand to script, on the game thread, in the order it was produced.
//
// Two kinds in one queue rather than two queues, and the reason is the ordering: a sentence
// belongs BEFORE the reply it is part of, and two queues drained one after the other would put
// every sentence of a request behind every reply that finished first.
enum class Kind
{
    Answer,   // the whole reply, once
    Sentence  // one finished sentence of a reply still being written
};

struct Delivery
{
    Kind kind = Kind::Answer;
    int requestId = 0;

    // Answer
    int status = 0;
    std::string body;
    std::string date;

    // Sentence. `last` is the end of the stream and may carry no text at all -- see
    // OpenRouterStream.hpp.
    std::string text;
    bool last = false;
};

// A reply and the moment it belongs to. The date is not part of ChatReply because a CLI lane
// invents it and the streaming lane is given it by the server, and only the caller knows which.
struct Outcome
{
    ChatReply reply;
    std::string date;
};

RED4ext::v1::PluginHandle g_handle = nullptr;
const RED4ext::v1::Sdk* g_sdk = nullptr;
std::wstring g_pluginDirectory;
void* g_job = nullptr;

std::mutex g_mutex;
std::condition_variable g_wake;

// One worker drains this serially, at up to 180 s a job. Past a handful, a queued request is
// one whose script-side watchdog has already fired: it would run to completion, cost a
// subscription call, and be discarded on arrival. Refusing at the door is the honest answer,
// and script already reports a refused transport correctly.
constexpr size_t kPendingLimit = 8;
std::deque<Job> g_pending;
std::deque<Delivery> g_ready;
std::atomic<bool> g_running{false};
std::thread g_worker;

// Whether this session has already proved the CLI is usable, per backend name. Checked once
// rather than per request, because it is a whole extra process spawn -- and cleared on
// failure so a player who signs in mid-session recovers without restarting the game.
std::mutex g_authMutex;
std::string g_authProved;

void Log(const char* aMessage)
{
    if (g_sdk && g_sdk->logger)
    {
        g_sdk->logger->Info(g_handle, aMessage);
    }
}

void LogError(const char* aMessage)
{
    if (g_sdk && g_sdk->logger)
    {
        g_sdk->logger->Error(g_handle, aMessage);
    }
}

// The day this answer belongs to, in the shape an HTTP `Date` header has.
//
// The token ledger rolls the day from that header and ignores an empty one, so a CLI lane
// that supplied nothing would leave the daily cap frozen on whatever day it last saw. The
// machine clock is the honest source here: the request never touched a server that could
// have dated it.
std::string HttpDateNow()
{
    SYSTEMTIME utc{};
    GetSystemTime(&utc);

    static const char* days[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
    static const char* months[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};

    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%s, %02d %s %04d %02d:%02d:%02d GMT", days[utc.wDayOfWeek % 7], utc.wDay,
              months[(utc.wMonth - 1) % 12], utc.wYear, utc.wHour, utc.wMinute, utc.wSecond);
    return buffer;
}

void Finish(int aRequestId, const Outcome& aOutcome)
{
    Delivery delivery;
    delivery.kind = Kind::Answer;
    delivery.requestId = aRequestId;
    delivery.status = aOutcome.reply.status;
    delivery.body = aOutcome.reply.body;
    delivery.date = aOutcome.date.empty() ? HttpDateNow() : aOutcome.date;

    char message[160];
    std::snprintf(message, sizeof(message), "request %d finished with status %d (%zu bytes)", aRequestId,
                  aOutcome.reply.status, aOutcome.reply.body.size());
    Log(message);

    std::lock_guard<std::mutex> lock(g_mutex);
    g_ready.push_back(std::move(delivery));
}

// One sentence, on its way to the voice while the rest of the reply is still being written.
// Queued exactly like a reply, because it crosses the same boundary and needs the same thread.
void Emit(int aRequestId, const std::string& aText, bool aLast)
{
    Delivery delivery;
    delivery.kind = Kind::Sentence;
    delivery.requestId = aRequestId;
    delivery.text = aText;
    delivery.last = aLast;

    std::lock_guard<std::mutex> lock(g_mutex);
    g_ready.push_back(std::move(delivery));
}

// The streaming lane. It shares nothing with the CLI path above but the dialect: no executable
// to find, no auth to prove, no scratch directory to write a prompt into.
Outcome RunStream(const Job& aJob)
{
    const Settings settings = ReadSettings(g_pluginDirectory);
    const openrouter::Streamed streamed =
        openrouter::Stream(aJob.body, settings.openRouterKey,
                           [&](const std::string& aText, bool aLast) { Emit(aJob.requestId, aText, aLast); });

    // The measurement the lane was built for, and the only place it exists. A first sentence
    // that is not meaningfully earlier than the whole reply means the model streams too coarsely
    // for a voice to hide inside the difference -- which is a result, and this line is how
    // anyone finds out.
    char message[200];
    if (streamed.firstSentenceMs >= 0)
    {
        std::snprintf(message, sizeof(message),
                      "request %d streamed %d sentence(s): first ready after %lld ms, whole reply after %lld ms",
                      aJob.requestId, streamed.sentences, streamed.firstSentenceMs, streamed.totalMs);
    }
    else
    {
        std::snprintf(message, sizeof(message),
                      "request %d streamed no complete sentence before it ended, after %lld ms", aJob.requestId,
                      streamed.totalMs);
    }
    Log(message);

    Outcome outcome;
    outcome.reply = streamed.reply;
    outcome.date = streamed.date;
    return outcome;
}

// One CLI request, start to finish, on the worker thread.
ChatReply RunCli(const Job& aJob)
{
    const ITransport* transport = Find(aJob.provider);
    if (!transport)
    {
        return Failure(400, ExplainUnknown(aJob.provider));
    }

    ChatRequest request;
    std::string error;
    if (!ParseChatBody(aJob.body, request, error))
    {
        // A malformed body is a bug in the mod, not in the player's setup, and saying so
        // stops the report going to the wrong place.
        return Failure(400, error + " - this is a bug in the mod, please report it");
    }

    const Settings settings = ReadSettings(g_pluginDirectory);
    const std::wstring executable = transport->Executable(settings);
    if (executable.empty())
    {
        return Failure(503, std::string(transport->Name()) +
                                ": the command could not be found on PATH. Install it, or set its path in "
                                "r6\\storages\\AiNpc\\settings.json");
    }

    // A precondition of the request, checked beside the executable lookup and for the same
    // reason: everything below runs the child in this directory and writes the system prompt
    // into it. Empty, the prompt path would become "\system-N.txt" -- the root of the
    // current drive -- and the child would run wherever the game happens to be, reading
    // whatever configuration it finds there.
    const std::wstring scratch = MakeScratchDirectory();
    if (scratch.empty())
    {
        return Failure(500, std::string(transport->Name()) +
                                ": a temporary folder for the request could not be created under %TEMP%");
    }

    // The auth check, once per session per backend. It runs through the same spawn path and
    // the same scrubbed environment as the request itself -- a check made under a different
    // environment describes a state that is not the one being used, and would pass while the
    // request quietly billed an API key.
    {
        std::unique_lock<std::mutex> lock(g_authMutex);
        if (g_authProved != aJob.provider)
        {
            lock.unlock();
            const ProcessResult status =
                RunCapture(executable, transport->AuthCommandLine(executable), scratch, "", 30000, g_job,
                           ScrubbedVariables());
            const std::string problem = transport->AuthProblem(status);
            if (!problem.empty())
            {
                return Failure(401, problem);
            }
            lock.lock();
            g_authProved = aJob.provider;
        }
    }

    std::wstring systemFile;
    if (transport->WantsSystemPromptFile() && !request.system.empty())
    {
        systemFile = scratch + L"\\system-" + std::to_wstring(aJob.requestId) + L".txt";
        if (!WriteUtf8File(systemFile, request.system))
        {
            return Failure(500, "the system prompt could not be written to " +
                                    std::string("the temporary folder - is it writable?"));
        }
    }

    const ProcessResult result =
        RunCapture(executable, transport->CommandLine(executable, request, systemFile), scratch,
                   transport->StandardInput(request), 180000, g_job, ScrubbedVariables());

    if (!systemFile.empty())
    {
        DeleteFileW(systemFile.c_str());
    }

    // One line, and only when a guarantee was actually lost. Neither failure stops the reply:
    // what each costs is written where the guarantee is explained, in Process.hpp.
    if (result.gameJobError != 0)
    {
        char message[160];
        std::snprintf(message, sizeof(message),
                      "request %d: the child is not tied to the game and will outlive a crash (error %lu)",
                      aJob.requestId, result.gameJobError);
        Log(message);
    }
    if (result.requestJobError != 0)
    {
        char message[160];
        std::snprintf(message, sizeof(message),
                      "request %d: nothing will release the pipes if the CLI leaves a child behind (error %lu)",
                      aJob.requestId, result.requestJobError);
        Log(message);
    }

    const ChatReply reply = transport->Interpret(result);

    // A failure that might be about credentials retires the cached pass, so the next request
    // checks again. Cheap, and it is what lets a player fix their sign-in without restarting.
    if (reply.status == 401 || reply.status == 502)
    {
        std::lock_guard<std::mutex> lock(g_authMutex);
        g_authProved.clear();
    }

    return reply;
}

// Which lane, and nothing else. The CLI lanes date their own answers from the machine clock
// because they never touched a server that could have dated one; the streaming lane is given a
// Date header and uses it.
Outcome Run(const Job& aJob)
{
    if (aJob.provider == openrouter::ProviderName())
    {
        return RunStream(aJob);
    }
    return {RunCli(aJob), HttpDateNow()};
}

void Worker()
{
    while (true)
    {
        Job job;
        {
            std::unique_lock<std::mutex> lock(g_mutex);
            g_wake.wait(lock, []() { return !g_pending.empty() || !g_running.load(); });
            if (!g_running.load())
            {
                return;
            }
            job = std::move(g_pending.front());
            g_pending.pop_front();
        }

        Finish(job.requestId, Run(job));
    }
}

/// Delivery, on the game thread ///

RED4ext::CBaseFunction* FindGlobal(const char* aBareName, const char* aQualifiedName)
{
    auto* rtti = RED4ext::CRTTISystem::Get();
    if (!rtti)
    {
        return nullptr;
    }

    // By short name, scanning, rather than by full name: a redscript global function is
    // registered under a decorated full name that includes its parameter types, and guessing
    // that decoration is a worse bet than looking at what is there.
    RED4ext::DynArray<RED4ext::CBaseFunction*> functions;
    rtti->GetGlobalFunctions(functions);

    // Two candidates, because it is not settled from this side whether a redscript global
    // in `module AiNpc` lands in RTTI under its bare name or its module-qualified one. The
    // class next door registers qualified (verified: "RedHttpClient.AsyncHttpClient" is in
    // that DLL verbatim), so guessing one and being wrong would mean every reply silently
    // never arriving. Accepting both costs one comparison.
    const RED4ext::CName bare(aBareName);
    const RED4ext::CName qualified(aQualifiedName);
    for (auto* function : functions)
    {
        if (!function)
        {
            continue;
        }
        if (function->shortName == bare || function->shortName == qualified ||
            function->fullName == bare || function->fullName == qualified)
        {
            return function;
        }
    }
    return nullptr;
}

void DeliverAnswer(const Delivery& aDelivery)
{
    static RED4ext::CBaseFunction* deliver = nullptr;
    static bool complained = false;

    if (!deliver)
    {
        deliver = FindGlobal("AiNpcCliDeliver", "AiNpc.AiNpcCliDeliver");
    }
    if (!deliver)
    {
        if (!complained)
        {
            complained = true;
            LogError("AiNpcCliDeliver was not found in the script runtime: replies cannot reach the mod. "
                     "The scripts and this DLL are probably from different versions.");
        }
        return;
    }

    auto* rtti = RED4ext::CRTTISystem::Get();
    RED4ext::CString body(aDelivery.body.c_str());
    RED4ext::CString date(aDelivery.date.c_str());
    int32_t requestId = aDelivery.requestId;
    int32_t status = aDelivery.status;

    RED4ext::StackArgs_t args;
    args.emplace_back(rtti->GetType("Int32"), &requestId);
    args.emplace_back(rtti->GetType("Int32"), &status);
    args.emplace_back(rtti->GetType("String"), &body);
    args.emplace_back(rtti->GetType("String"), &date);

    // The cast is load-bearing: a bare nullptr matches both the void* and the CClass*
    // overload, and neither is more specialised than the other.
    RED4ext::ExecuteFunction(static_cast<void*>(nullptr), deliver, nullptr, args);

    char message[96];
    std::snprintf(message, sizeof(message), "request %d delivered to script", aDelivery.requestId);
    Log(message);
}

// The side channel, and NOT A SECOND NATIVE CLASS. A plain redscript global costs nothing at
// boot; a declared native type the plugin failed to register is one more line in the error that
// stops the GAME from starting -- see the head of AiNpcCliNative.reds.
//
// Its absence is not fatal and is said once: a build whose scripts predate this lane still gets
// its replies, it simply hears no sentences.
void DeliverSentence(const Delivery& aDelivery)
{
    static RED4ext::CBaseFunction* deliver = nullptr;
    static bool searched = false;

    if (!searched)
    {
        searched = true;
        deliver = FindGlobal("AiNpcStreamDeliver", "AiNpc.AiNpcStreamDeliver");
        if (!deliver)
        {
            Log("AiNpcStreamDeliver was not found in the script runtime: the streamed sentences have "
                "nowhere to go, and only the complete replies will arrive.");
        }
    }
    if (!deliver)
    {
        return;
    }

    auto* rtti = RED4ext::CRTTISystem::Get();
    RED4ext::CString text(aDelivery.text.c_str());
    int32_t requestId = aDelivery.requestId;
    bool last = aDelivery.last;

    RED4ext::StackArgs_t args;
    args.emplace_back(rtti->GetType("Int32"), &requestId);
    args.emplace_back(rtti->GetType("String"), &text);
    args.emplace_back(rtti->GetType("Bool"), &last);

    RED4ext::ExecuteFunction(static_cast<void*>(nullptr), deliver, nullptr, args);
}

bool OnUpdate(RED4ext::CGameApplication*)
{
    // Drained under the lock, delivered outside it: a script callback can send a new request
    // from inside this call, and doing that while holding the queue's lock deadlocks.
    std::deque<Delivery> ready;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        ready.swap(g_ready);
    }

    for (const Delivery& delivery : ready)
    {
        if (delivery.kind == Kind::Sentence)
        {
            DeliverSentence(delivery);
        }
        else
        {
            DeliverAnswer(delivery);
        }
    }

    // FALSE, AND IT IS THE WHOLE DELIVERY MECHANISM.
    //
    // The contract is "true means this state is done updating, do not call me again". The SDK
    // documents the result as ignored for Running; it is not. Measured 2026-08-24, returning
    // true: the state was accepted, this function ran once, requests completed with status 200
    // -- and no answer was ever handed to script. Returning false, same build, same request:
    // delivered 18 ms after it finished.
    return false;
}

bool OnEnterOrExit(RED4ext::CGameApplication*)
{
    return true;
}

/// The one native function ///

void SendImpl(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    RED4ext::CString provider;
    RED4ext::CString body;
    int32_t requestId = 0;

    RED4ext::GetParameter(aFrame, &provider);
    RED4ext::GetParameter(aFrame, &body);
    RED4ext::GetParameter(aFrame, &requestId);
    ++aFrame->code; // skip ParamEnd

    bool accepted = false;
    if (g_running.load())
    {
        Job job;
        job.provider = provider.c_str();
        job.body = body.c_str();
        job.requestId = requestId;

        size_t queued = 0;
        {
            std::lock_guard<std::mutex> lock(g_mutex);
            if (g_pending.size() < kPendingLimit)
            {
                g_pending.push_back(std::move(job));
                accepted = true;
            }
            queued = g_pending.size();
        }

        char message[160];
        if (accepted)
        {
            g_wake.notify_one();
            std::snprintf(message, sizeof(message), "request %d accepted for %s (%zu queued)", requestId,
                          provider.c_str(), queued);
        }
        else
        {
            std::snprintf(message, sizeof(message), "request %d refused for %s: %zu already waiting", requestId,
                          provider.c_str(), queued);
        }
        Log(message);
    }

    if (aOut)
    {
        *aOut = accepted;
    }
}

// Plays a tone, and answers what the device said. A String rather than a Bool because the
// answer IS the measurement: "nothing came out" has two causes that look identical from a
// chair, and only the device can tell them apart. The same sentence goes to the log, so a
// player who read it on screen and an agent who read the file are looking at one fact.
void BeepImpl(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    ++aFrame->code; // skip ParamEnd

    // 700 ms at 40%, and both numbers were measured rather than chosen: 150 ms at 30% was
    // played and NOT heard on 2026-08-31, because a device that has just been opened swallows
    // the start of the first buffer. A beep too short to notice would be reported as a game
    // holding the audio device, which is the one conclusion this function exists to rule out.
    const audio::Sound sound = audio::Tone(0.7, 440.0, 0.40);
    const audio::Status status = audio::Play(sound.samples.data(), sound.samples.size(), sound.format);

    // The device is named in the answer, because "it says ok and I hear nothing" is one
    // question with two causes, and the second one is a machine with five outputs where the
    // listener is wearing the one Windows does not call default.
    char message[400];
    std::snprintf(message, sizeof(message), "beep: %s -- it went to %s", audio::Describe(status),
                  audio::DeviceName().c_str());
    if (status == audio::Status::Ok)
    {
        Log(message);
    }
    else
    {
        LogError(message);
    }

    if (aOut)
    {
        *aOut = RED4ext::CString(message);
    }
}

// Says a line out loud. Queues and returns at once: synthesis takes hundreds of milliseconds
// and the caller is the game thread.
//
// The answer describes the PREVIOUS line, not this one -- the current one has not been spoken
// yet by the time this returns, and inventing a result for it would be the one thing a
// measurement must not do. What comes back therefore reads as "ok -- 41216 bytes in 380 ms",
// and 380 ms is the number the voice lane is judged on.
void SpeakImpl(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    RED4ext::CString text;
    RED4ext::GetParameter(aFrame, &text);
    ++aFrame->code; // skip ParamEnd

    const bool queued = speech::Speak(text.c_str());
    const std::string answer = queued ? ("queued; previous: " + speech::LastResult())
                                      : std::string("nothing to say");

    char message[400];
    std::snprintf(message, sizeof(message), "speak: %s", answer.c_str());
    Log(message);

    if (aOut)
    {
        *aOut = RED4ext::CString(message);
    }
}

// Never instantiated: the class exists only to hang one static function on, which is the
// smallest shape redscript will accept for `public native class AiNpcCli`. TTypedClass needs
// a real type to size and construct, so it gets an empty one.
//
// It derives from IScriptable, and that is not decoration. Measured 2026-08-24: a type
// registered with no parent is a *struct* to the RTTI, and RED4ext validates the script blob
// against that -- `public native class` in scripts against a parentless native type refuses
// the whole blob, and the game does not start:
//
//   Script validation error: Struct 'AiNpc.AiNpcCli' has to be declared in scripts as 'struct'
//   Script validation error: Native class 'AiNpc.AiNpcCli' has declared base class
//                            'IScriptable' that is different than current one '<none>'
//
// The parent itself is wired in PostRegisterTypes, because IScriptable does not exist in the
// RTTI yet while RegisterTypes runs.
struct CliClassBody : RED4ext::IScriptable
{
    // ISerializable leaves GetNativeType pure, so a body that did not answer it would be
    // abstract -- and TTypedClass refuses a type it cannot default-construct.
    RED4ext::CClass* GetNativeType() override
    {
        return RED4ext::CRTTISystem::Get()->GetClass("AiNpc.AiNpcCli");
    }
};

RED4ext::TTypedClass<CliClassBody> g_cliClass("AiNpc.AiNpcCli");

// The same shape, and the same reason for every line of it: see CliClassBody above.
struct AudioClassBody : RED4ext::IScriptable
{
    RED4ext::CClass* GetNativeType() override
    {
        return RED4ext::CRTTISystem::Get()->GetClass("AiNpc.AiNpcAudio");
    }
};

RED4ext::TTypedClass<AudioClassBody> g_audioClass("AiNpc.AiNpcAudio");

void RegisterTypes()
{
    // The name has to be in the pool before anything can look the class up by it.
    RED4ext::CNamePool::Add("AiNpc.AiNpcCli");
    RED4ext::CNamePool::Add("AiNpc.AiNpcAudio");

    g_cliClass.flags = {.isNative = true};
    RED4ext::CRTTISystem::Get()->RegisterType(&g_cliClass);

    g_audioClass.flags = {.isNative = true};
    RED4ext::CRTTISystem::Get()->RegisterType(&g_audioClass);
}

void PostRegisterTypes()
{
    auto* rtti = RED4ext::CRTTISystem::Get();
    auto* cls = rtti->GetClass("AiNpc.AiNpcCli");
    if (!cls)
    {
        LogError("AiNpc.AiNpcCli did not register: the CLI lanes will not work.");
        return;
    }

    // The base class the script side declares. Without it the type is a struct to the RTTI and
    // the blob is rejected outright -- see CliClassBody for the exact error.
    cls->parent = rtti->GetClass("IScriptable");

    auto* send = RED4ext::CClassStaticFunction::Create(cls, "Send", "Send", &SendImpl);
    send->flags = {.isNative = true, .isStatic = true, .isPublic = true};
    send->AddParam("String", "provider");
    send->AddParam("String", "body");
    send->AddParam("Int32", "requestId");
    send->SetReturnType("Bool");
    cls->RegisterFunction(send);

    Log("AiNpc.AiNpcCli registered.");

    auto* audioClass = rtti->GetClass("AiNpc.AiNpcAudio");
    if (!audioClass)
    {
        LogError("AiNpc.AiNpcAudio did not register: the mod will make no sound.");
        return;
    }
    audioClass->parent = rtti->GetClass("IScriptable");

    auto* beep = RED4ext::CClassStaticFunction::Create(audioClass, "Beep", "Beep", &BeepImpl);
    beep->flags = {.isNative = true, .isStatic = true, .isPublic = true};
    beep->SetReturnType("String");
    audioClass->RegisterFunction(beep);

    auto* speak = RED4ext::CClassStaticFunction::Create(audioClass, "Speak", "Speak", &SpeakImpl);
    speak->flags = {.isNative = true, .isStatic = true, .isPublic = true};
    speak->AddParam("String", "text");
    speak->SetReturnType("String");
    audioClass->RegisterFunction(speak);

    Log("AiNpc.AiNpcAudio registered.");
}
} // namespace

void Start(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk, const std::wstring& aPluginDirectory,
           void* aJob)
{
    g_handle = aHandle;
    g_sdk = aSdk;
    g_pluginDirectory = aPluginDirectory;
    g_job = aJob;

    auto* rtti = RED4ext::CRTTISystem::Get();
    rtti->AddRegisterCallback(RegisterTypes);
    rtti->AddPostRegisterCallback(PostRegisterTypes);

    // The per-frame tick that drains the answer queue on the game thread. Its result is
    // checked and said out loud: without this state nothing is ever delivered, every request
    // hangs for ever, and the mod has no other symptom to show for it.
    static RED4ext::v1::GameState state{&OnEnterOrExit, &OnUpdate, &OnEnterOrExit};
    if (aSdk && aSdk->gameStates)
    {
        if (aSdk->gameStates->Add(aHandle, RED4ext::EGameStateType::Running, &state))
        {
            Log("the Running game state was added: answers will be delivered on the game thread.");
        }
        else
        {
            LogError("RED4ext refused the Running game state: no answer can be delivered, and every CLI "
                     "request will hang.");
        }
    }
    else
    {
        LogError("RED4ext exposed no game states: no answer can be delivered.");
    }

    g_running.store(true);
    g_worker = std::thread(&Worker);
}

void Stop()
{
    speech::Shutdown();

    g_running.store(false);
    g_wake.notify_all();

    // The worker may be several minutes into a CLI call, and the game is closing. Killing the
    // job kills whatever it spawned, which makes its capture return at once -- without this
    // the join below would hold the game open for the rest of the request's budget.
    if (g_job)
    {
        TerminateJobObject(static_cast<HANDLE>(g_job), 1);
    }

    // The same reason on the streaming lane: a worker blocked on a socket read would hold the
    // game open for the rest of the receive timeout.
    http::Cancel();

    if (g_worker.joinable())
    {
        g_worker.join();
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    g_pending.clear();
    g_ready.clear();
}
} // namespace ainpc::script
