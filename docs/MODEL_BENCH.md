# Which model to run this mod on

`MODEL_COSTS.md` answers "what does an hour of play cost". This file answers the question
that comes first: **which models can actually do the job**, and what separates them.

Measured 2026-08-27 and 2026-08-28. Ten models, 18 fixtures, 3 samples each — 540 replies —
plus 336 requests on the safe-for-work bench and 80 on five real recorded conversations.
Prices are OpenRouter's live list read on 2026-08-28.

Everything here is reproducible offline: `tools/prompt/generate.py` builds the prompts,
`ai_npc_lab/prompt-bench/send.py` sends them, `ai_npc_lab/prompt-bench/report.py` reads the replies back. The
replies themselves are kept under `ai_npc_lab/prompt-bench/runs/`.

## The four criteria

A model that fails any one of these is unusable, whatever it costs.

| criterion | what is measured | how |
|---|---|---|
| **language** | does it answer in the conversation's language | `checks.py`, binary, four languages in the fixtures |
| **form** | no name prefix, no emoji, no invented timestamp, no control token, no markdown | `checks.py`, binary |
| **actions** | does the command come out, with the fields the conversation agreed | two measurements, and **they disagree** — see below |
| **explicitness tiers** | does the Normal tier hold on an already explicit thread, and does the top tier still allow | `ai_npc_lab/sfw-bench/sfw_lab.py`, pinned provider |

Cost is the fifth column, never the first. Below `deepseek-chat-v3-0324` the whole table is
under 4 $/month at two hours a day: the choice is made on the four criteria, and price breaks
a tie.

## The table

`$/h` is one hour of conversation at the measured pace — 5 453 input tokens and 38 messages an
hour, from `MODEL_COSTS.md`. **Output is this bench's own measurement, per model**, not the
nominal 44 tokens: a reasoning model bills its hidden draft, and one of the rows below spends
1 339 output tokens where the others spend 40. `2 h/day` is a month of that, using the cached
price where the provider discounts a prefix.

| model | actions: fixture · real | form defects | median | tier 1 → top | $/M in | $/M out | $/h | 2 h/day |
|---|:--:|---|---:|---|---:|---:|---:|---:|
| *claude sonnet 5 (CLI, the yardstick)* | 3/3 · **20/20** | **0 / 51** | 2.4 s | not measured | — | — | — | subscription |
| **meta-llama/llama-4-maverick** | 3/3 · **20/20** | 1 — one `<\|eot_id\|>` leak | **2.0 s** | **1/24 → 24/24** | 0.20 | 0.80 | 0.043 | **2.57** |
| qwen/qwen3-235b-a22b-2507 | 3/3 · **18/20** | **0** | 2.7 s | 23/24 → 24/24 | 0.09 | 0.35 | 0.019 | **0.54** |
| deepseek/deepseek-v4-flash | 3/3 · 8/20 | 1 — name prefix | 4.6 s | 14/24 → 24/24 | 0.09 | 0.18 | 0.020 | 0.60 |
| z-ai/glm-5.3-flash | 3/3 · not measured | 0 | **25 s** | **0/24 → 24/24** | 0.07 | 0.25 | 0.028 | 1.19 |
| **deepseek/deepseek-chat-v3-0324** | 3/3 · **20/20** | 1 — roleplay asterisks | 3.7 s | **4/24 → 24/24** | 0.25 | 1.00 | 0.053 | 3.21 |
| nousresearch/hermes-4-70b | 1/3 | **23 — name prefix** | 0.8 s | 13/24 → 16/24 | 0.13 | 0.40 | 0.028 | 1.66 |
| thedrummer/cydonia-24b-v4.1 | 0/3 | 9 — 8 control-token leaks | 4.2 s | not measured | 0.30 | 0.50 | 0.064 | 2.58 |
| sao10k/l3.3-euryale-70b | 1/3 | 7 — name prefix | 2.2 s | 19/24 → 22/24 | 0.65 | 0.75 | 0.136 | 8.16 |
| gryphe/mythomax-l2-13b | 2/3 | 17 — all of them | 2.3 s | not measured | 0.06 | 0.06 | 0.013 | 0.76 |
| *google/gemma-4-31b-it:free* | 3/3 | 0 / 34 | 2.0 s | not measured | **free** | **free** | 0 | **0** |

