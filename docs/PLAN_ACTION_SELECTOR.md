# Plan: the action selector on its own call

A measurement first, and a build only if it passes. Three experiments answer whether the
selection of a command can leave the dialogue generation; nothing is written into `src\` until
they do.

Depends on `docs/PLAN_MODEL_SLOTS.md`. Without a cheap mechanical slot this is a second
full-price request on every message, which is the trade that makes it not worth doing.

## The diagnosis

A command is a bracket the character writes inside its reply, so one generation carries all of
it at once: stay in voice, in the right language, inside the explicitness tier, keep a texting
register — and, after five thousand tokens of corpus, emit `[ACTION:GIVE_EDDIES:500]` with
exact syntax.

**Small and free models do not fail at choosing the action. They fail at the composite.** The
measurement we have — free and local tiers break the commands — was taken on that composite
task, so it says nothing about the isolated selection.

The evidence pointing the same way is already ours: removing the lore **improved** command
emission in the prompt lab, "because the instruction that asks for an act stops competing with
6500 characters of setting" (`docs/PROMPT_BUDGET.md`). Less prompt, better commands.

## What it would buy, beyond making cheap models viable

- **The `<commands>` block leaves the dialogue prompt.** 381 tokens off every message, and 381
  tokens that stop competing with the instruction to act.
- **The prose improves.** The character says "je te vire de quoi tenir" instead of emitting
  syntax the renderer then has to strip.
- **A malformed bracket becomes inexpressible.** A call whose entire output is one line cannot
  fumble mid-sentence, so the repair pass loses its reason to exist — and with it, its
  occasional request.

## The design question the bench will not answer

Today the promise and the command are the same sentence, so they cannot disagree. Split in
two, they can: the character says it sends money and the selector does not execute, or
executes something else. Whatever the accuracy numbers say, **this has to be answered before
any of it is written.** The options are to accept the divergence and make it visible, or to
keep a fallback where the dialogue model may still emit a bracket that wins over the selector.

## The reduced prompt

What it carries:

```
who is talking to whom, in one line
the last four to six messages
the reply just written
the command table with its parameters
ACTION: None
```

What it does **not** carry: `<world_background>` (5295 characters), `<system_rules>`, the
explicitness tier, the full bio. None of it decides a transfer. This is where the plan diverges
from SkyrimNet, whose first selector stage re-sends `render_character_profile("full")` — their
own drill-down stage concedes the point by switching to a reduced `"action"` profile.

The reduced render is `docs/ROADMAP.md`, *Render depths for a character sheet*. Until that
exists, the experiments below can assemble the prompt by hand.

## The experiments, in order

All three run offline, on the frozen bench conversations in `ai_npc_lab`, and none of them
touches an existing prompt — they write a new one beside it.

1. **The selector alone.** Take the replies in the journal that carried a command, strip the
   bracket, and ask three cheap models to recover the action. Report the rate of correct
   recovery *and* the rate of false positives on replies that carried none.
   *Kill:* if a cheap model cannot beat the current composite emission rate, the whole idea
   dies here and the plan is closed.
2. **The prose without the block.** Does the character still say clearly what it is doing when
   it is no longer taught a syntax? Compare replies generated with and without `<commands>`.
   *Kill:* if the intent stops being legible in the prose, the selector has nothing to read.
3. **Implicit parameters.** On the transfers, compare the amount the selector reads out of the
   prose with the amount the dialogue model had written. `AiNpcTransferLedger` already clamps,
   so what is measured is how often the clamp has to save it.

## If it passes

Build order, not written until the experiments are in: the reduced render, the selector
request on the mechanic slot, the dialogue prompt losing `<commands>`, and only then the
repair pass being removed — in that order, so each step is revertible alone.

## What must not be claimed

That the repair pass is unnecessary, until step 2 has shown the prose still carries the
intent. And that free models work: what the experiments measure is one isolated task, not a
conversation.
