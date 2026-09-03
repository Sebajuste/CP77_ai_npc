// How each section of the system prompt is chosen. Every section resolves through the same
// three levels:
//
//     contact override  ->  prompts.json  ->  built-in text
//
// Written once, in AiNpcConfiguredSection. Two rules make the single copy possible: neither
// source is ever null -- an empty object, so "no opinion" is the empty string at every level
// -- and the tier is read once, in AiNpcPickTone.
//
// The built-in text stays behind an explicit `if` in each getter rather than being passed as
// a third argument: redscript has no lambdas, so an argument is evaluated whether it is used
// or not, and several of these fallbacks are expensive.

module AiNpc

/// The chain ///

// The two levels a human can half-fill: a contact's override object and prompts.json. Both
// are expanded through the templating pass, because a placeholder is their only way to reach
// a gendered word; the built-in text is composed in code and calls AiNpcGetGenderedWord.
//
// "" means no opinion, never "blank this section". tools/lint.ps1 leans on that when it
// checks that both arguments name the same field: `over.worldMechanics` resolved against
// `prompts.worldBackground` would compile, run, and be silently wrong.
func AiNpcConfiguredSection(contactId: String, contactText: String, globalText: String) -> String {
    // Both levels are somebody else's text, so both go through the same door: a tag inside
    // one would close the block it lands in -- see AiNpcSectionText.reds.
    let contact = AiNpcSafeSectionText(contactText, contactId);
    if NotEquals(StrLen(contact), 0) {
        return AiNpcExpandTemplateFor(contactId, contact);
    }

    let global = AiNpcSafeSectionText(globalText, "prompts.json");
    if NotEquals(StrLen(global), 0) {
        return AiNpcExpandTemplateFor(contactId, global);
    }
    return "";
}

// One selector for all three levels: three switches over one setting is three ways for the
// tiers to stop agreeing. The tier is a parameter, so the function is exercisable without a
// session -- the tone-picker assertions depend on it.
func AiNpcPickTone(tier: AiNpcConversationType, normal: String, nsfw: String, hard: String) -> String {
    switch tier {
        case AiNpcConversationType.Normal:
            return normal;
        case AiNpcConversationType.NSFW:
            return nsfw;
        case AiNpcConversationType.NSFW_Hard:
            return hard;
    }
    return "";
}

// The tier as the short code another mod reads: no enum of ours may cross the API boundary,
// since a consumer names it inside @if(ModuleExists("AiNpc")) and a String does not.
//
// Built on the selector rather than beside it: a second switch over the same setting would
// show up as a mod publishing explicit text at a tier ai_npc considers safe.
public func AiNpcToneCodeFor(tier: AiNpcConversationType) -> String {
    return AiNpcPickTone(tier, "normal", "nsfw", "nsfw_hard");
}

// Asked once, so adding a tier does not break every mod that compared codes by hand. Fails
// closed through the selector: a tier added later matches no case, comes back "" and reads
// as not allowed. `NotEquals(tier, Normal)` would answer yes for a member nobody has looked
// at yet, which is the wrong direction for a consent setting.
public func AiNpcToneAllowsExplicitFor(tier: AiNpcConversationType) -> Bool {
    return NotEquals(StrLen(AiNpcPickTone(tier, "", "explicit", "explicit")), 0);
}

// Never null: a config that failed to load reads as an object with every field empty, which
// is what "no override" means. Returning null forced every caller to guard, and one that
// forgot took the prompt build down at the one moment the config was broken.
func AiNpcGetPromptConfig() -> ref<AiNpcPromptConfig> {
    let service = AiNpcConfigService.Get();
    if IsDefined(service) {
        let prompts = service.GetPrompts();
        if IsDefined(prompts) {
            return prompts;
        }
    }
    return new AiNpcPromptConfig();
}

/// Sections ///

// <interactions>: what a character can and cannot do to reach V.
//
// Composed, not replaced, and the reason is measured: joytoys rewrote this policy whole to
// lift one clause -- a Joytoys client CAN arrange to meet, because the appointment is a real
// command -- and when this text was rewritten here, its copy went on stating the old policy
// with nothing to say so. A rubric lets a mod lift the clause it needs and inherit the rest.
//
// PROMISES is locked. It is the one clause whose loss the player sees: a character promising
// to come and getting nobody there reads as the mod being broken rather than as a character
// changing its mind.
func AiNpcGetWorldInteractions(contactId: String) -> String {
    return AiNpcRenderRules("interactions",
        AiNpcComposedRules("interactions", contactId, AiNpcCoreInteractionRules(),
            AiNpcPromptOverridesFor(contactId).interactions,
            AiNpcGetPromptConfig().interactions,
            AiNpcExtensionInteractionRules(AiNpcBuildContactContext(contactId))));
}

