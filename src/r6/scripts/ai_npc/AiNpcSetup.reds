module AiNpc

import RedHttpClient.*
import RedData.Json.*

// Read the current setup, change it, and prove it works, from inside a running game.
// Installing asks a player to pick a provider in one menu, alt-tab out, paste a key into
// r6\storages\AiNpc\settings.json and restart -- every step invisible from in-game, and the
// only symptom when one goes wrong is "[NO SIGNAL]", which names none of them.
//
// A ScriptableSystem rather than a ScriptableService for one reason: CET reaches systems and
// not services. Everything here that touches settings goes through AiNpcStorageService, which
// remains the only owner of the file.
//
// Every public method returns a String meant to be read by a human, never parsed. The window
// renders what it is given; the wording lives here, next to the code that knows what happened.
public class AiNpcSetupSystem extends ScriptableSystem {

    // Three states rather than a Bool, because "no test has been run yet" and "a test ran and
    // failed" must not look the same in the window.
    private let m_testState: String = "";
    private let m_testResult: String = "";
    private let m_testProvider: AiNpcProvider = AiNpcProvider.OpenRouter;

    // Counted up on every send, and read only by the CLI transport: an HTTP test comes back
    // through the callback it was sent with. Without it, a test the player gave up on could
    // overwrite the result of the one they ran afterwards.
    private let m_testSerial: Int32 = 0;
    private let m_testUrl: String = "";

    // The clock on a test that may never be answered. Measured 2026-08-24: a CLI answer the
    // plugin produced correctly was never handed to script, and the window said "Testing
    // ClaudeCli..." for the rest of the session, refusing to start another -- the one state a
    // diagnostic must never reach.
    private let m_testWatchdog: ref<AiNpcWatchdog>;

    // What the test in flight is costing -- see AiNpcRequestLog.
    private let m_record: ref<AiNpcRequestRecord>;

    // The installer's choice, applied to a game never told anything else. The marker is the
    // choice itself, stored in settings.json: comparing the stored string to the compiled one
    // gets three cases right with no extra state -- first launch applies it, later launches
    // are no-ops, and re-running the installer with a different answer applies the new one. A
    // player who switched provider in the menu is not overruled.
    //
    // OnAttach rather than the storage service's OnInitialize: applying it writes the Mod
    // Settings ConfigVar and the field on AiNpcSystem, and neither exists until a session does.
    private func OnAttach() -> Void {
        // Named rather than null, like the two lanes: a callback firing with no test behind it
        // writes a line naming nobody instead of taking the system down.
        this.m_record = AiNpcRequestRecord.Idle();
        this.m_testWatchdog = new AiNpcWatchdog();

        let provider = AiNpcInstallPresetProvider();
        if Equals(StrLen(provider), 0) {
            return;
        }

        let storage = AiNpcStorageService.GetPersistentStorageSystem();
        if !IsDefined(storage) {
            return;
        }

        // The marker is the whole answer, every field of it. Two installs of the same provider
        // on different models are two different choices, and comparing the provider alone
        // would apply the first and silently ignore the second.
        let model = AiNpcInstallPresetOpenRouterModel();
        let unprompted = AiNpcInstallPresetUnprompted();
        let preset = provider + "|" + model + "|" + unprompted;
        if Equals(storage.GetSetting("installPreset", ""), preset) {
            return;
        }

        let outcome = this.SetProvider(provider);
        if NotEquals(StrLen(model), 0) {
            outcome += " " + this.SetSetting("openRouterModel", model);
        }
        if NotEquals(StrLen(unprompted), 0) {
            outcome += " " + this.SetUnprompted(Equals(unprompted, "on"));
        }
        storage.SetSetting("installPreset", preset);
        FTLog(s"[ai_npc]: install preset '\(preset)' applied. \(outcome)");
    }

    /// Reading ///

