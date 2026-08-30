# Conversation memory

How a character remembers a conversation that no longer fits in the prompt.

This document is the design. It states the model, the invariant everything else leans on,
where each piece lives, and — as much as it matters — the alternatives that were rejected
and why. Implementation notes that only repeat the code are deliberately absent; the code
carries those.

---

## The problem

Before this, a conversation was a flat list of messages trimmed to a window. Everything
past the window was deleted — from the prompt, and from disk: `AiNpcJournalReplay` retrims
on every load, so the messages were not merely unsent, they were gone. A character forgot
a promise made twenty turns earlier, completely and without warning, and nothing about the
failure was visible to the player except a personality that occasionally reset.

Trimming is a *loss of resolution*, and deletion is the crudest one available. The mod
already thinks in resolutions elsewhere — the gap markers in `AiNpcHistory` render a pause
as "moments", "2 hours" or "3 days" depending on how far away it is. Memory applies the
same idea to content instead of to time.

> **Memory is not a field beside the history. It is what the history becomes when it
> leaves the window.**

That sentence is the whole design. A `memory: String` stored next to `messages` would be
the patch-shaped answer: two things to keep in agreement, two write paths, two ways to
fork, and an undo that can cross a boundary neither of them knows about.

---

## The model

```
AiNpcConversation
    contactId : String
    memory    : ref<AiNpcMemory>          // the compacted past
    messages  : array<ref<AiNpcMessage>>  // the recent window, verbatim
```

**The invariant, and it is the only one:** `messages` is always a suffix of the
conversation. Everything that left it passed through `memory`. Nothing is ever in both.

Most of the awkward cases disappear as consequences rather than as code:

- `Undo` cannot cross a compaction boundary, because it pops the tail and the tail is by
  construction never absorbed. No guard, no test for a case that cannot arise.
- A batch can never be compacted twice: absorbed messages are removed in the same
  operation that writes the memory.
- "What has this character been told?" has one answer — memory plus window — and no
  ordering question, because the two never overlap.

### `AiNpcMemory` is structured, not a paragraph

```
AiNpcMemory
    facts     : array<String>            // consolidated  — sent every message, capped
    archive   : array<String>            // every fact ever held — kept, never sent
    chronicle : String                   // the archive as prose — a derived view
    threads   : array<ref<AiNpcMemoryThread>>  // open loops — rewritten every batch
    pacts     : array<ref<AiNpcMemoryPact>>    // agreements — forgotten by the clock
    tone      : String                   // one line: where the relationship stands
    coveredUpTo   : Int32                // game-time seconds of the last absorbed message
    chronicleUpTo : Int32                // how much of the archive the chronicle covers
```

Three reasons, and the third is the one that decides it.

**1. The cap becomes enforceable.** "Keep this under 120 words" is a request addressed to
a model. `AiNpcMemoryClamp` is a guarantee. The bound lives in the code; the word budget
in the prompt is a hint that makes the clamp rarely bite.

**2. The rendering is deterministic** — therefore testable, readable in a log, and
diffable between two batches. A prose blob can only be eyeballed.

**3. Four kinds of content decay at four different speeds.** An established fact almost
never dies. An open thread *must* die — a promise kept is a thread closed. Tone is
single-valued and always overwritten. A single blob forces one decay rate onto all three,
which is exactly what makes naive rolling summaries drift into sludge.

`AiNpcMemoryThread` is a class holding `text` and `age` rather than two parallel arrays,
for the reason written at the top of `AiNpcHistory.reds`: parallel arrays trimmed
independently is a bug this codebase has already paid for once.

### Bounding drift

The failure mode of a rolling summary is the telephone game: every batch re-feeds the
previous summary through the model, so errors compound. The `facts` / `threads` split
bounds it structurally.

- `threads` **is** resubmitted for rewriting. It must be — a thread has to be closable.
- `facts` **is never resubmitted for rewriting**. It is passed to the model read-only.
  The model may add to it; it cannot restate it.

Drift is then confined to the live part, which is small and short-lived. Forgetting stops
being an accident and becomes a mechanism: when `facts` is full, the oldest **episodic**
entry is evicted. A thread that survives `AiNpcMemoryPromoteAfter()` compactions graduates
into `facts` — that is consolidation.

