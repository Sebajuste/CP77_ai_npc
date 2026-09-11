module AiNpc

// L'etat du monde tel que le prompt le lit : quetes suivies, arcs, faits de romance.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

// The four ways AiNpcContextData used to be wrong, pinned so none of them can come back. All
// of it is reachable from a test because the table is a pure function of (contactId,
// questKey, objective): the journal read lives in the system, above it.
//
// The shipped resolver goes through the contact registry, which is a live system and does not
// exist while the self-tests run. What is asserted below is the CONTENT -- who says what
// about which quest -- so it reads the sheets, which is where that content lives.
func AiNpcTestQuestLine(contactId: String, questKey: String, objective: String) -> String {
    if Equals(StrLen(questKey), 0) {
        return "";
    }
    let sheet = AiNpcBuiltinSheet(contactId);
    if !IsDefined(sheet) {
        return "";
    }
    return AiNpcQuestBlock("", AiNpcQuestTextIn(sheet.questContexts, questKey, null), objective);
}

func AiNpcTestQuestContext(t: ref<AiNpcTestRunner>) -> Void {
    // 0. The resolver itself, on the one path that needs no registry: a contact nobody has
    //    a sheet for says nothing, rather than reaching into somebody else's.
    t.EqString("quest/unknown contact resolves to nothing",
        AiNpcQuestContextFor("nobody", "ghost_town", "", ""), "");

    // 1. Identification is single-vocabulary. Whatever comes in -- an editor name or a
    //    localized title -- leaves as one canonical key, and an unknown one is "" rather
    //    than a guess.
    t.EqString("quest/key from title", AiNpcQuestKey("", "Ghost Town"), "ghost_town");
    t.EqString("quest/key unknown", AiNpcQuestKey("", "Riders on the Storm (FR)"), "");
    t.EqString("quest/key empty", AiNpcQuestKey("", ""), "");
    // The editor name wins over the title, which is what makes a translated playthrough
    // resolve at all once the ids are captured.
    t.EqString("quest/id beats title", AiNpcQuestKey("Ghost Town", "Chevaucher l'orage"), "ghost_town");
    // The expansion resolves too, and the stretches where Songbird is held or gone do not:
    // an entry there would invite a questContext the game gives her no way to send.
    t.EqString("quest/expansion key", AiNpcQuestKey("", "Dog Eat Dog"), "dog_eat_dog");
    t.EqString("quest/expansion key from an apostrophe title",
        AiNpcQuestKey("", "I've Seen That Face Before"), "ive_seen_that_face_before");
    t.EqString("quest/songbird is held here", AiNpcQuestKey("", "Get It Together"), "");
    t.EqString("quest/songbird is not herself here", AiNpcQuestKey("", "Somewhat Damaged"), "");
    // A title with no objectives under it, covered end to end by the quest before it.
    t.EqString("quest/no second key for the same stretch",
        AiNpcQuestKey("", "Hole in the Sky"), "");

    // 2. Keyed by contact id, never by display name. "Panam Palmer" was the old key and
    //    must now resolve to nothing -- a display name is overridable, so it was never an
    //    identity.
    t.Check("quest/panam by id",
        NotEquals(StrLen(AiNpcTestQuestLine("panam", "riders_on_the_storm", "Find Saul")), 0));
    t.EqString("quest/display name is not a key",
        AiNpcTestQuestLine("Panam Palmer", "riders_on_the_storm", "Find Saul"), "");
    t.EqString("quest/unknown contact", AiNpcTestQuestLine("nobody", "ghost_town", ""), "");
    t.EqString("quest/no key", AiNpcTestQuestLine("panam", "", "Find Saul"), "");

    // 3. Content belongs to its own character. River Ward was being handed Rogue's block
    //    ("You are the Queen of Fixers"), Panam's ending and Takemura's epilogue.
    let river = AiNpcTestQuestLine("river_ward", "path_of_glory", "");
    t.EqString("quest/river has no path of glory", river, "");
    t.Check("quest/rogue has path of glory",
        NotEquals(StrLen(AiNpcTestQuestLine("rogue", "path_of_glory", "")), 0));
    t.EqString("quest/river has no watchtower",
        AiNpcTestQuestLine("river_ward", "all_along_the_watchtower", ""), "");
    t.Check("quest/panam has watchtower",
        NotEquals(StrLen(AiNpcTestQuestLine("panam", "all_along_the_watchtower", "")), 0));
    t.EqString("quest/river has no where is my mind",
        AiNpcTestQuestLine("river_ward", "where_is_my_mind", ""), "");
    t.Check("quest/takemura has where is my mind",
        NotEquals(StrLen(AiNpcTestQuestLine("takemura", "where_is_my_mind", "")), 0));
    // The blast radius of the misfiling, stated as the thing that must never be true again:
    // one character's block naming another character's role.
    t.Check("quest/river is never the queen of fixers",
        !StrContains(AiNpcTestQuestLine("river_ward", "nocturne_op55n1", ""), "Queen of Fixers"));

    // 4. An absent objective produces no clause at all. This is where "Tracked entry is not
    //    an Objective" used to reach the model as V's current situation.
    t.EqString("quest/no situation clause", AiNpcSituationClause(""), "");
    t.EqString("quest/situation clause", AiNpcSituationClause("Find Saul"), "V IS DOING THIS RIGHT NOW: Find Saul.");
    t.Check("quest/entry drops the clause when unknown",
        !StrContains(AiNpcTestQuestLine("panam", "riders_on_the_storm", ""), "V IS DOING THIS RIGHT NOW"));
    t.Check("quest/entry carries the clause when known",
        StrContains(AiNpcTestQuestLine("panam", "riders_on_the_storm", "Find Saul"), "V IS DOING THIS RIGHT NOW: Find Saul."));

    // The archive terminal is not Jackie. The post-heist guard lives at the impure edge, so
    // what is asserted here is the half that can be: "jackie_dead" has no entry of its own,
    // and therefore cannot be handed a block written in the dead man's first person.
    t.EqString("quest/jackie_dead has no first-person block",
        AiNpcTestQuestLine("jackie_dead", "the_heist", ""), "");
    t.Check("quest/jackie has the heist",
        NotEquals(StrLen(AiNpcTestQuestLine("jackie", "the_heist", "")), 0));

    // Every key the tables answer to is one AiNpcQuestKeyFor can produce. A key written
    // only in a character table is unreachable, and silently so.
    let keys = ["riders_on_the_storm", "with_a_little_help", "queen_of_the_highway",
        "all_along_the_watchtower", "both_sides_now", "ex_factor", "talkin_bout_a_revolution",
        "pisces", "pyramid_song", "playing_for_time", "down_on_the_street", "life_during_wartime",
        "play_it_safe", "search_and_destroy", "totalimmortal", "where_is_my_mind", "the_rescue",
        "the_ripperdoc", "the_ride", "the_pickup", "the_heist", "nocturne_op55n1", "ghost_town",
        "chippin_in", "blistering_love", "path_of_glory", "i_fought_the_law", "the_hunt",
        "following_the_river"];
    let contacts = ["panam", "judy", "takemura", "jackie", "river_ward", "rogue"];
    let reachable = 0;
    let i = 0;
    while i < ArraySize(keys) {
        let j = 0;
        let answered = false;
        while j < ArraySize(contacts) {
            if NotEquals(StrLen(AiNpcQuestContextFor(contacts[j], keys[i], "", "")), 0) {
                answered = true;
            }
            j += 1;
        }
        if answered {
            reachable += 1;
        }
        t.Check(s"quest/key '\(keys[i])' is answered by someone", answered);
        i += 1;
    }
    t.EqInt("quest/every canonical key is used", reachable, ArraySize(keys));
}

