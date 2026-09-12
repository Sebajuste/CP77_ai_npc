// V, as the characters texting them perceive them.
//
// What the GAME knows is read (life path, voice tone); what it cannot know is one free-form
// line the player writes in settings.json. A setting the game can answer is a setting the
// player can get wrong, and a wrong description is worse than none -- the model repeats it
// back, in character, for hours.
//
// The composing functions are pure and take their values as arguments, so the whole table is
// assertable without a session; the wrappers that read the settings sit next to them.

module AiNpc

// V's gender is the voice tone, the character creator's "brain" gender: the game's pronouns
// follow it. GetResolvedGenderName() is the body -- inventory icons and ripperdoc animations.
//
// Falls back to Male when there is no customization state yet -- this is reachable from the
// settings menu before a save is loaded, and a missing state must not read as Female by accident.
public func AiNpcResolveGender() -> AiNpcGender {
    let system = GameInstance.GetCharacterCustomizationSystem(GetGameInstance());
    if !IsDefined(system) {
        return AiNpcGender.Male;
    }
    let state = system.GetState();
    if !IsDefined(state) || state.IsBrainGenderMale() {
        return AiNpcGender.Male;
    }
    return AiNpcGender.Female;
}

// Resolved once per call rather than per branch, so every word in one prompt agrees.
func AiNpcGetGenderedWord(id: Int64) -> String {
    let isMale = Equals(AiNpcResolveGender(), AiNpcGender.Male);
    switch id {
        case 1:
            return isMale ? "boyfriend" : "girlfriend";
        case 2:
            return isMale ? "he" : "she";
        case 3:
            return isMale ? "him" : "her";
        case 4:
            return isMale ? "his" : "her";
        case 5:
            return isMale ? "male" : "female";
        default:
            return "";
    }
}

// V's gender, stated in the language the reply will be written in.
//
// English says nothing: its adjectives and participles do not agree, so the sentence would be
// prompt weight for no gain. Every other language the mod ships forces the model to choose --
// "t'es pret" or "t'es prete", "ты был" or "ты была" -- and an English he/she buried inside the
// relationship text is not enough to hold the agreement steady from one message to the next.
func AiNpcGenderStatementFor(language: AiNpcLanguage, gender: AiNpcGender) -> String {
    // Female is what is tested, rather than Male, so anything unexpected reaching here
    // reads as the same default AiNpcResolveGender falls back to and not as Female.
    let isFemale = Equals(gender, AiNpcGender.Female);
    switch language {
        case AiNpcLanguage.French:
            return (isFemale ? "V est une femme." : "V est un homme.") +
                " Accorde en conséquence tout adjectif ou participe qui se rapporte à V.";
        case AiNpcLanguage.Spanish:
            return (isFemale ? "V es una mujer." : "V es un hombre.") +
                " Concuerda en consecuencia todo adjetivo o participio referido a V.";
        case AiNpcLanguage.Italian:
            return (isFemale ? "V è una donna." : "V è un uomo.") +
                " Accorda di conseguenza ogni aggettivo o participio riferito a V.";
        case AiNpcLanguage.Portuguese:
            return (isFemale ? "V é uma mulher." : "V é um homem.") +
                " Faz a concordância de todos os adjetivos e particípios que se referem a V.";
        // German adjectives do not agree with the person addressed, but the nouns and
        // pronouns that name V do: ein Freund / eine Freundin.
        case AiNpcLanguage.German:
            return (isFemale ? "V ist eine Frau." : "V ist ein Mann.") +
                " Wähle entsprechend Pronomen und Personenbezeichnungen.";
        case AiNpcLanguage.Russian:
            return (isFemale ? "V — женщина." : "V — мужчина.") +
                " Согласуй с этим прилагательные и глаголы прошедшего времени, относящиеся к V.";
        case AiNpcLanguage.Ukraine:
            return (isFemale ? "V — жінка." : "V — чоловік.") +
                " Узгоджуй із цим прикметники та дієслова минулого часу, що стосуються V.";
        default:
            // English, and anything added to the enum without a sentence written for it.
            return "";
    }
}

func AiNpcGenderStatement() -> String {
    return AiNpcGenderStatementFor(AiNpcResolveLanguage(), AiNpcResolveGender());
}

// The same fact, always in English, with no agreement instruction attached.
//
// The compaction lane is not roleplay and never writes in V's voice: it needs to KNOW who V
// is, not to conjugate around it. AiNpcGenderStatementFor returns "" for English, which is
// right for a prompt whose only job is agreement and wrong for one whose job is attribution.
func AiNpcGenderFactFor(gender: AiNpcGender) -> String {
    return Equals(gender, AiNpcGender.Female) ? "V is a woman." : "V is a man.";
}

