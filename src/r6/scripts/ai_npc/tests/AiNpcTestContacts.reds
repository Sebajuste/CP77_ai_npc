module AiNpc

// Les fiches et le carnet : identite stable, variantes, portes, actions declarees.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

// jackie_dead is the one shipped contact that never reaches a model: it returns one recorded
// line to every message. Pure -- a sheet is data and reads no game state, which is what lets
// this run without a session; the language it is resolved against is the provider's half.
func AiNpcTestArchiveNumber(t: ref<AiNpcTestRunner>) -> Void {
    let archive = AiNpcSheetJackieArchive();

    let english = AiNpcLineTextIn(archive.scriptedReply, "English");
    t.Check("archive/answers something", NotEquals(StrLen(english), 0));

    // The three answers of the protocol must stay three: a recorded line is neither "no
    // opinion" nor silence, or the number would be handed to the model after all.
    t.EqBool("archive/its line is not silence", AiNpcIsSilentReply(english), false);

    // A language with no entry falls back rather than going quiet, which is the failure a
    // table of literals invites: a player in an unlisted locale would get an empty bubble.
    t.EqString("archive/an unlisted language falls back",
        AiNpcLineTextIn(archive.scriptedReply, "Klingon"), english);

    // Every language the mod speaks has its own line -- the fallback is for locales the enum
    // does not name, not for the ones it does.
    let names = AiNpcLanguageNames();
    let i = 0;
    let translated = 0;
    while i < ArraySize(names) {
        let line = AiNpcLineTextIn(archive.scriptedReply, names[i]);
        if NotEquals(StrLen(line), 0) && (Equals(names[i], "English") || NotEquals(line, english)) {
            translated += 1;
        }
        i += 1;
    }
    t.EqInt("archive/one line per language", translated, ArraySize(names));

    // It accumulates nothing: an unanswered number has no relationship to remember.
    t.EqBool("archive/remembers nothing", archive.allowsMemory, false);

    // What the sheet must NOT carry any more. A rule block existed only to argue the model
    // into behaving like a machine, and there is no model left to argue with.
    t.Check("archive/carries no rule block", !IsDefined(archive.prompts));

    // Nobody else answers from a script: a character who did would be one the player cannot
    // talk to, and it would look exactly like a broken backend.
    let cast = AiNpcBuiltinCast();
    let j = 0;
    let scripted = 0;
    while j < ArraySize(cast) {
        if ArraySize(cast[j].scriptedReply) > 0 {
            scripted += 1;
        }
        j += 1;
    }
    t.EqInt("archive/it is the only one", scripted, 1);

    // The text Jackie's own sheet borrows for its postHeist variant. Kept here rather than
    // repeated there, so the two cannot drift; asserting it exists is what makes deleting it
    // fail here instead of in a playthrough past the heist.
    t.Check("archive/still carries the text Jackie's variant reads",
        NotEquals(StrLen(archive.bio), 0) && NotEquals(StrLen(archive.relationship), 0));

    t.Check("archive/no shipped character carries a rule block",
        !IsDefined(AiNpcSheetJudy().prompts) && !IsDefined(AiNpcSheetJackie().prompts));
}

/// Contact hashes ///

func AiNpcTestContactHash(t: ref<AiNpcTestRunner>) -> Void {
    // Stability is the whole contract: a hash that changes between sessions detaches a
    // messenger thread from its history. Pinning a literal is what makes a change to the
    // derivation fail here instead of in someone's save.
    t.EqInt("hash/is deterministic", AiNpcContactHash("panam"), AiNpcContactHash("panam"));
    t.Check("hash/differs by id", AiNpcContactHash("panam") != AiNpcContactHash("judy"));
    t.Check("hash/differs by case", AiNpcContactHash("Panam") != AiNpcContactHash("panam"));
    t.Check("hash/differs by order", AiNpcContactHash("ab") != AiNpcContactHash("ba"));

    // Unknown characters map to 0 rather than being skipped, so these must not collide.
    t.Check("hash/unknown characters still count", AiNpcContactHash("a?b") != AiNpcContactHash("ab"));

    t.Check("hash/empty id is in range", AiNpcContactHash("") >= 1000000000);
    t.Check("hash/stays in the documented range", AiNpcContactHash("JoytoysVIP101") >= 1000000000);
    t.Check("hash/stays under the documented ceiling", AiNpcContactHash("JoytoysVIP101") <= 1008000009);
}