### Founding facts

Oldest-first is the right eviction rule for episodic content and exactly the wrong one for
identity, and at first the two shared a list. Measured on a real conversation (see below):
after two compactions the list was already more than half full, and plain FIFO would have
dropped *"V is a joytoy and told him herself"* — the fact the entire relationship rests on
— while keeping *"a colleague showed him the profile once"*.

So `AiNpcMemory.founding` counts how many of the leading facts are never evicted. A count
rather than a per-entry flag: founding facts are by definition the earliest, so they are
always a prefix, and a prefix cannot fall out of step with its list the way a parallel
array can.

It is **established once** — at the first compaction that produces any facts, which is also
where a provider's `GetSeedFacts` have landed — and never revised. The cost is real and
worth stating: a decisive event that happens at batch four is episodic, however defining it
feels. Re-electing founding facts later would mean choosing them by survival, which is the
oldest-wins rule this exists to escape.

The result is four temporal layers that happen to mirror how human memory is usually
described, which is where the idea came from:

| layer | holds | rewritten | forgotten by |
|---|---|---|---|
| window | verbatim messages | never | being absorbed by a compaction |
| threads | recent episodic | every batch | closure or age |
| pacts | agreements pending | every batch | **the clock** |
| facts | consolidated semantic | never | demotion to the archive when full |
| chronicle | the archive as prose | every fold | nothing — it blurs instead |

### Nothing is deleted: a fact descends one layer

Eviction used to be a `delete`. It is a `move`:

```
window (verbatim)  ->  facts (sent every message)  ->  archive (kept, never sent)
```

`archive` is append-only and holds every fact the memory has ever carried. `chronicle` is
that archive told as a paragraph — and it is a **derived view, not a second source**. The
distinction is the whole design:

> The chronicle is a cache. Its source is still on disk. It can be rebuilt at any time.

That is what a rolling summary can never say. The classic failure of one is the telephone
game: each pass re-summarises the last, an error compounds, and there is no way back.
Here there is a way back, because the facts the paragraph was made from were never
destroyed. **Drift stops being permanent and becomes repairable**, which is a different
kind of object.

Only facts descend. Threads and pacts do not: both are owned by the model and closed by
omission, so archiving them would resurrect loops their own compaction had closed.

`chronicleUpTo` is how much of the archive the paragraph covers — exactly
`archive[0 .. chronicleUpTo)`. A count defining a prefix, for the third time in this file
and for the same reason as `founding` and `coveredUpTo`: the covered part is by
construction the oldest, so it is always a prefix, and a prefix cannot fall out of step
with its list the way a parallel array can.

It also makes the two fold modes **one operation over a different slice**, which is why it
is an index and not a flag:

| `memoryChronicleExact` | reads | cost | drift |
|---|---|---|---|
| on *(default)* | the whole archive; the old paragraph is **not** sent | ~6 000 tk per fold, **bounded** | **zero, by construction** |
| off | the old paragraph + what was archived since | O(1) per fold | compounds |

The default came from a measurement, not from taste. Driving thirty folds — about three
hundred turns at the measured 6.3 new facts per compaction — the incremental chronicle
ends up **twenty-seven levels of summary-of-a-summary deep**. That is not a small drift
budget; it is exactly the sludge this document warns about, reached honestly.

What makes the exact mode affordable is that `AiNpcMemoryMaxArchive()` caps the archive,
and therefore caps the fold: ~200 entries at the observed median is ~6 000 tokens, once per
~30 turns, on a request the player never waits for. Against the ~75 000 tokens the speaking
lane spends over those same thirty turns, about **8%** — and it stops growing there. A
bounded cost for an unbounded relationship is the trade the whole structure exists to make.

The archive's backstop is the one place in the subsystem where something is genuinely
destroyed, and it is arranged to cost as little as possible: it drops from the **folded**
prefix only. Those entries are already inside the chronicle, so what is lost is the ability
to rebuild exactly from them — not the content. Dropping an unfolded entry would lose a
fact outright, so the loop stops rather than cross that line and lets the archive sit
slightly over its cap until the next fold moves the boundary.

