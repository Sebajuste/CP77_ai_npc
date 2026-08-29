// What a mod asked a character to say and that has not been said yet. The speaking lane is one
// for the whole session, so a mod asking Panam to write while Judy's reply is in flight was
// told "a generation is already running" with no queue and no signal saying when the lane
// frees. The policy argument on the call opts into this queue.
//
// AiNpcClientRegistry's deferral says only undated, idempotent things are ever queued, because
// a message carries a moment. That rule stands and this is its stated exception: the window is
// what makes the moment predictable again. AiNpcSayWithin(180) means "now or within three
// minutes, and after that it is no longer true" -- a lapsed reason is dropped, not delivered
// late, and its ticket says so. The two queues stay separate.
//
// The clock is engine time, like the floor's: a window and a debounce are measured in the
// seconds a player spends, and Night City's clock runs some sixty times faster, so a
// three-minute window in game seconds would lapse in three real ones.
//
// The debounce is not a schedule. When a character has something to say is the mod's question;
// what ai_npc owns is the cost of a request the player never typed, so one minute of play
// separates two unprompted messages on one contact -- not to pace the fiction, but so a mod
// looping on a bad trigger cannot spend the quota in a burst.
//
// The protections cover different abuses: the debounce stops one mod hammering one contact,
// the fixed size stops ten mods filling the queue, and one entry per (mod, contact) stops a
// single mod occupying more than one slot.
//
// The class below touches no game API -- it takes `now` as an argument -- so the cap, the
// replacement, the expiry boundary and the debounce are assertable without a session. The
// orchestration that needs the lane, the floor and the clock is in the free functions below.

module AiNpc

/// The numbers ///

// All mods together. Small on purpose: a queue deep enough to hold a backlog delivers one, and
// every entry is a message the player never asked for.
func AiNpcSpeechQueueSize() -> Int32 {
    return 8;
}

// Seconds of play between two unprompted messages on ONE contact.
func AiNpcSpeechDebounce() -> Float {
    return 60.0;
}

/// What Admit answers ///

// Three outcomes: the two refusals are reported as different sentences, and one is a call site
// to fix rather than a state to wait out.
func AiNpcSpeechAdmitted() -> Int32 {
    return 1;
}

// Refused immediately whatever window was asked for: holding an entry that cannot be admitted
// until somebody else's is spent is a wait with no bound.
func AiNpcSpeechQueueIsFull() -> Int32 {
    return 2;
}

// The window ends before this contact may speak again, so the entry is doomed on arrival:
// refused now rather than after a wait that could never have worked.
func AiNpcSpeechWindowTooShort() -> Int32 {
    return 3;
}

/// The entries ///

public class AiNpcPendingSpeech {
    public let modId: String;
    public let contactId: String;
    public let reason: String;
    public let intent: String;
    public let ticket: Int32;

    // Engine time, absolute. Past it the reason is no longer true and the entry is dropped
    // rather than delivered.
    public let expiresAt: Float;
}

// Per contact rather than per mod: the debounce protects the player from a burst of unprompted
// messages, and the player does not care which mod caused each.
public class AiNpcSpokeAt {
    public let contactId: String;
    public let at: Float;
}

public class AiNpcSpeechQueue {

    private let m_pending: array<ref<AiNpcPendingSpeech>>;
    private let m_spoke: array<ref<AiNpcSpokeAt>>;

    // Set while a drain is armed, so a burst of releases arms one callback and not six.
    private let m_drainArmed: Bool = false;

    /// The debounce ///

    // 0 for a contact that never has, so the first unprompted message of a session is never
    // held back.
    public func NextAllowedAt(contactId: String) -> Float {
        let index = this.SpokeIndexOf(contactId);
        if index < 0 {
            return 0.0;
        }
        return this.m_spoke[index].at + AiNpcSpeechDebounce();
    }

    public func MaySpeakAt(contactId: String, now: Float) -> Bool {
        return now >= this.NextAllowedAt(contactId);
    }