/// Contact validation ///

func AiNpcTestContactSupport(t: ref<AiNpcTestRunner>) -> Void {
    let ids = AiNpcGetAllContactIds();
    t.EqInt("contacts/list is populated", ArraySize(ids), 11);

    // Regression: this was written as ArrayContains(AiNpcGetAllContactIds(), name).
    // It compiled, and returned false for every name -- so no contact was ever
    // recognised, the T hint never appeared, and the chat could not be opened at all.
    // Shipping a character no longer implies V can write to them: AiNpcIsContactReachable asks
    // the story first. The two assertions below pin the SAFE side of that read -- with no quest
    // system there is nothing to go on, and a contact hidden on no evidence reads in game as
    // the mod having lost it.
    t.EqBool("contacts/a contact with no story rule is in play",
        AiNpcContactIsInPlay("panam"), true);
    t.EqBool("contacts/a contact with a story rule is in play without a session",
        AiNpcContactIsInPlay("songbird"), true);
    t.EqBool("contacts/songbird is supported offline", AiNpcIsContactSupported("songbird"), true);

    // The other half of the same idea: a confidence has to be earned in the save. False is the
    // safe side here, unlike in-play above -- claiming one that never happened is what put "you
    // are both dying of the same thing" in front of a V who had not been told.
    t.EqBool("contacts/no confidence without a session", AiNpcHasConfidedInV("songbird"), false);
    t.EqBool("contacts/no confidence for a contact with no rule", AiNpcHasConfidedInV("panam"), false);
    let vocabulary = AiNpcVariantConditions();
    t.EqBool("variants/the vocabulary carries the confidence",
        ArrayContains(vocabulary, "confidedInV"), true);
    // Both states carry the refusal: a variant field replaces, it does not add.
    t.EqBool("romance/songbird refuses before she confides",
        StrContains(AiNpcSheetSongbird().relationship, "do not take it up"), true);

    t.EqBool("contacts/regression: panam is supported", AiNpcIsContactSupported("panam"), true);
    t.EqBool("contacts/judy is supported", AiNpcIsContactSupported("judy"), true);
    t.EqBool("contacts/last entry is supported", AiNpcIsContactSupported("stud"), true);
    t.EqBool("contacts/unknown is rejected", AiNpcIsContactSupported("delamain"), false);
    t.EqBool("contacts/empty is rejected", AiNpcIsContactSupported(""), false);
    t.EqBool("contacts/case sensitive", AiNpcIsContactSupported("Panam"), false);

    // Every declared id has a sheet, and every sheet is declared. This is the drift the
    // shape is meant to make impossible -- one file per character, one line per character
    // -- and it is asserted rather than assumed because AiNpcGetAllContactIds is written
    // out by hand: it is read on every message, and building the cast to answer it would
    // allocate a dozen long strings each time.
    let cast = AiNpcBuiltinCast();
    t.EqInt("cast/one sheet per declared contact", ArraySize(cast), ArraySize(ids));

    let i = 0;
    let matched = 0;
    let described = 0;
    while i < ArraySize(cast) {
        if ArrayContains(ids, cast[i].contactId) {
            matched += 1;
        }
        // A sheet with no name or no bio is a character the model is told nothing about.
        if NotEquals(StrLen(cast[i].displayName), 0) && NotEquals(StrLen(cast[i].bio), 0) {
            described += 1;
        }
        i += 1;
    }
    t.EqInt("cast/every sheet is a declared contact", matched, ArraySize(cast));
    t.EqInt("cast/every sheet has a name and a bio", described, ArraySize(cast));

    t.Check("cast/a sheet is found by id", IsDefined(AiNpcBuiltinSheet("panam")));
    t.Check("cast/an unknown id has no sheet", !IsDefined(AiNpcBuiltinSheet("some_other_mods_contact")));

    // A copy must be writable without touching the shipped sheet -- the config loader
    // writes a player's overrides onto one of these, once per launch.
    let copy = AiNpcCopySheet(AiNpcBuiltinSheet("panam"));
    copy.bio = "Overridden.";
    ArrayClear(copy.variants);
    t.Check("cast/a copy does not write back to the sheet",
        NotEquals(AiNpcBuiltinSheet("panam").bio, "Overridden."));
    // Bound to a local first: an array intrinsic reads a call result from a stack slot that
    // is not stable, which compiles clean and answers zero.
    let jackie = AiNpcSheetJackie();
    t.EqInt("cast/a copy owns its variant list", ArraySize(jackie.variants), 1);

    // Reading the cast must not CHANGE which contact is selected. The side effect this
    // replaces made the question destructive: iterating the contact list -- as this very
    // test file does above -- repointed the open conversation at whatever it looked at last.
    //
    // Asserted on a session rather than on AiNpcSystem: the refusal moved to the door when the
    // phone stopped keeping a second copy of the contact, so it no longer needs a service to
    // exist and this runs at game start like everything else here.
    let session = new AiNpcChatSession();
    session.Show("panam");
    t.EqBool("door/an empty id opens nothing", AiNpcOpenConversation(session, ""), false);
    t.EqString("door/an empty id leaves the thread alone", session.GetShownContactId(), "panam");
}

