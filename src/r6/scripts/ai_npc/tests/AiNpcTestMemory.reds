module AiNpc

import RedData.Json.*

// Ce que devient une conversation qui sort de la fenetre.
//
// Une part des tests de demarrage -- voir tests\AiNpcTestRollCall.reds pour l'appel,
// et tests\AiNpcTestSuite.reds pour la raison d'etre du dossier.

// A memory built in one expression, for assertions that care about one slot at a time.
func AiNpcTestMemory(facts: array<String>, threads: array<String>, tone: String) -> ref<AiNpcMemory> {
    let memory = AiNpcMemoryNew();
    let i = 0;
    while i < ArraySize(facts) {
        ArrayPush(memory.facts, facts[i]);
        i += 1;
    }
    i = 0;
    while i < ArraySize(threads) {
        ArrayPush(memory.threads, AiNpcMemoryThreadNew(threads[i], 0));
        i += 1;
    }
    memory.tone = tone;
    return memory;
}

// "a|b" over the facts, "a|b" over the threads: the same compact rendering AiNpcTestRender
// gives a history, so a mismatch reads as a diff rather than as a count.

// "a|b" over the facts, "a|b" over the threads: the same compact rendering AiNpcTestRender
// gives a history, so a mismatch reads as a diff rather than as a count.
func AiNpcTestFacts(memory: ref<AiNpcMemory>) -> String {
    let result = "";
    let i = 0;
    while i < ArraySize(memory.facts) {
        if i > 0 {
            result += "|";
        }
        result += memory.facts[i];
        i += 1;
    }
    return result;
}

func AiNpcTestPacts(memory: ref<AiNpcMemory>) -> String {
    let result = "";
    let i = 0;
    while i < ArraySize(memory.pacts) {
        if i > 0 {
            result += "|";
        }
        result += AiNpcMemoryPactHorizonWord(memory.pacts[i].horizon) + ":" + memory.pacts[i].text;
        i += 1;
    }
    return result;
}

func AiNpcTestThreads(memory: ref<AiNpcMemory>) -> String {
    let result = "";
    let i = 0;
    while i < ArraySize(memory.threads) {
        if i > 0 {
            result += "|";
        }
        result += memory.threads[i].text;
        i += 1;
    }
    return result;
}

func AiNpcTestMemoryPolicy(t: ref<AiNpcTestRunner>) -> Void {
    // The derivation is the point: stating the steady-state bound anywhere else would let
    // it disagree with the two numbers it is made of.
    t.EqInt("memory/max is window plus batch", AiNpcMemoryMaxTurns(),
        AiNpcMemoryWindowTurns() + AiNpcMemoryBatchTurns());

    // The backstop must sit ABOVE the compaction threshold, or the trim destroys batches
    // before the lane has a chance to retry one.
    t.Check("memory/backstop above steady state", AiNpcMemoryHardMaxTurns() > AiNpcMemoryMaxTurns());

    // The slider's bounds. Asserted on the pure clamp rather than on the field, so this runs
    // the same whatever the menu currently holds.
    t.EqInt("memory/budget floor", AiNpcMemoryClampFactBudget(0), 8);
    t.EqInt("memory/budget floor from below", AiNpcMemoryClampFactBudget(-40), 8);
    t.EqInt("memory/budget ceiling", AiNpcMemoryClampFactBudget(9000), 40);
    t.EqInt("memory/budget passes a legal value", AiNpcMemoryClampFactBudget(32), 32);
    t.EqInt("memory/default is a legal value",
        AiNpcMemoryClampFactBudget(AiNpcMemoryDefaultMaxFacts()), AiNpcMemoryDefaultMaxFacts());

    // THE invariant the floor exists for: eviction starts after the founding prefix, so a
    // budget that does not clear it leaves AiNpcMemoryClamp evicting the identity of the
    // relationship instead of its oldest episode. Stated against the clamped floor, which is
    // the smallest budget any code path can ever see.
    t.Check("memory/budget floor clears the founding prefix",
        AiNpcMemoryClampFactBudget(0) > AiNpcMemoryFoundingFacts());

    // The cap in force is always one the clamp would accept -- this is what says the
    // accessor cannot hand a raw field value to the compaction.
    t.EqInt("memory/cap in force is clamped",
        AiNpcMemoryMaxFacts(), AiNpcMemoryClampFactBudget(AiNpcMemoryMaxFacts()));
}

func AiNpcTestMemoryClamp(t: ref<AiNpcTestRunner>) -> Void {
    let long = "";
    let i = 0;
    while i < AiNpcMemoryMaxEntryChars() + 40 {
        long += "x";
        i += 1;
    }

    let memory = AiNpcMemoryNew();
    ArrayPush(memory.facts, long);
    let clamped = AiNpcMemoryClamp(memory);
    t.Check("memory/entry truncated within the cap", StrLen(clamped.facts[0]) <= AiNpcMemoryMaxEntryChars());

    // A cut has to LOOK like a cut. A fact is never rewritten, so a truncation that stays
    // grammatical is a permanent false statement -- the ellipsis is what stops the model
    // reading half a sentence as a whole one.
    t.Check("memory/a truncated entry says so", StrEndsWith(clamped.facts[0], "..."));

    let sentence = "V a decide de ne pas arreter, et elle l'a dit franchement a River pendant une conversation qui a dure toute la soiree, sans jamais se justifier ni demander la permission, parce que c'est sa vie et son corps et pas celui de quelqu'un d'autre.";
    let cutMemory = AiNpcMemoryNew();
    ArrayPush(cutMemory.facts, sentence);
    // Bound to a local before indexing: `AiNpcMemoryClamp(cutMemory).facts[0]` indexes an
    // array field of a temporary with no stable stack slot -- the same trap as ArraySize on a
    // call result, which lint check 8 exists for. It compiles, emits no warning, and reads
    // back empty.
    let clamped = AiNpcMemoryClamp(cutMemory);
    let cut = clamped.facts[0];
    t.Check("memory/the cut lands on a word boundary", !StrContains(cut, " ..."));
    // Asserted as an equality rather than as a StrBeginsWith, so a failure carries the text
    // that was actually produced. This one has been failing on and off, and a bare false
    // says nothing about whether the cut landed in the wrong place or the entry was dropped
    // before it was ever cut -- which are opposite bugs.
    let expectedStart = "V a decide de ne pas arreter";
    t.EqString("memory/the cut keeps the start intact", StrLeft(cut, StrLen(expectedStart)), expectedStart);

    // Duplicates and blanks: a model that restates a fact must not make it count twice
    // against the cap, and an empty bullet must not occupy a slot.
    let dupes = AiNpcTestMemory(["owes V 500 eddies", "owes V 500 eddies", "", "   "], [], "");
    t.EqString("memory/facts deduped and blanks dropped", AiNpcTestFacts(AiNpcMemoryClamp(dupes)),
        "owes V 500 eddies");

    // Overflow drops the OLDEST. That is the forgetting the whole design is imitating.
    let many = AiNpcMemoryNew();
    i = 0;
    while i < AiNpcMemoryMaxFacts() + 2 {
        ArrayPush(many.facts, s"fact \(i)");
        i += 1;
    }
    let capped = AiNpcMemoryClamp(many);
    t.EqInt("memory/facts capped", ArraySize(capped.facts), AiNpcMemoryMaxFacts());
    t.EqString("memory/oldest fact evicted first", capped.facts[0], "fact 2");

    let threads = AiNpcMemoryNew();
    i = 0;
    while i < AiNpcMemoryMaxThreads() + 3 {
        ArrayPush(threads.threads, AiNpcMemoryThreadNew(s"thread \(i)", 1));
        i += 1;
    }
    let cappedThreads = AiNpcMemoryClamp(threads);
    t.EqInt("memory/threads capped", ArraySize(cappedThreads.threads), AiNpcMemoryMaxThreads());
    t.EqString("memory/oldest thread evicted first", cappedThreads.threads[0].text, "thread 3");
}

