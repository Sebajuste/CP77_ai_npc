# The channel: the entry point of a conversation

`docs/PLAN_HOLO_LANE.md` says the holo costs nothing existing: a renderer, an input, a style,
a session slot, and no file changes behaviour. That is true of a third *surface*. It is false
of the holo, and the reason is one sentence:

> **The holo is spoken. The phone and the terminal are written. That is not a difference of
> surface, it is a difference of channel — and a channel owns a turn, it is not a flag carried
> through one.**

Two requirements pull in opposite directions:

- what is said on a call must **not** appear as a written message;
- the memory is **shared** — one character, one history, whether the words were typed or said.

This document states the model that satisfies both. It is a design, not a report: nothing below
is implemented.

---

## 1. The pipeline has no owner today, and it already costs

The player's half of a turn is four steps in a fixed order: read the contact off the session,
echo the line, ask the lane, file the line. The order is a trap — filing before sending sends
it twice, because the lane reads the transcript from the store and is handed V's line
separately.

That sequence is written **twice**, in `AiNpcSystem.SendTyped` and in `AiNpcTerminalChat`, with
the trap commented in both. The reply's half is the same shape: `AiNpcDeliverOrNotify` offers
the line to every registered surface and falls back to an SMS push, and every decision about
*what kind of conversation this is* lives at whichever call site happened to need it.

So a third surface does not add a channel to that pipeline. It adds a third copy — and then a
sixth `if this is a call` in a sixth file, for the notification, the prompt, the delay, the
cleaner, the thread and the transcript.

**The channel is the owner that was missing.** A surface hands it a line; it does the rest, in
the one right order, and each channel answers for itself what a conversation of its kind means.
The holo then adds a file rather than a copy, and the `if`s never exist.

---

## 2. Two things, and they must not be confused

| | what it is | where it lives |
|---|---|---|
| `AiNpcChannelId` | the value that is **stored and compared** — an integer in the journal, an equality test in a predicate | `AiNpcEnums.reds`, the file whose stated job is that enum values are a compatibility surface |
| `AiNpcChannel` | the object that **owns a turn** — send, deliver, clean, and what to tell the model | `AiNpcChannel.reds`, and one file per implementation |

Identity is stored; behaviour is resolved from it. A class cannot go into a save, and an integer
cannot own a pipeline.

```
enum AiNpcChannelId {
    Text = 0,     // the phone, the terminal, an SMS notification
    Call = 1,     // the holo
}
```

`Text = 0` is the whole migration. Every stored line, every default, every renderer that says
nothing reads back as Text, which is what it has always been. Nothing is converted, nothing is
versioned, and a history written before this existed renders byte for byte as it does today.

`Call` and not `Voice`, because the axis is the medium and not the sound: a face-to-face
conversation would be spoken too. A third value is one enum entry and one file — nothing
structural. That is the test that this shape is the right one.

---

## 3. What a channel is

```
public abstract class AiNpcChannel extends IScriptable {

    // What goes on disk, and what a surface is matched against.
    public func Id() -> AiNpcChannelId

    // The player's half of a turn, in the one right order. The session echoes, ends the
    // typing state and scrolls; the lane call and the filing are mine.
    public func Send(session: ref<AiNpcChatSession>, text: String) -> Void

    // The outcome of a turn, to whoever can show it on me -- and my own answer when nobody
    // can. Called when the turn CONCLUDES, which may be several requests after Send.
    public func Deliver(contactId: String, text: String) -> Void

    // Run before the line is stored, so that what is filed is what was said.
    public func Clean(text: String) -> String

    // The <channel> rubric: one fact, one line.
    public func PromptLine() -> String

    // Nobody takes eight seconds to answer on a call.
    public func ReplyDelay(text: String) -> Float

    // Does the written thread paint my lines.
    public func ShowsInThread() -> Bool
}
```

