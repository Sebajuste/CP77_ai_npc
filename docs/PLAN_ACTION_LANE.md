# Plan: one lane for actions

Written 2026-08-27 from a read of the action path end to end, in both repositories, and
**executed the same day** in both. It stays as the account of why the lane has the shape it
has; `docs/API.md` is what a consumer reads.

> **Status.** Done in `ai_npc` and in `ai_npc_joytoys`. Both compile clean on every pass, both
> lints pass, the C++ suite passes, and the offline prompt builder rebuilds the new prompt. What
> has NOT happened is a game launch: the runtime self-tests replay a cached result from before
> this work, and the two prompt oracles now predate the mod, so nothing here has been seen to
> run. Re-capture with `ai_npc_lab\unprompted\capture.py` at the next launch.
>
> Two things changed against what is written below, and both are argued where they happen:
> patterns grew **optional trailing slots** (`{days?}`), because the rendezvous command really
> does carry three fields to five; and the world-knowledge registry's identity grew the contact
> id, because D4 turned out to be an identity defect rather than a wrong call.

This document is the brief the work followed: what was wrong, **why it was wrong**, the shape
the correction had to take, and what must not be touched.

The subject is narrow and the change is not: every action a character can perform — the
built-in eddie transfer, the tags a character sheet declares, everything `ai_npc_joytoys`
registers — goes through **one** declaration, one dispatcher and one report. Today it goes
through two paths that do the same thing under different names, and every divergence between
them has been a silent defect.

## How to work on this

The rules from `CP77_mods/CLAUDE.md` decide the judgement calls. In the form they take here:

**No fix.** Not one item below is closed by a guard in front of a symptom. Three of the four
defects in §2 could each be silenced in two lines; silencing them leaves the cause — two
paths for one truth — exactly where it is, and the fourth defect of the same family will be
written next month. When the clean correction turns out larger than this document assumes,
**say so to the user instead of shrinking it into a patch**.

**One file, one responsibility.** This pass adds concepts. A concept is a file. `AiNpcActions.reds`
currently carries four roles and `AiNpcHttp.HandleMessage` carries five; §7 says where they go.

**No recursion.** The pattern matcher and the tag matcher are loops over indices.

Also true, and cheaper to read here than to rediscover:

- REDscript has no `continue` and no `try`/`catch`. Restructure with nested `if`/`else`.
- Indexing the result of a call reads empty. `Foo()[0]` compiles, warns nothing, yields
  nothing. Bind to a local first — `ArrayContains` and friends take their operand by
  reference, and the existing dispatch carries comments about exactly this trap.
- REDscript has **no function values and no closures**. Verified across the 784 installed
  mods: zero function-typed parameters, zero closures. The only callback mechanism in the
  ecosystem is Codeware's `RegisterCallback(n"Event", target, n"MethodName")`, which resolves
  a method name by reflection — stringly typed, and a dependency this mod does not take. A
  callback here is therefore **an object with one virtual method**.
- `opt param: array<T>` is fine and idiomatic: verified in EquipmentEx, RedFileSystem and
  RedHttpClient, all installed and running.
- `.reds` files are UTF-8 **without BOM**. Use Edit, or Python with
  `io.open(..., encoding="utf-8")`. Never `Get-Content` → `Set-Content`.
- `tools/compile-check.ps1` shares a work directory between concurrent runs. Pass your own
  `-WorkDir`.
- Several agents share this working tree. Check `git status` before believing that something
  you did not write is your own doing.
- **Never deploy.** Build the zips with `tools/package.ps1`; the user installs them in Vortex.

### What "done" means

§11 carries the acceptance checks. They are checks, not descriptions: each one is a thing that
can come back false. Run `powershell -File tools\test.ps1 -WorkDir <your own>` before and
after.

---

## 1. What is wrong

An action has two halves that must agree: what the model is **told** it may emit, and what the
mod **honours** when it comes back. Today those halves are computed by two independent sets of
functions that never consult each other.