/// The built-in world lore ///

// Structural only. What the block SAYS is a property of the prose, and the repo pins prose in
// tools/lint.ps1 rather than here; what runtime can prove is the part that breaks silently --
// a block that lost its tag disappears into the surrounding prompt, and a rubric that fell
// out of the concatenation takes its rule with it without a single log line.
//
// The registry itself is a ScriptableSystem and needs a session; everything below is the pure
// half -- the bound, the merge, and the additive join. See AiNpcWorldKnowledge.reds.

// The romance facts replaced eight Mod Settings checkboxes. Nothing in the game can be
// asserted from here -- GetFact needs a session -- but the sheets can, and that is where
// the failure would be: a typo in a fact name reads as "never romanced", which looks
// exactly like a playthrough where the romance did not happen.
func AiNpcTestRomanceFacts(t: ref<AiNpcTestRunner>) -> Void {
    t.EqString("romance/panam fact", AiNpcSheetPanam().romanceFact, "sq027_panam_lover");
    t.EqString("romance/judy fact", AiNpcSheetJudy().romanceFact, "sq030_judy_lover");
    t.EqString("romance/river fact", AiNpcSheetRiver().romanceFact, "sq029_river_lover");
    t.EqString("romance/kerry fact", AiNpcSheetKerry().romanceFact, "sq028_kerry_relationship");

    // A romanceable character needs both halves: the fact to read, and the text to add when
    // it is set. One without the other is a romance that never shows or never resolves.
    t.Check("romance/panam has a romance rubric",
        NotEquals(StrLen(AiNpcSheetPanam().romance), 0));
    t.Check("romance/judy has a romance rubric",
        NotEquals(StrLen(AiNpcSheetJudy().romance), 0));
    t.Check("romance/river has a romance rubric",
        NotEquals(StrLen(AiNpcSheetRiver().romance), 0));
    t.Check("romance/kerry has a romance rubric",
        NotEquals(StrLen(AiNpcSheetKerry().romance), 0));

    // THE ADDITIVE INVARIANT, and the one worth a test rather than a comment.
    //
    // <relationship> is now injected whether or not the romance exists, so anything in it
    // that is only true in one of the two states contradicts the other. The refusal is
    // exactly that sentence, which is why it moved to AiNpcRomanceRefusalLine -- and why a
    // sheet quietly getting it back would make a romanced character reject V mid-flirt.
    //
    // Only the four romanceable ones. Songbird keeps hers in the plain relationship,
    // correctly: she has no second state for it to be false in, and nothing else in the cast
    // says anything about advances at all.
    //
    // Keyed on "advance" rather than on the sentence: the wording is meant to be edited, and a
    // test pinning it would fail on every rewrite while catching none of what it guards.
    t.EqBool("romance/panam does not refuse in the plain relationship",
        StrContains(AiNpcSheetPanam().relationship, "advance"), false);
    t.EqBool("romance/judy does not refuse in the plain relationship",
        StrContains(AiNpcSheetJudy().relationship, "advance"), false);
    t.EqBool("romance/river does not refuse in the plain relationship",
        StrContains(AiNpcSheetRiver().relationship, "advance"), false);
    t.EqBool("romance/kerry does not refuse in the plain relationship",
        StrContains(AiNpcSheetKerry().relationship, "advance"), false);
    t.EqBool("romance/the refusal is stated somewhere",
        StrContains(AiNpcRomanceRefusalLine(), "advance"), true);

    // The state it states, and the one it must not: the save says the romance HAS NOT
    // HAPPENED, not that it never can.
    t.EqBool("romance/the refusal does not close the future",
        StrContains(AiNpcRomanceRefusalLine(), "never will")
        || StrContains(AiNpcRomanceRefusalLine(), "nothing is going to"), false);

    // The manner belongs to the sheet. "Outright" asked four characters who refuse very
    // differently to refuse the same flat way.
    t.EqBool("romance/the refusal leaves the manner to the character",
        StrContains(AiNpcRomanceRefusalLine(), "outright"), false);

    // CAPABILITY IS ONE CLAIM, and this is where it is checked to have one source.
    //
    // "Could V be with this character" and "are they" are different questions -- the second
    // reads the save, the first is a fixed property of the character and is declared as one.
    // Two fields, deliberately, because they are two claims; what is NOT acceptable is the two
    // disagreeing, and both ways of disagreeing are invisible in game: a fact without the flag
    // is a character who never refuses before the romance, the flag without a fact is one who
    // refuses for ever.
    //
    // Nothing in the compiler pairs them. This loop is what does.
    let cast = AiNpcBuiltinCast();
    let i = 0;
    let capable = 0;
    while i < ArraySize(cast) {
        let provider = AiNpcDefContactProvider.Create(cast[i]);
        let named = NotEquals(StrLen(cast[i].romanceFact), 0);
        if named {
            capable += 1;
            t.Check(s"romance/\(cast[i].contactId) declares the capability next to the fact",
                provider.IsRomanceCapable());
            t.Check(s"romance/\(cast[i].contactId) has the text to add when it is set",
                NotEquals(StrLen(cast[i].romance), 0));
            t.Check(s"romance/\(cast[i].contactId) is not capable without the flag",
                cast[i].romanceable);
        } else {
            // Rogue, Songbird and Viktor say the refusal in their own relationship, which is
            // correct: they have no second state for it to be false in. A capability here
            // would add the generic line on top of theirs.
            t.EqBool(s"romance/\(cast[i].contactId) claims no capability",
                provider.IsRomanceCapable(), false);
        }
        i += 1;
    }
    t.EqInt("romance/four of the cast are romanceable", capable, 4);

    // The flag still answers for a contact the base game never heard of: no fact to read, so
    // nothing else can distinguish it.
    let mine = new AiNpcCharacterDef();
    mine.contactId = "some_mod_contact";
    mine.romanceable = true;
    t.Check("romance/a mod contact is capable by its flag",
        AiNpcDefContactProvider.Create(mine).IsRomanceCapable());

    // The rubric is one extension line among everybody else's, and the merge clamps a line
    // past AiNpcNowLineBudget. A sheet written past it loses its tail to a log message
    // nobody reads, which is the quietest way for characterisation to go missing.
    t.Check("romance/panam fits the event budget",
        StrLen(AiNpcSheetPanam().romance) <= AiNpcNowLineBudget());
    t.Check("romance/judy fits the event budget",
        StrLen(AiNpcSheetJudy().romance) <= AiNpcNowLineBudget());
    t.Check("romance/river fits the event budget",
        StrLen(AiNpcSheetRiver().romance) <= AiNpcNowLineBudget());
    t.Check("romance/kerry fits the event budget",
        StrLen(AiNpcSheetKerry().romance) <= AiNpcNowLineBudget());

    // No vanilla romance exists for these, so there is no fact to read. They must carry no
    // fact at all rather than some neighbouring one that happens to be set.
    t.EqString("romance/songbird has no fact", AiNpcSheetSongbird().romanceFact, "");
    t.EqString("romance/rogue has no fact", AiNpcSheetRogue().romanceFact, "");
    t.EqString("romance/viktor has no fact", AiNpcSheetViktor().romanceFact, "");
    t.EqString("romance/takemura has no fact", AiNpcSheetTakemura().romanceFact, "");
    t.EqString("romance/jackie has no fact", AiNpcSheetJackie().romanceFact, "");

    // A character with no fact is never romanced, and this one needs no session: the
    // lookup returns before the quest system is touched.
    t.EqBool("romance/no fact means not romanced", AiNpcRomanceFactIsSet(""), false);

    let mine = new AiNpcCharacterDef();
    mine.contactId = "SomeModContact01";
    mine.romanced = true;
    t.EqBool("romance/a mod contact answers for itself",
        AiNpcDefContactProvider.Create(mine).IsRomanced(), true);
}

