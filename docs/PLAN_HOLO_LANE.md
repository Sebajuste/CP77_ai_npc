# Plan: the call lane, and a third surface

A proof of concept. It answers three questions and refuses every other piece of work that
looks adjacent.

1. Can the mod make a sound while the game is running?
2. Can a call be started and shown without authoring a scene?
3. Does the mod take a third surface without any existing file changing behaviour?

Question 3 is not measured. It is answered by construction, and this plan is wrong if it
cannot be.

---

## How to work on this

The steps below are ordered so that each one is verifiable alone and can kill the next. Do
them in order and stop at the first that fails: the value of this plan is in what it lets you
abandon cheaply, not in what it builds.

**No existing file may change behaviour.** A step that needs the phone, the terminal or the
registry to be edited has found a wrong seam. Stop, say so, and do not paper over it — this is
the whole subject of rule 2 of `CLAUDE.md`.

Step 0 is the one exception, and it is an exception because it was argued in writing rather
than discovered halfway through a step: the channel takes ownership of the send and the
delivery, which are written twice today. Every default reads Text and no existing behaviour
changes — and the step that does it is verified on the phone and the terminal, before any holo
exists. `docs/PLAN_HOLO_CHANNEL.md` § 7 holds
the list. Anything else that wants out of this rule gets the same treatment or does not
happen.

The agent builds zips and runs the offline checks. The user installs through Vortex and
launches. Nothing here is deployed by an agent.

### What "done" means

From the phone, the player calls a contact. A call widget shows for a few seconds. The
character picks up and is displayed. A text field takes a line. A reply comes back, is painted,
and a beep is heard.

Nothing else. No voice, no lip sync, no speech-to-text, no second character, no persistence.

---

## 1. The design: a third surface, and one new concept

The mod already draws one conversation on two surfaces. `docs/VIEW_ARCHITECTURE.md` states
what that costs and what it buys, and the holo pays the same price:

| per surface | shared |
|---|---|
| a renderer (`AiNpcChatRenderer` subclass) | the session's behaviour |
| an input | the store, the speaking lane, the action lane |
| a style file — lengths, margins, anchors | `AiNpcStyle` — colour roles, fonts, case |
| a session instance in `AiNpcChatRegistry` | the door, `AiNpcChatDoor` |

So the holo is `AiNpcHolo*`, beside `AiNpcPhone*` and `AiNpcTerminal*`, and the list above is
the whole of it.

Two things are genuinely new, and they are the only two places this plan can go wrong.

**A third one was found after this plan was written, and it invalidates the table above.** The
holo is spoken, so what is said on it must not appear as a written message, while the memory
stays shared. That is not a surface, it is a second **channel**, and a channel is a property of
the stored line rather than of the widget that paints it. The model is
`docs/PLAN_HOLO_CHANNEL.md`; it adds a step 0 to § 5 and amends § 8.

### The call is a state, not a surface

A surface exists while its widgets exist. A call has moments no widget can report — dialing,
ringing, picked up, refused, hung up — and *building the widget is one of those moments*. Put
the lifecycle in the renderer and the renderer has to exist before it exists.

So the call lives in a system, and the renderer is built when the system says the call
connected. This is the same split as lint rule N+5, "hooks report, they never decide": the
widget layer reports that a tree was built, it never concludes that a call is in progress.

The call's nearest relative in this mod is not a surface at all — it is `AiNpcNotification`.
Both are "something happened outside the chat and may become a chat".

### The audio is not a session

`AiNpcChatRegistry` iterates most-recently-registered first, and **the first session that
answers true takes the reply; the others never see it.** Sound does not take the reply instead
of painting it — it renders it as well.

A "sound session" registered in that list would therefore swallow replies, and the phone would
stop painting. It compiles, the linter has nothing to say, and in game it reads as the chat
having broken.

**The holo renderer owns its audio.** `AppendMessage` paints and speaks. One session, one
renderer, two renderings. Nothing else in the mod learns that sound exists.

---

## 2. The states of a call

```
Idle --> Dialing --> Ringing --> Connected --> Ended
                 \-> Refused        \-> Missed
```