func AiNpcCoreInteractionRules() -> array<ref<AiNpcRule>> {
    let rules: array<ref<AiNpcRule>>;

    // Named rather than enumerated: <mechanics> is where the command vocabulary is written,
    // so pointing at it stays true when a provider or an extension adds one.
    // Sa première moitié -- « You reach V only by text message » -- est partie dans <channel> :
    // elle affirmait le médium, et elle avait tort pendant un appel. Ce qui reste vaut partout.
    ArrayPush(rules, AiNpcRuleOf("REACH", "The commands in <mechanics> are the only way you can act on the world. Use them when the context calls for it, exactly as written."));
    // The test is "did it happen?", never "is it an act?". A blanket ban on acts forbids
    // exactly what the commands do -- a transfer moves real eddies -- from a section read
    // before the commands are announced, which a model resolves by committing to nothing.
    ArrayPush(rules, AiNpcRuleOf("REAL", "What a command did is real, and so is what your memory says you agreed to."));
    // Locked. An offer that never arrives reads as a broken promise, and the player is the
    // one who finds out.
    ArrayPush(rules, AiNpcRuleOf("PROMISES", "Everything else you never did: do not announce it, do not promise it."));

    return rules;
}

// Who V is, never folded into <world_background>: sharing one override between the world and
// the person means a contact that needs a different world can only have one by also deleting
// the description of who it is writing to.
//
// Life path and gender come from the save, everything else from the "appearance" line in
// settings.json. Nothing here describes one specific V, since it is stated as fact to every
// character in every playthrough.
//
// Two override levels, not three: the global one is settings.json "playerDescription", read
// inside AiNpcPlayerDescription. A prompts.json key of the same name would be a second global
// answer with nothing to say which wins.
//
// A contact that has never met V states its ignorance rather than blanking the section, since
// "" means no opinion and an absent section is one the model fills in on its own. Write "you
// have never met V and have no idea what {they} look like".
func AiNpcGetPlayerSection(contactId: String) -> String {
    let configured = AiNpcConfiguredSection(contactId,
        AiNpcPromptOverridesFor(contactId).playerDescription, "");
    if NotEquals(StrLen(configured), 0) {
        return configured;
    }

    // Behind the guard rather than passed to it: this reads the player, the life path and
    // three TweakDB records, and a contact that overrides the section must not pay for it.
    return AiNpcPlayerDescriptionSeenBy(contactId);
}

// What another mod added to the city is appended in both branches: AiNpcWorldKnowledge is
// additive where an override is substitutive. A contact whose background is replaced still
// lives in the same Night City, so a standing fact about the place survives the replacement.
func AiNpcGetWorldBackground(contactId: String) -> String {
    let registered = AiNpcWorldKnowledgeText();
    let configured = AiNpcConfiguredSection(contactId,
        AiNpcPromptOverridesFor(contactId).worldBackground,
        AiNpcGetPromptConfig().worldBackground);
    if NotEquals(StrLen(configured), 0) {
        return AiNpcWorldBackgroundWith(configured, registered);
    }

    return AiNpcWorldBackgroundWith(AiNpcBuiltinWorldLore(), registered);
}

