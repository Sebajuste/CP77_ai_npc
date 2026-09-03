// Everything the mod reads from settings.json: the answers it cannot work out for itself and
// has to be told. Keeping them together is what keeps a credential accessor out of the prompt
// files, where a key ends up in something that gets pasted into a bug report.

module AiNpc

import RedData.Json.*

// API keys and model names live in <game>\r6\storages\AiNpc\settings.json, created with
// placeholders on first launch: credentials stay out of the distributed mod, and change
// without recompiling anything.
func AiNpcGetSetting(key: String, fallback: String) -> String {
    let storage = AiNpcStorageService.GetPersistentStorageSystem();
    if !IsDefined(storage) {
        return fallback;
    }
    return storage.GetSetting(key, fallback);
}

func AiNpcHasSetting(key: String) -> Bool {
    let storage = AiNpcStorageService.GetPersistentStorageSystem();
    if !IsDefined(storage) {
        return false;
    }
    return storage.HasSetting(key);
}

func AiNpcGetSettingObject(key: String) -> ref<JsonObject> {
    let storage = AiNpcStorageService.GetPersistentStorageSystem();
    if !IsDefined(storage) {
        return null;
    }
    return storage.GetSettingObject(key);
}

/// The slots ///

// One slot, resolved: the `slots` block of settings.json, the dialogue slot underneath it, and
// the three settings that predate the format laid over that. The impure half of AiNpcSlot.reds
// and the only one -- everything the mod decides about a slot is decided there, over values
// this function hands it.
//
// Read per request rather than cached, so an edit to settings.json followed by a reload
// applies to the next message like every other setting here.
func AiNpcGetSlot(name: String) -> ref<AiNpcSlot> {
    let model = AiNpcHasSetting("openRouterModel") ? AiNpcGetOpenRouterModel() : "";
    return AiNpcSlotFrom(AiNpcGetSettingObject("slots"), name,
        AiNpcSlotAliases(model, AiNpcGetMaxTokens(), AiNpcGetReasoningEffort()));
}

// The slot a kind of work is sent on. The pass table says which one; a pass nobody configured
// is on the dialogue slot, which is where every request went before slots existed.
func AiNpcGetSlotForPass(pass: String) -> ref<AiNpcSlot> {
    return AiNpcGetSlot(AiNpcPassSlotName(pass));
}

// The model the reply is actually written on, whatever key it is stored under. What the CET
// window shows, and what the setup test checks.
func AiNpcSpeakingModel() -> String {
    return AiNpcLlmSlotModel(AiNpcProviderSetting(), AiNpcGetSlotForPass(AiNpcLaneSpeaking()));
}

// Le plafond de reponse, et il est toujours envoye.
//
// LE LAISSER MUET FAIT REFUSER LA REQUETE CHEZ CERTAINS FOURNISSEURS. Sans plafond, ils
// reservent tout le contexte du modele pour la reponse et repondent : "Requested token count
// exceeds the model's maximum context length of 131072 tokens. You requested a total of 135244
// tokens: 4172 from the input messages and 131072 for the completion." Le meme corps passe chez
// DeepInfra et echoue chez GMICloud, et OpenRouter choisit l'un ou l'autre a chaque requete --
// d'ou un premier message qui passe et le suivant qui echoue sans que rien n'ait change.
// Mesure le 2026-09-02, en rejouant deux corps captures en jeu.
//
// Zero, la valeur qu'ecrivent tous les settings.json existants, vaut donc le plafond du mod et
// non plus le silence : la correction atteint les installations deja posees. Ce plafond est
// celui du slot de dialogue, mesure sur 31 executions -- deux fois la plus longue reponse
// observee, jetons de brouillon compris.
func AiNpcGetMaxTokens() -> Int32 {
    let asked = StringToInt(AiNpcGetSetting("maxTokens", "0"));
    if asked > 0 {
        return asked;
    }
    return AiNpcSlotDialogueMaxTokens();
}

// "low" | "medium" | "high" on the backends that take it. Empty sends nothing.
//
// A reasoning model spends most of its completion on a draft the mod never reads: gpt-oss-120b
// measured 360 reasoning tokens against 39 of visible answer, and "low" cuts that sixfold.
// Across 18 runs, replies that emitted the meeting command averaged 851 output tokens against
// 534 for those that did not: the deliberation may be what produces the command.
func AiNpcGetReasoningEffort() -> String {
    return AiNpcGetSetting("reasoningEffort", "");
}