Bringing an exact archived line back into the prompt is an open idea, not a plan: see
`docs\ROADMAP.md`, *Recall over the archive*.

### The block reads oldest-first

```
CHRONICLE: one paragraph — the past, blurred
FACTS:     the sharp lines
OPEN:      live loops
AGREED:    pending agreements
TONE:      one line
```

The order is itself the statement: resolution improves as it approaches the present. That
is the same idea the gap markers already apply to time, applied at last to content — which
is what this document opened by claiming and had not, until now, actually done.

### Agreements

The fourth kind of content, and it was added because the first three lost something
measurable. `python ai_npc_lab\journal\journal.py memory b18 --evicted` prints what compaction actually
dropped, and among the 42 evicted facts are *"Le choix définitif d'un concept cosplay reste
à trancher"* and *"Reste à voir si la boutique rappellera V pour une collaboration
régulière"* — both recorded, both gone within two compactions, while the biography around
them survived.

Nothing was misconfigured. They were filed under a rule that forgets. The table above is
sorted by *who decides a thing is over*, and an agreement has an owner none of the other
three has:

| | decided over by |
|---|---|
| facts | the code, by eviction when the list overflows |
| threads | **the model**, by not writing the thread again |
| tone | the model, by overwriting it |
| pacts | **the clock**, and nobody else can |

That is why an agreement filed as a thread is lost: a thread dies the moment a compaction
stops mentioning it, and a compaction stops mentioning whatever the last ten turns were not
about — which is exactly what an agreement made twenty turns ago is.

A pact holds its text, the in-game second the batch that recorded it ended, and a
**horizon**. It has its own small list (`AiNpcMemoryMaxPacts()` = 4) so it never competes
with a biography for room, and it leaves that list by exactly two doors, one per actor:

- **the model omits it** → it closed it. Dropped, exactly like a thread. The same
  compaction read the transcript, so whatever happened is already in its `FACTS:`.
- **the model keeps it and its horizon has passed** → the *clock* closed it. It graduates
  into `facts`. The model still believed this was live and it is not: that is the
  stood-up case, and it is content rather than silence.

Ordering them that way means a lapse is only ever recorded when nobody noticed it.

**The horizon is a word, never a duration.** `soon` (twice the idle gap — 12 in-game hours),
`days` (three in-game days), `open` (never lapses); anything unrecognised becomes `open`.
The model cannot read the in-game clock, so asking it for "in about three hours" is asking
for arithmetic it has no basis for, and a wrong number schedules a character to sulk about
a promise that was never late. This is the same discipline `JoytoysActionPolicy` applies to
action tags: a field the model fills is validated against a closed list, not trusted.

Expiry is evaluated **lazily, at the moment the memory is rendered** — never on a timer.
An agreement can fall due while the phone is shut, and a `DelayCallback` does not survive a
save/load. `AiNpcMemoryRenderAt` already takes the clock, so the `(overdue)` marker costs
nothing; the move into `facts` happens at the next compaction, which is the next time
anything is written at all.

One rule protects the content on the way out. A pact graduates into `facts` **verbatim**,
and a fact is never rewritten — so the instruction requires each agreement to be written as
*what was said* rather than *what will happen*: "V said she would come by tonight", never
"V is coming tonight". The second becomes a false statement the moment tonight is over.

---

## Windowing policy

`AiNpcMemory.reds` owns the numbers, as functions so tests can pin them and so the policy
is stated exactly once:

| | | |
|---|---|---|
| `AiNpcMemoryWindowTurns()` | 6 | what survives a compaction verbatim |
| `AiNpcMemoryBatchTurns()` | 10 | must accumulate beyond the window before a compaction fires |
| `AiNpcMemoryMaxTurns()` | 16 | **derived** — window + batch, the steady-state bound |
| `AiNpcMemoryHardMaxTurns()` | 26 | window + 2×batch — the backstop trim, see below |
| `AiNpcMemoryIdleGapSeconds()` | 21600 | **derived** — the gap marker's clock tier; past this a conversation counts as ended |
| `AiNpcMemoryIdleMinBatch()` | 4 | messages beyond the window before silence alone may fire a compaction |

