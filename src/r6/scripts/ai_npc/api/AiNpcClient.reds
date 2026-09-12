module AiNpc

// The writing half of the contract: a free function reads, a client method writes. An
// integrator can hold that in their head -- if you needed the client, you changed something.
// The integrator's guide is docs\API.md.
//
// The author is carried on the object rather than as an `opt sourceId` on each call: restated
// at every call site, one typo creates a ghost author whose facts nobody can retract. First
// claim on a modId wins, as for a contactId, so an attribution is never ambiguous. That is a
// collision model, not a threat model -- nothing stops a mod claiming a name first.
//
// These methods are called, never overridden, so they can take new `opt` parameters without
// silently unhooking anyone. Do not subclass this class.
//
// No logic below: every method is one delegating line, because a consumer taking ai_npc
// optionally mirrors this behind @if and would have to compute anything here identically.

// Every vocabulary crosses the @if boundary as Int32, because Int32 is all that can. Nothing
// stops a caller comparing a value of one vocabulary against a constant of another, so the
// ones that are compared get disjoint ranges and a confusion then matches nothing:
//
//     ticket states    0-3     0 is Unknown, because querying ticket 0 lands somewhere
//     open outcomes    10-14   0 unused, so a default-initialised Int32 is never an outcome
//     write outcomes   20-24   idem
//
// AiNpcUntilNextReply and AiNpcUntilForever stay at 0 and 1, outside the scheme: they are
// passed, never compared against an outcome, and 0 is what an `opt` parameter defaults to.
// AiNpcClientCharacterKnows logs the one crossing this cannot cover.

/// Ticket states ///

// Functions rather than an enum, for the reason above.
public func AiNpcTicketUnknown() -> Int32 {
    return 0;
}

// Accepted, not settled: there is no conversation to hang the statement on yet. Retried when
// that contact next speaks, so a mod seeding ahead of the first message need not watch for one.
public func AiNpcTicketPending() -> Int32 {
    return 1;
}

public func AiNpcTicketDone() -> Int32 {
    return 2;
}

public func AiNpcTicketFailed() -> Int32 {
    return 3;
}

// You withdrew the request with CancelWantsToSay before it went out. Not Failed, because
// Failed is what a mod falls back on: the author who withdrew did so because the moment had
// passed, and must not have their own fallback fire.
public func AiNpcTicketCancelled() -> Int32 {
    return 4;
}

// The player turned unprompted messages off. Also not Failed, for the opposite reason: the
// player answered a question about the gesture, so an authored SMS pushed in its place is the
// same thing they refused. Read it as "stop asking, for this session".
public func AiNpcTicketRefused() -> Int32 {
    return 5;
}

// Everything except Pending, Unknown included: a ticket that fell out of the ring is not still
// being worked on.
public func AiNpcTicketIsSettled(state: Int32) -> Bool {
    return NotEquals(state, AiNpcTicketPending());
}

/// How long a reason stays true ///

// How long ai_npc may hold your reason, in seconds of play, waiting for room to write. The
// value is the window, so there is no third policy: "as soon as possible" without a bound is
// not implementable honestly, and a reason held past the moment it describes is delivered as a
// message that contradicts the game.
//
// 0 is what an `opt` parameter takes, and now-or-never is what this call has always done, so a
// caller written before this argument existed keeps its behaviour.
public func AiNpcSayNow() -> Int32 {
    return 0;
}

// Queued, and sent the moment the lane is free, the floor is clear and the contact's debounce
// has lifted -- or dropped, with Failed on its ticket, if that has not happened within
// `seconds` of play.
//
// It does not survive a save load: the queue goes with the session, so a reload answers nothing
// on the ticket. Gate your retry on something you persist -- a quest fact set from
// OnTicketSettled, or AiNpcReadConversation. Retrying blind on every load writes one message
// twice.
public func AiNpcSayWithin(seconds: Int32) -> Int32 {
    if seconds < 1 {
        return AiNpcSayNow();
    }
    return seconds;
}