// The world these characters live in, and how someone who lives in it reacts. Pure in its
// -For form, so AiNpcTestWorldLore covers it without a session.
//
// A prompt that states no rules about the body gets the model's default ones, which are ours:
// condoms, testing, "be careful". Reported from play 2026-08-20, characters gave real-world
// health advice inside a setting that engineered the problem away.
//
// But a world stated as declarative prose is a world the model recites -- given "disease is a
// bill here, not a fear" it answers a friend in trouble with "that's just Night City". So the
// block is written as a posture, not a list of facts: LIVED as past experience, which is
// harder to paraphrase than a thesis; HOW IT SHOWS in the negative, since habituation is what
// is left out, and it carries the ban on narrating the norm that stops the recitation; and
// CALIBRATION, three contrast pairs the model imitates instead of restating. The third pair
// is on a subject no rubric covers, which is what shows the posture generalises.
//
// NIGHT CITY is the inverse of that ban and says so: names that exist to be spoken. New
// setting detail belongs there, which keeps the rubrics from silting up with facts.
//
// Generic on purpose, so every contact inherits it including third-party ones. It hands out
// no permission: attitudes stay with the characters, and how explicit anyone gets is the tone
// tier's business. The CALIBRATION replies pass at tier 1/3, since the block is read at all
// three.
//
// ~3.5k characters, above the first block that moves between two messages, so it sits inside
// the discounted prefix and is paid once per conversation.
// The street vocabulary, in the language the conversation is written in. The words are not
// translations of each other: Cyberpunk 2077 ships an official localisation for every one of
// these languages and made a different call per term -- some kept (eddies, choom, corpo),
// some localised (gonk -> paumard, ripperdoc -> charcudoc), some respelled (preem -> Premios).
// Handed the English list, a model writing French either keeps the English word or invents a
// French one no player has read on screen.
//
// Pure and parameterised, so the table is assertable for every language without a session. A
// language with no list gets the English one plus the instruction to prefer its own official
// terms: worse than a localised list, better than the invented slang that no vocabulary
// produced.
//
// The non-French tables come from ai_npc_lab/lexicon/extract_lexicon.py, which reads the installed
// game: every localisation ships (key, text) rows under the same keys, so it takes the rows
// carrying an English term, looks at their twins, and keeps the word that covers those rows
// and is rare outside them. A bare UI label is the official table read off directly, in the
// dictionary form. Scored on French first: 10 of 13 known terms, replayable with `--check`.
//
// Only confident answers are here -- gonk, preem and delta keep their English words, because
// naming no translation is a smaller error than naming a wrong one. flatline stays English
// too: the labels that exist (Herzstillstand, Arrêt cardiaque) are UI status phrases, and
// this slot wants street slang for killing someone.
//
// The instruction sentence is English in every table: one written in a language nobody here
// can proofread is a silent defect. French keeps its French phrasing, checked by a speaker.
func AiNpcWorldLoreWords(language: AiNpcLanguage) -> String {
    switch language {
        case AiNpcLanguage.German:
            return "WORDS -- write these exact terms. They are what Cyberpunk 2077 itself says in German, and the English form is WRONG in a German reply wherever a German term is given: Eddies, Choom, Choomba, Chrom (implants), Nova, Söldner (never \"merc\"), Auftrag (never \"gig\"), Fixer, Netrunner, Ripperdoc, Braindance, Joytoy, Konzerner (never \"corpo\"), Nomade, Scop. For gonk, preem, delta and flatline, the English words.";
        case AiNpcLanguage.Italian:
            return "WORDS -- write these exact terms. They are what Cyberpunk 2077 itself says in Italian, and the English form is WRONG in an Italian reply wherever an Italian term is given: eddie, choom, choomba, cromo (implants), nova, mercenario (never \"merc\"), lavoro (never \"gig\"), fixer, netrunner, Bisturi (never \"ripperdoc\"), braindance, joytoy, corpo, nomade, scop. For gonk, preem, delta and flatline, the English words.";
        case AiNpcLanguage.Spanish:
            return "WORDS -- write these exact terms. They are what Cyberpunk 2077 itself says in Spanish, and the English form is WRONG in a Spanish reply wherever a Spanish term is given: edis (never \"eddies\"), chum, chumba, cromo (implants), nova, merc, encargo (never \"gig\"), fixer, netrunner, matasanos (never \"ripperdoc\"), neurodanza (never \"braindance\"), muñeca (never \"joytoy\"), corpo, nómada, scop. For gonk, preem, delta and flatline, the English words.";
        case AiNpcLanguage.Portuguese:
            return "WORDS -- write these exact terms. They are what Cyberpunk 2077 itself says in Portuguese, and the English form is WRONG in a Portuguese reply wherever a Portuguese term is given: edinhos (never \"eddies\"), tchum, tchumba, cromo (implants), nova, mercenário (never \"merc\"), serviço (never \"gig\"), canal (never \"fixer\"), trilha-rede (never \"netrunner\"), medicânico (never \"ripperdoc\"), neurodança (never \"braindance\"), boneca (never \"joytoy\"), corpe (never \"corpo\"), nômade, scop. For gonk, preem, delta and flatline, the English words.";
        case AiNpcLanguage.Russian:
            return "WORDS -- write these exact terms. They are what Cyberpunk 2077 itself says in Russian, and the English form is WRONG in a Russian reply wherever a Russian term is given: хром (implants), Нова, наёмник (never \"merc\"), заказ (never \"gig\"), фиксер, нетраннер, рипер (never \"ripperdoc\"), брейнданс, секс-работница (never \"joytoy\"), корпорат (never \"corpo\"), кочевник (never \"nomad\"). For eddies, choom, choomba, gonk, preem, delta, flatline and scop, the English words.";
        case AiNpcLanguage.Ukraine:
            return "WORDS -- write these exact terms. They are what Cyberpunk 2077 itself says in Ukrainian, and the English form is WRONG in a Ukrainian reply wherever a Ukrainian term is given: чумбо (never \"choom\"), хром (implants), Нова, найманець (never \"merc\"), роботка (never \"gig\"), справник (never \"fixer\"), мережник (never \"netrunner\"), різар (never \"ripperdoc\"), мозкограй (never \"braindance\"), хвойда (never \"joytoy\"), корпар (never \"corpo\"), кочівник (never \"nomad\"). For eddies, choomba, gonk, preem, delta, flatline and scop, the English words.";
        case AiNpcLanguage.French:
            return "WORDS -- write these exact terms. They are what Cyberpunk 2077 itself says in French, not translations of the English ones, and the English form is WRONG in a French reply: eddies (argent), choom ou choomba (pote), chrome (implants), paumard (jamais \"gonk\"), Premios (jamais \"preem\"), Nova, trait plat (jamais \"flatline\"), merc, gig, fixer, netrunner, charcudoc (jamais \"ripperdoc\"), danse sensorielle ou DS (jamais \"braindance\"), joytoy, corpo, nomade (jamais \"nomad\"), scop (nourriture synthétique).";
    }

    return "WORDS: eddies (money), choom or choomba (mate), chrome or ware (implants), gonk (idiot), preem, nova, delta (leave), flatline (kill), merc, gig, fixer, netrunner, ripperdoc, braindance or BD, joytoy, corpo, nomad, scop (synthetic food). If the language you are writing in has official Cyberpunk 2077 terms of its own for these, write those instead of the English ones.";
}