func AiNpcTestMemoryFounding(t: ref<AiNpcTestRunner>) -> Void {
    let first = AiNpcMemoryMerge(AiNpcMemoryNew(),
        AiNpcTestMemory(["is a joytoy", "told him herself", "will not stop"], [], "tense"), 0, true);
    t.EqInt("memory/the first compaction establishes the founding facts", first.founding, 3);

    // And never revises it: a later fact is episodic, however long it ends up surviving.
    let later = AiNpcMemoryMerge(first, AiNpcTestMemory(["bought a car"], [], ""), 0, true);
    t.EqInt("memory/founding is established once", later.founding, 3);

    // Overflow evicts the oldest EPISODIC fact and leaves the founding prefix alone. Plain
    // FIFO would have dropped "is a joytoy" -- the fact the character is built on.
    let full = AiNpcMemoryCopy(later);
    let i = 0;
    while i < AiNpcMemoryMaxFacts() + 4 {
        ArrayPush(full.facts, s"episodic \(i)");
        i += 1;
    }
    let clamped = AiNpcMemoryClamp(full);
    t.EqInt("memory/overflow respects the cap", ArraySize(clamped.facts), AiNpcMemoryMaxFacts());
    t.EqString("memory/a founding fact survives overflow", clamped.facts[0], "is a joytoy");
    t.EqString("memory/the third founding fact survives too", clamped.facts[2], "will not stop");
    t.Check("memory/an episodic fact is what gets evicted", !ArrayContains(clamped.facts, "bought a car"));

    // A founding fact dropped as a duplicate must not leave its protection behind for
    // whatever slid into its place.
    let dupe = AiNpcMemoryNew();
    dupe.founding = 2;
    ArrayPush(dupe.facts, "same");
    ArrayPush(dupe.facts, "same");
    ArrayPush(dupe.facts, "episodic");
    t.EqInt("memory/founding shrinks with its facts", AiNpcMemoryClamp(dupe).founding, 1);

    // The count has to cross a save, or the protection lasts exactly one session.
    let json = AiNpcMemoryFromJson(AiNpcMemoryToJson(first));
    t.EqInt("memory/founding survives the journal", json.founding, 3);
}

func AiNpcTestMemoryRender(t: ref<AiNpcTestRunner>) -> Void {
    t.EqString("memory/empty renders nothing", AiNpcMemoryRender(AiNpcMemoryNew()), "");

    let memory = AiNpcTestMemory(["V paid for the fixer"], ["still owes an answer about the gig"], "warmer than it was");
    let rendered = AiNpcMemoryRender(memory);
    t.Check("memory/renders facts", StrContains(rendered, "V paid for the fixer"));
    t.Check("memory/renders open threads", StrContains(rendered, "still owes an answer about the gig"));
    t.Check("memory/renders tone", StrContains(rendered, "warmer than it was"));

    // The section names the block writes and the ones the parser reads are the same three
    // functions; this pins that they actually reach the output.
    t.Check("memory/renders the facts header", StrContains(rendered, AiNpcMemorySectionFacts()));

    // Dating: a memory with no stamp says nothing about when it happened. A wrong "ago" is
    // worse than no "ago" -- the same rule the gap markers follow.
    t.Check("memory/undated says nothing about time", !StrContains(rendered, "ago"));

    let dated = AiNpcTestMemory(["V paid for the fixer"], [], "");
    dated.coveredUpTo = 86400;
    t.Check("memory/dated says how long ago", StrContains(AiNpcMemoryRenderAt(dated, 86400 + 7200), "2 hours ago"));
}

// The compaction request has to say who is speaking, because the summariser writes facts
// about people and the transcript is the only place it can read them from.
//
// The regression: V asked a character "t'es un mec ?", the character answered "ouais, un
// mec", and the note came back saying V was a man -- a wrong fact about the player, read
// back into every prompt for the next ten turns. Both halves are asserted here.

