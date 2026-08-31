// Loading character files and prompts.json, and saying loudly when they are wrong.
//
// Character text on disk is what lets a bio be edited without recompiling, and what lets a
// third-party contact have one at all. The price is the compiler: a sheet in cast\ is
// checked, a JSON file is not -- and a malformed one must never degrade quietly, because a
// model handed a truncated prompt still answers, just worse. So:
//
//   * a file is read onto a copy of the shipped sheet, key by key, so it overrides the
//     character and never replaces them. A file that fails to load costs its overrides only;
//   * every problem is collected, logged through FTLogError and written to
//     config-report.json;
//   * unknown keys are reported, because a typo in a key name is the likeliest edit mistake
//     and the hardest to notice.
//
// Files, all flat in the storage root, since RedFileSystem storages are not browsed
// recursively:
//
//   prompts.json              world / rules / interactions / language overrides
//   recipes.json              what the system prompt renders, block by block
//   recipes.example.json      rewritten every launch: the template, and the mod's own default
//   characters.builtin.json   optional overrides for the characters shipped with the mod
//   characters.<mod>.json     dropped in by another mod, or by hand
//   characters.user.json      always applied last, so a hand edit wins over any mod
//   characters.example.json   rewritten every launch, never loaded: live schema doc
//   config-report.json        written every launch: what loaded, what was rejected
//
// It fills in AiNpcCharacterDef, the same class the shipped cast is written in, so there is
// one character shape and not two.
module AiNpc

import RedFileSystem.*
import RedData.Json.*

/// Service ///

public class AiNpcConfigService extends ScriptableService {

    private const let PROMPTS_FILE: String = "prompts.json";
    private const let EXAMPLE_FILE: String = "characters.example.json";
    private const let REPORT_FILE: String = "config-report.json";
    private const let CHARACTER_PREFIX: String = "characters.";
    private const let USER_FILE: String = "characters.user.json";
    private const let FACTS_PREFIX: String = "facts.";
    private const let FACTS_USER_FILE: String = "facts.user.json";
    private const let FACTS_EXAMPLE_FILE: String = "facts.example.json";

    private let m_loaded: Bool = false;
    private let m_defs: array<ref<AiNpcCharacterDef>>;
    private let m_watches: array<ref<AiNpcFactWatch>>;
    private let m_prompts: ref<AiNpcPromptConfig>;
    private let m_recipe: ref<AiNpcRecipe>;
    private let m_book: ref<AiNpcRecipeBook>;
    private let m_passes: array<ref<AiNpcPassBinding>>;
    private let m_issues: array<ref<AiNpcConfigIssue>>;
    private let m_errors: Int32 = 0;
    private let m_warnings: Int32 = 0;

    private cb func OnInitialize() {
        // Best effort: loading is idempotent and lazy-safe, so the first real lookup does it
        // instead when the storage service is not up. Service order is not guaranteed.
        this.EnsureLoaded();
    }

    public static func Get() -> ref<AiNpcConfigService> {
        return GameInstance.GetScriptableServiceContainer().GetService(NameOf<AiNpcConfigService>()) as AiNpcConfigService;
    }

    /// Accessors ///

    public func GetCharacterDefs() -> array<ref<AiNpcCharacterDef>> {
        this.EnsureLoaded();
        return this.m_defs;
    }

    public func GetPrompts() -> ref<AiNpcPromptConfig> {
        this.EnsureLoaded();
        return this.m_prompts;
    }

    // What a pass renders with, and the only way a recipe leaves this service: the active one
    // is not offered, because a caller that could ask for it could render one pass under
    // another's. Both answers fall back the way an absent `passes` block does: the active
    // recipe, and the dialogue slot.
    public func GetPassRecipe(pass: String) -> ref<AiNpcRecipe> {
        this.EnsureLoaded();
        let binding = AiNpcPassBindingNamed(this.m_passes, pass);
        let named = AiNpcRecipeBookNamed(this.m_book, binding.recipeName);
        if IsDefined(named) {
            return named;
        }
        return this.m_recipe;
    }

    public func GetPassSlotName(pass: String) -> String {
        this.EnsureLoaded();
        return AiNpcPassSlotNameIn(this.m_passes, pass);
    }

    // The book as loaded, for a preset deciding which recipe names it may write.
    public func GetRecipeBook() -> ref<AiNpcRecipeBook> {
        this.EnsureLoaded();
        return this.m_book;
    }

    // Read once at player attach, by AiNpcFactBridge: a watch is only meaningful next to a
    // live listener and a baseline.
    public func GetFactWatches() -> array<ref<AiNpcFactWatch>> {
        this.EnsureLoaded();
        return this.m_watches;
    }

    // Whether a load happened, as opposed to being deferred because the storage was not open.
    // Callers that cache what they read must check it, or they cache a startup race.
    public func IsLoaded() -> Bool {
        return this.m_loaded;
    }

    public func GetErrorCount() -> Int32 {
        this.EnsureLoaded();
        return this.m_errors;
    }

    public func GetWarningCount() -> Int32 {
        this.EnsureLoaded();
        return this.m_warnings;
    }

    // One line fit for a log or an in-game diagnostic.
    public func GetStatusLine() -> String {
        this.EnsureLoaded();
        let defs = ArraySize(this.m_defs);
        if this.m_errors > 0 {
            return s"config DEGRADED: \(defs) character(s), \(this.m_errors) error(s), \(this.m_warnings) warning(s) - see \(this.REPORT_FILE)";
        }
        if this.m_warnings > 0 {
            return s"config ok with \(this.m_warnings) warning(s): \(defs) character(s) - see \(this.REPORT_FILE)";
        }
        // Only shown when there are watches: someone who has never declared one should not
        // learn what the word means from a status line.
        let watches = ArraySize(this.m_watches);
        if watches > 0 {
            return s"config ok: \(defs) character override(s), \(watches) fact watch(es)";
        }
        return s"config ok: \(defs) character override(s)";
    }

    // Re-reads every file, and touches no registered provider: swapping a live one under a
    // running conversation is worse than a session restart for character edits.
    public func Reload() -> Void {
        this.m_loaded = false;
        this.EnsureLoaded();
    }

    /// Loading ///

    private func EnsureLoaded() -> Void {
        if this.m_loaded {
            return;
        }

        let storage = AiNpcModStorage();
        if !IsDefined(storage) {
            // m_loaded is not latched here: this is reachable simply because the storage
            // service has not opened yet, and caching "no config" for the session would lose
            // every override. Retrying costs one null check per lookup.
            return;
        }

        this.m_loaded = true;

        ArrayClear(this.m_defs);
        ArrayClear(this.m_watches);
        ArrayClear(this.m_passes);
        ArrayClear(this.m_issues);
        this.m_errors = 0;
        this.m_warnings = 0;
        this.m_prompts = new AiNpcPromptConfig();
        this.m_recipe = AiNpcRecipeFull();

        this.WriteExampleFile(storage);
        this.WriteFactsExampleFile(storage);
        this.WriteRecipeTemplate(storage);
        this.LoadRecipes(storage);
        this.LoadPasses();
        this.LoadPrompts(storage);
        this.LoadCharacterFiles(storage);
        this.LoadFactFiles(storage);
        this.WriteReport(storage);
        this.LogSummary();
    }

