// Which tags a contact carries, and who is allowed to say so.
//
// A tag is what a character IS: "joytoy:client", "ainpc:contact". It is how an action finds
// the people it applies to without either mod having heard of the other -- a taxi mod grants
// a command to `ainpc:contact` and reaches an anonymous escort minted at runtime by a mod it
// has never seen, and neither author had to enumerate anything.
//
// TAGS ONLY EVER ADD. Removing an action from a character is the other lever entirely, the
// suppression in AiNpcActionRegistry, and it belongs to whoever declared that character. The
// asymmetry is the design: reach accumulates and refusals are listed, so a behaviour can be
// read without knowing which mods are installed.
//
// The corollary is the rule that makes the whole thing safe: A TAG IS NEVER OMITTED IN ORDER
// TO REMOVE REACH. If leaving a tag out could take a character out of somebody's rule, then
// every tag this mod adds later becomes one more thing every modder must remember to write,
// and the forgetting would silently break OTHER MODS' actions. So the two tags below are
// granted here, cannot be written by a mod, and cannot be dropped.
//
// Flat, never hierarchical. The colon is a naming convention that keeps mods off each other's
// names -- the comparison is on the whole string and never splits it. A shallow hierarchy is
// already a set: a VIP carries "joytoy:client" AND "joytoy:vip", which is what "joytoy:client:*"
// would have bought without teaching the matcher a wildcard. Flat matching stays a subset of
// wildcard matching, so the day a real case needs one it can be added without invalidating a
// single tag written before it.
module AiNpc

// The two namespaces ai_npc GRANTS. A mod may not assign inside them -- these tags are given
// out by this file, which is what makes them impossible to forget.
//
// Reservation is about granting, never about targeting. A command may perfectly well be scoped
// to "ainpc:contact" or to "contact:judy": that is a mod saying who its command is for, which
// is the whole point. What it may not do is hand "contact:judy" to Panam, which would quietly
// give her every command written for Judy.
func AiNpcReservedTagNamespace() -> String {
    return "ainpc:";
}

func AiNpcTagIsReserved(tag: String) -> Bool {
    return StrBeginsWith(tag, AiNpcReservedTagNamespace())
        || StrBeginsWith(tag, "contact:");
}

// A tag a mod is allowed to write: non-empty, no space, outside the reserved namespace.
func AiNpcTagIsWellFormed(tag: String) -> Bool {
    return StrLen(tag) > 0 && !StrContains(tag, " ") && !StrContains(tag, ",");
}

/// What a mod assigns ///

public class AiNpcAssignedTag {
    public let modId: String;
    public let contactId: String;
    public let tag: String;
}

// Session lifetime, like every other registry here: assignments must not leak across a save
// load, and a mod re-assigns on every attach.
public class AiNpcContactTagStore extends ScriptableSystem {

    private let m_assigned: array<ref<AiNpcAssignedTag>>;

