module AiNpc

import RedData.Json.*

// Les slots et la table des passes : ce qu'un fichier dit, et ce que la requete emporte.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

/// The slot ///

func AiNpcTestSlotResolution(t: ref<AiNpcTestRunner>) -> Void {
    let slots = ParseJson("{\"dialogue\": {\"model\": \"vendor/big\", \"max_tokens\": 100},"
        + " \"memory\": {\"max_tokens\": 1200, \"timeoutSeconds\": 60},"
        + " \"mechanic\": {\"model\": \"vendor/small\"}}") as JsonObject;

    let dialogue = AiNpcSlotFrom(slots, AiNpcSlotDefaultName(), null);
    t.EqString("slot/the dialogue slot keeps its model", dialogue.model, "vendor/big");
    t.EqInt("slot/the dialogue slot keeps its parameters",
        AiNpcJsonInt(dialogue.params, "max_tokens", -1), 100);

    // Key by key, with dialogue as the base: "the slot is empty" and "the slot says nothing
    // about this parameter" are one case.
    let memory = AiNpcSlotFrom(slots, "memory", null);
    t.EqString("slot/an unnamed model comes from dialogue", memory.model, "vendor/big");
    t.EqInt("slot/a named parameter wins over dialogue",
        AiNpcJsonInt(memory.params, "max_tokens", -1), 1200);

    let mechanic = AiNpcSlotFrom(slots, "mechanic", null);
    t.EqString("slot/a named model wins over dialogue", mechanic.model, "vendor/small");
    t.EqInt("slot/an unnamed parameter comes from dialogue",
        AiNpcJsonInt(mechanic.params, "max_tokens", -1), 100);

    // Reserved: ours, and it must never reach the body. The overlay copies whatever it holds,
    // so a key left in the parameters is a key sent to a provider that will refuse it.
    t.EqInt("slot/timeoutSeconds is read", memory.timeoutSeconds, 60);
    t.Check("slot/timeoutSeconds is not a parameter", !memory.params.HasKey(AiNpcSlotTimeoutKey()));
    t.EqInt("slot/an unset timeout is zero", mechanic.timeoutSeconds, 0);

    // Both directions are safe, and that is what lets a slot be added without breaking
    // anything: a file naming a slot this version has never heard of still sends what it
    // always sent.
    let unknown = AiNpcSlotFrom(slots, "vision", null);
    t.EqString("slot/an unknown slot falls back to dialogue", unknown.model, "vendor/big");
    t.EqInt("slot/an unknown slot keeps dialogue's parameters",
        AiNpcJsonInt(unknown.params, "max_tokens", -1), 100);

    let nothing = AiNpcSlotFrom(null, AiNpcSlotDefaultName(), null);
    t.EqString("slot/no slots block names no model", nothing.model, "");
    let bare = nothing.params.GetKeys();
    t.EqInt("slot/no slots block sends no parameter", ArraySize(bare), 0);
}

// The three settings that predate the format. THE MORE SPECIFIC WINS -- named slot, dialogue
// slot, then them -- which is what keeps a file with no slots block behaving exactly as it did
// AND lets a preset write a model the old key does not shadow.
func AiNpcTestSlotAliases(t: ref<AiNpcTestRunner>) -> Void {
    let silent = AiNpcSlotAliases("", 0, "");
    let none = silent.GetKeys();
    t.EqInt("slot/unset settings alias nothing", ArraySize(none), 0);

    let aliases = AiNpcSlotAliases("vendor/alias", 50, "low");
    t.EqString("slot/maxTokens aliases max_tokens", AiNpcJsonString(aliases, "reasoning_effort"), "low");
    t.EqInt("slot/maxTokens keeps its value", AiNpcJsonInt(aliases, "max_tokens", -1), 50);

    let slots = ParseJson("{\"dialogue\": {\"model\": \"vendor/big\", \"max_tokens\": 100},"
        + " \"memory\": {\"max_tokens\": 1200}}") as JsonObject;

    let dialogue = AiNpcSlotFrom(slots, AiNpcSlotDefaultName(), aliases);
    t.EqString("slot/the dialogue slot wins over the old setting", dialogue.model, "vendor/big");
    t.EqInt("slot/and so does its parameter",
        AiNpcJsonInt(dialogue.params, "max_tokens", -1), 100);

    let memory = AiNpcSlotFrom(slots, "memory", aliases);
    t.EqInt("slot/a named slot wins over both",
        AiNpcJsonInt(memory.params, "max_tokens", -1), 1200);

    // And a file that has no slots block at all is a file that behaves as it always has: the
    // old settings are then the only thing there is.
    let legacy = AiNpcSlotFrom(null, AiNpcSlotDefaultName(), aliases);
    t.EqString("slot/with no slots block the old setting is the answer", legacy.model, "vendor/alias");
    t.EqInt("slot/with no slots block maxTokens still applies",
        AiNpcJsonInt(legacy.params, "max_tokens", -1), 50);
}