    // The template is written first and then PARSED, and what comes out is the recipe the mod
    // renders with when there is no recipes.json. So the file a player copies and the default
    // they are copying are one text: a template that documented a default kept elsewhere would
    // be free to disagree with it, and nothing would ever say so.
    //
    // A player's file is read the same way, over the same built-in full render, so an absent
    // key keeps the mod's answer at both levels.
    private func LoadRecipes(storage: ref<FileSystemStorage>) -> Void {
        this.ReadRecipes(ParseJson(AiNpcRecipeTemplate()) as JsonObject, AiNpcRecipeTemplateFile());

        let root = this.ReadObject(storage, AiNpcRecipeFile());
        if IsDefined(root) {
            this.ReadRecipes(root, AiNpcRecipeFile());
            AiNpcLog(s"Loaded \(AiNpcRecipeFile()): rendering with recipe '\(this.m_recipe.name)'.");
        }
    }

    // The whole book is kept, not only the active recipe: a pass may name any recipe in the
    // file. A player's file REPLACES the template's book rather than adding to it, so a pass
    // naming a recipe that only the shipped template declares points at nothing -- and the
    // pass table says so, by name.
    private func ReadRecipes(root: ref<JsonObject>, fileName: String) -> Void {
        let issues: array<ref<AiNpcConfigIssue>>;
        let book = AiNpcRecipeBookFromJson(root, fileName, issues);

        let i = 0;
        let count = ArraySize(issues);
        while i < count {
            this.AddIssue(issues[i].severity, issues[i].source, issues[i].message);
            i += 1;
        }
        this.m_book = book;
        this.m_recipe = AiNpcRecipeBookActive(book);
    }

    // The pass table lives in settings.json, beside the slots it names: what a request is sent
    // with is one file, and what it says is another. Read after the recipes, because half of
    // what it is checked against is the book.
    private func LoadPasses() -> Void {
        let issues: array<ref<AiNpcConfigIssue>>;
        let slots = AiNpcGetSettingObject("slots");
        AiNpcSlotReportShapes(slots, AiNpcSettingsFile(), issues);
        this.m_passes = AiNpcPassTableFromJson(AiNpcGetSettingObject("passes"),
            AiNpcSettingsFile(), slots, this.m_book, issues);

        let i = 0;
        let count = ArraySize(issues);
        while i < count {
            this.AddIssue(issues[i].severity, issues[i].source, issues[i].message);
            i += 1;
        }
    }

    private func LoadPrompts(storage: ref<FileSystemStorage>) -> Void {
        let root = this.ReadObject(storage, this.PROMPTS_FILE);
        if !IsDefined(root) {
            return;
        }

        let allowed = [
            "version", "interactions", "worldBackground", "worldMechanics",
            "rules", "speechStyle", "languages"
        ];
        this.ReportUnknownKeys(root, allowed, this.PROMPTS_FILE, "");

        this.m_prompts.interactions = this.ReadRules(root, "interactions", "interactions", this.PROMPTS_FILE, "");
        this.m_prompts.worldBackground = this.ReadPromptString(root, "worldBackground", this.PROMPTS_FILE);
        this.m_prompts.worldMechanics = this.ReadPromptString(root, "worldMechanics", this.PROMPTS_FILE);
        this.m_prompts.rules = this.ReadRules(root, "rules", "system_rules", this.PROMPTS_FILE, "");
        this.RefuseGuidelines(root, this.PROMPTS_FILE, "");
        this.m_prompts.speechStyle = this.ReadPromptString(root, "speechStyle", this.PROMPTS_FILE);


        let languages = root.GetKey("languages") as JsonObject;
        if IsDefined(languages) {
            let known = AiNpcLanguageNames();
            let names = languages.GetKeys();
            let i = 0;
            let count = ArraySize(names);
            while i < count {
                if !ArrayContains(known, names[i]) {
                    this.AddIssue("warning", this.PROMPTS_FILE,
                        s"languages.\(names[i]) is not a known language; it will never be used.");
                } else {
                    ArrayPush(this.m_prompts.languages, names[i]);
                    ArrayPush(this.m_prompts.languageTexts,
                        this.ReadPromptString(languages, names[i], this.PROMPTS_FILE));
                }
                i += 1;
            }
        }

        AiNpcLog(s"Loaded \(this.PROMPTS_FILE).");
    }

    private func LoadCharacterFiles(storage: ref<FileSystemStorage>) -> Void {
        let names = this.CollectFileNames(storage, this.CHARACTER_PREFIX, this.USER_FILE, this.EXAMPLE_FILE);
        let i = 0;
        let count = ArraySize(names);
        while i < count {
            this.LoadCharacterFile(storage, names[i]);
            i += 1;
        }
    }

    // Alphabetical, with the user file forced last. Order decides who wins an id clash, so it
    // cannot be left to whatever sequence the filesystem returns. The family is an argument
    // rather than a name, because a second copy pinned to "facts." is a second place for the
    // ordering guarantee to stop being true.
    private func CollectFileNames(storage: ref<FileSystemStorage>, prefix: String, userFile: String,
            exampleFile: String) -> array<String> {
        let names: array<String>;
        let files = storage.GetFiles();
        let i = 0;
        let count = ArraySize(files);
        while i < count {
            let name = files[i].GetFilename();
            if StrBeginsWith(name, prefix)
                && StrEndsWith(name, ".json")
                && NotEquals(name, exampleFile)
                && NotEquals(name, userFile) {
                ArrayPush(names, name);
            }
            i += 1;
        }

        let sorted = AiNpcSortStrings(names);
        if Equals(storage.Exists(userFile), FileSystemStatus.True) {
            ArrayPush(sorted, userFile);
        }
        return sorted;
    }

    private func LoadCharacterFile(storage: ref<FileSystemStorage>, fileName: String) -> Void {
        let root = this.ReadObject(storage, fileName);
        if !IsDefined(root) {
            return;
        }

        let allowed = ["version", "characters"];
        this.ReportUnknownKeys(root, allowed, fileName, "");

        let list = root.GetKey("characters") as JsonArray;
        if !IsDefined(list) {
            this.AddIssue("error", fileName, "missing or non-array \"characters\"; file ignored.");
            return;
        }

        let loaded = 0;
        let i: Uint32 = 0u;
        while i < list.GetSize() {
            let entry = list.GetItem(i) as JsonObject;
            if !IsDefined(entry) {
                this.AddIssue("error", fileName, s"characters[\(i)] is not an object; entry ignored.");
            } else {
                if this.LoadCharacter(entry, fileName, Cast<Int32>(i)) {
                    loaded += 1;
                }
            }
            i += 1u;
        }

        AiNpcLog(s"Loaded \(loaded) character(s) from \(fileName).");
    }