// The compaction request has to say who is speaking, because the summariser writes facts
// about people and the transcript is the only place it can read them from.
//
// The regression: V asked a character "t'es un mec ?", the character answered "ouais, un
// mec", and the note came back saying V was a man -- a wrong fact about the player, read
// back into every prompt for the next ten turns. Both halves are asserted here.
func AiNpcTestMemoryRequest(t: ref<AiNpcTestRunner>) -> Void {
    let messages = AiNpcTestHistory(["V:t'es un mec ?", "N:ouais, un mec"]);
    let body = AiNpcMemoryRequestBody(AiNpcMemoryNew(), "Rita", AiNpcGenderFactFor(AiNpcGender.Female),
        AiNpcHistoryTranscript(messages, "Rita"), false);

    t.Check("memory/the request states who V is", StrContains(body, "V is a woman."));
    t.Check("memory/the request names the player label", StrContains(body, "V is the player"));
    t.Check("memory/the request names the character label", StrContains(body, "Rita is the character"));
    t.Check("memory/the request still carries the transcript", StrContains(body, "Rita: ouais, un mec"));

    // Every line of the transcript carries a name, including the second line of a reply the
    // model chose to write in two bubbles. Before this, "et toi ?" reached the summariser
    // bare, attributable to anyone.
    let split = AiNpcTestHistory(["V:salut", "N:ouais, un mec\net toi ?"]);
    let rendered = AiNpcHistoryTranscript(split, "Rita");
    t.EqString("memory/a multi-line message stays one labelled line", rendered,
        "V: salut\nRita: ouais, un mec et toi ?\n");
    t.Check("memory/no bare continuation line", !StrContains(rendered, "\net toi"));

    // Unknown gender is silence, not a guess: the line simply is not written.
    let mute = AiNpcMemoryRequestBody(AiNpcMemoryNew(), "Rita", "", "", false);
    t.Check("memory/no gender line when nothing is known", !StrContains(mute, "V is a woman"));
    t.Check("memory/who-is-who survives an unknown gender", StrContains(mute, "V is the player"));

    t.Check("memory/the instruction rules on attribution",
        StrContains(AiNpcMemoryInstruction(false), "prefixed with the name of whoever said it"));

    t.EqString("memory/the male fact", AiNpcGenderFactFor(AiNpcGender.Male), "V is a man.");
}

func AiNpcTestMemoryParse(t: ref<AiNpcTestRunner>) -> Void {
    let answer = "FACTS:\n- V owes Rogue a favour\n* second style of bullet\nOPEN:\n- waiting on the Afterlife meet\nTONE: guarded but civil";
    let parsed = AiNpcMemoryParse(answer);
    t.Check("memory/parse returns a note", IsDefined(parsed));
    t.EqString("memory/parse reads facts", AiNpcTestFacts(parsed), "V owes Rogue a favour|second style of bullet");
    t.EqString("memory/parse reads threads", AiNpcTestThreads(parsed), "waiting on the Afterlife meet");
    t.EqString("memory/parse reads tone", parsed.tone, "guarded but civil");

    // The guard the whole feature rests on. A refusal or a paragraph of prose has no section
    // header, and storing one as a memory would rewrite a character's personality for good.
    t.Check("memory/prose is rejected",
        !IsDefined(AiNpcMemoryParse("I'm sorry, but I can't help with summarising that conversation.")));
    t.Check("memory/empty is rejected", !IsDefined(AiNpcMemoryParse("")));

    // A bullet before any header is dropped rather than guessed at: filing it under facts
    // would make an unparseable answer permanent.
    let stray = AiNpcMemoryParse("- something said before any header\nFACTS:\n- the real one");
    t.EqString("memory/bullets outside a section are dropped", AiNpcTestFacts(stray), "the real one");

    // Windows line endings, which is what a proxy or a local bridge on this machine may
    // hand back.
    let crlf = AiNpcMemoryParse("FACTS:\r\n- carried across a CRLF\r\nTONE: fine");
    t.EqString("memory/parse survives CRLF", AiNpcTestFacts(crlf), "carried across a CRLF");
}

func AiNpcTestMemoryMerge(t: ref<AiNpcTestRunner>) -> Void {
    let previous = AiNpcTestMemory(["V is an Aldecaldo now"], ["owes an answer about the convoy"], "warm");
    let parsed = AiNpcTestMemory(["V bought a new car"], ["owes an answer about the convoy"], "");

    let merged = AiNpcMemoryMerge(previous, parsed, 1200, true);

    // Old facts survive VERBATIM and new ones are appended. This is what bounds drift: a
    // fact is never handed back to the model to be reworded.
    t.EqString("memory/merge keeps old facts and appends new",
        AiNpcTestFacts(merged), "V is an Aldecaldo now|V bought a new car");

    // An empty tone leaves the previous one standing: "no opinion" is not "no relationship".
    t.EqString("memory/merge keeps the previous tone when none is offered", merged.tone, "warm");
    t.EqInt("memory/merge records coverage", merged.coveredUpTo, 1200);

    // A thread that reappears grows older; one that is left out is closed by omission.
    t.EqInt("memory/repeated thread ages", merged.threads[0].age, 1);

    let dropped = AiNpcMemoryMerge(merged, AiNpcTestMemory([], ["something else entirely"], "cold"), 1300, true);
    t.EqString("memory/threads are replaced, not accumulated",
        AiNpcTestThreads(dropped), "something else entirely");
    t.EqString("memory/merge takes a new tone when offered", dropped.tone, "cold");

    // Consolidation: a thread the conversation keeps returning to graduates into facts and
    // stops being rewritten.
    let persistent = AiNpcTestMemory([], ["the debt to Wakako"], "");
    let round = AiNpcMemoryMerge(AiNpcMemoryNew(), persistent, 0, true);
    let promoteAt = AiNpcMemoryPromoteAfter();
    let i = 1;
    while i < promoteAt {
        round = AiNpcMemoryMerge(round, persistent, 0, true);
        i += 1;
    }
    t.EqString("memory/a persistent thread is promoted to a fact", AiNpcTestFacts(round), "the debt to Wakako");
    t.EqString("memory/a promoted thread leaves the open list", AiNpcTestThreads(round), "");

    // An idle compaction rewrites and closes threads exactly like a full one, but buys no
    // age with them. Otherwise checking the phone often would consolidate faster than
    // talking, and PromoteAfter would stop meaning "three batches".
    let idleRounds = AiNpcMemoryMerge(AiNpcMemoryNew(), persistent, 0, false);
    let j = 0;
    while j < promoteAt + 2 {
        idleRounds = AiNpcMemoryMerge(idleRounds, persistent, 0, false);
        j += 1;
    }
    t.EqString("memory/an idle compaction does not promote", AiNpcTestFacts(idleRounds), "");
    t.EqString("memory/an idle compaction keeps the thread open",
        AiNpcTestThreads(idleRounds), "the debt to Wakako");
    t.EqInt("memory/an idle compaction leaves the age alone", idleRounds.threads[0].age, 0);
}

// The gameplay door and the thinking lane writing to the same list, which they do off two
// clocks that know nothing about each other.
//
// This is the test that was missing when AiNpcRecordFact shipped: every other memory test
// drives the lane alone, and the lane alone is never wrong. The bug only exists when
// something ELSE writes -- and the whole point of the door is that a gameplay event does
// not wait for a network round trip to be allowed to happen.

