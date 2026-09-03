// A character sheet, adapted to the runtime contract.
//
// This is what makes the three ways of describing a character indistinguishable downstream:
// a sheet shipped in cast\, a sheet parsed out of a JSON file, and a provider implemented by
// another mod are all an AiNpcContactProvider, and nothing that builds a prompt knows or
// cares which it is holding.
//
// The variant vocabulary lives here too, because this is the file that EVALUATES it. It is a
// closed set on purpose: data may carry the text, never the predicate, so a JSON file can
// never ask the game a question this mod did not agree to answer. The loader consults the
// same list to reject an unknown condition at load time, where it can still be fixed.
module AiNpc

/// Config-backed provider ///

// Adapts one AiNpcCharacterDef to the runtime contract. The shipped cast is registered
// through this same class, so a built-in character is not a special case anywhere.
public class AiNpcDefContactProvider extends AiNpcContactProvider {
    private let m_def: ref<AiNpcCharacterDef>;

    public static func Create(def: ref<AiNpcCharacterDef>) -> ref<AiNpcDefContactProvider> {
        let provider = new AiNpcDefContactProvider();
        provider.m_def = def;
        return provider;
    }

    public func GetDefinition() -> ref<AiNpcCharacterDef> {
        return this.m_def;
    }

    public func GetContactId() -> String {
        return this.m_def.contactId;
    }

    public func GetDisplayName() -> String {
        return this.m_def.displayName;
    }

    public func GetBio() -> String {
        let variant = this.ResolveVariant("bio");
        if NotEquals(StrLen(variant), 0) {
            return variant;
        }
        return this.m_def.bio;
    }

    public func GetRelationship() -> String {
        let variant = this.ResolveVariant("relationship");
        if NotEquals(StrLen(variant), 0) {
            return variant;
        }
        return this.m_def.relationship;
    }

    public func GetLiveContext() -> String {
        let variant = this.ResolveVariant("liveContext");
        if NotEquals(StrLen(variant), 0) {
            return variant;
        }
        return this.m_def.liveContext;
    }

    public func GetSpeechStyle() -> String {
        let variant = this.ResolveVariant("speechStyle");
        if NotEquals(StrLen(variant), 0) {
            return variant;
        }
        return this.m_def.speechStyle;
    }

    // Sans variante : une variante décrit un moment de l'arc, pas une surface, et les deux
    // questions se croiseraient en quatre textes par personnage. Le jour où une variante devra
    // parler autrement à voix haute, elle le dira -- ici, additivement.
    public func GetSpokenStyle() -> String {
        return this.m_def.spokenStyle;
    }

    // What this character wants of V when the journal says nothing. The quest half is
    // GetQuestIntent below, and the two are composed by the caller -- see AiNpcIntentFor,
    // which owns the cascade for a script provider exactly as it does for a sheet.
    public func GetIntent() -> String {
        let variant = this.ResolveVariant("intent");
        if NotEquals(StrLen(variant), 0) {
            return variant;
        }
        return this.m_def.intent;
    }

    public func GetQuestIntent(questKey: String) -> String {
        return AiNpcQuestTextIn(this.m_def.questIntents, questKey);
    }

    /// Identity ///

    public func GetContactTags() -> array<String> {
        return this.m_def.tags;
    }

    public func GetPromptOverrides() -> ref<AiNpcPromptOverrides> {
        return this.m_def.prompts;
    }

    /// Scripted replies ///

    // The same line whatever V wrote: a sheet carries text, and a text that varied with the
    // message would be a predicate. A contact with no table answers "" and the model writes.
    //
    // Resolved here rather than when the sheet is built, because the cast is built once per
    // session and a sheet reads no game state -- the language does.
    public func GetScriptedReply(playerText: String) -> String {
        return AiNpcLineTextIn(this.m_def.scriptedReply, AiNpcCurrentLanguageName());
    }

    public func AllowsMemory() -> Bool {
        return this.m_def.allowsMemory;
    }

    public func GetSeedFacts() -> array<String> {
        return this.m_def.seedFacts;
    }

    // COULD they be together, as opposed to are they. Both questions are asked: IsRomanced
    // reads the save and decides whether the romance text is added, this one decides whether
    // a contact who is NOT romanced is told to refuse advances.
    //
    // DECLARED, never inferred from `romanceFact`. Whether a character can be romanced at all
    // is a fixed property of who they are, and reading it out of another field would move the
    // answer the day that field moves.
    public func IsRomanceCapable() -> Bool {
        return this.m_def.romanceable;
    }

    public func GetRomance() -> String {
        return this.m_def.romance;
    }

