module AiNpc

// Public extension point: learning what happened, without taking part in it.
//
// The only shared interface in this API that needs no merge rule, ordering, arbitration or
// budget, because nothing it returns is used: N listeners, one broadcast. Its own type rather
// than more methods on AiNpcCharacterExtension, where every addition has to answer "and if
// two mods answer at once?".
//
// An observer observes: it cannot refuse, modify or reorder. A listener that may say no puts
// the conflict straight back -- two mods vetoing one reply, decided by registration order.
// Anything that needs to say no belongs on the extension, where the merge rule is written.
//
// It replaces polling AiNpcReadConversation -- the whole thread, not a window -- in a loop,
// and removes the limitation ai_npc_joytoys works around by doing nothing: a provider
// registered later by another mod is not wrapped, and detecting it meant polling the
// registry forever.

/// Events ///

// Classes rather than parameter lists: a field added to a class the consumer never constructs
// is safe, while a parameter added to a virtual method the consumer overrides silently stops
// the override from overriding.

// A message was written into a thread -- by the character, by V, generated or seeded.
public class AiNpcMessageEvent extends IScriptable {
    public let contactId: String;
    public let text: String;
    public let fromPlayer: Bool;

    // "<modId>", or "" for ai_npc itself -- a generated reply, or V typing into the chat. Read
    // it to tell your own writes from everyone else's: a listener that answers messages and
    // cannot recognise its own answers will answer itself. Session-lived; nothing about the
    // author is stored, because what was said stays said.
    public let sourceId: String;

    // True when the line is the mod speaking rather than a person in the fiction: the operator
    // notice standing in for a reply that never arrived. `fromPlayer` is false for it as for a
    // real answer, so without this field "[NO SIGNAL: HTTP 0]" is indistinguishable from Panam
    // answering.
    //
    // Announced rather than withheld, because the store keeps it: a listener replaying the
    // thread from events must see the same thread the store does, and dropping it would make
    // the two diverge exactly on the turns where something went wrong.
    public let systemNotice: Bool;

    // By which medium: "text", "holo", or the name of a channel this mod has not heard of.
    // AiNpcTextChannel() and its neighbours spell the ones that exist.
    //
    // COMPARE IT FOR A CHANNEL YOU KNOW; BRANCH ON THE TWO PREDICATES BELOW FOR EVERY OTHER.
    // The set is open -- a face-to-face channel is planned -- and a listener that writes
    // `if holo { ... } else { /* texting */ }` swallows the next one into its `else` with no
    // error and no log.
    public let channel: String;

    // A mouth said this: no emoji, no stage directions, and nothing to paint in a phone thread.
    // Being spoken does not make it a call, which is why this is a question of its own.
    public let spoken: Bool;

    // Whether the written thread paints this line. False for what was said out loud, of which
    // the thread keeps only a trace -- so a mod mirroring a thread does not show it as an SMS.
    public let showsInThread: Bool;
}

// A reply was expected and did not arrive. Only failures are announced: a reply that arrives
// is already an AiNpcMessageEvent, and publishing it twice would have every listener choose
// which to trust.
public class AiNpcReplyFailedEvent extends IScriptable {
    public let contactId: String;

    // Plain text, for a log or a fallback line. No closed vocabulary of causes: the ways a
    // network call fails are not ai_npc's to enumerate, and a mod branching on them breaks the
    // day one more is added.
    //
    // No HTTP status: of the four paths to the failure site -- bad credentials, an unparseable
    // body, a watchdog timeout, a non-OK response -- only the last has one, and a field
    // present three times in four as a zero is worse than no field, since zero already means
    // "the request never left" elsewhere.
    public let reason: String;
}

// Published whether the tag was applied or refused: a refusal is where a mod finds out the
// model is being argued into commands its own preconditions keep rejecting.
public class AiNpcActionEvent extends IScriptable {
    public let contactId: String;
    public let tag: String;
    public let sourceId: String;      // the full id of the claimant, "<modId>:<subject>"
    public let applied: Bool;
    public let note: String;
}

// The chat was opened or closed on a contact.
public class AiNpcThreadEvent extends IScriptable {
    public let contactId: String;
}

// Both sides are carried, so a listener never has to remember the previous state. holderId ""
// means the floor is now free.
public class AiNpcFloorEvent extends IScriptable {
    public let contactId: String;
    public let holderId: String;
    public let previousHolderId: String;

    // True when the lease ran out rather than ReleaseFloor being called: an expiry means a mod
    // stopped mid-scene, leaving the character in a conversation nobody is driving.
    public let expired: Bool;
}

// The counterpart to AiNpcTicketState for a mod that would rather be told than ask, carrying
// the same values. Named for the ticket because two kinds arrive here:
//
//   CharacterKnows        the fact was recorded, or could not be
//   CharacterWantsToSay   she wrote, or she did not -- the only channel that says so, since
//                         an unprompted turn puts nothing on the player's screen when it fails
//
// Renamed from OnFactRecorded, which named the first and hid the second, while nothing
// implemented it: renaming an overridable method after a consumer ships turns their override
// into dead code, silently.
public class AiNpcTicketEvent extends IScriptable {
    public let contactId: String;
    public let ticket: Int32;
    // Everything except Pending, which is not a verdict. Fall back on Failed only: Cancelled is
    // your own withdrawal, and Refused is the player having turned unprompted messages off.
    public let state: Int32;
    public let reason: String;        // empty on success
}

/// The listener ///

public class AiNpcConversationListener extends IScriptable {

    // The subject half of the id, as on AiNpcCharacterExtension: the client supplies the mod
    // name and the full id is "<modId>:<subject>".
    public func GetSubject() -> String {
        return "";
    }

    // Empty means all, which is the common case: a listener usually watches for a kind of
    // event rather than for one character.
    public func GetContactIds() -> array<String> {
        let empty: array<String>;
        return empty;
    }

    // Every method below is called with the event and returns nothing. There is no ordering
    // guarantee between listeners and never will be: an order that mattered would mean the
    // callbacks were doing something.
    //
    // Do not block. A listener runs on the caller's stack, inside the write it is reporting.

    public func OnMessage(ev: ref<AiNpcMessageEvent>) -> Void {
    }

    public func OnReplyFailed(ev: ref<AiNpcReplyFailedEvent>) -> Void {
    }

    public func OnActionApplied(ev: ref<AiNpcActionEvent>) -> Void {
    }

    public func OnConversationOpened(ev: ref<AiNpcThreadEvent>) -> Void {
    }

    public func OnConversationClosed(ev: ref<AiNpcThreadEvent>) -> Void {
    }

    public func OnFloorChanged(ev: ref<AiNpcFloorEvent>) -> Void {
    }

    public func OnTicketSettled(ev: ref<AiNpcTicketEvent>) -> Void {
    }
}

/// Waiting for ai_npc ///

// Handed the client it was waiting for, so there is nothing to look up on arrival.
//
// Needed less often than it looks: AiNpcOpenClient never returns null and queues what is
// idempotent and undated, so a mod that only registers things at startup never has to know
// whether ai_npc was up. This is for the mod that needs to read early, since a read cannot be
// queued. It costs a guarded class declaration, which is why it is not the default answer.
public class AiNpcReadyHandler extends IScriptable {

    // Runs on the caller's stack, immediately, when ai_npc is already up at the moment
    // AiNpcWhenReady is called, so it must tolerate being re-entered from inside its own mod's
    // attach.
    public func OnAiNpcReady(client: ref<AiNpcClient>) -> Void {
    }
}