// The gameplay door and the thinking lane writing to the same list, which they do off two
// clocks that know nothing about each other.
//
// This is the test that was missing when AiNpcRecordFact shipped: every other memory test
// drives the lane alone, and the lane alone is never wrong. The bug only exists when
// something ELSE writes -- and the whole point of the door is that a gameplay event does
// not wait for a network round trip to be allowed to happen.
func AiNpcTestMemoryRebase(t: ref<AiNpcTestRunner>) -> Void {
    let base = AiNpcTestMemory(["owes V 500 eddies"], [], "wary");

    // The store as it stands when the answer lands: a scene played while the request was
    // out, and AiNpcRecordFact appended its line -- and moved the coverage to now, because
    // what the game has just observed is the most recent thing in the block.
    let live = AiNpcMemoryCopy(base);
    ArrayPush(live.facts, "met V at Kabuki last night, paid, it went well");
    live.coveredUpTo = 90000;

    let summarised = AiNpcMemoryMerge(base, AiNpcTestMemory(["V asked about the ripperdoc"], [], ""),
        86400, true);

    // The defect itself, pinned rather than described: the merge is built from the memory
    // captured at SEND time, so on its own it writes the recorded fact out of existence --
    // after RecordFact has already answered true and the caller has dropped its fallback.
    t.EqString("memory/the summary alone loses a fact recorded in flight",
        AiNpcTestFacts(summarised), "owes V 500 eddies|V asked about the ripperdoc");

    let rebased = AiNpcMemoryRebase(summarised, base, live);
    t.EqString("memory/a fact recorded in flight survives the compaction", AiNpcTestFacts(rebased),
        "owes V 500 eddies|V asked about the ripperdoc|met V at Kabuki last night, paid, it went well");
    // Last, so it is the last thing eviction takes -- the same rule RecordFact appends by.
    t.EqInt("memory/the carried fact dates the block", rebased.coveredUpTo, 90000);

    // Nothing recorded: the answer stands exactly as the merge wrote it, clock included. A
    // rebase that moved anything here would be a rebase that fires on every compaction.
    let untouched = AiNpcMemoryCopy(base);
    let quiet = AiNpcMemoryRebase(summarised, base, untouched);
    t.EqString("memory/an untouched store leaves the summary alone", AiNpcTestFacts(quiet),
        AiNpcTestFacts(summarised));
    t.EqInt("memory/an untouched store does not move the clock", quiet.coveredUpTo,
        summarised.coveredUpTo);

    // The model and the game reaching the same sentence -- the transcript said what the
    // scene did -- must not state it twice.
    let echo = AiNpcMemoryCopy(base);
    ArrayPush(echo.facts, "V asked about the ripperdoc");
    let once = AiNpcMemoryRebase(summarised, base, echo);
    t.EqString("memory/a fact the summary already states is not carried twice",
        AiNpcTestFacts(once), AiNpcTestFacts(summarised));

    // Forgetting is not undone. A fact this compaction evicted into the archive is settled;
    // carrying it back would resurrect it at every compaction from here on.
    let evicted = AiNpcMemoryNew();
    ArrayPush(evicted.facts, "still current");
    ArrayPush(evicted.archive, "an old episode");
    let stale = AiNpcMemoryNew();
    ArrayPush(stale.facts, "an old episode");
    let forgotten = AiNpcMemoryRebase(evicted, AiNpcMemoryNew(), stale);
    t.EqString("memory/an archived fact is not pulled back out", AiNpcTestFacts(forgotten),
        "still current");

    /// The rule on its own ///

    let nothing = AiNpcMemoryFactsSince(base, untouched);
    t.EqInt("memory/nothing recorded, nothing carried", ArraySize(nothing), 0);

    // A base LONGER than the store's memory is the ordinary first compaction: SeedIfEmpty
    // adds the provider's seed facts before sending. Counting list sizes would read that as
    // a negative carry, or -- with one fact recorded at the same time -- as none at all.
    let seeded = AiNpcMemoryCopy(base);
    ArrayPush(seeded.facts, "is a joytoy");
    let recorded = AiNpcMemoryCopy(base);
    ArrayPush(recorded.facts, "met V at Kabuki last night, paid, it went well");
    let since = AiNpcMemoryFactsSince(seeded, recorded);
    t.EqInt("memory/a seeded base does not hide a recorded fact", ArraySize(since), 1);
    t.EqString("memory/and it is the recorded one", since[0],
        "met V at Kabuki last night, paid, it went well");
}

// Agreements: the fourth kind of content, and the one the clock forgets rather than the
// model. The failure it exists to fix was measured on the shipped journals, so the test
// that matters most here is the last one -- an agreement must not lose its place to a
// biography, which is exactly what happened when they shared the facts list.

