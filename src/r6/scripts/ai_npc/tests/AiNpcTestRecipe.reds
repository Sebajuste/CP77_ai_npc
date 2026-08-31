module AiNpc

import RedData.Json.*

// La recette : le vocabulaire, le fichier lu, et ce que chaque bloc en fait.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

/// The vocabulary ///

func AiNpcTestRecipeSchema(t: ref<AiNpcTestRunner>) -> Void {
    let schema = AiNpcRecipeSchema();
    t.Check("recipe/the schema is not empty", ArraySize(schema) > 0);

    // The order of the table IS the order of the prompt, and the first two blocks are the two
    // a recipe may not drop. Asserted by position because that is what the claim is.
    t.EqString("recipe/system comes first", schema[0].key, "system");
    t.EqString("recipe/explicitness comes second", schema[1].key, "explicitness");

    // One name, one block. A duplicate key would make AiNpcRecipeBlockNamed answer the first
    // and the parser write the second, which is a block rendered at a level nobody chose.
    let seen: array<String>;
    let duplicates = 0;
    let i = 0;
    while i < ArraySize(schema) {
        if ArrayContains(seen, schema[i].key) {
            duplicates += 1;
        }
        ArrayPush(seen, schema[i].key);
        // Every block has at least one part, so "full" always means something.
        t.Check(s"recipe/\(schema[i].key) has a part", ArraySize(schema[i].parts) > 0);
        i += 1;
    }
    t.EqInt("recipe/no block is declared twice", duplicates, 0);

    t.Check("recipe/system is required", AiNpcRecipeSchemaOf("system").required);
    t.Check("recipe/explicitness is required", AiNpcRecipeSchemaOf("explicitness").required);
    t.Check("recipe/character can be dropped", !AiNpcRecipeSchemaOf("character").required);
    t.Check("recipe/target carries a source", AiNpcRecipeIsSourced(AiNpcRecipeSchemaOf("target")));
    t.Check("recipe/memory carries no source", !AiNpcRecipeIsSourced(AiNpcRecipeSchemaOf("memory")));

    // The two message blocks. A request is two messages whatever a file says, so neither can
    // be dropped -- and they are the only blocks that render nothing themselves: they name the
    // builder that writes each half.
    t.Check("recipe/the instruction is a block",
        IsDefined(AiNpcRecipeSchemaOf("instruction")));
    t.Check("recipe/the ask is a block", IsDefined(AiNpcRecipeSchemaOf("ask")));
    t.Check("recipe/the instruction carries a source",
        AiNpcRecipeIsSourced(AiNpcRecipeSchemaOf("instruction")));
    t.Check("recipe/the ask cannot be dropped",
        AiNpcRecipeSchemaOf("ask").required);
    t.Check("recipe/a part of the prompt is not a message",
        !AiNpcRecipeBlockIsMessage(AiNpcRecipeSchemaOf("system")));
    t.Check("recipe/an unknown block has no schema entry",
        !IsDefined(AiNpcRecipeSchemaOf("no_such_block")));
}

/// What a renderer asks ///