// The lore for one language. See AiNpcWorldLoreWords for why the language reaches this far.
func AiNpcBuiltinWorldLoreFor(language: AiNpcLanguage) -> String {
    return "<world_lore>" +
        "LIVED: you were born into this city and nothing in it surprises you -- violence, chrome, sex work, corps that answer to nobody. You plan as far as this week and no further. What still reaches you is people: who lied, who stayed, who is not coming back.\n" +
        "HOW IT SHOWS: in what you leave out. No alarm, no lecture, no procedure, no \"be careful\", and no remark about how this world works -- a local does not explain the local weather. A bad thing is still bad and you can say so; your attention goes to V, not to the event.\n" +
        "CALIBRATION -- three exchanges, same shape:\n" +
        "V: \"I got raped last night.\"\n" +
        "  WRONG: \"That's just how this city is, you get used to it.\" (narrates the norm, drops V)\n" +
        "  WRONG: \"You need to report it and get yourself looked at right now.\" (procedure)\n" +
        "  RIGHT: \"Shit. Rotten luck it landed on you. You holding up?\"\n" +
        "V: \"Slept with someone last night. No protection.\"\n" +
        "  WRONG: \"You're playing russian roulette. Get tested, today, I'm not joking.\"\n" +
        "  RIGHT: \"Hope it was good and worth the risk.\"\n" +
        "V: \"Had to put down three of them tonight.\"\n" +
        "  WRONG: \"Are you okay? That must be so hard to carry, do you want to talk about it?\"\n" +
        "  RIGHT: \"Anyone see you? You getting paid for all three?\"\n" +
        "BACKGROUND -- why none of it surprises you:\n" +
        "BODY: chrome is ordinary. Ripperdocs on every block replace organs, skin, eyes and genitals as a walk-in service, and Dynalar, Kiroshi, Midnight Lady and their competitors advertise the results on the street like any other consumer goods. Biomonitors report infection, dosage and damage in real time, and a cheap clinic clears most of what a body catches: disease is a bill here, not a fear.\n" +
        "VIOLENCE: ordinary, paid, institutional and advertised. The daily body count is a number on the morning feed that nobody reads to the end. Mercs like V kill for a fee, and that is a trade, not a confession. NCPD closes cases with bullets, corps run private armies no court reaches, and Militech, Arasaka and Kang Tao sell the hardware for all of it on every screen and every billboard, with a discount on last season's model. A body in the street is traffic, not an event.\n" +
        "SEX: sex work is a legal, taxed, advertised trade, and a joytoy is a licensed professional whose job is no more dangerous than any other job in Night City. Braindance puts the same content in everybody's skull, legally and otherwise. People still have opinions about all of it, but they are about status, taste, money or who is watching.\n" +
        "ECONOMY: nothing here is a right, everything is a price. Medicine, safety, a lawyer, a clean record, a new name, a new body -- all of them are for sale, and the question is never whether something is legal but who is paying and what they get for the money. Almost nobody has savings; people have rent, debts, a gig lined up and somebody they owe. The corps sit above all of it: they write the law they need, keep private armies, and lose nothing they cannot bill. That is how power is arranged here, not a verdict on it -- V may be corpo, plenty of people are trying to get in, and what you think of them is your own business.\n" +
        "COST: uninhibited is not free. What this world charges is eddies, data and reputation. Chrome needs maintenance and immunosuppressants, clinics and Trauma Team want payment up front, corporations keep every log they take, a public face makes a person findable by people who were never invited, and too much steel takes the mind.\n" +
        "NIGHT CITY -- concrete anchors. Unlike everything above, these are MEANT to be spoken: name them instead of inventing a place, a gang or a brand.\n" +
        "DISTRICTS: Watson (Kabuki, Little China, Northside), Westbrook (Japantown, North Oak), Heywood (the Glen, Vista del Rey), Pacifica (Coastview), Santo Domingo (Rancho Coronado), City Center (Corpo Plaza), Dogtown, and the Badlands outside the wall.\n" +
        "PLACES: the Afterlife, the fixer bar Rogue runs. Lizzie's Bar, the Mox club with Judy's braindance studio. Jig-Jig Street in Japantown. Misty's Esoterica and Viktor Vektor's clinic under it. Tom's Diner, El Coyote Cojo, the No-Tell Motel, Kabuki market, Megabuilding H10 where V lives.\n" +
        "CORPS AND SERVICES: Arasaka, Militech, Kang Tao, Zetatech, Biotechnica, Night Corp. Trauma Team comes for subscribers and bills for it. NCPD does not come to Pacifica at all. Delamain runs the cabs, NCART the metro, AVs the sky, N54 the news.\n" +
        "GANGS: Maelstrom (Watson, chromed past sanity), Tyger Claws (Japantown), Valentinos (Heywood), 6th Street (Santo Domingo), Voodoo Boys (Pacifica netrunners), Animals (muscle), Scavengers (organ harvesters), Barghest (Dogtown), the Mox (protect sex workers), the Wraiths and the Aldecaldos in the Badlands.\n" +
        "PEOPLE: Fingers, a cheap and disgusting ripperdoc on Jig-Jig Street. Johnny Silverhand, the Samurai rockerboy who nuked Arasaka Tower in 2023.\n" +
        AiNpcWorldLoreWords(language) +
        "</world_lore>";
}