// Agreements: the fourth kind of content, and the one the clock forgets rather than the
// model. The failure it exists to fix was measured on the shipped journals, so the test
// that matters most here is the last one -- an agreement must not lose its place to a
// biography, which is exactly what happened when they shared the facts list.
func AiNpcTestMemoryPacts(t: ref<AiNpcTestRunner>) -> Void {
    /// The closed vocabulary ///

    t.EqInt("memory/soon is a horizon", AiNpcMemoryPactHorizonOf("soon"), AiNpcMemoryPactSoon());
    t.EqInt("memory/days is a horizon", AiNpcMemoryPactHorizonOf("DAYS"), AiNpcMemoryPactDays());
    // Anything unrecognised falls to OPEN, which never lapses: the only failure direction
    // that cannot invent a deadline the two of them never agreed to.
    t.EqInt("memory/an invented horizon falls back to open",
        AiNpcMemoryPactHorizonOf("in about three hours"), AiNpcMemoryPactOpen());
    t.Check("memory/open never lapses", AiNpcMemoryPactHorizonSeconds(AiNpcMemoryPactOpen()) < 0);

    /// Parsing ///

    let answer = "FACTS:\n- V works nights at the Lizzy\n"
        + "OPEN:\n- who pays for the room\n"
        + "AGREED:\n- soon | V said she would come by tonight\n"
        + "- days | V said she would call the shop back\n"
        + "TONE: easy";
    let parsed = AiNpcMemoryParse(answer);
    t.Check("memory/parse returns a note with agreements", IsDefined(parsed));
    t.EqString("memory/parse reads agreements", AiNpcTestPacts(parsed),
        "soon:V said she would come by tonight|days:V said she would call the shop back");
    // The three lists stay separate: an agreement filed as a thread is the bug.
    t.EqString("memory/an agreement is not a thread", AiNpcTestThreads(parsed), "who pays for the room");
    t.EqString("memory/an agreement is not a fact", AiNpcTestFacts(parsed), "V works nights at the Lizzy");

    // A model that ignores the prefix has still reported an agreement. Dropping the line
    // would lose the content to punish the formatting.
    let bare = AiNpcMemoryParse("AGREED:\n- V said she would think about it");
    t.EqString("memory/an agreement with no horizon word is kept as open", AiNpcTestPacts(bare),
        "open:V said she would think about it");
    // ...and a bar that belongs to the sentence must not be mistaken for the separator,
    // which would eat the first half of the agreement.
    let bar = AiNpcMemoryParse("AGREED:\n- V said she would bring the shard | the red one");
    t.EqString("memory/a bar inside the sentence is not a separator", AiNpcTestPacts(bar),
        "open:V said she would bring the shard | the red one");

    /// The clock, and nobody else ///

    let soon = AiNpcMemoryPactNew("come by tonight", 86400, AiNpcMemoryPactSoon());
    t.Check("memory/an agreement is live inside its horizon", !AiNpcMemoryPactLapsed(soon, 86400 + 39600));
    t.Check("memory/an agreement lapses once its horizon passes", AiNpcMemoryPactLapsed(soon, 86400 + 43200));
    // 19% of the messages in the shipped journals carry a stamp, so an undated agreement is
    // the common case on an imported history. A wrong "this is overdue" is worse than none,
    // which is the rule the gap markers already follow.
    let undated = AiNpcMemoryPactNew("come by tonight", AiNpcTimeUnknown(), AiNpcMemoryPactSoon());
    t.Check("memory/an undated agreement never lapses", !AiNpcMemoryPactLapsed(undated, 999999));

    /// Merging: the two doors out of the list ///

    let previous = AiNpcMemoryNew();
    ArrayPush(previous.pacts, AiNpcMemoryPactNew("V said she would come by tonight", 86400, AiNpcMemoryPactSoon()));
    ArrayPush(previous.pacts, AiNpcMemoryPactNew("V said she would call the shop back", 86400, AiNpcMemoryPactDays()));

    // The model rewrites the list and leaves the second one out: it closed it.
    let restated = AiNpcMemoryNew();
    ArrayPush(restated.pacts, AiNpcMemoryPactNew("V said she would come by tonight", AiNpcTimeUnknown(), AiNpcMemoryPactSoon()));
    let merged = AiNpcMemoryMerge(previous, restated, 86400 + 3600, true);
    t.EqString("memory/an agreement the model dropped is closed", AiNpcTestPacts(merged),
        "soon:V said she would come by tonight");
    t.Check("memory/a closed agreement is not turned into a fact",
        !StrContains(AiNpcTestFacts(merged), "call the shop back"));
    // Restating it must not restart its clock, or an agreement the two of them keep
    // mentioning could never fall due -- which is the one that most needs to.
    t.EqInt("memory/a restated agreement keeps its original stamp", merged.pacts[0].openedAt, 86400);

    // The other door: the model still believes it is live, and the clock says otherwise.
    let late = AiNpcMemoryMerge(previous, restated, 86400 + 50000, true);
    t.EqString("memory/a lapsed agreement leaves the list", AiNpcTestPacts(late), "");
    t.Check("memory/a lapsed agreement becomes a fact",
        StrContains(AiNpcTestFacts(late), "V said she would come by tonight"));

    /// The measured failure ///

    // This is the whole reason the list exists. Fill the facts past their cap -- the
    // biography that, in journal.b18, evicted "the cosplay concept is still undecided"
    // within two compactions -- and check the agreement does not move.
    let crowded = AiNpcMemoryNew();
    ArrayPush(crowded.pacts, AiNpcMemoryPactNew("V said she would come by tonight", 86400, AiNpcMemoryPactOpen()));
    let i = 0;
    while i < AiNpcMemoryMaxFacts() + 6 {
        ArrayPush(crowded.facts, "biography line " + ToString(i));
        i += 1;
    }
    let clamped = AiNpcMemoryClamp(crowded);
    t.EqInt("memory/facts still evict under pressure", ArraySize(clamped.facts), AiNpcMemoryMaxFacts());
    t.EqString("memory/an agreement never loses its place to a biography",
        AiNpcTestPacts(clamped), "open:V said she would come by tonight");

    // It has a bound of its own, though, and it is FIFO like the threads.
    let many = AiNpcMemoryNew();
    i = 0;
    while i < AiNpcMemoryMaxPacts() + 2 {
        ArrayPush(many.pacts, AiNpcMemoryPactNew("agreement " + ToString(i), 86400, AiNpcMemoryPactOpen()));
        i += 1;
    }
    let cappedPacts = AiNpcMemoryClamp(many);
    t.EqInt("memory/agreements capped", ArraySize(cappedPacts.pacts), AiNpcMemoryMaxPacts());
    t.EqString("memory/oldest agreement evicted first", cappedPacts.pacts[0].text, "agreement 2");

    /// Rendering ///

    let live = AiNpcMemoryNew();
    ArrayPush(live.pacts, AiNpcMemoryPactNew("V said she would come by tonight", 86400, AiNpcMemoryPactSoon()));
    let rendered = AiNpcMemoryRenderAt(live, 86400 + 3600);
    t.Check("memory/renders the agreements header", StrContains(rendered, AiNpcMemorySectionAgreed()));
    t.Check("memory/renders the agreement", StrContains(rendered, "come by tonight"));
    t.Check("memory/a live agreement is not marked overdue", !StrContains(rendered, "(overdue)"));
    // Computed at the moment it is read, never stored and never scheduled: an agreement can
    // fall due while the phone is shut, and a DelayCallback would not survive a save.
    t.Check("memory/a lapsed agreement renders as overdue",
        StrContains(AiNpcMemoryRenderAt(live, 86400 + 50000), "(overdue)"));

    /// The request, and the journal ///

    t.Check("memory/the instruction asks for agreements",
        StrContains(AiNpcMemoryInstruction(false), AiNpcMemorySectionAgreed()));
    t.Check("memory/the instruction fixes the horizon vocabulary",
        StrContains(AiNpcMemoryInstruction(false), "soon (within the day)"));
    let body = AiNpcMemoryRequestBody(live, "Rita", "", "V: salut", false);
    t.Check("memory/the request hands the agreements back for rewriting",
        StrContains(body, "soon | V said she would come by tonight"));

    let roundTrip = AiNpcMemoryFromJson(AiNpcMemoryToJson(live));
    t.EqString("memory/agreements survive the journal", AiNpcTestPacts(roundTrip),
        "soon:V said she would come by tonight");
    t.EqInt("memory/an agreement keeps its stamp across the journal",
        roundTrip.pacts[0].openedAt, 86400);
    // Every snapshot written before this existed has no "p" key at all. Restoring one must
    // simply produce a memory with no agreements, not a broken one.
    let legacy = AiNpcMemoryFromJson(ParseJson("{\"f\":[\"an older memory\"],\"n\":\"fine\"}") as JsonObject);
    t.EqString("memory/a memory written before agreements existed still loads",
        AiNpcTestFacts(legacy), "an older memory");
    t.EqInt("memory/an older memory simply has none", ArraySize(legacy.pacts), 0);
}