    private func LoadCharacter(entry: ref<JsonObject>, fileName: String, index: Int32) -> Bool {
        let allowed = [
            "contactId", "displayName", "bio", "relationship", "romance",
            "liveContext", "speechStyle", "intent", "prompts", "romanceable", "romanced",
            "suppressActions", "tags", "allowsMemory", "seedFacts", "enabled", "variants",
            "questContexts", "questIntents", "actions", "comment"
        ];
        this.ReportUnknownKeys(entry, allowed, fileName, s"characters[\(index)].");

        let contactId = entry.GetKeyString("contactId");
        if Equals(StrLen(contactId), 0) {
            this.AddIssue("error", fileName, s"characters[\(index)] has no \"contactId\"; entry ignored.");
            return false;
        }
        if StrContains(contactId, " ") {
            this.AddIssue("error", fileName,
                s"contactId \"\(contactId)\" contains a space; it can never match a phone contact. Entry ignored.");
            return false;
        }

        if entry.HasKey("enabled") && !entry.GetKeyBool("enabled") {
            this.AddIssue("info", fileName, s"\(contactId) is disabled; skipped.");
            return false;
        }

        // From a copy of the shipped sheet, so a key the file does not carry keeps what the
        // character had. Every assignment below is guarded by HasKey for the same reason: an
        // absent key must not read back as "" and blank a bio.
        let def = AiNpcCopySheet(AiNpcBuiltinSheet(contactId));
        def.contactId = contactId;
        def.source = fileName;

        // Before any prompt text: every string below is checked for action tags no parser
        // handles, and the tags this character declares have to be known by then, or its own
        // bio reports its own commands as broken.
        this.LoadActions(entry, def, fileName);

        if entry.HasKey("displayName") { def.displayName = entry.GetKeyString("displayName"); }
        if entry.HasKey("bio") { def.bio = this.ReadCharacterString(entry, "bio", def, fileName); }
        if entry.HasKey("relationship") {
            def.relationship = this.ReadCharacterString(entry, "relationship", def, fileName);
        }
        if entry.HasKey("romance") {
            def.romance = this.ReadCharacterString(entry, "romance", def, fileName);
        }
        if entry.HasKey("liveContext") {
            def.liveContext = this.ReadCharacterString(entry, "liveContext", def, fileName);
        }
        if entry.HasKey("speechStyle") {
            def.speechStyle = this.ReadCharacterString(entry, "speechStyle", def, fileName);
        }
        if entry.HasKey("intent") {
            def.intent = this.ReadCharacterString(entry, "intent", def, fileName);
        }
        if entry.HasKey("romanceable") { def.romanceable = entry.GetKeyBool("romanceable"); }
        if entry.HasKey("romanced") { def.romanced = entry.GetKeyBool("romanced"); }
        if entry.HasKey("suppressActions") {
            def.suppressActions = this.ReadRawStringArray(entry, "suppressActions");
        }
        if entry.HasKey("tags") { def.tags = this.ReadRawStringArray(entry, "tags"); }
        if entry.HasKey("allowsMemory") { def.allowsMemory = entry.GetKeyBool("allowsMemory"); }
        if entry.HasKey("seedFacts") { def.seedFacts = this.ReadStringArray(entry, "seedFacts"); }
        def.enabled = true;

        if Equals(StrLen(def.displayName), 0) {
            this.AddIssue("warning", fileName,
                s"\(contactId) has no \"displayName\"; the shipped name is kept, or \"Unknown\" for a new contact.");
        }
        if Equals(StrLen(def.bio), 0) && !AiNpcIsBuiltinContactId(contactId) {
            this.AddIssue("warning", fileName,
                s"\(contactId) is a new contact with no \"bio\"; the model will be told almost nothing about it.");
        }
        if Equals(StrLen(def.romance), 0) && def.romanceable {
            this.AddIssue("warning", fileName,
                s"\(contactId) is romanceable but has no \"romance\"; a playthrough that romanced it reads exactly like one that did not.");
        }

        this.LoadPromptOverrides(entry, def, fileName);
        this.LoadVariants(entry, def, fileName);
        this.LoadQuestContexts(entry, def, fileName);
        this.LoadQuestIntents(entry, def, fileName);
        this.AddOrReplaceDef(def, fileName);
        return true;
    }

    // Commands this character may emit, and the fact each one sets. Every check refuses rather
    // than repairs, and each refusal drops one action rather than the character: a command that
    // cannot work is a bracket in front of the player, and guessing what a malformed one meant
    // would put it there on purpose.
    private func LoadActions(entry: ref<JsonObject>, def: ref<AiNpcCharacterDef>, fileName: String) -> Void {
        let list = entry.GetKey("actions") as JsonArray;
        if !IsDefined(list) {
            if entry.HasKey("actions") {
                this.AddIssue("error", fileName,
                    s"\(def.contactId): \"actions\" is not an array; ignored.");
            }
            return;
        }

        // Declaring any replaces the shipped set, as variants and quest contexts do: an
        // override cannot be shadowed by a built-in command it never saw.
        ArrayClear(def.actions);

        let i: Uint32 = 0u;
        while i < list.GetSize() {
            let raw = list.GetItem(i) as JsonObject;
            let where = s"\(def.contactId).actions[\(i)]";
            if !IsDefined(raw) {
                this.AddIssue("error", fileName, s"\(where) is not an object; ignored.");
            } else {
                let declared = AiNpcActionsTags(def.actions);
                let action = this.ReadAction(raw, where, declared, fileName);
                if IsDefined(action) {
                    ArrayPush(def.actions, action);
                }
            }
            i += 1u;
        }
    }