    // What is running, what it is pointed at, and whether it can work at all, in that order.
    public func DescribeSetup() -> String {
        let system = GetAiNpcSystem();
        if !IsDefined(system) {
            return "AI NPC is not running: no session, or the mod failed to load. Check gamelog.log.";
        }

        let provider = AiNpcProviderSetting();
        let out = s"provider  \(AiNpcProviderName(provider))\n";

        switch provider {
            case AiNpcProvider.OpenRouter:
                out += s"model     \(AiNpcGetOpenRouterModel())\n";
                out += s"routing   \(AiNpcGetOpenRouterProvider())\n";
                out += s"key       \(AiNpcMaskSecret(AiNpcGetOpenRouterApiKey()))\n";
                break;
            case AiNpcProvider.ClaudeCli:
                out += s"model     \(AiNpcGetClaudeCliModel())\n";
                out += s"command   \(AiNpcDescribeCliPath(AiNpcGetClaudeCliPath()))\n";
                out += "key       none -- your Claude subscription, not an API key\n";
                break;
            case AiNpcProvider.CodexCli:
                out += s"model     \(AiNpcDescribeCliModel(AiNpcGetCodexCliModel()))\n";
                out += s"command   \(AiNpcDescribeCliPath(AiNpcGetCodexCliPath()))\n";
                out += "key       none -- your ChatGPT subscription, not an API key\n";
                break;
        }

        let issue = AiNpcLlmCredentialIssue(provider);
        if Equals(StrLen(issue), 0) {
            out += "status    configured. Press Test to find out whether it answers.\n";
        } else {
            out += s"status    NOT USABLE: \(issue)\n";
        }

        if AiNpcMemoryEnabled() {
            out += "memory    on\n";
        } else {
            out += "memory    off\n";
        }

        out += "file      r6\\storages\\AiNpc\\settings.json";
        return out;
    }

    // The provider list, with the one thing a player has to decide about each: what it costs
    // them to get started.
    public func DescribeProviders() -> String {
        return
            // ":free costs nothing" is half the story: a free slug can be retired (404) and a
            // live one can answer 429 for hours, because the pool is shared with every other
            // mod using it. Either reads as a broken install without this line.
            "OpenRouter    the supported way to play. Needs a key from openrouter.ai/keys. Model ids ending in :free cost nothing, but they are a shared pool: expect 429 (busy) or 404 (retired), and change the model when one stops answering.\n" +
            "\n" +
            // Not a footnote under the two lines: the window renders this verbatim, and a
            // reader picking a lane reads the lane. Said on each, in the same words, so
            // neither reads as the exception.
            "ClaudeCli     FOR MOD AUTHORS TESTING THEIR OWN WORK, NOT FOR PLAYING. Anthropic states the limits on Pro and Max assume ordinary individual use of Claude Code; playing this way is outside that, and the account can be limited or suspended without warning (anthropic.com/legal/consumer-terms). No key at all: it drives the Claude CLI you are already signed into, through ai_npc.dll. Needs `claude` installed, and `claude auth status` reporting a subscription rather than an API key.\n" +
            "\n" +
            "CodexCli      FOR MOD AUTHORS TESTING THEIR OWN WORK, NOT FOR PLAYING. Stricter than the Claude lane: OpenAI's terms forbid extracting Output automatically or programmatically, with no exception written for third-party products, and the account can be limited or suspended without warning (openai.com/policies). No key either: the same idea on a ChatGPT subscription, through the Codex CLI and ai_npc.dll. Needs `codex` installed and `codex login status` reporting a ChatGPT sign-in rather than an API key. Untested in game so far, and its safe-for-work tier has not been measured on this lane.";
    }