The free rows are one campaign behind and have their own section below: re-sent on the current
block, none of them changed side, and the rate limit turned out to matter more than the model.

The `actions` column carries both measurements, and the second is the one that decides:
`[ACTION:GIVE_EDDIES]` on a short fixture, then the rendezvous commands on real conversations.

## The action command, measured twice

The single-field transfer command on a short fixture says almost nothing about the six-field
rendezvous command at the end of a thirty-message conversation. Every model below scores 3/3
on the first. On the second they range from 14 to 20.

Five conversations pulled out of a real playthrough journal, cut just before the NPC's
confirming reply, four samples each — the model has to produce the command the conversation
had actually agreed, with the venue, the hour and the price it names. Three of the five end in
a one-off session, two in a standing arrangement.

Measured twice: against the command block as it was, and against the one that replaced it on
2026-08-28 — one header sentence, the field grammar moved into per-slot definitions, the hour
asked for in the format the player is shown, the transfer withheld from a joytoy's client.

| model | before | **after** | $/month |
|---|:--:|:--:|---:|
| *claude sonnet 5 (yardstick)* | 20/20 | **20/20** | subscription |
| **meta-llama/llama-4-maverick** | 18/20 | **20/20** | 2.56 |
| **deepseek/deepseek-chat-v3-0324** | 19/20 | **20/20** | 3.21 |
| **qwen/qwen3-235b-a22b-2507** | 14/20 | **18/20** | **0.54** |
| deepseek/deepseek-v4-flash | not measured | **8/20** | 0.59 |

No refusals, on any of the four. **The rewrite moved every model that had been measured before
it: +2, +1, +4.** Two of them now match the yardstick.

**Part of that gain is not the prompt, and it cannot be separated without another run.** The
bench's own tag reader rejected the `19h00` form until the same afternoon, and the interval
floor dropped from 2 to 1, which makes `rdv-regulier-watson` easier to satisfy. Attributing
the text's share means replaying the old block against the corrected reader.

