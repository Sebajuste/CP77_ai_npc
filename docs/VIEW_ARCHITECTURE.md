# The chat surfaces: rules in force

ai_npc draws a conversation on two surfaces — the in-game phone and a Night City terminal —
and they share one session. This document states the rules that shape the code today,
the lint checks that keep them, and the one thing that must not be claimed. It is not a plan:
everything below is implemented.

---

## Rule 1 — the model publishes, the view paints, and a view exists only while its widgets do

A chat view registers when its widget tree is built and unregisters when it is torn down.

- `ToggleIsGenerating` publishes to registered views. It never calls into a painter itself and
  never asks whether a chat is open.
- **"Is there a view?" replaces "is this widget alive?"** — one question, asked once at
  registration, instead of N questions asked at use time.
- No view registered means no painting, and the reply falls through to the SMS notification.
  That is the default path, not a lucky one.

The registry is an **ordered list**, iterated most-recently-registered first: the first view
that answers `true` takes the reply, and none answering falls through to the notification.
Two views can be alive at once (a terminal and the phone), which is why one slot was not
enough.

## Rule 2 — one resolver per foreign tree, all-or-nothing

Inside `@wrapMethod(PhoneDialerLogicController)` the widgets belong to the game, are genuinely
transient, and are not ours to hold. So:

> every traversal of a foreign widget tree lives in exactly one function, which returns a
> fully validated bundle of what the mod needs, or nothing.

The magic indices, the `GetWidget(n)` chains, the `parentWidget` walk and the
`FindWidgetWithName` chains live inside that one function and are validated together. A caller
gets "not found" and returns. Interleaving a traversal with decisions makes every step a place
to dereference null.

This applies to **any** tree the mod did not build, including another mod's:
`AiNpcPhoneInput.reds` is the resolver for Codeware's `HubTextInput` internals, and a miss
there costs a yellow caret, never the chat.

## Rule 3 — one session, two renderers, two inputs

The surface is not the right thing to abstract. Behaviour that was written twice — splitting a
reply too long for one bubble, filling the conversation from the store, "is this reply
addressed to me?", the resting/typing/generating states, and send (read the field, push,
clear, echo) — lives **once**, in the session. What stays per surface is drawing and input.

## Rule 3b — the session is handed its data; it never fetches it

The policies are **pure functions over plain data**: a message array, a contact id, two flags.
A thin adapter does the fetching, holds no decision, and is not tested.

This is not style. The test suite runs from `AiNpcStorageService`'s attach, at game start,
**before any `ScriptableSystem` exists** — so a policy that calls `AiNpcConversationStore.Get()`
or `GetAiNpcHttpSystem()` inside itself is untestable by construction, and the whole
testability argument for rule 3 evaporates. `tests\AiNpcTestSession.reds` holds `AiNpcMockRenderer`, a
double that records what it was told and can **refuse**, because a double that always accepts
would never exercise the notification fall-through.

Enforced by lint: no `Get*System()` and no `*.Get()` in `AiNpcChatSession.reds`.

## Rule 3c — a conversation opens and closes through one door

A session's shown contact **is** the conversation, so `Show` and `Close` are the two moments a
thread starts and ends. Everything that has to happen at those moments happens in
`AiNpcChatDoor.reds`: the write to the session, `AiNpcPublishConversationOpened` /
`Closed` for listeners, and `AiNpcMemoryService.NotifyConversationOpened`. No surface calls a
session's `Show` or `Close` itself.

Stated as the phone's job, it was wrong for the other surface and silently so. The
announcement lived in `AiNpcSystem.ShowModChat` — the phone's door — so AGENT LINK opened
conversations no listener saw, and never reached the memory service, whose idle compaction has
exactly one trigger point: a terminal-only player never compacted. Switching contact inside the
phone was silent for the same reason, because `SwitchChatTo` repaints rather than reopens.

The door sits **above** the session and not inside it, because of rule 3b: the extension
registry and the memory service are both systems, and the session may not reach one. The only
part that is pure — "does showing this contact open a conversation?" — is
`AiNpcConversationOpening`, and that is the part the tests own.

Enforced by lint, in two halves: session `Show`/`Close` only in the door and the tests, and the
three events only in the door. Two rules because the half that actually drifted was the
announcement, not the `Show`.

## Rule 4 — a builder builds one thing and returns its anchors

A builder file takes the parent it draws into and returns **only the handles the rest of the
code needs later**. Everything else is local and dies with the call. The renderer keeps the
`wref`s and no state at all; the builders keep nothing.

## Rule 5 — geometry is per surface, identity is shared

One module holds what makes the mod recognisable — colour roles, font family, font styles,
letter case, opacity constants. Two modules hold what makes each surface *fit* — lengths,
margins, anchors, font sizes. **A length never crosses between them.** A single shared style
file was rejected for that reason: the two surfaces share no coordinate space, so every number
would exist twice inside it.

---

## What must not be claimed

The chat-widget bug reported against mods of this kind — a scanner or HUD element surviving on
screen — was diagnosed here from another mod's source as a missing restore, not reproduced.
The code is in the shape where that class of defect cannot happen, **but no session has ever
reproduced the bug, so nothing here may be advertised as fixing it.**

## What offline verification cannot reach

No runtime assertion can touch a widget. `lint.ps1` and `compile-check.ps1` prove that the
rules hold and that it compiles — never that a surface still draws. Any change to either
surface therefore needs its own build and its own launch; the walk is in `docs/ARCHITECTURE.md`
§ 9, "What only a launch can prove".