- **Dialing** is entered by the player, from the phone.
- **Ringing** is a delay, armed through the existing lane-callback pattern
  (`AiNpcLaneCallback.reds`): a `DelaySystem` timer cannot be cancelled and does not belong to
  the session that armed it, so it resolves through its lane or does nothing.
- **Connected** is the only transition that crosses `AiNpcChatDoor`. A call that is never
  picked up must not open a conversation, must not publish `ConversationOpened`, and must not
  reach the memory service. **It crosses the door on the holo's session, never on the phone's:**
  the conversation a call opens is a spoken one, and opening the written thread instead is the
  defect `docs/PLAN_HOLO_CHANNEL.md` exists to prevent. So the crossing waits for the channel
  (step 0) and the surface (step 4); it is absent from step 2 rather than faked through the
  phone.
- **Ended** tears the widgets down, which unregisters the session — in that order, per rule 1.

**A call does not survive a save.** No persistent field, no restore. A save taken mid-call
reloads Idle. This is a decision, not an omission: a call is a moment, and the mod already has
a lane for things that must wait for a moment to come back — the want-to-say queue — which is
not this plan's business.

`AiNpcCallState.reds` holds the enum and the legal transitions as **pure functions over plain
data**, so `tests\AiNpcTestCallState.reds` can run them at `AiNpcStorageService` attach, before
any `ScriptableSystem` exists. Same constraint as rule 3b, same reason.

---

## 3. File layout

New, and nothing else:

| file | role |
|---|---|
| `AiNpcCallState.reds` | the states and the legal transitions. Pure. |
| `AiNpcCallSystem.reds` | the machine, as a `ScriptableSystem`. Owns the timers. |
| `AiNpcHoloResolver.reds` | the single walk of the game's call tree. All-or-nothing. |
| `AiNpcHoloWidgets.reds` | the builder: takes a parent, returns anchors, keeps nothing. |
| `AiNpcHoloRenderer.reds` | `AiNpcChatRenderer` subclass. Paints, and speaks. |
| `AiNpcHoloInput.reds` | the field. |
| `AiNpcHoloStyle.reds` | this surface's lengths. |
| `AiNpcSpeaker.reds` | the audio seam. |
| `tests\AiNpcTestCallState.reds` | the transitions. |

Touched:

- the files of step 0, listed in `docs/PLAN_HOLO_CHANNEL.md` § 9, plus the three new `AiNpcChannel*`.
- `AiNpcHooks.reds` — only if the call needs a vanilla callback, and then it reports a fact.
- `tools\lint.ps1` — the four rules in § 6, plus the two the channel adds.
- `plugin\Audio.{hpp,cpp}` — playing a buffer, with no RED4ext dependency, which is what lets
  `plugin\test\run.ps1` build and run it outside the game.
- `plugin\ScriptApi.cpp` and `AiNpcAudioNative.reds` — the second native class. Read the head of
  `AiNpcCliNative.reds` first: each declared type is one more line in the error that stops the
  **game** from starting when a plugin fails to load.