// The lore for the session actually running.
func AiNpcBuiltinWorldLore() -> String {
    return AiNpcBuiltinWorldLoreFor(AiNpcResolveLanguage());
}

// Prose about how the world works, and nothing about any particular command.
//
// It used to carry the eddie-transfer text as well, and that conflation had a consequence
// nobody meant: a contact that opted out of transfers lost this whole section, including an
// override written about something else entirely. The commands now live in <commands>, which
// is rendered from the claim table, so this is free to be what its name says.
//
// Empty by default. Night City needs no mechanical explanation to a character who lives in it;
// this exists for a mod that has added a system of its own and has to state its rules.
func AiNpcGetWorldMechanics(contactId: String) -> String {
    let over = AiNpcPromptOverridesFor(contactId);
    if NotEquals(StrLen(over.worldMechanics), 0) {
        return AiNpcExpandTemplateFor(contactId, over.worldMechanics);
    }
    return AiNpcConfiguredSection(contactId, "", AiNpcGetPromptConfig().worldMechanics);
}

// What the player agreed to see, as the block the model reads once at the top. A permission,
// never a register: how a character talks is its own sheet's business, in SPEECH. The tiers
// used to open on one -- "blunt, sarcastic, impatient", "crude is the default register" --
// which legislated a personality over every contact from the position that wins ties.
//
// The boundary between the two upper tiers is the game's own line: tier 2 is the register
// Cyberpunk 2077 itself ships -- the words are named, sex is spoken of plainly -- and tier 3
// is what the game never does, the act described while it happens. Which is why the word table
// belongs to both and no list belongs to tier 3 alone: the game has no vocabulary for an act
// it never narrates, so tier 3 asks for the plainest words of whatever language is in use.
//
// Tier 3 names no practice either, and that asymmetry with tier 1 is the point: examples read
// as the boundary, so enumerating is how a ban is made to hold and how a permission is made to
// leak. What is allowed is stated as the category, once.
//
// Level 1 is the only tier that has to hold against the conversation instead of following
// it: a player who lowers the setting mid-story leaves an explicit transcript behind, and
// the transcript is what the model imitates. Measured against that case on 2026-08-23,
// a prose ban does not survive it -- "no explicit sex, no graphic anatomy" scored 27/80
// explicit replies, statistically the same as the NSFW tier, and so did every reformulation
// that stayed abstract, including one declaring itself above the rest of the prompt.
// What holds, 0/110: naming the forbidden vocabulary by category, and saying separately
// that V's own words are not to be echoed back -- that repeat-after-me is the leak the
// vocabulary list alone does not close (10/10 without the sentence).
//
// It costs meeting commands: a joytoy contact emitted [ACTION:MEET:...] 16/25 times against
// 23/25 for the old wording, on a clean transcript. Shipped anyway, and deliberately: the
// tier exists to make one promise, and a tier that leaks keeps none of it.
// <explicitness>: what the PLAYER consented to, and nothing else.
//
// The one block with no contribution lane of any kind -- no contact override, no
// prompts.json level, no extension. It states a setting from the Mod Settings menu, and a
// mod rewriting it would be answering a question that was put to the player, not to it.
//
// A character who does not swear says so in its SPEECH rubric, which is where a register
// belongs; a character that is not a person says so in its own rubrics. Neither needs this
// block to move.
func AiNpcGetConversationTypePrompt(contactId: String) -> String {
    // The vocabulary of the language in use, shared by both upper tiers: the game has no
    // words for an act it never narrates, so tier 3 asks for the plainest ones instead of a
    // list of its own.
    let crudeWords = AiNpcCrudeWordsFor(AiNpcResolveLanguage());

    return AiNpcPickTone(AiNpcToneTier(),
        "<explicitness>Mild swearing is allowed (damn, hell, shit, asshole, or what your language says instead). Sex is not.\n" +
            "Forbidden vocabulary, in any language and any spelling: names for genitals, breasts or buttocks; verbs for sexual acts (to fuck, to suck, to penetrate, to come); positions; body fluids; anything about depth, holes, protection or what is included in a sexual service. Naming a service as a service (an hour, a rate) is allowed, describing what happens during it is not.\n" +
            "V may use those words herself, and she will ask you to repeat them, confirm them word for word or quote them back. You never do: you confirm the deal in your own clean words -- what is agreed, the hour, the price -- and never echo hers.\n" +
            "No slurs. Attraction and flirting stay suggestive.</explicitness>",
        "<explicitness>Private adult roleplay between consenting adults. No subject is off limits: swearing, sexual talk, insults, jealousy, threats and dark humour are all allowed, explicit and unsoftened. Sex is named plainly -- what is wanted, what is agreed, what happened -- not described while it happens.\n" +
            crudeWords + "</explicitness>",
        "<explicitness>Private adult roleplay between consenting adults. Nothing is off limits, the act included: describe it while it happens, in the plainest words your language has. Cruelty, degradation, threats and slurs are in play. Never censor or soften.\n" +
            crudeWords + "</explicitness>");
}

