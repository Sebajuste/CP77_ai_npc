# The prompt budget, and who decides how to spend it

Written 2026-08-22, from measurements taken the same day. Nothing here is a plan for a
rewrite: it is the shape of a setting that does not exist yet, and the numbers that argue for
it.

## The problem, stated in the only units that matter

A free provider does not meter conversations, it meters tokens, and it meters them by the
day. Measured on Groq's free tier:

    Rate limit reached for model `openai/gpt-oss-120b` ... on tokens per day (TPD):
    Limit 200000, Used 197778

None of the `x-ratelimit-*` headers says so -- they describe the minute, and they were still
reporting a healthy 8000 tokens for it while the day was already spent. The cap exists only
in the body of the 429.

One turn of conversation costs **4504 prompt tokens** on the probe's contact, and **5025**
once that contact has a memory block of average size. So:

    200000 / 4504  =  about 44 messages a day, free
    200000 / 5025  =  about 39, once the character remembers anything

That is the real ceiling a player meets. Not the advertised 14400 requests -- those are
unreachable, the tokens run out first. Two conversations and the day is over.

**Optimisation cannot fix this.** Dropping the single heaviest section -- the whole world
lore, a third of the prompt -- takes 39 messages a day to 60. The same order of magnitude, for
a large amount of work and one feature deleted outright. The way out is not a smaller prompt, it is a prompt the player composes.

## What each section actually costs

Measured, not estimated. One real request reported **4504 prompt tokens for 17174
characters** -- system prompt AND transcript, because a provider bills the whole request --
so **3.81 characters per token**, applied to the sections as `AiNpcBuildSystemPrompt`
assembles them.

(An earlier draft of this table divided that same token count by the system prompt alone and
inflated every row by 10%. The transcript is not free, and neither is the memory block.)

| section | tokens | share | messages/day without it |
|---|---:|---:|---:|
| `<world_background>` world lore | 1720 | 34.2% | **60** |
| `<system>` guidelines | 1527 | 30.4% | 57 |
| `<memory>` (12 facts) | 535 | 10.7% | 44 |
| the transcript | 411 | 8.2% | -- |
| `<mechanics>` commands | 381 | 7.6% | 43 |
| `<interactions>` | 191 | 3.8% | 41 |
| `<explicitness>` | 96 | 1.9% | 40 |*
| `<language>` | 60 | 1.2% | 40 |
| `<relationship>` | 49 | 1.0% | 40 |
| `<now>` | 31 | 0.6% | 40 |
| `<character>` | 20 | 0.4% | 40 |
| `<quest>` | 5 | 0.1% | 39 |
| **total** | **5025** | | **39** |

\* The explicitness row is the tier the player picked, and the tiers are not the same size.
Level 1 (Safe for Work) is the heavy one -- it was 220 tokens on 2026-08-23, plus 37 for the
closing reminder -- because it buys the only thing that made the tier hold: measured, an
abstract ban on explicit talk was worth nothing, and enumerating the forbidden vocabulary is
what works (see `AiNpcGetConversationTypePrompt`). Levels 2 and 3 close the prompt with
nothing at all, since a model drifts towards saying less than it was allowed, never more.

These rows predate the 2026-08-27 pass, which cut `<interactions>` from 663 to 313 characters,
`<world_background>` from 6166 to 5295, and rewrote the three tiers as permissions with no
register in them -- about 1500 characters off every message, roughly 390 tokens.

**The ranking is the opposite of the intuition.** The feature anybody would think of turning
off first -- the commands -- is 7.6% of the bill, and switching it off buys four messages a
day. The two blocks nobody thinks about, the world lore and the rule block, are 65% of it
between them, and the memory nobody sees is worth more than the commands.

The lore is the strongest lever twice over: removing it also **improved** command emission in
the prompt lab (see `ai_npc_joytoys/tools/probe/prompt_lab.py`), because the instruction that
asks for an act stops competing with 6500 characters of setting.

## The design

One toggle per feature in Mod Settings. Off means the feature is **absent**, not idle.

### The rule that makes it work

**A toggle removes the prompt text AND the code that reads the answer.** Both, always, and
this is not a style preference -- the mod already states why, in `AiNpcGetWorldMechanics`:

> A contact that opts out of generic transfers gets no mechanics block unless it wrote one
> itself. [...] Announcing a command that will be refused costs ~200 tokens a message and
> lets the model promise eddies that never arrive, which reads to the player as a broken mod
> rather than as a policy.

Half a toggle is worse than no toggle. Prompt without parser: the character promises what
will never happen. Parser without prompt: dead code waiting for a tag nobody was told to
write. The pattern already exists for one case; the setting generalises it.

### The toggles