    // The editable fields of the current provider, one per line:
    //
    //     key <tab> label <tab> value <tab> secret
    //
    // The window builds its form from this rather than a list of its own, so adding a provider
    // stays a one-file change. Secrets come back already masked, so the window is never handed
    // a key it would have to be trusted not to display.
    public func EditableRows() -> String {
        let system = GetAiNpcSystem();
        if !IsDefined(system) {
            return "";
        }

        switch AiNpcProviderSetting() {
            case AiNpcProvider.OpenRouter:
                return this.Row("openRouterApiKey", "API key", AiNpcMaskSecret(AiNpcGetOpenRouterApiKey()), true)
                    + "\n" + this.Row("openRouterModel", "Model", AiNpcGetOpenRouterModel(), false)
                    + "\n" + this.Row("openRouterProvider", "Routing", AiNpcGetOpenRouterProvider(), false);
            // No secret row on either CLI lane: there is no key to show. What is editable is
            // what the plugin has to be told -- which model, and where the executable is when
            // PATH cannot answer.
            case AiNpcProvider.ClaudeCli:
                return this.Row("claudeCliModel", "Model", AiNpcGetClaudeCliModel(), false)
                    + "\n" + this.Row("claudeCliPath", "Command", AiNpcGetClaudeCliPath(), false);
            case AiNpcProvider.CodexCli:
                return this.Row("codexCliModel", "Model", AiNpcGetCodexCliModel(), false)
                    + "\n" + this.Row("codexCliPath", "Command", AiNpcGetCodexCliPath(), false);
        }
        return "";
    }

    private func Row(key: String, label: String, value: String, secret: Bool) -> String {
        let flag = "0";
        if secret {
            flag = "1";
        }
        return key + "\t" + label + "\t" + value + "\t" + flag;
    }

    /// Writing ///

    // Two writes, because they answer different questions. The live field is what every request
    // reads, so AiNpcSetProviderSetting makes the next message use the new provider with no menu
    // and no reload; Mod Settings owns the value across launches, in its own user.ini, so the
    // ConfigVar is pushed too and AcceptChanges persists it.
    //
    // If the ConfigVar cannot be found the session still switches, and the answer says so: a
    // player told "this session only" knows to set it in the menu, and a player told nothing
    // would be back on the default provider after a restart with no idea why.
    public func SetProvider(name: String) -> String {
        let provider: AiNpcProvider;
        if !AiNpcProviderFromName(name, provider) {
            return s"Unknown provider '\(name)'. One of: OpenRouter, ClaudeCli, CodexCli.";
        }

        if !AiNpcSetProviderSetting(provider) {
            return "AI NPC is not running: no session.";
        }

        this.m_testState = "";
        this.m_testResult = "";

        let persisted = this.PushProviderToModSettings(provider);
        let label = AiNpcProviderName(provider);

        if persisted {
            return s"Provider is now \(label), and Mod Settings has it for next launch.";
        }
        return s"Provider is now \(label) for THIS SESSION. Mod Settings did not take it -- set 'Model' in Mod Settings > AI NPC so it survives a restart.";
    }

    // The same two writes, for the one setting that spends a request the player never typed.
    public func SetUnprompted(enabled: Bool) -> String {
        if !AiNpcSetUnpromptedSetting(enabled) {
            return "AI NPC is not running: no session.";
        }

        let label = enabled ? "on" : "off";
        if this.PushUnpromptedToModSettings(enabled) {
            return s"Characters may write first: \(label), and Mod Settings has it for next launch.";
        }
        return s"Characters may write first: \(label) for THIS SESSION. Mod Settings did not take it -- set it in Mod Settings > AI NPC > Budget so it survives a restart.";
    }

    // One setting written to settings.json and applied to the running game. Whitelisted, and
    // not as a security measure -- the file is three clicks away in a text editor -- but so a
    // typo cannot invent a key: accepting "openrouterApiKey" would write a setting nothing
    // reads, report success, and leave a green message over a dead provider.
    //
    // importConversationsFrom is absent: it is the journal's repair hatch, meant to be deleted
    // once it has run, and it belongs to the tab that can show which pointer to use.
    public func SetSetting(key: String, value: String) -> String {
        if !AiNpcSetupIsWritableKey(key) {
            return s"Refused: '\(key)' is not a setting this window writes. See README.";
        }

        let storage = AiNpcStorageService.GetPersistentStorageSystem();
        if !IsDefined(storage) {
            return "No storage: RedFileSystem is missing, or the AiNpc storage was revoked this session (see red4ext\\logs\\redfilesystem-*.log).";
        }

        if !storage.SetSetting(key, value) {
            return s"Could not write \(key) to settings.json.";
        }

        // The write went through the object every accessor reads, so the next request already
        // uses it. The test state is dropped, because a result obtained with the previous
        // value is now a lie on screen.
        this.m_testState = "";
        this.m_testResult = "";

        if AiNpcSetupIsSecretKey(key) {
            return s"\(key) saved: \(AiNpcMaskSecret(value)). Press Test.";
        }
        if Equals(StrLen(value), 0) {
            return s"\(key) cleared.";
        }
        return s"\(key) = \(value)";
    }