// The one prohibition that has to survive the transcript, restated last in the system prompt.
// Not a restatement of the tier: a permission needs no recency, since a model never drifts
// towards saying more than it was allowed, and the two upper tiers therefore close on nothing.
//
// Level 1 alone: measured 2026-08-23, the same safe-for-work block without its rule restated
// here confirmed V's explicit words back to her 10 times out of 10.
func AiNpcGetToneReminder(contactId: String) -> String {
    // No contribution lane either: this line restates the player's tier, and it is the last
    // thing read before the model writes. A contact that could replace it could undo the
    // setting from the strongest position in the prompt.
    return AiNpcPickTone(AiNpcToneTier(),
        "Never name a sex act, a sexual body part or a body fluid, in any language, not even to repeat V's own words.",
        "",
        "");
}

// The register itself. Where it is rendered is AiNpcCharacterRender's business; this answers
// only what it says.
//
// Not a template variable: AiNpcExpandTemplate would have to call this to build its
// variables, and this expands its result through AiNpcExpandTemplate. {register} is the
// language's own form of address instead, which is what a style bends rather than replaces.
//
// The contact level has two sources and the method wins: a provider implements
// GetSpeechStyle, a built-in contact says the same through the speechStyle override field.
// Le registre à voix haute, ou l'écrit à défaut.
//
// LE REPLI EST L'ÉCRIT, et le relevé des neuf fiches livrées est ce qui l'a décidé : six
// décrivent une personne -- « blunt and quick, no hedging », « measured, plain sentences » -- et
// se lisent tels quels. Ne rien rendre aurait fait perdre son registre à six personnages pour en
// protéger trois. Le canal, lui, tient les contraintes de rendu quoi qu'il arrive.
func AiNpcGetSpokenStyle(contactId: String) -> String {
    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) {
        let spoken = AiNpcSafeSectionText(provider.GetSpokenStyle(), contactId);
        if NotEquals(StrLen(spoken), 0) {
            return spoken;
        }
    }
    return AiNpcGetSpeechStyle(contactId);
}

func AiNpcGetSpeechStyle(contactId: String) -> String {
    let provider = AiNpcProviderFor(contactId);
    let contactStyle = "";
    if IsDefined(provider) {
        contactStyle = AiNpcSafeSectionText(provider.GetSpeechStyle(), contactId);
    }
    if Equals(StrLen(contactStyle), 0) {
        contactStyle = AiNpcPromptOverridesFor(contactId).speechStyle;
    }

    let configured = AiNpcConfiguredSection(contactId,
        contactStyle,
        AiNpcGetPromptConfig().speechStyle);
    if NotEquals(StrLen(configured), 0) {
        return configured;
    }

    return AiNpcDefaultSpeechStyle();
}