// The archive and the chronicle: eviction as a demotion rather than a deletion.
//
// The property under test throughout is the one the whole design rests on -- a fact leaves
// the prompt without leaving the memory -- and the last group is what that property buys:
// a chronicle can be rebuilt from the facts themselves, so drift is undoable.

// The archive and the chronicle: eviction as a demotion rather than a deletion.
//
// The property under test throughout is the one the whole design rests on -- a fact leaves
// the prompt without leaving the memory -- and the last group is what that property buys:
// a chronicle can be rebuilt from the facts themselves, so drift is undoable.
func AiNpcTestMemoryArchive(t: ref<AiNpcTestRunner>) -> Void {
    /// Eviction moves, it does not erase ///

    let crowded = AiNpcMemoryNew();
    let i = 0;
    while i < AiNpcMemoryMaxFacts() + 3 {
        ArrayPush(crowded.facts, "fact " + ToString(i));
        i += 1;
    }
    crowded.founding = 2;
    let clamped = AiNpcMemoryClamp(crowded);
    t.EqInt("memory/facts still capped", ArraySize(clamped.facts), AiNpcMemoryMaxFacts());
    t.EqInt("memory/what overflowed went to the archive", ArraySize(clamped.archive), 3);
    // The oldest EPISODIC fact goes first -- index 2, just past the founding prefix -- and
    // the archive keeps them in the order they were demoted.
    t.EqString("memory/the archive holds what the prompt lost", clamped.archive[0], "fact 2");
    t.Check("memory/a founding fact is never demoted", ArrayContains(clamped.facts, "fact 0"));
    t.Check("memory/an archived fact is out of the live list", !ArrayContains(clamped.facts, "fact 2"));

    // Clamping happens on every merge AND on every read from disk, so it has to be
    // idempotent or the archive would grow a duplicate on each load.
    let twice = AiNpcMemoryClamp(clamped);
    t.EqInt("memory/clamping twice archives nothing new", ArraySize(twice.archive), 3);

    /// The archive's backstop drops only what the chronicle already holds ///

    let huge = AiNpcMemoryNew();
    i = 0;
    while i < AiNpcMemoryMaxArchive() + 5 {
        ArrayPush(huge.archive, "archived " + ToString(i));
        i += 1;
    }
    // Nothing folded yet: the backstop must NOT fire, because dropping an unfolded entry
    // loses the fact outright -- the one thing this list exists to prevent.
    huge.chronicleUpTo = 0;
    let untouched = AiNpcMemoryClamp(huge);
    t.EqInt("memory/an unfolded archive is never truncated",
        ArraySize(untouched.archive), AiNpcMemoryMaxArchive() + 5);

    huge.chronicleUpTo = 10;
    let trimmed = AiNpcMemoryClamp(huge);
    t.EqInt("memory/the backstop drops only folded entries",
        ArraySize(trimmed.archive), AiNpcMemoryMaxArchive());
    t.EqString("memory/it drops the oldest folded one first", trimmed.archive[0], "archived 5");
    // The coverage mark moves with what it covers, or it would start pointing at entries
    // the chronicle has never seen.
    t.EqInt("memory/coverage follows the truncation", trimmed.chronicleUpTo, 5);

    /// Folding: asked for exactly when there is something to fold ///

    let pending = AiNpcMemoryNew();
    t.Check("memory/nothing to fold when the archive is empty", !AiNpcMemoryShouldFold(pending));
    ArrayPush(pending.archive, "V used to work days at the Be Hot");
    ArrayPush(pending.archive, "Mira put V in touch with the Mox");
    t.Check("memory/an unfolded archive asks for a fold", AiNpcMemoryShouldFold(pending));
    pending.chronicleUpTo = 2;
    t.Check("memory/a fully folded archive asks for nothing", !AiNpcMemoryShouldFold(pending));

    // The two modes are one operation over a different slice. That is the whole reason
    // chronicleUpTo is an index and not a flag.
    pending.chronicleUpTo = 1;
    t.EqInt("memory/incremental starts where the chronicle stopped",
        AiNpcMemoryChronicleFrom(pending, false), 1);
    t.EqInt("memory/exact starts at the beginning", AiNpcMemoryChronicleFrom(pending, true), 0);

    /// The request carries the right slice, and only then ///

    pending.chronicle = "Elle a commence au Be Hot, de jour.";
    let incremental = AiNpcMemoryRequestBody(pending, "Rita", "", "V: salut", false);
    t.Check("memory/incremental sends the previous chronicle",
        StrContains(incremental, "Elle a commence au Be Hot"));
    t.Check("memory/incremental sends only what is not folded yet",
        StrContains(incremental, "Mira put V in touch") && !StrContains(incremental, "used to work days"));

    let exact = AiNpcMemoryRequestBody(pending, "Rita", "", "V: salut", true);
    t.Check("memory/exact sends the whole archive",
        StrContains(exact, "used to work days") && StrContains(exact, "Mira put V in touch"));
    // The point of exact mode, and it is a property rather than a preference: the paragraph
    // is rebuilt from the facts, never from the paragraph before it, so it cannot inherit
    // an error. Sending the old chronicle would quietly restore the telephone game.
    t.Check("memory/exact does not send the previous chronicle",
        !StrContains(exact, "Elle a commence au Be Hot"));

    let quiet = AiNpcMemoryRequestBody(AiNpcMemoryNew(), "Rita", "", "V: salut", false);
    t.Check("memory/no archive block when there is nothing to fold", !StrContains(quiet, "ARCHIVE"));
    // Asked for unconditionally, a model with nothing to fold invents one out of the batch
    // it was handed -- and an invented chronicle is indistinguishable from a real one.
    t.Check("memory/the chronicle is not asked for when not folding",
        !StrContains(AiNpcMemoryInstruction(false), AiNpcMemorySectionChronicle()));
    t.Check("memory/it is asked for when folding",
        StrContains(AiNpcMemoryInstruction(true), AiNpcMemorySectionChronicle()));
    t.Check("memory/the fold instruction forbids editorialising",
        StrContains(AiNpcMemoryInstruction(true), "grew closer"));

    /// Parsing a fold ///

    let parsed = AiNpcMemoryParse("FACTS:\n- something new\n"
        + "CHRONICLE: Ils se connaissent depuis des mois. Elle lui a dit ce qu'elle fait,\n"
        + "il ne l'a jamais mal pris.");
    t.Check("memory/parse reads a chronicle", IsDefined(parsed));
    // Prose is the one section where a line break is expected rather than a formatting slip,
    // so a wrapped paragraph is joined instead of being dropped at the first newline.
    t.EqString("memory/a wrapped paragraph is joined", parsed.chronicle,
        "Ils se connaissent depuis des mois. Elle lui a dit ce qu'elle fait, il ne l'a jamais mal pris.");

    /// Merging a fold ///

    let before = AiNpcMemoryNew();
    ArrayPush(before.archive, "first archived");
    ArrayPush(before.archive, "second archived");
    let answer = AiNpcMemoryNew();
    answer.chronicle = "Le resume de tout ca.";
    let merged = AiNpcMemoryMerge(before, answer, 86400, true);
    t.EqString("memory/the chronicle is stored", merged.chronicle, "Le resume de tout ca.");
    // It covers the archive AS IT WAS WHEN THE REQUEST WENT OUT. Anything demoted by this
    // same merge lands past the mark and waits for the next fold -- it was not in the
    // material the model just read, so claiming it was covered would lose it.
    t.EqInt("memory/coverage marks what the model actually read", merged.chronicleUpTo, 2);
    t.EqInt("memory/the archive is carried across a merge", ArraySize(merged.archive), 2);

    // An answer with no chronicle leaves the previous one standing, exactly like tone: a
    // compaction that did not fold must not erase what an earlier one folded.
    let noFold = AiNpcMemoryMerge(merged, AiNpcMemoryNew(), 90000, true);
    t.EqString("memory/a compaction that did not fold keeps the chronicle",
        noFold.chronicle, "Le resume de tout ca.");
    t.EqInt("memory/and keeps its coverage", noFold.chronicleUpTo, 2);

    /// Rendering, and the journal ///

    let live = AiNpcMemoryNew();
    live.chronicle = "Ils se connaissent depuis des mois.";
    ArrayPush(live.facts, "V bosse au Lizzy");
    let rendered = AiNpcMemoryRender(live);
    t.Check("memory/renders the chronicle", StrContains(rendered, "depuis des mois"));
    // Oldest and blurriest first: the order of the block states the loss of resolution.
    t.Check("memory/the chronicle comes before the facts",
        StrFindFirst(rendered, "depuis des mois") < StrFindFirst(rendered, "V bosse au Lizzy"));
    // The archive is kept, not sent. If it ever reached the prompt the whole point of
    // separating it from `facts` would be gone.
    ArrayPush(live.archive, "an archived fact nobody should see");
    t.Check("memory/the archive is never rendered",
        !StrContains(AiNpcMemoryRender(live), "nobody should see"));

    let roundTrip = AiNpcMemoryFromJson(AiNpcMemoryToJson(live));
    t.EqString("memory/the chronicle survives the journal", roundTrip.chronicle,
        "Ils se connaissent depuis des mois.");
    t.EqString("memory/the archive survives the journal", roundTrip.archive[0],
        "an archived fact nobody should see");
    let legacy = AiNpcMemoryFromJson(ParseJson("{\"f\":[\"older\"],\"n\":\"fine\"}") as JsonObject);
    t.EqInt("memory/a memory written before the archive existed loads with none",
        ArraySize(legacy.archive), 0);
    t.EqString("memory/and with no chronicle", legacy.chronicle, "");
}

