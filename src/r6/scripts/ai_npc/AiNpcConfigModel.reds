// What a character is, in this mod: one shape and only one. The shipped cast is written as
// sheets in cast\, a JSON file parses into sheets, and both reach the rest of the mod through
// the same provider. No per-character fact lives anywhere else -- no table of names, no switch
// on an enum, no second place to keep in step.
//
// Plain data classes: no loading, no validation, no game access. Apart from the loader because
// they are the shape the rest of the mod reads, and because a person editing a sheet wants the
// field list rather than six hundred lines of error reporting.
//
// Every field defaults to empty or to the permissive value: a definition is applied over the
// built-in text field by field, so a key nobody wrote means "keep what you had".
module AiNpc

/// Model ///

// One conditional override of a sheet. `when` is a closed vocabulary evaluated in code: data
// carries the text, never the predicate, so a JSON file cannot ask the game a question this
// mod did not agree to answer.
public class AiNpcCharacterVariant {
    public let when: String;
    public let bio: String;
    public let relationship: String;
    public let liveContext: String;
    public let speechStyle: String;

    // What this character wants from V when the condition holds. An intention is the kind of
    // thing the heist and the romance change, which is why it is variantable where `romance`
    // -- an extension's subject -- is not.
    public let intent: String;
}

// Quelle voix dit les repliques de ce personnage, par palier.
//
// Deux entrees parce qu'il y a deux paliers et qu'ils ne se remplacent pas : le clone est la
// voix du jeu, le catalogue est une voix libre qui ne lui ressemble pas. Un joueur qui a le
// pack de clonage entend le premier ; tous les autres entendent le second ; personne n'entend
// le synthetiseur de Windows sauf quand ni l'un ni l'autre n'est disponible.
//
// C'est une donnee de personnage et pas un reglage : « la voix de Judy » ne se choisit pas dans
// un menu, elle est un fait sur elle. Elle vit donc dans la fiche, avec le reste.
public class AiNpcVoiceDef {
    // Le fichier de reference, dans r6\storages\AiNpcoices\. Vide, c'est `<contactId>.wav`,
    // qui est ce que la recette d'extraction produit -- le nommer sert a partager une reference
    // entre deux contacts, ou a en designer une que le joueur a deposee lui-meme.
    public let clone: String;

    // La voix du catalogue de PocketTTS, par son nom. Vide, ce personnage n'a pas de repli et
    // tombe sur la voix du systeme.
    //
    // Vingt-six voix existent, dont trois inutilisables ; l'attribution est celle qui a ete
    // corrigee a l'oreille dans tools	ts-laballback-voices.json, et c'est cette table qui
    // se deverse ici, fiche par fiche.
    public let fallback: String;
}

public class AiNpcCharacterDef {
    public let contactId: String;
    public let displayName: String;
    public let bio: String;
    public let relationship: String;

    // What the romance adds, never a replacement: `relationship` is this character's
    // psychology and holds either way, so say only what being together changes. A text that
    // restates the friendship is the same paragraph twice in one prompt.
    //
    // It reaches the prompt through AiNpcRomanceExtension and the public extension API, which
    // makes the romance one subject with one owner rather than a branch in the sheet reader.
    public let romance: String;
    public let liveContext: String;
    public let speechStyle: String;

    // Comment ce personnage parle A VOIX HAUTE, quand la même conversation passe par un appel.
    //
    // Vide, le registre écrit sert : sur les neuf fiches livrées, six décrivent une personne et
    // se lisent tels quels -- « blunt and quick, no hedging » ne dépend d'aucune surface. Ce
    // champ existe pour les trois qui décrivent une FRAPPE : minuscules, apostrophes manquantes,
    // émoticônes. Prescrire cela à une bouche est la seule chose que le repli ferait de faux.
    //
    // Ce n'est pas une règle de rendu. Qu'une voix ne prononce pas d'émoticône est un fait sur
    // la surface, et il est dans <channel> ; que Judy en tape est un fait sur elle.
    public let spokenStyle: String;

    // Whether V could be with this character at all -- not the same question as `romanced`, and
    // the one that decides whether an unromanced contact is told to refuse advances. For a
    // contact the base game knows, `romanceFact` answers it; this is for one it has never
    // heard of, which has no record to read.
    public let romanceable: Bool = false;
    public let romanced: Bool = false;

    // Null quand la fiche ne dit rien : le clone garde son defaut -- `<contactId>.wav` -- et il
    // n'y a pas de repli de catalogue. Ce qui est le comportement d'aujourd'hui, exactement.
    public let voice: ref<AiNpcVoiceDef>;

    // Default on, and off is characterisation: an automated number does not accumulate a
    // relationship.
    public let allowsMemory: Bool = true;