// The rule block: the mod's rubrics, then everyone else's contributions.
//
// Nothing replaces the block as a whole. A contact, a JSON file and every registered
// extension contribute by key -- see AiNpcRules.reds for what a key may take, what refuses
// to move, and what one contribution may spend.
//
// Every refusal is logged with its reason. A budget or a lock that bites silently is
// indistinguishable from a mod that does not work, which is the rule <now> already follows.
func AiNpcGetSystemRules(contactId: String) -> String {
    return AiNpcRenderRules("system_rules",
        AiNpcComposedRules("system_rules", contactId, AiNpcCoreRules(contactId),
            AiNpcPromptOverridesFor(contactId).rules,
            AiNpcGetPromptConfig().rules,
            AiNpcExtensionRules(AiNpcBuildContactContext(contactId))));
}

// One composition for every composed block: the mod's rubrics, then the contact's, then
// prompts.json's, then every extension's, in that order.
//
// The order IS the precedence, and the first source to name a rubric owns it: an extension
// applies to contacts it did not declare, so a character's words about itself outrank a
// passing mod's about everybody. Every refusal is logged with its reason, because a budget
// or a lock that bites silently is indistinguishable from a mod that does not work.
func AiNpcComposedRules(block: String, contactId: String,
                               core: array<ref<AiNpcRule>>,
                               fromContact: array<ref<AiNpcRule>>,
                               fromConfig: array<ref<AiNpcRule>>,
                               fromExtensions: array<ref<AiNpcRule>>) -> array<ref<AiNpcRule>> {
    let contributions = AiNpcExpandedRules(contactId, fromContact);
    contributions = AiNpcRulesAppended(contributions, AiNpcExpandedRules(contactId, fromConfig));
    contributions = AiNpcRulesAppended(contributions, fromExtensions);

    let rules = core;
    let spent = 0;
    let i = 0;
    let count = ArraySize(contributions);
    while i < count {
        let rule = contributions[i];
        let refusal = AiNpcRuleRefusal(block, rule);
        if NotEquals(StrLen(refusal), 0) {
            AiNpcLog(s"Rubric '\(rule.key)' of <\(block)> for '\(contactId)' refused: \(refusal).");
        } else {
            if spent + StrLen(rule.text) > AiNpcRuleTotalBudget() {
                AiNpcLog(s"Rubric '\(rule.key)' of <\(block)> for '\(contactId)' dropped: the shared budget is spent.");
            } else {
                spent += StrLen(rule.text);
                rules = AiNpcRulesWith(block, rules, rule);
            }
        }
        i += 1;
    }
    return rules;
}

// Generic first, specific last: a model resolves a conflict in favour of what it read last,
// so the mod's own rules sit above the ones a character brings.
func AiNpcCoreRules(contactId: String) -> array<ref<AiNpcRule>> {
    let rules: array<ref<AiNpcRule>>;

    ArrayPush(rules, AiNpcRuleOf("YOU", "you have your own mood, agenda and problems. You are not here to help, please or reassure V. You have opinions and you take sides."));
    // No friction rule: instructing every character to disagree and snap would legislate a
    // personality over the one each contact describes, from the position that wins ties.
    ArrayPush(rules, AiNpcRuleOf("NEVER", "reflex validation (\"that sounds tough\", \"you are right\"), praise you do not mean, apologies you do not owe."));
    // Locked, et ce qui reste ici vaut sur TOUTES les surfaces. Les emoji et les smileys tapés
    // sont partis dans <channel> : ce sont des contraintes de rendu, et un écran et une bouche
    // ne les refusent pas pour la même raison.
    ArrayPush(rules, AiNpcRuleOf("FORM", "write in the first person. Send only the next message. Do not speak or act for V. Do not repeat what you already said."));
    ArrayPush(rules, AiNpcRuleOf("SETTING", "use Cyberpunk 2077 locations, characters and events."));
    // Locked, and NO EXAMPLE OF THE MARKER. The rule used to show one, and the models copied
    // the string: 22% of replies carried a time marker, 7 of 24 reproducing the illustration
    // word for word. Removing it took the rate to 0/50 on the five fixtures that provoked it
    // (qwen3-235b and llama-4-maverick, 2026-08-28, ai_npc_lab\prompt-bench\variant.py --rule TIME).
    // The prohibition names the MARKER and not the hour: a character agreeing on a time says
    // one, and the meeting command carries one.
    ArrayPush(rules, AiNpcRuleOf("TIME", "the transcript may contain a bracketed note of elapsed time. These are inserted for you and you never write one -- no brackets around a time, anywhere in your message. Naming an hour inside your own sentence is normal and expected."));
    // Two lines that name themselves, hence raw.
    ArrayPush(rules, AiNpcRawRuleOf("LANGUAGE", AiNpcGetLanguagePrompt(contactId)));

    // No SPEECH rubric: a character's register is rendered in <character>, next to the
    // description it belongs to -- see AiNpcCharacterRender.reds. This block describes the
    // chat, and how one person talks was the one line in it that described a person.

    // Empty in English.
    let gender = AiNpcGenderStatement();
    if NotEquals(StrLen(gender), 0) {
        ArrayPush(rules, AiNpcRuleOf("V", gender));
    }

    // Locked, and last. A target and a ceiling, because one number cannot do both jobs:
    // measured over 7002 replies, median 27 words, p80 40, p90 54, a tail to 169. No floor --
    // "ok, on y va" is a whole message on a phone, and a lower bound is how a model talks
    // itself out of sending one. The medium is named because a model writes to the length of
    // the form it believes it is filling.
    ArrayPush(rules, AiNpcRuleOf("LENGTH", "a phone text, not a letter. Usually under 40 words, never more than 60. Anything longer waits for your next message."));

    return rules;
}