func AiNpcTestMemoryWindow(t: ref<AiNpcTestRunner>) -> Void {
    let short = AiNpcTestHistory(["V:hi", "N:yo"]);
    t.EqBool("memory/short conversation is not compacted", AiNpcMemoryShouldCompact(short), false);
    let nothingEvicted = AiNpcMemoryEvicted(short);
    t.EqInt("memory/nothing is evicted from a short conversation", ArraySize(nothingEvicted), 0);

    let long: array<ref<AiNpcMessage>>;
    let i = 0;
    while i < AiNpcMemoryMaxTurns() * 2 + 1 {
        long = AiNpcHistoryAppend(long, s"m\(i)", (i % 2) == 0);
        i += 1;
    }
    t.EqBool("memory/a full conversation is compacted", AiNpcMemoryShouldCompact(long), true);

    let kept = AiNpcMemoryKept(long);
    let evicted = AiNpcMemoryEvicted(long);

    // The invariant, asserted directly: the two halves partition the conversation, in order,
    // with nothing duplicated and nothing lost.
    t.EqInt("memory/the split loses nothing", ArraySize(kept) + ArraySize(evicted), ArraySize(long));
    t.EqString("memory/the window is the tail", kept[ArraySize(kept) - 1].text, long[ArraySize(long) - 1].text);
    t.EqString("memory/the batch is the head", evicted[0].text, long[0].text);
    t.Check("memory/the window stays within its bound", ArraySize(kept) <= AiNpcMemoryWindowTurns() * 2 + 1);

    // Coverage: an unstamped batch leaves the previous coverage exactly where it was, rather
    // than claiming to cover up to time zero.
    t.EqInt("memory/an unstamped batch does not move coverage", AiNpcMemoryCoverage(999, evicted), 999);

    let stamped: array<ref<AiNpcMessage>>;
    ArrayPush(stamped, AiNpcMessageNewAt("early", true, 100));
    ArrayPush(stamped, AiNpcMessageNewAt("late", false, 500));
    t.EqInt("memory/coverage is the last stamp of the batch", AiNpcMemoryCoverage(0, stamped), 500);
}

