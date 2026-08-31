// The thinking lane: the one place a request is sent that the player never sees. It owns one
// thing -- turning a batch that has fallen out of the window into the memory that replaces it
// -- with its own in-flight slot and callback and no share of AiNpcHttpSystem's state, because
// routing it through the speaking lane would grey out the player's input during a background
// task.
//
// What it decides is decided by pure functions in AiNpcMemory.reds; here is the impure half --
// the clock, the store, the socket -- and the scheduling.
//
// A ScriptableSystem: its state must not survive a save load, because the batch it holds
// belongs to a timeline the next session may not be on.

module AiNpc

import Codeware.*
import RedData.Json.*
import RedHttpClient.*

public class AiNpcMemoryService extends ScriptableSystem {

    private let m_contact: String;
    private let m_base: ref<AiNpcMemory>;
    private let m_coverage: Int32;

    // How the answer finds its way back to the right messages. The reply lands seconds later,
    // by which time the player may have sent more, undone an exchange or cleared the thread,
    // so the captured list must not be written back. What is captured is the batch's identity
    // -- how many messages, and the text of the first -- and ApplyMemory re-reads and checks.
    private let m_absorbed: Int32;
    private let m_firstAbsorbed: String;

    // Whether the batch in flight is a full one, and so whether its answer may age the open
    // threads.
    private let m_ages: Bool = true;

    // Logged once per session, not per turn: a missing key is a standing condition the player
    // already knows from the speaking lane.
    private let m_warned: Bool = false;

    // The clock on the compaction in flight, and the answer to whether there is one: a lane
    // that stays busy never compacts again for the rest of the session, and a request that
    // never comes back has no callback to say so. The other fields are only meaningful while
    // it is waiting.
    private let m_watchdog: ref<AiNpcWatchdog>;

    // Counted up on every send, and read only by the CLI transport: HTTP addresses its answer
    // through the callback object, so a stale one cannot arrive.
    private let m_serial: Int32 = 0;

    // What the compaction in flight is costing. This lane is invisible to the player, which is
    // why it has to be counted: it spends the same key against the same daily cap, and a tally
    // of only what the player typed would end the day early with nothing to explain it.
    private let m_record: ref<AiNpcRequestRecord>;

    private func OnAttach() -> Void {
        this.m_watchdog = new AiNpcWatchdog();
        this.m_record = AiNpcRequestRecord.Idle();
    }