    // Seeded into the memory at the first compaction, so it lives and ages like everything the
    // conversation produced rather than as a second kind of memory.
    public let seedFacts: array<String>;
    public let enabled: Bool = true;
    public let source: String;
    public let variants: array<ref<AiNpcCharacterVariant>>;
    // Null unless the entry carries a "prompts" object. The same type a script provider
    // returns, so both kinds of contact override sections through one code path.
    public let prompts: ref<AiNpcPromptOverrides>;

    // The quest fact the base game sets at the end of this character's romance arc, or "" for
    // anybody it never lets V romance. A name rather than a Bool, because for a shipped
    // character the save is the authority: an override file must not claim a romance the
    // playthrough never had. A contact with no fact falls back to `romanced`.
    public let romanceFact: String;

    // Keyed by canonical quest name, and empty for most of the cast: a character with nothing
    // to say about the current quest contributes no <quest> block.
    public let questContexts: array<ref<AiNpcQuestLine>>;

    // What this character wants from V, and not more bio: `bio` says who somebody is and
    // `relationship` how they see V, and a model handed a person with no intention invents a
    // different one every message. ai_npc_joytoys wrote "who you are, then what you want, then
    // what you know" into GetSpeechStyle because there was nowhere else for the middle third.
    //
    // Durable, and a property of the person rather than of the story.
    public let intent: String;

    // What the current mission replaces the durable intention with, keyed like questContexts. A
    // character wants what they always want until the thing V is doing gives them something
    // else; an absent entry is no opinion, so the durable one survives.
    public let questIntents: array<ref<AiNpcQuestLine>>;

    // What this character has lived through, recorded as it happens. See AiNpcArcBeat.
    public let arc: array<ref<AiNpcArcBeat>>;

    // Commands this character may emit, and the fact each sets. AiNpcDataAction.reds owns what
    // a sheet may do: announce anything, write only inside `ainpc_`.
    public let actions: array<ref<AiNpcActionDef>>;

    // Commands this character refuses, by head: "[ACTION:GIVE_EDDIES:" for the eddie transfer.
    // The declarative half of the veto, and the only way a character declared by a file can
    // turn down a command granted to everyone.
    //
    // One-way, like every suppression: nothing can grant it back.
    public let suppressActions: array<String>;

    // What this character IS, as tags: "joytoy:client", "fixer". A command another mod scopes
    // to one of these reaches this character without either side having heard of the other.
    //
    // Tags only ever ADD. To take a command away, use suppressActions -- leaving a tag out is
    // never how reach is removed.
    public let tags: array<String>;

    // The one line this contact answers to every message, in each language. Empty for a
    // character: a contact that carries it never reaches a model at all, which is what a
    // number nobody answers is -- see AiNpcContactProvider's scripted-reply protocol.
    //
    // Sheets only, like `arc`: a character file that declared one would be switching off the
    // very thing it came to configure.
    public let scriptedReply: array<ref<AiNpcLocalizedLine>>;
}

// One line of fixed text, in one language. `language` is an AiNpcLanguage member name -- the
// vocabulary AiNpcLanguageNames writes out, and the one prompts.json keys its language
// overrides by -- and "" is the line every unlisted language falls back to.
public class AiNpcLocalizedLine {
    public let language: String;
    public let text: String;
}

// One quest a character has something to say about. Written in the second person, like every
// other text a sheet carries: the prompt addresses the character throughout, and a paragraph
// in "I" would be the one place it speaks in the voice it is asking for.
//
// The account and nothing else. The quest's title and what V is doing right now are read from
// the journal and written around it by AiNpcQuestBlock.
public class AiNpcQuestLine {
    public let questKey: String;
    public let text: String;
}

/// Constructors ///
// Free functions rather than `new` plus three assignments, because the sheets in cast\ are read
// as data and every line of ceremony there is a line of noise.

func AiNpcQuest(questKey: String, text: String) -> ref<AiNpcQuestLine> {
    let entry = new AiNpcQuestLine();
    entry.questKey = questKey;
    entry.text = text;
    return entry;
}

func AiNpcLine(language: String, text: String) -> ref<AiNpcLocalizedLine> {
    let line = new AiNpcLocalizedLine();
    line.language = language;
    line.text = text;
    return line;
}

func AiNpcVariant(condition: String) -> ref<AiNpcCharacterVariant> {
    let variant = new AiNpcCharacterVariant();
    variant.when = condition;
    return variant;
}

func AiNpcBeat(fact: String, text: String) -> ref<AiNpcArcBeat> {
    let beat = new AiNpcArcBeat();
    beat.fact = fact;
    beat.text = text;
    return beat;
}

// Which fields a variant may override, and the only place that list is written out. One
// accessor rather than a resolver per field: five copies of one loop fail by having a field
// added to the class and the loader and forgotten in the reader, silently, and only in the
// playthroughs where the condition holds.
func AiNpcVariantFields() -> array<String> {
    return ["bio", "relationship", "liveContext", "speechStyle", "intent"];
}