Two implementations now, `AiNpcChannelText.reds` and `AiNpcChannelHolo.reds`, one file each per
rule 1. `AiNpcChannelOf(id)` resolves one; they hold no state, so resolving is allocating.

### What it is not

**Not the door.** `AiNpcChatDoor` is the one place a conversation *opens and closes*; the
channel is the one place a turn is *spoken and answered*. Different verbs, different lifetimes,
and merging them would put the memory service's one trigger point inside the send.

**Not a session, and it must never be registered as one.** `AiNpcChatRegistry` is
first-refusal: whatever answers true takes the reply and the others never see it. That is the
trap the POC plan records for a "sound session", and it applies here for the same reason.

**Not pure, and that is a role rather than a slip.** `Send` and `Deliver` reach for systems, so
they cannot be asserted at `AiNpcStorageService` attach, where no `ScriptableSystem` exists yet.
That is exactly the "thin adapter does the fetching" of rule 3b — and testability *rises*: two
untested copies of the send become one. `Clean`, `PromptLine`, `ReplyDelay`, `ShowsInThread` and
`Id` touch nothing, so a test constructs a channel and asserts them.

---

## 4. What each channel answers

| | `AiNpcChannelText` | `AiNpcChannelHolo` |
|---|---|---|
| nobody rendered the reply | the SMS notification, through the existing phone-controller resolver | nothing is pushed. The line is filed, so the memory keeps it |
| `Clean` | the line as written | emoji, markdown and stage directions removed |
| `ReplyDelay` | as today, modelled on typing | short |
| `ShowsInThread` | true | false |
| `PromptLine` | § 6 | § 6 |

The `Call` fallback is the one that would be a visible defect if it were forgotten: an SMS of
what a character said out loud on the phone.

A missed call is a notification of its own kind and belongs to the call system, not here. It can
wait, **because** the fallback above is silent rather than wrong.

### The cleaner is the channel's, and it runs before the line is stored

A spoken channel makes some of what a model writes meaningless: emoji, markdown, and the stage
directions that are Mantella's most-reported quality defect — bracketed narration read out loud
(§ 10 of the POC plan).

Cleaning for the ear alone is not enough, and putting the cleaner beside the speaker gets it
wrong twice: an emoji cleaned only for the sound is still **painted** on the holo, where nothing
of the kind exists in a voice, and it is still **stored**, so it returns in the next request's
transcript and teaches the model that emoji belong on a call. The prompt would be arguing with
the history.

So `Clean` runs on the way in, at the point where the lane already processes a reply — where
`AiNpcApplyActions` hands back its `processedText`, the one text that then goes to the surface
and to the store. One text, cleaned once, filed, painted and spoken.

This does not leak sound into the lane, which is the invariant the POC plan protects. The lane
learns that a channel is spoken; it does not learn that a speaker exists.

---

## 4b. The turn is the generation's, not the channel's

`docs/PLAN_MODEL_SLOTS.md` gives each kind of work its own model, and the action selector it
enables is a **second, short call inside one turn**: the character writes plain prose, and a
cheap call reads it back and answers with the action or `None`.

A channel must therefore be able to hold the turn while an analysis prompt runs. It can,
because it never holds it in the first place:

> **The turn is held by `AiNpcGeneration`.** The channel opens it and receives its outcome.

That is not a provision for the future — it is running today. `TryRepairActions` sends a second
request inside one generation, on `AiNpcLaneRepair()`, keeping `isGenerating` true, re-arming
the watchdog the first answer disarmed, and carrying an `m_repairSerial` so a reply that arrives
after its turn is dropped. The repair budget lives on the generation for the stated reason that
it is *generation-scoped*: one repair per thing V said.

So `Send` starts a turn and `Deliver` receives its conclusion, however many requests apart those
two moments are. A channel that held the turn itself would have to model a small state machine
in competition with the one that exists, and would have to learn how many requests its turn
cost — which is none of its business.