// Unknown is not Failed. Resolved tickets are kept in a bounded ring, so "I no longer know" is
// a normal answer to an old ticket and must stay distinguishable from "it did not work".
public func AiNpcTicketState(ticket: Int32) -> Int32 {
    let registry = AiNpcGetClientRegistry();
    if !IsDefined(registry) {
        return AiNpcTicketUnknown();
    }
    return registry.StateOf(ticket);
}

// Why it failed, in plain text; empty for anything not failed. Failed on its own cannot be
// debugged: three causes, three fixes, and no other way to tell them apart.
public func AiNpcTicketReason(ticket: Int32) -> String {
    let registry = AiNpcGetClientRegistry();
    if !IsDefined(registry) {
        return "";
    }
    return registry.ReasonOf(ticket);
}

/// Opening a conversation ///

// A code rather than a Bool: already there is success, not driven is a configuration mistake,
// floor held is a reason to wait.
public func AiNpcOpenOk() -> Int32 {
    return 10;
}

public func AiNpcOpenAlreadyThere() -> Int32 {
    return 11;
}

public func AiNpcOpenNotDriven() -> Int32 {
    return 12;
}

public func AiNpcOpenPhoneUnavailable() -> Int32 {
    return 13;
}

public func AiNpcOpenFloorHeld() -> Int32 {
    return 14;
}

/// Placing a holo call ///

// A call is not a thread opened out loud, and the codes say so: it can be refused for reasons a
// thread has no equivalent of -- somebody is already on the line, and V is somewhere a call
// cannot reach.
//
// Separate from the Open* codes on purpose. Reusing them would make "already there" mean two
// things, and a caller branching on it would treat a call in progress as a success.
public func AiNpcCallOk() -> Int32 {
    return 30;
}

// A call is already up, with this contact or another. Who is on it: AiNpcCharacterOnCall.
public func AiNpcCallBusy() -> Int32 {
    return 31;
}

// This mod does not drive that contact, or nothing does. A configuration mistake, not a state
// to wait out.
public func AiNpcCallNotDriven() -> Int32 {
    return 32;
}

// No save loaded, or ai_npc not up yet. Transient, like its Write equivalent.
public func AiNpcCallNoSession() -> Int32 {
    return 33;
}

// Empty contact id -- a call site to correct.
public func AiNpcCallEmpty() -> Int32 {
    return 34;
}

/// Writing into a thread ///

// One vocabulary for CharacterWrote and PlayerWrote: the same contract with the other speaker,
// failing the same three ways. A Bool collapsed a held floor -- temporary, with a defined
// moment to retry -- into the same answer as a misspelt contact id.
//
// There is deliberately no "not driven": a thread can be seeded for a contact ai_npc does not
// drive yet, which is the normal way to hand a conversation its starting point.
// AiNpcDrivesCharacter is a separate question.
public func AiNpcWriteOk() -> Int32 {
    return 20;
}

// The only refusal worth retrying. AiNpcFloorHeldBy says who; OnFloorChanged is when.
public func AiNpcWriteFloorHeld() -> Int32 {
    return 21;
}

// No save loaded, or ai_npc not up yet. Transient: try again at the next attach rather than
// latching "ai_npc is missing". AiNpcIsReady answers the same question without writing.
public func AiNpcWriteNoSession() -> Int32 {
    return 22;
}

// Empty contact id or empty text -- a call site to correct, not a state to wait out.
public func AiNpcWriteEmpty() -> Int32 {
    return 23;
}

/// The client ///

// Never null, and the same mod id always answers with an equivalent handle: the client carries
// no state, so there is nothing to cache and nothing to keep alive.
//
// Outside a session the claim cannot be recorded and the handle does nothing: there is no
// conversation to affect, and queueing for a session that does not exist would move the
// failure somewhere harder to see.
public func AiNpcOpenClient(modId: String) -> ref<AiNpcClient> {
    let registry = AiNpcGetClientRegistry();
    if IsDefined(registry) {
        registry.Claim(modId);
    }

    let client = new AiNpcClient();
    client.Bind(modId);
    return client;
}

