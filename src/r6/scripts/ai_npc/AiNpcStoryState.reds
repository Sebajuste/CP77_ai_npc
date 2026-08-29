// Quest facts, read rather than configured: everything here is something the playthrough has
// already decided, so the save is the authority and loading an older one flips the answers
// back on its own.

module AiNpc

public static func AiNpcIsPostHeist(game: GameInstance) -> Bool {
    let qs = GameInstance.GetQuestsSystem(game);
    return
        qs.GetFact(n"q101_started") > 0 ||
        qs.GetFact(n"q005_jackie_to_hospital") > 0 ||
        qs.GetFact(n"q005_jackie_to_mama") > 0 || qs.GetFact(n"q005_done") > 0;
}

// Takes the fact name, because the mapping from character to fact is a property of the
// character and lives on their sheet. This half is only the read:
//
//   Panam  sq027_panam_lover          River  sq029_river_lover
//   Judy   sq030_judy_lover           Kerry  sq028_kerry_relationship
//
// The *_romanceable facts are used by no sheet: they mark that the arc is still open, which is
// not the claim "V and this character are together". Not gated on V's gender either -- the
// base game restricts who can romance whom, a mod can lift that, and the fact is correct
// either way.
func AiNpcRomanceFactIsSet(factName: String) -> Bool {
    if Equals(StrLen(factName), 0) {
        return false;
    }

    let fact = StringToName(factName);
    if !IsNameValid(fact) {
        return false;
    }

    let questsSystem = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(questsSystem) {
        return false;
    }
    return questsSystem.GetFact(fact) > 0;
}

/// How an arc ended ///
//
// A romance has three states, not two: never started, together, refused. A single `*_lover`
// fact makes "V never tried" and "V said no" the same prompt, and the same generic line
// telling the character to reject advances -- right for the first, wrong for the second.
//
// The third cannot be derived from the other two, and the base game does not record it the
// same way twice. Measured 2026-08-24 from the quest graphs in basegame_4_gamedata; the method
// and the full survey are in docs\ARC_FACTS.md:
//
//   Judy    sq030_failed                     an explicit failure fact
//   Kerry   sq028_kerry_goes_home_alone      a fact that describes a gesture
//   River   sq029_done without the lover     no failure fact; the arc simply closed
//
// Three names, three shapes. A pair of fact names on the sheet expresses the first only, and a
// predicate language in JSON would let a data file ask the game anything -- the one thing the
// variant vocabulary prevents. So the sheets carry the text, keyed on a condition name, and
// the awkward part lives here in one switch.
//
// Panam is missing on purpose: nothing under base\quest\side_quests\sq027\ exists in the
// archive index, so her failure fact has not been found. She answers false rather than resting
// on a guess -- a wrong fact name is silent, and would make her cold for the whole playthrough
// of somebody who never refused her.
func AiNpcRomanceFailedFor(contactId: String) -> Bool {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return false;
    }

    switch contactId {
        case "judy":
            return quests.GetFact(n"sq030_failed") > 0;
        case "kerry_eurodyne":
            return quests.GetFact(n"sq028_kerry_goes_home_alone") > 0;
        // Two reads rather than one, because there is no third fact to lean on:
        // sq029_conclusion sets sq029_done on every path through it, romance or not.
        case "river_ward":
            return quests.GetFact(n"sq029_done") > 0 && quests.GetFact(n"sq029_river_lover") <= 0;
    }
    return false;
}

// Randy Cassidy did not come out of The Hunt alive. Not a romance state, which is why it is
// its own question: choosing the wrong farm gets the boy killed, which closes the romance and
// changes the man, including for a V he could never have romanced. Folded into `romanceFailed`
// it would say nothing to that playthrough.
//
// Both halves are read: sq021_randy_saved alone is 0 in a save that has not reached the quest.
func AiNpcRandyIsDead() -> Bool {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return false;
    }
    return quests.GetFact(n"sq021_done") > 0 && quests.GetFact(n"sq021_randy_saved") <= 0;
}

/// Judy's arc, as the base game records it ///
//
// Surveyed 2026-08-26 like the block above: sq026 and sq030 pulled out of basegame_4_gamedata
// by hash, phase graphs read with the wkdump harness. Every name comes from a
// questFactsDBManagerNodeDefinition that sets it, which matters here because a plain string
// scan of the same files offers `judy_pissed`, and that is a socket name, not a fact.
//
// Found and deliberately not wired: `sq026_refused`, set when the Clouds thread is dropped.
// The name and the node are real; what it means -- "V turned Judy down" or "the quest was
// abandoned" -- is not established. A fact whose name is wrong is silent; one whose meaning is
// wrong would put a Judy who was never refused into the refused state.

// Evelyn Parker is dead, and Judy is the one who found her. sq026_01 is Both Sides, Now: it
// closes on the burial, and until it does Judy has not lost anybody. The largest
// before-and-after in her sheet, and not a romance state -- it lands the same for a V she will
// never be with.
//
// The second guard is whether V went to fetch Evelyn with her and stayed afterwards. q105_04
// is the phase at Judy's after the Scavengers' den: V brings Evelyn back, stays, and it is the
// scene where Judy says she did not trust V at the start. The fact and the moment coincide.
//
// Without it her relationship asserted that act in a playthrough where it never happened,
// including before they had spoken once.
func AiNpcEvelynWasRescued(contactId: String) -> Bool {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return false;
    }
    switch contactId {
        case "judy":
            return quests.GetFact(n"q105_04_done") > 0;
    }
    return false;
}

