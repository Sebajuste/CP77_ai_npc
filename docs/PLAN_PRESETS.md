# Plan: three presets — light, normal, premium

`docs/PLAN_PASSES.md` gave the mod a place to say *which model does which kind of work*. It
shipped with that place empty, on the grounds that nothing had been measured. This plan fills
it, with three named starting points a player picks once.

A preset is **not** a mode the mod runs in. It is a block of JSON the mod writes into
`settings.json`, in clear, which the player then owns: the models are visible, editable, and
the mod never rewrites them behind their back. That is the whole design, and everything below
follows from it.

---

## 1. What a preset writes

```json
"modelPreset": "normal",
"slots": {
    "dialogue": { "model": "qwen/qwen3-235b-a22b-2507", "max_tokens": 4096 },
    "mechanic": { "max_tokens": 500 }
},
"passes": {
    "speaking": { "slot": "dialogue", "recipe": "default" },
    "thinking": { "slot": "dialogue", "recipe": "compaction" },
    "repair":   { "slot": "mechanic", "recipe": "repair" },
    "test":     { "slot": "dialogue", "recipe": "test" }
}
```

Three rules, and each one is a decision:

**Written out, never resolved live.** A `"preset": "normal"` key read at every request would
mean a mod update moving a player's models without telling them, and a `settings.json` that no
longer says what goes out. Written in clear, the file stays the source of truth the README
promises, and a preset is a starting point rather than a regime.

**`modelPreset` records which one produced the block**, the way `installPreset` records the
installer's answer. It is a stamp, not an instruction: editing a model below it is expected,
and nothing re-applies a preset on its own.

**A preset names a recipe per pass; it never edits one.** Recipes are the mod's, and what they
render is not a knob a preset turns. Naming them is what makes the file legible — four lines
that say which prompt each kind of work uses. The name is written **only when the loaded
`recipes.json` declares it**, checked at the moment the preset is applied, so a player with
their own recipe file never gets a binding that points at nothing.

## 1b. The output budget

Every preset ships a ceiling on what a model may write. **A ceiling is not an economy**, and the
difference is the whole of this section: a cap sized to save money cuts the last thing in a
message, and the last thing in a message is the `[ACTION:...]` command — a reply that reads
perfectly and creates no appointment, which is the worst failure this mod has. A cap sized above
everything ever measured costs nothing and bounds a model that runs away.

| slot | ceiling | against what |
|---|---:|---|
| `dialogue` | 4096 | the longest completion measured is **1976 tokens**, over 31 runs on two providers, every one finishing on `stop`. Twice that, because reasoning is billed against the same number and the heaviest model measured spends 1250 tokens of draft before the answer |
| `mechanic` | 500 | a technical call writes **one line** — the repair today, the action selector next. It is the only kind of pass whose output has a known shape, and the only one where being cut off costs nothing: a failed repair delivers the reply as it was written |

The `mechanic` slot names **no model**. It inherits the dialogue one and exists for its ceiling
alone — which is what a slot resolving key by key is for, and it keeps the rule that no model
goes anywhere a bench has not looked.

**A ceiling only became shippable because a truncation is now visible.** The wire says
`finish_reason: "length"` and nothing used to read it:

- the **compaction refuses a truncated note** rather than storing it. This is the one that
  mattered: a note cut off still *parses*, because the sections it reached are well formed and
  the ones it did not are simply absent — which reads as "this character no longer remembers
  that", forever, with nothing saying why. The previous memory stands and the next batch tries
  again, which is what every other bad answer already does;
- the **reply is delivered and named** in the log, with the slot that capped it: a turn that
  agreed to something and then does nothing now has its explanation somewhere;
- the **repair says so** and falls back to the reply as written.

Reasoning tokens are billed against the same number, so a reasoning model spends the budget
twice: 1250 tokens of draft nobody reads plus the answer. That is measured
(`z-ai/glm-5.3-flash`, `docs/MODEL_BENCH.md`) and it is why the ceiling is 4096 rather than the
2000 the replies alone would justify.

## 2. The three

One model changes between them today. That is not a simplification: it is what the measurements
support, and the passes nobody has measured stay on the dialogue slot rather than getting a
guess.