**The two axes do not cross.** A slot says what kind of *work* a request is (dialogue, memory,
mechanic); a channel says what kind of *conversation* it belongs to. The selector runs on
`mechanic` whether the player is texting or on a call. Do not make a slot channel-dependent: the
slots plan already names its one foreseen migration (per-provider namespaces), and a second
dimension would be a third. If a call ever needs a faster model for latency — the one complaint
Mantella's players make most — that is a **new slot name**, declared like any other, not a
dimension on an existing one.

**Two ordering constraints the pair creates, and neither plan states.**

1. **The selector runs before `Clean`.** A stage direction is exactly the action intent the
   selector exists to read — `*hands you 500 eddies*` — and `Clean` deletes it. Cleaning first
   destroys the selector's input. Clean what is *stored*, after the turn has been read.
2. **The selector's own prompt needs the `<channel>` line.** It is given who is talking to whom,
   the last few messages and the reply just written; an action is not offered the same way aloud
   and in writing.

And one synergy that is real rather than symmetric: the selector takes the brackets out of the
prose entirely. The first source of "stage directions read out loud" disappears **by
construction**, so the spoken channel gains more from the slots plan than the written one does.

---

## 5. The history is one, and the filter is at the reading end

**The split is at the reading end, never at the writing end.** One store, one ordered
per-contact list, one chronology. A second store for spoken lines would satisfy the first
requirement and destroy the second: the memory service, the compaction, the arc facts and the
transcript would each have to merge two sources in order, and one of them eventually would not.

| what | what it reads |
|---|---|
| the memory, the summary, the compaction, the prompt transcript | **everything**, unfiltered |
| the phone and the terminal | the `Text` lines |
| the holo | the `Call` lines |

The sharing is the **absence** of a split. Nothing is plumbed for it.

### The record

