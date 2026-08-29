module AiNpc

import RedFileSystem.*
import Codeware.*
import RedData.Json.*

// Persistent storage for ai_npc.
//
// Files live in  <game>\r6\storages\AiNpc\ :
//   settings.json         - API keys / model / provider (user-editable, never shipped filled in)
//   journal.index.json    - conversation branch registry (see AiNpcJournal.reds)
//   journal.b<N>.jsonl    - the conversation journals themselves
//   journal.sessions.json - which playthrough sits on which branch (offline tools only)
//
// settings.json is created with safe defaults on first run, so a fresh install needs no
// manual setup; the journal files appear on the first message.
public class AiNpcStorageService extends ScriptableService {

    // RedFileSystem validates storage names against [A-Za-z]{3,24}: letters only, no
    // digits, no underscore. The mod's own folder name, "ai_npc", is rejected outright and
    // takes the whole service down with it -- self-tests included. Hence "AiNpc".
    private const let MOD_STORAGE_NAME: String = "AiNpc";
    private const let SETTINGS_FILE: String = "settings.json";

    // Deliberately not `persistent`: a ScriptableService is not part of the savegame, so
    // the keyword would only suggest that the handle survives a load. It does not, and it
    // does not need to -- FileSystem.GetStorage reopens it every session.
    private let m_storage: ref<FileSystemStorage>;
    private let m_settings: ref<JsonObject>;

    private cb func OnInitialize() {
        // Unconditional, and first: this is the line that answers "which build is
        // actually running?" when a report comes in, and it has to survive the storage
        // failing to open. FTLog rather than AiNpcLog, so it does not depend on the
        // in-game logging toggle being on.
        FTLog(s"[ai_npc]: version \(AiNpcVersion()) starting.");

        this.m_storage = FileSystem.GetStorage(this.MOD_STORAGE_NAME);

        if IsDefined(this.m_storage) {
            this.EnsureSettingsFile();
            FTLog(s"[ai_npc]: storage '\(this.MOD_STORAGE_NAME)' ready.");
        } else {
            FTLogError(s"[ai_npc]: FATAL: could not open storage '\(this.MOD_STORAGE_NAME)'. Is RedFileSystem installed?");
        }

        // Announced, not performed: the storage handle is settled here, and what happens on
        // the other side depends on the build (AiNpcSelfTest.reds). Called even when the
        // storage failed to open -- the tests need none of it, and a broken install is
        // exactly when their output matters.
        AiNpcRunSelfTests(this.m_storage);
    }

    public func GetFileStorage() -> ref<FileSystemStorage> {
        return this.m_storage;
    }

    /// Settings ///

    // Creates settings.json with placeholder values if it is missing or unreadable.
    private func EnsureSettingsFile() -> Void {
        let existing = this.ReadJsonObject(this.SETTINGS_FILE);

        if IsDefined(existing) {
            this.m_settings = existing;
            return;
        }

        let defaults = ParseJson(
            "{" +
            "\"openRouterApiKey\": \"\"," +
            "\"openRouterModel\": \"google/gemma-4-31b-it:free\"," +
            "\"openRouterProvider\": \"Auto\"," +
            // The CLI lanes carry no key: they run a CLI the player has already signed into.
            // The two paths are empty because empty means "search PATH", which is right on
            // most machines; the setup step fills them in when it has resolved one, so the
            // plugin never has to guess twice. ai_npc.dll reads them from this same file.
            "\"claudeCliModel\": \"sonnet\"," +
            "\"claudeCliPath\": \"\"," +
            "\"codexCliModel\": \"\"," +
            "\"codexCliPath\": \"\"," +
            // memoryEnabled is NOT written here: the switch is in Mod Settings, and a file
            // offering a key nobody reads teaches the wrong place to look. An old one left in
            // an existing settings.json is ignored, and startup says so once.
            // memoryChronicleExact stays because the menu has no way to ask it.
            "\"memoryChronicleExact\": true," +
            // Both off by default and both sent only when set -- see AiNpcGetMaxTokens.
            // maxTokens bounds a runaway completion; 0 sends no limit at all, which is what
            // every provider measured so far behaves correctly without.
            // reasoningEffort is "low" | "medium" | "high" on the backends that take it.
            "\"maxTokens\": 0," +
            "\"reasoningEffort\": \"\"," +
            // What V looks like, in the player's own words. APPENDED to the life path and the
            // gender, which are read from the save. Empty by default: the mod says nothing
            // about V's looks until the player has.
            "\"appearance\": \"\","+
            // The same description, but REPLACING the whole section instead of adding to it.
            // The escape hatch for a mod or a player who needs the life path gone too.
            "\"playerDescription\": \"\"" +
            "}") as JsonObject;

        this.m_settings = defaults;
        this.m_storage.GetFile(this.SETTINGS_FILE).WriteJson(defaults, "    ");
        FTLog(s"[ai_npc]: created default \(this.SETTINGS_FILE) - add your API key there.");
    }

