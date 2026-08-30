# Plan: one model per kind of work

Today every request the mod makes goes to one model: `AiNpcLlmChatModel(provider)` reads a
single setting, and `AiNpcLlmWithTuning` applies one `max_tokens` and one `reasoning_effort`
to all of them. A reply the player reads, a memory compaction with a section format to
respect, and a one-bracket repair are the same call with different text in it.

This plan gives each kind of work its own model and its own request parameters. It does
**not** change what any prompt says, and it does not add or move a request.

## Why, in the order that matters

1. **A truncated compaction is a corrupted memory.** `maxTokens` defaults to `0` — nothing is
   sent — but a player who sets it to control spend caps the compaction too. Sections go
   missing at parse time, facts are lost, and nothing reports it. One slider cannot govern a
   text message and a structured note.
2. **It is what makes the next calls affordable.** A dedicated action selector, a ranker over
   the archive, a relevance filter before compaction: each is an added request per turn, and
   each is negligible on a cheap slot and unacceptable on the dialogue model.
3. **Cost becomes readable.** `AiNpcUsageLedger` already totals per lane
   (`LaneTotal(AiNpcLaneSpeaking())`). Once the model follows the lane, the daily report says
   what each kind of work costs, with no new instrument.

The split is not *important vs accessory*. It is **per turn vs occasional** — the rule the
SkyrimNet presets follow, where the budget preset keeps a large model for bios and diaries
and downgrades the dialogue. We spend on what every message pays for.

---

## What "done" means

The player who configures nothing gets exactly today's behaviour, byte for byte in the
prompt and identical in the request body. The player who wants to can name a second model for
memory and a third for mechanical work, and the daily usage report attributes tokens to each.

Nothing else. No new request, no prompt edit, no action selector — that is
`docs/ROADMAP.md`, *The action selector on its own call*, and it depends on this plan
without being part of it.

---

## 1. The slots

The lanes already exist and are already named. A slot is a lane plus whatever the file says to
send with it.

| Slot | Lane (`AiNpcRequestLog.reds`) | What goes through it | Output |
|---|---|---|---|
| **dialogue** | `AiNpcLaneSpeaking()` | the reply, and the unprompted message | free prose |
| **memory** | `AiNpcLaneThinking()` | compaction and chronicle fold | a section format |
| **mechanic** | `AiNpcLaneRepair()` | the repair pass; later, the selector and the ranker | one line |
| *(test)* | `AiNpcLaneTest()` | the configuration check | one sentence |

`test` is not a fourth slot. It runs against the slot it is asked to check, and the Mod
Settings button checks `dialogue`. Anything else declares the installation healthy while the
memory model is a typo the player meets ten replies later.

The CLI providers (`ClaudeCli`, `CodexCli`) ignore slots and keep their single model. They are
development lanes, not shipped ones, and dividing them buys nothing.

---

## 2. The settings format

```json
{
  "openRouterApiKey": "",
  "slots": {
    "dialogue": { "model": "google/gemma-4-31b-it:free" },
    "memory":   { "max_tokens": 1200, "timeoutSeconds": 60 },
    "mechanic": { "max_tokens": 150, "temperature": 0.2, "timeoutSeconds": 20 }
  }
}
```

Four rules, and each one is why the shape is nested rather than a flat `memoryMaxTokens`
beside `mechanicTemperature`.

### A slot IS a request fragment

The keys are the protocol's — `model`, `max_tokens`, `temperature`, `top_p`,
`reasoning_effort` — not names of ours. `{"model": "...", "max_tokens": 1200}` is already
valid request JSON. The mod builds its body, then overlays the slot object on it.

**It reads none of these keys. It copies them.** That is the point: a parameter a provider
ships tomorrow works tomorrow, with no accessor, no setting, no release. A flat file would
need one typed reader per parameter per slot, and this mod has no `GetSettingInt` — the only
numeric setting it has today, `maxTokens`, is read as a string.

### Reserved keys are camelCase, and there are as few as possible

`timeoutSeconds` belongs to us, not to the provider. It is stripped before the overlay. The
casing carries the boundary so a reader can see it without a list: **`snake_case` goes on the
wire, `camelCase` stays here.** Every reserved key is declared in one place, and adding one is
a decision, not a convenience.

### Resolution is key by key, with `dialogue` as the base

A key absent from a slot is taken from `dialogue`. One rule, not two: "the slot is empty" and
"the slot says nothing about this parameter" become the same case. `memory` above names no
`model`, so it uses the dialogue model — and the file says exactly what the player meant.

### An unknown slot is ignored; a missing slot is an empty slot

Both directions are safe, and that is what lets a slot be added without breaking anything: a
version that writes `"vision"` does not disturb a version that has never heard of it, and the
reverse holds too.

### What this removes

