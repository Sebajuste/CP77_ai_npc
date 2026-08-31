// Conversation memory: what the history becomes when it leaves the window. Design in
// docs\MEMORY.md.
//
// Invariant every function preserves: messages is always a SUFFIX of the conversation, and
// everything that left it passed through memory. Nothing is in both. That makes undo safe
// across a compaction and a double-compaction of the same batch inexpressible.
//
// Facts, threads, tone and pacts are separate lists because they decay at different speeds;
// one blob forces one decay rate on all four.

module AiNpc

import RedData.Json.*

// A class rather than a parallel array beside the texts: two arrays trimmed independently
// is a bug this codebase has paid for once (AiNpcHistory.reds).
public class AiNpcMemoryThread {
    public let text: String;
    public let age: Int32;
}

func AiNpcMemoryThreadNew(text: String, age: Int32) -> ref<AiNpcMemoryThread> {
    let thread = new AiNpcMemoryThread();
    thread.text = text;
    thread.age = age;
    return thread;
}

// One agreement, not yet played out. Its own list, on the axis of who decides it is over:
//
//   facts    the code, by eviction        threads  the model, by not writing it again
//   tone     the model, by overwriting    pacts    the clock, and nobody else
//
// Filed as a thread it is lost: a compaction stops mentioning whatever the last ten turns
// were not about. Measured on b18 (`journal.py memory b18 --evicted`), two agreements were
// gone within two compactions while the biography around them survived.
//
// A pact leaves the list by two doors: the model omits it (settled, recorded as a fact), or
// its horizon passes (it becomes a fact itself).
public class AiNpcMemoryPact {
    public let text: String;

    // In-game seconds: the end of the batch that recorded it. AiNpcTimeUnknown() when the
    // batch carried no stamp, and the pact then never lapses -- a wrong "this is overdue"
    // is worse than no deadline.
    public let openedAt: Int32;

    // One of the closed horizons below, not a duration.
    public let horizon: Int32;
}

func AiNpcMemoryPactNew(text: String, openedAt: Int32, horizon: Int32) -> ref<AiNpcMemoryPact> {
    let pact = new AiNpcMemoryPact();
    pact.text = text;
    pact.openedAt = openedAt;
    pact.horizon = horizon;
    return pact;
}

// A closed enumeration: a field the model fills is a field the model can get wrong, so it
// is validated against a list. The model is asked for a word, never a duration -- it cannot
// read the in-game clock. An unrecognised word falls back to the horizon that never
// expires, which is the direction that cannot hurt.
func AiNpcMemoryPactSoon() -> Int32 {
    return 0;
}

func AiNpcMemoryPactDays() -> Int32 {
    return 1;
}

func AiNpcMemoryPactOpen() -> Int32 {
    return 2;
}

// In-game seconds; negative means "never lapses". Both spans are derived, not picked, so
// this file and the renderer cannot disagree about when an episode ended: SOON is twice
// AiNpcMemoryIdleGapSeconds, DAYS is where AiNpcFormatElapsedGameTime stops counting hours.
func AiNpcMemoryPactHorizonSeconds(horizon: Int32) -> Int32 {
    if Equals(horizon, AiNpcMemoryPactSoon()) {
        return 2 * AiNpcMemoryIdleGapSeconds();
    }
    if Equals(horizon, AiNpcMemoryPactDays()) {
        return 3 * 86400;
    }
    return -1;
}

// Both cases spelled out rather than case-folded: there is no vanilla StrLower, and the
// UTF8StrLower seen in installed mods is Codeware's, which this mod does not depend on.
func AiNpcMemoryPactHorizonOf(word: String) -> Int32 {
    let text = AiNpcMemoryTrim(word);
    if Equals(text, "soon") || Equals(text, "SOON") {
        return AiNpcMemoryPactSoon();
    }
    if Equals(text, "days") || Equals(text, "DAYS") {
        return AiNpcMemoryPactDays();
    }
    return AiNpcMemoryPactOpen();
}

func AiNpcMemoryPactHorizonWord(horizon: Int32) -> String {
    if Equals(horizon, AiNpcMemoryPactSoon()) {
        return "soon";
    }
    if Equals(horizon, AiNpcMemoryPactDays()) {
        return "days";
    }
    return "open";
}

// Evaluated at read time, never scheduled: a DelayCallback does not survive a save/load.
func AiNpcMemoryPactLapsed(pact: ref<AiNpcMemoryPact>, nowSeconds: Int32) -> Bool {
    if !IsDefined(pact) {
        return false;
    }
    let span = AiNpcMemoryPactHorizonSeconds(pact.horizon);
    if span < 0 {
        return false;
    }
    if Equals(pact.openedAt, AiNpcTimeUnknown()) || Equals(nowSeconds, AiNpcTimeUnknown()) {
        return false;
    }
    return nowSeconds - pact.openedAt >= span;
}

public class AiNpcMemory {
    // Consolidated, oldest first; every rule here depends on that order. Written once,
    // never rewritten, which is what bounds drift. Evicted oldest first, except for the
    // founding prefix below.
    public let facts: array<String>;

    // How many of the leading facts are founding, and so never evicted. Oldest-first is the
    // right rule for episodic content and the wrong one for identity: measured before this
    // existed, plain FIFO dropped "V is a joytoy and told him herself" while keeping "a
    // colleague showed him the profile once".
    //
    // A count rather than a flag per entry: the founding facts are always a prefix, and a
    // prefix cannot fall out of step with its list the way a parallel array can.
    public let founding: Int32;

    // Open loops. Resubmitted for rewriting at every compaction, because a thread has to be
    // closable.
    public let threads: array<ref<AiNpcMemoryThread>>;

    // Never in competition with facts for room -- see AiNpcMemoryPact.
    public let pacts: array<ref<AiNpcMemoryPact>>;

    // Every fact ever held, in order. Append-only, never sent with a normal request. It
    // makes eviction a demotion rather than a deletion:
    //
    //     window (verbatim) -> facts (sent every message) -> archive (kept, not sent)
    //
    // Only facts descend. Threads and pacts are closed by omission, so archiving them would
    // resurrect loops their own compaction closed.
    public let archive: array<String>;

    // The archive as prose, and a derived view: it can be rebuilt from the archive at any
    // time, so drift is repairable rather than permanent. A rolling summary re-summarises
    // its own last pass and has no way back.
    public let chronicle: String;

    // How much of the archive the chronicle covers: exactly `archive[0 .. chronicleUpTo)`.
    // A count defining a prefix, as with `founding`. It makes the two folding modes one
    // operation over a different slice -- see AiNpcMemoryChronicleFrom.
    public let chronicleUpTo: Int32;

    // Where the relationship stands, in one line. Always overwritten.
    public let tone: String;

    // In-game time of the last absorbed message, in absolute seconds; AiNpcTimeUnknown()
    // when nothing absorbed carried a stamp. Lets the prompt say how long ago the remembered
    // part happened without keeping the messages.
    public let coveredUpTo: Int32;
}

// Policy stated as functions, so the tests can pin it and no caller can disagree.

// What goes into the prompt verbatim.
func AiNpcMemoryWindowTurns() -> Int32 {
    return 6;
}