    // One declaration, or null with the reason reported. Separate from the loop so each refusal
    // is a return rather than another level of else: redscript has no `continue`.
    private func ReadAction(raw: ref<JsonObject>, where: String, declared: array<String>,
                            fileName: String) -> ref<AiNpcActionDef> {
        this.ReportUnknownKeys(raw, ["tag", "prompt", "fact", "value", "comment"], fileName, where + ".");

        let tag = raw.GetKeyString("tag");
        if !AiNpcActionTagIsWellFormed(tag) {
            this.AddIssue("error", fileName,
                s"\(where) has tag \"\(tag)\", which is not shaped like [ACTION:NAME]; action dropped.");
            return null;
        }
        // A sheet declares a command, never a form. A slot would hand the effect a field this
        // file cannot validate, and the only effect a sheet has is writing a fixed fact -- so
        // the field would be read by nobody and the model taught to fill it for nothing.
        if StrContains(tag, "{") {
            this.AddIssue("error", fileName,
                s"\(where) has tag \"\(tag)\", which carries a {slot}; a character file declares a command, not a form. Action dropped.");
            return null;
        }
        if ArrayContains(declared, tag) {
            this.AddIssue("error", fileName,
                s"\(where) declares \(tag) a second time; the duplicate is dropped.");
            return null;
        }

        let fact = raw.GetKeyString("fact");
        if !AiNpcActionFactIsWritable(fact) {
            let namespace = AiNpcActionFactNamespace();
            this.AddIssue("error", fileName,
                s"\(where) sets fact \"\(fact)\"; a character file may only write facts starting with \"\(namespace)\", which is what keeps a command from reaching vanilla quest state. Action dropped.");
            return null;
        }

        let prompt = raw.GetKeyString("prompt");
        if Equals(StrLen(prompt), 0) {
            this.AddIssue("error", fileName,
                s"\(where) has no \"prompt\"; the model would be handed a command with no trigger and emit it at random. Action dropped.");
            return null;
        }

        let action = AiNpcAction(tag, prompt, fact);
        if raw.HasKey("value") {
            action.value = Cast<Int32>(raw.GetKeyInt64("value"));
        }
        return action;
    }

    // Whole sections of the system prompt, replaced for this contact only. Null when absent, so
    // the common entry costs nothing and every section keeps resolving down the chain.
    private func LoadPromptOverrides(entry: ref<JsonObject>, def: ref<AiNpcCharacterDef>, fileName: String) -> Void {
        let raw = entry.GetKey("prompts") as JsonObject;
        if !IsDefined(raw) {
            if entry.HasKey("prompts") {
                this.AddIssue("error", fileName,
                    s"\(def.contactId): \"prompts\" is not an object; overrides ignored.");
            }
            return;
        }

        let allowed = [
            "rules", "interactions", "worldBackground", "playerDescription",
            "worldMechanics", "language", "comment"
        ];
        this.ReportUnknownKeys(raw, allowed, fileName, s"\(def.contactId).prompts.");

        let over = new AiNpcPromptOverrides();
        over.rules = this.ReadRules(raw, "rules", "system_rules", fileName, s"\(def.contactId).prompts.");
        over.interactions = this.ReadRules(raw, "interactions", "interactions", fileName, s"\(def.contactId).prompts.");
        this.RefuseGuidelines(raw, fileName, s"\(def.contactId).prompts.");
        over.worldBackground = this.ReadPromptString(raw, "worldBackground", fileName);
        // Contact level only: the global answer is settings.json "playerDescription".
        over.playerDescription = this.ReadPromptString(raw, "playerDescription", fileName);
        over.worldMechanics = this.ReadPromptString(raw, "worldMechanics", fileName);
        over.language = this.ReadPromptString(raw, "language", fileName);


        def.prompts = over;
    }

    private func LoadVariants(entry: ref<JsonObject>, def: ref<AiNpcCharacterDef>, fileName: String) -> Void {
        let list = entry.GetKey("variants") as JsonArray;
        if !IsDefined(list) {
            return;
        }

        // A file that declares variants declares all of them: the inherited list is dropped
        // rather than appended to, so an override cannot be shadowed by one it never saw.
        ArrayClear(def.variants);

        let known = AiNpcVariantConditions();
        let i: Uint32 = 0u;
        while i < list.GetSize() {
            let raw = list.GetItem(i) as JsonObject;
            if !IsDefined(raw) {
                this.AddIssue("error", fileName, s"\(def.contactId): variants[\(i)] is not an object; ignored.");
            } else {
                let allowed = ["when", "bio", "relationship", "liveContext", "speechStyle",
                               "intent", "comment"];
                this.ReportUnknownKeys(raw, allowed, fileName, s"\(def.contactId).variants[\(i)].");

                let condition = raw.GetKeyString("when");
                if !ArrayContains(known, condition) {
                    // Dropped rather than defaulted: a variant whose condition is never true
                    // is invisible, and guessing which was meant would be worse.
                    let knownList = AiNpcJoinStrings(known, ", ");
                    this.AddIssue("error", fileName,
                        s"\(def.contactId): unknown variant condition '\(condition)'; variant dropped. Known: \(knownList).");
                } else {
                    let variant = new AiNpcCharacterVariant();
                    variant.when = condition;
                    variant.bio = this.ReadCharacterString(raw, "bio", def, fileName);
                    variant.relationship = this.ReadCharacterString(raw, "relationship", def, fileName);
                    variant.liveContext = this.ReadCharacterString(raw, "liveContext", def, fileName);
                    variant.speechStyle = this.ReadCharacterString(raw, "speechStyle", def, fileName);
                    variant.intent = this.ReadCharacterString(raw, "intent", def, fileName);
                    ArrayPush(def.variants, variant);
                }
            }
            i += 1u;
        }
    }

    // What this character says about a quest V is tracking, keyed by canonical quest name.
    // Declaring any replaces the shipped set, as variants do.
    private func LoadQuestContexts(entry: ref<JsonObject>, def: ref<AiNpcCharacterDef>, fileName: String) -> Void {
        let raw = this.QuestObjectAt(entry, "questContexts", def, fileName);
        if IsDefined(raw) {
            def.questContexts = this.ReadQuestLines(raw, "questContexts", def, fileName);
        }
    }

    // What this character wants while V is on a given quest, keyed the same way and read
    // through the same helpers, so the parsing rule changes in one place.
    private func LoadQuestIntents(entry: ref<JsonObject>, def: ref<AiNpcCharacterDef>, fileName: String) -> Void {
        let raw = this.QuestObjectAt(entry, "questIntents", def, fileName);
        if IsDefined(raw) {
            def.questIntents = this.ReadQuestLines(raw, "questIntents", def, fileName);
        }
    }

    // The object under `key`, or null, with a report when the key is there and is not one. Null
    // means "keep whatever the sheet had".
    private func QuestObjectAt(entry: ref<JsonObject>, key: String, def: ref<AiNpcCharacterDef>,
                               fileName: String) -> ref<JsonObject> {
        let raw = entry.GetKey(key) as JsonObject;
        if !IsDefined(raw) && entry.HasKey(key) {
            this.AddIssue("error", fileName, s"\(def.contactId): \"\(key)\" is not an object; ignored.");
        }
        return raw;
    }