// Runs the handler as soon as ai_npc can answer, or immediately on this stack when it already
// can, so the two cases are indistinguishable to the caller.
//
// Not queued when ai_npc is unreachable: outside a session there is nothing to become ready,
// and a mod re-calls this at its next attach. A handler registry would have to survive exactly
// as long as the thing it waits for, which is a lifetime nobody has.
public func AiNpcWhenReady(modId: String, handler: ref<AiNpcReadyHandler>) -> Void {
    if !IsDefined(handler) {
        return;
    }
    if AiNpcIsReady() {
        handler.OnAiNpcReady(AiNpcOpenClient(modId));
    }
}

public class AiNpcClient extends IScriptable {

    private let m_modId: String;

    // Called by AiNpcOpenClient and nothing else. Not a constructor argument because redscript
    // has none, and not public because a handle that can rename itself has no attribution.
    public func Bind(modId: String) -> Void {
        this.m_modId = modId;
    }

    public func GetModId() -> String {
        return this.m_modId;
    }

    /// Statements: what the character knows ///

    // Something your systems know and the conversation cannot hear. V never reads it. Written
    // as a plain sentence addressed to the character, in your own words: it reaches the model
    // untouched.
    //
    //     AiNpcUntilNextReply   spent on the next generation, then dropped; does not survive a
    //                           save. For what is true at this instant. Keyed by your mod, so
    //                           a second mod seeding the same contact adds rather than erases.
    //     AiNpcUntilForever     recorded in the contact's memory, repeated on every message,
    //                           survives everything. For what happened.
    //
    // Forever is a different thing, not a longer one: the memory block states its precedence
    // over the character sheet, so a fact recorded there fixes a contradiction where <now>
    // can only add to one.
    //
    // Returns a ticket, not a Bool: a contact with no conversation yet is normal to seed, and
    // it settles when that contact next speaks. 0 means refused outright, with nothing to query.
    //
    // Idempotent on exact text, so a reload or a listener firing twice leaves one line. Two
    // wordings of one event are two facts -- keep the sentence stable.
    public func CharacterKnows(contactId: String, text: String, opt until: Int32) -> Int32 {
        return AiNpcClientCharacterKnows(this.m_modId, contactId, text, until);
    }

    /// Statements: what was written ///

    // The character wrote this, and V reads it in the thread. Past tense, and load-bearing:
    // nothing is sent -- no notification, no phone screen, no opening, no reply generated. Your
    // mod already decided how a message reaches the player; this puts the same line where the
    // model and the chat both see it. Write here first, then notify.
    //
    // Answers with an AiNpcWrite* code, and the three refusals are three different jobs: wait
    // for the floor, retry at the next attach, or fix the call. A write nobody checked is how a
    // mod notifies the player about a message that was never filed.
    public func CharacterWrote(contactId: String, text: String) -> Int32 {
        return AiNpcClientWrote(this.m_modId, contactId, text, false);
    }

    // V wrote this. Same contract, other speaker, same codes.
    public func PlayerWrote(contactId: String, text: String) -> Int32 {
        return AiNpcClientWrote(this.m_modId, contactId, text, true);
    }

    // The character sends this text now, as a message V receives: filed as CharacterWrote
    // files it, then delivered the way a generated reply is -- painted if the thread is open,
    // notified otherwise. The words are yours; how the message reaches V is ai_npc's. Same
    // codes as CharacterWrote.
    public func CharacterSends(contactId: String, text: String) -> Int32 {
        return AiNpcClientSends(this.m_modId, contactId, text);
    }

    /// Statements: what the character wants to say ///