// How much must pile up beyond the window before a compaction is worth a request. Per batch
// rather than per turn: it keeps the memory block byte-identical between compactions, and
// stops the memory being rewritten -- and so given a chance to drift -- every message.
func AiNpcMemoryBatchTurns() -> Int32 {
    return 10;
}

// Derived, not chosen: stating it any other way would let it disagree with window + batch.
func AiNpcMemoryMaxTurns() -> Int32 {
    return AiNpcMemoryWindowTurns() + AiNpcMemoryBatchTurns();
}

// The backstop: memory is best-effort, the size of the prompt is not. Past this the history
// is trimmed whether or not anything was remembered, and the content is lost. Above MaxTurns
// so an ordinary compaction can be retried at the next turn first.
func AiNpcMemoryHardMaxTurns() -> Int32 {
    return AiNpcMemoryWindowTurns() + 2 * AiNpcMemoryBatchTurns();
}

// The window when memory is switched off. A prompt bound, not a storage one: the journal
// always keeps HardMaxTurns, so toggling the setting never destroys messages.
func AiNpcMemoryLegacyMaxTurns() -> Int32 {
    return 20;
}

// How many consolidated facts are held before the oldest episodic one is evicted.
//
// Measured with `python ai_npc_lab\journal\journal.py memory b18`, which replays the compactions the game
// wrote. Facts evicted over 16 compactions: cap 12 loses 41 of 59, cap 16 loses 25, cap 20
// loses 10, cap 24 loses 2. 20 is where the curve bends; 24 buys eight more facts for ~120
// tokens on every message, and the memory block sits after the cacheable prefix.
//
// Rendering only the most relevant subset was measured and rejected: over 180 player
// messages, 60% share no content word with any stored fact. A texting conversation refers to
// its past by pronoun, the facts are the model's paraphrase, and the two share no
// vocabulary. So budget and cap are the same number.
//
// The default of a slider, not the only value; AiNpcMemoryClampFactBudget is what the mod
// will accept.
func AiNpcMemoryDefaultMaxFacts() -> Int32 {
    return 20;
}

// Floor 8: eviction starts after the founding prefix (4), and a budget at or below it would
// leave AiNpcMemoryClamp nothing it is allowed to evict -- it would fall back to victim 0
// and eat the identity of the relationship. Ceiling 40: past the measured curve.
//
// A value from a hand-written settings file is corrected, not trusted. tools\lint.ps1 pins
// both numbers to the min/max the menu advertises.
func AiNpcMemoryClampFactBudget(value: Int32) -> Int32 {
    if value < 8 {
        return 8;
    }
    if value > 40 {
        return 40;
    }
    return value;
}

// The player's slider, clamped, or the default when there is no session to ask. The impure
// step lives in AiNpcMemoryFactBudget (AiNpcUtilities.reds).
func AiNpcMemoryMaxFacts() -> Int32 {
    return AiNpcMemoryFactBudget();
}

// Small on purpose: the identity of the relationship, not a second archive.
func AiNpcMemoryFoundingFacts() -> Int32 {
    return 4;
}

func AiNpcMemoryMaxThreads() -> Int32 {
    return 6;
}

// Smaller than the thread list: a longer one would invite the model to file ordinary open
// questions as agreements. Four covers the measured case -- the negotiated meeting in b18
// settled place, duration, surcharge and who pays. FIFO, like threads.
func AiNpcMemoryMaxPacts() -> Int32 {
    return 4;
}

// The archive's backstop, in entries. Not a budget: the archive is never sent. 200 entries
// at the observed median of 121 characters is ~26 KB per snapshot, reached past three
// hundred turns with one contact.
//
// Only entries the chronicle has already folded in are dropped, so the price of reaching it
// is that a full rebuild is no longer exact -- it starts from the chronicle rather than from
// the beginning. See AiNpcMemoryClamp.
func AiNpcMemoryMaxArchive() -> Int32 {
    return 200;
}

// The chronicle's hard cap, in characters -- ~150 tokens, paid on every message. Narrow on
// purpose: a tight cap forces density better than an instruction against editorialising.
func AiNpcMemoryMaxChronicleChars() -> Int32 {
    return 600;
}

// Where a fold starts reading the archive. Two modes over one operation:
//
//   exact        from 0             rebuilt from the facts, never from a previous
//                                   chronicle: zero drift, costs the whole archive
//   incremental  from chronicleUpTo the previous chronicle plus what was archived since:
//                                   O(1), drifts slowly
//
// Incremental is the default, exact is the repair.
func AiNpcMemoryChronicleFrom(memory: ref<AiNpcMemory>, exact: Bool) -> Int32 {
    if !IsDefined(memory) || exact {
        return 0;
    }
    return memory.chronicleUpTo;
}

func AiNpcMemoryShouldFold(memory: ref<AiNpcMemory>) -> Bool {
    if !IsDefined(memory) {
        return false;
    }
    return ArraySize(memory.archive) > memory.chronicleUpTo;
}

// Per entry, in characters. A backstop, not a budget -- the budget is the "one short
// sentence each" in AiNpcMemoryInstruction, and the longest entry a real compaction produced
// was 85 characters.
//
// 240 comes from the corpus: over 1118 sentences these characters wrote, median 67, p95 155,
// longest 274. At 160 the cap would fire on one natural sentence in twenty-five, and facts
// are never rewritten, so it would mangle them permanently.
func AiNpcMemoryMaxEntryChars() -> Int32 {
    return 240;
}

// How many compactions a thread survives before it graduates into facts: something the
// conversation keeps returning to has earned the right to stop being rewritten.
func AiNpcMemoryPromoteAfter() -> Int32 {
    return 3;
}

// The silence past which a conversation counts as ended rather than paused, and so is worth
// compacting below a full batch. Derived from the gap markers, not chosen: inventing a
// second number would let the two disagree about where an episode ends.
func AiNpcMemoryIdleGapSeconds() -> Int32 {
    return AiNpcGapMarkerClockSeconds();   // 6 in-game hours
}

// The floor under an idle compaction, in messages beyond the window: it keeps the idle
// trigger from undoing the batching. Every compaction re-submits `threads` to be rewritten,
// so two short ones are two chances to drift where one full batch is one.
func AiNpcMemoryIdleMinBatch() -> Int32 {
    return 4;
}

/// Construction ///

func AiNpcMemoryNew() -> ref<AiNpcMemory> {
    let memory = new AiNpcMemory();
    memory.tone = "";
    memory.chronicle = "";
    memory.coveredUpTo = AiNpcTimeUnknown();
    memory.founding = 0;
    memory.chronicleUpTo = 0;
    return memory;
}

func AiNpcMemoryIsEmpty(memory: ref<AiNpcMemory>) -> Bool {
    if !IsDefined(memory) {
        return true;
    }
    return Equals(ArraySize(memory.facts), 0)
        && Equals(ArraySize(memory.threads), 0)
        && Equals(ArraySize(memory.pacts), 0)
        && Equals(ArraySize(memory.archive), 0)
        && Equals(StrLen(memory.chronicle), 0)
        && Equals(StrLen(memory.tone), 0);
}