// The overlay copies and does not inspect: that is what lets a parameter a provider ships
// tomorrow work tomorrow. What it must never do is add a key nobody wrote -- `max_tokens: 0`
// is not unset, it is a value, and it comes back a 400.
func AiNpcTestSlotOverlay(t: ref<AiNpcTestRunner>) -> Void {
    let body = ParseJson("{\"model\": \"vendor/big\", \"messages\": []}") as JsonObject;
    let before = body.GetKeys();
    let count = ArraySize(before);

    AiNpcSlotOverlay(body, AiNpcSlotFrom(null, AiNpcSlotDefaultName(), null));
    let after = body.GetKeys();
    t.EqInt("slot/a slot that says nothing adds nothing", ArraySize(after), count);

    let slots = ParseJson("{\"dialogue\": {\"model\": \"vendor/small\", \"max_tokens\": 40,"
        + " \"reasoning_effort\": \"low\", \"timeoutSeconds\": 20}}") as JsonObject;
    AiNpcSlotOverlay(body, AiNpcSlotFrom(slots, AiNpcSlotDefaultName(), null));
    t.EqInt("slot/a parameter reaches the body", AiNpcJsonInt(body, "max_tokens", -1), 40);
    t.EqString("slot/a parameter the mod has never heard of reaches it too",
        AiNpcJsonString(body, "reasoning_effort"), "low");
    t.Check("slot/a reserved key never reaches the body", !body.HasKey(AiNpcSlotTimeoutKey()));
    t.EqString("slot/the model is not overlaid: it is resolved once",
        AiNpcJsonString(body, "model"), "vendor/big");

    // A CLI lane runs a process the player signed into, in another model namespace entirely.
    let slot = AiNpcSlotFrom(slots, AiNpcSlotDefaultName(), null);
    t.EqString("slot/a slot model reaches an http lane",
        AiNpcLlmSlotModel(AiNpcProvider.OpenRouter, slot), "vendor/small");
    t.EqString("slot/a slot model never reaches a cli lane",
        AiNpcLlmSlotModel(AiNpcProvider.ClaudeCli, slot), AiNpcLlmChatModel(AiNpcProvider.ClaudeCli));

    // The reserved key is the only thing about a request that cannot travel in the body.
    t.Check("slot/a slot timeout is the deadline",
        Equals(AiNpcLlmRequestTimeout(AiNpcProvider.OpenRouter, slot), 20.0));
    t.Check("slot/a slot with no timeout keeps the provider's",
        AiNpcLlmRequestTimeout(AiNpcProvider.OpenRouter, null) > 0.0);
}

// Une requete part toujours avec un plafond de reponse.
//
// Sans lui, certains fournisseurs derriere OpenRouter reservent tout le contexte du modele et
// refusent la requete ; le meme corps passe chez l'un et echoue chez l'autre, au hasard du
// routage. Le plafond voyage comme tout parametre de fil : le slot le porte, l'incrustation le
// copie. Verifie sur la chaine envoyee, et par sa valeur -- la cle ne s'ecrit que dans la
// table d'alias.
func AiNpcTestCompletionCap(t: ref<AiNpcTestRunner>) -> Void {
    t.Check("cap/an unset setting still asks for a ceiling", AiNpcGetMaxTokens() > 0);

    let slot = new AiNpcSlot();
    slot.name = AiNpcSlotDefaultName();
    slot.params = AiNpcSlotAliases("vendor/model", 77, "");

    let router = AiNpcLlmChatBody(AiNpcProvider.OpenRouter, slot, "systeme", "V: salut");
    t.Check("cap/the slot carries it onto the body", StrContains(router, "77"));

    let cli = AiNpcLlmChatBody(AiNpcProvider.ClaudeCli, slot, "systeme", "V: salut");
    t.Check("cap/both body shapes carry it", StrContains(cli, "77"));

    // Un slot muet ne fabrique rien : c'est le reglage, plus haut, qui garantit le plafond.
    slot.params = AiNpcSlotAliases("vendor/model", 0, "");
    let unset = AiNpcLlmChatBody(AiNpcProvider.OpenRouter, slot, "systeme", "V: salut");
    t.Check("cap/a slot asked for nothing writes nothing", !StrContains(unset, "77"));
}