    // The character has a reason to write to V unprompted. ai_npc turns it into a message in
    // her own voice, files it, and pushes an SMS notification when the phone is closed.
    //
    // A reason, not a line: CharacterWrote takes text, and the text is then yours -- one
    // language, a voice that is not the character's. Right for an SMS your quest wrote, wrong
    // for "she noticed V has gone quiet", which the model writes better and in the player's
    // language for nothing. State the reason in your own words, addressed to the character.
    //
    //     client.CharacterWantsToSay("panam",
    //         "V has not been in touch for three days. You are worried, so you ask whether
    //          everything is all right.");
    //
    // Present tense: nothing is recorded at this call. Whether it becomes a message, and when,
    // comes back on the ticket rather than on the return.
    //
    // When is the caller's, and that is not a gap: a mod that wants a character to notice a
    // silence knows that silence better, since AiNpcReadConversation carries gameTimeSeconds on
    // every message. ai_npc keeps only the guards that are not a mod's to hold -- the floor, one
    // generation at a time, the player's setting, and one minute of play between two unprompted
    // messages on one contact. The debounce is not a schedule: it says how fast anything may
    // speak, never when a character should.
    //
    // It can act, not only speak: the reason lands where V's message would, so the command
    // vocabulary fires from it. A birthday reason produced an unasked-for eddie transfer. It
    // spends a request, it can move money under the conversation cap, and it can trigger any
    // command this contact carries. State reasons you would be happy for her to act on.
    //
    // Refusals:
    //
    //     another mod holds the floor    the scene in progress owns the thread
    //     a generation already running   one at a time, and the lane is one for the session
    //     she wrote first a minute ago   the debounce, so a looping trigger cannot burst
    //     the queue is full              refused at once, whatever window was asked for
    //     unprompted turns turned off    Refused, not Failed -- the player's call
    //     ai_npc does not drive this     AiNpcDrivesCharacter is the question
    //     the day's token budget spent   the player's ceiling, and it counts this too
    //     empty contact id or reason     0, and there is nothing to query
    //
    // The first four are what `policy` is for. The last three never clear while the session runs.
    //
    // A contact that answers from its own script is not consulted here: GetScriptedReply asks
    // what it answers to a message, and there is no message. CharacterWrote is the call for one
    // of those -- you own its text, and it costs no request.
    //
    // Have a fallback, and hold it yourself. Most rows above are ordinary conditions, so a
    // moment your content depends on will sometimes not be written, with nothing on screen to
    // say why -- deliberate, since nobody is waiting on a message they never asked for. Watch
    // the ticket from OnTicketSettled and write your own line with CharacterWrote on Failed
    // only: Cancelled is your own withdrawal, and Refused is the player having said no.
    // AiNpcMayWriteFirst answers that before you arm a trigger.
    //
    // `intent` answers a different question from `reason`: the reason is what just happened, the
    // intent is what she is trying to do while she writes about it. It replaces <intent> for
    // this one generation and nothing else. Left empty she writes under what she always wants,
    // or under the intent the tracked mission gave her -- which is wrong exactly when that
    // mission says something like "nothing else matters until Saul is out".
    //
    // `policy` decides what happens when the lane is not free. AiNpcSayNow is now or never;
    // AiNpcSayWithin(n) queues the reason and fails it if there is still no room within n
    // seconds of play.
    //
    //     client.CharacterWantsToSay("panam", reason, "", AiNpcSayWithin(180));
    //
    // Choose by the reason you wrote, not by how much you want it delivered. "She has just seen
    // V walk past" is only true now; "she has been worried since this morning" survives a wait.
    public func CharacterWantsToSay(contactId: String, reason: String, opt intent: String,
                                    opt policy: Int32) -> Int32 {
        return AiNpcClientWantsToSay(this.m_modId, contactId, reason, intent, policy);
    }