func AiNpcMemoryCopy(memory: ref<AiNpcMemory>) -> ref<AiNpcMemory> {
    let result = AiNpcMemoryNew();
    if !IsDefined(memory) {
        return result;
    }

    let i = 0;
    while i < ArraySize(memory.facts) {
        ArrayPush(result.facts, memory.facts[i]);
        i += 1;
    }

    i = 0;
    while i < ArraySize(memory.threads) {
        ArrayPush(result.threads, AiNpcMemoryThreadNew(memory.threads[i].text, memory.threads[i].age));
        i += 1;
    }

    i = 0;
    while i < ArraySize(memory.pacts) {
        ArrayPush(result.pacts, AiNpcMemoryPactNew(memory.pacts[i].text,
            memory.pacts[i].openedAt, memory.pacts[i].horizon));
        i += 1;
    }

    i = 0;
    while i < ArraySize(memory.archive) {
        ArrayPush(result.archive, memory.archive[i]);
        i += 1;
    }

    result.tone = memory.tone;
    result.chronicle = memory.chronicle;
    result.coveredUpTo = memory.coveredUpTo;
    result.founding = memory.founding;
    result.chronicleUpTo = memory.chronicleUpTo;
    return result;
}

/// Text helpers ///

// A parsed memory line comes off model output that may carry a stray "\r", so it is trimmed at
// both ends. The rule itself is AiNpcTrimBlanks: this name says which reader wants it.
func AiNpcMemoryTrim(text: String) -> String {
    return AiNpcTrimBlanks(text);
}

// Truncated, not rejected: half a remembered fact is worth more than none. The cut must
// look like a cut, because a fact is never rewritten and a truncation that stays
// grammatical can reverse its meaning permanently -- "V a decide de ne pas arreter" cut
// early reads "V a decide de".
func AiNpcMemoryClampEntry(text: String) -> String {
    return AiNpcMemoryClampTo(text, AiNpcMemoryMaxEntryChars());
}

// Split out so the chronicle, which has a wider bound, cannot grow a second copy of the
// word-boundary rule that would drift from this one.
func AiNpcMemoryClampTo(text: String, cap: Int32) -> String {
    let trimmed = AiNpcMemoryTrim(text);
    if StrLen(trimmed) <= cap {
        return trimmed;
    }

    let body = AiNpcMemoryTrim(StrLeft(trimmed, cap - 3));

    // Back up to the last space, unless that costs more than a quarter of the entry: a line
    // with no spaces (a url, a handle) is better cut mid-token than reduced to nothing.
    let i = StrLen(body) - 1;
    let floor = (cap * 3) / 4;
    while i > floor {
        if Equals(StrMid(body, i, 1), " ") {
            return AiNpcMemoryTrim(StrLeft(body, i)) + "...";
        }
        i -= 1;
    }
    return body + "...";
}

/// Clamping ///

// The bound behind the word budget the prompt requests. Applied on every write and every
// read, because a memory can also arrive from disk -- hand-edited, or written by an older
// build with different caps. Overflow drops the oldest.
func AiNpcMemoryClamp(memory: ref<AiNpcMemory>) -> ref<AiNpcMemory> {
    let result = AiNpcMemoryNew();
    if !IsDefined(memory) {
        return result;
    }

    // Recomputed rather than copied: a founding fact can be dropped here as a blank or a
    // duplicate, and a stale count would then protect the episodic fact that took its place.
    let i = 0;
    while i < ArraySize(memory.facts) {
        let entry = AiNpcMemoryClampEntry(memory.facts[i]);
        if NotEquals(StrLen(entry), 0) && !ArrayContains(result.facts, entry) {
            ArrayPush(result.facts, entry);
            if i < memory.founding {
                result.founding += 1;
            }
        }
        i += 1;
    }
    // Copied before the eviction below, which is where evicted facts land. Deduplicated on
    // the way in, so clamping twice is a no-op -- and it is clamped twice routinely, once
    // out of a merge and once in from the journal.
    i = 0;
    while i < ArraySize(memory.archive) {
        let entry = AiNpcMemoryClampEntry(memory.archive[i]);
        if NotEquals(StrLen(entry), 0) && !ArrayContains(result.archive, entry) {
            ArrayPush(result.archive, entry);
        }
        i += 1;
    }
    result.chronicleUpTo = memory.chronicleUpTo;
    if result.chronicleUpTo > ArraySize(result.archive) {
        result.chronicleUpTo = ArraySize(result.archive);
    }
    if result.chronicleUpTo < 0 {
        result.chronicleUpTo = 0;
    }

    // Eviction starts after the founding prefix, oldest episodic fact first. The fact is
    // moved, not erased: it leaves the prompt and stays on disk, where a chronicle can be
    // rebuilt from it.
    while ArraySize(result.facts) > AiNpcMemoryMaxFacts() {
        let victim = result.founding;
        if victim >= ArraySize(result.facts) {
            victim = 0;     // unreachable while founding < the cap; not a reason to spin
        }
        if !ArrayContains(result.archive, result.facts[victim]) {
            ArrayPush(result.archive, result.facts[victim]);
        }
        ArrayErase(result.facts, victim);
    }

    // The only place in this file where something is destroyed, and it drops from the folded
    // prefix only: those entries are inside the chronicle already, so what is lost is the
    // exact rebuild, not the content. The loop stops rather than drop an unfolded entry, and
    // the archive may sit over its cap until the next fold moves the boundary.
    while ArraySize(result.archive) > AiNpcMemoryMaxArchive() && result.chronicleUpTo > 0 {
        ArrayErase(result.archive, 0);
        result.chronicleUpTo -= 1;
    }

    i = 0;
    while i < ArraySize(memory.threads) {
        let entry = AiNpcMemoryClampEntry(memory.threads[i].text);
        if NotEquals(StrLen(entry), 0) && !AiNpcMemoryHasThread(result.threads, entry) {
            ArrayPush(result.threads, AiNpcMemoryThreadNew(entry, memory.threads[i].age));
        }
        i += 1;
    }
    while ArraySize(result.threads) > AiNpcMemoryMaxThreads() {
        ArrayErase(result.threads, 0);
    }

    i = 0;
    while i < ArraySize(memory.pacts) {
        let entry = AiNpcMemoryClampEntry(memory.pacts[i].text);
        if NotEquals(StrLen(entry), 0) && !AiNpcMemoryHasPact(result.pacts, entry) {
            ArrayPush(result.pacts, AiNpcMemoryPactNew(entry, memory.pacts[i].openedAt,
                memory.pacts[i].horizon));
        }
        i += 1;
    }
    while ArraySize(result.pacts) > AiNpcMemoryMaxPacts() {
        ArrayErase(result.pacts, 0);
    }

    result.tone = AiNpcMemoryClampEntry(memory.tone);
    result.chronicle = AiNpcMemoryClampTo(memory.chronicle, AiNpcMemoryMaxChronicleChars());
    result.coveredUpTo = memory.coveredUpTo;
    return result;
}

func AiNpcMemoryHasThread(threads: array<ref<AiNpcMemoryThread>>, text: String) -> Bool {
    let i = 0;
    while i < ArraySize(threads) {
        if Equals(threads[i].text, text) {
            return true;
        }
        i += 1;
    }
    return false;
}

func AiNpcMemoryHasPact(pacts: array<ref<AiNpcMemoryPact>>, text: String) -> Bool {
    let i = 0;
    while i < ArraySize(pacts) {
        if Equals(pacts[i].text, text) {
            return true;
        }
        i += 1;
    }
    return false;
}