/// The pass table ///

func AiNpcTestPassSources(t: ref<AiNpcTestRunner>) -> Void {
    // A pass is a lane, by name: the usage report already totals per lane, and a second
    // vocabulary would be a mapping table nobody maintains.
    let names = AiNpcPassNames();
    t.EqInt("pass/this version makes six passes", ArraySize(names), 6);
    t.Check("pass/the speaking lane is a pass", ArrayContains(names, AiNpcLaneSpeaking()));
    t.Check("pass/the test lane is a pass", ArrayContains(names, AiNpcLaneTest()));

    // Le canal choisit la passe, et c'est la seule chose qui separe une replique lue a voix
    // haute d'un SMS. Verifie sur ce que le choisisseur rend, parce qu'il a deja existe sans
    // appelant : la table des passes etait juste, et aucun appel ne la traversait.
    let spoken = AiNpcPassBuilderFor(AiNpcChannelId.Call, "judy", "", "", "salut", false);
    t.EqString("pass/a call is sent on the holo pass", spoken.Pass(), AiNpcLaneHolo());
    let written = AiNpcPassBuilderFor(AiNpcChannelId.Text, "judy", "", "", "salut", false);
    t.EqString("pass/a text is sent on the speaking pass", written.Pass(), AiNpcLaneSpeaking());

    // The speaking lane has two askmakers and one source: which of the two runs is decided by
    // SpeaksFirst() at the moment of sending, and a file that could name one would be a file
    // that switches off the character writing first.
    t.EqString("pass/speaking asks the conversation",
        AiNpcPassAskSource(AiNpcLaneSpeaking()), "conversation");
    t.EqString("pass/repair asks its own question",
        AiNpcPassAskSource(AiNpcLaneRepair()), "repair");
    t.EqString("pass/repair instructs with the commands",
        AiNpcPassInstructionSource(AiNpcLaneRepair()), "actions");
    t.EqString("pass/the selection is instructed with the same table the repair is",
        AiNpcPassInstructionSource(AiNpcLaneActions()), "actions");
    t.EqString("pass/the selection reads what was written",
        AiNpcPassAskSource(AiNpcLaneActions()), "selector");
    t.EqString("pass/a pass this version does not make renders nothing",
        AiNpcPassInstructionSource("ranking"), "");

    // The schema's source lists are these, derived: a fifth pass brings its own with it.
    let asks = AiNpcPassAskSources();
    t.Check("pass/the ask sources are the passes'", ArrayContains(asks, "repair"));
    let entry = AiNpcRecipeSchemaOf("ask");
    t.EqInt("pass/the schema knows exactly those", ArraySize(entry.sources), ArraySize(asks));
}

