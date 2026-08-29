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

**No existing file may change behaviour.** A step that needs the phone, the terminal, the
session or the registry to be edited has found a wrong seam. Stop, say so, and do not paper
over it — this is the whole subject of rule 2 of `CLAUDE.md`.

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
  reach the memory service.
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

- `AiNpcHooks.reds` — only if the call needs a vanilla callback, and then it reports a fact.
- `tools\lint.ps1` — the four rules in § 6.
- `src\r6\audioware\ai_npc\` — the manifest and the `.wav`. A new kind of artefact under
  `src\`, so `tools\package.ps1` must learn to copy it, and the check afterwards is the
  **contents of the zip**, never the contents of `src\`.

`tools\package.ps1` needs nothing new unless an asset appears. If one does, extend the packager
and **check the contents of the zip, not the contents of `src\`.**

### The input field comes from the terminal, not the phone

The phone's field is Codeware's `HubTextInput`, resolved in `AiNpcPhoneInput.reds` — the mod's
last dependence on Codeware. The terminal's field is the mod's own.

The holo takes the terminal's. The POC then adds no dependency at all, and the eventual
speech-to-text lane replaces a field the mod wrote itself.

---

## 4. The audio seam

redscript has no function values, so a callback is an object with one virtual method:

```
public abstract class AiNpcSpeaker extends IScriptable {
    public func Speak(text: String) -> Void {}
}
```

The renderer holds a speaker **or none**, and none means silent while everything else works.
That is what makes the audio lane optional by construction rather than by a setting somebody
can get wrong.

### The implementation is Audioware, and no C++ is needed

Measured 2026-08-29 against the copy installed on this machine (`red4ext\plugins\audioware`,
`r6\scripts\Audioware`). Audioware is a RED4ext plugin that plays custom audio files — `.wav`,
`.ogg`, `.mp3`, `.flac` — declared in a YAML manifest and addressed by `CName`:

```
GetAudioSystemExt(game).PlayOverThePhone(n"ainpc_beep", emitterName, gender);
```

`PlayOverThePhone` is a dedicated entry point, not a repurposed one: the plugin already treats
"a voice arriving through a call" as a case worth its own routing. `Play` takes a
`scnDialogLineType` and `DefineSubtitles` registers subtitles for custom audio, so the
dialogue-line and subtitle machinery is reachable from the same place.

This removes the entire plugin half of this plan. No native to add, no `ScriptApi.cpp` change,
no DLL-and-scripts version pairing to warn about.

**Audioware is an optional dependency**, guarded like BrowserExtension:
`@if(ModuleExists("Audioware"))`. The name is compared **case-sensitively** — a mistyped guard
leaves the degraded half live and every compilation pass stays green.

### What Audioware does not do, and it is the voice lane's real question

Sounds are declared **at load**, in a manifest, and addressed by name. There is no API taking a
path, and `HotReload()` is `private` to `module Audioware` *and* documented as doing nothing in
a release build. A file produced at runtime — which is exactly what a TTS lane produces — has
no manifest entry and cannot be played through Audioware as shipped.

And **writing the file first is not a way round it**, for a reason that has nothing to do with
Audioware. Measured 2026-08-29: `r6\audioware\` carries `__folder_managed_by_vortex`, and its
files answer **2 links** —

```
r6/audioware/CourierJobs/cj_boot.wav    2 links
```

— so Audioware's depot is Vortex's, and its contents are hardlinks into the staging folder.
Writing a generated `.wav` there writes **through the link, into the source copy of the mod**,
silently, once per reply. The trap `CLAUDE.md` records for `r6\scripts\` is the same one.

The mod's only writable place is `r6\storages\`, precisely because Vortex does not manage it
(shipped files there answer 2 links, `anon-report.json`, written at runtime, answers 1). That
is not a depot Audioware reads.

So the disk is closed on both sides, and the consequence is a decision rather than a list of
options:

> **The beep is Audioware's. The voice is not, and the voice never touches disk.**

A shipped `.wav` deployed by Vortex is exactly Audioware's supported case, and step 1 stands as
written. A generated utterance belongs to `ai_npc.dll` — which already spawns processes for the
CLI lanes — held in memory and played from there, outside the game's audio engine, with
everything that costs: no mixing, no ducking, no volume setting.

If an upstream request is ever worth making, it is therefore not "reload the manifest". It is
"accept a buffer, or a path outside the mod depot".

---

## 5. Step order, with kill criteria

**Step 1 — the beep, through Audioware.** A manifest, one `.wav`, one call to
`PlayOverThePhone` from the CET console. No holo, no call, no widget, no C++.

> **Kill:** no sound at all, or a crash. Then this POC has no audio and the holo is a worse
> phone — stop and report it.
>
> **Not a kill, and not a pass either:** the beep working proves that a *declared* sound plays
> over the phone lane. It does **not** prove the voice lane, because a generated file has no
> manifest entry — see § 4. Never report step 1 as "sound works" without that sentence
> attached.

**Step 2 — the call, with no holo.** A "call" entry on the phone, the state machine, the timers.
Connected opens the *existing* chat through the door.

> Verifiable with no new pixels: the chat opens after the ring, and never opens when the call
> is refused. This is where the door discipline is proven, and it is proven before any widget
> work can obscure it.

**Step 3 — the resolver.** Measure whether a vanilla call can be started and shown without a
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

---

## 7. Acceptance

Offline, and these must be green before anything is handed over: `compile-check.ps1` (with your
own `-WorkDir`), `lint.ps1` including the four new rules, and `AiNpcTestCallState`.

In game, one launch, by the user:

- calling a contact shows a call widget;
- refusing or letting it ring out opens no conversation and leaves no trace in the journal;
- picking up shows the character and a field that takes a line;
- a reply is painted on the holo and **not** on the phone;
- a beep is heard when the reply lands;
- hanging up gives the screen back, and the phone still works afterwards.

The last one is the real check. The failure this design is built to avoid is a third surface
that quietly breaks the first two.

---

## 8. What must not be touched

The phone files, the terminal files, `AiNpcChatSession.reds`, `AiNpcChatRegistry.reds` and the
action lane. If a step needs one of them, the seam is wrong: stop and say so rather than
widening the plan.

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