    private func ReadQuestLines(raw: ref<JsonObject>, key: String, def: ref<AiNpcCharacterDef>,
                                fileName: String) -> array<ref<AiNpcQuestLine>> {
        let lines: array<ref<AiNpcQuestLine>>;
        let keys = raw.GetKeys();
        let i = 0;
        let count = ArraySize(keys);
        while i < count {
            let text = this.ReadCharacterString(raw, keys[i], def, fileName);
            if Equals(StrLen(text), 0) {
                this.AddIssue("warning", fileName,
                    s"\(def.contactId): \(key).\(keys[i]) is empty; nothing will be said about that quest.");
            } else {
                ArrayPush(lines, AiNpcQuest(keys[i], text));
            }
            i += 1;
        }
        return lines;
    }

    // Later files override earlier ones, per the documented load order.
    private func AddOrReplaceDef(def: ref<AiNpcCharacterDef>, fileName: String) -> Void {
        let i = 0;
        let count = ArraySize(this.m_defs);
        while i < count {
            if Equals(this.m_defs[i].contactId, def.contactId) {
                this.AddIssue("info", fileName,
                    s"\(def.contactId) overrides the definition from \(this.m_defs[i].source).");
                this.m_defs[i] = def;
                return;
            }
            i += 1;
        }
        ArrayPush(this.m_defs, def);
    }

    /// Fact watches ///

    private func LoadFactFiles(storage: ref<FileSystemStorage>) -> Void {
        let names = this.CollectFileNames(storage, this.FACTS_PREFIX, this.FACTS_USER_FILE, this.FACTS_EXAMPLE_FILE);
        let i = 0;
        let count = ArraySize(names);
        while i < count {
            this.LoadFactFile(storage, names[i]);
            i += 1;
        }
    }

    // Watches accumulate where characters override by id: a character sheet has a built-in
    // version to replace and a watch has nothing underneath it. Two entries on one fact are two
    // watches, which is also how an event is worded differently per character.
    private func LoadFactFile(storage: ref<FileSystemStorage>, fileName: String) -> Void {
        let root = this.ReadObject(storage, fileName);
        if !IsDefined(root) {
            return;
        }

        let allowed = ["version", "facts"];
        this.ReportUnknownKeys(root, allowed, fileName, "");

        let list = AiNpcJsonArrayAt(root, "facts");
        if !IsDefined(list) {
            this.AddIssue("error", fileName, "missing or non-array \"facts\"; file ignored.");
            return;
        }

        let loaded = 0;
        let i: Uint32 = 0u;
        while i < list.GetSize() {
            let entry = list.GetItem(i) as JsonObject;
            if !IsDefined(entry) {
                this.AddIssue("error", fileName, s"facts[\(i)] is not an object; entry ignored.");
            } else {
                if this.LoadFactWatch(entry, fileName, Cast<Int32>(i)) {
                    loaded += 1;
                }
            }
            i += 1u;
        }

        AiNpcLog(s"Loaded \(loaded) fact watch(es) from \(fileName).");
    }

    // Everything a bad declaration can be is caught here, because past this point a wrong watch
    // is silent: a fact nobody writes never fires, and there is only a character who never
    // mentions something.
    private func LoadFactWatch(entry: ref<JsonObject>, fileName: String, index: Int32) -> Bool {
        let where = s"facts[\(index)]";
        this.ReportUnknownKeys(entry, ["fact", "atLeast", "contacts", "event", "ackFact"], fileName, s"\(where).");

        let watch = new AiNpcFactWatch();
        watch.fact = AiNpcJsonString(entry, "fact");
        watch.event = AiNpcJsonString(entry, "event");
        watch.ackFact = AiNpcJsonString(entry, "ackFact");
        watch.contacts = this.ReadRawStringArray(entry, "contacts");
        watch.source = fileName;

        if Equals(StrLen(watch.fact), 0) {
            this.AddIssue("error", fileName, s"\(where) has no \"fact\"; entry ignored.");
            return false;
        }
        // A fact name becomes a CName, and one with a space matches no fact any quest graph can
        // set, so it would register cleanly and never fire.
        if StrContains(watch.fact, " ") {
            this.AddIssue("error", fileName,
                s"\(where) fact \"\(watch.fact)\" contains a space, so it can never match a real quest fact; entry ignored.");
            return false;
        }
        if Equals(StrLen(watch.event), 0) {
            this.AddIssue("error", fileName,
                s"\(where) watches \"\(watch.fact)\" but says nothing about it (\"event\" is empty); entry ignored.");
            return false;
        }
        // The sentence reaches the model untouched, which is the contract -- so it is checked
        // here, once, rather than trusted there: a tag inside it would close <now>.
        let unsafe = AiNpcSectionRefusal(watch.event);
        if NotEquals(StrLen(unsafe), 0) {
            this.AddIssue("error", fileName, s"\(where) event refused: \(unsafe). Entry ignored.");
            return false;
        }
        if Equals(ArraySize(watch.contacts), 0) {
            this.AddIssue("error", fileName,
                s"\(where) watches \"\(watch.fact)\" with an empty \"contacts\" list, so nobody would ever hear it; entry ignored.");
            return false;
        }

        // Whether these contact ids exist is not checked: providers register during the
        // session, long after this runs, so a warning would fire on every correct watch naming
        // another mod's contact. The report lists what each is addressed to instead.

        if entry.HasKey("atLeast") {
            watch.atLeast = Cast<Int32>(entry.GetKeyInt64("atLeast"));
        }
        // A threshold at or below zero can never be crossed from below, since a fact never
        // reads less than zero, so the watch would register and stay mute. Clamped rather than
        // rejected, because "fire when it is set" is what was meant.
        if watch.atLeast < 1 {
            this.AddIssue("warning", fileName,
                s"\(where) has atLeast \(watch.atLeast), which could never fire; using 1.");
            watch.atLeast = 1;
        }

        if StrContains(watch.ackFact, " ") {
            this.AddIssue("warning", fileName,
                s"\(where) ackFact \"\(watch.ackFact)\" contains a space; no acknowledgement will be written.");
            watch.ackFact = "";
        }

        ArrayPush(this.m_watches, watch);
        return true;
    }

    /// Reading + validation helpers ///

    // Reads a string and checks any action tag it advertises against the parser: a tag the
    // parser does not know is not stripped from the reply and leaks verbatim into the chat.
    // <system_rules> by rubric. Every refusal is reported here rather than at build time, so
    // an author reads about it in the config report instead of wondering why the text never
    // appears -- and the reasons come from AiNpcRuleRefusal, which the composer uses too. One
    // list of refusals, not two that drift.
    private func ReadRules(owner: ref<JsonObject>, key: String, block: String,
                           fileName: String, prefix: String) -> array<ref<AiNpcRule>> {
        let taken: array<ref<AiNpcRule>>;
        let raw = owner.GetKey(key) as JsonObject;
        if !IsDefined(raw) {
            if owner.HasKey(key) {
                this.AddIssue("error", fileName, s"\(prefix)\(key) is not an object; ignored.");
            }
            return taken;
        }

        let keys = raw.GetKeys();
        let i = 0;
        let count = ArraySize(keys);
        while i < count {
            let rule = AiNpcRuleOf(keys[i], this.ReadPromptString(raw, keys[i], fileName));
            let refusal = AiNpcRuleRefusal(block, rule);
            if NotEquals(StrLen(refusal), 0) {
                this.AddIssue("error", fileName, s"\(prefix)\(key).\(keys[i]) refused: \(refusal). Ignored.");
            } else {
                if AiNpcRuleIndexOf(taken, rule.key) >= 0 {
                    this.AddIssue("warning", fileName,
                        s"\(prefix)\(key).\(keys[i]) names a rubric this file already set; the first one stands.");
                } else {
                    ArrayPush(taken, rule);
                }
            }
            i += 1;
        }
        return taken;
    }