    // Withdraws a reason still waiting in the queue, because the moment it described has passed.
    // False for cancelling twice, for somebody else's ticket, and for one whose request has
    // already gone out -- a generation in flight cannot be recalled.
    //
    // The ticket settles as Cancelled, not Failed. Your fallback should not fire for this.
    public func CancelWantsToSay(ticket: Int32) -> Bool {
        return AiNpcClientCancelWantsToSay(this.m_modId, ticket);
    }

    /// Orders: the thread ///

    // Selecting and opening are one call: done by hand there is a window in which the dialer
    // reselects whatever it points at, and the chat shows a different conversation.
    //
    // Idempotent, and not out of politeness: building the chat twice stacks two into the
    // container and the widgets corrupt until the phone is closed. A caller wired to a button in
    // someone else's screen cannot see the chat is already open, so the guard lives here.
    public func OpenConversation(contactId: String) -> Int32 {
        return AiNpcClientOpenConversation(this.m_modId, contactId);
    }

    /// Orders: the call ///

    // Rings this character's holo, as the game's own call would. Answering is the player's:
    // this places the call, it does not connect it.
    //
    // A separate order from OpenConversation, and the distinction is the whole of
    // docs\PLAN_HOLO_CHANNEL.md -- what is said on a call must not appear as a written message,
    // while the memory stays shared. A caller that wants the thread wants the other function.
    //
    // The voice is prepared while it rings, which is the reason a call is placed rather than
    // connected straight away: cutting the reference out of the player's archives and cloning
    // it costs about seven seconds, and the ring is the only moment nobody is waiting.
    public func CallContact(contactId: String) -> Int32 {
        return AiNpcClientCallContact(this.m_modId, contactId);
    }

    // Erases a thread, entirely and irreversibly. Refused for a contact this mod did not
    // declare: not securable, since a modId is self-declared, but it covers the unrecoverable
    // case -- a mod wiping a vanilla character's history. Every call is logged with its author.
    public func ForgetConversation(contactId: String) -> Bool {
        return AiNpcClientForgetConversation(this.m_modId, contactId);
    }

    // Exclusive control of a thread: while held, only this mod's GetScriptedReply is consulted,
    // no model is asked, and nobody else may write into it. Not the same question as a
    // provider's IsAvailable, which says whether a contact is reachable in the fiction at all --
    // conflated, two mods could both suspend a contact without either knowing.
    //
    // A lease, not a lock: maxSeconds bounds it (0 takes the default) and it expires lazily on
    // read, never on a DelayCallback, so a mod that crashes or is uninstalled mid-scene does not
    // hold a character for the rest of the playthrough. Re-taking your own floor extends it.
    //
    // False means somebody else has it. AiNpcFloorHolder says who; OnFloorAvailable is when.
    public func TakeFloor(contactId: String, opt maxSeconds: Float) -> Bool {
        return AiNpcTakeFloor(contactId, this.m_modId, maxSeconds);
    }

    // Release explicitly at the end of a scene rather than letting the lease lapse: the lease is
    // a backstop for a mod that stopped, and an expiry is reported as one.
    public func ReleaseFloor(contactId: String) -> Bool {
        return AiNpcReleaseFloor(contactId, this.m_modId);
    }

    /// Orders: the cast ///

    // Declares a character of yours. One per contactId, first claim wins, and a refusal is not
    // resolvable by ordering: two mods claiming one contact disagree about something no merge
    // rule covers.
    //
    // Do not declare a vanilla character. Redefining one of ai_npc's own is the user's call,
    // through characters.builtin.json. To give Rogue something new, extend her.
    public func RegisterCharacter(provider: ref<AiNpcContactProvider>) -> Bool {
        return AiNpcRegisterContact(provider);
    }

    // The conversation is untouched -- it belongs to the journal, not to the provider -- so
    // registering the same id again resumes where it left off.
    public func UnregisterCharacter(contactId: String) -> Bool {
        return AiNpcUnregisterContact(contactId);
    }

