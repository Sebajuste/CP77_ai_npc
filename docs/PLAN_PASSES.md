# Plan: passes — one slot, one recipe, per kind of work

A **pass** is one request the mod makes about a conversation. Today it makes four, each written
by hand: the reply, the memory compaction, the bracket repair, the connection test. A fifth —
an action selector reading the prose that was just written — is measured and cannot be
configured, because neither the model it needs nor the prompt it needs has a name.

This plan gives both a name. It supersedes nothing: `docs/PLAN_MODEL_SLOTS.md` stays the
rationale for the slot format, and its steps appear here as phase A so that one ordered
sequence exists from today to a working fifth pass.

**Nothing here changes a prompt, adds a request, or alters what an unconfigured install sends.**

---

## Where this stands — 2026-08-31

**Phases A, B and C are written and green offline: `tools\lint.ps1`, both compile shapes, and
`tools\prompt` (the corpus matches the sources, and the captured prompt still rebuilds byte for
byte). Nothing has been launched.** The redscript assertions in `tests\` — the slot resolution,
the aliases, the overlay, the pass table, the two message blocks and the D4 exemption — run at
startup and have not run.

Two things this plan asked for did NOT ship, and neither is a detail:

- **A6, the memory cap, is still not measured.** The presets ship two output ceilings —
  4096 on the reply, 500 on the repair (`docs/PLAN_PRESETS.md` §1b) — and the compaction
  inherits the first. Neither is the measured compaction number, the `1200` in
  `PLAN_MODEL_SLOTS.md` is still a placeholder, and the bench stays owed. What makes an
  inherited ceiling acceptable in the meantime is that a truncated compaction is now **refused
  rather than stored**: the failure is "no compaction this time", not a memory quietly missing
  its last section.
- **Nothing is measured at all**, which is §7: every pass ships on the dialogue slot and on its
  own builder, so what goes out is the request that went out before.

Two rules were sharpened while writing it, and both are in the code:

- **the more specific wins: named slot, dialogue slot, then the legacy settings.** A2 below
  says the opposite, and the presets are what turned it over (`docs/PLAN_PRESETS.md`, §5): a
  preset writes `slots.dialogue.model`, and an `openRouterModel` left in the file from before
  would have shadowed it — the preset would have appeared to do nothing. A file with no `slots`
  block still behaves exactly as it did.
- **`model` is held out of the overlay** and resolved once, because a CLI lane runs a process in
  another model namespace: `deepseek/...` must never reach `claude`.

---

## 1. The end state

```json
{
  "openRouterApiKey": "sk-or-v1-...",

  "slots": {
    "dialogue": { "model": "deepseek/deepseek-v4-flash" },
    "memory":   { "timeoutSeconds": 60 },
    "mechanic": { "model": "deepseek/deepseek-v4-flash",
                  "max_tokens": 40, "reasoning_effort": "low" }
  },

  "passes": {
    "speaking": { "slot": "dialogue", "recipe": "conversation" },
    "thinking": { "slot": "memory",   "recipe": "memory" },
    "repair":   { "slot": "mechanic", "recipe": "repair" },
    "test":     { "slot": "dialogue" }
  }
}
```

Three tables, and each answers one question:

| Table | Question | File |
|---|---|---|
| `slots` | which model, with what request parameters | `settings.json` |
| `recipes` | what the two messages contain | `recipes.json` |
| `passes` | which slot and which recipe, per kind of work | `settings.json` |

`slots` and `recipes` are named separately and bound by `passes` because they do not vary
together: `repair` and a selector both want the cheap mechanical model and cannot want the same
prompt. A `recipe` key inside a slot would force a second cheap slot differing only by its
prompt.

**A pass is keyed by its lane.** `speaking`, `thinking`, `repair` and `test` are declared in
`AiNpcRequestLog.reds` and already written to disk by `AiNpcUsageLedger`. Nothing is invented,
nothing is renamed, and the two vocabularies `PLAN_MODEL_SLOTS.md` leaves open become one.

**Every key is optional, and the block above is not the default.** The default is the block
being absent: every pass on the `dialogue` slot, every pass on the `active` recipe, every
message built by the lane that sends it. That is today's behaviour exactly, and it is what
phases A to C ship.

---

## 2. What a recipe reaches, and what it does not

A request is **two messages**, always. `AiNpcLlmChatBody` builds that shape for every backend
and nothing else is ever sent. The mod's own words for the two halves are already in the code,
in the lanes that write them by hand: **`instruction`** (`AiNpcMemoryInstruction`, and the
`instruction` local in the connection test) and **`ask`** (`AiNpcRepairAsk`, and the `ask`
local beside it). `user` stays on the wire, because `"role": "user"` is what an
OpenAI-compatible API requires; it is not what the block is called.

Today a recipe reaches **one message of one lane**. `GetRecipe()` is read at exactly one site,
`AiNpcPromptSections.reds`, inside the conversation's own system prompt. Measured offline with
`tools\prompt` (fixture `judy-after-the-win`, ai_npc 0.9.5, corpus `2a453a925fbd`): **12 727
characters of instruction, 280 of ask**, and the eleven blocks a recipe governs — `system`,
`explicitness`, `character`, `target`, `relationship`, `world`, `commands`, `memory`, `intent`,
`quest`, `now` — are all in the first of the two.

The other three lanes build both halves with no recipe anywhere near them:

| Pass | instruction | ask |
|---|---|---|
| speaking | `AiNpcBuildSystemPrompt` — the eleven blocks | `AiNpcBuildTranscript`, or `AiNpcBuildUnpromptedTranscript` when the character writes first |
| thinking | `AiNpcMemoryInstruction(folding)` | `AiNpcMemoryRequestBody` |
| repair | `AiNpcActionVocabularyFor(contactId)` | `AiNpcRepairAsk(tag)` |
| test | a literal | a literal |

So the eleven blocks are not a vocabulary the other three passes can use: bound to `thinking`,
a recipe saying `character: ["bio"]` would render nothing, in silence — the one outcome the
parser exists to prevent. **A recipe describes the conversation prompt. A pass names the
builders.** That is the whole of the correction this plan makes to itself.

What a recipe gains is the ability to *say which pass it is for*, so that a recipe bound to the
wrong one is refused when the files are read rather than discovered as a prompt nobody
recognises. Two blocks carry it, `instruction` and `ask`, each holding a source — and the
sources are named after the lanes that already build them.

### What the measured selector needs

`ai_npc_lab/docs/SELECTEUR_ACTION.md`, 2026-08-30 — 56 calls, $0.0140, one selector
(`deepseek/deepseek-v4-flash`). A probe, not a campaign; its own *ce qui n'est pas mesuré*
section is half of what it says. Three facts bear on this plan:

- its instruction carries **no world, no character sheet, no explicitness tier, no form
  rubrics** — the commands table, the thread, the prose;
- its ask is **the thread plus that prose** — the transcript with one message appended and the
  handover removed;
- **97 % of its output is reasoning it never reads** — 13 useful tokens against a median of 644
  on a rendezvous. The untried levers are `reasoning_effort`, a short `max_tokens`, and a
  non-reasoning model: all three are request parameters, which is phase A.

The first of those refutes a rule the schema states today. `AiNpcRecipeSchema()` marks `system`
and `explicitness` **required**, and the selector's instruction carries neither. Both reasons
were right while every recipe described a character speaking; neither survives a pass that
reads prose already written. See decision D4.

---

## 3. Decisions

Settled here so that no step has to re-open one.

**D1 — two message blocks, `instruction` and `ask`**, each sourced the way `target` is. They
declare which builder renders each half. The sources are the lanes': `conversation`, `memory`,
`commands` and `test` for the instruction, `conversation`, `memory`, `repair` and `test` for
the ask. The other eleven blocks are the instruction's own, and only when its source is
`conversation`.

`conversation` is one source and not two, although the speaking lane has two askmakers:
`AiNpcBuildTranscript` and `AiNpcBuildUnpromptedTranscript` are chosen by `SpeaksFirst()` at
the moment of sending, and a file that could name one of them would be a file that switches
off the character writing first. The branch stays inside the source.

**D2 — a recipe silent on a source keeps the lane's own builder.** `AiNpcRecipeSourceOf`
already returns `""` when a recipe says nothing, and `AiNpcRecipe.reds` already states what
that means: "a renderer decides what an empty answer means, because only it knows its own
default". So `AiNpcRecipeFull()` leaves both sources empty — where `target` has one default for
everybody, a message has one per pass — and the four existing passes need no recipe at all to
keep working.

**D3 — one schema table, and the containment is stated rather than encoded.** `instruction`
and `ask` sit in the same table as the eleven; the table's order stays the order of the
conversation instruction, which is what `AiNpcBuildSystemPromptWith` walks. A second table
would mean a second parser loop, a second unknown-key report and a second lint rule, for two
entries.

**D4 — required means required of a recipe that has not said otherwise. DECIDED.**

`system` and `explicitness` stay required, and the exemption is stated by the recipe itself:
**a recipe whose `instruction` source is declared and is not `conversation` may drop them**,
because they do not exist in the message it describes. A recipe that declares nothing is a
conversation recipe until it says otherwise — which is what keeps the shipped default, and
every file a player has already written, exactly as protected as it is today.

The refusal stays where every other refusal is, in the parser, at the cost the earlier draft of
this plan already named: `instruction` is resolved before the schema loop rather than during
it.

The rejected alternative was to key the exemption on the *ask* source, or to move the check to
binding time. The first inverts the default — `AiNpcRecipeFull()` names no source, so every
recipe would read as "not speaking" and the two blocks would become droppable for exactly the
file everybody edits. The second moves one refusal out of the parser and into a second place
that reports, for no gain: a recipe that never says what it is for is a conversation recipe,
and the parser can read that.

**D5 — `passes` is keyed by the lane name**, and both `slot` and `recipe` are optional. A pass
name this version does not implement is **reported as a warning and ignored**: `actions` is the
next thing to be built, so a table naming it is a table written ahead of the code on purpose,
and the line saying so is worth more than the silence.

**D6 — `active` stays the fallback** for a pass that names no recipe. That is what keeps every
existing `recipes.json` working with no `passes` block, and it costs nothing for the three
lanes that build both halves themselves: a conversation recipe bound to `thinking` names no
source, and D2 makes silence mean the lane's own builder.

**D7 — a source names the pass it belongs to, and a mismatch is refused.** A recipe that
declares `ask: {"source": "memory"}` and is bound to `speaking` is reported when the two files
are read, and the pass falls back to its own builder. The list of sources a pass renders lives
in one place, `AiNpcPass.reds`; the schema's per-block list is derived from it, which is also
what fixes the parser reading every source against `AiNpcTargetSources()`.

**D8 — a new pass owns its own record and its own watchdog**, in its own `ScriptableSystem`,
the way `AiNpcMemoryService` does. `AiNpcHttpSystem` holds one `m_record`; repair survives that
only because it is strictly sequential. A pass that runs after delivery frees the player to
send a new message, and that message would overwrite the record the pass is still waiting on,
charging its tokens to the wrong lane. The header of `AiNpcLlm.reds` already states the rule:
each lane keeps its own in-flight state and callbacks.

**D9 — a recipe describes a request, never a response.** What to do with the answer is code
beside the pass, the way `AiNpcMemoryService` reads a section format. **A pass is a slot and a
recipe for the request, plus a reader for the answer.**

---

## 4. The steps

Four phases, in this order because the pass table is what gives a source its meaning: a
`recipe` naming an `ask` source before anything binds recipes to passes would be a key that
applies to all four lanes at once. Each step is verifiable alone; the offline suite is
`tools\test.ps1` (lint, two compile shapes, the C++ suite, and `tools\prompt`), and the
redscript assertions in `tests\` need a launch. Stop at the first step that fails.

### Phase A — the slots

`docs/PLAN_MODEL_SLOTS.md` holds the rationale for the format. Its steps, with the three gaps
that review found closed:

**A1. The overlay, pure, with its tests.** Key-by-key resolution against `dialogue`, reserved
keys stripped, unknown slot ignored, absent key not sent, a slot that says nothing producing
today's body.
*Kill:* if any of those needs a session to assert, the seam is wrong.

**A2. `GetSlot(name)` in `AiNpcStorage.reds`**, plus the three aliases — `openRouterModel`,
`maxTokens`, `reasoningEffort` — and the rule that a present alias wins. Present means
*written in the file*: all three have a built-in default, and an alias that won by default
would make `slots.dialogue.model` unreachable.

**A3. The four call sites take a slot.** `AiNpcHttp.reds:234`, `AiNpcHttp.reds:577`,
`AiNpcMemoryService.reds:156`, `AiNpcSetup.reds:316`. Two signatures change beyond the body,
and both were missing from the slots plan:

- `AiNpcRequestRecord.Sent` calls `AiNpcLlmChatModel(provider)` itself
  (`AiNpcRequestLog.reds:76`); without the slot every log line names the dialogue model
  whatever sent the request;
- `AiNpcLlmRequestTimeout(provider)` becomes `(provider, slot)`. `timeoutSeconds` is a reserved
  key with no path out of `AiNpcLlmChatBody`, which returns a `String`, and the timeout is read
  at five sites — `AiNpcHttp.reds:342` and `:636`, `AiNpcMemoryService.reds:183`,
  `AiNpcSetup.reds:334` and `:384` — three of which do not have the slot in hand. They get it
  the same way they get everything else about the request they are waiting on: the lane holds
  it, beside the record it already holds.

*Kill:* if the request body for an unconfigured install is not byte-identical to the previous
one, stop. The CLI lanes keep their own model — a slot naming `deepseek/...` must not reach a
`claude` process — and everything else about a slot applies to them.

**A4. The request log** records the slot name and, behind Debug Mode, the merged body. A
mistyped key is not refused by the mod — it goes out and comes back a 400, and that is only
payable if the log says which slot produced it.

**A5. The usage report** needs no change: `AiNpcUsageLedger` already totals per lane, and D5
made the lane name and the pass name one word.

**A6. Measure the memory cap** with `journal.py memory` over real compactions. Until then
**no number ships**: `PLAN_MODEL_SLOTS.md` carries `1200` as a placeholder, and neither
`settings.example.json` nor the documentation may repeat it. A `max_tokens` on the memory slot
is the one setting in this plan that can corrupt a save's worth of memory, and it is the one
nobody has measured.

### Phase B — the pass table

**B1. The book kept.** `AiNpcConfig.LoadRecipes` keeps only `AiNpcRecipeBookActive(book)` and
discards the rest of the file. Keep the book, add `GetRecipeNamed(name)`. A `recipes.json` on
disk replaces the template's book whole, so a `passes` entry naming a recipe that only the
shipped template declares is a name that points at nothing — and is reported as one.

**B2. `passes`**, per D5, D6 and D7, with a named refusal when `slot` or `recipe` points at
nothing — the `active` refusal already has the wording. Both keys cross files: a slot into
`slots`, a recipe into `recipes.json`.
*Kill:* with no `passes` block, every request identical to phase A's.

**B3. `settings.example.json`** gains a commented `slots` and `passes` block, and `docs/`
states the reserved keys, the alias rule and the D6 fallback.

### Phase C — the recipe says which pass it is for

**C1. `instruction` and `ask` in the schema**, with their per-pass source lists and D4 applied.
Three things change together, or the file's vocabulary and the code's stop agreeing:

- `AiNpcRecipeBlockSchema` carries its own list of sources, and the parser reads that list
  rather than `AiNpcTargetSources()`;
- the shipped template names both blocks — `tools\lint.ps1` fails the moment a schema entry is
  not in the template, so this is one commit, not two;
- the `AiNpcRecipe(Required|Sourced|Whole)` regex in `tools\lint.ps1` grows the constructor
  that sets both fields at once.

*Kill:* the prompt for an unconfigured install must be byte-identical to `tools\prompt`'s
output. Not equivalent — identical.

**C2. The binding refuses a source that is not the bound pass's.** Reported when the files are
read, with the pass named and its own source quoted, and the pass keeps its builder.

**C3. The template and the docs** gain the two blocks, their sources, and the D4 rule.

### Phase D — the first new pass

**Built 2026-08-31**, ahead of the bench `docs/PLAN_ACTION_SELECTOR.md` still owes, and behind
a Mod Settings switch (Command Handling) whose default is the behaviour that predates it.
Everything the list below asked for is in, and it is left as it was written so the seams can be
checked against it:

- **a fifth pass**, `actions`, whose sources are its own — `commands` for the instruction, and
  `selector` for the ask: the thread plus the prose just written, ending on a question rather
  than on the handover;
- **a lane name**, a CLI lane code, and a branch in `AiNpcCliDeliver` (a contract with
  `ScriptApi.cpp`, changed in the same commit);
- **its own `ScriptableSystem`**, per D8;
- **a reader** for the answer, per D9 — including the defect the measurement found: 15 of 20
  tags came back as `ACTION:…` without brackets. That is absorbed by the parser, never by the
  prompt;
- **`AiNpcHasTokenBudgetLeft()`** consulted, and the pass refusable — a per-turn pass that
  cannot be refused spends the daily cap on work the player never sees.

---

## 5. What the linter must forbid

- a call to `AiNpcLlmChatBody` that does not name a slot;
- a wire parameter named in redscript outside the alias table — the overlay copies, it does not
  inspect, so `max_tokens` and `reasoning_effort` appear once each, where the two old settings
  are translated;
- the reserved-key list, or a pass's source list, written in more than one place;
- a request parameter reintroduced as a typed setting beside the slots;
- a recipe key that reaches a response rather than a request;
- `userText` as an identifier in new code.

## 6. What must not be touched

The prompts. Not one word, in any block, in any phase — including the handover string, which
`AiNpcTranscriptHandover` keeps in one place precisely so the two speaking paths cannot differ
by a byte.

## 7. What must not be claimed

**That any of this improves a reply.** Phases A–C ship with every pass on the dialogue model
and every message on its own lane's builder, which is today's request exactly. Nothing has been
measured because nothing has changed.

**That a dedicated call removes wrong commands.** It removed the 15 free ones of 18 on that
probe and left three where the character had promised money in its own prose and the selector
transcribed it. The drift is in the reply before it reaches the pass, so "the command only
fires on a match" is stronger than anything measured.

**That a cheap model is good enough for anything.** The question the whole thing is for — can a
cheap model do the isolated selection — has exactly zero measurements. The first person to
fill a slot owes a bench run.
