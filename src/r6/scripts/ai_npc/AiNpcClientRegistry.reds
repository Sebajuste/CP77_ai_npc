// Who is allowed to write, and what happened when they did. The client is a handle carrying a
// mod id, and every method on it is one delegating line into this file: a consumer taking
// ai_npc optionally mirrors the public half behind @if, so logic there is logic its degraded
// half would have to reimplement identically.
//
// A claim buys uniqueness and nothing else. First claim on a mod id wins, so an attribution
// is never ambiguous; nothing stops a mod claiming a name that is not its own, because this
// is a collision model, not a threat model. It is what makes per-mod budgets, retraction and
// "who put that in Rogue's history" answerable at all.
//
// A permanent fact can fail after the call returns -- there may be no conversation to hang it
// on -- so CharacterKnows answers with a ticket rather than a Bool it would have to guess.
// Resolved tickets live in a bounded ring, since a talkative mod would leave hundreds behind,
// and falling out of it answers Unknown: a mod reading that as Failed announces an invented
// failure to the player.

module AiNpc

/// Deferred work ///

// A statement that could not be applied yet, kept until it can. Only undated, idempotent
// things are ever queued: a permanent fact says what happened, not when it is being said. A
// message, an opening, a floor claim and a transient context line all carry a moment, and
// replaying those at an unpredictable one turns a visible failure into a timing bug.
//
// AiNpcSpeechQueue is the one stated exception, and a separate queue: what makes an unprompted
// message's moment predictable again is the window the mod has to name for it.
public class AiNpcDeferredFact {
    public let modId: String;
    public let contactId: String;
    public let text: String;
    public let ticket: Int32;
}

public class AiNpcClientRegistry extends ScriptableSystem {

    private let m_claims: array<String>;
    private let m_deferred: array<ref<AiNpcDeferredFact>>;

    // Pure, so the ring and the two emptinesses can be asserted without a session. What is
    // left here is the announcing, which cannot be.
    private let m_tickets: ref<AiNpcTicketBook>;

    // Held here because a mod's claim, its verdicts and what it is waiting on are one
    // lifetime: withdrawing clears all three in one call.
    private let m_speech: ref<AiNpcSpeechQueue>;

    private func OnAttach() -> Void {
        this.m_tickets = new AiNpcTicketBook();
        this.m_speech = new AiNpcSpeechQueue();
    }

    public func SpeechQueue() -> ref<AiNpcSpeechQueue> {
        return this.m_speech;
    }