func AiNpcEvelynIsDead() -> Bool {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return false;
    }
    return quests.GetFact(n"sq026_01_done") > 0;
}

// The Clouds arc is over, and blind to how it went: the branch facts of the last phase are
// sockets rather than facts, so the graph carries the outcome on the wire and not in the
// database. The text hangs on "settled" rather than on a verdict this cannot see.
func AiNpcCloudsIsSettled() -> Bool {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return false;
    }
    return quests.GetFact(n"sq026_done") > 0;
}

/// The night Johnny wore V's body ///
//
// Surveyed 2026-08-27, same harness as the blocks above: sq031 and its nine phases pulled out
// of basegame_4_gamedata by hash, graphs read with wkdump's qgraph mode. The relevé is in
// docs\ARC_FACTS.md.
//
// This is the largest before-and-after any character in the cast has, and until now no sheet
// could express it: Rogue is told about the engram in V's head from the first message of a new
// game, through a channel that does not exist yet.
//
// `sq031_afterlife_sequence_done` is set on the LAST node of the `afterlife` phase, and that
// phase is first in a strictly linear chain -- afterlife, tattoo, striptease, motel, rogue,
// ebunike. The bar is not one of the optional stops of that night, so no path through Chippin'
// In skips the scene where Johnny, wearing V, introduces himself to her.
//
// Offered to every sheet rather than to Rogue's alone, like randyDead: Johnny showing himself
// to somebody who knew him is a world event, not one contact's property.
func AiNpcJohnnyWasRevealed() -> Bool {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return false;
    }
    return quests.GetFact(n"sq031_afterlife_sequence_done") > 0;
}

// The drive-in at Silver Pixel Cloud happened, and it ended the way it ended. Set in the
// `bushidox` phase next to sq031_done, so the movie played through: the fact is not "V asked"
// but "the evening took place".
func AiNpcJohnnyDateHappened() -> Bool {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return false;
    }
    return quests.GetFact(n"sq031_rogue_date_done") > 0;
}

// Per contact, like AiNpcRomanceFailedFor: leaving is not one fact the base game keeps for
// everybody. Judy's is `judy_left_nc`, set on three branches of sq030, each of which despawns
// her and her van. A contact with no rule answers false -- "still around", never "already
// gone".
func AiNpcHasLeftNightCity(contactId: String) -> Bool {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return false;
    }
    switch contactId {
        case "judy":
            return quests.GetFact(n"judy_left_nc") > 0;
    }
    return false;
}

/// Whether a contact can be written to at all ///
//
// Per contact, like AiNpcHasLeftNightCity above, and a contact with no rule answers TRUE:
// "reachable" is what the mod has always assumed, so a missing rule must not silence anybody.
// The same default covers the read failing -- with no quest system there is nothing to go on,
// and hiding a contact on no evidence is the worse of the two mistakes.
//
// Surveyed 2026-08-29 the way Judy's block above was: the seven ep1 quest graphs and their
// top-level phases pulled out of ep1_2_gamedata by hash, read with wkdump qgraph. Every name
// below comes from a questFactsDBManagerNodeDefinition that sets it.
func AiNpcContactIsInPlay(contactId: String) -> Bool {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return true;
    }
    switch contactId {
        case "songbird":
            return AiNpcSongbirdIsInPlay(quests);
    }
    return true;
}

// Song So Mi is the one character in the cast V does not start with. The expansion hands over
// her number and takes it back, and in between the story locks her away twice -- which is why
// this is four reads and not one.
//
// `ep1_songbird_known` is the outer bracket: set in q301 when she first reaches V through the
// Relic, cleared in q306. Before it, V has no number to write to, which is also the root of
// the bug this whole pass came from -- the old sheet was answering from the main menu.
//
// The two inner stretches are the ones the expansion writes her out of. Hansen holds her from
// the end of Spider and the Fly until V reaches her on the mezzanine of the Black Sapphire,
// and the game sends V nothing at all across that whole span. Then q305 is the branch where V
// gave her up: MaxTac's convoy, the bunker, the border. What speaks to V under Cynosure is
// what the Blackwall left of her, and it is not reachable by text.
func AiNpcSongbirdIsInPlay(quests: ref<QuestsSystem>) -> Bool {
    if quests.GetFact(n"ep1_songbird_known") <= 0 {
        return false;
    }
    if quests.GetFact(n"q302_active") > 0 {
        return false;
    }
    if quests.GetFact(n"q303_active") > 0 && quests.GetFact(n"q303_found_somi_paradise") <= 0 {
        return false;
    }
    return quests.GetFact(n"q305_active") <= 0;
}

// This character has told V what is wrong with them. Per contact like the two rules above,
// and false for anyone with no rule -- "has not said" is the state every relationship starts
// in, so a missing rule must not grant a confidence that never happened.
//
// So Mi keeps it until the Black Sapphire, and says it there in front of Reed and V:
// "I'm... dyin', Sol. Like V." `q303_v_talked_to_somi` is set by that conversation, which is
// the exact moment rather than the quest around it.
func AiNpcHasConfidedInV(contactId: String) -> Bool {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return false;
    }
    switch contactId {
        case "songbird":
            return quests.GetFact(n"q303_v_talked_to_somi") > 0;
    }
    return false;
}