    // Adds to characters you do not own. N per contact, no conflict, no ordering to arrange; see
    // AiNpcCharacterExtension for what may be added.
    //
    // Idempotent by subject, so re-registering every session -- which every mod must do, since
    // nothing here survives a save load -- needs no state of its own.
    public func RegisterExtension(ext: ref<AiNpcCharacterExtension>) -> Bool {
        let registry = AiNpcGetExtensionRegistry();
        return IsDefined(registry) && registry.RegisterExtension(this.m_modId, ext);
    }

    public func UnregisterExtension(subject: String) -> Bool {
        let registry = AiNpcGetExtensionRegistry();
        return IsDefined(registry) && registry.UnregisterExtension(this.m_modId, subject);
    }

    /// Orders: what characters can DO ///

    // Declares a command. One call carries both halves of it: `pattern` is what the model is
    // shown AND what the dispatcher matches, so a command cannot be advertised without being
    // implemented, nor implemented without being advertised.
    //
    //     AddAction("[ACTION:CALL_DELAMAIN]", "You call a Delamain for V when...",
    //               new DelamainHandler(), AiNpcEveryContactTag())
    //
    // Slots are written {like_this} and each fills one colon-separated field:
    // "[ACTION:TRICK:{place}:{hour}:{price}]" hands the handler three strings, always three,
    // never empty. Getting the count wrong is then a fumble the repair pass can fix rather
    // than an index a consumer walks off the end of.
    //
    // `scopeTag` says who may use it, and there is NO DEFAULT. An omission must narrow reach,
    // never widen it: a permissive default is found by the player, in play, on the day the
    // model happens to emit the tag. Name a tag of your own for your own characters,
    // AiNpcContactTagFor(id) for one, or AiNpcEveryContactTag() for everybody -- which is a
    // decision, spelled out, and listed in the load report so a player can read who granted
    // what to whom.
    //
    // Idempotent by verb: re-declaring "[ACTION:TRICK:...]" replaces your earlier one, so this
    // can be called unconditionally on every attach.
    public func AddAction(pattern: String, prompt: String, handler: ref<AiNpcActionHandler>,
                          scopeTag: String,
                          opt parameters: array<ref<AiNpcActionParam>>) -> Bool {
        let registry = AiNpcGetActionRegistry();
        return IsDefined(registry)
            && registry.RegisterAction(this.m_modId, pattern, prompt, handler, scopeTag,
                                       parameters);
    }

    // By verb -- "TRICK" for "[ACTION:TRICK:{place}:{hour}]" -- because that is the half of the
    // id you chose.
    public func RemoveAction(verb: String) -> Bool {
        let registry = AiNpcGetActionRegistry();
        return IsDefined(registry) && registry.UnregisterAction(this.m_modId, verb);
    }

    // Takes a command away from the characters carrying `scopeTag`. `head` is the literal run
    // before the first slot -- AiNpcTransferHead() for the eddie transfer.
    //
    // ONE-WAY. Nobody can grant back what you removed, which is what makes it safe for a mod
    // that has taken responsibility for a character's economy: whoever registers afterwards
    // cannot override you. Use it when your own mod already does the thing, so the model is
    // never taught a command it would only be refused.
    public func SuppressAction(head: String, scopeTag: String) -> Bool {
        let registry = AiNpcGetActionRegistry();
        return IsDefined(registry)
            && registry.SuppressAction(this.m_modId, head, scopeTag);
    }

    public func UnsuppressAction(head: String, scopeTag: String) -> Bool {
        let registry = AiNpcGetActionRegistry();
        return IsDefined(registry)
            && registry.UnsuppressAction(this.m_modId, head, scopeTag);
    }

    // Says that a character IS something: a client, a fixer, one of yours. Additive and
    // idempotent, and it works on characters you did not declare -- which is the point, since
    // it lets a config file grant somebody else's command to somebody else's character without
    // either mod knowing the other.
    //
    // Tags never take anything away; that is SuppressAction's job. So a tag is safe to add and
    // safe to leave, and leaving one out is never how reach is removed.
    public func TagCharacter(contactId: String, tag: String) -> Bool {
        let store = AiNpcGetContactTagStore();
        return IsDefined(store) && store.Assign(this.m_modId, contactId, tag);
    }