    // For the player who edited the file by hand while the game was running, which is still
    // the documented way in.
    public func ReloadSettings() -> String {
        let storage = AiNpcStorageService.GetPersistentStorageSystem();
        if !IsDefined(storage) {
            return "No storage: nothing to reload.";
        }
        storage.ReloadSettings();
        this.m_testState = "";
        this.m_testResult = "";
        return "settings.json re-read from disk.";
    }

    /// Testing ///

    // One real request to the configured provider, built with the same AiNpcLlmChatBody and
    // AiNpcLlmChatHeaders the speaking lane calls, so anything that would break a reply breaks
    // this too and in the same place. A test that assembled its own request could pass while
    // the mod stayed silent.
    //
    // Not through AiNpcHttpSystem: that lane owns the typing indicator and the input field, and
    // a diagnostic must not leave a contact typing forever.
    public func StartTest() -> String {
        if Equals(this.m_testState, "running") {
            return s"Already testing \(AiNpcProviderName(this.m_testProvider))...";
        }

        let system = GetAiNpcSystem();
        if !IsDefined(system) {
            return "AI NPC is not running: no session.";
        }

        let provider = AiNpcProviderSetting();
        this.m_testProvider = provider;

        let issue = AiNpcLlmCredentialIssue(provider);
        if NotEquals(StrLen(issue), 0) {
            this.m_testState = "done";
            this.m_testResult = s"NOT CONFIGURED: \(issue)";
            return this.m_testResult;
        }

        this.m_testUrl = AiNpcLlmChatUrl(provider);
        // Bound to locals so the record can measure each half: a serialised body cannot be
        // taken apart again.
        let instruction = "You are a connection test. Answer with a single word.";
        let ask = "Reply with the single word OK.";
        let body = AiNpcLlmChatBody(provider, instruction, ask);

        // Recorded like any other request: it appears in the log with its size and cost, and
        // what it spends is charged to the day.
        this.m_record = AiNpcRequestRecord.Sent(AiNpcLaneTest(), "", provider, instruction, ask);

        // Through the same seam the two real lanes use.
        this.m_testSerial += 1;
        if !AiNpcSendChat(provider, body, this, n"OnTestResponse",
                AiNpcCliRequestId(AiNpcCliLaneTest(), this.m_testSerial)) {
            this.m_testState = "done";
            this.m_testResult = "FAILED: the transport refused the request. On a CLI lane that means ai_npc.dll did not load - check red4ext\\logs\\ai_npc-*.log.";
            return this.m_testResult;
        }

        this.m_testState = "running";
        this.m_testResult = "";
        AiNpcArmTimeout(AiNpcTestTimeoutCallback.Create(this.m_testWatchdog.Arm()),
            AiNpcLlmRequestTimeout(provider));
        AiNpcLog(s"Setup test: \(AiNpcProviderName(provider)) -> \(this.m_testUrl)");
        return s"Testing \(AiNpcProviderName(provider))...";
    }

    // Polled by the window every frame, so it must be cheap and must never start anything.
    public func DescribeTest() -> String {
        if Equals(this.m_testState, "running") {
            return s"Testing \(AiNpcProviderName(this.m_testProvider))...";
        }
        if Equals(this.m_testState, "") {
            return "No test run yet.";
        }
        return this.m_testResult;
    }