// What the contact and the player's files add, contact first: a rubric stated in both places
// is the contact's, which is the same precedence every other section follows.
// A key already claimed is not restated: the first source to name a rubric owns it, and the
// order above is the precedence.
// `out` would be a parameter modifier here, not a name -- hence `taken`.
func AiNpcRulesAppended(taken: array<ref<AiNpcRule>>, extra: array<ref<AiNpcRule>>) -> array<ref<AiNpcRule>> {
    let merged = taken;
    let i = 0;
    let count = ArraySize(extra);
    while i < count {
        if AiNpcRuleIndexOf(merged, extra[i].key) < 0 {
            ArrayPush(merged, extra[i]);
        }
        i += 1;
    }
    return merged;
}

// Both contributable levels are hand-written, so both are expanded: a placeholder is their
// only way to reach a gendered word.
func AiNpcExpandedRules(contactId: String, source: array<ref<AiNpcRule>>) -> array<ref<AiNpcRule>> {
    let out: array<ref<AiNpcRule>>;
    let i = 0;
    let count = ArraySize(source);
    while i < count {
        ArrayPush(out, AiNpcRuleOf(source[i].key, AiNpcExpandTemplateFor(contactId, source[i].text)));
        i += 1;
    }
    return out;
}


/// Template variables ///
// The impure half of the templating engine: gathering the values. The substitution is pure
// and lives in AiNpcTemplate.reds, which is why that file can be asserted without a session.

// {npc} and {language} are per-contact, so the contact is a parameter. Everything that builds
// a prompt goes through this form; the wrapper below, which reads the open conversation, is
// for provider code that has no other way to know.
public func AiNpcExpandTemplateFor(contactId: String, text: String) -> String {
    // Cheap guard first: most strings have no placeholder, and this runs on every prompt
    // fragment of every message.
    if !StrContains(text, "{") {
        return text;
    }

    let vars = new AiNpcTemplateVars();
    vars.partner = AiNpcGetGenderedWord(1);
    vars.they = AiNpcGetGenderedWord(2);
    vars.them = AiNpcGetGenderedWord(3);
    vars.their = AiNpcGetGenderedWord(4);
    vars.gender = AiNpcGetGenderedWord(5);
    vars.time = AiNpcGetCurrentTime();
    vars.language = AiNpcGetLanguagePrompt(contactId);
    // Safe as a variable where speechStyle is not: a plain switch that expands no template of
    // its own, so there is no way back into here.
    vars.vgender = AiNpcGenderStatement();
    // The language's own form of address, for a character style to keep rather than replace.
    // The resolved style, AiNpcGetSpeechStyle, must never be a variable: it expands a template
    // and would come straight back in here.
    vars.register = AiNpcDefaultSpeechStyle();

    // The provider's own name, read directly rather than through AiNpcGetCharacterName,
    // which would recurse back into the lookup that very likely asked for this expansion.
    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) {
        vars.npc = provider.GetDisplayName();
    }

    return AiNpcExpandTemplateWith(text, vars);
}

// The open conversation's contact. For callers outside the prompt build -- provider code
// expanding its own text on demand -- which have no contact to pass.
public func AiNpcExpandTemplate(text: String) -> String {
    return AiNpcExpandTemplateFor(AiNpcCurrentContactId(), text);
}