// Exact match, like AiNpcMemoryThreadAge: it lets a re-stated agreement keep the stamp it
// was opened with instead of resetting its clock every ten turns.
func AiNpcMemoryFindPact(pacts: array<ref<AiNpcMemoryPact>>, text: String) -> ref<AiNpcMemoryPact> {
    let i = 0;
    while i < ArraySize(pacts) {
        if Equals(pacts[i].text, text) {
            return pacts[i];
        }
        i += 1;
    }
    return null;
}

/// Merging ///

// Folds one compaction's answer into the memory that produced it. The asymmetry between the
// two lists is what bounds drift:
//
//   facts    previous ones kept verbatim, parsed ones appended. Handed to the model
//            read-only, so a fact cannot be reworded and errors cannot compound.
//   threads  replaced by the parsed list, because the only way to close a thread is to stop
//            writing it. One that reappears carries its age forward; a new one starts at 1.
//
// `agesThreads` is false for an idle compaction. Age counts full batches survived, not
// calls: without it, a player who checks the phone often would consolidate faster than one
// who talks more.
//
// An empty tone leaves the previous one standing: "no opinion" is not "no relationship".
func AiNpcMemoryMerge(previous: ref<AiNpcMemory>, parsed: ref<AiNpcMemory>, coveredUpTo: Int32, agesThreads: Bool) -> ref<AiNpcMemory> {
    let before = AiNpcMemoryCopy(previous);
    let result = AiNpcMemoryNew();

    let i = 0;
    while i < ArraySize(before.facts) {
        ArrayPush(result.facts, before.facts[i]);
        i += 1;
    }

    // Carried across untouched: the archive grows in the clamp at the end of this function,
    // when a fact overflows into it, never here.
    i = 0;
    while i < ArraySize(before.archive) {
        ArrayPush(result.archive, before.archive[i]);
        i += 1;
    }
    result.chronicle = before.chronicle;
    result.chronicleUpTo = before.chronicleUpTo;

    if IsDefined(parsed) {
        i = 0;
        while i < ArraySize(parsed.facts) {
            ArrayPush(result.facts, parsed.facts[i]);
            i += 1;
        }

        i = 0;
        while i < ArraySize(parsed.threads) {
            let text = AiNpcMemoryClampEntry(parsed.threads[i].text);
            if NotEquals(StrLen(text), 0) {
                let age = AiNpcMemoryThreadAge(before.threads, text);
                if agesThreads {
                    age += 1;
                }
                if age >= AiNpcMemoryPromoteAfter() {
                    ArrayPush(result.facts, text);
                } else {
                    ArrayPush(result.threads, AiNpcMemoryThreadNew(text, age));
                }
            }
            i += 1;
        }

        // The two doors out of the list. Omitted by the model: it closed the pact, dropped
        // like a thread, and the outcome is in parsed.facts already. Kept but past its
        // horizon: the clock closed it, and it graduates into facts -- the stood-up case.
        // In that order, so a lapse is recorded only when nobody noticed it.
        i = 0;
        while i < ArraySize(parsed.pacts) {
            let text = AiNpcMemoryClampEntry(parsed.pacts[i].text);
            if NotEquals(StrLen(text), 0) {
                // A restated agreement keeps its original stamp: re-stamping would reset the
                // clock every time it was mentioned, so the pact they keep bringing up --
                // the one that most needs to lapse -- never would.
                let existing = AiNpcMemoryFindPact(before.pacts, text);
                let openedAt = coveredUpTo;
                if IsDefined(existing) {
                    openedAt = existing.openedAt;
                }
                // The horizon comes from the new answer: tonight moved to next week is a
                // legitimate renegotiation.
                let pact = AiNpcMemoryPactNew(text, openedAt, parsed.pacts[i].horizon);
                if AiNpcMemoryPactLapsed(pact, coveredUpTo) {
                    ArrayPush(result.facts, text);
                } else {
                    ArrayPush(result.pacts, pact);
                }
            }
            i += 1;
        }

        // The chronicle covers the archive as it was when the request went out, which is
        // `before`. Facts evicted by the clamp below land past that mark and wait for the
        // next fold: they were not in the material the model read. Computed here rather
        // than passed in, so there is no argument for a caller to get wrong.
        if NotEquals(StrLen(AiNpcMemoryTrim(parsed.chronicle)), 0) {
            result.chronicle = parsed.chronicle;
            result.chronicleUpTo = ArraySize(before.archive);
        }

        result.tone = parsed.tone;
    }

    if Equals(StrLen(AiNpcMemoryTrim(result.tone)), 0) {
        result.tone = before.tone;
    }

    // Established once, never revised: recomputing it later would let a fact become founding
    // purely by outliving the others, which is the rule this exists to escape.
    result.founding = before.founding;
    if Equals(result.founding, 0) && ArraySize(result.facts) > 0 {
        result.founding = ArraySize(result.facts);
        if result.founding > AiNpcMemoryFoundingFacts() {
            result.founding = AiNpcMemoryFoundingFacts();
        }
    }

    result.coveredUpTo = coveredUpTo;
    return AiNpcMemoryClamp(result);
}

// The facts `live` holds that `base` never had, in the order they were recorded. Named
// rather than inlined so the lane reports the same number it acts on: counting the
// difference in list sizes is wrong as soon as SeedIfEmpty or the clamp changes a length.
func AiNpcMemoryFactsSince(base: ref<AiNpcMemory>, live: ref<AiNpcMemory>) -> array<String> {
    let result: array<String>;
    if !IsDefined(live) {
        return result;
    }

    // Bound to locals first: ArrayContains takes its operand by reference, and indexing a
    // call result reads empty. AiNpcConversationStore.RecordFact answered false every time
    // until it did the same.
    let liveFacts = live.facts;
    let baseFacts: array<String>;
    if IsDefined(base) {
        baseFacts = base.facts;
    }

    let i = 0;
    while i < ArraySize(liveFacts) {
        if !ArrayContains(baseFacts, liveFacts[i]) && !ArrayContains(result, liveFacts[i]) {
            ArrayPush(result, liveFacts[i]);
        }
        i += 1;
    }
    return result;
}

// Facts recorded while the compaction was in flight, folded back into its answer.
//
// The race: a compaction captures the memory it summarises when it sends
// (AiNpcMemoryService.m_base) and writes the merge back seconds later, while AiNpcRecordFact
// writes to the same list off a gameplay event. A fact recorded inside that window was
// stored, read back as kept, then overwritten -- and silently, since RecordFact had returned
// true and the caller never fell back on the transient channel.
//
// Carried rather than abandoned: the summary is incomplete, not invalid. Appended last, as
// RecordFact appends, so what the game just observed is the last thing eviction takes.
func AiNpcMemoryRebase(merged: ref<AiNpcMemory>, base: ref<AiNpcMemory>,
        live: ref<AiNpcMemory>) -> ref<AiNpcMemory> {
    let result = AiNpcMemoryCopy(merged);
    let since = AiNpcMemoryFactsSince(base, live);

    let carried = 0;
    let i = 0;
    while i < ArraySize(since) {
        let text = since[i];
        // Not in the archive either: pulling an evicted fact back out would undo the
        // forgetting on every subsequent compaction.
        if !ArrayContains(result.facts, text) && !ArrayContains(result.archive, text) {
            ArrayPush(result.facts, text);
            carried += 1;
        }
        i += 1;
    }

    // Only when something was carried. `coveredUpTo` is what the block renders as "the most
    // recent of it was ...", and it would otherwise date a summary that stops short of the
    // fact just folded in.
    if carried > 0 && IsDefined(live) && live.coveredUpTo > result.coveredUpTo {
        result.coveredUpTo = live.coveredUpTo;
    }

    return AiNpcMemoryClamp(result);
}

