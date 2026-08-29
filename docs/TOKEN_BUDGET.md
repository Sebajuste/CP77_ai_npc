# The daily token cap

A ceiling on what the mod may spend in a day, set in Mod Settings, off by default.

Written and implemented 2026-08-23. Everything below is in the build, compiles in all three
shapes and is covered by the offline suite; **none of it has been exercised in a running
game** -- see the last section for what a first launch has to confirm. The numbers it leans on
were measured for `PROMPT_BUDGET.md`, which is the companion document: that one says what a
turn costs, this one says how to stop paying.

## The rule, in one sentence

    A request is refused when the day already recorded in usage.json is the same day the
    provider last said it was, and its total has reached the budget.

Everything else in this document is that sentence, taken apart.

## What "today" is, and why it comes from the network

Redscript has no real clock. `GameTime` is the time inside the fiction, `GetSimTime` is the
time since the session started; neither can name a calendar day, and there is no vanilla API
that can. A cap "per day" therefore has no clock of its own to read.

It has one from the outside. `RedHttpClient` exposes `HttpResponse.GetHeader`, and every HTTP
response carries `Date: Sat, 23 Aug 2026 15:42:58 GMT`. That is a real date, in UTC, stated by
the provider itself — which is also the machine that resets its own free-tier quota, so the
two roll over together. Only `"2026-08-23"` is kept: no timezone arithmetic, no parsing beyond
the day.

The consequence is stated rather than worked around:

**The first request of a session always goes through.** No response has arrived yet, so no day
has been confirmed, so there is nothing to compare the stored day against and nothing to
refuse. That request's own `Date` header settles it. Same day and the budget is spent — every
request after it is refused. A different day — tomorrow, or three weeks later — and the tally
is purged and starts again under the new date.

That is one request per game launch in the worst case, and it is what stops the mod from
locking out a player who comes back the next day. The alternative was refusing on a date the
mod had no way to check, which is worse: a wrong refusal has no symptom a player can act on.

A provider that returns no `Date` header confirms no day. The tally keeps accumulating under
the last date known, and the cap keeps applying — a backend that will not say what day it is
does not get to reset the counter.

## What is counted

`total_tokens` when the provider reports it, otherwise `prompt + completion`, otherwise —
a provider that reports no usage block at all — an estimate of `characters / 3.81`, the ratio
measured in `PROMPT_BUDGET.md` and recomputed on every request line since.

That estimate is a deliberate departure from `AiNpcRequestLog`'s rule that **absence is never
zero**. The rule stands for the log: a provider that measured nothing must not print 0, or an
unmeasured day reads as a free one. But a ceiling that counts nothing when the provider says
nothing is not a ceiling — it is a switch anyone can turn off by choosing the right backend.
So the ledger charges an estimate, and marks it as one (`estimated` in the file, and on the
request line), which keeps the two readers honest about which number they are looking at.

All four senders count, and there is **no exemption for any provider**. The local bridge is
billed into the same tally as OpenAI and OpenRouter: one rule, one pipeline, no branch that
has to be kept in step. Someone running a local model simply leaves the cap switched off,
which is the default anyway.

    speaking   the reply the player is waiting for          AiNpcHttp.ChatPostRequest
    repair     the retry that rewrites a broken command     AiNpcHttp.RepairPostRequest
    thinking   the memory compaction, behind the player     AiNpcMemoryService.Send
    test       the connection check in Mod Settings         AiNpcSetup

The fourth is new to the accounting: it was the last `AsyncHttpClient.Post` in the mod with no
`AiNpcRequestRecord` behind it, so giving it one is also what makes it appear in the request
log. It is the one send the cap never REFUSES -- someone running a connection test is trying
to find out why nothing works, and answering "your budget is spent" to a diagnostic, when the
real fault may be a dead key, is how an evening gets lost. Its answer is also useful: it
carries a `Date` header like any other, so a test run after midnight is what tells the mod the
day has turned.

## What happens at the ceiling

Everything stops: speaking, repair and memory alike. A cap that leaves one lane open is not a
cap, and the lane it would leave open is the invisible one — the compaction that spends
without the player having typed anything.

The refusal is delivered the way a scripted reply is (`HandleMessage(..., carrier: true)`): the
typing indicator comes down, the input is released, the line is journalled. The text is a
telecom fact, which is what the fiction of a phone is already built on — a data allowance
spent for the day, not an error. It gets its own per-language table next to
`AiNpcCarrierMessageFor` in `AiNpcLanguage.reds`; it must not reuse the carrier line, which
means something else (the network is down) and would send a player looking for a network
problem they do not have.

One warning line is sent when the day crosses 80%, once per day. Without it the ceiling is
discovered mid-conversation.

## Where it lives

One responsibility per file.

