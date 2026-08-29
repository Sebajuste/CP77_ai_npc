module AiNpc

// What another mod adds to what every character knows about Night City.
//
// Not an extension with an empty contact list, though that already has the right merge and
// the right audience: the regime is wrong. GetLiveContext lands in <now>, rebuilt and
// budgeted per message, because several mods each describing the moment is how the message V
// wrote ends up outweighed by commentary about it. A fact about the world is the opposite --
// it does not change between two messages and competes with nobody's account of the moment,
// so it is stated once in the background rather than truncated and re-billed every time.
//
// The rules, in the order that matters:
//
//   1. Additive, never substitutive: it joins <world_background> after the built-in text and
//      after prompts.json, and neither is diminished. AiNpcGetWorldBackground appends in both
//      of its branches, because a contact whose background is overridden still lives in the
//      same city. GetPromptOverrides cannot do this -- worldBackground is a silent loss.
//
//   2. Concatenated in full-id order, like extensions, never registration order: attachment
//      order differs between two loads of one save, so the prompt would change per launch. No
//      contribution may depend on running before or after another -- one that would need to
//      is a disagreement about the world, not an addition to it.
//
//   3. Idempotent by subject, so a mod re-registering every session needs no state of its own.
//
//   4. Told to every drivable character. An audience filter, if ever wanted, arrives as an
//      `opt` parameter -- which is why this is free functions rather than a virtual method: a
//      changed virtual signature leaves a consumer's override silently overriding nothing.
//
//   5. Withdrawn by UnregisterAll: a mod that pulls out and leaves a standing fact about the
//      city behind is a mod still talking after it left.
//
//   6. Bounded at registration, not at the prompt, and refused rather than clamped: this text
//      is written once by an author reading the return value, so false-and-a-log comes while
//      they can still shorten it. Clamping would ship half a sentence into every prompt.
//
// Its own system rather than a third entry kind in AiNpcExtensionRegistry: the two that
// registry holds are objects asked a question per message per contact through a context,
// while a world fact is a string, asked nothing, addressed to everyone.
//
// A ScriptableSystem, because the lifetime is the game session: registrations must not leak
// across a save load, and a mod re-registers on every attach.

/// The bound ///

// Characters per contribution, and deliberately not the <now> number: this text is stated
// once in the invariant half of the prompt, so it is paid once per conversation. 1200 is room
// for a real paragraph and still small enough that ten mods cannot outweigh the lore.
func AiNpcWorldKnowledgeBudget() -> Int32 {
    return 1200;
}

// What a contribution has to be to be held. Pure, so the rule is covered without a session.
func AiNpcWorldFactIsWellFormed(subject: String, text: String) -> Bool {
    return NotEquals(StrLen(subject), 0)
        && NotEquals(StrLen(text), 0)
        && StrLen(text) <= AiNpcWorldKnowledgeBudget()
        // A tag here closes <character> or <world_background> and lets what follows open a
        // block of its own -- see AiNpcSectionText.reds.
        && !AiNpcTextLooksLikeMarkup(text);
}

/// Entries ///

// One standing fact, and the id it is sorted by.
public class AiNpcWorldFactEntry {
    public let fullId: String;
    public let modId: String;
    public let subject: String;
    public let text: String;

    // Who is told; "" is everyone, the ordinary case. A named contact changes the destination
    // as well as the audience: a fact about the city belongs in <world_background>, something
    // true of one person in <character> after the bio. "You dislike this trade" in the world
    // background would state it as a property of Night City rather than of her.
    public let contactId: String;
}

/// The store ///

// The identity of an entry, and the contact is part of it.
//
// Leaving it out made one mod unable to say the same thing about two people: the second
// CharacterAlsoIs(panam, "bar", ...) replaced the first CharacterAlsoIs(judy, "bar", ...)
// under a shared id, silently. Worse, a character addition and a standing fact about the city
// sharing a subject were the same entry, so adding one deleted the other.
func AiNpcWorldFactId(modId: String, subject: String, contactId: String) -> String {
    if Equals(StrLen(contactId), 0) {
        return modId + ":" + subject;
    }
    return modId + ":" + contactId + ":" + subject;
}

public class AiNpcWorldKnowledgeRegistry extends ScriptableSystem {

    private let m_facts: array<ref<AiNpcWorldFactEntry>>;

    public static func Get(game: GameInstance) -> ref<AiNpcWorldKnowledgeRegistry> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(NameOf<AiNpcWorldKnowledgeRegistry>()) as AiNpcWorldKnowledgeRegistry;
    }

    // Sorted on insert rather than at query time: registrations happen once at attach, the
    // prompt is built on every message.
    public func Register(modId: String, subject: String, text: String, opt contactId: String) -> Bool {
        if Equals(StrLen(modId), 0) {
            return false;
        }
        if !AiNpcWorldFactIsWellFormed(subject, text) {
            FTLogError(s"[ai_npc]: world knowledge from '\(modId)' refused: subject '\(subject)', \(StrLen(text)) chars, budget \(AiNpcWorldKnowledgeBudget()).");
            return false;
        }

        let entry = new AiNpcWorldFactEntry();
        entry.modId = modId;
        entry.subject = subject;
        entry.fullId = AiNpcWorldFactId(modId, subject, contactId);
        entry.text = text;
        entry.contactId = contactId;

        let existingIds = this.FactIds();
        let existing = AiNpcIdIndexOf(existingIds, entry.fullId);
        if existing >= 0 {
            this.m_facts[existing] = entry;
            return true;
        }

        ArrayInsert(this.m_facts, AiNpcIdInsertionPoint(existingIds, entry.fullId), entry);
        AiNpcLog(s"Registered world knowledge '\(entry.fullId)'.");
        return true;
    }

    public func Unregister(modId: String, subject: String, opt contactId: String) -> Bool {
        let index = AiNpcIdIndexOf(this.FactIds(), AiNpcWorldFactId(modId, subject, contactId));
        if index < 0 {
            return false;
        }
        ArrayErase(this.m_facts, index);
        return true;
    }

    // Walked backwards so erasing does not move entries the loop has not reached yet.
    public func UnregisterAllFor(modId: String) -> Void {
        let i = ArraySize(this.m_facts) - 1;
        while i >= 0 {
            if Equals(this.m_facts[i].modId, modId) {
                ArrayErase(this.m_facts, i);
            }
            i -= 1;
        }
    }

    public func Facts() -> array<ref<AiNpcWorldFactEntry>> {
        return this.m_facts;
    }

    private func FactIds() -> array<String> {
        let ids: array<String>;
        let i = 0;
        let count = ArraySize(this.m_facts);
        while i < count {
            ArrayPush(ids, this.m_facts[i].fullId);
            i += 1;
        }
        return ids;
    }
}

