// Reaching the mod's own systems, and the log that depends on doing so: whether AiNpcLog
// prints at all is a setting on that service.
//
// The name is kept however little is left here. A renamed .reds does not disappear from the
// game folder when the mod is reinstalled: it becomes an orphan redscript compiles alongside
// its replacement, and the copy loaded last wins in silence.

module AiNpc

func GetAiNpcSystem() -> ref<AiNpcSystem> {
    return GameInstance.GetScriptableServiceContainer().GetService(NameOf<AiNpcSystem>()) as AiNpcSystem;
}

func GetAiNpcHttpSystem() -> ref<AiNpcHttpSystem> {
    return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(NameOf<AiNpcHttpSystem>()) as AiNpcHttpSystem;
}

public static func AiNpcLog(const text: String) {
    if AiNpcLogging() {
        FTLog(s"[ai_npc]: \(text)");
    }
}

// Whether the log is on, asked before a message is built: AiNpcLog takes a String, so an
// interpolated `s"..."` is assembled at the call site whether or not it is written. Only the
// lines the phone drives once per contact per redraw ask this first; everywhere else a guard
// around a line that runs once is noise.
//
// The null check is not padding: config loading and provider registration run from service
// initialisation, where AiNpcSettingsService may not exist yet, and an unguarded read would
// take the service down at start -- the one moment its output is worth having.
public static func AiNpcLogging() -> Bool {
    let settings = AiNpcSettingsService.Get();
    return IsDefined(settings) && settings.logging;
}

// Same null guard as AiNpcLog: a failure can be reported before the menu exists, and the
// answer then has to be "no" rather than a crash.
public static func AiNpcDebugEnabled() -> Bool {
    let settings = AiNpcSettingsService.Get();
    return IsDefined(settings) && settings.debugMode;
}

// A development tool, not a player feature: undo rewrites the story the player just lived. It
// rides on Debug Mode rather than a switch of its own, because whoever wants it is already
// replaying the same line against a prompt change.
//
// A function because two lanes ask it -- the key handler and the hint strip -- and the key
// that does nothing and the glyph that promises it have to go dark together.
public static func AiNpcUndoAvailable() -> Bool {
    return AiNpcDebugEnabled();
}

// Named after the setting, which is named after the cost: the retry is what is bought, the
// repair is what is done with it. Absent service reads as no -- a setting that spends the
// player's tokens must never default to yes because the menu had not finished loading.
// Where the choice of a command is made. Read at the two points that differ: the prompt that
// does or does not carry the vocabulary, and the reply that is or is not scanned for one.
//
// A switch flipped mid-conversation is safe in both directions and settles on the next reply:
// nothing about it is stored, and neither half remembers what the other did last turn.
func AiNpcActionModeSetting() -> AiNpcActionMode {
    let settings = AiNpcSettingsService.Get();
    if !IsDefined(settings) {
        return AiNpcActionMode.Embedded;
    }
    return settings.actionMode;
}

func AiNpcActionsAreDedicated() -> Bool {
    return Equals(AiNpcActionModeSetting(), AiNpcActionMode.Dedicated);
}

public static func AiNpcRetryActionsEnabled() -> Bool {
    let settings = AiNpcSettingsService.Get();
    return IsDefined(settings) && settings.retryActions;
}

// Settings, asked for by name. Mod Settings binds its menu to the fields on
// AiNpcSettingsService, so the fields live there, and nothing reads one directly: a caller
// names the question and the answer is looked up here.
//
// `AiNpcSettingsService.Get().aiModel` at a call site is an ambient read -- it works from
// anywhere, it cannot be given a different answer in a test, and every occurrence is one more
// place that has to remember the service may not exist yet. tools\lint.ps1 counts them.

// OpenRouter outside a session: the field's own default, so an early caller sees what the menu
// would have shown it.
func AiNpcProviderSetting() -> AiNpcProvider {
    let settings = AiNpcSettingsService.Get();
    if !IsDefined(settings) {
        return AiNpcProvider.OpenRouter;
    }
    return settings.aiModel;
}

// The one write. The setup window changes the provider for the running session -- Mod Settings
// owns it across launches and is pushed separately -- and this is where "the service may not be
// up" is answered, so no call site has to hold a settings handle to assign one field.
//
// Answers whether it took: a window told nothing would report a switch that did not happen.
func AiNpcSetProviderSetting(provider: AiNpcProvider) -> Bool {
    let settings = AiNpcSettingsService.Get();
    if !IsDefined(settings) {
        return false;
    }
    settings.aiModel = provider;
    return true;
}