| File | Role |
|---|---|
| `AiNpcUsageLedger.reds` *(new)* | The pure model: `{ day, total, estimated, warned, lanes }`, adding to it, rolling it onto a new day, reading the day off a `Date` header, and its JSON shape. No game access, so the offline suite pins every rule. |
| `AiNpcUsageService.reds` *(new)* | The `ScriptableService` that holds the ledger, loads `usage.json` through `AiNpcStorageService.GetFileStorage()`, writes it back after each charge, and answers the one question the lanes ask. |
| `AiNpcUtilities.reds` | `AiNpcDailyLimitEnabled`, `AiNpcDailyTokenBudget` and `AiNpcHasTokenBudgetLeft`, in the file where every other setting is asked for by name. |
| `AiNpcRequestLog.reds` | `Answered` takes the whole response rather than only its parsed body -- the day is in the `Date` header -- and charges the ledger. The line gains `charged=`, `charged_from=chars` on an estimate, and `day_total=`. A fourth lane, `test`, is named. |
| `AiNpcHttp.reds` | `RefuseIfBudgetSpent` before the speaking send; the budget as a fifth condition on the repair; `DeliverBudgetWarning` at the end of `HandleMessage`. |
| `AiNpcRepair.reds` | `Claim` takes `budgetLeft`, so "a spent day buys no retry" is a decision assertable offline like the other four. |
| `AiNpcMemoryService.reds` | The gate in `Consider`, next to the credential check: a compaction is deferred, never abandoned. |
| `AiNpcSetup.reds` | A record for the connection test, which was the last send in the mod going out unaccounted for. |
| `AiNpcSystem.reds` | The two Mod Settings entries. |
| `AiNpcLanguage.reds` | The two lines the player reads, per language, beside the carrier table. |
| `tests\AiNpcTestTransport.reds` | `AiNpcTestUsageLedger` and `AiNpcTestBudgetMessages`. |

`usage.json` sits in `r6\storages\AiNpc\`, beside `settings.json`. That is the point: a
`RedFileSystem` storage is **not** part of the savegame, so one tally covers every save, every
character and every branch — which is the only shape that matches what a provider actually
meters, one key, one day.

## The settings

Mod Settings, category "Budget", order 4. The pattern is `memoryEnabled` / `memoryFacts`: a
switch, and a value that depends on it.

    Daily Token Limit             Bool    default false
    Tokens Per Day (thousands)    Int32   default 200, min 10, max 1000, step 10
                                          dependency: dailyLimitEnabled

Off by default, because a cap the player did not ask for turns into a character who stops
answering for reasons nothing on screen explains.

200 000 when it is switched on: that is the free tier measured on Groq, about 40 messages a
day once a character remembers anything. In thousands because Mod Settings has no free numeric
field, and a step of 1 across 200 000 is not a slider anyone can use.

## Two imprecisions, accepted

**The ceiling can be overshot by one request.** The gate runs before the send; the cost is only
known after. So the rule is "nothing new is started once the line is crossed", not "the line is
never crossed". Predicting a request's cost before sending it would buy a precision worth less
than the machinery.

**A blocked day leaves memory uncompacted.** Messages accumulate unabsorbed until the next day.
Nothing is lost — the store keeps every message, always — but the prompt stays large in the
meantime, which costs more on the day the budget comes back. It is the price of the previous
section's decision, and it is the right way round: the alternative spends real tokens on a day
the player declared closed.

## The unit is the provider's, not the mod's

Measured 2026-08-25, and it is the one thing about this cap that can mislead a player.

The tally counts **what the provider says it billed**, which is the only honest thing it can
count. But on a CLI lane that number includes the agent's own harness, and the multiplier is
not small: over the 169 requests of 2026-08-24, `usage.json` recorded **2 851 914** tokens for
a prompt that actually weighed **849 563** -- 3.24x, and 4.46x on the bridge specifically. The
per-lane figures are in `MODEL_COSTS.md`.

So the same cap means two different things depending on the provider selected. A player who
sets 200 000 because that is their OpenRouter free-tier quota, and then switches to the Claude
lane, will be refused after roughly a third of the messages they expected -- with no symptom
that explains why. Nothing here is wrong: the ledger is measuring the bill, and the bill really
is that size on that lane. The gap is that **the number a player reasons about is the prompt,
and the number the cap enforces is the invoice.**

Not fixed by discounting the harness, which would be a second estimate layered on a measured
figure and would make the cap stop bounding the thing that is actually charged. What the
setting owes the player instead is the ratio: the request line already carries both halves
(`chars_system` + `chars_user` against `charged`), so the cap's own description can say what a
message costs *on the lane currently selected* rather than in the abstract -- the same
self-measuring shape `PROMPT_BUDGET.md` argues for on the prompt toggles.

Unimplemented. Recorded here so the next reader does not diagnose a lane switch as a broken
cap.

## What a first launch has to confirm

Nothing here has run in the game. Three things the offline suite cannot see:

* **the `Date` header arrives.** `RedHttpClient` exposes it and every backend measured sends
  it, but this is the first code in the mod to read a response header. With logging on, the
  line to look for is `day_total=` on a request line, and `A new day: the token tally starts
  again from zero` at the first rollover;
* **`usage.json` appears** in `r6\storages\AiNpc\` after the first answered request, and its
  `day` matches the real UTC date;
* **the refusal reads as a phone message**, not as a failure: switch the cap on, set it to its
  floor, and spend it.

## What the offline suite pins

Everything above that is a rule rather than a wire, which is why the model is a separate file:

* a new day purges the total, whether it is the next one or a month later;
* the same day accumulates across lanes, and across a save/load;
* no day confirmed yet ⇒ no refusal, whatever the stored total says;
* a response with no `Date` header confirms nothing and resets nothing;
* usage absent ⇒ the estimate is charged and flagged, and `chars / 3.81` is what it is;
* the cap disabled ⇒ the ledger still counts and never refuses.