func AiNpcTestRecipeQueries(t: ref<AiNpcTestRunner>) -> Void {
    // Null reads as "render everything". Every renderer is called with whatever the config
    // service answered, and a null that meant "render nothing" would empty the prompt at the
    // one moment the config is broken.
    t.Check("recipe/null renders every block", AiNpcRecipeHas(null, "memory"));
    t.Check("recipe/null renders every part", AiNpcRecipeWants(null, "memory", "facts"));
    t.EqString("recipe/null names no source", AiNpcRecipeSourceOf(null, "target"), "");

    let full = AiNpcRecipeFull();
    t.Check("recipe/full renders character", AiNpcRecipeHas(full, "character"));
    t.Check("recipe/full renders the speech part", AiNpcRecipeWants(full, "character", "speech"));

    // A block the recipe never mentions is rendered: that is what lets a block added by a
    // later version reach a file written before it existed.
    let quiet = new AiNpcRecipe();
    t.Check("recipe/an unmentioned block is rendered", AiNpcRecipeHas(quiet, "character"));
    t.Check("recipe/an unmentioned part is rendered", AiNpcRecipeWants(quiet, "memory", "agreed"));

    // An empty part list is how a recipe says "drop it", and it is the only way.
    let none: array<String>;
    let dropped = AiNpcRecipeWith(full, AiNpcRecipeBlockOf("memory", none));
    t.Check("recipe/an empty part list drops the block", !AiNpcRecipeHas(dropped, "memory"));
    t.Check("recipe/dropping one block leaves the others", AiNpcRecipeHas(dropped, "character"));

    let some = AiNpcRecipeWith(full, AiNpcRecipeBlockOf("memory", ["facts"]));
    t.Check("recipe/a kept part answers true", AiNpcRecipeWants(some, "memory", "facts"));
    t.Check("recipe/an unlisted part answers false", AiNpcRecipeWants(some, "memory", "agreed"));
    t.Check("recipe/a trimmed block is still rendered", AiNpcRecipeHas(some, "memory"));

    // Building one never edits the one it was built from: a recipe is handed around a whole
    // prompt build, and a shared object edited underneath is a prompt nobody logged.
    t.Check("recipe/the source recipe is untouched", AiNpcRecipeWants(full, "memory", "agreed"));
}

/// The file ///

func AiNpcTestRecipeParse(t: ref<AiNpcTestRunner>) -> Void {
    let issues: array<ref<AiNpcConfigIssue>>;

    // "full" and a part list, the two ordinary shapes.
    let recipe = AiNpcTestRecipeOf("{\"character\": \"full\", \"memory\": [\"facts\"]}", issues);
    t.Check("recipe/full keeps every part", AiNpcRecipeWants(recipe, "character", "speech"));
    t.Check("recipe/a list keeps what it names", AiNpcRecipeWants(recipe, "memory", "facts"));
    t.Check("recipe/a list drops what it omits", !AiNpcRecipeWants(recipe, "memory", "chronicle"));
    // A key the file never mentions keeps the mod's answer.
    t.Check("recipe/an absent key keeps the block", AiNpcRecipeHas(recipe, "quest"));
    t.EqInt("recipe/a well-formed recipe reports nothing", ArraySize(issues), 0);

    // The four ways to remove a block, and they agree.
    let byWord = AiNpcTestRecipeOf("{\"commands\": \"none\"}", issues);
    let byBool = AiNpcTestRecipeOf("{\"commands\": false}", issues);
    let byList = AiNpcTestRecipeOf("{\"commands\": []}", issues);
    let byNull = AiNpcTestRecipeOf("{\"commands\": null}", issues);
    t.Check("recipe/none removes the block", !AiNpcRecipeHas(byWord, "commands"));
    t.Check("recipe/false removes the block", !AiNpcRecipeHas(byBool, "commands"));
    t.Check("recipe/an empty list removes the block", !AiNpcRecipeHas(byList, "commands"));
    t.Check("recipe/null removes the block", !AiNpcRecipeHas(byNull, "commands"));
    t.EqInt("recipe/removing a block reports nothing", ArraySize(issues), 0);

    // null is written, absence is not, and they mean different things. A key nobody wrote
    // keeps the mod's answer; a key written as null is somebody saying "not this one".
    let absent = AiNpcTestRecipeOf("{\"memory\": [\"facts\"]}", issues);
    t.Check("recipe/an absent key is not a null one", AiNpcRecipeHas(absent, "commands"));

    // A number resembles all of them and means none: 1 would read as true on one line and 0
    // would delete a block on the next.
    let numbered: array<ref<AiNpcConfigIssue>>;
    let counted = AiNpcTestRecipeOf("{\"memory\": 3}", numbered);
    t.EqInt("recipe/a number is reported", ArraySize(numbered), 1);
    t.EqString("recipe/a number is an error", numbered[0].severity, "error");
    t.Check("recipe/a number keeps every part", AiNpcRecipeWants(counted, "memory", "agreed"));

    // The parts come back in the SCHEMA's order, never the file's. <memory> reads oldest and
    // blurriest first, and a file listing them backwards must not reverse the block.
    let reversed = AiNpcTestRecipeOf("{\"memory\": [\"agreed\", \"facts\", \"chronicle\"]}", issues);
    let block = AiNpcRecipeBlockNamed(reversed, "memory");
    t.EqString("recipe/parts are ordered by the schema",
        AiNpcRecipeJoinNames(block.parts), "chronicle, facts, agreed");
}