The `"max_tokens": 0` trap. Today `0` has to mean "do not send the key", because a DTO field
is always serialised — hence the key being added after serialisation. With an overlay, an
absent key is simply not sent: the file expresses absence, not a sentinel value. A player who
wants no cap deletes the line.

The typing problem goes with it. Values are copied as `JsonVariant`; a number stays a number,
and nothing round-trips through `GetKeyString`.

### Compatibility

`openRouterModel`, `maxTokens` and `reasoningEffort` stay readable and win when present, as
aliases into `slots.dialogue`. One branch, and no existing `settings.json` stops working —
nor any screenshot in a bug report.

### What is deliberately not done

**Mod Settings gets no slot widgets.** A nested object has no widget, and inventing one would
mean flattening the shape in the menu — the very thing this format refuses. The menu keeps the
dialogue model it already has; slots are a file-level feature for the player who wants them.

**`slots` sits at the root, not under a provider.** Model ids are per-provider namespaces
(`deepseek/deepseek-v3.2` against `sonnet`), so this is wrong the day a second distributable
provider exists — and right today, when there is one and the CLI lanes ignore slots. The
migration when it comes is `"providers": { "openRouter": { "slots": … } }`, and it is named
here so it is not discovered.

---

## 3. The code

Two signatures, at the one point that already decides:

```
AiNpcLlmChatModel(provider)   ->  resolved from the slot
AiNpcLlmWithTuning(body)      ->  AiNpcLlmOverlaySlot(body, slot)
```

`AiNpcLlmChatBody` takes the slot and applies the overlay. The four callers already name their
lane one line away, when they build their `AiNpcRequestRecord`:

| Caller | Line | Slot |
|---|---|---|
| `AiNpcHttp.reds` | 234 | dialogue |
| `AiNpcHttp.reds` | 577 | mechanic |
| `AiNpcMemoryService.reds` | 156 | memory |
| `AiNpcSetup.reds` | 316 | the slot under test |

A slot is a value, not a string typed at each site — the same shape as `AiNpcLaneSpeaking()`
and next to it, so a caller cannot invent a fifth.

**The overlay is pure.** It takes the body and the resolved slot object and returns the merged
body: no storage, no game, no provider. Resolution against `dialogue`, reserved-key stripping,
absent-key semantics and unknown-slot tolerance are all assertable in
`tests\AiNpcTestTransport.reds` with no session. The impure half is one new read path,
`GetSlot(name)` in `AiNpcStorage.reds`, because `GetSetting` is flat and cannot reach into an
object.

### Validation moves to the provider, so the log has to name the slot

A mistyped key is not refused by the mod. It goes out and comes back a 400. That is the price
of a format the mod does not enumerate, and it is only payable if the failure is
diagnosable: `AiNpcRequestLog` already records the lane; it records the slot name and the
merged body, and the 400 says which slot produced it. Without that, this format trades a
readable error for a mystery.

---

## 4. Step order, with kill criteria

Each step is verifiable alone, offline. Stop at the first that fails.

1. **The overlay, pure, with its tests.** Key-by-key resolution against `dialogue`, reserved
   keys stripped, unknown slot ignored, absent key not sent, a slot that says nothing
   producing a body identical to today's.
   *Kill:* if any of those needs a session to assert, the seam is wrong.
2. **`GetSlot` in storage**, plus the three aliases (`openRouterModel`, `maxTokens`,
   `reasoningEffort`) and the rule that a present alias wins.
3. **Measure the memory cap** with `journal.py memory` over real compactions, and write the
   number into this file next to how it was obtained. `1200` above is a placeholder and must
   not ship as one — a guess here is the failure this plan exists to prevent.
4. **The four callers**, one commit, no behaviour change while `slots` is absent.
   *Kill:* if the request body for an unconfigured install is not identical to the previous
   one, byte for byte, stop — the migration rule is broken.
5. **The request log**: slot name and merged body.
6. **The usage report**, which already totals per lane, now labelled per slot.
7. **`settings.example.json`** gains a commented `slots` block, and `docs/` says what the
   reserved keys are.

---

## 5. What the linter must forbid

- a call to `AiNpcLlmChatBody` that does not name a slot;
- a slot key read individually anywhere — the overlay copies, it does not inspect;
- the reserved-key list written in more than one place;
- a request parameter reintroduced as a typed setting beside the slots.

---

## 6. What must not be touched

The prompts. Not one word, in any section, in this pass. A model change and a prompt change
measured together cannot be told apart afterwards, and the wording rule of this project is
that a prompt is never rewritten alone anyway.

## 7. What must not be claimed

That a cheaper model is good enough for memory or repair. This plan makes the choice
*possible* and ships with no `slots` block at all, which means every slot on the dialogue
model, which means nothing has been measured. The first person to fill one owes a bench run.