    public static func Get() -> ref<AiNpcMemoryService> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(NameOf<AiNpcMemoryService>()) as AiNpcMemoryService;
    }

    /// Scheduling ///

    // Offered a turn after a reply is delivered, never before one is sent: by then the message
    // is on screen and nothing the player waits for depends on what happens next. Compacting
    // before a send would make them wait for two round trips.
    public func NotifyTurnComplete(contactId: String) -> Void {
        this.Consider(contactId, false);
    }

    // The second trigger: a conversation that stopped hours ago is compacted at its own
    // boundary rather than waiting for a message count it may never reach again.
    //
    // Opening rather than closing, because at open the silence is a measured fact and at close
    // it would be a prediction: Hide is the catch-all for Escape, the hub menu and combat, and
    // stowing the phone because a gang opened fire is not the end of a conversation.
    //
    // Still not "before a send": if the player types before the answer lands, the send goes
    // out with the window un-absorbed, and ApplyMemory keeps whatever arrived meanwhile.
    public func NotifyConversationOpened(contactId: String) -> Void {
        this.Consider(contactId, true);
    }

    private func Consider(contactId: String, idle: Bool) -> Void {
        if this.m_watchdog.IsWaiting() || Equals(StrLen(contactId), 0) || !AiNpcMemoryEnabled() {
            return;
        }

        let contactProvider = AiNpcProviderFor(contactId);
        if IsDefined(contactProvider) && !contactProvider.AllowsMemory() {
            return;
        }

        // The same key, so a spent day stops this lane too -- and this is where it matters
        // most: the player never sees this request, so a cap that let it through would go on
        // emptying a budget they were told was closed.
        //
        // Nothing is lost by refusing: the store keeps every message and the window is
        // compacted at the next occasion. What it costs is a prompt that stays large.
        if !AiNpcHasTokenBudgetLeft() {
            AiNpcLog(s"Compaction deferred for '\(contactId)': the daily token budget is spent.");
            return;
        }

        let backend = AiNpcProviderSetting();
        let issue = AiNpcLlmCredentialIssue(backend);
        if NotEquals(StrLen(issue), 0) {
            if !this.m_warned {
                this.m_warned = true;
                AiNpcLog(s"Memory is idle: \(issue). Conversations will be trimmed instead of remembered.");
            }
            return;
        }

        let store = AiNpcConversationStore.Get();
        if !IsDefined(store) {
            return;
        }

        let messages = store.GetMessages(contactId);

        // A full batch is a full batch whichever trigger noticed it: the idle rule adds
        // occasions and never lowers the bar for the ordinary path.
        let full = AiNpcMemoryShouldCompact(messages);
        if !full && !(idle && AiNpcMemoryShouldCompactIdle(messages, AiNpcGetCurrentGameTimeSeconds())) {
            return;
        }

        let evicted = AiNpcMemoryEvicted(messages);
        if Equals(ArraySize(evicted), 0) {
            return;
        }

        this.Send(contactId, store.GetMemory(contactId), evicted, backend, contactProvider, full);
    }

    /// The request ///

    private func Send(contactId: String, previous: ref<AiNpcMemory>, evicted: array<ref<AiNpcMessage>>,
            backend: AiNpcProvider, contactProvider: ref<AiNpcContactProvider>, full: Bool) -> Void {
        let npcName = AiNpcGetCharacterName(contactId);
        let base = this.SeedIfEmpty(previous, contactProvider);

        // The builder decides once for both halves: the instruction asks for a CHRONICLE
        // exactly when the body carries an ARCHIVE to build it from.
        let builder = AiNpcPassCompaction.Of(base, npcName,
            AiNpcHistoryTranscript(evicted, npcName));

        this.m_contact = contactId;
        this.m_base = base;
        this.m_coverage = AiNpcMemoryCoverage(base.coveredUpTo, evicted);
        this.m_absorbed = ArraySize(evicted);
        this.m_firstAbsorbed = evicted[0].text;
        this.m_ages = full;

        // One send for both transports, and this lane is not told which runs: naming the CLI
        // type here would put a third file at risk of the validation failure AiNpcCliNative
        // describes.
        this.m_serial += 1;
        let request = AiNpcPassSend(builder, backend, contactId, this, n"OnMemoryResponse",
                AiNpcCliRequestId(AiNpcCliLaneMemory(), this.m_serial));
        if !IsDefined(request) {
            // Refused before anything was spawned. The log is the only place a silent lane can
            // say so, and nothing was armed, so the lane is already free.
            AiNpcLog(s"Compaction for '\(contactId)' was refused by the transport.");
            return;
        }
        this.m_record = request.record;

        // After the send and not before: arming is what marks this lane busy, so a request
        // that never left cannot occupy it.
        AiNpcArmTimeout(AiNpcThinkingTimeoutCallback.Create(this.m_watchdog.Arm()),
            AiNpcLlmRequestTimeout(backend, request.slot));

        let trigger = full ? "batch" : "silence";
        if builder.folding {
            let pending = ArraySize(base.archive) - AiNpcMemoryChronicleFrom(base, builder.exact);
            AiNpcLog(s"Folding \(pending) archived fact(s) into the chronicle for '\(contactId)' (\(builder.exact ? "exact" : "incremental")).");
        }

        AiNpcLog(s"Compacting \(this.m_absorbed) message(s) for '\(contactId)' (\(trigger)).");
    }

    // Applied at the first compaction rather than at registration, so seeded facts travel
    // through the same clamp, journal entry and eviction rule as everything else instead of
    // being a second kind of memory with its own lifetime.
    private func SeedIfEmpty(previous: ref<AiNpcMemory>, contactProvider: ref<AiNpcContactProvider>) -> ref<AiNpcMemory> {
        let base = AiNpcMemoryCopy(previous);
        if !AiNpcMemoryIsEmpty(base) || !IsDefined(contactProvider) {
            return base;
        }

        let seeds = contactProvider.GetSeedFacts();
        let i = 0;
        while i < ArraySize(seeds) {
            ArrayPush(base.facts, seeds[i]);
            i += 1;
        }
        return AiNpcMemoryClamp(base);
    }

    /// The answer ///

    // No logic: everything below the translation is shared with the CLI transport, so an
    // answer cannot be handled one way here and another there.
    private cb func OnMemoryResponse(response: ref<HttpResponse>) {
        this.HandleMemoryReply(AiNpcReply.FromHttp(response));
    }

    // Called from AiNpcCliDeliver. The serial makes a late answer harmless: a compaction that
    // timed out is not cancelled, and by the time it delivers this lane may hold a different
    // batch -- applying it would write one conversation's memory over another's.
    public func OnCliMemoryReply(serial: Int32, reply: ref<AiNpcReply>) -> Void {
        if NotEquals(serial, this.m_serial) {
            AiNpcLog(s"A compaction answer arrived after its turn (serial \(serial)); dropped.");
            return;
        }
        this.HandleMemoryReply(reply);
    }

    private func HandleMemoryReply(reply: ref<AiNpcReply>) -> Void {
        // Before the lane is freed, and before the record is written: a compaction abandoned
        // at 90 seconds is not cancelled, so an answer arriving at 95 would free the batch
        // that replaced it and file its cost against the wrong request.
        if !this.m_watchdog.IsWaiting() {
            AiNpcLog("A compaction answer arrived with nothing waiting for it; dropped.");
            return;
        }

        // Freed first and unconditionally: every path below is a return, and a lane that stays
        // busy after one never compacts again for the rest of the session.
        this.m_watchdog.Disarm();

        let root = reply.Root();

        // Above every branch, refusals included: an abandoned compaction still spent the
        // tokens.
        this.m_record.Answered(reply);

        if !reply.IsOk() {
            this.Abandon(s"HTTP \(reply.StatusCode())");
            return;
        }

        let text = AiNpcExtractChatText(root);
        if Equals(StrLen(text), 0) {
            this.Abandon("empty answer");
            return;
        }

        // Before the parse, and this is the branch that makes an output cap safe on this lane.
        // A note cut off by max_tokens still parses: the sections it did reach are well formed,
        // and the ones it did not are simply absent -- which reads as "this character no longer
        // remembers that", forever, with nothing anywhere saying why. The previous memory
        // stands and the next batch tries again, which is what every other bad answer does.
        if AiNpcReplyWasTruncated(root) {
            this.Abandon("the answer was cut off by the output budget (max_tokens); raise it on the slot this pass is on");
            return;
        }

        let parsed = AiNpcMemoryParse(text);
        if !IsDefined(parsed) {
            // An apology, a refusal or a paragraph of prose, rejected outright: a refusal
            // stored as a memory is a bug nobody diagnoses, because the character just starts
            // behaving as though it had been told to be careful, forever.
            this.Abandon("the answer was not a continuity note");
            return;
        }

        this.ApplyMemory(parsed);
    }

    // Abandoned like any other, which is the point of routing it here: the lane frees itself,
    // the previous memory stands, and the next batch tries again. Only the log says whether it
    // was lost to silence or to a bad answer.
    public func OnWaitTimedOut(waitId: Int32) -> Void {
        if !this.m_watchdog.IsCurrent(waitId) {
            return;
        }
        this.m_watchdog.Disarm();
        this.Abandon("no answer came back");
    }

    // Nothing changes: the previous memory stands, the messages are not evicted, and no banner
    // is shown. The next batch tries again, and if none succeeds the backstop trim takes over,
    // which is the behaviour the mod had before memory existed.
    private func Abandon(reason: String) -> Void {
        AiNpcLog(s"Compaction for '\(this.m_contact)' abandoned: \(reason). Nothing was changed.");
    }

    private func ApplyMemory(parsed: ref<AiNpcMemory>) -> Void {
        let store = AiNpcConversationStore.Get();
        if !IsDefined(store) {
            return;
        }

        let current = store.GetMessages(this.m_contact);

        // The batch has to still be there and still be at the front. It is not if the thread
        // was cleared, undone past the batch, or trimmed while the request was in flight, and
        // writing the captured window back would resurrect deleted messages or delete new ones.
        if ArraySize(current) < this.m_absorbed || this.m_absorbed <= 0 {
            this.Abandon("the conversation changed while the answer was in flight");
            return;
        }
        if NotEquals(current[0].text, this.m_firstAbsorbed) {
            this.Abandon("the batch is no longer at the front of the conversation");
            return;
        }

        let kept: array<ref<AiNpcMessage>>;
        let i = this.m_absorbed;
        while i < ArraySize(current) {
            ArrayPush(kept, current[i]);
            i += 1;
        }

        // Re-read for the same reason the messages are: it can have moved while the answer was
        // in flight, through AiNpcRecordFact, a gameplay event that does not wait for this
        // lane. A merge written from m_base alone erases whatever came through it, after
        // RecordFact told its caller the fact was kept.
        let live = store.GetMemory(this.m_contact);
        let summarised = AiNpcMemoryMerge(this.m_base, parsed, this.m_coverage, this.m_ages);
        let merged = AiNpcMemoryRebase(summarised, this.m_base, live);
        store.Compact(this.m_contact, merged, kept);

        let carried = AiNpcMemoryFactsSince(this.m_base, live);
        if ArraySize(carried) > 0 {
            AiNpcLog(s"Carried \(ArraySize(carried)) fact(s) recorded while the compaction for '\(this.m_contact)' was in flight.");
        }

        AiNpcLog(s"'\(this.m_contact)' now remembers \(ArraySize(merged.facts)) fact(s) and \(ArraySize(merged.threads)) open thread(s); \(ArraySize(kept)) message(s) still verbatim.");
    }
}

