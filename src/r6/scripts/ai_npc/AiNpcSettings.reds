// Everything the mod reads from settings.json: the answers it cannot work out for itself and
// has to be told. Keeping them together is what keeps a credential accessor out of the prompt
// files, where a key ends up in something that gets pasted into a bug report.

module AiNpc

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

// The two per-request knobs, both read as text and both meaning "say nothing" when unset.
//
// UNSET BY DEFAULT, from measurement: across 31 runs on two providers every reply came back
// with finish_reason "stop", completions from 282 to 1976 tokens. The only way to truncate a
// reply today is a cap of the mod's own, and a cap set too low cuts the last thing in a
// message -- exactly where an [ACTION:...] command sits.
func AiNpcGetMaxTokens() -> Int32 {
    return StringToInt(AiNpcGetSetting("maxTokens", "0"));
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