func AiNpcMemoryThreadAge(threads: array<ref<AiNpcMemoryThread>>, text: String) -> Int32 {
    let i = 0;
    while i < ArraySize(threads) {
        if Equals(threads[i].text, text) {
            return threads[i].age;
        }
        i += 1;
    }
    return 0;
}

/// Rendering ///

// The <memory> block, or "" when there is nothing to say. Rendered from the structure every
// time rather than stored: a stored rendering would be a second copy to keep in agreement.
// The header line names the memory as a memory -- without it the model reads the block as
// more instructions and answers them.
func AiNpcMemoryRender(memory: ref<AiNpcMemory>) -> String {
    return AiNpcMemoryRenderAt(memory, AiNpcTimeUnknown());
}

// The same, dated against a clock the caller reads and hands in, so this stays pure and a
// memory can be rendered in a test without a session. "3 days ago" rather than a timestamp;
// a memory with no stamp says nothing, since a wrong "ago" is worse than no "ago".
//
// Every part, which is what a null recipe asks for -- see AiNpcRecipe.reds.
func AiNpcMemoryRenderAt(memory: ref<AiNpcMemory>, nowSeconds: Int32) -> String {
    return AiNpcMemoryRenderParts(memory, nowSeconds, null);
}

// The block a recipe asked for. The parts are the sections a compaction produces, so a player
// trimming the prompt trims what the model wrote rather than a shape invented here.
//
// THE HEADER IS NOT A PART. It names the memory as a memory, and a block that arrives without
// it is read as more instructions and answered; its second sentence states precedence over the
// character description, which is what stops a persona's "you do not know V's age" outranking
// the age V gave three hundred messages ago. So it is emitted whenever anything else is, and
// no recipe can drop it -- but it is not emitted ALONE either, which is why the sections are
// built first and the header prepended to them.
func AiNpcMemoryRenderParts(memory: ref<AiNpcMemory>, nowSeconds: Int32,
                            recipe: ref<AiNpcRecipe>) -> String {
    if AiNpcMemoryIsEmpty(memory) {
        return "";
    }

    let body = "";

    // Oldest and blurriest first, then the sharp lines, then the live loops: resolution
    // improves as the block approaches the present.
    if AiNpcRecipeWants(recipe, "memory", "chronicle") && NotEquals(StrLen(memory.chronicle), 0) {
        body += AiNpcMemorySectionChronicle() + " " + memory.chronicle + "\n";
    }

    let i = 0;
    if AiNpcRecipeWants(recipe, "memory", "facts") && ArraySize(memory.facts) > 0 {
        body += AiNpcMemorySectionFacts() + "\n";
        while i < ArraySize(memory.facts) {
            body += "- " + memory.facts[i] + "\n";
            i += 1;
        }
    }

    if AiNpcRecipeWants(recipe, "memory", "open") && ArraySize(memory.threads) > 0 {
        body += AiNpcMemorySectionOpen() + "\n";
        i = 0;
        while i < ArraySize(memory.threads) {
            body += "- " + memory.threads[i].text + "\n";
            i += 1;
        }
    }

    if AiNpcRecipeWants(recipe, "memory", "agreed") && ArraySize(memory.pacts) > 0 {
        body += AiNpcMemorySectionAgreed() + "\n";
        i = 0;
        while i < ArraySize(memory.pacts) {
            // Computed here, not stored: an agreement can fall due while the phone is shut,
            // and rendering is the only moment it is guaranteed to be read. The marker is
            // English like the section headers; the entry stays in the conversation's
            // language.
            let marker = "";
            if AiNpcMemoryPactLapsed(memory.pacts[i], nowSeconds) {
                marker = "(overdue) ";
            }
            body += "- " + marker + memory.pacts[i].text + "\n";
            i += 1;
        }
    }

    if AiNpcRecipeWants(recipe, "memory", "tone") && NotEquals(StrLen(memory.tone), 0) {
        body += AiNpcMemorySectionTone() + " " + memory.tone + "\n";
    }

    if Equals(StrLen(body), 0) {
        return "";
    }

    // The second sentence states precedence over the character description, and it is
    // load-bearing. Measured in journal.b18, contact anon_259272939: the character asked V's
    // age at message 5, was told "27 ans", and asked again at 97 and 113. The fact was in
    // this block every time; the persona said "tu ne connais ni son nom, ni son quartier, ni
    // son age", and that text sits in the cacheable prefix ahead of everything. A persona
    // should be allowed to say what its character does not know -- this sentence makes it
    // mean "not yet".
    let result = "What you remember of earlier conversations with V. Not a script: recall it the way a person does, only when it is relevant.\n"
        + "Everything below is something you ALREADY KNOW. Never ask V about it again. Where your character description says you do not know something and this block does, this block is right: the description is how you began, and this is what has happened since.\n";

    let elapsed = AiNpcFormatElapsedGameTime(memory.coveredUpTo, nowSeconds);
    if NotEquals(StrLen(elapsed), 0) {
        result += "The most recent of it was " + elapsed + ".\n";
    }

    return result + body;
}

/// The compaction request ///

// What the thinking lane asks for. Out of character on purpose: a summariser that stays in
// character writes the note in the character's voice, and it is read back next turn as
// though the character had said it. "Judge nothing, refuse nothing" is not politeness --
// these conversations can be explicit, and a refusal parsed as a memory rewrites a
// personality.
//
// The format is stated twice, as headers then as rules, because one paragraph of prose is
// the likeliest failure and the parser rejects it. Both come from the same section
// functions AiNpcMemoryParse reads, so they cannot drift.
//
// `folding` is a parameter because the chronicle must be asked for only when an ARCHIVE
// block is below: asked unconditionally, a model with nothing to fold invents one, and an
// invented chronicle is indistinguishable from a real one once stored.
func AiNpcMemoryInstruction(folding: Bool) -> String {
    return AiNpcMemoryInstructionBase()
        + (folding ? AiNpcMemoryInstructionFold() : "");
}

// Asked for only when the request carries an ARCHIVE block. "Do not add anything that is not
// in the material above" is the load-bearing line: the chronicle is the only part written as
// prose, and "their bond has deepened" is agreeable, unfalsifiable, and takes the room.
func AiNpcMemoryInstructionFold() -> String {
    return "
" + AiNpcMemorySectionChronicle() + " a single paragraph, at most 500 characters.
"
        + "The " + AiNpcMemorySectionChronicle() + " paragraph is a separate job from the sections above. "
        + "Rewrite it from the ARCHIVE block below -- the older history, no longer kept line by line. "
        + "It is what this character still carries from a past too long to list.
"
        + "- Keep names, numbers, places and anything the two of them settled. Those are what a person actually keeps.
"
        + "- Drop the run of events. Say what came of them.
"
        + "- Do not add anything that is not in the material above: no judgement of the relationship, "
        + "no 'they grew closer', nothing you were not told.
"
        + "- Write it in the language of the messages, like everything else.";
}