// Nothing is ever dropped in silence: a hand-written file's likeliest fault is a typo, and a
// block that quietly stopped being rendered looks exactly like a model that got worse.
func AiNpcTestRecipeRefusals(t: ref<AiNpcTestRunner>) -> Void {
    let unknownBlock: array<ref<AiNpcConfigIssue>>;
    AiNpcTestRecipeOf("{\"charcter\": \"full\"}", unknownBlock);
    t.EqInt("recipe/a misspelled block is reported", ArraySize(unknownBlock), 1);
    t.EqString("recipe/a misspelled block is only a warning",
        unknownBlock[0].severity, "warning");

    let unknownPart: array<ref<AiNpcConfigIssue>>;
    let partial = AiNpcTestRecipeOf("{\"character\": [\"bio\", \"speech-tyle\"]}", unknownPart);
    t.EqInt("recipe/a misspelled part is reported", ArraySize(unknownPart), 1);
    t.Check("recipe/a misspelled part costs itself and nothing else",
        AiNpcRecipeWants(partial, "character", "bio"));
    t.Check("recipe/a misspelled part is not rendered",
        !AiNpcRecipeWants(partial, "character", "speech"));

    let unknownLevel: array<ref<AiNpcConfigIssue>>;
    let kept = AiNpcTestRecipeOf("{\"memory\": \"short\"}", unknownLevel);
    t.EqInt("recipe/an invented level is reported", ArraySize(unknownLevel), 1);
    t.EqString("recipe/an invented level is an error", unknownLevel[0].severity, "error");
    t.Check("recipe/an invented level keeps every part",
        AiNpcRecipeWants(kept, "memory", "agreed"));

    // The two required blocks. A recipe that could drop <explicitness> would answer a question
    // that was put to the player, from the strongest position in the prompt.
    let required: array<ref<AiNpcConfigIssue>>;
    let stubborn = AiNpcTestRecipeOf("{\"explicitness\": null, \"system\": []}", required);
    t.EqInt("recipe/both required blocks refuse removal", ArraySize(required), 2);
    t.Check("recipe/explicitness survives being dropped",
        AiNpcRecipeHas(stubborn, "explicitness"));
    t.Check("recipe/system survives being dropped", AiNpcRecipeHas(stubborn, "system"));

    // And they are required OF A CONVERSATION RECIPE, which is what a recipe is until it says
    // otherwise. One written for the compaction pass carries neither a <system> block nor a
    // tier the player consented to, so it may drop both -- and a file that has never heard of
    // the instruction block, which is every file written before this version, may not.
    let exempt: array<ref<AiNpcConfigIssue>>;
    let elsewhere = AiNpcTestRecipeOf(
        "{\"instruction\": {\"source\": \"memory\"}, \"explicitness\": null, \"system\": null}", exempt);
    t.EqInt("recipe/another pass's recipe drops them in silence", ArraySize(exempt), 0);
    t.Check("recipe/and they really are dropped", !AiNpcRecipeHas(elsewhere, "system"));

    let stillSpeaking: array<ref<AiNpcConfigIssue>>;
    AiNpcTestRecipeOf("{\"instruction\": {\"source\": \"conversation\"}, \"system\": null}", stillSpeaking);
    t.EqInt("recipe/a declared conversation recipe still refuses", ArraySize(stillSpeaking), 1);

    // Neither message block can go, whatever the recipe is for: a request has two halves.
    let halves: array<ref<AiNpcConfigIssue>>;
    let both = AiNpcTestRecipeOf(
        "{\"instruction\": {\"source\": \"memory\"}, \"ask\": null}", halves);
    t.EqInt("recipe/a message cannot be removed", ArraySize(halves), 1);
    t.EqString("recipe/removing a message is an error", halves[0].severity, "error");
    t.Check("recipe/the message block stands", AiNpcRecipeHas(both, "ask"));

    // The source list is the block's own. <target> knows nothing of the passes, and the two
    // message blocks know nothing of who is being written to.
    let crossed: array<ref<AiNpcConfigIssue>>;
    AiNpcTestRecipeOf("{\"target\": {\"source\": \"memory\"}}", crossed);
    t.EqInt("recipe/a source from another block is refused", ArraySize(crossed), 1);

    let asked: array<ref<AiNpcConfigIssue>>;
    let repair = AiNpcTestRecipeOf("{\"ask\": {\"source\": \"repair\"}}", asked);
    t.EqInt("recipe/a pass source is taken", ArraySize(asked), 0);
    t.EqString("recipe/a pass source is stored",
        AiNpcRecipeSourceOf(repair, "ask"), "repair");

    // The source is a closed list, checked when the file is read rather than discovered as a
    // missing block ten minutes into a conversation.
    let source: array<ref<AiNpcConfigIssue>>;
    let target = AiNpcTestRecipeOf("{\"target\": {\"source\": \"player\"}}", source);
    t.EqInt("recipe/a known source is taken", ArraySize(source), 0);
    t.EqString("recipe/a known source is stored", AiNpcRecipeSourceOf(target, "target"), "player");

    let badSource: array<ref<AiNpcConfigIssue>>;
    let fallback = AiNpcTestRecipeOf("{\"target\": {\"source\": \"jackie\"}}", badSource);
    t.EqInt("recipe/an unknown source is reported", ArraySize(badSource), 1);
    t.EqString("recipe/an unknown source is not stored",
        AiNpcRecipeSourceOf(fallback, "target"), "");
    t.Check("recipe/an unknown source leaves the block standing",
        AiNpcRecipeHas(fallback, "target"));

    // A source on a block that has none is a misunderstanding worth a line, not an error: the
    // block is rendered exactly as asked.
    let strayed: array<ref<AiNpcConfigIssue>>;
    AiNpcTestRecipeOf("{\"memory\": {\"source\": \"player\"}}", strayed);
    t.EqInt("recipe/a source where none belongs is reported", ArraySize(strayed), 1);
    t.EqString("recipe/a source where none belongs is a warning", strayed[0].severity, "warning");
}