    public func IsTestRunning() -> Bool {
        return Equals(this.m_testState, "running");
    }

    private cb func OnTestResponse(response: ref<HttpResponse>) {
        this.HandleTestReply(AiNpcReply.FromHttp(response));
    }

    // Called from AiNpcCliDeliver. A test the player gave up on still finishes in the plugin,
    // and its answer must not overwrite a newer one.
    public func OnCliTestReply(serial: Int32, reply: ref<AiNpcReply>) -> Void {
        if NotEquals(serial, this.m_testSerial) {
            return;
        }
        this.HandleTestReply(reply);
    }

    // Public because a DelayCallback is the only thing that can reach it, and addressed by
    // name rather than cancelled.
    //
    // It writes its own sentence rather than passing an empty reply to HandleTestReply: an
    // empty reply is status 0, which that path explains in terms of RedHttpClient and the
    // -no-tls flag -- true of a dropped POST, meaningless where nothing was posted.
    public func OnTestTimedOut(waitId: Int32) -> Void {
        if !this.m_testWatchdog.IsCurrent(waitId) {
            return;
        }
        this.m_testWatchdog.Disarm();
        this.m_testState = "done";

        // The record closes on nothing, like any request that was never answered: it spent
        // what it spent, and leaving it open would hold a line in the log for ever.
        this.m_record.Answered(AiNpcReply.Nothing());

        let seconds = Cast<Int32>(AiNpcLlmRequestTimeout(this.m_testProvider));
        this.m_testResult =
            s"FAILED: \(AiNpcProviderName(this.m_testProvider)) never answered within \(seconds)s.";
        FTLogError(s"[ai_npc]: setup test timed out after \(seconds)s (provider \(AiNpcProviderName(this.m_testProvider)))");
    }

    private func HandleTestReply(reply: ref<AiNpcReply>) -> Void {
        this.m_testState = "done";
        // Renaming the wait disarms it: the timer still in the delay queue now carries a name
        // nobody answers to.
        this.m_testWatchdog.Disarm();

        let root = reply.Root();

        // Above every branch, refusals included, as in the two lanes. The answer carries the
        // day it belongs to, so a test run after midnight tells the mod the day has turned.
        this.m_record.Answered(reply);

        if !reply.IsOk() {
            let detail = AiNpcExtractApiError(root);
            if Equals(StrLen(detail), 0) {
                detail = s"HTTP \(reply.StatusCode())";
            }
            // The one case where the status code says nothing: the request never reached the
            // network. AiNpcDescribeTransportFailure names the two causes -- RedHttpClient's
            // version and the -no-tls launch flag -- which is the most common way this mod is
            // installed correctly and still does not work.
            if Equals(reply.StatusCode(), 0) {
                detail = AiNpcDescribeTransportFailure(this.m_testUrl, detail);
            }
            this.m_testResult = s"FAILED: \(detail)";
            FTLogError(s"[ai_npc]: setup test failed (provider \(AiNpcProviderName(this.m_testProvider)), url \(this.m_testUrl)): \(detail)");
            return;
        }

        if !IsDefined(root) {
            this.m_testResult = "FAILED: the provider answered, but not with JSON. Wrong endpoint?";
            return;
        }

        let text = AiNpcExtractChatText(root);
        if Equals(StrLen(text), 0) {
            let detail = AiNpcExtractApiError(root);
            if Equals(StrLen(detail), 0) {
                detail = "the provider returned an empty reply -- usually a model id it does not serve";
            }
            this.m_testResult = s"FAILED: \(detail)";
            return;
        }

        this.m_testResult = s"OK: \(AiNpcProviderName(this.m_testProvider)) answered \"\(text)\". Characters can talk.";
    }

    /// Mod Settings ///