| setting | leaves the prompt | stops running | what the player loses |
|---|---|---|---|
| **World detail** | `<world_background>` | -- | characters stop knowing Night City: they apply present-day reflexes to chrome, sex work and violence, and start explaining the setting instead of living in it |
| **Memory** | `<memory>` | the compaction pass in `AiNpcMemoryService` | a character forgets anything older than the transcript window; the last N messages are all there is. Costs 106 tk at 4 facts and 535 at 12; the cap is 20, so about 550 at saturation |
| **Actions** | `<mechanics>`, the provider's action fragment | tag parsing and dispatch in `AiNpcHttpSystem.HandleMessage` | no transfers, no meetings -- conversation only |
| **Quest & ambient context** | `<quest>`, the live and pending context inside `<now>` | `AiNpcFactEvent`, `AiNpcWeather`, the quest lookup | characters no longer react to what V just did, nor to the weather |
| **V's appearance** | `<target>` | -- | characters stop describing V; it is one settings.json line (`appearance`), so this only decides whether it is sent |

Not toggleable, because the mod is not itself without them: `<system>`, `<explicitness>`,
`<language>`, `<character>`, and the transcript.

### What the recipe changed

The table above was written when the only lever was a toggle, and a toggle is coarse: it takes
a whole block or leaves it. `recipes.json` is the fine one -- it takes **parts** of a block, so
`<memory>` can keep its consolidated facts and drop the chronicle, the open loops and the
agreements, and `<character>` can keep the bio and drop the register. What it cannot take is
`<system>` or `<explicitness>`, for reasons that are not about cost.

It does not replace the toggles: a toggle also stops something RUNNING -- the compaction pass,
the fact watches -- and a recipe only decides what is written into the prompt. The measurements
above are unchanged, and none of them was retaken for the recipe.

### Self-documentation, and its one trap

Each toggle's description states its cost. That is the point of the design -- the menu
teaches the budget instead of a README nobody reads.

**Never state a cost that a measurement can contradict.** "Actions require a paid model"
would have been such a claim, and our own bench refutes it: `gpt-oss-120b`, free, emitted the
meeting command on 5 of 6 runs of the nominal turn. A description that our instruments can
falsify is worse than no description, because it is believed.

Two honest forms instead:

- a measured token cost, restated whenever it is re-measured -- "about 1700 tokens a message,
  a third of what a free day allows";
- better still, a **live** figure. `AiNpcSetupSystem.DescribeSetup` already reports the
  current configuration; it can assemble the prompt as configured, count it, and say what
  that means in messages per day for the chosen provider. Then nothing is promised: the mod
  measures itself, and the number moves when the player moves a switch.

## What is not measured yet

**How much of the loss column is real.** Every "what the player loses" cell is a prediction
from reading the code, not a measurement. `prompt_lab.py` measures exactly this shape of
question -- a variant is a list of sections -- so each toggle can be run before it ships.

## How to re-measure

**In game, without an instrument.** With Enable Logs on, every request now writes one line
naming its two halves in characters and whatever the provider said it cost -- both lanes, the
repair retry included. The 3.81 above is that same division, done once by hand; the line now
does it on every request, for the model actually in use, so a provider whose tokeniser
disagrees says so on the first message. Two fields exist for reasons this document already
learned the hard way: `finish` (a truncated reply reads as a disobedient
one) and `usage=absent` (a provider that reports nothing measured nothing -- it is not a free
request). See `AiNpcRequestLog.reds`.

The instruments below still answer what the log cannot: what a section would cost if it were
removed, which needs a prompt that was never sent.

The instruments live in `ai_npc_joytoys/tools/`:

- `rdv-probe.py` rebuilds the prompt by reading these `.reds` at run time, so it always
  measures the current text. `--send --runs N --model --key-env --url` points it at any
  OpenAI-compatible provider and counts commands.
- `probe/prompt_lab.py --split` writes each section to `prompt/parts/`, and runs variants
  described in `prompt/variants.json`.
- `probe/bench.py` scores four scripted turns against the parser's own semantics.

And in this repository, for the one section the probes cannot see:

- `ai_npc_lab/journal/journal.py memory <branch>` renders every contact's memory block as the prompt
  builder would and reports its size, so the heaviest volatile section can be measured
  without launching the game. `ai_npc_lab/journal/journal.py list` ranks the branches; `show <pointer>`
  prints the conversations, longest first when you sort them.

Two things they taught, both of which cost a wrong conclusion first: **three runs per cell is
below the noise floor** -- the same configuration scored 1/3 and then 3/3 -- and
**`finish_reason` has to be read**, because the command is the last thing in a reply and a
truncated answer looks exactly like a disobedient one.