func AiNpcTestMemoryIdleWindow(t: ref<AiNpcTestRunner>) -> Void {
    let gap = AiNpcMemoryIdleGapSeconds();

    // A batch big enough to matter, all of it stamped at the same moment, sitting well below
    // the full-batch threshold. This is the case the idle trigger exists for.
    let quiet: array<ref<AiNpcMessage>>;
    let i = 0;
    while i < AiNpcMemoryWindowTurns() * 2 + AiNpcMemoryIdleMinBatch() {
        ArrayPush(quiet, AiNpcMessageNewAt(s"m\(i)", (i % 2) == 0, 1000));
        i += 1;
    }
    t.EqBool("memory/idle: the batch is below the ordinary threshold",
        AiNpcMemoryShouldCompact(quiet), false);
    t.EqBool("memory/idle: silence past the gap compacts it",
        AiNpcMemoryShouldCompactIdle(quiet, 1000 + gap), true);

    // Still the same scene: a pause is not an ending.
    t.EqBool("memory/idle: a short pause does not compact",
        AiNpcMemoryShouldCompactIdle(quiet, 1000 + gap - 1), false);

    // A clock read backwards -- an older save reloaded -- is not a silence either.
    t.EqBool("memory/idle: a clock that moved backwards does not compact",
        AiNpcMemoryShouldCompactIdle(quiet, 500), false);

    // The floor: silence alone is not enough, or every visit to the phone would be a rewrite.
    let thin: array<ref<AiNpcMessage>>;
    i = 0;
    while i < AiNpcMemoryWindowTurns() * 2 + AiNpcMemoryIdleMinBatch() - 1 {
        ArrayPush(thin, AiNpcMessageNewAt(s"m\(i)", (i % 2) == 0, 1000));
        i += 1;
    }
    let thinEvicted = AiNpcMemoryEvicted(thin);
    t.Check("memory/idle: the under-sized batch is really under the floor",
        ArraySize(thinEvicted) < AiNpcMemoryIdleMinBatch());
    t.EqBool("memory/idle: an under-sized batch waits", AiNpcMemoryShouldCompactIdle(thin, 1000 + gap), false);

    let tiny = AiNpcTestHistory(["V:hi", "N:yo"]);
    t.EqBool("memory/idle: a two-message conversation is never compacted",
        AiNpcMemoryShouldCompactIdle(tiny, 999999), false);

    // Unstamped tail: unknown, and unknown declines. Taking the newest stamp further back
    // would report a silence that never happened.
    let legacy: array<ref<AiNpcMessage>>;
    i = 0;
    while i < AiNpcMemoryWindowTurns() * 2 + AiNpcMemoryIdleMinBatch() {
        ArrayPush(legacy, AiNpcMessageNewAt(s"m\(i)", (i % 2) == 0, 1000));
        i += 1;
    }
    ArrayPush(legacy, AiNpcMessageNew("said just now, untimed", true));
    t.EqBool("memory/idle: an unstamped last message declines",
        AiNpcMemoryShouldCompactIdle(legacy, 1000 + gap * 4), false);

    // An unknown clock -- no session, a replay -- declines too.
    t.EqBool("memory/idle: an unknown clock declines",
        AiNpcMemoryShouldCompactIdle(quiet, AiNpcTimeUnknown()), false);
}

func AiNpcTestMemoryJournal(t: ref<AiNpcTestRunner>) -> Void {
    let memory = AiNpcTestMemory(["remembered across a reload"], ["still open"], "steady");
    memory.coveredUpTo = 4242;

    // Round trip through the journal line, which is where a memory actually crosses a save.
    let op = AiNpcJournalOpSnapshotWith(1, "panam", AiNpcTestHistory(["V:hi", "N:yo"]), memory);
    let restored = AiNpcJournalOpFromJson(ParseJson(AiNpcJournalOpToLine(op)) as JsonObject);
    t.EqString("memory/journal round trip keeps facts", AiNpcTestFacts(restored.memory), "remembered across a reload");
    t.EqString("memory/journal round trip keeps threads", AiNpcTestThreads(restored.memory), "still open");
    t.EqString("memory/journal round trip keeps tone", restored.memory.tone, "steady");
    t.EqInt("memory/journal round trip keeps coverage", restored.memory.coveredUpTo, 4242);

    // A conversation with no memory writes a line indistinguishable from one written before
    // memory existed -- because it is one.
    let plain = AiNpcJournalOpSnapshot(1, "panam", AiNpcTestHistory(["V:hi"]));
    t.Check("memory/an empty memory adds nothing to the line", !StrContains(AiNpcJournalOpToLine(plain), "mm"));

    let ops: array<ref<AiNpcJournalOp>>;
    ArrayPush(ops, op);
    let replayed = AiNpcJournalReplay(ops, 1, AiNpcMemoryHardMaxTurns());
    t.EqInt("memory/replay restores one conversation", ArraySize(replayed), 1);
    t.EqString("memory/replay restores the memory", AiNpcTestFacts(replayed[0].memory), "remembered across a reload");

    // Clear means "this conversation never happened", and a memory that survived it would be
    // the one thing still able to contradict that.
    ArrayPush(ops, AiNpcJournalOpClear(2, "panam"));
    let cleared = AiNpcJournalReplay(ops, 2, AiNpcMemoryHardMaxTurns());
    t.EqBool("memory/clear forgets the memory too", AiNpcMemoryIsEmpty(cleared[0].memory), true);

    // A fork snapshots the live state; a memory it dropped would be lost at every branch.
    let carried = AiNpcJournalSnapshotOps(replayed);
    t.EqInt("memory/fork snapshots the conversation", ArraySize(carried), 1);
    t.EqString("memory/fork carries the memory", AiNpcTestFacts(carried[0].memory), "remembered across a reload");

    // A conversation whose window was emptied by an undo still has something to snapshot.
    let memoryOnly = new AiNpcConversation();
    memoryOnly.contactId = "judy";
    memoryOnly.memory = memory;
    let onlyList: array<ref<AiNpcConversation>>;
    ArrayPush(onlyList, memoryOnly);
    let onlyOps = AiNpcJournalSnapshotOps(onlyList);
    t.EqInt("memory/a memory with no messages is still snapshotted", ArraySize(onlyOps), 1);
}

/// Result reporting ///
