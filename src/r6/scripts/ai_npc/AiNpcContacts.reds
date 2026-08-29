// Contact identity: which contacts exist, which one is selected, and what a contact id
// means.
//
// The rule this file exists to hold in one place: THE IDENTITY OF A CONTACT IS ITS STRING.
// Everything about a character -- name, bio, relationship, quest context -- is looked up
// FROM that string, in that character's sheet (cast\), and nothing derives it back.
//
// The lookups at the bottom are the only way the rest of the mod reads a character. They
// ask the contact's provider and stop there: a shipped character has one too, built from
// its sheet, so there is no second answer hiding behind a fallback.
module AiNpc

// Every contact id the mod can drive. Single source of truth: used to seed
// conversations.json and to validate contacts in the phone UI.
public func AiNpcGetAllContactIds() -> array<String> {
    return [
        "panam",
        "judy",
        "river_ward",
        "kerry_eurodyne",
        "songbird",
        "rogue",
        "victor_vector",
        "takemura",
        "jackie",
        "jackie_dead",
        "stud"
    ];
}

// True for a contact this mod ships with. Used to decide whether a config entry is an
// override of built-in text or the definition of a brand new contact -- the two have
// different validation rules, because a new contact with no bio is a real problem while
// an override with no bio just means "keep what you had".
func AiNpcIsBuiltinContactId(contactId: String) -> Bool {
    let ids = AiNpcGetAllContactIds();
    return ArrayContains(ids, contactId);
}

// Every contact the mod can drive right now: the built-in list plus whatever providers
// are registered and currently available. Unlike AiNpcGetAllContactIds this is not a
// constant -- a provider can appear or disappear mid-session.
public func AiNpcGetActiveContactIds() -> array<String> {
    let result = AiNpcGetAllContactIds();

    let registry = AiNpcGetContactRegistry();
    if !IsDefined(registry) {
        return result;
    }

    let registered = registry.AllAvailableContactIds();
    let i = 0;
    let count = ArraySize(registered);
    while i < count {
        if !ArrayContains(result, registered[i]) {
            ArrayPush(result, registered[i]);
        }
        i += 1;
    }
    return result;
}

// The provider backing a contact, or null when nothing overrides the built-in text.
//
// Keyed by id rather than by the enum, which could not name an external contact at all.
func AiNpcProviderFor(contactId: String) -> ref<AiNpcContactProvider> {
    return AiNpcFindContact(contactId);
}

// The contact whose thread is on screen, on WHICHEVER surface is showing one.
//
// Asked of the session registry and not of AiNpcSystem, which is the phone's model and knows
// nothing about AGENT LINK: through the terminal this answered the phone's last contact --
// "panam" on a fresh save -- and it is what the public AiNpcCharacterInOpenChat and AiNpcExpand
// are built on, so both were wrong for a whole surface.
//
// "" when nothing is open, which is the honest answer: there is no "last contact" to fall back
// on, and a stale one reads downstream as a conversation that is not there.
func AiNpcCurrentContactId() -> String {
    return AiNpcShownContactId(AiNpcChatSessions());
}

public func AiNpcIsContactSupported(character: String) -> Bool {
    return AiNpcIsContactReachable(character, AiNpcFindContact(character));
}

//
// THE SAME TWO QUESTIONS, ASKED OF A PROVIDER THE CALLER ALREADY HOLDS. The id-shaped
// versions above and below are written on top of these, so the two shapes cannot drift apart.
//
// They exist for one caller: the contact-row badge, which runs once per row per redraw of the
// phone's contact list and would otherwise resolve the same provider twice, each time a
// linear scan of the registry comparing GetContactId() on everything it walks past. Anywhere
// else, take the id-shaped ones.
//
// The contact id is still a parameter of the first, and not redundantly: a built-in contact
// is supported because this mod ships it, which is true before any provider is consulted.
func AiNpcIsContactReachable(character: String, provider: ref<AiNpcContactProvider>) -> Bool {
    // The array MUST be bound to a local first. REDscript array intrinsics take their
    // operand by reference, and a call's return value is a temporary with no stable slot:
    // ArrayContains(AiNpcGetAllContactIds(), character) compiles clean, warns nothing,
    // reads the wrong stack slot, and answers false for every name -- which reads in game
    // as no contact being recognised at all. Same rule for ArraySize.
    let ids = AiNpcGetAllContactIds();
    if ArrayContains(ids, character) {
        // Shipping a character is not the same as V being able to write to them today. The
        // story says when, and it is read here rather than at lookup time for the same reason
        // a third-party provider's IsAvailable is: the conversation must survive the silence
        // and come back, not be torn down and lost.
        return AiNpcContactIsInPlay(character);
    }

    // A registered contact from another mod. IsAvailable is honoured here rather than at
    // lookup time: that is what lets a mod suspend AI chat during its own scripted
    // exchange without tearing its provider down and losing the conversation.
    return IsDefined(provider) && provider.IsAvailable();
}

func AiNpcNameOfProvider(provider: ref<AiNpcContactProvider>) -> String {
    if IsDefined(provider) {
        let name = provider.GetDisplayName();
        if NotEquals(StrLen(name), 0) {
            return name;
        }
    }
    return "Unknown";
}

/// What a contact id means ///

// The three below are how the whole mod reads a character, and they are deliberately
// thin: find the provider, ask it, expand the placeholders. A shipped character has a
// provider like anybody else -- the registry builds one per sheet in cast\ -- so there is
// no built-in branch here and no way for the two to disagree.
//
// An id nobody has a sheet for gets the generic answer. That is a real case, not a
// defensive one: another mod can hand the phone a contact and never describe it.

func AiNpcGetCharacterName(contactId: String) -> String {
    return AiNpcNameOfProvider(AiNpcProviderFor(contactId));
}

func AiNpcGetCharacterBio(contactId: String) -> String {
    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) {
        let bio = AiNpcSafeSectionText(provider.GetBio(), contactId);
        if NotEquals(StrLen(bio), 0) {
            return AiNpcExpandTemplateFor(contactId, bio);
        }
    }
    return "You are a Night City local in a text conversation with V.";
}

func AiNpcGetRelationship(contactId: String) -> String {
    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) {
        return AiNpcExpandTemplateFor(contactId,
            AiNpcSafeSectionText(provider.GetRelationship(), contactId));
    }
    return "";
}