The split reuses the existing trim rather than reimplementing the "never open the window
on a reply" rule:

```
kept    = AiNpcHistoryTrim(messages, windowTurns)      // the existing function
evicted = the messages before it
```

so the two definitions cannot drift apart.

**The prompt sends the whole stored list, not `kept`.** Eviction happens at compaction time,
in the same journal entry that writes the memory — so the stored list *is* the un-absorbed
part of the conversation, and sending less than all of it would drop messages that nothing
remembers. That is the invariant, and it is worth more than the tokens it costs. In practice
the transcript settles to six turns after each compaction and grows back to sixteen before
the next.

Firing per batch instead of per turn is not an optimisation detail. It amortises the extra
request over ten player messages, keeps the memory block stable between compactions (see
prompt ordering below), and — most of all — stops the memory being rewritten, and
therefore given a chance to drift, on every single message.

---

## Persistence

The memory must ride in the journal. Storing it in a side file would resurrect exactly the
bug the journal exists to end (`AiNpcJournal.reds`, header): reload a save from an hour ago
and a character would remember a future that, on that timeline, never happened.

The good news is that no new operation is needed. `Fork` already snapshots the live state
per contact, and it *must* carry the memory or a fork would drop it. Once
`AiNpcJournalKindSnapshot` carries memory:

> **A compaction is a snapshot.** "Here is this conversation's whole state, rewritten."

One new field, one branch of `AiNpcJournalApply` touched, fork works unchanged. And the
property that actually matters comes free: **evicting the messages and writing the memory
are atomic**, because they are one line in the journal. As two operations there would be a
window — a crash, a save, a reload — in which the batch is either lost or counted twice.

`Clear` resets both.

---

## Two lanes: speaking and thinking

This is where the design is an architecture rather than an addition.

`AiNpcHttpSystem` was two things under a transport's name: an HTTP client (four backends,
DTOs, polling, error mapping) *and* the dialogue orchestrator (history, action tags, typing
indicator, bubbles, and `isGenerating`, which drives the UI). While there was only one kind
of call, the conflation cost nothing. Memory introduces the second kind and splits it open.

|  | **speaking** | **thinking** |
|---|---|---|
| addressed to | the player | the mod |
| register | in character | out of character |
| concurrency | one at a time (a real UI constraint) | one at a time, independent |
| visible | yes — typing, bubble, disabled input | never |
| on failure | carrier message to the player | silent; retried at the next batch |

Routing the compaction through the existing slot (`m_requestContact`, `playerInput`,
`isGenerating`) would grey out the player's input during a background task. That is the
patch-shaped answer and it would be visible in game.

The cut:

```
AiNpcLlm.reds            transport, backend-agnostic, no state
                         url / model / headers / credential check / chat body
    |
    +-- AiNpcHttpSystem       the speaking lane. Owns the UI-visible request.
    +-- AiNpcMemoryService    the thinking lane. Owns its own request, invisible.
```

Both lanes build their request through the same functions, so "what a usable backend is"
is defined once. Each owns its own in-flight state and its own response callback, so
neither can corrupt the other. `AiNpcHttpSystem` keeps its name: it remains the dialogue
orchestrator, and a rename would be churn across the whole codebase for no behaviour.

**Scheduling.** Compaction is offered a turn when `isGenerating` falls, i.e. after the
reply has been delivered — never before a send. The threshold has already been crossed by
then and nothing is urgent; making the player wait for two round trips instead of one to
save ten minutes of staleness would be a bad trade.

A count is not the only thing that ends a conversation, though, so there is a **second
trigger**: opening a conversation that has gone quiet. A twelve-turn exchange that simply
stopped would otherwise never compact — it sits below the batch threshold forever, its
memory empty and its `coveredUpTo` unknown, and the character has nothing to date when the
player comes back.

Three things make it safe rather than merely appealing.