    public static func Get(game: GameInstance) -> ref<AiNpcClientRegistry> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(NameOf<AiNpcClientRegistry>()) as AiNpcClientRegistry;
    }

    /// Claims ///

    // True when this mod id is free or already this caller's. No way to tell those apart and
    // no reason to: opening a client twice is how a mod avoids storing the handle.
    public func Claim(modId: String) -> Bool {
        if Equals(StrLen(modId), 0) {
            return false;
        }
        if !ArrayContains(this.m_claims, modId) {
            ArrayPush(this.m_claims, modId);
            AiNpcLog(s"Client '\(modId)' opened.");
        }
        return true;
    }

    /// Tickets ///

    public func IssueResolved(modId: String, contactId: String, state: Int32, reason: String) -> Int32 {
        let ticket = this.m_tickets.Issue(modId, contactId, state, reason);
        // Anything but Pending is a verdict, Cancelled and Refused included. Enumerating the
        // states that count is how the two added for CharacterWantsToSay would have shipped
        // announcing nothing.
        if AiNpcTicketIsSettled(state) {
            AiNpcPublishFactRecorded(contactId, ticket, state, reason);
        }
        return ticket;
    }

    // Announced only when the book still knows the ticket: a verdict naming an id that has
    // fallen out of the ring is one no listener could look up afterwards.
    public func Resolve(ticket: Int32, state: Int32, reason: String) -> Void {
        let contactId = this.m_tickets.ContactOf(ticket);
        if this.m_tickets.Resolve(ticket, state, reason) {
            AiNpcPublishFactRecorded(contactId, ticket, state, reason);
        }
    }

    public func StateOf(ticket: Int32) -> Int32 {
        return this.m_tickets.StateOf(ticket);
    }

    public func ReasonOf(ticket: Int32) -> String {
        return this.m_tickets.ReasonOf(ticket);
    }

    /// Deferral ///

    public func Defer(modId: String, contactId: String, text: String, ticket: Int32) -> Void {
        let pending = new AiNpcDeferredFact();
        pending.modId = modId;
        pending.contactId = contactId;
        pending.text = text;
        pending.ticket = ticket;
        ArrayPush(this.m_deferred, pending);
    }

    // Called when a conversation for that contact is certainly present -- the moment its prompt
    // is built -- rather than from a hook on the store: one array walk at a point the code
    // already reaches beats a notification path that has to stay correct forever.
    public func Flush(contactId: String) -> Void {
        let i = ArraySize(this.m_deferred) - 1;
        while i >= 0 {
            if Equals(this.m_deferred[i].contactId, contactId) {
                let pending = this.m_deferred[i];
                if AiNpcRecordFact(contactId, pending.text) {
                    ArrayErase(this.m_deferred, i);
                    this.Resolve(pending.ticket, AiNpcTicketDone(), "");
                }
            }
            i -= 1;
        }
    }

    public func ForgetDeferredFor(modId: String) -> Void {
        let i = ArraySize(this.m_deferred) - 1;
        while i >= 0 {
            if Equals(this.m_deferred[i].modId, modId) {
                ArrayErase(this.m_deferred, i);
            }
            i -= 1;
        }
    }

    public func CountDeferred() -> Int32 {
        return ArraySize(this.m_deferred);
    }
}

/// Access ///

public func AiNpcGetClientRegistry() -> ref<AiNpcClientRegistry> {
    return AiNpcClientRegistry.Get(GetGameInstance());
}

// AiNpcOpenClient and AiNpcWhenReady are the two doors a consumer comes through, so they are
// declared in api\AiNpcClient.reds with the handle they hand out. What is left here is the
// bookkeeping behind them.

/// The writes ///

public func AiNpcClientCharacterKnows(modId: String, contactId: String, text: String, until: Int32) -> Int32 {
    if Equals(StrLen(contactId), 0) || Equals(StrLen(text), 0) {
        return 0;
    }

    let registry = AiNpcGetClientRegistry();
    if !IsDefined(registry) {
        return 0;
    }

    // The one crossing the disjoint ranges cannot catch: bounds are 0 and 1, so a ticket state
    // passed here reads as a bound rather than matching nothing. Anything outside the two is
    // treated as NextReply, the safe direction, and logged -- it is a caller's bug, and the
    // alternative is a mod whose facts quietly stop surviving a save.
    if NotEquals(until, AiNpcUntilNextReply()) && NotEquals(until, AiNpcUntilForever()) {
        AiNpcLog(s"'\(modId)' passed \(until) as a bound for '\(contactId)'. Not one of AiNpcUntilNextReply/AiNpcUntilForever; treated as NextReply.");
    }

    // A line waiting for the next generation, keyed by its author so a second mod seeding for
    // the same contact adds to it instead of erasing it.
    if NotEquals(until, AiNpcUntilForever()) {
        if !AiNpcSeedContext(contactId, text, modId) {
            return registry.IssueResolved(modId, contactId, AiNpcTicketFailed(), "no session");
        }
        return registry.IssueResolved(modId, contactId, AiNpcTicketDone(), "");
    }

    if AiNpcRecordFact(contactId, text) {
        return registry.IssueResolved(modId, contactId, AiNpcTicketDone(), "");
    }

    // Three ways it can fail, because they need three different fixes and a mod author has no
    // other way to tell them apart.
    if !AiNpcMemoryEnabled() {
        return registry.IssueResolved(modId, contactId, AiNpcTicketFailed(), "memory is turned off in the settings");
    }

    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) && !provider.AllowsMemory() {
        return registry.IssueResolved(modId, contactId, AiNpcTicketFailed(), "this contact keeps no memory");
    }

    // No conversation yet: the one genuinely temporary failure, so it waits rather than
    // reports. The fact is undated, and seeding ahead of the first message is the normal use.
    let ticket = registry.IssueResolved(modId, contactId, AiNpcTicketPending(), "");
    registry.Defer(modId, contactId, text, ticket);
    return ticket;
}