func AiNpcGenderFact() -> String {
    return AiNpcGenderFactFor(AiNpcResolveGender());
}

/// What V looks like ///

// V's life path, as a lowercase key -- "streetkid", "nomad", "corpo", or "" when there is no
// player to ask. Read from the save rather than configured: anything written here by hand is
// one playthrough's answer told to every other playthrough as fact.
//
// Matched against the TweakDB records instead of gamedataLifePath members, as Dark Future and
// FreshStart both do: the record ids are stable across patches, and t"LifePaths.NewStart"
// (added by FreshStart) is a real fourth answer that must not be mistaken for one of the
// three -- hence "" rather than a default.
func AiNpcResolveLifePath() -> String {
    let player = GetPlayer(GetGameInstance());
    if !IsDefined(player) {
        return "";
    }

    let development = PlayerDevelopmentSystem.GetInstance(player);
    if !IsDefined(development) {
        return "";
    }

    let path = development.GetLifePath(player);
    if AiNpcLifePathIs(path, t"LifePaths.StreetKid") {
        return "streetkid";
    }
    if AiNpcLifePathIs(path, t"LifePaths.Nomad") {
        return "nomad";
    }
    if AiNpcLifePathIs(path, t"LifePaths.Corporate") {
        return "corpo";
    }
    return "";
}

// Guarded on the record rather than calling .Type() straight through: a missing record is
// what a TweakXL mod removing a life path looks like, and it must read as "no answer"
// instead of taking the prompt build down with it.
func AiNpcLifePathIs(path: gamedataLifePath, id: TweakDBID) -> Bool {
    let record = TweakDBInterface.GetLifePathRecord(id);
    if !IsDefined(record) {
        return false;
    }
    return Equals(path, record.Type());
}

// The sentence describing V, from what the game knows plus what the player wrote.
//
// TWO PARTS, AND ONLY THE SECOND IS WRITTEN BY HAND. The life path and the gender are read
// from the save (AiNpcResolveLifePath, AiNpcResolveGender) and are never configurable.
// Everything else is one free-form line: a closed list can say a hair colour and cannot say a
// tattoo, a scar, chrome, the relic mark or what V wears, which is most of what somebody
// texting V would have noticed.
//
// ADDITIVE, not substitutive: whatever the player writes is appended to the life path and the
// gender rather than replacing them. That is the difference with "playerDescription", which
// replaces the whole section. The life path is the only thing an override actually loses --
// the gender is stated again by AiNpcGenderStatement in the prompt itself.
func AiNpcPlayerDescriptionFor(lifePath: String, gender: AiNpcGender,
        appearance: String) -> String {

    let result = "";
    if NotEquals(StrLen(lifePath), 0) {
        result += "V is a " + lifePath + " (life path). ";
    }
    result += Equals(gender, AiNpcGender.Female) ? "V is a woman." : "V is a man.";

    // Taken verbatim, with only a space in front. The player wrote a sentence, not a clause:
    // punctuating it here would mean guessing whether it already ends in a full stop, and a
    // mod writing through the same field would have to guess back.
    let trimmed = AiNpcTrimBothEnds(appearance);
    if NotEquals(StrLen(trimmed), 0) {
        result += " " + trimmed;
    }

    return result;
}

// The same sentence for the session actually running.
//
// settings.json "playerDescription" REPLACES it when non-empty rather than adding to it, as
// every other override in this mod does; "appearance" is the additive half. A file that sets
// both is answered by the override.
func AiNpcPlayerDescription() -> String {
    return AiNpcPlayerDescriptionSeenBy("");
}

// The same sentence, as one contact may know it. A contact that answers false to
// KnowsPlayerLifePath is not told where V comes from; everything else it sees is unchanged.
//
// The player's own "playerDescription" still wins over both: a line the player wrote about V
// is not the mod's to edit per contact.
func AiNpcPlayerDescriptionSeenBy(contactId: String) -> String {
    let custom = AiNpcGetSetting("playerDescription", "");
    if NotEquals(StrLen(custom), 0) {
        return custom;
    }

    let lifePath = AiNpcResolveLifePath();
    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) && !provider.KnowsPlayerLifePath() {
        lifePath = "";
    }

    return AiNpcPlayerDescriptionFor(lifePath, AiNpcResolveGender(),
        AiNpcGetSetting("appearance", ""));
}