    public static func Get(game: GameInstance) -> ref<AiNpcContactTagStore> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(NameOf<AiNpcContactTagStore>()) as AiNpcContactTagStore;
    }

    // Idempotent: the same mod assigning the same tag to the same contact twice is one
    // assignment, so a mod can call this unconditionally on every attach.
    public func Assign(modId: String, contactId: String, tag: String) -> Bool {
        if Equals(StrLen(modId), 0) || Equals(StrLen(contactId), 0) {
            return false;
        }
        if !AiNpcTagIsWellFormed(tag) {
            FTLogError(s"[ai_npc]: '\(modId)' cannot assign tag \"\(tag)\" to '\(contactId)': a tag must be a single word with no comma.");
            return false;
        }
        if AiNpcTagIsReserved(tag) {
            FTLogError(s"[ai_npc]: '\(modId)' cannot assign tag \"\(tag)\" to '\(contactId)': \"\(AiNpcReservedTagNamespace())\" and \"contact:\" are granted by ai_npc, never given. Handing one character another's tag would pass on every command written for them.");
            return false;
        }

        let i = 0;
        let count = ArraySize(this.m_assigned);
        while i < count {
            let existing = this.m_assigned[i];
            if Equals(existing.modId, modId) && Equals(existing.contactId, contactId)
                    && Equals(existing.tag, tag) {
                return true;
            }
            i += 1;
        }

        let entry = new AiNpcAssignedTag();
        entry.modId = modId;
        entry.contactId = contactId;
        entry.tag = tag;
        ArrayPush(this.m_assigned, entry);
        AiNpcLog(s"'\(modId)' tagged '\(contactId)' as \(tag).");
        return true;
    }

    // A mod retracts only its own assignment. Another mod's identical tag stands, because it
    // was a second author saying the same thing rather than the same author saying it twice.
    public func Retract(modId: String, contactId: String, tag: String) -> Bool {
        let i = 0;
        while i < ArraySize(this.m_assigned) {
            let existing = this.m_assigned[i];
            if Equals(existing.modId, modId) && Equals(existing.contactId, contactId)
                    && Equals(existing.tag, tag) {
                ArrayErase(this.m_assigned, i);
                return true;
            }
            i += 1;
        }
        return false;
    }

    public func AssignedFor(contactId: String) -> array<String> {
        let tags: array<String>;
        let i = 0;
        let count = ArraySize(this.m_assigned);
        while i < count {
            if Equals(this.m_assigned[i].contactId, contactId)
                    && !ArrayContains(tags, this.m_assigned[i].tag) {
                ArrayPush(tags, this.m_assigned[i].tag);
            }
            i += 1;
        }
        return tags;
    }

    public func All() -> array<ref<AiNpcAssignedTag>> {
        return this.m_assigned;
    }
}

public func AiNpcGetContactTagStore() -> ref<AiNpcContactTagStore> {
    return AiNpcContactTagStore.Get(GetGameInstance());
}

/// Resolution ///

// Everything one contact carries, from three sources, deduped.
//
// The two granted tags come first and unconditionally. Then whoever declared the character,
// then whoever assigned from outside -- and the last two are peers: a mod that declares a
// character has no more right to say what it is than a mod that extends it, because a tag
// adds and never takes away.
//
// Built once per message and handed to the handlers on the context, rather than resolved per
// claim: a dozen commands on one contact must not mean a dozen walks of the same three lists.
public func AiNpcContactTags(contactId: String) -> array<String> {
    let tags: array<String>;
    if Equals(StrLen(contactId), 0) {
        return tags;
    }

    ArrayPush(tags, AiNpcEveryContactTag());
    ArrayPush(tags, AiNpcContactTagFor(contactId));

    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) {
        let declared = provider.GetContactTags();
        let i = 0;
        let count = ArraySize(declared);
        while i < count {
            AiNpcPushDeclaredTag(tags, declared[i], contactId);
            i += 1;
        }
    }

    let store = AiNpcGetContactTagStore();
    if IsDefined(store) {
        let assigned = store.AssignedFor(contactId);
        let j = 0;
        let assignedCount = ArraySize(assigned);
        while j < assignedCount {
            AiNpcPushDeclaredTag(tags, assigned[j], contactId);
            j += 1;
        }
    }

    return tags;
}

// The reserved check runs HERE as well as at assignment, because a provider is code: a sheet
// is validated at load where the player can still fix it, and a script provider compiled into
// a mod has no such moment. The rule has to be true of both.
func AiNpcPushDeclaredTag(out tags: array<String>, tag: String, contactId: String) -> Void {
    if !AiNpcTagIsWellFormed(tag) || ArrayContains(tags, tag) {
        return;
    }
    if AiNpcTagIsReserved(tag) {
        AiNpcLog(s"Tag \(tag) on '\(contactId)' ignored: \"\(AiNpcReservedTagNamespace())\" is ai_npc's own namespace.");
        return;
    }
    ArrayPush(tags, tag);
}