func AiNpcVariantField(variant: ref<AiNpcCharacterVariant>, field: String) -> String {
    if !IsDefined(variant) {
        return "";
    }
    switch field {
        case "bio":           return variant.bio;
        case "relationship":  return variant.relationship;
        case "liveContext":   return variant.liveContext;
        case "speechStyle":   return variant.speechStyle;
        case "intent":        return variant.intent;
    }
    return "";
}

// The text this character has for one quest, or "".
func AiNpcQuestTextIn(entries: array<ref<AiNpcQuestLine>>, questKey: String) -> String {
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if Equals(entries[i].questKey, questKey) {
            return entries[i].text;
        }
        i += 1;
    }
    return "";
}

// The line written for this language, or the one written for none. "" when the table is empty,
// which is what every character has and what means "no scripted reply".
func AiNpcLineTextIn(lines: array<ref<AiNpcLocalizedLine>>, language: String) -> String {
    let fallback = "";
    let i = 0;
    let count = ArraySize(lines);
    while i < count {
        if Equals(lines[i].language, language) {
            return lines[i].text;
        }
        if Equals(StrLen(lines[i].language), 0) {
            fallback = lines[i].text;
        }
        i += 1;
    }
    return fallback;
}

// What another mod's fact means, and who should hear about it. A declaration and nothing more:
// the listener, the baseline and the acknowledgement belong to AiNpcFactBridge.reds. Here with
// the character sheet because it is the same kind of object -- text a person edits in a file,
// validated once at launch and read-only afterwards.
public class AiNpcFactWatch {
    public let fact: String;

    // One by default, which is what a flag means; a counter uses its own number.
    public let atLeast: Int32 = 1;

    // Who is told. Each of them reacts in its own voice, the next time V texts them.
    public let contacts: array<String>;

    // In the declaring mod's own words. Placeholders are expanded per contact, plus {value}
    // for the fact's own number.
    public let event: String;

    // A fact of theirs to set to 1 once the news has landed. Empty means the declaring side
    // does not want to be told.
    public let ackFact: String;

    // Where the sentence lands. False is news: seeded for the next reply, then gone. True is
    // what HAPPENED: recorded in the contact's memory, repeated on every message, survives a
    // save, and cannot be taken back. The memory block states its precedence over the sheet,
    // so a remembered beat can contradict the bio; a seeded one can only add to it.
    public let remembered: Bool = false;

    // A fact that must still be BELOW 1 for this watch to speak, read at the moment it fires.
    // Empty means nothing blocks it.
    //
    // It exists because this game writes most outcomes as the absence of a death: Oda spared is
    // `q112_oda_dead` never set, and River's romance surviving is `sq029_river_lover` never set.
    // There is no positive fact to watch for either, so the only way to say "it ended well" is
    // to watch the moment the arc closed and check that the bad fact stayed down.
    public let unlessFact: String;

    public let source: String;
}

// One beat of a character's own story: the quest fact that says it happened, and the sentence
// they carry afterwards. Declared in the sheet rather than in facts.*.json because everything
// about somebody lives in their own file, and because a beat is about that one character --
// there is no `contacts` list to fill.
//
// Write what REMAINS, not the news: the game sends its own SMS the day a beat lands, and a
// second announcement of the same event is how a character starts repeating itself.
public class AiNpcArcBeat {
    public let fact: String;

    public let atLeast: Int32 = 1;

    public let text: String;

    // See AiNpcFactWatch.unlessFact: how an outcome the game only writes as an absence gets
    // said. The beat watches the moment the arc closed, and stays quiet if the bad fact is up.
    public let unlessFact: String;
}

public class AiNpcPromptConfig {
    public let interactions: array<ref<AiNpcRule>>;
    public let worldBackground: String;
    public let rules: array<ref<AiNpcRule>>;
    public let speechStyle: String;
    public let languages: array<String>;      // parallel arrays: languages[i] is the
    public let languageTexts: array<String>;  // enum member name, languageTexts[i] its text

    public func GetLanguage(name: String) -> String {
        let i = 0;
        let count = ArraySize(this.languages);
        while i < count {
            if Equals(this.languages[i], name) {
                return this.languageTexts[i];
            }
            i += 1;
        }
        return "";
    }
}

public class AiNpcConfigIssue {
    public let severity: String;  // "error" | "warning" | "info"
    public let source: String;    // file the problem came from
    public let message: String;
}

// One issue, built where it is found. The loader owns the list and the counters; a reader
// that only knows how to read a file -- the recipe parser -- collects into an array and hands
// it over, which is what keeps that parser free of the service.
func AiNpcConfigIssueOf(severity: String, source: String, message: String) -> ref<AiNpcConfigIssue> {
    let issue = new AiNpcConfigIssue();
    issue.severity = severity;
    issue.source = source;
    issue.message = message;
    return issue;
}