| preset | model | what is measured (`docs/MODEL_BENCH.md`) |
|---|---|---|
| **light** | `google/gemma-4-31b-it:free` | 0 mechanical defects over 34 replies, the action command 3/3 on the fixture. Never measured on the real rendezvous conversations, and NSFW never measured. **Rate-limited by the provider, not by the key**: 46 HTTP 429 out of 54 on 2026-08-28 |
| **normal** | `qwen/qwen3-235b-a22b-2507` | 18/20 on the real conversations, 0 defects over 54 replies, 2.7 s median, ~1 $/month at two hours a day (real bill, 2026-09-10) |
| **premium** | `meta-llama/llama-4-maverick` | 20/20 on the real conversations, one `<\|eot_id\|>` leak in 54, 2.0 s median, ~2.57 $/month. `deepseek/deepseek-chat-v3-0324` is the documented fallback when a provider outage makes it unavailable |

**light is what it says it is.** One model for every pass, deliberately: the ceiling on the free
tier is the provider's pool, so spreading passes over several free models multiplies the walls
rather than the throughput. It is a way to try the mod, not a way to play an evening, and the
window says so.

**premium will never gain a second slot.** Its definition is "the best, whatever it costs";
moving the compaction or the repair onto something cheaper would be an economy nobody asked for.

**normal is the only one with holes**, and they are the *models* for `thinking` and `repair`.
Both stay on the dialogue model until a bench says otherwise — the repair has a slot of its own
already, but only for its ceiling. The candidate for the mechanic slot is
`deepseek/deepseek-v4-flash`, and the reason is precise rather than hopeful: it scores 3/3 on
the single-field command and 8/20 on the six-field one, and a repair *is* the single-field task
— one broken tag in, one line out. That is a hypothesis for a bench to kill, not a
recommendation.

## 3. The explicitness tier is not a preset's business

`qwen/qwen3-235b-a22b-2507` answers 23 explicit replies out of 24 on a thread where the Normal
tier should hold. That number stays in `MODEL_BENCH.md` as a measurement and does **not** choose
a preset, because it is not first a property of the model: measured over ~970 runs, the Normal
tier as it is written blocks nothing on anybody — a rule in prose does not hold, and an
enumerated ban is what it would take. The tier is engine work, upstream of every model. A preset
that tried to compensate for it would be answering a question that was put to the player.

## 4. What the benches must return

Run elsewhere; this plan only states what fills which blank, so nothing is left to
interpretation:

| bench | returns | admission rule |
|---|---|---|
| **repair** | `n/20` exact-match on replayed broken tags, `k` invented tags | a model enters `normal`'s mechanic slot at **n ≥ 19 and k = 0**. Below that the pass stays on `dialogue`: a bad repair replaces a good reply with a worse one |
| **thinking** | unparsable compactions, facts lost, output tokens observed | enters at **zero and zero** — binary, not a score, because a corrupted memory does not come back. The third number is the `max_tokens` of a `memory` slot, and it is the placeholder `PLAN_MODEL_SLOTS.md` has been carrying |
| **light on the real** | `n/20`, defects, 429 rate for `gemma-4-31b-it:free` | conditions nothing: the preset ships either way. It conditions what the README says about it |

## 5. What changed in the engine to make this work

**The more specific slot wins.** `PLAN_MODEL_SLOTS.md` had `openRouterModel`, `maxTokens` and
`reasoningEffort` winning over the `dialogue` slot. Implementing the presets showed that rule
inside out: a preset writes `slots.dialogue.model`, and an `openRouterModel` left in the file
from before would shadow it — the preset would appear to do nothing at all. The order is now
**named slot > dialogue slot > legacy setting**, which keeps every file that has no `slots`
block behaving exactly as it did, and makes `slots` the place a model is edited.

The CET window follows: the Model box writes into `slots.dialogue.model` when a slots block
declares one, and into `openRouterModel` otherwise. What it shows is the model that would
actually be sent, never the key it happens to be stored under.

**The connection test follows the speaking pass.** It used to fall back to `dialogue`
regardless, so a player who pointed `speaking` at another slot got a green test on a model they
never use. `passes.test.slot` if written, else the speaking pass's slot, else `dialogue`.

## 6. What must not be claimed

**That a preset is measured end to end.** One model per preset is measured, on the speaking
pass, against four criteria. `thinking` and `repair` are measured on nobody, which is exactly
why neither is given a model of its own.

**That the ceilings are measured either.** 4096 and 500 are bounds picked above and below
measurements taken for something else — a reply length and a one-line answer. They are sized so
that reaching one means something has gone wrong, and reaching one is now reported. The number a
bench still owes is the compaction's, which today inherits the dialogue ceiling.

**That light is a way to play.** It is the free tier, and the free tier answered 46 requests out
of 54 with a 429 on the one evening it was measured.