    // Reads a settings value, falling back when the key is absent or empty.
    public func GetSetting(key: String, fallback: String) -> String {
        if !IsDefined(this.m_settings) {
            this.EnsureSettingsFile();
        }
        if !IsDefined(this.m_settings) || !this.m_settings.HasKey(key) {
            return fallback;
        }

        let value = this.m_settings.GetKeyString(key);
        if Equals(StrLen(value), 0) {
            return fallback;
        }
        return value;
    }

    // A setting that is a yes/no, read the way a player is likely to have written it: both
    // `false` and `"false"` mean off. GetSetting alone cannot serve this -- GetKeyString
    // returns "" for a JSON boolean, which reads as "absent" and falls back to the default,
    // so switching a feature off with the obvious syntax would leave it on.
    public func GetSettingBool(key: String, fallback: Bool) -> Bool {
        if !IsDefined(this.m_settings) {
            this.EnsureSettingsFile();
        }
        if !IsDefined(this.m_settings) || !this.m_settings.HasKey(key) {
            return fallback;
        }

        let value = this.m_settings.GetKey(key);
        if !IsDefined(value) || value.IsUndefined() {
            return fallback;
        }
        if value.IsBool() {
            return value.GetBool();
        }
        if value.IsString() {
            let text = value.GetString();
            if Equals(text, "false") || Equals(text, "False") || Equals(text, "FALSE") || Equals(text, "0") {
                return false;
            }
            if Equals(text, "true") || Equals(text, "True") || Equals(text, "TRUE") || Equals(text, "1") {
                return true;
            }
        }
        return fallback;
    }

    // Re-reads settings.json from disk, so key edits apply without restarting the game.
    public func ReloadSettings() -> Void {
        let reloaded = this.ReadJsonObject(this.SETTINGS_FILE);
        if IsDefined(reloaded) {
            this.m_settings = reloaded;
        }
    }

    // Writes one setting back to settings.json, leaving every other key exactly as it was.
    //
    // The object written is the one already in memory: nothing is rebuilt from a list of known
    // keys, so a key this build has never heard of survives the write. It does NOT merge --
    // whoever wrote last owns the file, and ReloadSettings is how the other side is picked up.
    //
    // Stored as a string even for values that read as numbers or booleans: GetSetting is a
    // string accessor and GetSettingBool already reads "false" as well as false, so a file
    // written by hand and a file written by code cannot disagree.
    public func SetSetting(key: String, value: String) -> Bool {
        if Equals(StrLen(key), 0) {
            return false;
        }
        if !IsDefined(this.m_settings) {
            this.EnsureSettingsFile();
        }
        if !IsDefined(this.m_settings) {
            return false;
        }

        this.m_settings.SetKeyString(key, value);
        return this.WriteSettings();
    }

    // Same, for a setting that is a yes/no. Written as a real JSON boolean rather than as
    // the string "true": both are read correctly, and the file stays the shape the README
    // documents for anyone who opens it afterwards.
    public func SetSettingBool(key: String, value: Bool) -> Bool {
        if Equals(StrLen(key), 0) {
            return false;
        }
        if !IsDefined(this.m_settings) {
            this.EnsureSettingsFile();
        }
        if !IsDefined(this.m_settings) {
            return false;
        }

        this.m_settings.SetKeyBool(key, value);
        return this.WriteSettings();
    }

    private func WriteSettings() -> Bool {
        if !IsDefined(this.m_storage) {
            return false;
        }
        let file = this.m_storage.GetFile(this.SETTINGS_FILE);
        if !IsDefined(file) {
            return false;
        }
        file.WriteJson(this.m_settings, "    ");
        return true;
    }

    /// Helpers ///

    // Returns null when the file is missing or does not contain a JSON object.
    private func ReadJsonObject(fileName: String) -> ref<JsonObject> {
        if !IsDefined(this.m_storage) {
            return null;
        }
        if NotEquals(this.m_storage.Exists(fileName), FileSystemStatus.True) {
            return null;
        }

        let file = this.m_storage.GetFile(fileName);
        if !IsDefined(file) {
            return null;
        }

        let json = file.ReadAsJson();
        if !IsDefined(json) || json.IsUndefined() || !json.IsObject() {
            return null;
        }

        return json as JsonObject;
    }

    public static func GetPersistentStorageSystem() -> ref<AiNpcStorageService> {
        return GameInstance.GetScriptableServiceContainer().GetService(NameOf<AiNpcStorageService>()) as AiNpcStorageService;
    }
}

// The shared r6\storages\AiNpc\ folder, or null before the service has settled.
//
// Written out four times before this existed -- the config loader, the conversation store, the
// usage ledger, and the public AiNpcSharedStorage, which its own header forbids from holding
// logic. Four copies of a null check is four chances to write the fifth one without it, and
// the answer here is the same for every caller: no service, no folder, and nothing crashes for
// having asked outside a session.
public func AiNpcModStorage() -> ref<FileSystemStorage> {
    let service = AiNpcStorageService.GetPersistentStorageSystem();
    if !IsDefined(service) {
        return null;
    }
    return service.GetFileStorage();
}
