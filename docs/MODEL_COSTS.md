# What a model costs a player

`PROMPT_BUDGET.md` answers "how big is one message". This file answers the next question:
**what does that cost, on which model, for a player who actually plays.** Prices are
OpenRouter's live list, read on **2026-08-25**; they move, the method does not.

**`MODEL_BENCH.md` answers the question that comes before this one** -- which models can do
the job at all -- and it was written after the campaign this file was still planning. Where
the two disagree, the bench measured and this file predicted; the two corrections are marked
below.

Everything below the first section was re-derived on 2026-08-25 from **229 real requests**
(22-25 August) and the **7 001 NPC replies** in the journal. The earlier edition of this file
guessed the player's pace; this one measures it, and the conclusion changed. See
"What the measurement overturned".

## The three numbers everything else is derived from

| | value | where it comes from |
|---|---:|---|
| input per message | **5 453 tokens** | 224 speaking requests, median 20 112 characters at 3.81 c/tk, **plus** the memory compaction's share -- it fires once per ten messages and costs 1 774 tk |
| output per message | **44 tokens** | the 7 001 NPC replies in the journal: 167 characters on average (median 144, p90 291) |
| **messages per hour** | **38** | 15 conversation sessions, cut at gaps over 15 minutes. Median gap between two turns: **70 seconds** |

Output is under 1 % of the bill. **The cost of this mod is the cost of its prompt**, and
nothing a character says will ever change that. The only levers that matter are the size of
the prompt, and whether the provider discounts a cached prefix.

### Why the unit is an hour, and not a month

A per-month figure has to assume how much somebody plays, and that assumption did all the work
in the previous edition -- badly. **Messages per hour is measured; hours per day is the
reader's own business.** 38 msg/h is remarkably stable across sessions (24 to 63), because it
is not a property of the mod: it is how fast a person reads a reply and types an answer.

For scale, the heaviest day recorded -- 152 turns on 2026-08-24 -- is about **four hours of
conversation**, spread across a day of ordinary play. It is not a stress test.

## The table

`$/h` is one hour of conversation. `cached` is the same hour on a provider that discounts a
cached prefix: 3 675 of the 5 453 tokens are the stable head of the prompt (world lore,
guidelines, bio -- everything `AiNpcBuildSystemPrompt` puts before the clock), written once
per session and read thereafter.

| model | $/M in | $/M out | $/h | $/h cached | 2 h/day | 6 h/day |
|---|---:|---:|---:|---:|---:|---:|
| `mistralai/mistral-nemo` | 0.019 | 0.03 | 0.004 | -- | 0.25 | 0.75 |
| `openai/gpt-oss-120b` | 0.037 | 0.17 | 0.009 | -- | 0.51 | 1.54 |
| `z-ai/glm-4.7-flash` | 0.06 | 0.40 | 0.014 | **0.008** | **0.47** | **1.40** |
| `google/gemini-2.5-flash-lite` | 0.10 | 0.40 | 0.023 | **0.011** | **0.65** | **1.95** |
| `meta-llama/llama-3.3-70b-instruct` | 0.10 | 0.32 | 0.022 | -- | 1.33 | 3.99 |
| `nousresearch/hermes-4-70b` | 0.13 | 0.40 | 0.029 | -- | 1.73 | 5.18 |
| `openai/gpt-5-mini` | 0.25 | 2.00 | 0.061 | 0.032 | 1.91 | 5.74 |
| `deepseek/deepseek-v3.2` | 0.26 | 0.38 | 0.057 | 0.040 | 2.38 | 7.13 |
| `google/gemini-2.5-flash` | 0.30 | 2.50 | 0.074 | 0.039 | 2.32 | 6.97 |
| `z-ai/glm-4.7` | 0.40 | 1.75 | 0.090 | 0.046 | 2.77 | 8.31 |
| `sao10k/l3.3-euryale-70b` | 0.65 | 0.75 | 0.139 | -- | 8.36 | 25.07 |
| `moonshotai/kimi-k2.6` | 0.95 | 4.00 | 0.216 | 0.106 | 6.39 | 19.18 |
| `anthropic/claude-haiku-4.5` | 1.00 | 5.00 | 0.231 | 0.113 | 6.80 | 20.39 |
| `openai/gpt-5` | 1.25 | 10.00 | 0.293 | 0.137 | 8.20 | 24.61 |
| `anthropic/claude-sonnet-5` | 2.00 | 10.00 | 0.462 | 0.227 | 13.59 | 40.78 |
| `anthropic/claude-opus-5` | 5.00 | 25.00 | 1.154 | 0.566 | 33.98 | 101.94 |