    // Refused rather than migrated: it replaced the whole block, and a silent reinterpretation
    // as one rubric would leave a mod believing it still overrides rules it no longer touches.
    private func RefuseGuidelines(owner: ref<JsonObject>, fileName: String, prefix: String) -> Void {
        if owner.HasKey("guidelines") {
            this.AddIssue("error", fileName,
                s"\(prefix)guidelines is no longer read: <system_rules> is composed from rubrics and cannot be replaced whole. Move the text into \"rules\", one key per rubric.");
        }
    }

    private func ReadPromptString(owner: ref<JsonObject>, key: String, fileName: String) -> String {
        let none: array<String>;
        return this.ReadClaimingString(owner, key, fileName, none);
    }

    // The same read for a character that may have declared commands of its own: a tag it claims
    // is not unknown, so reporting one would tell an author their working command is broken.
    private func ReadCharacterString(owner: ref<JsonObject>, key: String, def: ref<AiNpcCharacterDef>,
                                     fileName: String) -> String {
        return this.ReadClaimingString(owner, key, fileName, AiNpcActionsTags(def.actions));
    }

    private func ReadClaimingString(owner: ref<JsonObject>, key: String, fileName: String,
                                    claimed: array<String>) -> String {
        if !owner.HasKey(key) {
            return "";
        }
        let value = owner.GetKeyString(key);
        if Equals(StrLen(value), 0) {
            return "";
        }

        let written = AiNpcFindActionTags(value);
        let i = 0;
        let count = ArraySize(written);
        while i < count {
            let tag = written[i];
            if !ArrayContains(claimed, tag) && !AiNpcActionHeadIsClaimed(tag) {
                this.AddIssue("error", fileName,
                    s"\(key) advertises \(tag), which no command matches; the model will emit it and it will show up as raw text in the chat.");
            }
            i += 1;
        }
        return value;
    }

    // A non-string entry is skipped rather than coerced: a number where an id belongs is a
    // mistake, and "3" would carry all the way to a lookup that matches nobody.
    private func ReadRawStringArray(owner: ref<JsonObject>, key: String) -> array<String> {
        let result: array<String>;
        let items = AiNpcJsonArrayAt(owner, key);
        if !IsDefined(items) {
            return result;
        }

        let i: Uint32 = 0u;
        while i < items.GetSize() {
            let item = items.GetItem(i);
            if IsDefined(item) && item.IsString() && NotEquals(StrLen(item.GetString()), 0) {
                ArrayPush(result, item.GetString());
            }
            i += 1u;
        }
        return result;
    }

    // Through the memory's own clamp, so a file cannot seed a paragraph where the rest of the
    // system stores a line.
    private func ReadStringArray(owner: ref<JsonObject>, key: String) -> array<String> {
        let result: array<String>;
        let raw = this.ReadRawStringArray(owner, key);
        let i = 0;
        let count = ArraySize(raw);
        while i < count {
            let entry = AiNpcMemoryClampEntry(raw[i]);
            if NotEquals(StrLen(entry), 0) {
                ArrayPush(result, entry);
            }
            i += 1;
        }
        return result;
    }

    private func ReportUnknownKeys(owner: ref<JsonObject>, allowed: array<String>, fileName: String, prefix: String) -> Void {
        let keys = owner.GetKeys();
        let i = 0;
        let count = ArraySize(keys);
        while i < count {
            // A leading underscore marks a comment: JSON has none, and characters.example.json
            // uses the convention, so copying it must not produce warnings about its own
            // annotations.
            if !StrBeginsWith(keys[i], "_") && !ArrayContains(allowed, keys[i]) {
                this.AddIssue("warning", fileName,
                    s"unknown key \"\(prefix)\(keys[i])\" is ignored. Check the spelling against \(this.EXAMPLE_FILE).");
            }
            i += 1;
        }
    }

    private func ReadObject(storage: ref<FileSystemStorage>, fileName: String) -> ref<JsonObject> {
        if NotEquals(storage.Exists(fileName), FileSystemStatus.True) {
            return null;
        }
        let file = storage.GetFile(fileName);
        if !IsDefined(file) {
            return null;
        }

        let raw = file.ReadAsJson();
        if !IsDefined(raw) || raw.IsUndefined() || !raw.IsObject() {
            this.AddIssue("error", fileName, "not valid JSON, or not a JSON object; file ignored entirely.");
            return null;
        }
        return raw as JsonObject;
    }

    private func AddIssue(severity: String, source: String, message: String) -> Void {
        let issue = new AiNpcConfigIssue();
        issue.severity = severity;
        issue.source = source;
        issue.message = message;
        ArrayPush(this.m_issues, issue);

        if Equals(severity, "error") {
            this.m_errors += 1;
        }
        if Equals(severity, "warning") {
            this.m_warnings += 1;
        }
    }

    /// Reporting ///

    private func LogSummary() -> Void {
        let i = 0;
        let count = ArraySize(this.m_issues);
        while i < count {
            let line = s"[ai_npc]: config \(this.m_issues[i].severity) in \(this.m_issues[i].source): \(this.m_issues[i].message)";
            // Through FTLogError: a config problem must be visible without the in-game logging
            // toggle, which is off by default and which nobody turns on before things break.
            if Equals(this.m_issues[i].severity, "info") {
                AiNpcLog(line);
            } else {
                FTLogError(line);
            }
            i += 1;
        }
        FTLog(s"[ai_npc]: \(this.GetStatusLine())");
    }