    // Searched rather than addressed: the mod name and category in the menu are display
    // strings, free to change here without anything noticing. The variable name is the one
    // compile-time fact, so that is what is matched.
    private func PushProviderToModSettings(provider: AiNpcProvider) -> Bool {
        let var = this.FindVar(n"aiModel") as ModConfigVarEnum;
        if !IsDefined(var) {
            return false;
        }

        let index = var.GetIndexFor(EnumInt(provider));
        if index < 0 {
            return false;
        }

        var.SetIndex(index);
        ModSettings.AcceptChanges();
        return true;
    }

    private func PushUnpromptedToModSettings(enabled: Bool) -> Bool {
        let var = this.FindVar(n"unpromptedEnabled") as ModConfigVarBool;
        if !IsDefined(var) {
            return false;
        }

        var.SetValue(enabled);
        ModSettings.AcceptChanges();
        return true;
    }

    private func FindVar(name: CName) -> ref<ConfigVar> {
        let mods = ModSettings.GetMods();
        let i = 0;
        while i < ArraySize(mods) {
            let categories = ModSettings.GetCategories(mods[i]);
            let j = 0;
            while j < ArraySize(categories) {
                let vars = ModSettings.GetVars(mods[i], categories[j]);
                let k = 0;
                while k < ArraySize(vars) {
                    if Equals(vars[k].GetName(), name) {
                        return vars[k];
                    }
                    k += 1;
                }
                j += 1;
            }
            i += 1;
        }
        return null;
    }
}

/// Free functions ///

// A whole table rather than a parse: the strings are a contract with the CET window and with
// anybody typing into the console. Out-parameter rather than a sentinel member, because
// inventing an "invalid" AiNpcProvider would put a value in the enum Mod Settings persists.
func AiNpcProviderFromName(name: String, out provider: AiNpcProvider) -> Bool {
    let key = StrLower(name);

    if Equals(key, "openrouter") {
        provider = AiNpcProvider.OpenRouter;
        return true;
    }
    if Equals(key, "claudecli") || Equals(key, "claude") {
        provider = AiNpcProvider.ClaudeCli;
        return true;
    }
    if Equals(key, "codexcli") || Equals(key, "codex") {
        provider = AiNpcProvider.CodexCli;
        return true;
    }
    return false;
}

// The command a CLI lane will run, said in a way a player can act on. An empty setting is the
// normal case and must not read as a fault: the plugin looks the executable up on PATH, which
// is right on most machines.
func AiNpcDescribeCliPath(path: String) -> String {
    if Equals(StrLen(path), 0) {
        return "found on PATH (set claudeCliPath or codexCliPath if it is not)";
    }
    return path;
}

// Same idea for a model left empty: the CLI picks, and that is a choice rather than a gap.
func AiNpcDescribeCliModel(model: String) -> String {
    if Equals(StrLen(model), 0) {
        return "whatever the CLI defaults to";
    }
    return model;
}

// The settings the configuration window is allowed to write.
func AiNpcSetupIsWritableKey(key: String) -> Bool {
    return Equals(key, "openRouterApiKey")
        || Equals(key, "openRouterModel")
        || Equals(key, "openRouterProvider")
        || Equals(key, "claudeCliModel")
        || Equals(key, "claudeCliPath")
        || Equals(key, "codexCliModel")
        || Equals(key, "codexCliPath")
        || Equals(key, "appearance")
        || Equals(key, "playerDescription");
}

// Whether a value must never be echoed back in full.
func AiNpcSetupIsSecretKey(key: String) -> Bool {
    return StrContains(key, "ApiKey");
}

// Recognisable but not reusable: the window is the first thing somebody screenshots when they
// ask for help on Nexus, and a key pasted into a public forum has to be revoked. Enough
// characters to answer "is this the key I think it is?", never enough to be one.
func AiNpcMaskSecret(value: String) -> String {
    let length = StrLen(value);
    if Equals(length, 0) {
        return "(not set)";
    }
    if Equals(value, "0000000000") {
        return "0000000000 (anonymous)";
    }
    if length <= 12 {
        return s"(set, \(length) chars)";
    }
    return s"\(StrLeft(value, 6))...\(StrRight(value, 4))  (\(length) chars)";
}