func AiNpcTestRecipeBook(t: ref<AiNpcTestRunner>) -> Void {
    let issues: array<ref<AiNpcConfigIssue>>;
    let book = AiNpcRecipeBookFromJson(
        ParseJson("{\"active\": \"compact\", \"recipes\": {\"default\": {}, \"compact\": {\"commands\": false}}}") as JsonObject,
        "test", issues);
    t.EqInt("recipe/both recipes are read", ArraySize(book.recipes), 2);
    t.EqString("recipe/active is read", book.active, "compact");
    t.Check("recipe/the active recipe is the one selected",
        !AiNpcRecipeHas(AiNpcRecipeBookActive(book), "commands"));
    t.EqInt("recipe/a well-formed book reports nothing", ArraySize(issues), 0);

    // Pointing "active" at nothing is the one mistake whose symptom is indistinguishable from
    // the file not being read at all, so it is named rather than left to show up as a prompt.
    let missing: array<ref<AiNpcConfigIssue>>;
    let orphan = AiNpcRecipeBookFromJson(
        ParseJson("{\"active\": \"tiny\", \"recipes\": {\"default\": {}}}") as JsonObject,
        "test", missing);
    t.EqInt("recipe/an active nobody declares is reported", ArraySize(missing), 1);
    t.Check("recipe/an active nobody declares falls back to the full render",
        AiNpcRecipeHas(AiNpcRecipeBookActive(orphan), "commands"));

    // A leading underscore is a comment. The shipped template annotates itself with them, so
    // copying it must not produce warnings about its own documentation.
    let annotated: array<ref<AiNpcConfigIssue>>;
    let documented = AiNpcRecipeBookFromJson(
        ParseJson("{\"_doc\": \"hello\", \"recipes\": {\"_note\": \"hello\", \"default\": {}}}") as JsonObject,
        "test", annotated);
    t.EqInt("recipe/comments are not read as recipes", ArraySize(documented.recipes), 1);
    t.EqInt("recipe/comments are not reported", ArraySize(annotated), 0);

    let broken: array<ref<AiNpcConfigIssue>>;
    AiNpcRecipeBookFromJson(ParseJson("{\"active\": \"default\"}") as JsonObject, "test", broken);
    t.Check("recipe/a book with no recipes is reported", ArraySize(broken) > 0);
}