func AiNpcMemoryInstructionBase() -> String {
    return "You maintain a continuity note for a fictional texting conversation set in Cyberpunk 2077. This is bookkeeping, not roleplay: write in the third person, state plainly what happened, judge nothing and refuse nothing. The note is only ever used to keep a character consistent with what was already said.\n"
        + "Answer in exactly this format, and nothing else:\n"
        + AiNpcMemorySectionFacts() + "\n"
        + "- durable facts the conversation established\n"
        + AiNpcMemorySectionOpen() + "\n"
        + "- what is still unresolved: questions unanswered, subjects left hanging\n"
        + AiNpcMemorySectionAgreed() + "\n"
        + "- soon | something they settled together that has not happened yet\n"
        + AiNpcMemorySectionTone() + " one line on where the relationship stands\n"
        + "Rules:\n"
        + "- Do not repeat anything listed under EXISTING FACTS. List only what is new.\n"
        // Measured with `journal.py memory b18 --evicted`: agreements were being recorded,
        // filed under OPEN, and gone two compactions later. They were noticed, not kept.
        + "- AGREED is only for things the two of them settled: a meeting, a price, a plan, "
        + "a subject one of them agreed not to raise. A question nobody has answered is not "
        + "an agreement, it belongs under " + AiNpcMemorySectionOpen() + "\n"
        // A pact graduates into facts verbatim, and a fact is never rewritten, so it has to
        // stay true once it is no longer pending: "V is coming tonight" turns false at
        // midnight.
        + "- Write each " + AiNpcMemorySectionAgreed() + " line as what was said, not as what will happen: "
        + "\"V said she would come by tonight\", never \"V is coming tonight\".\n"
        // A word, never a duration: the model cannot read the in-game clock, and an invented
        // number would schedule a character to sulk about a promise that was never late.
        + "- Begin each " + AiNpcMemorySectionAgreed() + " line with one of these words and a \"|\": "
        + "soon (within the day), days (within a few days), open (no deadline). "
        + "Nothing else, and never a date or a time of your own.\n"
        + "- Rewrite the agreements in full, like the open threads: leave out the ones that "
        + "have now happened or been called off.\n"
        + "- At most four lines per section, one sentence each.\n"
        // Facts are evicted one at a time, so a line leaning on its neighbour breaks when
        // that neighbour ages out: "he came round in the end" loses its subject once "she
        // told him what she does for a living" is gone.
        + "- Each line must stand on its own, understandable without the other lines: name who and what, do not write \"it\" or \"that\" pointing at another line.\n"
        + "- Rewrite the open threads in full: leave out the ones that are now resolved. Leaving one out is how it is closed.\n"
        // Measured on a real batch: without this line, a question answered later in the same
        // batch was still filed as open, and the character spent a whole window raising
        // something settled in front of it.
        + "- Judge each thread as of the LAST message below, not as of where it was raised. A question answered later in these same messages is resolved, not open.\n"
        // Measured on a real batch: V asked "t'es un mec ?", the character answered "ouais,
        // un mec", and the note came back "V est un homme". The speaker labels were in the
        // transcript; what was missing was a rule saying they outrank the content. The other
        // half of the fix is the WHO IS WHO block in the request body.
        + "- Every line is prefixed with the name of whoever said it. Attribute each statement to that speaker and no other: a question one of them asks is not a fact about the other, and an answer belongs to whoever prefixes it.\n"
        + "- The WHO IS WHO block is ground truth. Never revise it, and never record a fact that contradicts it.\n"
        // The instruction is in English and the model was only following the transcript;
        // saying it makes the behaviour a rule rather than luck.
        + "- Write the note in the language of the messages below.\n"
        + "- No preamble, no commentary, no explanation of what you did.";
}

// The material it works from: what is already remembered, then the batch that fell out of
// the window. Existing facts are read-only -- the instruction forbids repeating them --
// which stops the memory being re-summarised from itself every ten turns. Threads are handed
// over to be rewritten, because closing one is only expressible as not writing it again.
//
// `vGender` is a plain sentence ("V is a woman."), or "" when nothing is known. Passed in,
// because this file is held free of game calls.
func AiNpcMemoryRequestBody(previous: ref<AiNpcMemory>, npcName: String, vGender: String,
        transcript: String, exact: Bool) -> String {
    let result = "";

    // The archive block, where the whole cost of the feature sits. `exact` picks the slice
    // and nothing else differs: exact sends the entire archive and no previous chronicle, so
    // the paragraph cannot inherit an error from the one before it; incremental sends the
    // previous chronicle plus what was archived since, O(1) and drifting.
    if IsDefined(previous) && AiNpcMemoryShouldFold(previous) {
        let from = AiNpcMemoryChronicleFrom(previous, exact);
        if !exact && NotEquals(StrLen(previous.chronicle), 0) {
            result += AiNpcMemorySectionChronicle() + " " + previous.chronicle + "
";
        }
        result += "ARCHIVE (older history, fold it into the "
            + AiNpcMemorySectionChronicle() + " paragraph):
";
        let a = from;
        while a < ArraySize(previous.archive) {
            result += "- " + previous.archive[a] + "
";
            a += 1;
        }
        result += "
";
    }

    if IsDefined(previous) && ArraySize(previous.facts) > 0 {
        result += "EXISTING FACTS (already recorded, do not repeat):\n";
        let i = 0;
        while i < ArraySize(previous.facts) {
            result += "- " + previous.facts[i] + "\n";
            i += 1;
        }
    }

    if IsDefined(previous) && ArraySize(previous.threads) > 0 {
        result += AiNpcMemorySectionOpen() + "\n";
        let i = 0;
        while i < ArraySize(previous.threads) {
            result += "- " + previous.threads[i].text + "\n";
            i += 1;
        }
    }

    // Handed over to be rewritten, like the threads: an agreement is closed by not writing it
    // again. The horizon word goes back out in the shape it came in, so a pact the model
    // wants to leave alone can be copied straight across.
    if IsDefined(previous) && ArraySize(previous.pacts) > 0 {
        result += AiNpcMemorySectionAgreed() + "\n";
        let i = 0;
        while i < ArraySize(previous.pacts) {
            result += "- " + AiNpcMemoryPactHorizonWord(previous.pacts[i].horizon) + " | "
                + previous.pacts[i].text + "\n";
            i += 1;
        }
    }

    if IsDefined(previous) && NotEquals(StrLen(previous.tone), 0) {
        result += AiNpcMemorySectionTone() + " " + previous.tone + "\n";
    }

    // The roleplay lane is told V's gender in the system prompt; this one was told nothing,
    // and inferred it from dialogue that can contain the question and the answer side by
    // side.
    result += "\nWHO IS WHO (ground truth, not to be revised from the messages):\n";
    result += "- V is the player. Every line beginning \"V: \" is V speaking.\n";
    if NotEquals(StrLen(vGender), 0) {
        result += "- " + vGender + "\n";
    }
    result += "- " + npcName + " is the character. Every line beginning \"" + npcName
        + ": \" is " + npcName + " speaking.\n";

    result += "\nNEW MESSAGES:\n";
    result += transcript;
    return result;
}