// Same shape, same reason: the installer answers this one too, and the field is what
// AiNpcUnpromptedEnabled reads on the next unprompted request.
func AiNpcSetUnpromptedSetting(enabled: Bool) -> Bool {
    let settings = AiNpcSettingsService.Get();
    if !IsDefined(settings) {
        return false;
    }
    settings.unpromptedEnabled = enabled;
    return true;
}

// Normal outside a session, which is the field's default and the safe answer: a missing menu
// must never read as "no filter".
public func AiNpcToneTier() -> AiNpcConversationType {
    let settings = AiNpcSettingsService.Get();
    if !IsDefined(settings) {
        return AiNpcConversationType.Normal;
    }
    return settings.conversationType;
}

// On outside a session, which is the field's default and the safe direction: a compaction that
// does not run costs nothing, where a window silently cut to twenty turns looks like a
// character that forgot. Nothing is destroyed either way.
//
// Moved out of settings.json, which is for what the menu cannot say -- keys, urls, free text.
// A key of the same name left in the file is ignored, and AiNpcSystem logs a line when it
// finds one that disagrees.
func AiNpcMemoryEnabled() -> Bool {
    let settings = AiNpcSettingsService.Get();
    if !IsDefined(settings) {
        return true;
    }
    return settings.memoryEnabled;
}

// The one place the slider is read, clamped on the way out: a value persisted under an older
// range must not set a budget that leaves eviction nothing it is allowed to evict. Falls back
// to the measured default with no service, since the compaction lane can run before the menu.
func AiNpcMemoryFactBudget() -> Int32 {
    let settings = AiNpcSettingsService.Get();
    if !IsDefined(settings) {
        return AiNpcMemoryDefaultMaxFacts();
    }
    return AiNpcMemoryClampFactBudget(settings.memoryFacts);
}

// The field's default with no service, which costs nothing here: the only caller has already
// refused for "no session". So this answers the setting and never doubles as a readiness
// check, which would give a mod two different reasons for one refusal.
public func AiNpcUnpromptedEnabled() -> Bool {
    let settings = AiNpcSettingsService.Get();
    if !IsDefined(settings) {
        return true;
    }
    return settings.unpromptedEnabled;
}

// Off with no service, the field's default and the only safe direction: a cap that switched
// itself on because the menu had not loaded would refuse a request against a budget nobody
// set, and the symptom names none of that.
func AiNpcDailyLimitEnabled() -> Bool {
    let settings = AiNpcSettingsService.Get();
    return IsDefined(settings) && settings.dailyLimitEnabled;
}

// That ceiling, in tokens; the menu is in thousands because a step of 1 across 200000 is not a
// usable slider. Clamped on the way out like the memory budget: a value persisted under an
// older range must not set a ceiling the menu never offered.
func AiNpcDailyTokenBudget() -> Int32 {
    let settings = AiNpcSettingsService.Get();
    if !IsDefined(settings) {
        return AiNpcClampDailyBudget(AiNpcDefaultDailyBudgetThousands());
    }
    return AiNpcClampDailyBudget(settings.dailyTokens);
}

// Asked by the three lanes before they build anything, and yes with no service: the tally
// cannot refuse what it has not been able to count.
func AiNpcHasTokenBudgetLeft() -> Bool {
    let usage = AiNpcUsageService.Get();
    return !IsDefined(usage) || usage.HasBudgetLeft();
}

// A question about state, not widgets: the import path refuses while the player is reading a
// thread, because replacing the history under an open chat leaves them looking at messages
// that no longer exist.
//
// Both surfaces, which is why it goes through the registry rather than the phone's model: read
// off AiNpcSystem it left AGENT LINK unprotected, and the terminal is the surface an offline
// import is most likely to be run next to.
func AiNpcChatIsOnScreen() -> Bool {
    return NotEquals(StrLen(AiNpcCurrentContactId()), 0);
}

// The "unread" flag that drove an auto-open is gone, and the flag went with it: it inferred an
// intention from a widget-spawn callback, so it fired on a plain tab switch and opened
// whichever contact a list-refresh burst had last reported. The SMS notification, titled with
// the sender's name, is the game's own affordance for the same thing.
//
// Done right it would need the pending reply to carry its contact id, and belong on the Raised
// edge of AiNpcPhoneStateMachine, which cannot be reached by pressing Q or D.