    // Called when a request is committed, not when its message lands: the debounce protects the
    // quota, and a request that left has spent one whether or not anything came back. It also
    // stops a mod whose trigger is wrong retrying a failing send in a tight loop.
    public func MarkSpoken(contactId: String, now: Float) -> Void {
        let index = this.SpokeIndexOf(contactId);
        if index >= 0 {
            this.m_spoke[index].at = now;
            return;
        }

        let mark = new AiNpcSpokeAt();
        mark.contactId = contactId;
        mark.at = now;
        ArrayPush(this.m_spoke, mark);
    }

    /// The queue ///

    public func Admit(modId: String, contactId: String, reason: String, intent: String,
                      ticket: Int32, expiresAt: Float) -> Int32 {
        if expiresAt <= this.NextAllowedAt(contactId) {
            return AiNpcSpeechWindowTooShort();
        }

        // A restatement replaces this mod's own entry and keeps its place: a mod whose trigger
        // fired twice must not own two slots, nor lose the position it has been waiting in.
        let index = this.IndexOfEntry(modId, contactId);
        if index >= 0 {
            this.m_pending[index].reason = reason;
            this.m_pending[index].intent = intent;
            this.m_pending[index].ticket = ticket;
            this.m_pending[index].expiresAt = expiresAt;
            return AiNpcSpeechAdmitted();
        }

        if ArraySize(this.m_pending) >= AiNpcSpeechQueueSize() {
            return AiNpcSpeechQueueIsFull();
        }

        let entry = new AiNpcPendingSpeech();
        entry.modId = modId;
        entry.contactId = contactId;
        entry.reason = reason;
        entry.intent = intent;
        entry.ticket = ticket;
        entry.expiresAt = expiresAt;
        ArrayPush(this.m_pending, entry);
        return AiNpcSpeechAdmitted();
    }

    // Removed and handed back so the caller can resolve the tickets. One call, because an entry
    // dropped without its ticket settled is a mod waiting forever on a Pending.
    public func TakeExpired(now: Float) -> array<ref<AiNpcPendingSpeech>> {
        let dropped: array<ref<AiNpcPendingSpeech>>;
        let i = ArraySize(this.m_pending) - 1;
        while i >= 0 {
            if AiNpcLeaseHasExpired(this.m_pending[i].expiresAt, now) {
                ArrayPush(dropped, this.m_pending[i]);
                ArrayErase(this.m_pending, i);
            }
            i -= 1;
        }
        return dropped;
    }

    // Null when it holds none, which is the honest answer to cancelling twice, to cancelling a
    // ticket that already went out, and to cancelling somebody else's.
    public func TakeOwned(modId: String, ticket: Int32) -> ref<AiNpcPendingSpeech> {
        let i = 0;
        let count = ArraySize(this.m_pending);
        while i < count {
            if Equals(this.m_pending[i].ticket, ticket) && Equals(this.m_pending[i].modId, modId) {
                let entry = this.m_pending[i];
                ArrayErase(this.m_pending, i);
                return entry;
            }
            i += 1;
        }
        return null;
    }

    // Everything one mod is waiting on, removed and handed back: part of withdrawing in one
    // call.
    public func TakeAllFor(modId: String) -> array<ref<AiNpcPendingSpeech>> {
        let dropped: array<ref<AiNpcPendingSpeech>>;
        let i = ArraySize(this.m_pending) - 1;
        while i >= 0 {
            if Equals(this.m_pending[i].modId, modId) {
                ArrayPush(dropped, this.m_pending[i]);
                ArrayErase(this.m_pending, i);
            }
            i -= 1;
        }
        return dropped;
    }

    public func Count() -> Int32 {
        return ArraySize(this.m_pending);
    }

    // Arrival order and nothing else: "the most urgent" needs a comparison between two mods'
    // content, and there is none.
    public func At(index: Int32) -> ref<AiNpcPendingSpeech> {
        if index < 0 || index >= ArraySize(this.m_pending) {
            return null;
        }
        return this.m_pending[index];
    }

    public func RemoveAt(index: Int32) -> Void {
        if index >= 0 && index < ArraySize(this.m_pending) {
            ArrayErase(this.m_pending, index);
        }
    }