/// The template ///

// The one guarantee the shipped file has to keep: copying it changes nothing. It is written to
// disk as documentation AND parsed as the mod's own default, so a key it spells wrongly would
// silently remove a block from every prompt of a fresh install.
func AiNpcTestRecipeTemplate(t: ref<AiNpcTestRunner>) -> Void {
    let root = ParseJson(AiNpcRecipeTemplate()) as JsonObject;
    t.Check("recipe/the template is valid JSON", IsDefined(root));

    let issues: array<ref<AiNpcConfigIssue>>;
    let book = AiNpcRecipeBookFromJson(root, AiNpcRecipeTemplateFile(), issues);
    t.EqInt("recipe/the template uses no word the schema refuses", ArraySize(issues), 0);

    let active = AiNpcRecipeBookActive(book);
    t.EqString("recipe/the template's active recipe is default", active.name, "default");

    // Block by block, part by part, against the schema: the default renders everything, so a
    // fresh install carries the prompt this mod has always built.
    let schema = AiNpcRecipeSchema();
    let missing = 0;
    let i = 0;
    while i < ArraySize(schema) {
        if !AiNpcRecipeHas(active, schema[i].key) {
            missing += 1;
        }
        let j = 0;
        while j < ArraySize(schema[i].parts) {
            if !AiNpcRecipeWants(active, schema[i].key, schema[i].parts[j]) {
                missing += 1;
            }
            j += 1;
        }
        i += 1;
    }
    t.EqInt("recipe/the template renders every block at every part", missing, 0);

    // And the example of a trimmed one is a real trim, or it documents nothing.
    // The default declares what it is: a conversation recipe. Silence would mean the same
    // thing, and saying it is what documents the vocabulary a second recipe needs.
    t.EqString("recipe/the template's default renders the conversation",
        AiNpcRecipeSourceOf(active, "instruction"), "conversation");

    let compact = AiNpcTestRecipeNamed(book, "compact");
    t.Check("recipe/the template ships a trimmed example", IsDefined(compact));
    if IsDefined(compact) {
        t.Check("recipe/the trimmed example drops the commands",
            !AiNpcRecipeHas(compact, "commands"));
        t.Check("recipe/the trimmed example keeps the bio",
            AiNpcRecipeWants(compact, "character", "bio"));
        t.Check("recipe/the trimmed example drops the register",
            !AiNpcRecipeWants(compact, "character", "speech"));
    }
}

/// What the blocks do with it ///