/// Quest context ///

// The text belongs to the character and the situation belongs to V, and this is where the
// two are put together. Pure: no journal, no session.

// The text belongs to the character and the situation belongs to V, and this is where the
// two are put together. Pure: no journal, no session.
func AiNpcTestQuestSheets(t: ref<AiNpcTestRunner>) -> Void {
    let panam = AiNpcSheetPanam();
    t.Check("quests/panam has a line for her own quest",
        NotEquals(StrLen(AiNpcQuestTextIn(panam.questContexts, "riders_on_the_storm", null)), 0));
    t.EqString("quests/she has none for someone else's",
        AiNpcQuestTextIn(panam.questContexts, "both_sides_now", null), "");
    t.EqString("quests/an unknown key says nothing",
        AiNpcQuestTextIn(panam.questContexts, "no_such_quest", null), "");

    // An entry carries the ACCOUNT and nothing else. The heading, the labels and the live
    // objective are written by AiNpcQuestBlock, so an entry that spelled any of them itself
    // would put them in the prompt twice -- and {situation} is no longer substituted anywhere,
    // so a leftover placeholder would reach the model as five literal characters.
    let cast = AiNpcBuiltinCast();
    let i = 0;
    let entries = 0;
    let structural = 0;
    while i < ArraySize(cast) {
        let j = 0;
        while j < ArraySize(cast[i].questContexts) {
            entries += 1;
            let text = cast[i].questContexts[j].text;
            if StrContains(text, "{situation}") || StrContains(text, "WHERE THINGS STAND")
                || StrContains(text, "V IS DOING THIS RIGHT NOW") || StrContains(text, "MISSION:") {
                structural += 1;
            }
            j += 1;
        }
        i += 1;
    }
    t.Check("quests/the cast has quest lines", entries > 20);
    t.EqInt("quests/no entry carries the mod's own structure", structural, 0);

    // The block itself: the three parts in order, and the two absences that must not leave a
    // dangling label behind them.
    t.EqString("quests/block with every part",
        AiNpcQuestBlock("Ghost Town", "You are waiting.", "stealing a tank"),
        "Ghost Town. WHERE THINGS STAND: You are waiting. V IS DOING THIS RIGHT NOW: stealing a tank.");
    t.EqString("quests/no objective, no clause",
        AiNpcQuestBlock("Ghost Town", "You are waiting.", ""),
        "Ghost Town. WHERE THINGS STAND: You are waiting.");
    t.EqString("quests/no title, no heading",
        AiNpcQuestBlock("", "You are waiting.", ""), "WHERE THINGS STAND: You are waiting.");
    t.EqString("quests/nothing to say, no block at all",
        AiNpcQuestBlock("Ghost Town", "", "stealing a tank"), "");
}

