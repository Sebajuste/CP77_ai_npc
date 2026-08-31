# Brief: how vanilla draws a holocall, and what of it we can have

A work order for one agent, working alone. Everything it needs is here; it has none of the
conversation this came from.

The goal is stated once and does not move: **a vanilla-looking holocall, carrying a conversation
this mod generates.** Not a character standing in the world, not a portrait on a phone — the
holo window with somebody in it.

---

## Where the investigation starts, and what is already established

Measured in game on 2026-08-31, in one launch, and it is why this brief exists:

- `questTriggerCallRequest` queued on `PhoneSystem` **opens the real holo window**, with
  `callMode = Video`, addressed by journal contact id (`judy`). No scene needed for the chrome.
- **The frame stays empty.** Every reachable entry point was tried on the live
  `HudPhoneAvatarController` — found by walking the phone HUD tree, on the widget `rightColumn`,
  after 219 widgets, consistently:
  `StartHolocall(TweakDBID, String)`, `StartAudiocall(...)`,
  `RefreshView(id, name, EHudAvatarMode.Holocall)`, and `HolocallStartEvent` queued on the
  player. None draws a character.
- The controller holds `m_HolocallRenderTexture`, `m_HolocallHolder`, `SetHolder(inkWidgetRef)`
  and show/hide animations. **It positions and animates a frame; it does not produce the image.**
- Script has **no** render-to-texture: the only such API in the bundle belongs to the Portal
  device (`entRenderToTextureCameraComponent`, `entVirtualCameraComponent`, `stream_view_ui`).
- Script has **no** way to play a scene: `SceneSystem` exists and `GetScriptInterface()`
  resolves, but `PlayScene` / `RequestScene` / `StartScene` do not, and `scnSceneResource` and
  `scnStartSceneEvent` are not scripted types at all.
- `GetQuestsSystem().SetFact(CName, Int32)` **does** resolve. Advancing a quest phase is
  therefore possible and is a dead end for us: it plays authored story content, damages the
  playthrough, and only exists for calls the game already wrote.

**One earlier conclusion is weak and must be redone.** `holocallInitializerPath` on Character
records was reported NULL — but that was sampled on `Character.<journal contact id>`, and only
5 of 176 such records exist. The real character records use other ids. **Re-test properly before
believing it.**

---

## Get a decompiler first

Everything above is the shape of the surface, never its behaviour, because nothing on the
machine can read vanilla script bodies. `scc.exe` compiles only.

**`redscript-cli` (jac3km4/redscript, GitHub releases) decompiles `r6/cache/final.redscripts`
into readable source.** Get it, dump the vanilla scripts, and read. This turns the whole brief
from guesswork into reading, and it is reusable for every future question about vanilla
behaviour — so it is worth the download even if this investigation fails.

Then read, in this order:

1. `HudPhoneAvatarController` — what `StartHolocall` actually does, and what it expects to have
   been set up before it is called;
2. **who calls it in vanilla.** That caller is the mechanism. If it is scripted, it is
   imitable; if the setup happens before any script runs, it is not;
3. whatever sets `m_HolocallRenderTexture` / `m_HolocallHolder`.

---

## The four questions, in order, each able to end the brief

### 1. How does vanilla do it?

Answer it with the decompiled source and with data, not inference. Name the mechanism: what
puts a rendered character into that frame, and what has to exist before it can.

Also re-test `holocallInitializerPath` **properly**: find real `Character` records (CET's TweakDB
editor can search; the record ids are not the journal contact ids) and report whether *any*
record sets it, and to what.

> **Report even if the answer is "a scene node with no scripted equivalent".** That is the
> result, and steps 2 and 3 then have nothing to work with — go straight to 4.

### 2. Can we reuse it?

Given the mechanism, can a mod invoke it for a call it placed itself? The test is a holo frame
with any character visible in it, however wrong the character is. Getting the *wrong* face to
appear is a pass; an empty frame is a fail.

### 3. Can we customise it?

If something can be made to appear, can it be pointed at an arbitrary contact — including one
this mod invented, which has no quest, no scene and no authored asset?

> **Kill:** if the visual can only ever be a character the game already ships a holocall for,
> say so. It would mean the tier works for ten vanilla contacts and for nobody else, and that
> changes what the mod can promise.

### 4. Can we fake it convincingly?

This is the branch that most likely carries the answer, and it is not a consolation prize: what
the player must get is *a holocall that reads as one*, not the engine's exact path to it.

Things known to be within reach, cheapest first:

- **Our own widget in the frame.** The mod already parents widgets into the phone HUD tree —
  `AiNpcHoloInput.reds` puts a text field there and its resolver is the pattern to copy. A large
  portrait, tinted and animated, sits in the empty frame for the price of one widget.
- **The game's own holo animations.** The controller names them:
  `avatarHolocallShowingAnimation`, `avatarHolocallHidingAnimation`,
  `avatarHoloCallLoopAnimation`. If they can be played on our widget, the motion is the game's
  own and the result stops looking like an overlay.
- **The avatar art already exists**, per contact, as a TweakDBID: the journal dump gave
  `PhoneAvatars.Avatar_Judy`, `Avatar_Panam`, `Avatar_River` and so on for every callable
  contact. That is the image, already shipped, already correct.
- A looping video per character (`inkVideo`) is the expensive end. Note it, do not build it.

Judge the result the only way it can be judged: **screenshot it and let the user look.** "It
draws" is not the bar; "it reads as a holocall" is.

---

## Constraints, not negotiable

Read `../CLAUDE.md` (the `CP77_mods` one) first. What bites here:

- **Never deploy.** Build with `tools/package.ps1`; the user installs through Vortex and
  launches. Never write into `D:\Jeux\Cyberpunk 2077\`.
- **One resolver per foreign widget tree, all-or-nothing.** Rule 2 of
  `docs/VIEW_ARCHITECTURE.md`, enforced by `tools/lint.ps1`. Every traversal of the phone's tree
  lives in exactly one function that returns a validated bundle or nothing. Adding a file to
  that rule's owner list is a decision to argue for, not a formality.
- **Hooks report, they never decide** — also enforced by the linter.
- **`tools/compile-check.ps1` needs your own `-WorkDir`**: the default is shared and collides
  with the other agents working in this repository.
- **Never kill a process by image name**; track the PID you started.
- Several agents write in this worktree. **Never `git add -A`** — stage explicit paths, and
  check `git status` before committing. Files that are not yours will appear mid-session.

## What must not be claimed

That the frame is filled, before a screenshot the user has seen. Every measurement above was
made in one launch and written down; keep that discipline — record what you tried and what the
game answered, in `docs/PLAN_HOLO_LANE.md`, including the attempts that produced nothing. Two
sessions have now spent time re-deriving that an empty frame is empty.