/// Parsing ///

// Shared by the request renderer and the answer parser. Named rather than written twice:
// the two have to agree exactly, and nothing else would catch it if they stopped.
func AiNpcMemorySectionFacts() -> String {
    return "FACTS:";
}

func AiNpcMemorySectionOpen() -> String {
    return "OPEN:";
}

func AiNpcMemorySectionAgreed() -> String {
    return "AGREED:";
}

func AiNpcMemorySectionChronicle() -> String {
    return "CHRONICLE:";
}

func AiNpcMemorySectionTone() -> String {
    return "TONE:";
}

// Reads a compaction reply into the typed model, or null when the answer is not one. Null is
// the guard the feature rests on: an apology, a refusal or a chunk of prose carries no
// section header and is rejected. A refusal stored as memory is a bug nobody diagnoses --
// the character just starts behaving as though it had been told to be careful, forever.
func AiNpcMemoryParse(text: String) -> ref<AiNpcMemory> {
    let lines = StrSplit(AiNpcReplaceAll(text, "\r\n", "\n"), "\n");
    let result = AiNpcMemoryNew();
    let section = 0;        // 0 none, 1 facts, 2 open, 3 agreed, 4 chronicle
    let sawSection = false;

    let i = 0;
    while i < ArraySize(lines) {
        let line = AiNpcMemoryTrim(lines[i]);
        i += 1;

        if StrBeginsWith(line, AiNpcMemorySectionFacts()) {
            section = 1;
            sawSection = true;
        } else if StrBeginsWith(line, AiNpcMemorySectionOpen()) {
            section = 2;
            sawSection = true;
        } else if StrBeginsWith(line, AiNpcMemorySectionAgreed()) {
            section = 3;
            sawSection = true;
        } else if StrBeginsWith(line, AiNpcMemorySectionTone()) {
            section = 0;
            sawSection = true;
            result.tone = AiNpcMemoryTrim(StrRight(line, StrLen(line) - StrLen(AiNpcMemorySectionTone())));
        } else if StrBeginsWith(line, AiNpcMemorySectionChronicle()) {
            // Single-valued like TONE, but section 4 rather than 0 so a paragraph wrapped
            // onto a second line is still collected: prose is the one section where a line
            // break is expected rather than a formatting slip.
            section = 4;
            sawSection = true;
            result.chronicle = AiNpcMemoryTrim(StrRight(line, StrLen(line) - StrLen(AiNpcMemorySectionChronicle())));
        } else if section > 0 {
            // A bullet outside any section is dropped, not guessed at: filing it under facts
            // would make an unparseable answer permanent.
            let entry = AiNpcMemoryStripBullet(line);
            if NotEquals(StrLen(entry), 0) {
                if Equals(section, 1) {
                    ArrayPush(result.facts, entry);
                } else if Equals(section, 4) {
                    // A continuation line of the paragraph. Joined with a space rather than
                    // a newline: the chronicle renders as one line of the block.
                    //
                    // The raw line, not `entry`: the bullet stripper also clamps to the
                    // per-ENTRY cap, and a paragraph is not an entry. Running it here would
                    // plant an ellipsis in the middle of a chronicle that is nowhere near
                    // its own, wider cap.
                    if NotEquals(StrLen(result.chronicle), 0) {
                        result.chronicle += " ";
                    }
                    result.chronicle += AiNpcMemoryTrim(line);
                } else if Equals(section, 3) {
                    // openedAt is left unknown: only AiNpcMemoryMerge knows when the batch
                    // ended, and only it can tell a new agreement from a restated one.
                    ArrayPush(result.pacts, AiNpcMemoryParsePact(entry));
                } else {
                    ArrayPush(result.threads, AiNpcMemoryThreadNew(entry, 0));
                }
            }
        }
    }

    if !sawSection {
        return null;
    }
    return AiNpcMemoryClamp(result);
}

// "soon | V said she would come by tonight" -> a pact, opened at an unknown time. The
// separator is optional: a model that ignores the prefix has still reported an agreement,
// and the line becomes OPEN, which never lapses.
func AiNpcMemoryParsePact(entry: String) -> ref<AiNpcMemoryPact> {
    let bar = StrFindFirst(entry, "|");
    if bar > 0 {
        let word = StrLeft(entry, bar);
        let horizon = AiNpcMemoryPactHorizonOf(word);
        // Only strip the prefix when it was one of the three words: otherwise the bar
        // belonged to the sentence, and cutting there would eat half the agreement.
        if NotEquals(horizon, AiNpcMemoryPactOpen()) || Equals(AiNpcMemoryTrim(word), "open")
                || Equals(AiNpcMemoryTrim(word), "OPEN") {
            let text = AiNpcMemoryTrim(StrRight(entry, StrLen(entry) - bar - 1));
            if NotEquals(StrLen(text), 0) {
                return AiNpcMemoryPactNew(text, AiNpcTimeUnknown(), horizon);
            }
        }
    }
    return AiNpcMemoryPactNew(entry, AiNpcTimeUnknown(), AiNpcMemoryPactOpen());
}

// "- thing", "* thing", "1. thing" and bare "thing" all mean the same thing here. Models
// pick a bullet style of their own and changing it must not empty a memory.
func AiNpcMemoryStripBullet(line: String) -> String {
    let result = line;
    if StrBeginsWith(result, "- ") || StrBeginsWith(result, "* ") {
        result = StrRight(result, StrLen(result) - 2);
    } else {
        if StrBeginsWith(result, "-") || StrBeginsWith(result, "*") {
            result = StrRight(result, StrLen(result) - 1);
        }
    }
    return AiNpcMemoryClampEntry(result);
}

/// Windowing ///

func AiNpcMemoryShouldCompact(messages: array<ref<AiNpcMessage>>) -> Bool {
    return ArraySize(messages) > AiNpcMemoryMaxTurns() * 2;
}

// Answered when the conversation is next opened, never on a timer: a DelayCallback does not
// survive a save. The gap is measured from the last message, not the last stamped one --
// reaching further back for a stamp would report a silence that never happened on a
// conversation active seconds ago. Unstamped is unknown, and unknown declines.
func AiNpcMemoryShouldCompactIdle(messages: array<ref<AiNpcMessage>>, nowSeconds: Int32) -> Bool {
    let size = ArraySize(messages);
    if size <= 0 || Equals(nowSeconds, AiNpcTimeUnknown()) {
        return false;
    }

    let last = messages[size - 1];
    if !AiNpcMessageHasTime(last) {
        return false;
    }

    // Also covers a clock read backwards across a reload: a negative gap is not a silence.
    if (nowSeconds - last.gameTimeSeconds) < AiNpcMemoryIdleGapSeconds() {
        return false;
    }

    let evicted = AiNpcMemoryEvicted(messages);
    return ArraySize(evicted) >= AiNpcMemoryIdleMinBatch();
}