// Translating a refusal into the client's vocabulary is this function's job, which is why the
// emptiness check is restated here rather than left to AiNpcSeedMessage: seeding answers with
// a Bool because one failure is all its own callers can act on, and a mod needs three. Once
// the empty case is filtered, the only false left from seeding is a missing store.
//
// Emptiness first, because asking who holds the floor on "" is a meaningless question that
// would still have been answered.
public func AiNpcClientWrote(modId: String, contactId: String, text: String, fromPlayer: Bool) -> Int32 {
    if Equals(StrLen(contactId), 0) || Equals(StrLen(text), 0) {
        return AiNpcWriteEmpty();
    }

    if !AiNpcMayWriteTo(contactId, modId) {
        AiNpcLog(s"'\(modId)' may not write to '\(contactId)': '\(AiNpcFloorHolder(contactId))' holds the floor.");
        return AiNpcWriteFloorHeld();
    }

    // The announcement happens inside, at the single point a message enters a thread, so this
    // publishes none of its own.
    if !AiNpcSeedMessage(contactId, text, fromPlayer, modId) {
        return AiNpcWriteNoSession();
    }
    return AiNpcWriteOk();
}

// The character writes first, because this mod gave her a reason to. The contract and the
// refusals live on AiNpcClient.CharacterWantsToSay; what is here is the split between what can
// be answered without the speaking lane and what cannot.
//
// This answers only what it can answer alone: nonsense arguments, and a contact ai_npc does
// not drive. Everything else is state the lane holds, and asking it twice is how two answers
// to one question disagree. The lane resolves the ticket issued here.
//
// The ticket is Pending rather than Done because this is the first genuinely asynchronous one:
// a message has to be generated, delivered and filed before "she wrote" is true. It settles in
// HandleMessage or on the failure path, both of which read it off the generation.
public func AiNpcClientWantsToSay(modId: String, contactId: String, reason: String,
                                  opt intent: String, opt policy: Int32) -> Int32 {
    if Equals(StrLen(contactId), 0) || Equals(StrLen(reason), 0) {
        return 0;
    }

    let registry = AiNpcGetClientRegistry();
    if !IsDefined(registry) {
        return 0;
    }

    // The session first: outside one every contact reads as undrivable, so asking about the
    // contact first hands back "ai_npc does not drive this contact" for one it drives perfectly
    // well, and sends a mod author looking at their contact id.
    let http = GetAiNpcHttpSystem();
    if !IsDefined(http) {
        return registry.IssueResolved(modId, contactId, AiNpcTicketFailed(), "no session");
    }

    // Asked here rather than in the lane: it looks like lane state and is not -- a settings
    // field readable from anywhere, unchanging while this call runs, and no window will lift
    // it. So a mod hears it synchronously rather than on a Pending that resolves a frame later
    // for a reason knowable at the call.
    if !AiNpcUnpromptedEnabled() {
        return registry.IssueResolved(modId, contactId, AiNpcTicketRefused(),
            "the player turned off characters writing first");
    }

    // Not "is this contact known" but "can ai_npc hold a conversation for it right now": a
    // provider whose IsAvailable() says no cannot be written to, and a mod has to hear so
    // rather than wait on a ticket that will never settle.
    if !AiNpcIsContactSupported(contactId) {
        return registry.IssueResolved(modId, contactId, AiNpcTicketFailed(),
            "ai_npc does not drive this contact");
    }

    let ticket = registry.IssueResolved(modId, contactId, AiNpcTicketPending(), "");

    // The window, or 0 for now-or-never. Computed here so the lane is handed an instant rather
    // than a duration, which re-read further down would restart from wherever it was read.
    let expiresAt = 0.0;
    if policy > 0 {
        expiresAt = AiNpcSpeechWindowEndsAt(AiNpcSpeechNow(), policy);
    }

    http.TriggerUnpromptedRequest(contactId, modId, reason, ticket, intent, expiresAt);
    return ticket;
}