    private func WriteReport(storage: ref<FileSystemStorage>) -> Void {
        let issues = ParseJson("[]") as JsonArray;
        let i = 0;
        let count = ArraySize(this.m_issues);
        while i < count {
            let entry = ParseJson("{}") as JsonObject;
            entry.SetKeyString("severity", this.m_issues[i].severity);
            entry.SetKeyString("source", this.m_issues[i].source);
            entry.SetKeyString("message", this.m_issues[i].message);
            issues.AddItem(entry);
            i += 1;
        }

        let characters = ParseJson("[]") as JsonArray;
        let j = 0;
        let defCount = ArraySize(this.m_defs);
        while j < defCount {
            let entry = ParseJson("{}") as JsonObject;
            entry.SetKeyString("contactId", this.m_defs[j].contactId);
            entry.SetKeyString("displayName", this.m_defs[j].displayName);
            entry.SetKeyString("source", this.m_defs[j].source);
            entry.SetKeyBool("builtin", AiNpcIsBuiltinContactId(this.m_defs[j].contactId));
            entry.SetKeyInt64("variants", Cast<Int64>(ArraySize(this.m_defs[j].variants)));
            // Spelled out rather than counted: the difference between "declared three, kept
            // two" and "declared two" is the first thing to look at when one never fires.
            entry.SetKeyString("actions", AiNpcJoinStrings(AiNpcActionsTags(this.m_defs[j].actions), ", "));
            characters.AddItem(entry);
            j += 1;
        }

        // What each watch is addressed to. The only place a contact id typed into a watch can
        // be checked against reality, because the check cannot be made at load time.
        let facts = ParseJson("[]") as JsonArray;
        let k = 0;
        let watchCount = ArraySize(this.m_watches);
        while k < watchCount {
            let entry = ParseJson("{}") as JsonObject;
            entry.SetKeyString("fact", this.m_watches[k].fact);
            entry.SetKeyInt64("atLeast", Cast<Int64>(this.m_watches[k].atLeast));
            entry.SetKeyString("contacts", AiNpcJoinStrings(this.m_watches[k].contacts, ", "));
            entry.SetKeyString("ackFact", this.m_watches[k].ackFact);
            entry.SetKeyString("source", this.m_watches[k].source);
            facts.AddItem(entry);
            k += 1;
        }

        let root = ParseJson("{}") as JsonObject;
        root.SetKeyString("status", this.GetStatusLine());
        root.SetKeyInt64("errors", Cast<Int64>(this.m_errors));
        root.SetKeyInt64("warnings", Cast<Int64>(this.m_warnings));
        root.SetKey("characters", characters);
        root.SetKey("facts", facts);
        root.SetKey("issues", issues);

        storage.GetFile(this.REPORT_FILE).WriteJson(root, "    ");
    }

    // Overwritten every launch: it is documentation, not configuration, and stale documentation
    // of a schema is worse than none. Never read back.
    private func WriteExampleFile(storage: ref<FileSystemStorage>) -> Void {
        let text = "{\n" +
            "    \"version\": 1,\n" +
            "    \"_comment\": \"EXAMPLE ONLY - this file is rewritten at every launch and never loaded. Copy it to characters.user.json (yours, never overwritten) or characters.<yourmod>.json.\",\n" +
            "    \"_placeholders\": \"{they} {them} {their} {partner} {gender} {npc} {time} {vgender}, and the capitalised forms {They} {Them} {Their} {Partner}. They agree with V's gender, read from the character; {vgender} is a whole sentence stating that gender, written in the reply language and empty in English.\",\n" +
            "    \"_variantConditions\": \"" + AiNpcJoinStrings(AiNpcVariantConditions(), " | ") + "\",\n" +
            "    \"characters\": [\n" +
            "        {\n" +
            "            \"contactId\": \"panam\",\n" +
            "            \"displayName\": \"Panam Palmer\",\n" +
            "            \"bio\": \"Overrides the built-in bio. Omit any key to keep the built-in text.\",\n" +
            "            \"relationship\": \"How {they} sees V. Injected whether or not there is a romance.\",\n" +
            "            \"_romance\": \"ADDITIVE, and emitted only while V has romanced this character. Say what being together CHANGES -- the relationship above is injected either way, so a text that restates it is the same paragraph twice.\",\n" +
            "            \"romance\": \"V is your {partner} now, not just a friend.\",\n" +
            "            \"speechStyle\": \"Blunt, uses Night City slang, calls V 'choom'.\",\n" +
            "            \"romanceable\": true,\n" +
            "            \"_tags\": \"What this character IS. A command another mod scopes to one of these reaches this character without either side having heard of the other. Tags only ADD -- use suppressActions to take a command away.\",\n" +
            "            \"tags\": [\"nomad\"],\n" +
            "            \"enabled\": true,\n" +
            "            \"variants\": [\n" +
            "                { \"when\": \"postHeist\", \"bio\": \"Applied only after the heist.\" }\n" +
            "            ],\n" +
            "            \"_questContexts\": \"What this character says while V is tracking a given quest, keyed by the canonical quest name. The mod logs that name when it meets a quest it has no entry for. Write the account only, in the second person: the mod adds the quest title and what V is doing right now. Declaring any replaces the shipped set for this character.\",\n" +
            "            \"questContexts\": {\n" +
            "                \"riders_on_the_storm\": \"The Wraiths took Saul, and that is where you are going in after him. INSTRUCTION: ...\"\n" +
            "            },\n" +
            "            \"_questIntents\": \"What this character WANTS while V is tracking that quest, keyed the same way. It replaces 'intent' below for as long as the quest is tracked, and an absent entry changes nothing.\",\n" +
            "            \"questIntents\": {\n" +
            "                \"riders_on_the_storm\": \"You want V beside you when you take the camp back, and you will say so rather than ask.\"\n" +
            "            }\n" +
            "        },\n" +
            "        {\n" +
            "            \"contactId\": \"MyModContact01\",\n" +
            "            \"displayName\": \"Nadia\",\n" +
            "            \"bio\": \"A brand new contact. contactId MUST equal the contactId your mod puts on its ContactData.\",\n" +
            "            \"relationship\": \"You met V once, in Kabuki. You remember {them}.\",\n" +
            "            \"_speechStyle\": \"ADDITIVE, and the one you almost always want: appended to the rule block, so the built-in rules still apply. Say how this character SPEAKS -- register, form of address, verbal tics. Facts go in bio, mood in liveContext.\",\n" +
            "            \"speechStyle\": \"Formal and distant. Never uses slang.\",\n" +
            "            \"_prompts\": \"Rarely needed: the same keys as prompts.json, for this contact only. Omit a key to keep resolving prompts.json, then the built-in text. 'rules' and 'interactions' are objects keyed by rubric -- a known rubric is replaced where it stands, an unknown one is appended.\",\n" +
            "            \"prompts\": {\n" +
            "                \"interactions\": { \"REAL\": \"Replaces the REAL rubric of <interactions> for Nadia only.\" },\n" +
            "                \"playerDescription\": \"Replaces the <target> section: what THIS contact knows of V. For an unknown number, state the ignorance -- 'you have never met V' -- rather than leaving it empty.\",\n" +
            "                \"worldBackground\": \"Replaces the <world_background> section for Nadia only.\"\n" +
            "            },\n" +
            "            \"_romanced\": \"Your own contact only. For a built-in one -- Panam, Judy, River, Kerry -- the save answers instead and this key is ignored, so an override file cannot claim a romance the playthrough never had.\",\n" +
            "            \"romanced\": false,\n" +
            "            \"_suppressActions\": \"Commands this character refuses, named by the literal run before the first slot. Removes them from the prompt entirely rather than advertising a command that would then be refused. One-way: nothing grants them back. Use it when your own mod already does the thing.\",\n" +
            "            \"suppressActions\": [\"[ACTION:GIVE_EDDIES:\"],\n" +
            "            \"_seedFacts\": \"What this contact already knows about V before the first message. One line each; they are folded into the memory at its first compaction and then age like anything else it remembers.\",\n" +
            "            \"seedFacts\": [\"V once did a job for her brother and never got paid.\"],\n" +
            "            \"_allowsMemory\": \"false when the contact should not accumulate a relationship at all -- an automated number, a bot, a dead drop. Its conversation is then trimmed rather than remembered.\",\n" +
            "            \"allowsMemory\": true,\n" +
            "            \"_intent\": \"WHAT THIS CHARACTER WANTS FROM V, in one or two sentences, second person. bio says who they are and relationship how they see V; neither says what they are after, and a model given no intention invents a different one every message. Wanting, not knowing: 'You want V to take the Kabuki job' is an intent, 'You are worried about V' is a mood and belongs in liveContext.\",\n" +
            "            \"intent\": \"You want V to owe you a favour before this conversation ends, and you steer towards it.\",\n" +
            "            \"_actions\": \"Commands this character may emit. Each one sets a quest fact when it fires, and only a fact starting with ainpc_ -- that is what keeps a command a language model can be talked into from reaching vanilla quest state. Anything more than a fact means running code, which is a script provider (docs/API.md, Way 2). The tag is stripped from the message before the player sees it; the sentence around it is what tells them.\",\n" +
            "            \"actions\": [\n" +
            "                {\n" +
            "                    \"_tag\": \"Shaped like [ACTION:NAME], no spaces inside the brackets and no {slots}: a sheet declares a command, not a form, because data cannot validate what a field would carry.\",\n" +
            "                    \"tag\": \"[ACTION:OWES_FAVOUR]\",\n" +
            "                    \"_prompt\": \"WHEN to emit it, in the character's own terms. Required: a command with no trigger is one the model fires at random or never.\",\n" +
            "                    \"prompt\": \"Emit this when V agrees to owe you one.\",\n" +
            "                    \"fact\": \"ainpc_nadia_owed_favour\",\n" +
            "                    \"_value\": \"What the fact is set to. Optional, defaults to 1. Re-emitting the tag sets the same value again, which does nothing -- and a model does repeat itself.\",\n" +
            "                    \"value\": 1\n" +
            "                }\n" +
            "            ]\n" +
            "        }\n" +
            "    ]\n" +
            "}\n";
        storage.GetFile(this.EXAMPLE_FILE).WriteText(text);
    }

