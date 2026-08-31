// Turning what the journal is tracking into something a character can react to. The text is
// not here: what each character says about a quest lives on their sheet, in cast\. This file
// owns the two halves that are nobody's property in particular:
//
//   identification   one function turns whatever is tracked into a canonical key. It is the
//                    only place a localized string is compared, so a character sheet can
//                    never be made to match a translation.
//   composition      the objective V is on is read here and substituted into the character's
//                    line, and an absent one produces no clause at all.
//
// Both were once a single table indexed by display name, comparing localized titles against
// English literals, with River filed under Rogue's block and a debug string interpolated into
// the prompt as V's situation.
module AiNpc

/// Identification ///

// The canonical name of the tracked quest, or "" when it is not one this mod has anything to
// say about. Two vocabularies, one table, and the order matters:
//
//   editorName   what the game calls the quest internally, identical in every language and
//                therefore the key. StealthRunner keys its whole quest map on it.
//   englishTitle the localized title this table matched on before, kept as a second key so an
//                English playthrough keeps working while the editor names are captured. A
//                migration aid: a title is locale-dependent by definition.
//
// AiNpcQuestContext logs the editor name of whatever is tracked, so filling in a missing one
// is a matter of reading the log.
public func AiNpcQuestKey(editorName: String, localizedTitle: String) -> String {
    let byId = AiNpcQuestKeyFor(editorName);
    if NotEquals(StrLen(byId), 0) {
        return byId;
    }
    return AiNpcQuestKeyFor(localizedTitle);
}

// Editor names and English titles share the table: one captured later is added next to the
// title it replaces, and nothing downstream changes.
func AiNpcQuestKeyFor(name: String) -> String {
    switch name {
        // -- Panam --------------------------------------------------------------------
        case "Riders on the Storm":                     return "riders_on_the_storm";
        case "With a Little Help from My Friends":      return "with_a_little_help";
        case "Queen of the Highway":                    return "queen_of_the_highway";
        case "All Along the Watchtower":                return "all_along_the_watchtower";

        // -- Judy ---------------------------------------------------------------------
        case "Both Sides, Now":                         return "both_sides_now";
        case "Ex-Factor":                               return "ex_factor";
        case "Talkin' 'bout a Revolution":              return "talkin_bout_a_revolution";
        case "Pisces":                                  return "pisces";
        case "Pyramid Song":                            return "pyramid_song";

        // -- Takemura -----------------------------------------------------------------
        case "Playing for Time":                        return "playing_for_time";
        case "Down on the Street":                      return "down_on_the_street";
        case "Life During Wartime":                     return "life_during_wartime";
        case "Play It Safe":                            return "play_it_safe";
        case "Search and Destroy":                      return "search_and_destroy";
        case "Totalimmortal":                           return "totalimmortal";
        case "Where is My Mind?":                       return "where_is_my_mind";

        // -- Kerry --------------------------------------------------------------------
        // Two of his quests are deliberately absent, and for the same reason: there is no
        // moment inside them where he could answer a text from a state he is in. Chippin' In
        // (in the shared block below) is Johnny driving to the villa, before he has met V; and
        // Holdin' On is the visit itself -- he is out of the house for the first half and in
        // the same room as V for the second.
        case "Second Conflict":                         return "second_conflict";
        case "A Like Supreme":                          return "a_like_supreme";
        case "Rebel! Rebel!":                           return "rebel_rebel";
        case "I Don't Wanna Hear It":                   return "i_dont_wanna_hear_it";
        case "Off the Leash":                           return "off_the_leash";
        case "Boat Drinks":                             return "boat_drinks";

        // -- Jackie (pre-heist only) --------------------------------------------------
        case "The Rescue":                              return "the_rescue";
        case "The Ripperdoc":                           return "the_ripperdoc";
        case "The Ride":                                return "the_ride";
        case "The Pickup":                              return "the_pickup";
        case "The Heist":                               return "the_heist";

        // -- Songbird (Phantom Liberty) -----------------------------------------------
        // Only the stretches she can answer a text from. She is out of reach for most of the
        // middle of the expansion, and the game is explicit about it: between the crash site
        // and the Black Sapphire she is Hansen's prisoner and sends V nothing at all, so
        // Lucretia My Reflection, The Damned and Get It Together are absent. So are Black
        // Steel In The Hour of Chaos, where MaxTac has her; Somewhat Damaged, where what
        // speaks to V is what the Blackwall left of her rather than her; and Leave in Silence,
        // where V is carrying her.
        //
        // The epilogues are absent for a harder reason than silence: every branch ends with
        // her dead, in NUSA custody, or gone to Tycho, and the variant vocabulary has no
        // Phantom Liberty condition to tell those apart. A context written there would fire in
        // all of them.
        // Hole in the Sky is deliberately absent: the expansion gives it a title and no
        // objectives of its own, and the stretch it names -- the crash, the wreck, Myers walked
        // clear -- is carried by Dog Eat Dog, whose objective list runs all the way through it.
        // A second key there would be one account written twice.
        case "Dog Eat Dog":                             return "dog_eat_dog";
        case "Spider and the Fly":                      return "spider_and_the_fly";
        case "You Know My Name":                        return "you_know_my_name";
        case "I've Seen That Face Before":              return "ive_seen_that_face_before";
        case "Firestarter":                             return "firestarter";
        case "Birds with Broken Wings":                 return "birds_with_broken_wings";
        case "The Killing Moon":                        return "the_killing_moon";

        // -- Shared endings and fixer work --------------------------------------------
        case "Nocturne Op55N1":                         return "nocturne_op55n1";
        case "Ghost Town":                              return "ghost_town";
        case "Chippin' In":                             return "chippin_in";
        case "Blistering Love":                         return "blistering_love";
        case "Path of Glory":                           return "path_of_glory";
        case "I Fought the Law":                        return "i_fought_the_law";
        case "The Hunt":                                return "the_hunt";
        case "Following the River":                     return "following_the_river";
    }
    return "";
}