`AiNpcMessage` gains a `channel`. In `api\` because a consumer reads the fields of a message it
is handed back, so it is part of the published contract the moment a spoken line can exist.

Persisted as `"c": 1`, **omitted when Text**, read back as Text when absent — the convention
`"g"` already carries for an unknown timestamp, and for the same reason: a snapshot written
before the field existed is not wrong, it predates the question. `SCHEMA_VERSION` does not move.

`AiNpcAppendMessage` gains `opt channel`, last, so every existing call site files Text without
being edited; `AiNpcConversationStore.Append` passes it to the journal op. A channel that
stopped at the store's door would never reach the disk.

### The renderer declares its own — rule 3 of `VIEW_ARCHITECTURE.md`, unchanged

`AiNpcChatRenderer` gains one verb beside `SplitBudget()` and `HistoryLimit()`:

```
public func Channel() -> AiNpcChannelId {
    return AiNpcChannelId.Text;
}
```

The default is Text, so **`AiNpcPhoneRenderer.reds` and `AiNpcTerminalChat.reds` need no edit
for it**. It vindicates the seam rather than straining it: the holo answers `SplitBudget() = 0`,
because splitting a spoken line across two bubbles means nothing, and the API already has that
answer.

Two pure functions in the session grow one parameter each and stay assertable with no system
alive:

```
AiNpcIsDisplayableMessage(message, surface: AiNpcChannelId) -> Bool
AiNpcSessionAccepts(shownContactId, targetContactId, surface, reply: AiNpcChannelId) -> Bool
```

### The channel of a reply in flight is captured at send time

`AiNpcGeneration` exists to enforce one invariant: *a request is addressed once, at send time,
and nothing downstream re-asks*. The contact is captured there because delivery happens a
`DelayCallback` plus a round trip later.

The channel fails the same way and is captured beside it. A player who hangs up while the reply
is in flight would otherwise have a spoken line painted into the SMS thread. No new mechanism:
one field on the object that already exists to stop this class of bug.

### The call marker is derived, never stored

The decision taken: a call leaves **a line in the written thread, without its content**.

That line is not a record. It is derived the way the transcript's time markers are derived from
timestamps: a run of `Call` lines between two `Text` lines *is* a call, and its first and last
timestamps *are* its start and its duration. One pure function family in `AiNpcHistory.reds`,
two renderings — a divider on the phone, and a parenthesised marker in the transcript, in the
grammar that never touches the `V: ` / `<name>: ` pairing the stop sequences rely on. Proposed
wording, **not to be written without the user's word**: `(on a call)`, `(back to messages)`.

The divider needs `AiNpcChatRenderer.AppendDivider(label)`, defaulting to a no-op, so the phone
file is edited once, additively, at the step that draws it and not before.

---

## 6. The prompt: one rubric, `<channel>`, right after `</now>`

No such notion exists today: the word appears only in comments, in its ordinary sense, and the
phone and the terminal build the same prompt byte for byte. There is already one channel, it is
implicit, and it is Text.

The medium is stated in two places today, and both are wrong on a call:

- `<fiction>` — "texting V on a phone";
- the `REACH` rule — "You reach V only by text message".

Neither is a good home. `<fiction>` is the block that is *identical for every contact and every
save*, which is what lets it lengthen the cacheable prefix; a sentence that changes with the
medium does not belong in it. `REACH` is composed per contact and overridable by another mod,
which could leave a character believing it is texting during a call.

**Position: its own tag, immediately after `</now>`, and it is forced rather than chosen.** The
channel varies from one generation to the next, so it cannot sit in the shared prefix — and the
prefix ends at `<now>`, whose clock is the most volatile thing in the prompt. Below that line it
costs no cache that was not already spent.

Not *inside* `<now>`, a container of world statements many contributors write into. The one
positional measurement this repo holds says a sentence placed among them becomes one more thing
the character happens to know: the unprompted reason was the subject 0 times out of 8 there, and
8 out of 8 in V's slot. That was about a *subject* rather than a form constraint, so it does not
transfer — it warns. A line that constrains the shape of a reply is not a line the character
knows.

And **not last**: `<explicitness>` is a settings-wide tier that ignores its `contactId` entirely,
defined near the top and *restated* at the very end for a measured reason — without that
restatement the SFW tier repeated V's explicit words back to her 10 times out of 10. The last
slot belongs to a prohibition that had to survive the transcript.

Proposed content, **one fact, one line, no second sentence**, and not to be written without the
user's word:

| channel | `<channel>` |
|---|---|
| `Text` | `You and V are texting.` |
| `Call` | `You and V are on a call.` |
| *(later)* `InPerson` | `You and V are face to face.` |

**A fact and nothing else.** An earlier draft added "no emoji, no formatting, nothing written
down" to the `Call` line — the engine's work handed to the model as a request. A prompt clause
is a request; `Clean` is the guarantee. What the engine can make true, the prompt does not ask
for.

`REACH` keeps its second half, the one that points at `<mechanics>` for the command vocabulary:
that is true on every channel. `<fiction>` loses three words and stays identical for everyone,
so the shared prefix is shortened, never broken.

None of this has to stay argued: `tools\prompt` rebuilds the real prompt offline and the bench
runs against it, so the position is measurable — remembering that n = 3 is below the noise
floor.

**A channel already written by hand.** Jackie's sheet drops the Heist entry entirely, because
"he is beside V from the Afterlife briefing to the Delamain, so the phone is never the channel".
That is an `InPerson` conversation reasoned about in prose before the concept existed, and it is
the best evidence that the third value is real rather than a symmetry.

---

## 7. One channel is live at a time — and the history is mixed anyway

Only one channel is ever in flight, and that is not a rule this design adds: the speaking lane
holds **one** `AiNpcGeneration` and refuses a second while one is open. So there is no merging of
two `<channel>` lines and no concurrency story to write.

One generation, not one request: a turn already spans two calls when a repair fires, and will
span more with the action selector (§ 4b). Every request of a turn carries the channel its
generation captured, so the count never matters here.

Two things look like consequences of that and are not:

- **The channel is still captured at send time.** There is only one selected contact at a time
  either way, and the contact is captured all the same. "One at a time" says nothing about
  *which* one, later.
- **The stored thread is permanently mixed.** Live-ness is single; history is not. The display
  filter is therefore not a concurrency guard and cannot be dropped as one. The concrete case:
  the phone session is still registered when a call ends, so a late spoken reply would land in
  the SMS thread with nothing but that filter in the way.

---

## 8. What the linter must forbid

Beside the four rules of the POC plan:

5. **A channel is decided in two places only**: the renderer that declares its id, and the
   generation that captures one. No `AiNpcChannelId` literal in a widget or a builder.
6. **Nothing outside the session filters by channel.** The memory service, the compaction, the
   transcript and the arc facts read the whole thread; a channel test in any of them is the
   shared-memory requirement being quietly undone.
7. **The send sequence exists once.** No `TriggerPostRequest` outside `AiNpcChannel*` and the
   lane itself. This is the rule that keeps the duplication from coming back, and the one that
   would have caught it in the first place.

---

## 9. What this changes in the POC plan

`PLAN_HOLO_LANE.md` § 8 said the session, the registry, the store and the action lane must not
be touched, and that a step needing one of them has found a wrong seam. That was right about
surfaces and wrong about channels, so it is amended rather than worked around.

**Touched, deliberately, additively, all defaulting to Text:**

| file | what it gains |
|---|---|
| `AiNpcEnums.reds` | the id |
| `api\AiNpcMessage.reds` | the field |
| `AiNpcJournal.reds` | the `"c"` key, omitted when Text |
| `AiNpcConversationStore.reds` | one parameter on `Append`, passed straight through |
| `AiNpcConversationApi.reds` | `opt channel` on the one door |
| `AiNpcGeneration.reds` | the channel captured at send time |
| `AiNpcHttp.reds` | the send states it; the reply is cleaned and filed with it |
| `AiNpcChatRenderer.reds` | `Channel()`, defaulting to Text |
| `AiNpcChatSession.reds` | the parameter on the two pure predicates |
| `AiNpcSystem.reds`, `AiNpcTerminalChat.reds` | **their duplicated send becomes one call** |
| `AiNpcNotification.reds` | the push becomes what the Text channel calls, not what everyone calls |
| `AiNpcPromptBuild.reds`, `AiNpcPromptSections.reds` | `<channel>`, and the medium out of `<fiction>` and `REACH` |

**New:** `AiNpcChannel.reds`, `AiNpcChannelText.reds`, `AiNpcChannelHolo.reds`.

**Still not touched:** `AiNpcPhoneRenderer.reds`, every other phone file,
`AiNpcChatRegistry.reds`, the action lane.

### The risk, stated plainly

This rebuilds the most load-bearing path in the mod. The send and the delivery carry invariants
won the hard way: the contact captured at send, first-refusal ordering, the notification
fallback, carrier lines, the action pass and its repair, the memory notification, and the filing
order. None of that is provable offline beyond compilation, the linter and the suite.

So the step that does it is verified **on the existing surfaces, before any holo exists**:

> **Step 0 — the channel owns the turn.** No new pixels, no sound, no call. The phone and the
> terminal send and receive through `AiNpcChannelText`, and everything else is unchanged.
>
> **Kill:** anything the phone or the terminal did before and does not do now. Stop and revert —
> a third surface is not worth a regression on the two that work.

It comes before the beep for a second reason: the stored channel cannot be retrofitted once
spoken lines exist in players' journals.

---

## 10. What must not be claimed

Nothing above is implemented, and none of it is verified. `lint.ps1` and `compile-check.ps1`
will say that the rules hold and that it compiles — never that a spoken line stayed out of the
SMS thread, and never that the phone still sends. That takes a launch, by the user, on a save
whose threads already have messages in them.