// Cancelled rather than Failed, which is the whole point: a mod withdraws because the moment
// passed, and Failed is the verdict its fallback fires on. False when there was nothing to
// withdraw -- already sent, already cancelled, or never this mod's.
public func AiNpcClientCancelWantsToSay(modId: String, ticket: Int32) -> Bool {
    if Equals(ticket, 0) {
        return false;
    }

    let queue = AiNpcGetSpeechQueue();
    if !IsDefined(queue) {
        return false;
    }

    let entry = queue.TakeOwned(modId, ticket);
    if !IsDefined(entry) {
        return false;
    }

    AiNpcLog(s"'\(modId)' withdrew what it had asked '\(entry.contactId)' to say.");
    AiNpcResolveClientTicket(ticket, AiNpcTicketCancelled(), "withdrawn by the mod that asked");
    return true;
}

// A free function so the lane need not know the registry exists, or reach for it on four paths
// and null-check each. Ticket 0 is accepted and ignored: it is what a generation the player
// asked for carries.
func AiNpcResolveClientTicket(ticket: Int32, state: Int32, reason: String) -> Void {
    if Equals(ticket, 0) {
        return;
    }

    let registry = AiNpcGetClientRegistry();
    if IsDefined(registry) {
        registry.Resolve(ticket, state, reason);
    }
}

// The floor is checked here rather than in AiNpcOpenChatOn, because it is a question about the
// caller and the open path has other callers -- the player's own key binding among them, which
// no lease should be able to refuse.
public func AiNpcClientOpenConversation(modId: String, contactId: String) -> Int32 {
    if !AiNpcMayWriteTo(contactId, modId) {
        return AiNpcOpenFloorHeld();
    }
    return AiNpcOpenChatOn(contactId);
}

// Places a holo call. The state machine decides; this only translates its refusals into the
// vocabulary the contract publishes, because a caller cannot branch on a sentence.
public func AiNpcClientCallContact(modId: String, contactId: String) -> Int32 {
    if Equals(StrLen(contactId), 0) {
        return AiNpcCallEmpty();
    }

    let calls = AiNpcCallSystem.Get();
    if !IsDefined(calls) {
        return AiNpcCallNoSession();
    }
    if !AiNpcIsContactSupported(contactId) {
        return AiNpcCallNotDriven();
    }
    if !AiNpcCallIsOver(calls.State()) && NotEquals(calls.State(), AiNpcCallState.Idle) {
        return AiNpcCallBusy();
    }

    AiNpcLog(s"'\(modId)' placed a holo call to '\(contactId)'.");
    calls.Dial(contactId);
    return AiNpcCallOk();
}

// Refused unless this mod declared the contact. Not securable, since a mod id is
// self-declared, but it prevents a mod wiping a vanilla character's history or another mod's
// contact, where the loss is unrecoverable. Every call is logged with its author, refused or
// not, because this is the one irreversible thing in the API.
public func AiNpcClientForgetConversation(modId: String, contactId: String) -> Bool {
    if AiNpcIsBuiltinContactId(contactId) {
        FTLogError(s"[ai_npc]: '\(modId)' tried to erase the thread of built-in contact '\(contactId)'. Refused.");
        return false;
    }

    AiNpcLog(s"'\(modId)' erased the thread of '\(contactId)'.");
    return AiNpcResetConversation(contactId);
}

/// Withdrawing ///