// https://openrouter.ai/keys
func AiNpcGetOpenRouterApiKey() -> String {
    return AiNpcGetSetting("openRouterApiKey", "");
}

// Any model id from https://openrouter.ai/models
func AiNpcGetOpenRouterModel() -> String {
    return AiNpcGetSetting("openRouterModel", "google/gemma-4-31b-it:free");
}

// "Auto" lets OpenRouter pick; otherwise a provider slug such as "google-ai-studio".
func AiNpcGetOpenRouterProvider() -> String {
    return AiNpcGetSetting("openRouterProvider", "Auto");
}

/// The CLI lanes ///
//
// No key lives here: these lanes run a CLI the player has already signed into, and an API key
// would bill them a second time for what their subscription covers. The plugin refuses one
// outright rather than warning and proceeding.

// The model alias handed to `claude` -- haiku, sonnet, opus, or a full id.
func AiNpcGetClaudeCliModel() -> String {
    return AiNpcGetSetting("claudeCliModel", "sonnet");
}

// Absolute path to claude.exe. Empty means "search PATH", which usually works and sometimes
// cannot: the native installer puts it in %USERPROFILE%\.local\bin, and a player who installs
// it while the game is running will not see that in the PATH this process inherited. The
// setup step writes the resolved path here so the second launch never has to guess.
func AiNpcGetClaudeCliPath() -> String {
    return AiNpcGetSetting("claudeCliPath", "");
}

// The model handed to `codex exec`. Empty lets the CLI use its own default.
func AiNpcGetCodexCliModel() -> String {
    return AiNpcGetSetting("codexCliModel", "");
}

func AiNpcGetCodexCliPath() -> String {
    return AiNpcGetSetting("codexCliPath", "");
}

// Whether a `memoryEnabled: false` left in settings.json is still being honoured. It is NOT:
// the switch moved to Mod Settings (AiNpcMemoryEnabled, AiNpcUtilities.reds). The stale key is
// read for one purpose -- so that startup can SAY the file is being ignored.
//
// True means "the file asks for memory off". Absent key reads as false: nothing to warn about.
func AiNpcLegacyMemoryDisabled() -> Bool {
    let storage = AiNpcStorageService.GetPersistentStorageSystem();
    if !IsDefined(storage) {
        return false;
    }
    return !storage.GetSettingBool("memoryEnabled", true);
}

// Whether a chronicle fold is rebuilt from the whole archive, or only extended. The two modes
// differ only in which slice of the archive the fold reads (AiNpcMemoryChronicleFrom):
//
//   on   the whole archive, previous paragraph NOT sent. Drift is zero by construction.
//   off  the previous chronicle plus what has been archived since. O(1) per fold -- and it
//        compounds: thirty folds, about three hundred turns at the measured 6.3 new facts
//        per compaction, is twenty-seven levels of summary-of-a-summary deep.
//
// ON is affordable because AiNpcMemoryMaxArchive caps the archive: ~200 entries at the
// observed median is ~6 000 tokens once per roughly thirty turns, about 8% of what the
// speaking lane spends over the same span, and it does not grow after that. OFF stays worth
// having for a metered endpoint, and the choice is reversible -- the archive is kept, so
// turning it back on repairs whatever the cheap mode accumulated.
func AiNpcMemoryChronicleExact() -> Bool {
    let storage = AiNpcStorageService.GetPersistentStorageSystem();
    if !IsDefined(storage) {
        return true;
    }
    return storage.GetSettingBool("memoryChronicleExact", true);
}

// A journal pointer such as "b14:467", or "" -- the repair hatch, meant to be deleted again
// once it has done its work.
//
// A savegame's conversation pointer lives inside the savegame, where no tool can reach it:
// when a later save is lost and play resumes from an earlier one, the chats rewind with it.
// This aims them forward from inside; AiNpcConversationStore.ApplyImport does the work.
func AiNpcImportPointerSetting() -> String {
    return AiNpcGetSetting("importConversationsFrom", "");
}