func AiNpcTestPassTable(t: ref<AiNpcTestRunner>) -> Void {
    let bookIssues: array<ref<AiNpcConfigIssue>>;
    let book = AiNpcRecipeBookFromJson(
        ParseJson("{\"recipes\": {\"default\": {}, \"compaction\": {\"instruction\": {\"source\": \"memory\"},"
            + " \"ask\": {\"source\": \"memory\"}}}}") as JsonObject, "test", bookIssues);
    let slots = ParseJson("{\"mechanic\": {\"model\": \"vendor/small\"}}") as JsonObject;

    // Nothing configured is the shipped state: every pass on the dialogue slot and on the
    // active recipe, which is where every request went before this table existed.
    let absent: array<ref<AiNpcConfigIssue>>;
    let empty = AiNpcPassTableFromJson(null, "test", slots, book, absent);
    t.EqInt("pass/no table binds nothing", ArraySize(empty), 0);
    t.EqString("pass/an unbound pass is on the dialogue slot",
        AiNpcPassBindingNamed(empty, AiNpcLaneThinking()).slotName, AiNpcSlotDefaultName());
    t.EqString("pass/an unbound pass names no recipe",
        AiNpcPassBindingNamed(empty, AiNpcLaneThinking()).recipeName, "");

    let issues: array<ref<AiNpcConfigIssue>>;
    let table = AiNpcPassTableFromJson(
        ParseJson("{\"thinking\": {\"slot\": \"mechanic\", \"recipe\": \"compaction\"}}") as JsonObject,
        "test", slots, book, issues);
    t.EqInt("pass/a well-formed table reports nothing", ArraySize(issues), 0);
    t.EqString("pass/the slot is bound",
        AiNpcPassBindingNamed(table, AiNpcLaneThinking()).slotName, "mechanic");
    t.EqString("pass/the recipe is bound",
        AiNpcPassBindingNamed(table, AiNpcLaneThinking()).recipeName, "compaction");

    // Both keys cross a file boundary, and pointing at nothing is the mistake whose symptom
    // is indistinguishable from the table not being read at all.
    let strays: array<ref<AiNpcConfigIssue>>;
    let stray = AiNpcPassTableFromJson(
        ParseJson("{\"speaking\": {\"slot\": \"mechanix\", \"recipe\": \"compct\"}}") as JsonObject,
        "test", slots, book, strays);
    t.EqInt("pass/both dangling names are reported", ArraySize(strays), 2);
    t.EqString("pass/a dangling slot is an error", strays[0].severity, "error");
    t.EqString("pass/a dangling slot falls back to dialogue",
        AiNpcPassBindingNamed(stray, AiNpcLaneSpeaking()).slotName, AiNpcSlotDefaultName());
    t.EqString("pass/a dangling recipe falls back to the active one",
        AiNpcPassBindingNamed(stray, AiNpcLaneSpeaking()).recipeName, "");

    // A pass this version does not make is a table written ahead of the code -- on purpose,
    // and said out loud, because the next pass to be built is already named.
    let ahead: array<ref<AiNpcConfigIssue>>;
    AiNpcPassTableFromJson(ParseJson("{\"ranking\": {\"slot\": \"mechanic\"}}") as JsonObject,
        "test", slots, book, ahead);
    t.EqInt("pass/an unimplemented pass is reported", ArraySize(ahead), 1);
    t.EqString("pass/an unimplemented pass is only a warning", ahead[0].severity, "warning");

    // A recipe says which pass it was written for. Binding it to another is refused here, not
    // discovered as a prompt nobody recognises.
    let mismatch: array<ref<AiNpcConfigIssue>>;
    AiNpcPassTableFromJson(
        ParseJson("{\"speaking\": {\"recipe\": \"compaction\"}}") as JsonObject,
        "test", slots, book, mismatch);
    t.EqInt("pass/a recipe bound to the wrong pass is reported twice", ArraySize(mismatch), 2);
    t.EqString("pass/a misbound recipe is an error", mismatch[0].severity, "error");

    let silent: array<ref<AiNpcConfigIssue>>;
    AiNpcPassTableFromJson(
        ParseJson("{\"speaking\": {\"recipe\": \"default\"}}") as JsonObject,
        "test", slots, book, silent);
    t.EqInt("pass/a recipe that names no source suits any pass", ArraySize(silent), 0);

    // The connection test checks the slot the REPLY is written on. Testing another one declares
    // the installation healthy on a model the player never sees.
    let aimed = AiNpcPassTableFromJson(
        ParseJson("{\"speaking\": {\"slot\": \"mechanic\"}}") as JsonObject,
        "test", slots, book, silent);
    t.EqString("pass/the test follows the speaking slot",
        AiNpcPassSlotNameIn(aimed, AiNpcLaneTest()), "mechanic");
    t.EqString("pass/an unbound pass is on the dialogue slot",
        AiNpcPassSlotNameIn(aimed, AiNpcLaneThinking()), AiNpcSlotDefaultName());

    let stated = AiNpcPassTableFromJson(
        ParseJson("{\"speaking\": {\"slot\": \"mechanic\"}, \"test\": {\"slot\": \"dialogue\"}}") as JsonObject,
        "test", slots, book, silent);
    t.EqString("pass/a test that names its own slot keeps it",
        AiNpcPassSlotNameIn(stated, AiNpcLaneTest()), AiNpcSlotDefaultName());
}