    // A sheet that names a romance fact reads the save, and nothing else may answer: the
    // base game records its own romances, so an override file cannot claim V is dating Judy
    // when the playthrough says otherwise. A contact the base game never heard of has no
    // such record and falls back to whatever its sheet declares.
    public func IsRomanced() -> Bool {
        if NotEquals(StrLen(this.m_def.romanceFact), 0) {
            return AiNpcRomanceFactIsSet(this.m_def.romanceFact);
        }
        return this.m_def.romanced;
    }

    // What this character has to say about the quest V is tracking, or "". The account alone:
    // the title and the live objective are read from the journal and written around it by
    // AiNpcQuestBlock -- see AiNpcContextData.reds.
    public func GetQuestContext(questKey: String) -> String {
        return AiNpcQuestTextIn(this.m_def.questContexts, questKey);
    }

    /// Variants ///

    // The first variant that both supplies this field and whose condition holds, or "".
    //
    // One loop for every field: a field added to the sheet and to the loader but not here
    // would be silently unvariantable, and only in the playthroughs where the condition
    // holds. The field vocabulary is AiNpcVariantFields, next to the class it describes.
    private func ResolveVariant(field: String) -> String {
        let i = 0;
        let count = ArraySize(this.m_def.variants);
        while i < count {
            let text = AiNpcVariantField(this.m_def.variants[i], field);
            if NotEquals(StrLen(text), 0)
                && AiNpcEvaluateVariantCondition(this.m_def.variants[i].when,
                                                 this.m_def.contactId, this.IsRomanced()) {
                return text;
            }
            i += 1;
        }
        return "";
    }
}

/// Variant vocabulary ///

// The closed set of predicates a data file may name. Adding one here is a deliberate
// decision to let config ask the game that question; nothing else can widen it.
func AiNpcVariantConditions() -> array<String> {
    return ["postHeist", "preHeist", "romanced", "notRomanced", "playerMale", "playerFemale",
            "romanceFailed", "randyDead", "evelynDead", "evelynRescued", "cloudsSettled",
            "leftNightCity", "johnnyRevealed", "johnnyDateDone", "confidedInV"];
}

// Whether a named condition holds, FOR THIS CONTACT.
//
// The contact id is what lets one condition name have a different rule per character, and it
// is what makes `romanceFailed` expressible at all: the base game records a refused romance
// three different ways (an explicit failure fact for Judy, a gesture for Kerry, nothing but a
// closed arc for River), so the vocabulary stays one short word and the awkwardness lives in
// AiNpcStoryState, where the save is read.
//
// Every read is lazy, at prompt build: a DelayCallback does not survive a save load, and a
// cached answer would outlive the load that changed it.
func AiNpcEvaluateVariantCondition(condition: String, contactId: String, romanced: Bool) -> Bool {
    switch condition {
        case "postHeist":
            return AiNpcIsPostHeist(GetGameInstance());
        case "preHeist":
            return !AiNpcIsPostHeist(GetGameInstance());
        case "romanced":
            return romanced;
        case "notRomanced":
            return !romanced;
        case "playerMale":
            return Equals(AiNpcResolveGender(), AiNpcGender.Male);
        case "playerFemale":
            return Equals(AiNpcResolveGender(), AiNpcGender.Female);
        // The third romance state. Never true at the same time as `romanced`: both halves
        // read the same save, and an arc cannot be both refused and consummated.
        case "romanceFailed":
            return AiNpcRomanceFailedFor(contactId);
        // Not a romance state at all -- see AiNpcRandyIsDead. Offered to every sheet rather
        // than to River's alone: a vocabulary that answered for one contact would be a switch
        // pretending to be a rule.
        case "randyDead":
            return AiNpcRandyIsDead();
        // What the character has LIVED THROUGH, as opposed to what they are. False in a
        // playthrough that has not got there, which is why each one asks a "done" fact rather
        // than the absence of something.
        case "evelynDead":
            return AiNpcEvelynIsDead();
        // Per contact, like leftNightCity: what V did FOR this particular character.
        case "evelynRescued":
            return AiNpcEvelynWasRescued(contactId);
        case "cloudsSettled":
            return AiNpcCloudsIsSettled();
        // What somebody else has been told, as opposed to what V has lived: Johnny took V's
        // body for a night and introduced himself to the people who knew him. A character who
        // has met him that way cannot be written the same as one who has not.
        case "johnnyRevealed":
            return AiNpcJohnnyWasRevealed();
        case "johnnyDateDone":
            return AiNpcJohnnyDateHappened();
        // Per contact, and about what V has been TOLD rather than what is true. A sheet states
        // what the character knows; this is the only way it can also state what the other one
        // does, which is what keeps a confidence from arriving four quests early.
        case "confidedInV":
            return AiNpcHasConfidedInV(contactId);
        // Per contact, like romanceFailed: leaving the city is not one fact for everybody.
        case "leftNightCity":
            return AiNpcHasLeftNightCity(contactId);
        default:
            return false;
    }
}