func AiNpcGetWorldKnowledgeRegistry() -> ref<AiNpcWorldKnowledgeRegistry> {
    return AiNpcWorldKnowledgeRegistry.Get(GetGameInstance());
}

/// What reaches the prompt ///

// The contributions, raw, one per line, in the order they are held. Raw is the decision: no
// subject heading, no attribution, no separator that would read as a list. What is added to
// the world has to read like the rest of it, and a paragraph under a "joytoys:implants" label
// reads to the model as a quotation rather than as something everyone here knows.
//
// Pure -- it takes the entries rather than fetching them -- so the merge is covered without a
// session.
//
// `audience` is who is addressed: "" collects what is told to everyone, a contact id what is
// held for that character alone. Never both: merging them would put one character's trait into
// the block that describes the city.
func AiNpcWorldKnowledgeFragment(facts: array<ref<AiNpcWorldFactEntry>>,
                                        opt audience: String) -> String {
    let merged = "";
    let i = 0;
    let count = ArraySize(facts);
    while i < count {
        if Equals(facts[i].contactId, audience) {
            merged += facts[i].text + "\n";
        }
        i += 1;
    }
    return merged;
}

// Appends to a background, or hands it back untouched: the additive rule, in the one function
// both branches of AiNpcGetWorldBackground call.
//
// A newline before the addition: the built-in lore ends on a rubric line, and running a mod's
// sentence onto the end of it is how a fact becomes part of the previous claim.
func AiNpcWorldBackgroundWith(background: String, addition: String) -> String {
    if Equals(StrLen(addition), 0) {
        return background;
    }
    if Equals(StrLen(background), 0) {
        return addition;
    }
    return background + "\n" + addition;
}

// Empty when nothing is held or the session is not up, which is what makes this callable from
// the prompt builder with no guard.
func AiNpcWorldKnowledgeText() -> String {
    let registry = AiNpcGetWorldKnowledgeRegistry();
    if !IsDefined(registry) {
        return "";
    }
    return AiNpcWorldKnowledgeFragment(registry.Facts());
}

// What another mod added to one character, joined to the end of the bio in <character>. Empty
// for most contacts, so the prompt builder needs no guard.
func AiNpcCharacterAdditionsText(contactId: String) -> String {
    let registry = AiNpcGetWorldKnowledgeRegistry();
    if !IsDefined(registry) || Equals(StrLen(contactId), 0) {
        return "";
    }
    return AiNpcWorldKnowledgeFragment(registry.Facts(), contactId);
}

/// The capability, as the facade calls it ///

// Free functions rather than methods on a registry handle: an audience filter added later is
// an `opt` parameter here and costs no consumer anything.
public func AiNpcRegisterWorldKnowledge(modId: String, subject: String, text: String) -> Bool {
    let registry = AiNpcGetWorldKnowledgeRegistry();
    return IsDefined(registry) && registry.Register(modId, subject, text);
}

public func AiNpcUnregisterWorldKnowledge(modId: String, subject: String) -> Bool {
    let registry = AiNpcGetWorldKnowledgeRegistry();
    return IsDefined(registry) && registry.Unregister(modId, subject);
}

// The same store addressed to one character: what this mod adds to who that person is. Every
// rule above still holds and only the destination differs.
//
// It replaces nothing, which is what makes it safe for a mod to touch somebody else's
// character: the bio, the relationship and the speech style stay as whoever declared them
// wrote them, and this joins the end of the bio. Two bios do not merge, but a bio and an
// addition to it do.
public func AiNpcRegisterCharacterAddition(modId: String, contactId: String, subject: String,
                                           text: String) -> Bool {
    if Equals(StrLen(contactId), 0) {
        return false;      // that is world knowledge, and it has its own door
    }
    let registry = AiNpcGetWorldKnowledgeRegistry();
    return IsDefined(registry) && registry.Register(modId, subject, text, contactId);
}

// Retracts one character's addition, and only that one. It needs the contactId for the same
// reason registering does: without it this addressed a standing fact about Night City that
// happened to share the subject, deleted that instead, and left the addition in place.
public func AiNpcUnregisterCharacterAddition(modId: String, contactId: String,
                                             subject: String) -> Bool {
    if Equals(StrLen(contactId), 0) {
        return false;
    }
    let registry = AiNpcGetWorldKnowledgeRegistry();
    return IsDefined(registry) && registry.Unregister(modId, subject, contactId);
}