**No asset, so the packager needs nothing.** The tone is synthesised in the DLL. `src\r6\audioware\`
was planned for a manifest and a `.wav`, and neither exists: if one ever does, extending
`tools\package.ps1` is part of adding it, and the check afterwards is the **contents of the zip**,
never the contents of `src\`.

### The input field comes from the terminal, not the phone

The phone's field is Codeware's `HubTextInput`, resolved in `AiNpcPhoneInput.reds` — the mod's
last dependence on Codeware. The terminal's field is the mod's own.

The holo takes the terminal's. The POC then adds no dependency at all, and the eventual
speech-to-text lane replaces a field the mod wrote itself.

---

## 4. The audio seam

**Measured on 2026-08-31, in game, and it replaces the whole of what this section argued.**

`ai_npc.dll` plays a PCM buffer held in memory through `waveOut`. No file is written, none is
read, and Audioware is not in the loop. From a save, through the CET window's *Test speaker*
button, the log said:

```
AiNpc.AiNpcCli registered.
AiNpc.AiNpcAudio registered.
beep: ok -- it went to the Windows default output (5 output(s) on this machine)
```

and it was heard. Three things are settled by those three lines:

- **the game does not hold the audio device exclusively.** This was the one verdict that ended
  the voice lane, and it is lifted: `waveOutOpen` was accepted from inside the running game;
- **two native classes pass the script blob validation.** The boot risk of adding
  `AiNpc.AiNpcAudio` beside `AiNpc.AiNpcCli` did not fire;
- **a generated sound plays.** Not a declared one -- the tone is synthesised in the DLL, so it
  has no manifest entry and no asset in the zip, which is exactly the shape a text-to-speech
  lane produces.

### The route not taken: a file, and Audioware

**Neither is used.** No `.wav` is shipped, written or read; Audioware is not a dependency and
the word appears nowhere in the code but one comment. What follows is why that route was
rejected, kept so that nobody proposes it again -- the disk is closed on both sides, and no
reading of the code can show it.

`r6\audioware\` carries `__folder_managed_by_vortex` and its files answer **2 links** --

```
r6/audioware/CourierJobs/cj_boot.wav    2 links
```

-- so Audioware's depot is Vortex's, and its contents are hardlinks into the staging folder.
Writing a generated `.wav` there writes **through the link, into the source copy of the mod**,
silently, once per reply. The trap `CLAUDE.md` records for `r6\scripts\` is the same one.

The mod's only writable place is `r6\storages\`, precisely because Vortex does not manage it
(shipped files there answer 2 links; `anon-report.json`, written at runtime, answers 1). That
is not a depot Audioware reads.

Audioware itself is a RED4ext plugin that plays custom audio declared **at load**, in a YAML
manifest, addressed by `CName`, with a dedicated `PlayOverThePhone` entry point. It cannot play
a file produced at runtime: `HotReload()` is `private` to `module Audioware` and documented as
doing nothing in a release build. So both halves of the file route are closed, and what is left
is a buffer -- which now has a measurement behind it rather than a plan.

### What it costs, and what it is not

Playing outside the game's audio engine means no ducking against game audio, no game volume
slider, playback that continues while the game is paused, and the system default output rather
than the game's. Those are consequences of the route, not defects to fix here.

**Measured 2026-08-31: the beep is heard over game audio, with no difficulty.** So the missing
ducking is not a practical problem at this level, which was the one cost of the route with a
chance of deciding anything. It says nothing about a full spoken line over combat.

**Choosing the output belongs in the CET window** (noted 2026-08-31, not built). The test
machine has five outputs and `WAVE_MAPPER` follows the Windows default, so a player wearing a
headset the system does not call default hears nothing while every check passes. `Audio::Outputs()`
already lists them; what is missing is a device parameter on `Play` and a setting to hold the
choice. It is a setting, not a workaround: on a machine like that one, "which output does the
voice use" is a real question with no right default. Audioware
remains the answer **if** mixing turns out to matter for a shipped beep, and only for sounds
that can be declared at load.

**And a beep is not a voice.** What is proven is that arbitrary samples held in memory reach
the speakers from inside the running game. What is not: the latency of a real synthesis chunk,
several chunks played back to back without a gap, and whether any of it sounds like a person.

### The seam in script

redscript has no function values, so a callback is an object with one virtual method:

```
public abstract class AiNpcSpeaker extends IScriptable {
    public func Speak(text: String) -> Void {}
}
```

The renderer holds a speaker **or none**, and none means silent while everything else works.
That is what makes the audio lane optional by construction rather than by a setting somebody
can get wrong.

---

## 5. Step order, with kill criteria

**Step 0 — the channel.** No pixels, no sound, no call: the field on the message, its JSON
round trip, the channel on the generation, the two pure predicates, the call marker. Wholly
offline. It comes first because it is the only part of this design that cannot be retrofitted
once voice lines exist in players' journals. Stated in full in `docs/PLAN_HOLO_CHANNEL.md` § 7.

> **Kill:** the phone's behaviour changes at all on a thread with no voice line in it. Then the
> default is not where it should be — stop.

**Step 1 — the beep. DONE, measured in game on 2026-08-31.** Not through Audioware: a tone
generated in `ai_npc.dll` and played from memory through `waveOut`, triggered by *Test speaker*
in the CET window's Setup tab. The kill criterion — the game holding the audio device — did not
fire. § 4 holds the log and what it settles.

> **What it does not say:** a beep is not a voice. Synthesis latency, chunks played back to
> back, and whether it sounds like a person are all still unmeasured. Never report step 1 as
> "the voice lane works".

**Step 2 — the call, with no holo. BUILT 2026-08-31, offline-green, never launched.**
`AiNpcCallState.reds` (the transitions, pure), `AiNpcCallSystem.reds` (the machine and its
timers), `tests\AiNpcTestCallState.reds`, and a *Call* tab in the CET window. The entry point is
that tab and not a button on the phone, which is what keeps every phone file out of this step.

**`Connected` opens nothing.** The first attempt had it open the phone's chat, which is what an
earlier draft of this plan asked for -- and in game on 2026-08-31 it did exactly that: answering
a call put an SMS thread on screen. Correct against the sentence, wrong against the mod: a call
is spoken, and the written thread is the one place its content may not appear. The plan was
written before the holo was understood to be a second channel and this line was not amended with
the rest.

So the crossing is deliberately missing here, and its absence is the honest state: the session a
call opens belongs to the holo, the holo has no surface until step 4, and the channel that keeps
a spoken line out of the written thread is step 0. Both come first.

> What this step does prove, without a pixel: the transition table, the timers, and that a
> refused or missed call reaches no ending that could open anything. The endings stay on screen
> -- `missed -- judy` -- until the next call clears them, lazily, because a timer-driven expiry
> does not survive a save.
>
> **Not verified in the shape above.** What was launched opened a chat; what is built now does
> not. That needs its own launch.

**Step 3 — the resolver. MEASURED 2026-08-31, and the answer is split.**

A vanilla holocall **starts and shows without authoring a scene**: `questTriggerCallRequest`
queued on `PhoneSystem` folds the phone away, brings up the call UI and, on `callMode = Video`,
opens the real holo window. The contact is addressed by its journal id -- `judy` is the game's
own, callable, with `PhoneAvatars.Avatar_Judy`. See `AiNpcCallVanilla.reds`.

**The frame comes up empty, and `holocallInitializerPath` is not the answer.** Dumped on this
save: of 176 journal contacts, `Character.<id>` exists for five, and all five -- Songbird
included, who has holocalls in Phantom Liberty -- carry a NULL initializer. `Character.judy`
does not exist at all: a journal contact id is not a character record id.

So nothing in the character table puts an actor in the frame. In vanilla the quest's **scene**
does it, and a call placed from script opens the window with nobody projected into it. Filling
it is therefore its own piece of work -- spawning or puppeting an entity into the holo's render
texture -- and it is the one part of this POC that a request cannot buy.

**Step 3 (original wording) — the resolver.** Measure whether a vanilla call can be started and shown without a
scene. Two outcomes, both fine: graft into the game's tree (as the phone does) or build our own
(as AGENT LINK does). **Write one resolver either way.** The architecture does not depend on
which answer comes back — that is the point, and it is why steps 1 and 2 come first.

**Step 4 — the holo renderer, the widgets, the input.**

**Step 5 — the speaker, wired into `AppendMessage`.**

---

## 6. What the linter must forbid

Four rules, in the shape of the existing ones — searching the concatenation of all sources, and
failing loudly when they find nothing to check.

1. **`AiNpcSpeaker` is named only in its own file and in the holo renderer.** The rule that
   keeps sound out of the session registry.
2. **No renderer or builder reaches the call system.** No `GetAiNpcCallSystem()` outside
   `AiNpcCallSystem.reds`, the hooks and the door.
3. **`AiNpcCallState.reds` is pure**: no `Get*System()`, no `*.Get()`. Same check as the session
   already carries, same reason — the tests run before any system exists.
4. **The game's call tree has exactly one owner**: extend the file list of the existing
   "foreign widget trees" rule (N+3) to name the holo resolver.

Two more come with the channel, stated in `docs/PLAN_HOLO_CHANNEL.md` § 6: a channel is decided
only by a renderer declaring its own and by a generation capturing one, and nothing outside the
session filters by channel.

---

## 7. Acceptance

Offline, and these must be green before anything is handed over: `compile-check.ps1` (with your
own `-WorkDir`), `lint.ps1` including the six new rules, `AiNpcTestCallState`, and the channel
assertions of step 0 in `AiNpcTestSession`, `AiNpcTestJournal` and `AiNpcTestHistory`.

In game, one launch, by the user:

- calling a contact shows a call widget;
- refusing or letting it ring out opens no conversation and leaves no trace in the journal;
- picking up shows the character and a field that takes a line;
- a reply is painted on the holo and **not** on the phone;
- reopening the thread afterwards shows the call as a line without its content, and the
  character remembers what was said on it;
- a beep is heard when the reply lands (measured, including over game audio);
- hanging up gives the screen back, and the phone still works afterwards.

The last one is the real check. The failure this design is built to avoid is a third surface
that quietly breaks the first two.

---

## 8. What must not be touched

The phone files, the terminal files, `AiNpcChatRegistry.reds`, `AiNpcConversationStore.reds`
and the action lane. If a step needs one of them, the seam is wrong: stop and say so rather
than widening the plan.

`AiNpcChatSession.reds` left this list with the channel, and so did the two send sites: what
step 0 touches, why it is additive, and what it removes rather than adds, is
`docs/PLAN_HOLO_CHANNEL.md` § 9. Nothing else moves without the same treatment — a written
amendment, not a step that quietly widens.

## 9. What must not be claimed

Until a launch has happened, nothing here works — offline checks prove that the rules hold and
that it compiles, never that a surface draws or that a speaker sounds.

And a beep is not a voice. This POC does not promise the voice lane; it only says whether the
voice lane is worth planning.

---

## 10. Retex: what Mantella's players measured

Mantella has run the voice lane for three years on another game. Its Nexus comment thread —
2216 comments, read on 2026-08-29 — is the only large body of field data on this exact
feature. Read as evidence about *players*, not about redscript: none of it is measured here,
and none of it can decide a step above. It changes what the steps aim at.

**Latency is spent in the voice, not in the model.** The response times players quote from
their own logs are 0.8 to 5.5 s for the LLM. Every latency complaint in the thread — and it
is the most frequent complaint — names the synthesis: XTTS running locally drops the game to
20 FPS, Piper is abandoned as "too slow", one player moves synthesis to a second machine to
get under 10 s. So the voice lane's budget is an audio budget. Step 5 measures the speaker,
and the number to write down is the delay between the reply arriving and the first sound, not
the delay of the reply.

**No preferred model exists; the choice rotates with prices.** In eighteen months the thread's
recommendation moved four times — llama-3-70b, then Grok 4.1 Fast, then Gemini 3.1 Flash Lite
when xAI withdrew the cheap tier overnight, then DeepSeek v4 flash. The stable criterion is
cheap and fast, never "the best model". Orders of magnitude quoted: $10 lasts one to three
months on a cheap model and about an hour on an expensive one. The consequence for this mod is
a constraint the holo must not break: the model stays a setting, and no surface may assume a
capability of one provider.

**Stage directions get read out loud.** Bracketed and asterisked narration bleeding into speech
is the quality defect players report most. Mantella strips it in its pipeline and forbids `[`
and `{` in the prompt. Our text surfaces tolerate it because the player skims past it; a
speaker does not. Whatever cleans a reply for the ear belongs in the holo renderer, beside the
speaker, and nowhere near the session.

**Their memory threshold was sized for a context that no longer exists.** Summaries are
re-summarized past a limit chosen when contexts were 4k; it now never fires, files reach 100 KB
and come back truncated mid-word. A threshold in tokens is a dated constant. Ours will date
too.

**What the author added after three years** — v0.14: in-game actions, nearby NPCs in context,
awareness of the vanilla dialogue the player just played, conversations with up to five NPCs,
a reply when the player stays silent, summaries restricted to the moments a character was
present. That last list is not work for this POC. It is what a voice lane turns out to need
once it exists, and the silence case is the one this plan should keep in view: a call where
nobody speaks is a state, and § 2 does not have it.