    // Retracts your own assignment. Another mod's identical tag stands: that was a second
    // author agreeing, not the same author repeating himself.
    public func UntagCharacter(contactId: String, tag: String) -> Bool {
        let store = AiNpcGetContactTagStore();
        return IsDefined(store) && store.Retract(this.m_modId, contactId, tag);
    }

    /// Orders: the world ///

    // Adds to what every character knows about Night City -- a fact about the place rather than
    // about anyone in it. Additive to the built-in text and to prompts.json, concatenated in
    // full-id order, idempotent by subject.
    //
    // Not an extension with no contact list: an extension speaks into <now>, which is for what
    // is true now and is budgeted per message. A standing fact about the city is stated once and
    // competes with nobody's account of the moment.
    //
    // False means not stated -- over budget, or no session yet.
    public func RegisterWorldKnowledge(subject: String, text: String) -> Bool {
        return AiNpcRegisterWorldKnowledge(this.m_modId, subject, text);
    }

    public func UnregisterWorldKnowledge(subject: String) -> Bool {
        return AiNpcUnregisterWorldKnowledge(this.m_modId, subject);
    }

    // The same, addressed to one character: what your mod adds to who that person is. It joins
    // the end of their bio in <character>.
    //
    // The additive half of a bio, and the only one. AiNpcCharacterExtension has no GetBio --
    // two bios concatenated describe nobody -- but a bio and an addition to it are not two bios:
    // whoever declared the character keeps theirs exactly as written.
    //
    // For what is durably true of them, not for the moment; the moment is an extension's
    // GetLiveContext, rebuilt per message and budgeted. Idempotent by subject.
    public func CharacterAlsoIs(contactId: String, subject: String, text: String) -> Bool {
        return AiNpcRegisterCharacterAddition(this.m_modId, contactId, subject, text);
    }

    public func CharacterIsNoLonger(contactId: String, subject: String) -> Bool {
        return AiNpcUnregisterCharacterAddition(this.m_modId, contactId, subject);
    }

    // Watches without taking part. Same idempotence by subject.
    public func RegisterListener(listener: ref<AiNpcConversationListener>) -> Bool {
        let registry = AiNpcGetExtensionRegistry();
        return IsDefined(registry) && registry.RegisterListener(this.m_modId, listener);
    }

    public func UnregisterListener(subject: String) -> Bool {
        let registry = AiNpcGetExtensionRegistry();
        return IsDefined(registry) && registry.UnregisterListener(this.m_modId, subject);
    }

    // Everything this mod registered, in one call: extensions, listeners, held floors, and any
    // transient context or deferred statement still waiting. A mod whose content ends
    // mid-playthrough is the normal case.
    public func UnregisterAll() -> Void {
        AiNpcClientUnregisterAll(this.m_modId);
    }

    /// Accounting ///

    // How much this mod may still add to a contact's transient context before the clamp bites,
    // in characters. A budget nobody can read surfaces as "my mod misbehaves when others are
    // installed".
    public func ContextBudgetLeft(contactId: String) -> Int32 {
        return AiNpcPendingContextBudgetLeft(contactId, this.m_modId);
    }

    /// Files ///

    // This mod's file name inside the shared storage: "mod.<modId>.<name>.json".
    //
    // Names rather than opens. RedFileSystem allows one claimant per storage name and does not
    // fail softly: a second GetStorage("AiNpc") revokes the storage for the session, and the mod
    // that loses is ai_npc -- no journal, and every request returns [NO SIGNAL: HTTP 0]. The
    // only trace is red4ext\logs\redfilesystem-*.log. The handle comes from AiNpcSharedStorage,
    // already open.
    public func FileName(name: String) -> String {
        return AiNpcModFileName(this.m_modId, name);
    }
}