/// The pass builders ///

// The repair aims at a tag it is given after construction -- the claim that produces it is made
// against this builder's own vocabulary -- so Ready() is the whole of what keeps the two halves
// together. Without it an untagged repair asks a model to correct a blank line.
func AiNpcTestPassBuilders(t: ref<AiNpcTestRunner>) -> Void {
    let untagged = AiNpcPassRepair.Of("panam");
    t.Check("pass/an untagged repair is never ready", !untagged.Ready());

    // Ready exactly when it has both halves. Stated as an equality rather than as a true, so
    // the assertion holds on a contact whose command table happens to be empty.
    let aimed = AiNpcPassRepair.Of("panam");
    aimed.tag = "[ACTION:NOT_A_COMMAND]";
    t.Check("pass/a tagged repair is ready exactly when it has a vocabulary",
        Equals(aimed.Ready(), NotEquals(StrLen(aimed.Instruction()), 0)));

    // The probe carries no contact and no vocabulary, and is ready all the same: what it proves
    // is the transport.
    t.Check("pass/the connection test is always ready", AiNpcPassProbe.Of().Ready());
}

/// The presets ///

func AiNpcTestModelPresets(t: ref<AiNpcTestRunner>) -> Void {
    let presets = AiNpcModelPresets();
    t.EqInt("preset/three starting points", ArraySize(presets), 3);
    t.Check("preset/light is one of them", IsDefined(AiNpcModelPresetNamed("light")));
    t.Check("preset/premium is one of them", IsDefined(AiNpcModelPresetNamed("premium")));
    t.Check("preset/an invented name is nobody", !IsDefined(AiNpcModelPresetNamed("cheap")));

    let i = 0;
    while i < ArraySize(presets) {
        t.Check(s"preset/\(presets[i].name) names a model", NotEquals(StrLen(presets[i].model), 0));
        // The window reads its buttons out of the first word of each line, so a name with a
        // space in it would draw a button nobody can press.
        t.Check(s"preset/\(presets[i].name) is one word", !StrContains(presets[i].name, " "));
        i += 1;
    }

    // Written out, never resolved live: what a preset produces is a block of settings the
    // player then owns.
    let issues: array<ref<AiNpcConfigIssue>>;
    let book = AiNpcRecipeBookFromJson(ParseJson(AiNpcRecipeTemplate()) as JsonObject,
        "template", issues);
    let patch = AiNpcModelPresetPatch(AiNpcModelPresetNamed("normal"), book);
    t.EqString("preset/the block is stamped with the preset that wrote it",
        AiNpcJsonString(patch, AiNpcModelPresetKey()), "normal");

    let slots = AiNpcJsonObjectAt(patch, "slots");
    let dialogue = AiNpcJsonObjectAt(slots, AiNpcSlotDefaultName());
    t.EqString("preset/one model, on the dialogue slot",
        AiNpcJsonString(dialogue, "model"), AiNpcModelPresetNamed("normal").model);

    // A ceiling, not an economy: above the longest completion ever measured (1976 over 31
    // runs), so it bounds a model that runs away and cuts nothing that a model meant to write.
    t.EqInt("preset/the reply carries an output budget",
        AiNpcJsonInt(dialogue, "max_tokens", -1), AiNpcSlotDialogueMaxTokens());
    t.Check("preset/and it is above anything measured", AiNpcSlotDialogueMaxTokens() > 1976);

    // The second slot names no model at all -- it inherits the first. It exists for its
    // budget, because the repair and the selection are the passes whose output has a known
    // shape: one line, and no draft worth paying for.
    let mechanic = AiNpcJsonObjectAt(slots, AiNpcSlotMechanicName());
    t.Check("preset/the mechanic slot names no model of its own", !mechanic.HasKey("model"));
    t.EqInt("preset/the repair carries a tighter budget",
        AiNpcJsonInt(mechanic, "max_tokens", -1), AiNpcSlotMechanicMaxTokens());
    t.Check("preset/tighter than the reply's",
        AiNpcSlotMechanicMaxTokens() < AiNpcSlotDialogueMaxTokens());

    // And the draft switched off, which is what makes that budget a bound rather than a
    // guillotine -- three tokens of answer against five hundred of deliberation nobody reads.
    // Asserted as the nested object the wire takes, because a top-level effort hint is a
    // different key with a different effect, and the two were measured apart.
    let reasoning = AiNpcJsonObjectAt(mechanic, "reasoning");
    t.Check("preset/the technical calls do not deliberate", IsDefined(reasoning));
    let switched = IsDefined(reasoning) ? reasoning.GetKey("enabled") : null;
    t.Check("preset/and it is the switch, not a hint",
        IsDefined(switched) && switched.IsBool() && !switched.GetBool());
    t.Check("preset/the reply still may deliberate", !dialogue.HasKey("reasoning"));

    // And the resolution agrees with the file: the repair inherits the model and keeps its own
    // ceiling, which is the whole reason a slot resolves key by key.
    let resolved = AiNpcSlotFrom(slots, AiNpcSlotMechanicName(), null);
    t.EqString("preset/the repair is sent on the same model",
        resolved.model, AiNpcModelPresetNamed("normal").model);
    t.EqInt("preset/with its own budget",
        AiNpcJsonInt(resolved.params, "max_tokens", -1), AiNpcSlotMechanicMaxTokens());

    // Every pass named, so the file says which prompt each kind of work uses.
    let passes = AiNpcJsonObjectAt(patch, "passes");
    let names = AiNpcPassNames();
    let j = 0;
    while j < ArraySize(names) {
        let entry = AiNpcJsonObjectAt(passes, names[j]);
        t.Check(s"preset/\(names[j]) is bound", IsDefined(entry));
        t.EqString(s"preset/\(names[j]) names the slot it is sent on",
            AiNpcJsonString(entry, "slot"), AiNpcModelPresetSlotFor(names[j]));
        t.EqString(s"preset/\(names[j]) names its own recipe",
            AiNpcJsonString(entry, "recipe"), AiNpcPassRecipeName(names[j]));
        j += 1;
    }

    // A player who keeps their own recipes.json replaces the shipped book whole. A preset that
    // named a recipe they do not have would write a binding pointing at nothing.
    let theirs: array<ref<AiNpcConfigIssue>>;
    let small = AiNpcRecipeBookFromJson(
        ParseJson("{\"recipes\": {\"default\": {}}}") as JsonObject, "theirs", theirs);
    let modest = AiNpcJsonObjectAt(AiNpcModelPresetPatch(AiNpcModelPresetNamed("light"), small), "passes");
    t.EqString("preset/a recipe the book declares is written",
        AiNpcJsonString(AiNpcJsonObjectAt(modest, AiNpcLaneSpeaking()), "recipe"), "default");
    t.Check("preset/a recipe the book does not declare is left out",
        !AiNpcJsonObjectAt(modest, AiNpcLaneRepair()).HasKey("recipe"));
}