`gpt-oss-120b`'s row includes **500 hidden reasoning tokens** per message. They are measured
(`ai_npc_joytoys/tools/probe`), they are billed, and the mod never sees them: the CLI returns
them in a field nothing reads. Any reasoning model deserves the same correction before it is
compared to a plain one.

Two more were caught by that rule on 2026-08-28, and the correction is not a detail:
`z-ai/glm-5.3-flash` spends **1 250 reasoning tokens a message** out of 1 339 of output — its
real cost is 1.19 $/month at two hours a day, not the 0.48 its posted price gives — and
`deepseek/deepseek-v4-flash` spends 180. The seven other models measured write between 30 and
126 output tokens, close enough to the 44 above that the nominal figure holds. Per-model
output is recorded in `MODEL_BENCH.md`, taken from the runs rather than assumed.

## What the measurement overturned

**"Price is not the criterion" was wrong above the mid tier.** The previous edition said the
gap between a good generalist and a niche fine-tune was "one coffee a month". At the measured
pace the table spans **a factor of 140**, and the top half of it is real money: Sonnet 5 at two
hours a day is 13.59 $/month, Opus 5 is 33.98 $. For a free mod, that is a subscription.

The claim survives, but only in the lower half: **below `gemini-2.5-flash`, cost is genuinely
anecdotal** -- under 2 $/month even at six hours a day. That is where the default belongs, and
it is a bounded region, not a shrug.

**A cached prefix is now an eligibility criterion, not a bonus.** It halves the bill, because
the prompt is built prefix-first on purpose. A model without `pricing.input_cache_read` starts
at twice the price of an equivalent one that has it. The catch is unchanged -- a cache entry
expires in minutes, so it pays for someone chatting through an evening, not for one message
every two hours -- but the measured cadence (70 seconds between turns) is exactly the shape
that keeps a cache warm.

**Most small models are out, and the free lane is narrower than it is closed.** CORRECTED
2026-08-28. This file said every free model on OpenRouter was "small, aligned, or both" and
broke the action commands. Eighteen were then measured: **sixteen do break it, two do not.**
`google/gemma-4-31b-it:free` emits the transfer command 3 times out of 3 with no mechanical
defect over 34 replies, and `minimax/minimax-m3:free` does too. The free lane is one or two
models wide and it is where the shipped default sits. **What limits it is the provider, not
the key**: re-sent on 2026-08-28, gemma answered 46 of 54 requests with HTTP 429 on an account
that is not on the free tier, and minimax-m3 lost half its run the same way. The
failure mode the original claim describes is real and is what rules out the other sixteen --
a malformed command is an event the game never gets. See `MODEL_BENCH.md`.

The cheap rows above are kept so that the next person does not re-derive their price and
re-propose them.

**The safe-for-work tier costs about 160 tokens a message**, roughly 3 %. Cheap enough that
the tier is never a budget decision.

## The CLI lanes bill more than they send

Corrected on 2026-08-25. The previous edition said "the local bridge adds about 18 000 tokens
to every call" and generalised it to the CLI path. Measured over the 169 requests of
2026-08-24, the two lanes are not comparable:

| lane | requests | billed | prompt actually sent | ratio |
|---|---:|---:|---:|---:|
| speaking, ClaudeCli | 72 | 597 846 | 378 027 | **1.58x** |
| speaking, LocalBridge | 80 | 1 970 769 | 441 451 | **4.46x** |
| thinking, ClaudeCli | 7 | 26 211 | 13 621 | 1.92x |
| thinking, LocalBridge | 8 | 156 315 | 16 421 | 9.52x |
| **all** | **169** | **2 751 731** | **849 563** | **3.24x** |