func AiNpcGetMemoryService() -> ref<AiNpcMemoryService> {
    return AiNpcMemoryService.Get();
}

// The policy half of recording a gameplay fact; the write itself is
// AiNpcConversationStore.RecordFact. Who may be written to is the same pair
// AiNpcRenderMemoryBlock consults, stated once rather than at each call site.
//
// Both refusals are configurations, not failures: `memoryEnabled` is the player's switch, and
// AllowsMemory is the provider's, where false is characterisation. A caller gets false and
// chooses its own fallback; nothing here logs an error.
func AiNpcRecordFact(contactId: String, text: String) -> Bool {
    if Equals(StrLen(contactId), 0) || Equals(StrLen(text), 0) {
        return false;
    }
    if !AiNpcMemoryEnabled() {
        return false;
    }

    let provider = AiNpcProviderFor(contactId);
    if IsDefined(provider) && !provider.AllowsMemory() {
        return false;
    }

    let store = AiNpcConversationStore.Get();
    if !IsDefined(store) {
        return false;
    }

    let kept = store.RecordFact(contactId, text, AiNpcGetCurrentGameTimeSeconds());
    if kept {
        AiNpcLog(s"Recorded a fact for '\(contactId)': \(text)");
    } else {
        AiNpcLog(s"Could not record a fact for '\(contactId)': no conversation to hang it on.");
    }
    return kept;
}