/// The conversation door ///

func AiNpcTestDoor(t: ref<AiNpcTestRunner>) -> Void {
    t.EqBool("door/showing another contact opens", AiNpcConversationOpening("panam", "judy"), true);
    t.EqBool("door/showing nothing yet opens", AiNpcConversationOpening("", "judy"), true);
    // A HUD rebuild repaints the chat on the live tree without closing it; counted as an
    // opening it would announce a conversation the player never started.
    t.EqBool("door/repainting the same thread does not open",
             AiNpcConversationOpening("panam", "panam"), false);
    t.EqBool("door/an empty request is never an opening",
             AiNpcConversationOpening("panam", ""), false);

    // The registry answers for whichever surface has a thread up, and skips one that is
    // registered with nothing shown -- the terminal on its contact list.
    let empty: array<ref<AiNpcChatSession>>;
    t.EqString("door/nothing on screen has no contact", AiNpcShownContactId(empty), "");

    let idle = new AiNpcChatSession();
    let live = new AiNpcChatSession();
    live.Show("judy");
    let sessions: array<ref<AiNpcChatSession>>;
    ArrayPush(sessions, idle);
    ArrayPush(sessions, live);
    t.EqString("door/a surface showing nothing is skipped", AiNpcShownContactId(sessions), "judy");
}

/// Deduced state ///

// The romance facts replaced eight Mod Settings checkboxes. Nothing in the game can be
// asserted from here -- GetFact needs a session -- but the sheets can, and that is where
// the failure would be: a typo in a fact name reads as "never romanced", which looks
// exactly like a playthrough where the romance did not happen.