/// Composition ///
//
// THE BLOCK IS THE MOD'S, THE ACCOUNT IS THE CHARACTER'S. A sheet supplies one value -- what
// this contact has to say about the quest V is tracking -- and every label around it is
// written here, once. Both other parts are read out of the player's game: the quest's title
// and what V is doing at this second.
//
// Until 2026-08-27 the heading was copied into all thirty-nine entries, each free to spell it
// differently, and each carrying a {situation} placeholder the author had to remember to put
// somewhere. Data cannot hold a structure the engine imposes without holding thirty-nine
// chances to hold it wrong.

// The quest's own title, or nothing. Localized, like the objective below: both come from the
// journal, so both reach the model in the language the player is running.
func AiNpcQuestHeading(questName: String) -> String {
    if Equals(StrLen(questName), 0) {
        return "";
    }
    return questName + ". ";
}

// What V is doing at this second, or nothing. This is where the debug leak was: the objective
// getter answered "Tracked entry is not an Objective" for a tracked phase, and that sentence
// went into the prompt as V's situation. An absent objective produces no clause, which is the
// honest rendering of "we do not know what V is doing".
func AiNpcSituationClause(objective: String) -> String {
    if Equals(StrLen(objective), 0) {
        return "";
    }
    return "V IS DOING THIS RIGHT NOW: " + objective + ".";
}

// The three parts assembled, or "" when the character has nothing to say -- an empty account
// is what most of the cast answers for most quests, and it must produce no block at all.
//
// The volatile part goes LAST, after the character's account: measured on this prompt on
// 2026-08-23, what sits nearest the player's own message is what the reply is about.
func AiNpcQuestAccountLabel() -> String {
    return "WHERE THINGS STAND: ";
}

public func AiNpcQuestBlock(questName: String, account: String, objective: String) -> String {
    if Equals(StrLen(account), 0) {
        return "";
    }

    let block = AiNpcQuestHeading(questName) + AiNpcQuestAccountLabel() + account;
    let clause = AiNpcSituationClause(objective);
    if Equals(StrLen(clause), 0) {
        return block;
    }
    return block + " " + clause;
}

/// Quest context, by contact ///

// What one contact says about the quest V is tracking, or "". Pure -- everything the journal
// answers arrives as an argument -- so every entry is covered without a session.
//
// The account belongs to the character and lives on their sheet, reached through their
// provider, which is also what lets a contact from another mod answer this.
func AiNpcQuestContextFor(contactId: String, questKey: String, questName: String,
                                 objective: String) -> String {
    if Equals(StrLen(questKey), 0) {
        return "";
    }

    let provider = AiNpcProviderFor(contactId);
    if !IsDefined(provider) {
        return "";
    }
    return AiNpcQuestBlock(questName, provider.GetQuestContext(questKey), objective);
}

/// Intention ///

// What this character wants of V. Pure, like its neighbour above, and three tiers deep:
// a requested intent outranks the tracked mission, which outranks the durable want.
//
// An absent entry does not blank the tier below it: a quest gives a character something else
// to want, it does not stop them wanting anything.
//
// The requested intent describes an occasion where the other two describe a life, which is why
// it wins: without it a character wrote her unprompted message under an intent that knew
// nothing about why she was writing, and during a tracked quest that can read "nothing else
// matters until Saul is out".
//
// It is stored nowhere: it lives as long as the generation, and the character is what she was
// before once the message is written. That is what makes it safe for a third party to set,
// and what stops it being a way to rewrite somebody's character one request at a time.
func AiNpcIntentOf(contactId: String, questKey: String, opt requested: String) -> String {
    if NotEquals(StrLen(requested), 0) {
        return requested;
    }
    return AiNpcIntentFor(contactId, questKey);
}