/// Stages of one quest ///

// A quest is tracked from its first second, so an account written for its end was mounted at
// its beginning: Takemura named Oda's refusal and Hanako's parade before V had walked to the
// meeting. A sheet dates its stages, and the save says which one is true.
//
// The gate is stubbed rather than read: what is asserted is the selection, and the quests
// system does not exist while the self-tests run.
class AiNpcTestFactGate extends AiNpcFactGate {
    let posed: array<String>;

    public func IsSet(fact: String) -> Bool {
        return ArrayContains(this.posed, fact);
    }
}

func AiNpcTestPosed(posed: array<String>) -> ref<AiNpcFactGate> {
    let gate = new AiNpcTestFactGate();
    gate.posed = posed;
    return gate;
}

func AiNpcTestQuestStages(t: ref<AiNpcTestRunner>) -> Void {
    let entries: array<ref<AiNpcQuestLine>>;
    ArrayPush(entries, AiNpcQuest("q", "arranged"));
    ArrayPush(entries, AiNpcQuestStage("q", "met", "refused"));
    ArrayPush(entries, AiNpcQuestStage("q", "paid", "route bought"));
    ArrayPush(entries, AiNpcQuest("other", "someone else's quest"));

    let none: array<String>;
    t.EqString("stages/nothing posed yet, the quest opens on its first account",
        AiNpcQuestTextIn(entries, "q", AiNpcTestPosed(none)), "arranged");
    t.EqString("stages/a posed fact moves the account on",
        AiNpcQuestTextIn(entries, "q", AiNpcTestPosed(["met"])), "refused");
    t.EqString("stages/the last posed stage wins",
        AiNpcQuestTextIn(entries, "q", AiNpcTestPosed(["met", "paid"])), "route bought");
    // Order of declaration decides, not order of posing: a save loaded out of sequence still
    // reads as the story does.
    t.EqString("stages/a late fact alone still wins",
        AiNpcQuestTextIn(entries, "q", AiNpcTestPosed(["paid"])), "route bought");
    t.EqString("stages/no gate reads no save",
        AiNpcQuestTextIn(entries, "q", null), "arranged");
    t.EqString("stages/another quest is untouched",
        AiNpcQuestTextIn(entries, "other", AiNpcTestPosed(["met", "paid"])), "someone else's quest");

    // An outcome the game writes as an absence -- Oda spared is q112_oda_dead never posed --
    // holds a stage back, and the stage before it is what stays true.
    let held: array<ref<AiNpcQuestLine>>;
    ArrayPush(held, AiNpcQuest("q", "opening"));
    let late = AiNpcQuestStage("q", "closed", "he died");
    late.unlessFact = "spared";
    ArrayPush(held, late);
    t.EqString("stages/held back by an absence, the account before it stands",
        AiNpcQuestTextIn(held, "q", AiNpcTestPosed(["closed", "spared"])), "opening");
    t.EqString("stages/not held back, it speaks",
        AiNpcQuestTextIn(held, "q", AiNpcTestPosed(["closed"])), "he died");

    // A dated stage is never the fallback: a quest whose opening account nobody wrote says
    // nothing until its moment comes, rather than saying its end from the first second.
    let dated: array<ref<AiNpcQuestLine>>;
    ArrayPush(dated, AiNpcQuestStage("q", "met", "refused"));
    t.EqString("stages/a dated stage does not speak before its fact",
        AiNpcQuestTextIn(dated, "q", AiNpcTestPosed(none)), "");
}

/// Commands a sheet may declare ///

// The two rules that decide whether a declaration is accepted, and the fragment the model
// reads. Pure: no registry, no quests system. The apply itself is one SetFact and cannot be
// asserted without a session, which is exactly why every decision AROUND it is here.