// The two rules that decide whether a declaration is accepted, and the fragment the model
// reads. Pure: no registry, no quests system. The apply itself is one SetFact and cannot be
// asserted without a session, which is exactly why every decision AROUND it is here.
func AiNpcTestSheetActions(t: ref<AiNpcTestRunner>) -> Void {
    t.Check("actions/a plain tag is well formed", AiNpcActionTagIsWellFormed("[ACTION:BOOK]"));
    t.Check("actions/a bare word is not", !AiNpcActionTagIsWellFormed("BOOK"));
    t.Check("actions/an unterminated tag is not", !AiNpcActionTagIsWellFormed("[ACTION:BOOK"));
    t.Check("actions/a space inside is not", !AiNpcActionTagIsWellFormed("[ACTION:GO HOME]"));
    // "[ACTION:]" is nine characters and names nothing. The parser would find it, nobody
    // could claim it, and it would reach the player as a bracket.
    t.Check("actions/an empty name is not", !AiNpcActionTagIsWellFormed("[ACTION:]"));

    // The namespace, and it is the whole of what keeps a command a model can be talked into
    // from reaching vanilla quest state.
    t.Check("actions/ainpc_ is writable", AiNpcActionFactIsWritable("ainpc_owes_favour"));
    t.Check("actions/a vanilla fact is not", !AiNpcActionFactIsWritable("q101_started"));
    t.Check("actions/the bare prefix names nothing", !AiNpcActionFactIsWritable("ainpc_"));
    t.Check("actions/a space is not a fact name", !AiNpcActionFactIsWritable("ainpc_two words"));

    // The slot definitions, held to both directions. A slot with no definition hands the model
    // a name nobody explained; a definition no slot cites is text teaching a word that never
    // appears. Neither fails at run time -- the first produces a plausible wrong tag, the
    // second a slightly longer prompt -- so the refusal has to happen at declaration.
    let paramRefusal = "";
    let paramPattern = AiNpcParseActionPattern("[ACTION:TRICK:{venue}:{hour}:{days?}]",
                                               paramRefusal);
    t.Check("actions/the pattern under the parameter tests parses", IsDefined(paramPattern));

    let complete: array<ref<AiNpcActionParam>>;
    ArrayPush(complete, AiNpcParam("{venue}", "one of the places listed."));
    ArrayPush(complete, AiNpcParam("{hour}", "on the 24-hour clock."));
    // Defined without the optional mark, cited with it: one slot, asked for twice.
    ArrayPush(complete, AiNpcParam("{days}", "0 tonight, 1 tomorrow."));
    t.EqString("actions/a covering set of parameters is accepted",
        AiNpcActionParamsRefusal(paramPattern, complete), "");

    let unused: array<ref<AiNpcActionParam>>;
    ArrayPush(unused, AiNpcParam("{venue}", "one of the places listed."));
    ArrayPush(unused, AiNpcParam("{every}", "days between two meetings."));
    t.Check("actions/a parameter no slot cites is refused",
        NotEquals(StrLen(AiNpcActionParamsRefusal(paramPattern, unused)), 0));

    let twice: array<ref<AiNpcActionParam>>;
    ArrayPush(twice, AiNpcParam("{venue}", "one of the places listed."));
    ArrayPush(twice, AiNpcParam("{venue}", "somewhere else entirely."));
    t.Check("actions/the same parameter defined twice is refused",
        NotEquals(StrLen(AiNpcActionParamsRefusal(paramPattern, twice)), 0));

    let bareName: array<ref<AiNpcActionParam>>;
    ArrayPush(bareName, AiNpcParam("venue", "one of the places listed."));
    t.Check("actions/a parameter named without braces is refused",
        NotEquals(StrLen(AiNpcActionParamsRefusal(paramPattern, bareName)), 0));

    let empty: array<ref<AiNpcActionParam>>;
    ArrayPush(empty, AiNpcParam("{venue}", ""));
    t.Check("actions/a parameter with no definition is refused",
        NotEquals(StrLen(AiNpcActionParamsRefusal(paramPattern, empty)), 0));

    // The optional mark belongs to the pattern, which is the half that says what may be left
    // out. Defining "{days?}" would be naming a slot that does not exist under that name.
    t.EqString("actions/an optional slot is named without its mark",
        AiNpcSlotName("{days?}"), "{days}");
    t.EqString("actions/a plain slot keeps its name", AiNpcSlotName("{venue}"), "{venue}");
    t.EqString("actions/a literal segment is not a slot", AiNpcSlotName("NOTELL"), "");

    let actions: array<ref<AiNpcActionDef>>;
    ArrayPush(actions, AiNpcAction("[ACTION:BOOK]", "Emit when V takes the job.", "ainpc_booked"));
    ArrayPush(actions, AiNpcAction("[ACTION:OWES]", "Emit when V owes you one.", "ainpc_owes"));

    // A sheet declares on the same lane a mod does, so its declarations are patterns and the
    // block the model reads is rendered from them. There is no second fragment builder to keep
    // in step with a second claim list -- which is what the two of them drifting apart cost.
    let tags = AiNpcActionsTags(actions);
    t.EqInt("actions/every declaration is listed", ArraySize(tags), 2);

    let refusal = "";
    let i = 0;
    while i < ArraySize(tags) {
        let pattern = AiNpcParseActionPattern(tags[i], refusal);
        t.Check(s"actions/\(tags[i]) is a pattern the dispatcher can match", IsDefined(pattern));
        if IsDefined(pattern) {
            t.EqInt(s"actions/\(tags[i]) carries no field a sheet could not validate",
                pattern.arity, 0);
        }
        i += 1;
    }

    // A sheet's handler writes its fact and nothing else, whatever the world is doing: the
    // only effect data may have is idempotent by construction.
    let handler = AiNpcDataActionHandler.Create(AiNpcAction("[ACTION:X]", "t", "q101_started"));
    let noParams: array<String>;
    let smuggledResult = handler.OnAction(new AiNpcContactContext(), noParams);
    t.EqBool("actions/a vanilla fact is refused through the handler too",
        smuggledResult.applied, false);

    // A declaration nobody made cannot be applied. The apply re-checks the namespace itself,
    // so this holds even for a sheet compiled into the mod, which no loader ever validated.
    t.Check("actions/nothing to apply is a refusal", !AiNpcApplyDataAction(null));
    let smuggled = AiNpcAction("[ACTION:X]", "trigger", "q101_started");
    t.Check("actions/a vanilla fact is refused at the write", !AiNpcApplyDataAction(smuggled));

    // The shipped cast, against the same rules a file is held to. A sheet is code and is
    // never validated at load, so this is the only thing standing between a typo in cast\
    // and a bracket in the chat.
    let cast = AiNpcBuiltinCast();
    let c = 0;
    let declared = 0;
    while c < ArraySize(cast) {
        let a = 0;
        while a < ArraySize(cast[c].actions) {
            let action = cast[c].actions[a];
            declared += 1;
            t.Check(s"actions/\(cast[c].contactId) declares a well-formed \(action.tag)",
                AiNpcActionTagIsWellFormed(action.tag));
            t.Check(s"actions/\(cast[c].contactId) writes inside the namespace",
                AiNpcActionFactIsWritable(action.fact));
            t.Check(s"actions/\(cast[c].contactId) says when to emit \(action.tag)",
                NotEquals(StrLen(action.prompt), 0));
            a += 1;
        }
        c += 1;
    }
    t.Check("actions/the cast declares at least one command", declared > 0);
}