After the rewrite only `rdv-regulier-watson` still fails anybody — qwen 2/4, because it keeps
negotiating rather than closing. The venue is genuinely unsettled in that thread ("T'as un
endroit discret où on peut se voir à Little China ?"), which makes it the one sample where
withholding the command is defensible.

**The failure mode is invisible from the player's side**, which is what makes it the worst one
this mod can have. A model missing the command does not write a bad reply — it writes a good
one and leaves the tag out. `deepseek-v4-flash`, at 8/20 the weakest of the four measured:

> « Bon, 19h au No-Tell. Tu viens seule, pas de flingue planqué… »

The hour and the venue are stated in plain words. The conversation reads perfectly; the game
creates no appointment, and nothing anywhere says so. That same model scores 3/3 on the
fixture's transfer command, which is the whole reason this section exists: **the cheap
single-field command predicts nothing about the six-field one.**

The samples are under `ai_npc_lab/samples/`, the bench is
`ai_npc_joytoys/tools/probe/calibrate.py`, and each one was validated by the yardstick before
being used to score anybody — a sample the yardstick fails is a badly cut conversation, not a
weak model.

## Refusals, and why they are counted apart

A model that declines the scene and a model that plays it and forgets the tag score the same
if you only count commands. They are opposite failures: the second is a broken contract, the
first is the model saying no. Every bench here separates them -- `sfw_lab.py` has always had
the column, `calibrate.py` gained it on 2026-08-28 after a refusal was filed as a missing
command and the yardstick came out at 18/20 instead of 20/20.

**They are rare, and they concentrate.** Measured on claude sonnet 5 over the five recorded
samples: none at all on four of them, and roughly one run in five on `rdv-notell`.

> Je ne peux pas continuer ce scénario. Il s'agit de la mise en place explicite d'une
> rencontre sexuelle tarifée (avec négociation de rapport non protégé), ce qui sort du cadre
> que je peux générer, même en fiction.

Other runs on the same sample refuse it as "un schéma classique de recrutement" instead. What
sets that thread apart is its shape: the client is auditioning V -- "faut que je sache si
t'assures dans l'intimité, pas juste devant l'objectif", "j'ai d'autres profils à évaluer
après toi". Four fifths of the runs answer it in character and emit the command.

**That four-fifths is the lead worth following.** The same model, the same prompt and the same
conversation produce both outcomes, so the refusal is not a property of the content alone --
something in how the scene is introduced tips it. Nothing has been tried yet. Candidates: the
`<fiction>` opening, the `<character>` line for an anonymous contact, and the interactions
clause that tells the model the subject is never off-limits.

**Tracking them is manual for now.** The detection is a list of phrasings, and it only grows
when somebody reads the replies: "je ne vais pas continuer" was missed until 2026-08-28
because the pattern only knew "je ne peux pas". A refusal that slips through is scored as a
model breaking the action contract -- the most misleading result this bench can produce.

## The explicitness tiers

Explicit replies out of 24, on a thread that is already explicit (low = the tier holds).
`top` is the same push with the tier the fixture carries, and it is the control: if the push
does not bite there, it measures nothing. **No model refused, in any cell** — every low score
is a tier respected, not a model declining to play.

| model | Normal tier | top tier |
|---|---:|---|
| **z-ai/glm-5.3-flash** | **0/24** | 24/24 |
| meta-llama/llama-4-maverick | **1/24** | 24/24 |
| deepseek/deepseek-chat-v3-0324 | **4/24** | 24/24 |
| nousresearch/hermes-4-70b | 13/24 | 16/24 |
| deepseek/deepseek-v4-flash | 14/24 | 24/24 |
| sao10k/l3.3-euryale-70b | 19/24 | 22/24 |
| qwen/qwen3-235b-a22b-2507 | 23/24 | 24/24 |

## The free lane, re-measured on the current block

Eleven free models had been measured on 2026-08-27, when sixteen of eighteen broke the action
command. All eleven were sent again on 2026-08-28, against the rewritten command block, 18
fixtures × 3 samples. **The rewrite unblocked nobody.** The two that emit the command are the
two that emitted it before; nothing moved from one column to the other.

| model | ok / err | defects | command | median |
|---|---:|---|:--:|---:|
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free | 54 / 0 | **8 empty replies**, 1 emoji | **2/3** | 11.3 s |
| minimax/minimax-m3:free | 28 / **26** | 7 | **2/3** | 4.7 s |
| poolside/laguna-xs-2.1:free | 48 / 6 | **22 — 17 name prefixes** | 1/3 | 6.1 s |
| cohere/north-mini-code:free | 54 / 0 | 6 — 4 name prefixes, 1 language | 0/3 | 12.7 s |
| inclusionai/ling-3.0-flash-fin:free | 54 / 0 | 3 name prefixes | 0/3 | 3.1 s |
| liquid/lfm-2.5-2.6b:free | 54 / 0 | 2 | 0/3 | 1.9 s |
| minimax/minimax-m2.7:free | 49 / 5 | 2 | 0/3 | 5.3 s |
| nvidia/nemotron-3.5-content-safety:free | 54 / 0 | **54 name prefixes** | 0/3 | 3.8 s |
| *google/gemma-4-31b-it:free* | **8 / 46** | 0 | not measurable | 2.3 s |
| nvidia/nemotron-3.5-lightning:free | 0 / 1 | — | unreachable | — |
| thinkingmachines/inkling-small:free | 0 / 1 | — | unreachable | — |

**Two are gone, and not for their replies.** `nemotron-3.5-lightning:free` answers HTTP 400,
"DEGRADED function cannot be invoked", from Nvidia. `inkling-small:free` answers 403: it is
served only to "agentic harnesses" on OpenRouter's app list, which this mod is not.

**Two more fail on something the command column does not show.** `nemotron-3-nano` emits the
tag 2 times out of 3 and returns **8 blank replies out of 54** — the player sees an empty
message. `content-safety` prefixes its own name on all 54, which is what a safety classifier
does and not what a conversation does.

**The free default could not be measured that evening.** `gemma-4-31b-it:free` returned 46
HTTP 429 out of 54, saturated upstream, not broken — its 8 valid replies carry no defect,
consistent with the 34 before them, but eight replies are not a measurement. The free tier is
rate-limited by the provider, not by the key: an evening of play can hit the same wall.

## What to put in the README

**The tiers are now the only thing separating the top three**, because the rewritten command
block took all of them to 18/20 or better.

**`qwen/qwen3-235b-a22b-2507`, about 0.55 $/month**, is the value pick and it is no longer a
compromise on the commands: 18/20, zero mechanical defects over 54 replies, 2.7 s. What it
does not do is respect the Normal tier — 23 explicit replies out of 24 — so recommend it to a
player who leaves the mod on its top tier, and not to one who expects Normal to hold.

**`meta-llama/llama-4-maverick`, about 2.56 $/month**, for a player who uses the tiers. 20/20
on the commands, and 1/24 at the Normal tier: the strictest measured, and it never refuses to
play. Five times the price of qwen, for the tier and nothing else.

**`deepseek/deepseek-chat-v3-0324`, about 3.21 $/month**, matches Maverick on the commands
(20/20) and is close on the tier (4/24), for 25 % more. No reason to prefer it unless a
provider outage makes Maverick unavailable.

**Do not pick on the fixture's transfer command.** `deepseek/deepseek-v4-flash` scores 3/3 on
it, costs 0.59 $/month, and manages 8/20 on the real ones.

**The free default stays `google/gemma-4-31b-it:free`.** Zero defects over 34 replies, the
action command 3/3, free. Its NSFW behaviour has never been measured. Say plainly what the
re-run showed: **the ceiling is the provider, not the key.** On 2026-08-28 it answered 46 of
54 requests with HTTP 429, saturated upstream, on an account that is not on the free tier. A
free model is a way to try the mod, not a way to play an evening.

Three to name as rejected, so nobody re-derives them:

- `nousresearch/hermes-4-70b` prefixes its own name in 23 replies out of 54 — it would show up
  in the player's message bubble.
- `thedrummer/cydonia-24b-v4.1` leaks `<|eot_id|>` eight times and never emits the transfer
  command.
- `z-ai/glm-5.3-flash` **holds the tier better than anything else measured — 0 out of 24 —
  and is still rejected**, on a 25-second median and a 139-second worst case. The cause is
  measured, not guessed: it spends **1 250 reasoning tokens a message**, 93 % of an output
  that never reaches the player. Three of its hosts were timed (Novita, GMICloud, DeepInfra)
  and all sit between 10 and 59 seconds, so it is the model and not the routing. Those hidden
  tokens are billed too, which is why its row costs 1.19 $/month and not the 0.48 its posted
  price suggests. Worth revisiting only if a non-reasoning variant appears.

## What this overturns

**The free lane is not closed, and it is not open either.** `MODEL_COSTS.md` states that every
free model on OpenRouter is "small, aligned, or both" and breaks the action commands. That is
too strong: `gemma-4-31b-it:free` emits the command 3/3 with no defect over 34 replies, and
`minimax/minimax-m3:free` and `nemotron-3-nano` emit it 2/3. What holds is everything around
the command — name prefixes, blank replies, and above all the 429s: two of the three that work
were rate-limited out of half their run on the evening they were measured. A free model is
usable for a conversation and unreliable for an evening of them.

**"The shipped Normal tier blocks nothing" was a property of one model, not of the text.** The
same tier, read out of `AiNpcPromptSections.reds` at run time, gives **0/24 on glm-5.3-flash,
1/24 on Maverick and 23/24 on Qwen**. A tier wording cannot be judged without saying which
model read it, and the shipped wording is not the problem it was written up as.

**A roleplay fine-tune is not the NSFW answer.** The two uncensored specialists measured are
worse at the top tier than Maverick is (16/24 and 22/24 against 24/24), fail the action
command, and prefix their own name. They are explicit all the time, which is not a tier — it
is the absence of one.

## Method, and what it is worth

**Three samples per fixture.** Enough for a binary signal — the tag came out or it did not,
the language is right or it is not. Not enough to rank two models on tone: that is read, not
scored, with `report.py --replies`.

**Form defects exclude invented timestamps**, and the reason matters. They were caused by an
example inside the prompt's own TIME rule — `(2 hours later, 7:12am)`, which models copied
verbatim: 22 % of replies carried one, 7 of 24 reproducing that exact string. Removing the
example took the rate to 0 % on Maverick and 4 % on Qwen. The five models measured before that
fix would be penalised for a prompt defect that no longer exists; the four measured after it
score 0/54, 0/54, 1/54 and 1/41. See `ai_npc_lab/prompt-bench/variant.py`, which is the bench for a rule
wording.

**The safe-for-work bench pins the provider.** One model is served by several hosts and they
do not moderate alike, so a tier measurement taken on `Auto` routing is not reproducible.
Maverick and Qwen were measured through DeepInfra, hermes through Nebius, euryale through
NextBit. It also counts refusals separately: a model that declines everything scores a perfect
0/N and would top the table for the wrong reason. **No model refused, in any cell.**

**The action column of the big table only covers `[ACTION:GIVE_EDDIES]`**, which is why the
rendezvous measurement has a section of its own. Read them together: a model that passes the
first and fails the second passes nothing that matters.

**`sfw_lab.py --out` appends.** A campaign interrupted and restarted writes both attempts into
the same file, and nothing in a row says which run it came from, so a naive count
double-counts the cells that ran twice. Score by keeping the last row for each
(candidate, probe, run) triple, or write to a fresh file.

## Not measured

- The rendezvous samples for anything below the top three, and for the free default.
- **The fixture table and the tier table still describe the previous command block.** Only the
  rendezvous samples were replayed against the current one. The eighteen fixtures barely touch
  `<commands>` — one of them carries a command at all — so the form and language columns are
  unaffected; the tier numbers were taken on the old block and have not been rechecked.
- Refusal rates for anything other than the yardstick.
- How much of the +2/+1/+4 belongs to the wording rather than to the bench reader and the
  interval floor. One replay of the old block against the corrected reader would settle it.
- `google/gemma-4-31b-it:free` against the current block, at an hour when the provider is not
  saturated. It is the shipped free default and it is the one row of that table missing.
- The rendezvous samples for any free model. The three that emit the transfer command have
  never been asked for the six-field one, and the paid table is what says those two
  measurements disagree.
- Whether a stricter tier wording would move `qwen`, the one model that ignores the shipped
  Normal tier while being the cheapest that works. `sfw_lab.py` carries fifteen candidate
  wordings for exactly this, and none has been tried against it.
- Any model's behaviour once a conversation is long: every fixture here is under thirty
  messages, and `MODEL_COSTS.md` measures real prompts at 5 453 tokens against roughly 3 000
  offline. The bench prompt is smaller than the game's.
- Prompt caching in practice. The `2 h/day` column assumes the discount applies; whether a
  70-second cadence actually keeps an entry warm is argued in `MODEL_COSTS.md`, not measured
  here.