    // Same contract as WriteExampleFile, and one line because the text is not this file's: it
    // is the mod's own default recipe, and it lives with the parser that reads it.
    private func WriteRecipeTemplate(storage: ref<FileSystemStorage>) -> Void {
        storage.GetFile(AiNpcRecipeTemplateFile()).WriteText(AiNpcRecipeTemplate());
    }

    // Same contract as WriteExampleFile: rewritten every launch, never read back.
    private func WriteFactsExampleFile(storage: ref<FileSystemStorage>) -> Void {
        let text = "{\n" +
            "    \"version\": 1,\n" +
            "    \"_comment\": \"EXAMPLE ONLY - rewritten at every launch and never loaded. Copy it to facts.user.json (yours, never overwritten) or facts.<yourmod>.json.\",\n" +
            "    \"_what\": \"Each entry watches one quest fact. When another mod's quest, a scene, or a CET one-liner sets it, the named contacts are told what happened and react in their own voice the next time V texts them.\",\n" +
            "    \"_whenItFires\": \"On the CROSSING of atLeast, and only while you are playing: a fact already past the threshold when the save loads is not news, and writing the same value again is not news either.\",\n" +
            "    \"_findingFactNames\": \"Ask the mod's author, or watch the FactsDB from CET. Test yours from the console with Game.GetQuestsSystem():SetFact('your_fact', 1).\",\n" +
            "    \"_weAlsoWrite\": \"ai_npc_installed = 1 at every session start, so a quest can offer a texting path only where there is something to text.\",\n" +
            "    \"facts\": [\n" +
            "        {\n" +
            "            \"_fact\": \"The quest fact to watch. No spaces - it has to match the name the other mod sets.\",\n" +
            "            \"fact\": \"their_mod_rescue_done\",\n" +
            "            \"_atLeast\": \"The value it must reach. 1 is a flag; a counter uses its own number. Optional, defaults to 1.\",\n" +
            "            \"atLeast\": 1,\n" +
            "            \"_contacts\": \"Who hears about it. Each one reacts in its own voice; nobody is interrupted, the news waits for the next time V opens that thread.\",\n" +
            "            \"contacts\": [\"panam\", \"judy\"],\n" +
            "            \"_event\": \"What they are told, in your words. Placeholders work here ({they}, {npc}, ...), plus {value} for the fact's own number.\",\n" +
            "            \"event\": \"V pulled somebody out of a Maelstrom den in Northside last night. It made the local feeds.\",\n" +
            "            \"_ackFact\": \"Optional, and the way back: set to 1 once one of the contacts has answered V since being told, so your quest phase can move on. Omit it if you do not need to know.\",\n" +
            "            \"ackFact\": \"their_mod_ai_npc_heard\"\n" +
            "        }\n" +
            "    ]\n" +
            "}\n";
        storage.GetFile(this.FACTS_EXAMPLE_FILE).WriteText(text);
    }

}

// The two questions a call site asks about its own pass. A config that failed to load answers
// "the dialogue slot, the built-in recipe", which is what the mod sent before either table
// existed -- a caller that had to guard would be one caller away from a prompt with no blocks.
//
// AiNpcPassRecipe has ONE caller, AiNpcPassBuilder.Recipe(), and tools\lint.ps1 holds it there:
// a renderer reaching the recipe by any other route is a renderer that can read another pass's.
func AiNpcPassSlotName(pass: String) -> String {
    let service = AiNpcConfigService.Get();
    if IsDefined(service) {
        return service.GetPassSlotName(pass);
    }
    return AiNpcSlotDefaultName();
}

func AiNpcPassRecipe(pass: String) -> ref<AiNpcRecipe> {
    let service = AiNpcConfigService.Get();
    if IsDefined(service) {
        let recipe = service.GetPassRecipe(pass);
        if IsDefined(recipe) {
            return recipe;
        }
    }
    return AiNpcRecipeFull();
}