func AiNpcTestRecipeRendering(t: ref<AiNpcTestRunner>) -> Void {
    let memory = new AiNpcMemory();
    memory.chronicle = "they met in Kabuki";
    ArrayPush(memory.facts, "V drives a Thorton");
    let thread = new AiNpcMemoryThread();
    thread.text = "V never said where the money went";
    ArrayPush(memory.threads, thread);
    memory.tone = "warm";

    let everything = AiNpcMemoryRenderParts(memory, AiNpcTimeUnknown(), AiNpcRecipeFull());
    t.Check("recipe/memory renders the chronicle", StrContains(everything, "they met in Kabuki"));
    t.Check("recipe/memory renders the facts", StrContains(everything, "V drives a Thorton"));
    t.Check("recipe/memory renders the open loops", StrContains(everything, "where the money went"));

    let factsOnly = AiNpcMemoryRenderParts(memory, AiNpcTimeUnknown(),
        AiNpcRecipeWith(AiNpcRecipeFull(), AiNpcRecipeBlockOf("memory", ["facts"])));
    t.Check("recipe/facts survive the trim", StrContains(factsOnly, "V drives a Thorton"));
    t.Check("recipe/the chronicle is trimmed", !StrContains(factsOnly, "Kabuki"));
    t.Check("recipe/the open loops are trimmed", !StrContains(factsOnly, "money went"));
    t.Check("recipe/the tone is trimmed", !StrContains(factsOnly, "TONE"));

    // The header is not a part. Without it the block reads as instructions and the model
    // answers them, so it comes back with whatever survived the trim.
    t.Check("recipe/the header survives any trim", StrContains(factsOnly, "ALREADY KNOW"));

    // And it is never emitted alone: a block trimmed down to sections this memory does not
    // hold is no block at all.
    let nothingLeft = AiNpcMemoryRenderParts(memory, AiNpcTimeUnknown(),
        AiNpcRecipeWith(AiNpcRecipeFull(), AiNpcRecipeBlockOf("memory", ["agreed"])));
    t.EqString("recipe/a trim with nothing left renders no block", nothingLeft, "");

    // The rendered default is what it was before the block learned about parts.
    t.EqString("recipe/a full render is the undated render",
        everything, AiNpcMemoryRenderAt(memory, AiNpcTimeUnknown()));
}

// The register moved into <character>, and the rubric key that used to carry it is refused
// where it stands -- with a line that says where it went, because a contribution that vanished
// in silence is the worst of the three outcomes.
func AiNpcTestRecipeSpeechMoved(t: ref<AiNpcTestRunner>) -> Void {
    t.Check("recipe/SPEECH is locked in the rule block",
        AiNpcRuleIsLocked("system_rules", AiNpcCharacterSpeechKey()));
    t.Check("recipe/SPEECH is compared without regard to case",
        AiNpcRuleIsLocked("system_rules", "speech"));

    let refusal = AiNpcRuleRefusal("system_rules", AiNpcRuleOf("SPEECH", "blunt, uses slang"));
    t.Check("recipe/the refusal names the block it moved to",
        StrContains(refusal, "<character>"));
    t.Check("recipe/the refusal names a lane that still works",
        StrContains(refusal, "speechStyle"));

    // The mod's own rules no longer carry one, whatever the contact says.
    let rules = AiNpcCoreRules("panam");
    t.EqInt("recipe/the rule block declares no register",
        AiNpcRuleIndexOf(rules, AiNpcCharacterSpeechKey()), -1);
}

/// Helpers ///

func AiNpcTestRecipeOf(body: String, out issues: array<ref<AiNpcConfigIssue>>) -> ref<AiNpcRecipe> {
    return AiNpcRecipeFromJson(ParseJson(body) as JsonObject, "test", "test", issues);
}

func AiNpcTestRecipeNamed(book: ref<AiNpcRecipeBook>, name: String) -> ref<AiNpcRecipe> {
    let i = 0;
    while i < ArraySize(book.recipes) {
        if Equals(book.recipes[i].name, name) {
            return book.recipes[i];
        }
        i += 1;
    }
    return null;
}