    // The next instant this queue's answer could change on its own. Two conditions clear
    // themselves with the clock and announce nothing: a window closing, and a debounce
    // lifting. Everything else arms a drain of its own. 0 means nothing to wake up for.
    public func NextWakeAt(now: Float) -> Float {
        let soonest = 0.0;
        let i = 0;
        let count = ArraySize(this.m_pending);
        while i < count {
            soonest = AiNpcSoonerOf(soonest, this.m_pending[i].expiresAt);
            let allowed = this.NextAllowedAt(this.m_pending[i].contactId);
            if allowed > now {
                soonest = AiNpcSoonerOf(soonest, allowed);
            }
            i += 1;
        }
        return soonest;
    }

    /// The drain flag ///

    // True when this call is the one that armed it, so a burst of freed floors does not stack a
    // callback each.
    public func ArmDrain() -> Bool {
        if this.m_drainArmed {
            return false;
        }
        this.m_drainArmed = true;
        return true;
    }

    public func DisarmDrain() -> Void {
        this.m_drainArmed = false;
    }

    /// Internals ///

    private func IndexOfEntry(modId: String, contactId: String) -> Int32 {
        let i = 0;
        let count = ArraySize(this.m_pending);
        while i < count {
            if Equals(this.m_pending[i].modId, modId) && Equals(this.m_pending[i].contactId, contactId) {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    private func SpokeIndexOf(contactId: String) -> Int32 {
        let i = 0;
        let count = ArraySize(this.m_spoke);
        while i < count {
            if Equals(this.m_spoke[i].contactId, contactId) {
                return i;
            }
            i += 1;
        }
        return -1;
    }
}

/// The clock ///

// The earlier of two instants, with 0 meaning "nothing set yet" rather than "the beginning of
// time": `MinF(a, b)` would answer 0 against an unset accumulator, which is the one answer
// that must not mean "wake up now".
func AiNpcSoonerOf(current: Float, candidate: Float) -> Float {
    if current <= 0.0 || candidate < current {
        return candidate;
    }
    return current;
}

// Engine time, as the floor reads it: both measure a player's seconds and both would be wrong
// on the game's clock.
func AiNpcSpeechNow() -> Float {
    return EngineTime.ToFloat(GameInstance.GetSimTime(GetGameInstance()));
}

// The window a policy value asks for, as an absolute instant. 0 and below is "now or never",
// which never reaches here.
func AiNpcSpeechWindowEndsAt(now: Float, holdSeconds: Int32) -> Float {
    return now + Cast<Float>(holdSeconds);
}

/// Access ///

// On the client registry beside the ticket book, because the three things a mod is owed -- its
// claim, its verdicts and what it is waiting on -- are one lifetime.
func AiNpcGetSpeechQueue() -> ref<AiNpcSpeechQueue> {
    let registry = AiNpcGetClientRegistry();
    if !IsDefined(registry) {
        return null;
    }
    return registry.SpeechQueue();
}

/// Queueing ///

// Puts a reason in the line, or refuses it on the ticket. Never both, and never neither.
func AiNpcQueueSpeech(modId: String, contactId: String, reason: String, intent: String,
                             ticket: Int32, expiresAt: Float) -> Void {
    let queue = AiNpcGetSpeechQueue();
    if !IsDefined(queue) {
        AiNpcResolveClientTicket(ticket, AiNpcTicketFailed(), "no session");
        return;
    }

    let outcome = queue.Admit(modId, contactId, reason, intent, ticket, expiresAt);
    if Equals(outcome, AiNpcSpeechQueueIsFull()) {
        AiNpcResolveClientTicket(ticket, AiNpcTicketFailed(),
            s"the queue of unprompted messages is full (\(AiNpcSpeechQueueSize()) waiting)");
        return;
    }

    if Equals(outcome, AiNpcSpeechWindowTooShort()) {
        AiNpcResolveClientTicket(ticket, AiNpcTicketFailed(),
            s"'\(contactId)' wrote first less than \(Cast<Int32>(AiNpcSpeechDebounce())) seconds ago, and the window asked for ends before that lifts");
        return;
    }

    AiNpcLog(s"'\(modId)' is waiting for a window to have '\(contactId)' write first.");

    // Armed here and not only at the end of a drain: the two events that free the lane arm
    // their own, but nothing happens when a debounce lifts. An entry admitted behind one, with
    // no drain scheduled, would wait for an unrelated event that a quiet save never brings.
    let wake = queue.NextWakeAt(AiNpcSpeechNow());
    if wake > 0.0 {
        AiNpcScheduleSpeechDrain(wake - AiNpcSpeechNow());
    }
}

/// Draining ///

// A drain on the next frame, from the two places a wait ends -- the lane going idle and a floor
// released -- and nowhere else.
//
// Delayed rather than immediate: the lane frees itself mid-generation, several lines before the
// ticket of the message just delivered is resolved, and starting the next generation there
// would replace the object those lines are still reading. A drain lost to a save load costs
// nothing -- the queue does not survive one either.
func AiNpcRequestSpeechDrain() -> Void {
    let queue = AiNpcGetSpeechQueue();
    if !IsDefined(queue) || Equals(queue.Count(), 0) {
        return;
    }

    AiNpcScheduleSpeechDrain(0.1);
}

// The one place a drain is scheduled. Never affected by time dilation: a wait measured in the
// player's seconds must not stretch because they opened a menu.
func AiNpcScheduleSpeechDrain(seconds: Float) -> Void {
    let queue = AiNpcGetSpeechQueue();
    if !IsDefined(queue) || !queue.ArmDrain() {
        return;
    }

    let delay = seconds;
    if delay < 0.1 {
        delay = 0.1;
    }
    GameInstance.GetDelaySystem(GetGameInstance())
        .DelayCallback(AiNpcSpeechDrainCallback.Create(), delay, false);
}

// At most one waiting reason, dropping whatever expired on the way past. One, because the lane
// takes one generation at a time and the entry that goes out arms the next drain when it
// finishes; a second would be refused by the lane it just occupied and burn its ticket.
func AiNpcDrainSpeechQueue() -> Void {
    let queue = AiNpcGetSpeechQueue();
    if !IsDefined(queue) {
        return;
    }

    let now = AiNpcSpeechNow();

    // Before anything is sent, and unconditionally: a window that closed while the lane was
    // busy is the ordinary outcome, and the mod hears about it here either way.
    let stale = queue.TakeExpired(now);
    let i = 0;
    let count = ArraySize(stale);
    while i < count {
        AiNpcLog(s"'\(stale[i].modId)' waited for '\(stale[i].contactId)' to have a window, and it never came.");
        AiNpcResolveClientTicket(stale[i].ticket, AiNpcTicketFailed(),
            "the window passed before there was room to write");
        i += 1;
    }

    let http = GetAiNpcHttpSystem();
    if !IsDefined(http) || http.GetIsGenerating() {
        return;
    }

    i = 0;
    count = queue.Count();
    while i < count {
        let entry = queue.At(i);
        if AiNpcMayWriteTo(entry.contactId, entry.modId) && queue.MaySpeakAt(entry.contactId, now) {
            queue.RemoveAt(i);

            // Window 0, because the wait is over: a refusal from here is one this drain already
            // ruled out, so re-queueing would be a loop with a ticket in it.
            http.TriggerUnpromptedRequest(entry.contactId, entry.modId, entry.reason,
                entry.ticket, entry.intent, 0.0);
            i = count;
        } else {
            i += 1;
        }
    }

    // What is left waits on the clock rather than an event. One wake-up for the earliest of
    // them, not a poll: a mod holding a three-minute window must not cost three minutes of
    // per-second array walks, and an entry whose window closes in silence still needs its
    // ticket answered.
    let wake = queue.NextWakeAt(now);
    if wake > 0.0 {
        AiNpcScheduleSpeechDrain(wake - now);
    }
}

// The next frame, when the generation that freed the lane is entirely finished.
public class AiNpcSpeechDrainCallback extends DelayCallback {

    public static func Create() -> ref<AiNpcSpeechDrainCallback> {
        return new AiNpcSpeechDrainCallback();
    }

    public func Call() -> Void {
        let queue = AiNpcGetSpeechQueue();
        if IsDefined(queue) {
            queue.DisarmDrain();
        }
        AiNpcDrainSpeechQueue();
    }
}