**It fires on open, not on close, and the two are not symmetric.** At open the silence is a
*measured fact*: read the clock, read the last message's stamp. At close it would be a
*prediction*, and `PhoneDialerLogicController.Hide` is the catch-all for Escape, the hub
menu taking over, and combat starting. Putting the phone away because a gang opened fire is
not the end of a conversation. The close hook fires constantly and knows nothing about what
follows; the open hook fires rarely and knows exactly what happened.

This is also why there is no timer. Elapsed game time is evaluated lazily, at the moment it
is next read — a `DelayCallback` does not survive a save/load, and a conversation nobody
reopens needs no memory: the memory has to exist by the time it is *sent*, not before.

**It keeps a floor.** `AiNpcMemoryIdleMinBatch()` = 4 messages beyond the window. The idle
rule only ever *adds occasions*; it never lowers the bar for the ordinary path. Without the
floor, every dip into the phone after a night's sleep would be a rewrite — and a compaction
is not idempotent in the way a cached read is: each one re-submits `threads` to the model.
Two short compactions are two chances to drift where one full batch was one.

**It does not age threads.** This is the subtle one. `AiNpcMemoryPromoteAfter()` counts
*full batches survived*, not calls. An idle compaction rewrites and closes threads exactly
as a full one does and carries their ages through unchanged (`agesThreads` in
`AiNpcMemoryMerge`). Otherwise a player who checks the phone often would consolidate facts
faster than one who actually talks, which is backwards, and "three compactions" would stop
meaning anything measurable.

The threshold itself is derived, not chosen: `AiNpcMemoryIdleGapSeconds()` is
`AiNpcGapMarkerClockSeconds()` — six in-game hours, the tier at which the transcript itself
stops rendering a break as "later in the same scene" and starts stating the time of day. If
the history shows the player a new scene, the character is allowed to have closed the old
one. A second number here would let the two disagree about where an episode ends.

One deliberate non-guarantee: an idle compaction may still be in flight when the player
types. That is fine and needs no lock. The lanes are separate, the send goes out with the
window un-absorbed — complete and correct, merely not yet summarised — and `ApplyMemory`
re-reads the list, checks the batch is still at the front, and keeps whatever arrived in the
meantime.

---

## Prompt assembly

One rule, which also fixes a pre-existing problem rather than working around it:

> **Blocks are assembled in order of increasing volatility.**

```
corpus      rules, character, relationship, interactions, background, mechanics, language
                                                     invariant   ~1400 tk   <- cacheable prefix
<memory>    the compacted past                       every ~10 turns  ~200 tk
<mission>   tracked quest state                      every message
<now>     seeded context, live context, the clock  every message
transcript  the un-absorbed tail (6-16 turns)      every message   ~450-1200 tk
<explicitness>  one line                             invariant, last on purpose
```

`CONTEXT: it is <clock>` used to sit inside the guidelines, around token 200 of the system
prompt. The in-game clock moves between any two messages, so the identical prefix was ~200
tokens — below the ~1024-token threshold at which OpenAI-compatible backends discount a
repeated prefix, making the cache hit rate effectively zero. Moving it into `<now>` is
not a special case for the clock; it is the volatility rule applied.

The closing `<explicitness>` stays last despite being invariant: it is a recency device (see
`AiNpcGetToneReminder`), it is one line, and everything after the cacheable prefix is
uncached anyway.

### What does not go in memory

Everything the mod re-derives from live game state each request: quest tracking, transfers,
seeded context. Summarising those pays twice for a fact that is already fresh, and freezes
a stale copy that will eventually contradict `<mission>`. Memory holds only what nothing
else knows: what V confided, promises made, nicknames, running jokes, subjects that became
off-limits, where the relationship drifted.

---

## Guaranteed vs best-effort

The distinction is explicit in the code, not implied:

- **Guaranteed:** the window is bounded **in turns**. `AiNpcMemoryHardMaxTurns()` trims
  without compacting, whether or not any memory was ever written, so a broken key or a
  refusing model cannot make the transcript grow without end.

  Read that literally, because it is weaker than it first sounds: 26 turns is 53 messages,
  and nothing bounds a *message*. Measured over the 845 messages in the shipped journals —
  145 characters on average, 336 at the 95th percentile, 811 at the longest — a full window
  is about 1 900 tokens at the average rate, 4 500 at the p95 rate, and 10 700 if every
  message were as long as the longest one ever recorded here. The count is bounded; the
  size is only bounded in practice.

  The memory, by contrast, is bounded in bytes: 20 facts + 6 threads + 4 pacts + 1 tone
  line, each clamped to 240 characters, is **7 518 characters (~1 880 tokens) absolute**.
  The pre-launch estimate put real use at ~193 tokens against that ceiling; the journals the
  game has since written say **284–535** (`journal.py memory`), so the margin is nearer 3:1
  than 6:1 — still a backstop, but a less comfortable one than the first measurement
  suggested. The per-entry cap comes from the
  corpus: 1 118 sentences these characters actually wrote run to 155 characters at the p95
  and 212 at the p99, so 160 would have truncated roughly one natural sentence in
  twenty-five and 240 truncates one in two hundred and fifty. A truncation backs up to a
  word boundary and ends in an ellipsis, because a fact is never rewritten and a cut that
  stays grammatical is a permanent false statement.
- **Best-effort:** the memory. A failed request, a `HTTP 0`, an unparseable reply → nothing
  changes. The previous memory stands, the messages are not evicted, no banner is shown.
  The next batch tries again.

Two rules protect the content itself:

- The thinking lane uses **the same endpoint and the same model** as the dialogue. A
  `NSFW_Hard` exchange summarised by a censored endpoint comes back as a refusal, and a
  refusal stored as a character's memory is a bug nobody diagnoses.
- The reply is parsed into the typed model and clamped before it is stored. It is never
  kept as raw text. A reply with no recognisable section header is rejected outright —
  which is what an apology, a refusal or a chunk of prose looks like.

---

## Contact providers

Two additions, in the style of the existing short opt-outs (`AllowsGenericTransfer`):

- `AllowsMemory() -> Bool` — an automated number that has no memory is characterisation,
  not a limitation. A provider must be able to say no.
- `GetSeedFacts() -> array<String>` — what a contact knows about V before the first
  message. Seeded into `facts` at the first compaction.

---

## Settings

**Conversation Memory**, in *Mod Settings -> AI NPC -> Memory*, default on. Off restores
the previous behaviour exactly: a hard-trimmed window, no second request, no memory block.
It was `memoryEnabled` in `settings.json` until 2026-08-22; a key of that name left in the
file is now ignored, and startup logs one line saying so.

**Memory Size**, same category, default 20, range 8-40 in steps of 4. How many consolidated
facts a character keeps in front of it -- the cap enforced by `AiNpcMemoryClamp`, which the
measurement under *Cost* puts at 20. The two directions are not symmetric, and the menu says
so:

- **raising it** costs tokens and nothing else: about 30 tokens per fact, on *every* request,
  because the memory block sits after the cacheable prefix. Facts already archived come back
  into reach as the compactions go on.
- **lowering it** evicts, at the next compaction, every fact that no longer fits. Eviction
  moves a fact to the archive rather than erasing it -- the chronicle can still be rebuilt
  from it, and nothing is destroyed -- but it leaves the prompt, and the character stops
  knowing it.

The floor of 8 is not a taste: eviction starts *after* the founding prefix
(`AiNpcMemoryFoundingFacts`, 4), so a budget that does not clear it would leave the clamp
evicting the identity of the relationship. `AiNpcMemoryClampFactBudget` enforces both bounds
on the way out of the setting, and `tools/lint.ps1` pins them to the range the menu
advertises.

`memoryChronicleExact`, default on. Whether a fold is rebuilt from the whole archive or
merely extended — see the table under *Nothing is deleted*. Off is worth having: 8% of
somebody else's API bill is not this code's decision, and a local llama and a metered
frontier endpoint do not want the same answer. Either way the choice stays reversible,
because the archive is kept: turning it back on repairs whatever the cheap mode
accumulated while it was off. That is what an archive is for.

---

## Cost