/// The action selection ///

// The mode is the whole of the switch: what the conversation prompt carries, and what is done
// with the reply. Both halves read the same setting, so they cannot disagree about which mode
// a turn is in.
func AiNpcTestActionSelector(t: ref<AiNpcTestRunner>) -> Void {
    // The answer a selector gives most turns, and the one that must never fire anything.
    t.EqString("selector/nothing to do reads as nothing",
        AiNpcActionSelectorTag(AiNpcActionSelectorNone()), "");
    t.EqString("selector/an empty answer reads as nothing", AiNpcActionSelectorTag(""), "");
    t.EqString("selector/prose that names no command reads as nothing",
        AiNpcActionSelectorTag("She did not agree to anything."), "");

    // Written as asked.
    t.EqString("selector/a bracketed command is taken",
        AiNpcActionSelectorTag("[ACTION:GIVE_EDDIES:500]"), "[ACTION:GIVE_EDDIES:500]");
    t.EqString("selector/a bracketed command inside a sentence is taken",
        AiNpcActionSelectorTag("The command is [ACTION:GIVE_EDDIES:500] here."),
        "[ACTION:GIVE_EDDIES:500]");

    // Written correctly in the wrong dress: 15 answers out of 20 on the probe came back
    // without the brackets, which are punctuation invented for finding a command inside prose
    // -- and there is no prose here to find it in.
    t.EqString("selector/an unbracketed command is dressed and taken",
        AiNpcActionSelectorTag("ACTION:GIVE_EDDIES:500"), "[ACTION:GIVE_EDDIES:500]");
    t.EqString("selector/and trailing words do not join it",
        AiNpcActionSelectorTag("ACTION:GIVE_EDDIES:500 as agreed"), "[ACTION:GIVE_EDDIES:500]");
    t.EqString("selector/a newline does not either",
        AiNpcActionSelectorTag("ACTION:GIVE_EDDIES:500\nThat is all."), "[ACTION:GIVE_EDDIES:500]");

    // "Nothing happened" is an answer, and it arrives in every dress a command does. All of
    // them mean what an empty answer means, and none of them is a command that failed.
    t.EqString("selector/NONE as a verb reads as nothing",
        AiNpcActionSelectorTag("ACTION:NONE"), "");
    t.EqString("selector/NONE in brackets reads as nothing",
        AiNpcActionSelectorTag("[ACTION:NONE]"), "");
    t.EqString("selector/NONE in a sentence reads as nothing",
        AiNpcActionSelectorTag("NONE -- she agreed to nothing."), "");
    t.EqString("selector/and the verb is read without regard to case",
        AiNpcActionSelectorTag("[ACTION:none]"), "");

    // Strict everywhere else: what comes out of here goes to the same dispatcher a reply's own
    // brackets do, so a selector cannot invent a shape the table does not know.
    t.EqString("selector/a half-written tag is not a command",
        AiNpcActionSelectorTag("ACTION:"), "");

    // The ask ends on the reply, not on a handover: a selector asked to continue would answer
    // with dialogue.
    let ask = AiNpcActionSelectorAsk("V: You still owe me.\n", "Judy Alvarez", "Sending it now.");
    t.Check("selector/the ask quotes the reply", StrContains(ask, "Judy Alvarez: Sending it now."));
    t.Check("selector/the ask keeps the thread", StrContains(ask, "V: You still owe me."));
    t.Check("selector/the ask offers the empty answer", StrContains(ask, AiNpcActionSelectorNone()));
    t.Check("selector/the ask never hands the turn over",
        !StrContains(ask, "start_header_id"));

    // The window is a budget as much as a window: this request runs once per reply.
    t.Check("selector/the window is bounded", AiNpcActionSelectorWindow() > 0);
    t.Check("selector/and short", AiNpcActionSelectorWindow() <= 10);
}

// A cap makes one failure possible that nothing else does, and it is silent: the model stops
// mid-sentence and the wire says so in one word. Every lane that can be capped asks.
func AiNpcTestTruncation(t: ref<AiNpcTestRunner>) -> Void {
    t.Check("budget/a completed answer is not truncated",
        !AiNpcReplyWasTruncated(ParseJson("{\"choices\": [{\"finish_reason\": \"stop\"}]}") as JsonObject));
    t.Check("budget/an answer cut off by the cap is",
        AiNpcReplyWasTruncated(ParseJson("{\"choices\": [{\"finish_reason\": \"length\"}]}") as JsonObject));
    t.Check("budget/a filtered answer is not a truncated one",
        !AiNpcReplyWasTruncated(ParseJson("{\"choices\": [{\"finish_reason\": \"content_filter\"}]}") as JsonObject));
    // A provider that says nothing is not a provider saying "cut": the compaction would be
    // thrown away on every answer from a backend that omits the field.
    t.Check("budget/a provider that reports nothing is not truncated",
        !AiNpcReplyWasTruncated(ParseJson("{\"choices\": [{}]}") as JsonObject));
    t.Check("budget/and neither is a body that could not be parsed",
        !AiNpcReplyWasTruncated(null));
}