func AiNpcIntentFor(contactId: String, questKey: String) -> String {
    let provider = AiNpcProviderFor(contactId);
    if !IsDefined(provider) {
        return "";
    }

    if NotEquals(StrLen(questKey), 0) {
        let questIntent = AiNpcSafeSectionText(provider.GetQuestIntent(questKey), contactId);
        if NotEquals(StrLen(questIntent), 0) {
            return questIntent;
        }
    }
    return AiNpcSafeSectionText(provider.GetIntent(), contactId);
}

// Shared by the mission and the intention, because the journal read and the contact-specific
// rule below are the same for both, and two copies of a rule is how they come to disagree.
func AiNpcContactQuestKey(contactId: String) -> String {
    // Jackie's number, post-heist. At this edge rather than inside the table, so the table
    // stays a pure function of its arguments. The overlap is real: q005_jackie_to_hospital and
    // q005_jackie_to_mama are set during the escape, while "The Heist" is still tracked, and
    // every Jackie block is written in his first person.
    if Equals(contactId, "jackie") && AiNpcIsPostHeist(GetGameInstance()) {
        return "";
    }

    let journalManager = GameInstance.GetJournalManager(GetGameInstance());
    if !IsDefined(journalManager) {
        return "";
    }

    let quest = AiNpcTrackedQuest(journalManager);
    if !IsDefined(quest) {
        return "";
    }

    let editorName = quest.GetEditorName();
    let title = GetLocalizedText(quest.GetTitle(journalManager));
    let key = AiNpcQuestKey(editorName, title);

    // What makes the editor names collectable: until every entry of AiNpcQuestKeyFor carries
    // one, a non-English playthrough resolves nothing, and this says what to write.
    if Equals(StrLen(key), 0) {
        AiNpcLog(s"Tracked quest '\(editorName)' (\"\(title)\") has no context entry.");
    }

    return key;
}

// The <quest> block for one contact, by contact id and never by display name: the name is
// overridable, so keying on it made renaming a contact delete its quest context silently.
//
// The journal read happens above and the answer is handed to a pure function. The key is a
// parameter rather than read again, because the intention section needs the same one: one
// journal walk per message, and one log line rather than two saying the same thing.
// The three parts a recipe may keep are gathered here and handed to the pure assembler below,
// which is why the recipe stops at this edge: what the journal answers is read or not read,
// and AiNpcQuestBlock goes on being a function of the three strings it is given.
//
// Dropping `context` empties the block whatever else is kept, and that is right rather than
// surprising: a heading over an account nobody wrote says nothing at all.
func AiNpcQuestContext(contactId: String, questKey: String, recipe: ref<AiNpcRecipe>) -> String {
    if Equals(StrLen(questKey), 0) || !AiNpcRecipeHas(recipe, "quest") {
        return "";
    }

    let journalManager = GameInstance.GetJournalManager(GetGameInstance());
    if !IsDefined(journalManager) {
        return "";
    }

    let name = "";
    if AiNpcRecipeWants(recipe, "quest", "name") {
        name = AiNpcTrackedQuestName(journalManager);
    }
    let objective = "";
    if AiNpcRecipeWants(recipe, "quest", "objective") {
        objective = AiNpcTrackedObjective(journalManager);
    }
    if !AiNpcRecipeWants(recipe, "quest", "context") {
        return "";
    }
    return AiNpcQuestContextFor(contactId, questKey, name, objective);
}

// The title of the quest whatever is tracked belongs to, as the journal spells it. Not the
// canonical key: the key is ours and says play_it_safe, and what a character should be reading
// is the name the player sees in their own journal.
func AiNpcTrackedQuestName(journalManager: wref<JournalManager>) -> String {
    let quest = AiNpcTrackedQuest(journalManager);
    if !IsDefined(quest) {
        return "";
    }
    return GetLocalizedText(quest.GetTitle(journalManager));
}

// Walks up from whatever is tracked -- an objective, a phase -- to its owning quest, as the
// vanilla quest tracker and StealthRunner both do.
func AiNpcTrackedQuest(journalManager: wref<JournalManager>) -> ref<JournalQuest> {
    let currentEntry: wref<JournalEntry> = journalManager.GetTrackedEntry();
    while IsDefined(currentEntry) && !IsDefined(currentEntry as JournalQuest) {
        currentEntry = journalManager.GetParentEntry(currentEntry);
    }
    return currentEntry as JournalQuest;
}

// "" when what is tracked is not an objective, and not a sentence: anything else is
// interpolated into the prompt as V's current situation. AiNpcSituationClause drops the whole
// clause instead.
func AiNpcTrackedObjective(journalManager: wref<JournalManager>) -> String {
    let objectiveEntry = journalManager.GetTrackedEntry() as JournalQuestObjective;
    if !IsDefined(objectiveEntry) {
        return "";
    }
    return GetLocalizedText(objectiveEntry.GetDescription());
}