// What stays verbatim in the prompt. Defined as the existing trim rather than a new rule, so
// "never open the window on a reply" has one implementation.
func AiNpcMemoryKept(messages: array<ref<AiNpcMessage>>) -> array<ref<AiNpcMessage>> {
    return AiNpcHistoryTrim(messages, AiNpcMemoryWindowTurns());
}

// What the compaction absorbs: everything the window leaves behind, in order.
func AiNpcMemoryEvicted(messages: array<ref<AiNpcMessage>>) -> array<ref<AiNpcMessage>> {
    let result: array<ref<AiNpcMessage>>;
    // Bound to a local before ArraySize touches it: the intrinsics take their operand by
    // reference, and a call result is a temporary with no stable slot. It compiles and reads
    // the wrong one; tools\lint.ps1 fails the build over it.
    let kept = AiNpcMemoryKept(messages);
    let cut = ArraySize(messages) - ArraySize(kept);

    let i = 0;
    while i < cut {
        ArrayPush(result, messages[i]);
        i += 1;
    }
    return result;
}

// The last stamp the batch carries, or the previous coverage when it carries none. Never a
// guess: an unstamped batch leaves the coverage where it was.
func AiNpcMemoryCoverage(previous: Int32, evicted: array<ref<AiNpcMessage>>) -> Int32 {
    let last = AiNpcHistoryLastTime(evicted);
    if Equals(last, AiNpcTimeUnknown()) {
        return previous;
    }
    return last;
}

/// Serialization ///

func AiNpcMemoryToJson(memory: ref<AiNpcMemory>) -> ref<JsonObject> {
    let root = ParseJson("{}") as JsonObject;
    if !IsDefined(memory) {
        return root;
    }

    let facts = ParseJson("[]") as JsonArray;
    let i = 0;
    while i < ArraySize(memory.facts) {
        facts.AddItemString(memory.facts[i]);
        i += 1;
    }
    root.SetKey("f", facts);

    let threads = ParseJson("[]") as JsonArray;
    i = 0;
    while i < ArraySize(memory.threads) {
        let entry = ParseJson("{}") as JsonObject;
        entry.SetKeyString("t", memory.threads[i].text);
        entry.SetKeyInt64("a", Cast<Int64>(memory.threads[i].age));
        threads.AddItem(entry);
        i += 1;
    }
    root.SetKey("o", threads);

    // Omitted when empty: a conversation that has settled nothing is the common case, and an
    // empty "p" on every snapshot would grow the journal for nothing.
    if ArraySize(memory.pacts) > 0 {
        let pacts = ParseJson("[]") as JsonArray;
        i = 0;
        while i < ArraySize(memory.pacts) {
            let entry = ParseJson("{}") as JsonObject;
            entry.SetKeyString("t", memory.pacts[i].text);
            entry.SetKeyInt64("h", Cast<Int64>(memory.pacts[i].horizon));
            if NotEquals(memory.pacts[i].openedAt, AiNpcTimeUnknown()) {
                entry.SetKeyInt64("s", Cast<Int64>(memory.pacts[i].openedAt));
            }
            pacts.AddItem(entry);
            i += 1;
        }
        root.SetKey("p", pacts);
    }

    // The archive rides in the snapshot like everything else: a snapshot is the whole state
    // rewritten, which is what makes fork, atomicity and the offline repair tool work
    // without a special case. Accumulating it at replay time would save bytes and break that.
    if ArraySize(memory.archive) > 0 {
        let archive = ParseJson("[]") as JsonArray;
        i = 0;
        while i < ArraySize(memory.archive) {
            archive.AddItemString(memory.archive[i]);
            i += 1;
        }
        root.SetKey("ar", archive);
        if memory.chronicleUpTo > 0 {
            root.SetKeyInt64("cu", Cast<Int64>(memory.chronicleUpTo));
        }
    }
    if NotEquals(StrLen(memory.chronicle), 0) {
        root.SetKeyString("ch", memory.chronicle);
    }

    root.SetKeyString("n", memory.tone);
    if memory.founding > 0 {
        root.SetKeyInt64("fd", Cast<Int64>(memory.founding));
    }
    if NotEquals(memory.coveredUpTo, AiNpcTimeUnknown()) {
        root.SetKeyInt64("g", Cast<Int64>(memory.coveredUpTo));
    }
    return root;
}

// Clamped on the way in, not merely on the way out: this is the boundary where a
// hand-edited file or a journal written by another build arrives.
func AiNpcMemoryFromJson(json: ref<JsonObject>) -> ref<AiNpcMemory> {
    let result = AiNpcMemoryNew();
    if !IsDefined(json) {
        return result;
    }

    let facts = AiNpcJsonArrayAt(json, "f");
    if IsDefined(facts) {
        let i: Uint32 = 0u;
        while i < facts.GetSize() {
            let item = facts.GetItem(i);
            if IsDefined(item) && item.IsString() {
                ArrayPush(result.facts, item.GetString());
            }
            i += 1u;
        }
    }

    let threads = AiNpcJsonArrayAt(json, "o");
    if IsDefined(threads) {
        let i: Uint32 = 0u;
        while i < threads.GetSize() {
            let entry = AiNpcJsonItemObject(threads, i);
            if IsDefined(entry) {
                ArrayPush(result.threads,
                    AiNpcMemoryThreadNew(entry.GetKeyString("t"), Cast<Int32>(entry.GetKeyInt64("a"))));
            }
            i += 1u;
        }
    }

    // Absent from snapshots written before agreements existed: such a memory has none, and
    // the next compaction is free to record some.
    let pacts = AiNpcJsonArrayAt(json, "p");
    if IsDefined(pacts) {
        let i: Uint32 = 0u;
        while i < pacts.GetSize() {
            let entry = AiNpcJsonItemObject(pacts, i);
            if IsDefined(entry) {
                let openedAt = AiNpcTimeUnknown();
                if entry.HasKey("s") {
                    openedAt = Cast<Int32>(entry.GetKeyInt64("s"));
                }
                ArrayPush(result.pacts, AiNpcMemoryPactNew(entry.GetKeyString("t"), openedAt,
                    Cast<Int32>(entry.GetKeyInt64("h"))));
            }
            i += 1u;
        }
    }

    // Absent from snapshots written before the archive existed: such a memory starts its
    // archive empty, which is the behaviour that build had.
    let archive = AiNpcJsonArrayAt(json, "ar");
    if IsDefined(archive) {
        let i: Uint32 = 0u;
        while i < archive.GetSize() {
            let item = archive.GetItem(i);
            if IsDefined(item) && item.IsString() {
                ArrayPush(result.archive, item.GetString());
            }
            i += 1u;
        }
    }
    result.chronicle = AiNpcJsonString(json, "ch");
    result.chronicleUpTo = 0;
    if json.HasKey("cu") {
        result.chronicleUpTo = Cast<Int32>(json.GetKeyInt64("cu"));
    }

    result.tone = AiNpcJsonString(json, "n");
    result.founding = 0;
    if json.HasKey("fd") {
        result.founding = Cast<Int32>(json.GetKeyInt64("fd"));
    }
    result.coveredUpTo = AiNpcTimeUnknown();
    if json.HasKey("g") {
        result.coveredUpTo = Cast<Int32>(json.GetKeyInt64("g"));
    }
    return AiNpcMemoryClamp(result);
}