| | before | after |
|---|---|---|
| input per message | ~3 000 tk | ~1 900-2 800 tk (sawtooth: lowest just after a compaction) |
| cacheable prefix | ~200 tk (unusable) | ~1 400 tk |
| extra requests | — | 1 per 10 messages, off the critical path |
| recall past 20 turns | none | degraded |
| journal | 1 line/message | + 1 snapshot per 10 turns (~1–2 KB) |

The money saved is noise at the default model. The prefix cache and the disappearance of
the recall cliff are the real returns.

### What the block itself weighs, measured on a real save

The figures above are the cost of the *scheme*. This is the cost of the block one contact
actually sends, read off branch `b37` of the shipped journal on 2026-08-22 --
`python ai_npc_lab/journal/journal.py memory b37` renders every snapshot exactly as the prompt builder
would and reports its size, so this needs no game and no guessing:

| facts held | rendered | tokens |
|---:|---:|---:|
| 4 (founding only) | 427 chars | 106 |
| 8 | 1 138 chars | 284 |
| 11 | 1 557 chars | 389 |
| 12 | 2 041 chars | 510 |
| 17 | 1 873 chars | 468 |

So **30 to 40 tokens per fact**, and with `AiNpcMemoryMaxFacts()` at 20, **about 550 tokens at
saturation**. The two 12-fact contacts weigh more than the 17-fact one because entries vary in
length (p50 97 chars, p95 131, clamp 240): the fact count is a bound on the count, not on the
bill.

Why it is worth stating in tokens rather than in facts: on a free provider the day is metered,
not the conversation. At Groq's free 200 000 tokens per day, a saturated memory block is about
11% of every request, which is more than the whole command vocabulary costs -- see
`docs/PROMPT_BUDGET.md` for the rest of that arithmetic and for what it argues about
per-feature toggles.

---

## Measured, on real data

Replaying the shipped journals through a port of the pure half, and running the compaction
prompt over one real 28-message batch (a `river_ward` conversation), two rounds:

| | |
|---|---|
| transcript replaced | 953 tk |
| memory stored | 193 tk (~5:1) |
| parse | accepted on both rounds, first try |
| round-1 facts after round 2 | kept verbatim |
| open threads | 3 → 1, closed by omission |
| a simulated refusal | rejected, nothing stored |
| entry length vs the 160-char cap | 60–90 chars — the clamp never bit |

Three findings, all of which changed something:

1. **A thread was opened that its own batch had already closed** — a question asked early
   and answered later in the same messages. It heals at the next compaction, but a window
   is ten turns of a character raising a settled subject. The instruction now says to judge
   each thread as of the *last* message of the batch.
2. **Facts accumulate faster than threads close** — seven after two rounds, against a cap of
   twelve. That is what produced the founding-facts rule above.
3. **The note came back in French**, following the transcript, while the instruction is in
   English. That is the behaviour we want, and nothing guaranteed it; the instruction now
   states it.

Two things this did *not* measure: the quality of a weaker model's note (this was run
through a frontier model, and `gpt-4o-mini` or a free OpenRouter model will drift further),
and the in-game path — journal write, reload, fork.

Also worth knowing before the first launch: **only 19% of the messages in the existing
journals carry a timestamp**, so most memories restored from an old save will have no
coverage and will simply not date themselves. And the first compaction of an existing long
conversation absorbs 28–40 messages at once rather than the nominal ten turns, because
those conversations are already past the threshold.

## Measured in play

The section above was measured *before* the first launch, by replaying journals through a
port of the pure half. `python ai_npc_lab\journal\journal.py memory b<N>` measures the same thing on
what the game has actually written since: it walks a branch's snapshots in order and diffs
each against the one before, which is the only way an eviction is visible — a fact is never
rewritten, so a fact present in snapshot N and absent from N+1 was evicted, and nothing
else can produce that.

On `b18` — 5 contacts, 16 compactions:

| | |
|---|---|
| facts recorded | 59 |
| facts evicted | 42 (**71%**) |
| threads promoted into facts | 2 |
| rendered memory | 284–535 tk, against ~193 predicted |
| entry length vs the 240-char clamp | p50 121, p95 173, max 229 |

Three things came out of it, and each changed something.