public func AiNpcClientUnregisterAll(modId: String) -> Void {
    let extensions = AiNpcGetExtensionRegistry();
    if IsDefined(extensions) {
        extensions.UnregisterAllFor(modId);
    }

    let world = AiNpcGetWorldKnowledgeRegistry();
    if IsDefined(world) {
        world.UnregisterAllFor(modId);
    }

    let floors = AiNpcGetFloorRegistry();
    if IsDefined(floors) {
        floors.ReleaseAllFor(modId);
    }

    let clients = AiNpcGetClientRegistry();
    if IsDefined(clients) {
        clients.ForgetDeferredFor(modId);

        // Settled, not silently dropped: a Pending nobody will ever answer is the one outcome
        // the ticket vocabulary exists to prevent.
        let queue = clients.SpeechQueue();
        if IsDefined(queue) {
            let dropped = queue.TakeAllFor(modId);
            let i = 0;
            let count = ArraySize(dropped);
            while i < count {
                AiNpcResolveClientTicket(dropped[i].ticket, AiNpcTicketCancelled(),
                    "the mod that asked withdrew from the session");
                i += 1;
            }
        }
    }

    AiNpcForgetPendingContextFrom(modId);

    AiNpcLog(s"Client '\(modId)' withdrew everything it had registered.");
}

/// Files ///

// The prefix is not decoration: the config loader globs characters.*.json and facts.*.json, so
// a mod dropping a file that matches gets it parsed and reported as broken.
public func AiNpcModFileName(modId: String, name: String) -> String {
    return "mod." + modId + "." + name + ".json";
}

/// Diagnostics ///

// Everything acting on one contact, in one string. With N contributors on one character, "my
// action does not fire" has to become one line to read rather than an evening of guessing
// which mod is answering.
public func AiNpcExplainContact(contactId: String) -> String {
    let report = s"contact '\(contactId)'\n";
    report += s"  drivable: \(AiNpcIsContactSupported(contactId))\n";
    report += s"  built-in: \(AiNpcIsBuiltinContactId(contactId))\n";

    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) {
        report += s"  declared by a provider: \(provider.GetDisplayName())\n";
    } else {
        report += "  declared by: nobody (built-in text, or not driven)\n";
    }

    let holder = AiNpcFloorHolder(contactId);
    if NotEquals(StrLen(holder), 0) {
        report += s"  floor held by: \(holder)\n";
    } else {
        report += "  floor: free\n";
    }

    // Addressed to everyone rather than to this contact, which is why it is named here: a fact
    // about the city shows up in this character's <world_background> without anything having
    // been registered about this character.
    let world = AiNpcGetWorldKnowledgeRegistry();
    if IsDefined(world) {
        let facts = world.Facts();
        let f = 0;
        let factCount = ArraySize(facts);
        while f < factCount {
            report += s"  world knowledge '\(facts[f].fullId)': \(StrLen(facts[f].text)) chars, told to everyone\n";
            f += 1;
        }
    }

    let registry = AiNpcGetExtensionRegistry();
    if !IsDefined(registry) {
        return report;
    }

    let ctx = AiNpcBuildContactContext(contactId);
    let entries = registry.Extensions();
    let i = 0;
    let count = ArraySize(entries);
    while i < count {
        if entries[i].Covers(contactId) {
            report += s"  extension '\(entries[i].fullId)'\n";
        }
        i += 1;
    }

    // What this contact IS, then what it can DO. The tags are listed because they are the only
    // reason any of the commands below are here, and a command that is missing is nearly always
    // a tag that is missing.
    let table = AiNpcBuildActionTable(contactId);
    ctx.tags = table.tags;
    report += s"  tags: \(AiNpcJoinStrings(table.tags, ", "))\n";

    let claims = table.claims;
    let c = 0;
    let claimCount = ArraySize(claims);
    while c < claimCount {
        let claim = claims[c];
        // Offered is stated separately from owned: a command that is owned and not offered is
        // absent from the prompt and still recognised in a reply, which is the one piece of
        // this design that surprises a reader of the log.
        if claim.handler.IsOffered(ctx) {
            report += s"  command \(claim.pattern.raw) from '\(claim.fullId)' via \(claim.scopeTag)\n";
        } else {
            report += s"  command \(claim.pattern.raw) from '\(claim.fullId)' via \(claim.scopeTag), not offered right now\n";
        }
        c += 1;
    }

    let listeners = registry.Listeners();
    let j = 0;
    let listenerCount = ArraySize(listeners);
    while j < listenerCount {
        if listeners[j].Covers(contactId) {
            report += s"  listener '\(listeners[j].fullId)'\n";
        }
        j += 1;
    }
    return report;
}