/// The variant field vocabulary ///

// One accessor now answers for every variantable field, so the failure this guards is a
// field added to AiNpcCharacterVariant and forgotten in AiNpcVariantField: it would answer
// "" for ever, silently, and only in the playthroughs where the condition holds.

// One accessor now answers for every variantable field, so the failure this guards is a
// field added to AiNpcCharacterVariant and forgotten in AiNpcVariantField: it would answer
// "" for ever, silently, and only in the playthroughs where the condition holds.
func AiNpcTestVariantFields(t: ref<AiNpcTestRunner>) -> Void {
    let variant = AiNpcVariant("postHeist");
    variant.bio = "bio";
    variant.relationship = "relationship";
    variant.liveContext = "liveContext";
    variant.speechStyle = "speechStyle";
    variant.intent = "intent";

    // Every field of the vocabulary reads back what was written to it. The values are the
    // field names on purpose: a switch branch pointing at the wrong member reads as a
    // mismatch here rather than as text appearing in the wrong section of a prompt.
    let fields = AiNpcVariantFields();
    let i = 0;
    while i < ArraySize(fields) {
        t.EqString(s"variants/\(fields[i]) reads back", AiNpcVariantField(variant, fields[i]), fields[i]);
        i += 1;
    }

    t.EqString("variants/an unknown field says nothing", AiNpcVariantField(variant, "romance"), "");
    t.EqString("variants/no variant says nothing", AiNpcVariantField(null, "bio"), "");
}