**1. The fact cap was the binding constraint, not the entry length.** The clamp still never
bites; the *list* saturates constantly (12/12 on five of eight contact-branches). The tool
replays the same content at other caps and prints what each would have cost:

| cap | facts evicted on b18 |
|---|---|
| 12 | 41 — what shipped |
| 16 | 25 |
| 20 | 10 |
| 24 | 2 |
| 32 | 0 |

`AiNpcMemoryMaxFacts()` is now **20**, where the curve bends. It costs ~250 tokens at
saturation, paid on every message — the memory block sits after the cacheable prefix, so
none of it is discounted. 24 buys eight more facts for another ~120 tokens, which is a
worse trade.

**2. Agreements were being recorded and then lost.** See *Agreements* above; this is where
`pacts` came from.

**3. Rendering fewer facts than are stored does not work.** The obvious way to buy the
~250 tokens back was to store 20 and render the 12 most relevant. Measured before writing
any of it, over the 180 player messages in the journals sent while a memory of six or more
facts was in force:

| facts sharing a content word with the message | share of messages |
|---|---|
| none | 60% |
| one or none | 84% |
| average | 0.7 of 10.3 stored facts |

and the matches that do occur are the two longest facts matching nearly everything, on
words like *clients* and *heure*. The reason is structural rather than a matter of a better
scorer: a texting conversation refers to its own past by pronoun and by continuation, while
the facts are the model's paraphrase of it. The two do not share a vocabulary. A selector
built on that signal would drop eight facts at close to random, and the failure would be
invisible — the character would simply seem to forget, which is the symptom the whole
subsystem exists to fix.

So the render budget and the storage cap are the same number, deliberately, until something
better than word overlap is available inside redscript. The measurement is cheap to repeat
if that changes.

What replaced the idea is not a better selector but a different answer to the same
question: the facts past the cap are not *chosen between*, they are **kept and blurred**.
See *Nothing is deleted* above. Selection asks which twelve of twenty to send; the archive
and the chronicle send all twenty and a paragraph for everything before them.

**4. The re-asking is not caused by forgetting.** This one arrived last and reorders the
rest. Tracing every mention of V's age through `journal.b18`, contact `anon_259272939`:

```
#5    NPC | T'as quel âge en vrai ?
#6    V   | 27 ans. Et toi ?
      [compaction — the fact is recorded]
#97   NPC | Ok dernière un peu perso promis : t'as quel âge en vrai ?
      [compaction — the fact is still there]
#113  NPC | Juste une dernière truc avant de fixer l'heure : t'as quel âge en vrai ?
#114  V   | Mais si, 27 ans; deux fois que je te le dis
```

The player counts it out loud at 114 — and the fact was in the `<memory>` block at every
one of those compactions. Nothing was forgotten. The block was read and not obeyed.

The cause is upstream, in the contact's own persona: `anon.curious_fr.json` states *« Tu ne
connais ni son nom, ni son quartier, ni son âge »* and sets the character out to go looking
for exactly those. That text is true of the first message and permanent in the prompt — it
sits in the invariant corpus prefix, ahead of everything, while the memory block is smaller
and further down. The character definition wins on placement and the memory loses.

The fix is in `AiNpcMemoryRenderAt`, because that is the only place that knows both sides:
the block now states its own precedence — *everything here you already know, never ask
again, and where your description says you do not know something and this block does, this
block is right.* Editing one persona would have left the next one to rediscover it, and a
persona **should** be free to say what its character does not know. It just has to mean
"not yet", which is what the precedence line makes it mean.

Worth keeping in view when reading everything above: **loss and repetition are two
different measurements, and only the second is visible to the player.** A character who
forgets V's age once is human. One that asks every ten messages is broken. Cap sizes,
archives and chronicles all address the first; this one line addresses the second.

---

## Testing

Everything except the request itself is pure — split, clamp, render, parse, merge,
promotion, replay with memory — and runs in `tests\AiNpcTestMemory.reds` with no session, no disk and
no network, exactly as `AiNpcHistory` already does. The order the work was done in follows
from that: model and pure functions first, then journal and store (the tranche where bugs
cost an evening, and the one that is fully verifiable offline), then the lanes, then the
prompt reordering.