The 18 000-token figure holds for the bridge. **The plugin's ClaudeCli lane carries about
2 200 tokens of harness**, not 12 000 and not 18 000 -- the tool flags did their work. It costs
nothing on a subscription, which is the point of that lane; pointed at a metered API it would
now pay 1.6x the mod's prompt rather than five times it.

This ratio is why a day's tally is not a bill: see `TOKEN_BUDGET.md`, "The unit is the
provider's, not the mod's".

## The bench, which has since run

RUN 2026-08-27/28, results in `MODEL_BENCH.md`. What follows is the scoping as it was written
before, kept because the three questions it set are the three the bench answered, and because
the shortlist below is *not* the one that was measured -- `glm-4.7-flash` and the two Gemini
rows were never sent. What was measured instead: five mid-priced models, four uncensored
fine-tunes, eighteen free ones, and the safe-for-work tier on four of them.

Two of its predictions came out differently. **The tone tier does not transfer between
models, as expected -- but the spread is the finding:** the same shipped tier, read out of the
`.reds` at run time, gives 1 explicit reply out of 24 on `llama-4-maverick` and 23 out of 24
on `qwen3-235b`. A tier wording cannot be judged without naming the model that read it. And
**the action command turned out to be a paid-versus-free frontier**, not a size one: every
mid-priced model tested emits it, almost no free one does.

## The bench as it was scoped

Three candidates meet both hard criteria -- a price in the anecdotal band, **and** a
`pricing.input_cache_read` entry:

    z-ai/glm-4.7-flash              0.008 $/h cached
    google/gemini-2.5-flash-lite    0.011 $/h cached
    google/gemini-2.5-flash         0.039 $/h cached

`glm-4.7-flash` is roughly **5x cheaper than `gemini-2.5-flash`**. If they are equivalent on
the two things that actually decide the default, the price picks the winner on its own.

**What the bench has to answer**, and nothing else -- it is one paid campaign, so it is worth
scoping before it runs:

1. **Action commands.** Does the model emit a well-formed `[ACTION:...]` when the turn calls
   for one? This is the criterion that killed the free tier. Read `finish_reason`: a truncated
   reply looks exactly like a disobedient one.
2. **French.** The characters speak French to a French player, and the lexicon tables
   (`AiNpcWorldLoreWords`) assume the model honours the game's own terms.
3. **The tone tier.** The safe-for-work guarantee -- 0 explicit replies in 110 runs -- was
   measured on the Claude lane. It does not transfer to another model.

**Ten runs per cell, minimum.** Three is below the noise floor: the same configuration scored
1/3 and then 3/3 (`ai_npc_joytoys/tools/probe`).

**What it needs to run.** `bench.py` and `rdv-probe.py` read the bearer token from an
environment variable (`--key-env`); no key is set on this machine, and `openRouterApiKey` is
empty in `settings.json`. `bench.py` also defaults to `--provider groq` -- check that
OpenRouter is in its `PROVIDERS` table before aiming it at these three. Budget: six models,
two tiers, three probes, ten runs each -- 360 requests -- came to **0.38 $** last time.

## How to redo this

Prices come from `https://openrouter.ai/api/v1/models`, which needs no key: every model
carries `pricing.prompt`, `pricing.completion` and, when the provider caches,
`pricing.input_cache_read`.

The three numbers at the top are not assumptions and should not be re-guessed:

- **input** -- parse `chars_system` + `chars_user` off the `request` lines in
  `bin\x64\plugins\cyber_engine_tweaks\gamelog*.log` and divide by 3.81. Do **not** use the
  `prompt_tokens` those lines report while a CLI lane is selected: that number includes the
  agent's harness, per the table above;
- **output** -- re-derive from the journal, not from `completion_tokens`. It is a property of
  how the characters are written, and a prompt that makes them chattier moves it;
- **messages per hour** -- timestamps of the `speaking` lines, split into sessions at gaps over
  15 minutes.

The 3.81 characters per token came from one real request and re-measures itself on every
request line (`chars_per_token=`). It was taken on an OpenAI-compatible provider; the
transcript is French and the system prompt English, so a different tokeniser could move the
input column by 10-20 %. Nothing above depends on it qualitatively.