```
              ANNOUNCED                              HONOURED
              AiNpcGetWorldMechanics                 AiNpcParseActions          (built-in)
              provider.GetActionPromptFragment       provider.GetActionTags
              AiNpcExtensionActionFragment           AiNpcExtensionApplyAction
                       │                                      │
                       └────────► <mechanics>          reply ─┘
```

Nothing enforces that the left column and the right column describe the same set of commands.
Every defect found in this review is a divergence between them, and none of them is visible in
a log, a compile, or an offline test.

## 2. The four measured defects

All four are **independent of the refactor** — each could be corrected on its own. They are
listed because they are the evidence that the two-column shape produces this class of defect
on its own, and because the refactor must be checked against them: after the pass, each one
must be *inexpressible*, not merely fixed.

**D1 — the dead veto.** `AiNpcCharacterExtension.AllowsGenericTransfer` is documented in
`docs/API.md` as a veto ("anyone may remove the eddie-transfer commands, nobody may put them
back"). The aggregator `AiNpcExtensionAllowsGenericTransfer` exists at
`AiNpcExtensionRegistry.reds:450` and **is called from nowhere**. The two sites that decide —
`AiNpcPromptSections.reds:290` (announce) and `AiNpcHttp.reds:473` (honour) — ask only the
provider. An extension that withdraws the transfer is ignored on both halves.

**D2 — the rendezvous nobody is taught.** `RdvRosterExtension` (joytoys) declares
`GetActionPromptFragment(ctx)`. The base class declares `GetActionAddition(ctx)`. The names
differ because the provider path and the extension path chose different ones for the same
concept, so the method overrides nothing and the fragment is never emitted. The prefix
`[ACTION:TRICK:` *is* claimed correctly, so the command would work — but the model is never
told it exists. For roster contacts joytoys does not declare, which is the roster's whole
purpose, the feature is inert. The header of `api/AiNpcExtension.reds` describes this exact
trap; it happened anyway, one file away.

**D3 — the silent cap.** A transfer refused by the conversation cap, or carrying an
unparseable amount (`[ACTION:GIVE_EDDIES:1 500]`), is stripped from the text and pays nothing.
`AiNpcEconomySystem` writes a log line and that is all. The character promised the money, the
player received none, and the model is never told — so the next reply carries on as though it
had worked. `AiNpcActionResult.note`, the channel built for exactly this, is unreachable from
the built-in path because the built-in path does not produce an `AiNpcActionResult`. This
also breaks the user's standing design rule that a change of state is announced by a
character.

**D4 — `CharacterIsNoLonger` retracts the wrong thing.** `api/AiNpcClient.reds:417` ignores
its `contactId` and calls `AiNpcUnregisterWorldKnowledge(modId, subject)`. There is no
unregister for character additions at all. Retracting a facet of one character therefore
deletes a *global* world-knowledge entry that happens to share the subject, and leaves the
facet in place. Not an action defect — same family, found on the way, recorded so it is not
lost.

Also stale, and free to correct in this pass: `api/AiNpcExtension.reds:189,211` and
`api/AiNpcClient.reds:257` still describe the transfer tag as `[ACTION:TRANSFER_*]`. The tag
has been `[ACTION:GIVE_EDDIES:amount]` since the amount-carrying rewrite.

---

## 3. The design: one lane

One declaration. It carries what the model reads **and** what the dispatcher matches, so the
two cannot drift.

```reds
client.AddAction(pattern, prompt, handler, tag)
```

- **`pattern`** — the command, with named slots: `"[ACTION:TRICK:{place}:{hour}:{price}]"`.
  The prompt fragment is *generated* from it, so announcing a command you do not implement,
  and implementing one you do not announce, both become unwritable.
- **`prompt`** — the sentence that teaches the model *when* to emit it. Not optional in
  practice: a command with no trigger is one the model fires at random or never.
- **`handler`** — an object (see §5). No closures exist in this language.
- **`tag`** — who may use it (see §4). **Required. No default.**

The mod id comes from the client, the verb from the pattern, so the full identity
`taxi_mod:CALL_DELAMAIN` is derived. `GetSubject()` disappears.

The lightest possible consumer is a mod with no characters at all:

```reds
let client = AiNpcOpenClient("taxi_mod");
client.AddAction("[ACTION:CALL_DELAMAIN]",
                 "You call a Delamain for V when they need one and you are placed to do it.",
                 new DelamainHandler(), "ainpc:contact");
```

## 4. Scope: flat tags

**The default scope is nobody.** An omitted or empty scope is refused at registration. The
failure mode of an omission must be *narrow*, never *wide*: a permissive default is discovered
by the player, in play, on the day the model happens to emit the tag — while a refused
registration is discovered by the author, immediately.

Measured, so the default serves the common case and not the rare one: the tree today holds
**one** global action (the transfer) against **eight** scoped tag families in joytoys
(`BOOK_SESSION`, `DECLINE_SESSION`, `REQUEST_MEETING` on the joytoys providers; `TRICK`,
`REGULAR`, `UNDO_MEET` on the rendezvous lane; `MARRY_ME` appears only in tests). No cast
sheet declares an action yet.

### Tags are flat, and a character carries a set

No hierarchy, no wildcard. The colon in `joytoy:client` is a **naming convention** that keeps
mods off each other's names — the matcher never splits it and compares whole strings.

A shallow hierarchy is already expressible as a set: a VIP carries `joytoy:client` *and*
`joytoy:vip`. That is what `joytoy:client:*` would have bought, without a special case in the
matcher.

`ainpc:*`-style wildcards are refused, for four reasons worth keeping written down:

1. they reopen the universal-reach door under a spelling that does not read as "everyone";
2. *creating* a tag would retroactively enrol it in rules written before it existed — action
   at a distance, by a third party;
3. `ainpc:*` would silently widen every time the core adds a tag;
4. it re-introduces the boundary trap `AiNpcTagHasClaimedPrefix` already documents, where
   `[ACTION:MEET:` would claim `[ACTION:UNDO_MEET:`.

Flat matching is a subset of hierarchical matching, so a wildcard can be added later without
breaking a single existing tag, on the day a real case demands it.

### Two tags are implicit, and ai_npc owns them

Granted by ai_npc when a contact becomes drivable. **Not written by the mod, not omittable,
not removable.** The mod's list is purely additive.

| tag | meaning |
|---|---|
| `ainpc:contact` | every drivable contact. This is how "everyone" is spelled; there is no `"*"`. |
| `contact:<id>` | that one contact. This is how "attached to a character" is spelled. |

So an anonymous joytoys client carries `ainpc:contact`, `contact:anon_1234567` and
`joytoy:client`. A taxi mod targeting `ainpc:contact` reaches it, and neither mod knows the
other exists.

**`ainpc:` is reserved.** A third-party mod may neither declare nor assign a tag beginning
with it. Refused at registration, named in the report.

> **A tag is never omitted in order to remove reach.**

If omission could remove reach, then every tag the core adds later becomes something all
modders must remember to write, and forgetting it would silently break *other mods'* actions.
Removal has its own lever, below.

### The two levers do one thing each

| | does | decided by |
|---|---|---|
| **tag** | adds reach | whoever assigns the tag |
| **suppression** | removes one action | the declarer of the character |

Tags never remove, suppression never adds. That is what lets a behaviour be read without
knowing which mods are installed: reach accumulates, refusals are in the report.

## 5. Suppression

```reds
client.SuppressAction("[ACTION:CALL_DELAMAIN]", contactIds)
```

One-way, as `AllowsGenericTransfer` was: nobody can grant back what another mod removed. This
is the existing merge doctrine of `api/AiNpcExtension.reds` — *concatenation* for text,
*veto* for permissions, *exclusive turn* for the reply — applied to a case it already covered.
A global action is a permission granted to a character; therefore it is visible and
revocable, and the character's declarer has the last word.

**Character sheets need this as data.** A character declared by a `characters.*.json` sheet
has no code, and that is the commonest way a third party adds a character. Without a
declarative form, half the world's characters cannot refuse a global action:

```json
"suppressActions": ["[ACTION:CALL_DELAMAIN]"]
```

`allowsGenericTransfer` becomes one line of that list and stops being a field named after one
concrete command.

## 6. The handler

```reds
public class AiNpcActionHandler extends IScriptable {

    // Required. `params` are the slot values, in pattern order, already split and
    // arity-checked. They are raw strings written by a language model: validate the meaning,
    // the shape is all the dispatcher bought you.
    //
    // Must be idempotent: the model repeats tags, and a resend after a network error replays
    // the whole reply.
    public func OnAction(ctx: ref<AiNpcContactContext>, params: array<String>)
            -> ref<AiNpcActionResult>;

    // Optional. Whether the command is offered right now. Default true.
    public func IsOffered(ctx: ref<AiNpcContactContext>) -> Bool;

    // Optional. A fragment computed from game state, when a fixed sentence will not do —
    // the rendezvous lane generates a table of free slots. Default: the string given to
    // AddAction.
    public func GetPrompt(ctx: ref<AiNpcContactContext>) -> String;
}
```

`AiNpcContactContext` gains one field: `tags`, the contact's tag set, built once for the
message. The handler needs it and it is already computed.

> **A tag says what a character IS — declared, changed when somebody decides.**
> **`IsOffered` says what is true NOW — computed, asked every message.**

The line is *declared versus computed*, not immutable versus mutable: a tag can be added and
removed at runtime. `joytoy:client` is a tag. "The diary is full", "V is romanced", "there is
a slot free tonight" are offers. Without this rule someone will encode state in a tag and
refresh it by hand, badly, and there will be two state machines answering one question at
different rates.

An action's fragment enters the prompt of every contact it covers, on every message. A global
action therefore taxes every conversation in the game: keep the fragment to two lines, and
gate it with `IsOffered`, which removes the cost as well as the mistake.

## 7. Dispatch

### Arbitration

- **`contact:<id>` beats a category tag.** Direct attachment is the most specific and the rule
  is deterministic. "Judy sends money differently" becomes one registration.
- **Two claims at the same level collide.** Reported in `config-report.json`, first by full id
  wins — the existing rule.

The previous shape of this plan reserved a rank for the built-ins so a provider could never
shadow the transfer. That guarantee is dropped deliberately: a provider can already mint
eddies under a tag name of its own, and joytoys does, so the rule protected nothing except the
*name*, at the cost of making "this character handles money differently" a two-step dance.

### Offer governs the announcement; the claim governs the strip

Between building the prompt and reading the reply there is a network round trip. `IsOffered`
can flip in between — the player edits a config file, the last slot fills. The command was
legitimately announced and legitimately emitted.

> A claim that no longer offers a command still **owns** its tag: the tag reaches the handler,
> is refused, and is stripped from the message.

Without this, a bracket leaks into the player's chat bubble every time a state flips during a
round trip — a case nobody reproduces on purpose because it needs the right quarter second.
The refusal carries **no note**: the character has no way of knowing that a config file
changed, and a note would only make it invent an explanation. That is already the rendezvous
lane's doctrine, generalised.

### Three outcomes for a bracket in a reply

| the tag's head is | outcome |
|---|---|
| claimed, arity correct | dispatched to the handler; stripped whatever it answers |
| claimed, arity wrong | sent to the repair pass; if repair cannot run, stripped and refused |
| claimed by nobody | **left in the text** |

The last row is deliberate and is today's behaviour: the load-time report already names
unclaimed tags, and stripping them here would hide the report. The middle row is new and is
strictly better than today, where a prefix claim swallowed a malformed tag and left the
handler to cope. Net effect: **a tag whose command exists never reaches the player.**

### The note comes back to the character

`AiNpcActionResult.note` is seeded to the contact's pending context under the claimant's full
id — `AiNpcExtensionRegistry.reds` already does this correctly and the reason is written
there: seeded by the dispatcher, which knows the author, because two refusals in one reply
otherwise wrote to the same key. Keep that. The built-in transfer joins it, which closes D3.

The observer broadcast (`AiNpcActionEvent`, `OnActionApplied`) is unchanged: read-only, no
return value collected, ordering-free.

## 8. The pattern grammar

**Shape.** Begins `[ACTION:`, ends `]`, contains no space. At least one segment after `ACTION`:
the verb. Slots are written `{name}` and each occupies one whole colon-separated segment. A
slot may not sit in the verb position. A pattern with no slot is an exact tag.

**The head** is everything up to the first slot — `[ACTION:TRICK:` — and it is what claims.
For a slotless pattern the head is the whole tag and matching is string equality.

**Arity** is the slot count. Matching a live tag: head match, split the remainder on `:`, drop
the trailing `]`, require exactly `arity` segments, none of them empty.

A value containing `:` cannot be carried. Document it; nothing in either repo needs one.

**Refused at registration**, each with a named reason in the report: malformed shape; a slot
in the verb position; an empty or missing scope tag; a scope tag in the reserved `ainpc:`
namespace from a third-party mod; a head already claimed at the same level.

`AiNpcActionTagIsReserved` disappears: a sheet claiming the transfer head is now an ordinary
collision against `ai_npc:GIVE_EDDIES`, reported by the reporter that already exists.

## 9. What disappears

Every one of these is a hard-coded condition named after one concrete command:

| gone | where it lives today |
|---|---|
| `AiNpcParsedActions`, `AiNpcParseActions`, `AiNpcStripTransfers` | `AiNpcActions.reds` — the parallel parse pass |
| `AiNpcIsBuiltinActionTag` | the predicate carving the transfer out of the dispatch |
| the `if parsed.requestedEddies > 0 { … AllowsGenericTransfer … }` block | `AiNpcHttp.reds:466-480` |
| `AiNpcActionTagIsReserved` | `AiNpcDataAction.reds:78` |
| `AllowsGenericTransfer` | `AiNpcContactProvider.reds:235`, `AiNpcDefProvider.reds:122`, `api/AiNpcExtension.reds:217`, `AiNpcExtensionRegistry.reds:450` |
| `noGenericTransfer` | `AiNpcContactProvider.reds:59` |
| the `<money_transfer>` literal and its suppression branch | `AiNpcPromptSections.reds:273-311` |
| `GetActionPromptFragment` / `GetActionTags` / `GetActionTagPrefixes` / `TryApplyAction`, both copies | provider and extension |

`AiNpcFindUnknownActionTags` becomes `AiNpcFindActionTags`: "known" stops being a coded
predicate and becomes "the claim table contains it".

**One decision to take, and it is a real one.** `AiNpcGetWorldMechanics` currently conflates
two things: prose about how the world works (the `worldMechanics` override from
`prompts.json` and from a contact) and the eddie command's own text. That is why suppressing
the transfer also suppresses the override. Recommended split: `worldMechanics` becomes a
section preamble that is never suppressed, and only the `<money_transfer>` text moves into the
transfer handler. A contact that both overrides and opts out currently keeps an override
advertising a command that will be refused — precisely the defect class this pass removes.

## 10. File layout

| file | role |
|---|---|
| `AiNpcActionTag.reds` | tag shape, extraction, head matching — pure |
| `AiNpcActionPattern.reds` | pattern parse, arity, slot extraction — pure |
| `AiNpcActionClaim.reds` | the claim table: types, build for a contact, lookup |
| `AiNpcActionDispatch.reds` | apply a reply's tags, clean the text, seed the notes |
| `AiNpcTransferHandler.reds` | the built-in, through the public door: amount, cap, fragment |
| `AiNpcEconomy.reds` | unchanged — the ledger stays the ledger |

`AiNpcActions.reds` is split and removed. The action pass leaves
`AiNpcHttp.HandleMessage`, which today performs actions, repair, delivery, history, tickets
and the fact bridge in one method.

`AiNpcDataAction.reds` keeps its rule and loses its plumbing: a sheet's action registers on
the same lane with a handler that writes a quest fact, and the namespace check
(`ainpc_` only, at load **and** at apply) stays exactly as it is. Data may say what a
character announces; it may not decide what the game does about it.

## 11. Performance

Today the dispatch is `O(tags × extensions)` with virtual calls **inside** the loop: for each
candidate tag, `GetActionTags` and `GetActionTagPrefixes` are called on every covering
extension, each allocating an array.

After: the claim table is built once per reply — one pass over covering claims — and each tag
is a lookup. `2·E` calls instead of `2·T·E`, the rest being string comparisons over a
single-digit array. The contact's tag set is built once per message and shared by the prompt
build and the dispatch. Cost grows with the number of tags the current contact carries, not
with the number of mods installed.

Static fragments are constant per contact and need not be rebuilt per message.

## 12. Migration

**The built-in.** One registration, no privilege:

```reds
client.AddAction("[ACTION:GIVE_EDDIES:{amount}]", <the money_transfer text>,
                 new AiNpcTransferHandler(), "ainpc:contact");
```

The handler parses the amount, clamps one tag to `AiNpcTransferCap()`, calls
`AiNpcEconomySystem.TransferMoneyToPlayer`, and **returns a note** when the amount was clamped
or the conversation cap refused it. That note is the whole of D3.

**Character sheets.** `AiNpcDefProvider`'s four action methods go; the sheet loader registers
each declared action with scope `contact:<id>` and a fact-writing handler.

**joytoys**, per family. Read each site before moving it; this table is the mapping rule, not
a substitute for reading.

| family | today | scope after |
|---|---|---|
| `BOOK_SESSION`, `DECLINE_SESSION`, `REQUEST_MEETING` | `JoytoysActions.reds`, gated by `JoytoysVipActionsEnabled()` | `contact:<id>` per VIP, or a `joytoy:vip` tag |
| `TRICK`, `REGULAR`, `UNDO_MEET` | `RdvTag.reds`, prefix `[ACTION:TRICK:`, roster-gated | `joytoy:client`; the roster file becomes a tag-assignment file |
| `MARRY_ME` | tests only | confirm whether it is retired before carrying it over |
| the five `AllowsGenericTransfer() = false` | `JoytoysProvider`, `Juli`, `Mira`, `Fingers`, `AnonContact` | `SuppressAction("[ACTION:GIVE_EDDIES:", …)` at declaration |

The anonymous contact is the case that decided the design: minted at runtime by
`BridgeLlm.reds:574` as `anon_<seed>`, it exists in no list anybody could write. It carries
`joytoy:client` at birth and the rendezvous command follows it, with no registration to repeat
and nothing to clean up when it goes.

**The roster disappears as a mechanism.** It stops granting rights and starts assigning tags.

## 13. The API break

`TryApplyAction` changes from `Bool` to `ref<AiNpcActionResult>` and both `AllowsGenericTransfer`
methods are removed. This breaks joytoys' five providers and its one extension — all in this
user's own repositories.

**Break the signature; do not merely remove the method.** A removed virtual method leaves the
consumer's override compiling and doing nothing. That is D2, exactly, and it cost a feature
silently for as long as it has existed.

The API is not published: the repository is on its way to 1.0.0. The break is free now and
expensive later.

**Do not move `AiNpcApiVersion()`.** It is deliberately held at 1 until the first release, and
`api/AiNpcApi.reds` says why: the number exists for a consumer holding an older ai_npc against
a newer contract at an *unchanged signature*. A changed signature raises `UNRESOLVED_FN` and
fails the compilation of the whole game — which is the mechanism this break wants, and one no
runtime number can improve on. Record the break in `docs/API.md` instead.

## 14. The load-time report

`config-report.json` gains, and each line has a defect behind it:

- every action targeting `ainpc:contact`, **with the mod that registered it** — a global grant
  is a permission the player should be able to read;
- every action whose scope tag no character carries — catches `joytoy:client` against
  `joytoys:client`, which is silent otherwise. The converse (a tag carried but unused) is
  **not** an error: a tag may exist for a mod not yet installed;
- every head claimed twice at the same level, with the winner named;
- every suppression, with who removed what from whom;
- every registration refused by §8, with its reason.

## 15. Acceptance checks

Each can come back false.

1. `grep -c "GIVE_EDDIES" src/r6/scripts/ai_npc/` outside `AiNpcTransferHandler.reds` and the
   tests returns **0**. No other file names the built-in command.
2. A test registers an extension that suppresses the transfer for one contact, and asserts on
   **both** halves: the fragment is absent from that contact's prompt, and a transfer tag in a
   reply pays nothing. Fails today on both (D1).
3. A test asserts that a handler declaring a pattern has its fragment in the prompt of a
   covering contact — i.e. that announcement and claim come from one object (D2).
4. A test asserts that a transfer clamped by the conversation cap produces a non-empty note on
   the contact's pending context (D3).
5. A test asserts an anonymous-style contact minted at runtime, carrying one category tag,
   receives an action registered for `ainpc:contact` **and** one registered for its category,
   and does not receive one registered for a category it does not carry.
6. A test asserts a head-matching tag with the wrong arity does not reach the player: repair
   claimed it, or it was stripped.
7. A registration with an empty scope is refused, and the refusal is in the report.
8. A third-party registration of a tag beginning `ainpc:` is refused.
9. `tools/test.ps1` green, including the release-shape compile and the C++ suite.
10. joytoys compiles against the new API and its eight families still dispatch.

## 16. What must not be touched

- **`AiNpcEconomySystem`.** The conversation cap and its non-persistence are correct and are
  not part of this. Only its caller changes.
- **The `ainpc_` namespace rule** for sheet-declared actions, checked at load *and* at apply.
- **The observer broadcast.** `AiNpcActionEvent` / `OnActionApplied` keep their shape.
- **The repair pass's economics.** It stays one request, spent once, refused when the day's
  budget is met or the credentials have stopped working.
- **The unclaimed-tag rule**: a bracket whose head nobody claims stays in the text, because the
  report names it and hiding it would hide the report.
- **The rest of `AiNpcCharacterExtension`** — intent, rule contributions, live context,
  scripted reply, floor. Different concerns, different merge rules. Only the action methods
  move.

---

## Appendix: the four defects, as work items

Independent of everything above. If the refactor is deferred, these are still worth closing.

| | where | shape of the correction |
|---|---|---|
| D1 | `AiNpcPromptSections.reds:290`, `AiNpcHttp.reds:473` | consult `AiNpcExtensionAllowsGenericTransfer` at both sites |
| D2 | `RdvRosterExtension.reds:58` (joytoys) | the file is gone; the roster assigns a tag and the commands are declared once, in `RdvActionLane.reds` |
| D3 | `AiNpcEconomy.reds`, `AiNpcHttp.reds:470-480` | return a result with a note instead of logging |
| D4 | `api/AiNpcClient.reds:417` | write the missing `AiNpcUnregisterCharacterAddition` and call it |

All four are closed. D1 and D3 vanished with the two-column shape, D2 with the extension that
carried it, and D4 was fixed at its cause: `AiNpcWorldFactId` now includes the contact, so one
mod can say the same thing about two people — which it could not before, silently.

A fifth turned up while wiring the repair pass and is closed with them: `TryRepairActions` was
handed `AiNpcGetWorldMechanics`, which by then described the eddie transfer and nothing else. A
fumbled rendezvous command was therefore judged against a rulebook that did not contain it. It
now gets the contact's real command block, rendered from the same table the reply was dispatched
against.

Left for the joytoys text pass, not a defect: the three VIP command sentences still say "start
your reply with [ACTION:BOOK_SESSION]" inside a line the lane already prefixes with the pattern,
so the tag reads twice. Rewriting them is a translation change and belongs to that mod's own
string pass.
