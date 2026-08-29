# Giving a contact an AI voice, and adding to one that has

ai_npc drives a texting conversation for a fixed cast of vanilla characters. This document is
how another mod joins in: how it adds a contact ai_npc has never heard of, and how it adds
something to a character it does not own.

Those are two different jobs, and telling them apart is most of the design.

| | You DECLARE a contact | You EXTEND a contact |
|---|---|---|
| Who this person is — bio, relationship, way of speaking | yours to say | not yours to say |
| Commands the model may emit | yes | yes |
| A line of live context per message | yes | yes |
| How many mods at once, per contact | **one** | **any number** |
| What happens on a clash | refused, first claim wins | there is no clash |

A vanilla character — Panam, Rogue, Judy — is already declared. **You extend her.** Declaring
her yourself would mean taking her over, and two mods cannot both be right about who she is.
Redefining a vanilla character is the player's call, through `characters.builtin.json`.

Declaring comes in two flavours, and the question that picks between them is whether anything
about your contact depends on live game state:

| | JSON file | Script provider |
|---|---|---|
| Compile-time dependency on ai_npc | **none** | yes |
| Works when ai_npc is not installed | file is ignored | yes, behind `@if` — see below |
| Static text (bio, relationship) | yes | yes |
| Text computed from game state | only through fixed variants | yes |
| Register / unregister mid-session | no | yes |

Start with JSON. Move to a provider only when you hit its ceiling.

If what you want is for a character ai_npc already drives to react to something that happened
in **your quest**, that needs none of the three — see "Making a character react to your quest".

---

## Before any of it: the model that will answer you

Nothing described in this document can be observed without a model replying. A contact you
declare, a rubric you compose, an action you emit: all of it becomes visible in a reply and
nowhere else. So set the answering lane up before you write anything, and expect to spend real
messages — an add-on is written by reading replies, not by reading code.

**Use OpenRouter, and put a few dollars on it.** An account at `openrouter.ai`, a key at
`openrouter.ai/keys`, pasted in game: CET overlay, tab AI NPC, tab Setup, then Test. An
afternoon of iterating on one contact is measured in cents; `docs/MODEL_COSTS.md` has the
per-model numbers. It is also the only lane that lets you **compare models**, which is what you
will want the first time a reply is not what you expected: the same conversation answered by
two models tells you whether your bio is wrong or the model is weak, and nothing else does.

**The CLI lanes are a convenience, not a capability.** Mod Settings and the Setup tab also
offer `Claude CLI` and `Codex CLI`, which drive a coding agent already signed in on your
machine, so no message is billed. They exist for exactly the job this document describes. What
each one costs you is stated on its own line in the Setup tab and read in full in
`docs/DISTRIBUTION.md`: those plans are sold for ordinary individual use of a coding agent, and
the provider may limit or suspend an account without warning. That is your account and your
call — this mod states the terms and does not make the decision for you. Two practical limits
before you pick one: a subscription gives you one model, so no comparison; and the Codex lane
has never been run in game, which is why the installer does not offer it.

**When a reply is not what you wrote.** Read `config-report.json` first: every refusal is
listed there with its reason, and a rule that was dropped never reached the model at all. Then
the Setup tab, which says which provider is selected, what it is pointed at and what is
missing. Only then suspect the model.

**Iterating without launching the game** is possible for text that lives inside ai_npc itself —
`tools/prompt` extracts the real blocks from the `.reds` sources and rebuilds byte-identical
prompts offline. It does **not** see your JSON file or your provider: those are read during a
session, so your own contact is tested in game like any other.

---

## What you may call

Everything another mod is allowed to call lives in one folder,
`r6/scripts/ai_npc/api/`. That folder is the boundary: if it is not in there, it is an
internal that will move without warning.

**One rule decides which shape a call has.**

```
free function       reading, or anything with no author
method on a client  writing
```

If you needed the client, you changed something. That is the whole of it.

### The client

Every write carries who is writing. You state your mod's name once, when you open the handle,
and never again:

```reds
AiNpcOpenClient("your_mod_id")                // -> ref<AiNpcClient>, never null
```

It is idempotent and holds no state, so call it wherever you need it rather than storing it —
which also means your mod's name is written in exactly one place in your whole codebase, and
a name mistyped once is a contribution nobody can find, budget or withdraw.

```reds
// Statements
client.CharacterKnows(id, text, opt until)    // -> Int32, a ticket
client.CharacterWantsToSay(id, reason, opt intent, opt policy)  // -> Int32, a ticket
client.CancelWantsToSay(ticket)               // -> Bool, takes a waiting one back
client.CharacterWrote(id, text)               // -> Int32, see AiNpcWriteOk() and friends
client.PlayerWrote(id, text)                  // -> Int32, same codes

// The thread
client.OpenConversation(id)                   // -> Int32, see AiNpcOpenOk() and friends
client.ForgetConversation(id)                 // -> Bool, refused for a vanilla contact
client.TakeFloor(id, opt maxSeconds)          // -> Bool
client.ReleaseFloor(id)                       // -> Bool

// The cast
client.RegisterCharacter(provider)            // -> Bool, declare a contact of yours
client.UnregisterCharacter(id)                // -> Bool
client.RegisterExtension(extension)           // -> Bool, add to a contact you do not own
client.UnregisterExtension(subject)           // -> Bool
client.RegisterListener(listener)             // -> Bool
client.UnregisterListener(subject)            // -> Bool
client.UnregisterAll()                        // -> Void, withdraw everything in one call

// The world -- a fact about Night City rather than about anyone in it.
client.RegisterWorldKnowledge(subject, text)  // -> Bool, told to every character
client.CharacterAlsoIs(id, subject, text)    // -> Bool, joined to the end of one bio
client.UnregisterWorldKnowledge(subject)      // -> Bool

// Accounting and files
client.ContextBudgetLeft(id)                  // -> Int32, characters
client.FileName(name)                         // -> String, "mod.<yourid>.<name>.json"
```

### Free functions

```reds
// Version and readiness
AiNpcApiVersion()                             // -> Int32
AiNpcIsReady()                                // -> Bool, false is normal at load time
AiNpcWhenReady(modId, handler)                // -> Void, runs now if it already is

// Vocabularies -- functions, never enums; see below for why
AiNpcUntilNextReply() / AiNpcUntilForever()
AiNpcTicketUnknown() / Pending() / Done() / Failed() / Cancelled() / Refused()
AiNpcSayNow() / AiNpcSayWithin(seconds)       // the policy of CharacterWantsToSay
AiNpcOpenOk() / AlreadyThere() / NotDriven() / PhoneUnavailable() / FloorHeld()
AiNpcWriteOk() / FloorHeld() / NoSession() / Empty()
AiNpcActionDone(opt note) / AiNpcActionRefused(opt note)
AiNpcSilentAnswer()

// Reading
AiNpcTicketState(ticket) / AiNpcTicketReason(ticket)
AiNpcReadConversation(id)                     // -> array<ref<AiNpcMessage>>, a snapshot
AiNpcPlayerHasWritten(id)                     // -> Bool
AiNpcDrivesCharacter(id)                      // -> Bool
AiNpcListBuiltInCharacters()                  // -> array<String>, ai_npc's own eleven
AiNpcListDrivableCharacters()                 // -> array<String>, everything reachable now
AiNpcCharacterInOpenChat()                    // -> ref<AiNpcContactProvider> or null
AiNpcFloorHeldBy(id)                          // -> String, "" when free
AiNpcExplainCharacter(id)                     // -> String, read this when something is wrong

// Environment
AiNpcSharedStorage()                          // -> ref<FileSystemStorage>, ALREADY OPEN
AiNpcChosenLanguage()                         // -> String, "fr" / "en" / ...
AiNpcSpeaksOfPlayerAsMale()                   // -> Bool
AiNpcAllowsExplicitContent()                  // -> Bool, the player's consent, read-only
AiNpcMayWriteFirst()                          // -> Bool, may a character write unprompted
AiNpcChosenTone()                             // -> String, "normal" / "nsfw" / "nsfw_hard"
AiNpcCharacterIsRomanced(id)                  // -> Bool
AiNpcExpand(text) / AiNpcExpandFor(id, text)  // -> String
AiNpcContactKey(id)                           // -> Int32
```

Plus the classes you subclass: `AiNpcContactProvider` to declare, `AiNpcCharacterExtension`
to extend, `AiNpcConversationListener` to watch, `AiNpcReadyHandler` to wait, and
`AiNpcPromptOverrides` to replace a whole prompt section.

### Two conventions worth knowing before you read further

**Names answer a question, and the shape tells you which.**

| Shape | Means | Examples |
|---|---|---|
| subject + tense | a statement about the world | `CharacterKnows`, `PlayerWrote` |
| verb first | an order to ai_npc | `OpenConversation`, `AiNpcOpenClient` |
| question | the character answering about itself | `IsAvailable()`, `GetLiveContext()` |

Inside a statement, the **tense** tells you what happens: *past* means it already happened and
you are recording it — nothing is sent, nothing is displayed unless the name says so; *present*
means it is a state you are setting, and it holds until the bound you give.

**Vocabularies are functions, not enums.** `AiNpcUntilForever()` rather than an enum member,
because a public enum forces a *guarded declaration* in a mod that takes ai_npc optionally,
where a function only forces a guarded wrapper. `Int32` crosses the `@if` boundary; a
vocabulary does not.

The price of that is no type to keep two vocabularies apart: comparing an outcome against the
wrong constant compiles, warns nothing, and *matches* if the two share a number. So the ones
you compare occupy **disjoint ranges** — ticket states `0–3`, open outcomes `10–14`, write
outcomes `20–24` — and a confusion between them matches nothing at all instead of matching the
wrong thing. The bounds (`AiNpcUntilNextReply`, `AiNpcUntilForever`) stay at `0` and `1`: they
are only ever passed, never compared, and `0` has to be the `opt` default. Pass anything else
as a bound and ai_npc treats it as `NextReply` and says so in the log.

**The API is additive only once it ships.** `@if` tests `ModuleExists` and nothing else — there
is no way to compile against a version. A mod built for a newer API running beside an older one
raises `UNRESOLVED_FN`, and that fails the compilation of *the whole game*, not of the offending
mod. So nothing is removed or given a different signature after release; new parameters arrive
as `opt`.

---

## The one hard requirement: `contactId`

Everything hangs off one string. `contactId` **must equal the `contactId` your mod puts on
the `ContactData` it injects into the phone** — that field is the only thing linking a
widget in the contact list to a conversation on disk, and ai_npc reads it in
`PhoneDialerLogicController.RefreshInputHints`.

It is also the key every conversation journal entry is tagged with, so it must be stable
across sessions. A `contactId` that changes between launches silently starts a new, empty
history every time.

ai_npc does not put contacts in the phone. Getting yours listed there is a separate
problem, solved by [Phone Extension Framework](https://www.nexusmods.com/cyberpunk2077/mods/24949)
or by whatever your mod already does. ai_npc only gives a voice to a contact that is
already reachable.

---

## Way 1 — a JSON file

Drop a file in `<game>\r6\storages\AiNpc\`. Nothing else is required, and nothing links
your mod to ai_npc: without ai_npc installed the file is simply never read.

### File names and load order

Files are read in a deterministic order, and later files override earlier ones field by
field:

1. `characters.builtin.json` — overrides for the characters ai_npc ships with
2. `characters.<anything>.json` — alphabetically; use `characters.<yourmod>.json`
3. `characters.user.json` — always last, so a hand edit beats any mod

`characters.example.json` is rewritten at every launch and never read. It documents the
current schema; copy it, do not edit it.

### Schema

```json
{
    "version": 1,
    "characters": [
        {
            "contactId": "MyModContact01",
            "displayName": "Nadia",
            "bio": "You're Nadia, a fixer working out of Kabuki...",
            "relationship": "You met V once, on a job that went sideways. You remember {them}.",
            "romance": "V is your {partner} now, not just a friend.",
            "speechStyle": "{register} Clipped and businesslike. Never uses slang.",
            "intent": "You want V to take the Kabuki job, and you steer every conversation back to it.",
            "prompts": {
                "interactions": { "REACH": "Rewrites one rubric of <interactions> for Nadia only." },
                "playerDescription": "Replaces the <player> section: what Nadia knows of V."
            },
            "romanceable": false,
            "romanced": false,
            "suppressActions": ["[ACTION:GIVE_EDDIES:"],
            "seedFacts": ["V once did a job for her brother and never got paid."],
            "allowsMemory": true,
            "enabled": true,
            "variants": [
                { "when": "postHeist", "bio": "..." }
            ],
            "questContexts": {
                "riders_on_the_storm": "The Wraiths took Saul, and that is where you are going in after him. INSTRUCTION: ..."
            },
            "questIntents": {
                "riders_on_the_storm": "You want V beside you when you take the camp back."
            },
            "actions": [
                {
                    "tag": "[ACTION:BOOK]",
                    "prompt": "Emit this when V agrees to the job.",
                    "fact": "ainpc_nadia_booked",
                    "value": 1
                }
            ]
        }
    ]
}
```

Every key except `contactId` is optional. **An absent or empty key means "no opinion"**:
ai_npc keeps its built-in text for a vanilla character, or omits the section entirely for
a new one. That is what makes a partially broken file cost only the keys it got wrong.

| Key | Effect |
|---|---|
| `contactId` | required; must match the phone's `contactId`, no spaces |
| `displayName` | name shown in the chat header and used in the transcript |
| `bio` | lands in `<character>` — who this person is, and how they text |
| `relationship` | lands in `<relationship>` — how they see V. Injected **whether or not** there is a romance, so anything only true in one of the two states does not belong here |
| `romance` | **additive** — what the romance *changes*, added to `<now>` only while V has romanced this contact. `relationship` still applies, so do not restate it. A romanceable contact with no `romance` reads the same romanced and not |
| `speechStyle` | **additive** — one or two sentences on how this character *speaks*: register, form of address, verbal tics. Appended to the rule block, so the built-in rules still apply. See below |
| `prompts` | **replacing** — drops a whole section of the prompt for this contact. Rarely needed; see below |
| `romanceable` | declares the contact can be romanced at all. A fixed property of the character, declared and never inferred from `romanceFact` — that one says whether it *happened*, which is the playthrough's answer, not the character's |
| `romanced` | romance state for a **new** contact; ignored for a vanilla one, whose romance is read from the save (`sq027_panam_lover` and friends) |
| `suppressActions` | commands this character refuses, named by the literal run before the first slot — `["[ACTION:GIVE_EDDIES:"]` turns off the built-in eddie transfer. Removes them from the prompt entirely rather than advertising one that would be refused. One-way: nothing grants them back |
| `tags` | what this character IS — `["nomad"]`. A command another mod scopes to one of these reaches this character without either side having heard of the other. Tags only ADD; use `suppressActions` to take a command away |
| `intent` | **what this contact wants from V**, one or two sentences, second person. `bio` says who they are and `relationship` how they see V; neither says what they are *after*, and a model given no intention invents a different one every message. About wanting, not knowing: *“You want V to take the Kabuki job”* is an intent, *“You are worried about V”* is a mood and belongs in `liveContext` |
| `questIntents` | what this contact wants **while V is tracking a given quest**, keyed like `questContexts`. It replaces `intent` for as long as that quest is tracked; an absent entry leaves the durable one standing, never blanks it |
| `actions` | commands this contact may emit, and the quest fact each one sets. See *Actions from a file* below — the short version is that a file may only write facts starting with `ainpc_` |
| `seedFacts` | what this contact already knows about V before the first message. One line each; folded into its memory at the first compaction and aged like anything else it remembers |
| `allowsMemory` | `false` when the contact should not accumulate a relationship at all — an automated number, a bot, a dead drop. Its conversation is then trimmed rather than remembered. See [MEMORY.md](MEMORY.md) |
| `enabled` | `false` skips the entry entirely |
| `variants` | conditional overrides, below |
| `questContexts` | what this contact says while V is tracking a given quest, keyed by the canonical quest name ai_npc logs when it meets one it has no entry for. Write the account only, in the second person: ai_npc adds the quest title and what V is doing right now around it. Declaring any replaces the shipped set for that character |
| `comment` | ignored; for your own notes |

Any key starting with `_` is ignored everywhere, so `_note` and friends are free to use
as comments — JSON has none of its own.

### Speech style, and why it is not just more bio

Every prompt section resolves the same way, in three levels:

```
this contact  ->  prompts.json (global)  ->  ai_npc's built-in text
```

`speechStyle` is the level most contacts need and the only one that is **additive**: it is
appended to the rule block, next to the language rule, rather than replacing anything.

That placement is the whole point. A form of address stated once in `relationship` loses
against a `MANDATORY` line in the rule block, every time — a contact described as
addressing V formally still answered with slang, because the French language rule said
characters use *tu*. Style stated here lands in the rule block itself, at the same weight
as the rule it is meant to bend. The T-V distinction is now a **default** speech style per
language, not part of the language rule, so a character can say otherwise.

Keep it to one or two sentences, and keep it about *speech*. Facts go in `bio`, current
mood in `liveContext`.

It is also stated a second time, at the end of the prompt inside `<language>` — repetition
is what makes a register survive a long transcript. That second copy is dropped above 400
characters: a provider may return a whole dossier from `GetSpeechStyle` (ai_npc_joytoys
puts an unknown number's objective and knowledge there), and a paragraph that long already
dominates by mass, so copying it only doubles the cost.

### Replacing a whole section

When bending is not enough, `prompts` drops a section outright, for this contact only:

```json
"prompts": {
    "rules": { "YOU": "...", "SETTING": "...", "YOUR OWN RUBRIC": "..." },
    "interactions": { "REACH": "...", "REAL": "..." },
    "worldBackground": "...",
    "playerDescription": "...",
    "worldMechanics": "...",
    "tone": { "Normal": "...", "NSFW": "...", "NSFW_Hard": "..." },
    "language": "..."
}
```

The keys are exactly the keys of `prompts.json` — with one exception, `playerDescription`,
which has no global counterpart there because it already has one in `settings.json`, next to
the additive `appearance` key it overrides. So the global file and a per-contact override are
one vocabulary. Every key is optional and an absent key keeps resolving down
the chain — an override object is safe to fill in halfway.

### Three regimes, and the name says which

A block belongs to whoever owns what it states, and that decides how a mod reaches it:

| What the block states | Regime | Blocks | How you reach it |
|---|---|---|---|
| **the mod's policy** | **composed** by key | `<system_rules>`, `<interactions>` | `"rules"` / `"interactions"` objects, `SetRule` / `SetInteraction`, `GetRuleContributions(block, ctx)` |
| **the character** | **replaced** whole | `<character>`, `<relationship>`, `SPEECH`, `<intent>`, `<player>`, `<mechanics>` | the provider's own getters, or a JSON string |
| **the moment** | **added** to, with a budget | `<now>`, `<intent>` | `GetLiveContextAddition(ctx)`, `GetIntentAddition(ctx)` |
| **the player's consent** | **nothing** | `<explicitness>` | no lane at all — see below |

In JSON the shape says it too: **a string replaces, an object contributes.**

`<explicitness>` states what the player chose in Mod Settings. No contact override, no
`prompts.json` key, no extension: a mod rewriting it would answer a question that was put to
the player. A character who does not swear says so in its `SPEECH` rubric; a contact that is
not a person says so in rubrics of its own. The NCPD archive that answers Jackie's number
does exactly that.

### The rule block is composed, not replaced

`<system_rules>` is a list of rubrics, each owned by a key, and `rules` contributes to it by
key rather than replacing it:

- a **known key** — `YOU`, `NEVER`, `SETTING`, `SPEECH` — replaces that rubric where it
  stands, keeping its position, which is what decides how it weighs against the rest;
- an **unknown key** is a rubric of your own, appended after the mod's and before `LENGTH`.
  The NCPD archive that answers Jackie's number declares `NOT JACKIE`, `SCOPE` and
  `REGISTER` that way;
- **`FORM`, `TIME` and `LENGTH` refuse both.** They describe the chat itself — one message
  per turn, no `Name:` prefix, the time markers ai_npc writes and the model must only read,
  and a length that fits a phone bubble. A contact that won those would break the player's
  chat window, not its own characterisation. Setting one is an error in the config report,
  and the rubric is left alone.

A key is upper-cased and trimmed before anything else, so `form` is the locked `FORM` rather
than a second rubric contradicting it. Four other refusals, each reported with its reason in
`config-report.json` and in the log:

| Refused | Why |
|---|---|
| an empty text | it would delete the mod's rubric rather than replace it — say what you mean instead |
| a text holding a tag | a `</system_rules>` inside a rubric ends the block early, and whatever follows can restate a locked rule wherever it likes. A tag is a closing one or a name between angle brackets — `<3` and `->` are prose and pass |
| over 600 characters | one rubric's budget |
| past 2000 characters of contributions | the block's shared budget, spent in source order |

`<interactions>` composes the same way — `REACH`, `REAL` and a locked `PROMISES`, the one
clause whose loss the player sees: a character promising to come and getting nobody there
reads as the mod being broken. A mod that can really stage a meeting rewrites `REAL` and
inherits the rest.

**Extensions contribute too.** `AiNpcCharacterExtension.GetRuleContributions(block, ctx)` returns rubrics the
same way, and they are merged last: the contact's own first, then `prompts.json`, then every
extension in id order. The first source to name a rubric owns it — a character's words about
itself outrank a passing mod's about everybody.

### The same two checks, at every door

Text from outside the mod is a leaf of the prompt tree, and a leaf carrying a tag stops being
one. **Every** section goes through the same pair of refusals, whichever door it came in by —
a provider getter, an override, `facts.*.json`, `AiNpcSeedContext`, a registered world fact,
or an extension:

| Refused | Bound |
|---|---|
| a text holding a tag | closing tags and `<name>` shapes; `<3`, `->` and `a < b` are prose |
| a text over 4000 characters | one section's budget, refused whole rather than clamped |

A refusal is logged with the id it came from, and a refusal at load time is an error in
`config-report.json`.

### `<intent>` composes as well

`AiNpcCharacterExtension.GetIntentAddition(ctx)` appends a line to the contact's own intention —
appended, never replacing, because what a character wants is who they are and a mod that adds
a job to somebody's week does not get to overwrite it. Budgeted like `<now>`: 400 characters
a line, 1200 across every extension.

### What a contact may not know

`KnowsPlayerLifePath()` answers whether `<player>` tells this contact where V comes from.
Return `false` for a contact who met V through a profile or a clinic door: the gender and the
appearance stand, the `V is a streetkid (life path)` clause is left out. A question rather
than a text to override, so a contact that means "not this half" does not lose the player's
own appearance line by restating the block.

Nothing can drop the block, reorder it, or silently lose a rule it never mentioned. The
`guidelines` key that used to replace the whole block **is refused**, with an error at load:
move its text into `rules`, one key per rubric.

`suppressActions` removes a command from the prompt entirely rather than advertising one that
would then be refused. `<mechanics>` is unaffected: it carries prose about how the world works,
and the commands live in `<commands>` next to it — which is why suppressing the transfer no
longer takes an unrelated override down with it.

Three fields of `AiNpcPromptOverrides` exist only in script, with no JSON key, because a
global default for them would be meaningless — they describe a contact that is not a
person:

| Field | What it replaces |
|---|---|
| `speechStyle` | the SPEECH register, for a contact with no provider to implement `GetSpeechStyle`. The method wins when both are set. |

A character shipped with the mod reaches this level the same way: its sheet
(`src/r6/scripts/ai_npc/cast/`) may carry a `prompts` object. None does today. The bar is
not a character who is unusual, but a contact for whom the default rules are wrong — and a
contact that is not a person at all is usually better served by a scripted reply, below,
than by arguing a model into behaving like a machine.

### Placeholders

Configured text cannot concatenate code, so it carries placeholders. They are substituted
against V's gender -- read from the character the player created -- every time the
prompt is built:

`{they}` `{them}` `{their}` `{partner}` `{gender}` `{npc}` `{time}` `{language}`
`{vgender}` `{register}`

and the capitalised forms `{They}` `{Them}` `{Their}` `{Partner}` for the start of a
sentence.

`{vgender}` is not a word but a whole sentence -- *“V est une femme. Accorde en
conséquence...”* -- written in the reply language, and **empty in English**, which has no
agreement to make. The built-in block already emits it as its own `V` rubric, so you only
need the placeholder inside a rubric of your own that has to state it again. The gendered words above are still English-only, so non-English
configured text should prefer `{vgender}` and let the model agree by itself rather than
splicing `{partner}` into a French sentence.

`{register}` is the language's own form of address — *“Les personnages se tutoient.”* and its
equivalents, empty in English. It exists for `speechStyle`, which **replaces** that default
rather than adding to it: a character has to be able to say otherwise, and a style composed
with its own contradiction is worse than either half. So a style that only wants to describe a
register opens with `{register}` and keeps the T-V rule; one that wants to overturn it says so
and leaves the placeholder out. Every shipped sheet opens with it.

An unrecognised placeholder is **left in the text verbatim** rather than blanked, so a
typo shows up in the reply instead of quietly making the sentence wrong.

### Actions from a file

A file may teach a contact commands of its own. What it may not do is decide what one *does*:

```json
"actions": [
    {
        "tag": "[ACTION:BOOK]",
        "prompt": "Emit this when V agrees to the job.",
        "fact": "ainpc_nadia_booked",
        "value": 1
    }
]
```

The tag is advertised in `<commands>`, on the same lane every command uses, scoped to this
character alone, and **stripped from the message before the player sees it** — the sentence the
character wrote around it is what tells them. Firing it sets the fact, and that is the only
effect a file can have.

The namespace is the design, not a precaution. A tag is a request from a language model, and a
language model can be argued into emitting anything; a file that could name any fact would let
one bracket write `q101_started` and take the playthrough somewhere the quest graph never meant
to go. So a file may only write inside `ainpc_`, checked at load and again at the write.

That is not a wall a serious mod meets: wanting to move real quest state means wanting to run
code when it moves, which is *Way 2* — and a script provider has always been able to do
anything. Data stays sandboxed, script stays powerful, and the line between them is one prefix.

What the fact then *means* is whoever reads it: your own quest graph, a CET script, or a
`facts.<yourmod>.json` watch that turns it into news somebody else reacts to. ai_npc writes it
and stops there.

Each of these drops **one action** and reports why, rather than dropping the character:
a malformed tag, a tag carrying a `{slot}` (a file declares a command, not a form — data cannot
validate what a field would carry), a duplicate, a fact outside `ainpc_`, or a missing `prompt`
(a command with no trigger is one the model fires at random or never). `config-report.json` lists the commands each contact ended up with, so *“declared
three, kept two”* is visible without reading the issue list.

Three characters ship with one: Panam commits to a pickup, Rogue puts a gig on the table,
Viktor sets an appointment at the clinic.

### Variants

A variant overrides `bio`, `relationship`, `liveContext`, `speechStyle` or `intent` when a
condition holds. The first matching variant that supplies the field wins.

`when` is a **closed vocabulary**, evaluated in code:

`postHeist` `preHeist` `romanced` `notRomanced` `playerMale` `playerFemale`
`romanceFailed` `randyDead` `evelynDead` `evelynRescued` `cloudsSettled`
`leftNightCity` `johnnyRevealed` `johnnyDateDone`

`romanced` reads your `romanced` field for a contact of your own, and the game's own
romance quest facts for a vanilla one — there is no romance setting to keep in sync.

`romanceFailed` is the **third romance state**: V was there, and said no. Without it a
refused romance reads exactly like one that never started, and the character is told to
reject advances that were already made and turned down. It is evaluated **for the contact
whose sheet carries it**, which is what lets one condition name cover characters the base
game records three different ways — an explicit `sq030_failed` for Judy, a gesture
(`sq028_kerry_goes_home_alone`) for Kerry, nothing but a closed arc for River. The relevé is
in [ARC_FACTS.md](ARC_FACTS.md). It is false for a contact ai_npc has no rule for, including
one of your own: your contact's romance is whatever your `romanced` says, and there is no
third state to read.

`evelynDead`, `evelynRescued` and `cloudsSettled` are Judy's arc — what she has lived
through rather than what she is — and `leftNightCity` says she is gone. `evelynRescued`
and `leftNightCity` are evaluated per contact, like `romanceFailed`; the other two are
world facts and answer the same for everybody.

`johnnyRevealed` and `johnnyDateDone` are the two states of *Chippin' In*. The first says
Johnny took V's body for a night and introduced himself to the people who knew him, which
is the only way anyone but V learns what is in that head — in the branch where V never
lets him take the wheel, nobody ever finds out. The second says the drive-in evening
happened. Both are world facts. Order them the way Rogue's sheet does: the evening is the
later state and speaks first.

`randyDead` is not a romance state at all, and it is in the vocabulary to make that point.
The Hunt can end with River's nephew dead, which closes the romance **and** changes the man —
including for a V who could never have romanced him. An outcome folded into `romanceFailed`
would say nothing to that playthrough. Both conditions can hold at once, so order the
variants: the first one that supplies a field wins.

Data carries text, never predicates. An unknown condition is an error and the variant is
dropped — a variant that can never fire is invisible, and guessing what was meant would be
worse than saying so.

### Validation

Every file is validated at start. Results go to `<game>\r6\storages\AiNpc\config-report.json`
and to the RED4ext log via `FTLogError`, which is visible whether or not the in-game
logging toggle is on.

Reported: unparseable files, missing or malformed `contactId`, unknown keys (a typo in a
key name is the likeliest edit mistake and the hardest to notice), unknown variant
conditions, overrides of one file by another, and any `[ACTION:...]` tag advertised in
your text that no parser handles — that last one would otherwise leak into the chat as
raw text in front of the player.

**Read `config-report.json` first when a character does not behave the way the file says.**

---

## Way 2 — a script provider

For anything the JSON cannot express: text computed from live state, contacts that appear
and disappear during a playthrough, and actions of your own.

ai_npc's declarations live in `module AiNpc`, so start the file with:

```reds
import AiNpc.*
```

Only what is marked `public` is visible to you; the rest is ai_npc's own business and may be
moved or renamed without notice. If you need something that is not exported, ask rather than
work around it — an accidental export is a promise nobody meant to make.

Subclass `AiNpcContactProvider` and override only what you need — every method has a
sensible default, and returning an empty string means "no opinion" exactly as an absent
JSON key does.

```reds
public class NadiaProvider extends AiNpcContactProvider {

    public func GetContactId() -> String {
        return "MyModContact01";
    }

    public func GetDisplayName() -> String {
        return "Nadia";
    }

    // Reachable right now? Return false to suspend AI chat without unregistering --
    // that is how you keep your own scripted exchange from being talked over, while
    // preserving the conversation for later.
    public func IsAvailable() -> Bool {
        return !MyMod.HasScriptedExchangeRunning();
    }

    public func GetBio() -> String {
        return "You're Nadia, a fixer out of Kabuki...";
    }

    public func GetRelationship() -> String {
        let affinity = MyMod.GetAffinity();
        if affinity > 70 {
            return "V is someone you trust. You have worked together often.";
        }
        return "V is a merc you have hired once. You are still deciding about {them}.";
    }

    // What she WANTS from V. Its own question, because neither of the two above answers it:
    // a model handed a person with no intention invents one, and a different one every
    // message. Lands in <intent>, above the mission.
    public func GetIntent() -> String {
        return "You want V to take the Kabuki job, and you steer every conversation back to it.";
    }

    // The intention V's current mission replaces that one with, keyed like GetQuestContext.
    // Empty is no opinion, and the durable intention stands.
    public func GetQuestIntent(questKey: String) -> String {
        return "";
    }

    // What this contact has to say about the quest V is TRACKING, keyed by the canonical
    // quest name ai_npc logs when it meets one it has no entry for. Lands in <quest>.
    //
    // This works for a contact you declared. It did not until recently -- the builder tested
    // whether the contact was one of ai_npc's own before asking -- which made a documented
    // method silently dead for everybody else. A contact with nothing to say returns "" and
    // contributes no section, which is the same outcome by the honest route.
    public func GetQuestContext(questKey: String) -> String {
        return "";
    }

    // Volatile state, rebuilt for every message, injected into <now>. This is the
    // external equivalent of the quest context vanilla characters get.
    public func GetLiveContext() -> String {
        return s"Current job offer on the table: \(MyMod.GetOpenOfferLabel()).";
    }

    // How she speaks. Additive: appended to the rule block, so the built-in rules still
    // apply. Computed here, which the JSON key of the same name cannot do.
    public func GetSpeechStyle() -> String {
        if MyMod.GetAffinity() > 70 {
            return "Relaxed with V, first names, the occasional joke.";
        }
        return "Formal and distant. Keeps V at arm's length.";
    }

    // Whether this contact remembers what has fallen out of its window. Default true.
    // Answering false is characterisation, not a limitation: an automated number does not
    // accumulate a relationship, and giving it one would be the wrong kind of warmth.
    public func AllowsMemory() -> Bool {
        return true;
    }

    // What she already knows about V before a single message. Seeded into the memory at
    // its first compaction, so it lives and ages through the same machinery as everything
    // the conversation itself produced. One line each.
    //
    // BEFORE, and only before: this is applied once and never again. For something your
    // systems do LATER, see "Telling a character something your systems know" below --
    // client.CharacterKnows reaches the same list at any moment.
    public func GetSeedFacts() -> array<String> {
        let facts: array<String>;
        ArrayPush(facts, "V once did a job for her brother and never got paid.");
        return facts;
    }

    // Whole sections replaced. Return null -- the default -- unless you really need it.
    public func GetPromptOverrides() -> ref<AiNpcPromptOverrides> {
        let o = new AiNpcPromptOverrides();
        o.SetInteraction("REACH", "You talk to V through your own encrypted channel...");
        return o;                                  // unset fields keep resolving normally
    }
}
```

`GetSpeechStyle` and `GetPromptOverrides` are the same two levers as the JSON keys
`speechStyle` and `prompts`, and resolve through the same chain — see *Speech style* above
for what each is for. A provider contributes rubrics with `over.SetRule("KEY", "text")`.

### Registering

```reds
let client = AiNpcOpenClient("your_mod_id");

client.RegisterCharacter(new NadiaProvider());   // -> Bool
client.UnregisterCharacter("MyModContact01");    // -> Bool

AiNpcDrivesCharacter("MyModContact01");          // -> Bool, built-in or registered+available
AiNpcListDrivableCharacters();                   // -> array<String>, everything drivable now
AiNpcCharacterInOpenChat();                      // -> the provider behind the open chat, or null
```

Registration is dynamic. Nothing has to exist at launch: register the moment a contact becomes
reachable, and the phone picks it up the next time its contact list is built.

Three rules:

1. **Register after the player exists**, not at script load. A `ScriptableSystem`'s
   `OnPlayerAttach` is the usual place.
2. **Registrations do not survive a save load.** The registry's lifetime is the game session,
   deliberately: a stale provider outliving the state it describes is worse than registering
   again. Re-register on every session.
3. **One provider per `contactId`.** `RegisterCharacter` refuses a duplicate and returns
   `false` rather than overwriting, so which mod wins never depends on load order.

The registry holds a strong reference, so you do not need to keep the provider alive yourself.

**If the refusal is because somebody else declared that contact, do not go looking for a way
around it.** There used to be one — find the provider, unregister it, wrap it, put it back if
that failed — and it was a mistake this API has since removed, along with the function that
made it possible. Wanting to add to a contact somebody else declared is the normal case, and
it has its own door: see *Way 3*.

### Taking ai_npc as an optional dependency

A script provider does not have to make ai_npc mandatory for your mod. REDscript resolves
`@if(ModuleExists("AiNpc"))` at compile time, so you can ship one build that gains an AI voice
when ai_npc is installed and simply does without when it is not.

`module AiNpc` exists for this. Guard the import, the provider class and every call:

```reds
@if(ModuleExists("AiNpc"))
import AiNpc.*

// A class whose BASE TYPE lives in the guarded module can itself be guarded. That is what
// makes the pattern work at all for providers, and it is verified against scc.
@if(ModuleExists("AiNpc"))
public class NadiaProvider extends AiNpcContactProvider {
    public func GetContactId() -> String { return "MyModContact01"; }
    // ...
}

// One function, two definitions. The compiler keeps the one that matches the tree.
@if(ModuleExists("AiNpc"))
public func MyModRegisterVoice() -> Bool {
    return AiNpcOpenClient("your_mod_id").RegisterCharacter(new NadiaProvider());
}

@if(!ModuleExists("AiNpc"))
public func MyModRegisterVoice() -> Bool {
    return false;
}
```

The rest of your mod calls `MyModRegisterVoice()` and never learns which build it is in.

Four things worth knowing before you rely on this:

- **`@if` guards imports, free functions, methods, fields and class declarations.** It does
  not guard a *statement*, so a call inside an unguarded function still has to go through a
  two-definition function like the one above.
- **`ModuleExists("AiNpc")` is a contract.** The module name will not change. Individual
  `public` declarations may; a rename shows up as a compile error in your guarded half, which
  is the point of keeping the guarded half small.
- **A misspelled module name fails silently.** `ModuleExists("AiNPC")` is false in every tree,
  so the degraded half is compiled even where ai_npc is installed — your mod loads, and the
  voice simply never appears. Nothing warns you. Check the spelling as data if you can; the
  ai_npc_joytoys bridge does it in its linter.
- **Build both trees before you ship.** A guard that is missing somewhere compiles perfectly on
  a machine that has ai_npc installed and breaks every install that does not. The only thing
  that catches it is compiling your mod once with ai_npc in the tree and once without —
  `ai_npc_joytoys/tools/compile-check.ps1` is a worked example of exactly that.

- **Mirror the facade, one function per function, and put no logic in the mirror.** Whatever
  your guarded half computes, the degraded half has to compute identically — and a divergence
  between the two compiles, logs nothing, and shows up in game as a bug somewhere else
  entirely. Keep each half a single delegating line wherever you can.
  `ai_npc_joytoys/src/r6/scripts/ai_npc_joytoys/BridgeLlm.reds` is the worked example: one
  file, both halves of everything, and a linter rule that fails when a seam has only one.

And one rule about the degraded half that is worth stating on its own: **it is never a stub
that logs an error**. "ai_npc is not installed" is a supported configuration, not a failure.
Return the honest empty answer and let the caller carry on.

A JSON contact needs none of this: the file is data, and ai_npc not being there means nobody
reads it.

### Scripted replies — answering without the model

A provider can write the answer itself. `GetScriptedReply` is consulted for every message
V sends, **before any prompt is built**, and has three possible answers:

```reds
public func GetScriptedReply(playerText: String) -> String {
    if !MyMod.IsStillABot() {
        return "";                    // no opinion: the model answers, as usual
    }
    if MyMod.HasBeenQuestionedTwice() {
        return AiNpcSilentAnswer();   // says nothing at all to this message
    }
    return MyMod.NextCannedLine();    // this text IS the reply
}
```

A sheet in `cast/` says the same thing as data, in the `scriptedReply` field: one line per
language, plus one with no language for the locales the list does not name. `jackie_dead`
is the only shipped contact that carries one — after the heist that number answers *This
number is no longer in service.* and nothing else, whatever V writes. The field is for
sheets only; a character file cannot set it, since declaring one would switch off the very
thing the file came to configure.

The decision is taken per message rather than per contact, which is why this is a method
and not a `usesLlm` flag: a correspondent can loop mechanically for a while and hand over
to the model the moment the fiction says a person took the keyboard.

A scripted reply travels the same path a generated one does — typing indicator, delay,
action tags, history write, bubble when the chat is open on that contact and a phone
notification when it is not. Only two things differ: it costs no tokens and needs no API
key or network, and it arrives on a **fixed short beat** instead of the five-to-nine
seconds a person takes. That regularity is deliberate: it is what tells the player they
are talking to a machine.

`AiNpcSilentAnswer()` is not the same as `""`. The empty string means *let the model
answer*; the sentinel means *answer nothing*. V's own message is still recorded, so the
conversation keeps an unanswered line and `HasPendingReply` reports it — which is exactly
what happened. No generation is started, so the input stays enabled and the player is not
left watching a typing indicator for someone who will never write back.

This is the right shape for a correspondent that is not a person in the fiction: an
automated service, a bot, a menu system. It is also the only way to be certain a contact
cannot be argued out of character, since no model is asked.

### Actions

**A provider no longer declares commands.** What a character can DO is one call, and the
same call whoever is asking — the mod that declared the character, a mod extending it, a
character sheet, or ai_npc itself for the eddie transfer:

```reds
client.AddAction("[ACTION:BOOK]",
                 "Emit this when V takes the job you are offering.",
                 new MyBookingHandler(),
                 AiNpcContactTagFor("my_contact"));
```

See **[Commands](#commands)** below for the whole of it. What a provider still says about
its character is what that character *is* — including its tags, which is how somebody
else's command finds it:

```reds
public func GetContactTags() -> array<String> {
    return ["mymod:fixer"];
}
```

The four methods that used to live here — `GetActionPromptFragment`, `GetActionTags`,
`GetActionTagPrefixes`, `TryApplyAction` — are gone, along with `AllowsGenericTransfer`.
They are gone rather than deprecated, and the signature break is deliberate: a removed
virtual method leaves an override compiling and silently doing nothing, which is exactly
how one consumer lost its whole rendezvous vocabulary for as long as the feature existed.
The compiler saying so is the migration.

| was | is now |
|---|---|
| `GetActionPromptFragment` | the `prompt` argument of `AddAction`, or `AiNpcActionHandler.GetPrompt` when it has to be computed |
| `GetActionTags`, `GetActionTagPrefixes` | the `pattern` argument — one declaration is both the announcement and the claim |
| `TryApplyAction` | `AiNpcActionHandler.OnAction`, which returns a result carrying a note rather than a bare `Bool` |
| `AllowsGenericTransfer` | `client.SuppressAction(AiNpcTransferHead(), tag)` — it names the command it removes instead of being named after it |


## Commands

What a character can DO. One declaration, whoever is asking — the mod that declared the
character, a mod extending somebody else's, a character sheet, or ai_npc itself for the eddie
transfer. There is no second lane and no privileged one.

```reds
client.AddAction(pattern, prompt, handler, scopeTag)
```

**`pattern` is both halves of the command.** The model reads it and the dispatcher matches
against it, so a command cannot be advertised without being implemented, nor implemented
without being advertised. Slots are written `{like_this}` and each fills one colon-separated
field:

```reds
client.AddAction("[ACTION:TRICK:{venue}:{hour}:{price}]", "...", handler, "joytoy:client");
```

`OnAction` is then handed three strings, always three, never empty. A tag with the wrong number
of fields is a **fumble**, not an unknown command: it goes to the repair pass, and if that
cannot run it is stripped rather than shown. A trailing slot may be optional — `{days?}` — for
a command a model writes short when only part of it was agreed; `params` still holds one entry
per slot, and an absent optional is `""`. An optional may only be followed by other optionals.

**`prompt`** is the sentence that teaches the model *when* to emit it. Not optional in practice:
a command with no trigger is one the model fires at random or never. Keep it to two lines — it
is paid for in every prompt of every covered contact.

**`handler`** is an object with one required method. REDscript has no function values, and a
wide interface is one a consumer silently half-overrides:

```reds
public class MyBookingHandler extends AiNpcActionHandler {

    public func OnAction(ctx: ref<AiNpcContactContext>, params: array<String>)
            -> ref<AiNpcActionResult> {
        if !MyMod.HasOpenOffer() {           // re-check, always
            return AiNpcActionRefused("The offer is gone; say so rather than confirming.");
        }
        MyMod.AcceptOffer();
        return AiNpcActionDone();
    }

    // Optional. Whether it is offered right now -- state, not identity.
    public func IsOffered(ctx: ref<AiNpcContactContext>) -> Bool {
        return MyMod.HasOpenOffer();
    }

    // Optional. A prompt computed from game state, when a fixed sentence will not do.
    public func GetPrompt(ctx: ref<AiNpcContactContext>, declared: String) -> String {
        return declared;
    }
}
```

The **note** on the result is why it is not a `Bool`. A refused command is otherwise invisible:
the tag is stripped so the vocabulary does not leak into the bubble, and the model has already
written a message assuming it worked. The note is handed to the character as something it knows
for its next reply, so the refusal comes back in that character's own voice instead of as a
banner. Leave it empty when the reason is outside the fiction — a permission a config file
withdrew — because the character cannot know that and would only invent an explanation.

`OnAction` **must re-check its own preconditions and must be idempotent.** The prompt that
advertised the command was built before V wrote, the offer may be gone, a model can be argued
into emitting a tag it was never shown, and the reply is replayed whole after a network error.
Every field inside a tag was written by a language model: the arity is all the dispatcher bought
you. Prefer clamping a number or snapping a name to a known one over refusing, because a refusal
costs the whole command.

### Who may use it: tags

**`scopeTag` is required and there is no default.** An omission must narrow reach, never widen
it: a permissive default is found by the player, in play, on the day the model happens to emit
the tag, while a refused registration is found by its author immediately.

| tag | who carries it |
|---|---|
| `AiNpcEveryContactTag()` — `"ainpc:contact"` | every drivable contact. This is how *everyone* is spelled; there is no wildcard |
| `AiNpcContactTagFor(id)` — `"contact:judy"` | that one character |
| anything you name — `"joytoy:client"` | whoever carries it |

A character carries a **set** of flat tags: the two above, granted by ai_npc and neither
writable nor omittable, plus whatever its declarer states in `GetContactTags()` (or the sheet's
`tags`), plus whatever any mod assigns with `client.TagCharacter(contactId, tag)`.

That last one is the point. A taxi mod with no characters at all declares one command for
`ainpc:contact` and reaches an escort minted at runtime by a mod it has never heard of. A
rendezvous mod declares one for `joytoy:client`, and a config file that tags a contact makes it
a client without either mod knowing the other.

Tags are **flat**: the colon is a naming convention that keeps mods off each other's names, and
the comparison is on the whole string. There is no hierarchy and no `ainpc:*` — a shallow
hierarchy is already a set, and a wildcard would enrol tags created after the rule was written.

> **A tag is never omitted in order to remove reach.** If leaving one out could take a character
> out of somebody's rule, every tag added later would become one more thing every modder must
> remember to write, and forgetting it would silently break *other mods'* commands.

### Taking a command away

```reds
client.SuppressAction(AiNpcTransferHead(), "joytoy:vip");
```

Removes a command from the characters carrying that tag, by its **head** — the literal run
before the first slot. One-way: nobody can grant back what you removed, which is what makes it
safe for a mod that has taken responsibility for a character's economy. Use it when your own mod
already does the thing, so the model is never taught a command it would only be refused.

A character declared by a JSON file has no code, so it says the same thing as data:

```json
"suppressActions": ["[ACTION:GIVE_EDDIES:"]
```

Tags only ever add; suppression only ever removes. Two levers, one job each — which is what lets
a behaviour be read without knowing which mods are installed.

### Arbitration, and the one rule that surprises people

A command attached to one character (`contact:<id>`) beats one granted to a category, for that
character. Two claims at the same level collide: reported in `config-report.json`, lowest full
id wins.

And:

> **The offer governs the announcement. The claim governs the strip.**

Between building the prompt and reading the reply there is a network round trip, and `IsOffered`
can flip inside it. A claim that has stopped offering its command still **owns** its tag: the
tag reaches `OnAction`, is refused, and is stripped. Without that, a bracket leaks into the
player's chat every time a state changes mid-turn.

### What an extension may add, and what it may not

An extension has six methods, and the list is short on purpose. **A method is only here if the
rule for merging two mods' answers is written down.** That is the whole design, and it is why
the collisions are *unsayable* rather than arbitrated.

| Method | How two answers merge |
|---|---|
| `GetLiveContext` | concatenated, in id order, within a budget |
| `GetScriptedReply` | only the holder of the floor is asked; see below |

There is no `GetBio`, no `GetRelationship`, no `GetSpeechStyle`, because two of those do not
average. "Relaxed, first names" and "formal, keeps V at arm's length" is not a character, it is
a contradiction, and no ordering rule fixes it. If you need to say who someone *is*, you are
declaring a contact, not extending one.

What to use instead of what is missing:

| You wanted | Use |
|---|---|
| `GetBio`, `GetRelationship`, `GetSpeechStyle` | declare the contact, or `characters.json`. A *mood* belongs in `GetLiveContext` anyway |
| `GetSeedFacts` | `client.CharacterKnows(id, text, AiNpcUntilForever())`, which works at any moment rather than only before the first message |
| `IsAvailable` | two different questions. "Unreachable in the fiction" belongs to whoever declared the contact; "busy with my scripted exchange" is `client.TakeFloor` |

### The order, and what you must not do with it

Contributions merge in **ascending full id**, never in registration order. That is not
tidiness: the attachment order of game systems differs between two loads of the same save, so
ordering on it would make the prompt change from one launch to the next — a bug nobody
reproduces.

It is stable, and it is **alphabetical, not meaningful**: `johnny_leisure` merges before
`rogue_gigs` whatever the scene between them reads like. So never write a contribution whose
*sense* depends on running before or after somebody else's. Anything that would need to is not
an addition to a character, it is a disagreement about one.

Naming yourself to sort early buys nothing either: fragments concatenate, the veto is
order-free, and two mods claiming one exact tag is reported as a collision in
`config-report.json` before it is dispatched.

### The floor — taking a thread for a scene of your own

While you hold the floor on a contact, only your `GetScriptedReply` is consulted, no model is
asked, and **no other mod may write into that thread**.

```reds
client.TakeFloor("rogue", 90.0);   // -> Bool, false means somebody else has it
client.ReleaseFloor("rogue");
AiNpcFloorHeldBy("rogue");         // -> String, "" when free
```

- It is a **lease, not a lock**. `maxSeconds` bounds it (0 takes the default), and it expires
  lazily, on read — never on a timer, which would not survive a save load. A mod that crashes
  or is uninstalled mid-scene must not hold a character for the rest of the playthrough.
- Re-taking your own floor **extends** it, so a long scene can renew without releasing first.
- A refusal is information, not an error. `AiNpcFloorHeldBy` says who has it, and
  `OnFloorAvailable` on your extension is the defined moment to try again — every extension on
  that contact is offered it in id order, so which one gets it is the same on every machine.

`GetScriptedReply` has the same three answers it has on a provider: `""` hands the keyboard
back to the model, `AiNpcSilentAnswer()` says nothing at all and starts no generation, and any
other text *is* the reply.

---

## Watching what happens

A listener is told; it never decides. Nothing it returns is read, which is exactly why there
is no ordering between listeners, no budget and no arbitration — and why adding one costs
nothing.

```reds
public class MyWatcher extends AiNpcConversationListener {

    public func GetSubject() -> String {
        return "watch";
    }

    // Empty means every contact, which is the common case here: a listener usually watches for
    // a KIND of event rather than for one character.
    public func GetContactIds() -> array<String> {
        let empty: array<String>;
        return empty;
    }

    public func OnMessage(ev: ref<AiNpcMessageEvent>) -> Void {
        // ev.sourceId is your own mod id for lines YOU wrote. Read it, or a mod that answers
        // messages will answer itself.
        //
        // ev.systemNotice is true for a line ai_npc wrote as itself -- the operator notice
        // standing in for a reply that never arrived. fromPlayer is false for it, exactly as
        // for a real answer, so skip it when you are reacting to what a character said.
    }
}

AiNpcOpenClient("your_mod_id").RegisterListener(new MyWatcher());
```

The events:

| Callback | Fires when |
|---|---|
| `OnMessage` | any line enters a thread — V typing, a generated reply, a line a mod seeded |
| `OnReplyFailed` | a reply was expected and did not arrive. Only failures; an arrival is already an `OnMessage` |
| `OnActionApplied` | a tag was dispatched, applied or refused. The refusals are the interesting half |
| `OnConversationOpened` / `OnConversationClosed` | the chat opened or closed on a contact |
| `OnFloorChanged` | the exclusive turn changed hands. `expired` distinguishes a lapse from a release |
| `OnTicketSettled` | a ticket reached its verdict: a fact recorded, or a character having written first |

Two rules. **Do not block** — a listener runs on the caller's stack, inside the write it is
reporting. And **an observer cannot refuse or modify anything**: a listener that could say no
would be a conflict put back exactly where this design removed it.

---

## Making a character react to your quest

Everything above needs your mod to know ai_npc exists. Quest content mostly does not, and
cannot: a baked quest graph has no way to call redscript, and redscript has no way to add a
node to one. What both sides *can* do is read and write quest facts — so that is the bridge,
and it costs your mod nothing but the name of a fact it already sets.

Drop a file in `<game>\r6\storages\AiNpc\`, named `facts.<yourmod>.json` (or `facts.user.json`
for a hand edit, which is always applied last). `facts.example.json` is rewritten at every
launch and documents the live schema.

```json
{
    "version": 1,
    "facts": [
        {
            "fact": "yourmod_rescue_done",
            "atLeast": 1,
            "contacts": ["panam", "judy"],
            "event": "V pulled somebody out of a Maelstrom den in Northside last night. It made the local feeds.",
            "ackFact": "yourmod_ai_npc_heard"
        }
    ]
}
```

That is the whole integration. When anything sets `yourmod_rescue_done` — a quest phase, a
FactsDB manager node, a CET one-liner — Panam and Judy are each told what happened, **in your
words**, and each answers in her own voice the next time V texts her.

### What the fields mean

| Field | |
|---|---|
| `fact` | the quest fact to watch. No spaces: it becomes a `CName` and has to match the name your quest sets |
| `atLeast` | the value it must reach. `1` is a flag; a counter names its own number. Optional, defaults to 1 |
| `contacts` | who hears about it — `contactId`s, yours or ai_npc's own |
| `event` | what they are told. Placeholders are expanded (`{they}`, `{npc}`, …) plus `{value}` for the fact's own number |
| `ackFact` | optional, and the way back — see below |

The text you write is passed to the model untouched, framed as a world event so it cannot be
read as something V said. Write it as news, not as an instruction: the character decides what
to make of it.

### When it fires, and when it deliberately does not

A watch fires on the **crossing** of `atLeast`, and only on what happens while the player is
there. Two rules, both of which exist to stop a character bringing up the same thing forever:

- **A baseline is taken when the save loads.** A fact already past its threshold is not news —
  a quest finished three saves ago should not have Panam congratulating V on it at the next
  launch.
- **Only the crossing counts.** `atLeast: 3` fires on the third and stays quiet on the fourth
  and the fortieth. A mod that rewrites its facts on every load fires nothing.

Clearing the fact and raising it again *is* a second signal, and is treated as one. That is
the supported way to say the same thing twice.

### Nobody is interrupted

The event does not send a message. It is seeded as context for the named contacts and spent on
their **next** reply — so raising a fact while the phone is away, or during a firefight, costs
nothing: the news waits for the player to come back to that thread. A contact that is never
opened again simply never mentions it.

Two entries on the same fact are two watches, which is also how you word the same event
differently per character: declare it twice with different `contacts`.

### The way back

`ackFact` closes the loop. It is set to `1` once **one** of the named contacts has answered V
since being told, which is the signal a quest phase needs to move on:

```
Fact Condition: yourmod_ai_npc_heard >= 1   ->  next phase
```

Read it precisely: it means *the contact answered a message that carried your news*, not *the
character mentioned it*. Nothing here reads the reply, and a flag claiming otherwise would be
a flag that lies. Omit `ackFact` entirely if you do not need to know.

One fact is written without any declaration: **`ai_npc_installed` is set to `1` at every
session start**, so a quest can offer a texting-based path only where there is something to
text. It is a capability flag, not a liveness one — facts live in the savegame and nothing
clears it if the mod is later removed, so gate a branch on it, never a loop waiting for it to
drop.

### Testing yours

From the CET console:

```lua
Game.GetQuestsSystem():SetFact("yourmod_rescue_done", 1)
```

Then open the contact and send a message. If nothing happens, read `config-report.json` in the
same folder: every watch that loaded is listed there with the contacts it is addressed to,
which is where a mistyped `contactId` shows up. Contact ids are **not** validated at load —
providers register during the session, long after the file is read, so a warning there would
fire on every correctly-written watch that names another mod's contact.

---

## Telling a character something your systems know

A provider describes who a contact **is**. The quest bridge above reports something that
happened in the **world**. Neither covers the third case, and it is the most common one for a
mod that runs its own content: *your systems just did something involving this character, and
the conversation has no way of hearing about it.*

One call, and one parameter that decides everything:

```reds
client.CharacterKnows(contactId, "You met V last night at the No-Tell Motel. It was paid work, "
                               + "1500 eddies agreed beforehand, and it went well.",
                      AiNpcUntilForever());
```

| Bound | Lives | Use it for |
|---|---|---|
| `AiNpcUntilNextReply()` (default) | one generation, then dropped; does not survive a save | what is true *at this instant* — "you are still waiting outside", "you can hear the rain" |
| `AiNpcUntilForever()` | recorded in the contact's memory: repeated on every message, survives saves, **cannot be taken back** | what **happened** — a scene that played, a job that closed, a night that took place |

The text reaches the model untouched, exactly like the `event` field of a fact watch, and for
the same reason: you wrote it about your own content and there is nobody here to check a
rewording. Write it as a plain statement addressed to the character. Not as an instruction —
the block it lands in already states its own authority, and a second rule arriving after the
first is how a prompt starts contradicting itself.

### Why "forever" is a different thing, not just a longer one

It is not a bigger `UntilNextReply`. It is the only channel that can win an argument.

The memory block opens with its own precedence clause:

> *Everything below is something you ALREADY KNOW. Never ask V about it again. Where your
> character description says you do not know something and this block does, **this block is
> right**: the description is how you began, and this is what has happened since.*

Nothing else in the prompt says that. `<now>` cannot: it means "now", and memory means
"since".

**The failure that produced this call**, measured on 2026-08-22 in ai_npc_joytoys. A meeting
was negotiated in the chat, the player walked to it, another mod ran the whole scene, the
client texted afterwards, V answered "that was good" — and the client replied that they had
never met and that he was still standing outside. He was right to. The transcript held two
intentions and two allusions and never one statement, the appointment had just been cleared
from the provider's `GetLiveContext`, and the fallback line in `<now>` said *"there is no
history between you, nothing to refer back to"*. A model choosing between two allusions and one
declarative sentence picks the declarative one.

Four rules fell out of fixing it, and they are the ones worth copying:

1. **State it, do not imply it.** A transcript is evidence; a fact is a claim. Only the claim
   competes with another claim.
2. **Be explicit about what it was.** Vagueness is what caused the bug: a character told only
   that "it went well" fills the blank the obvious way, and the obvious way was that nothing
   had happened yet.
3. **Record it before you clear the state it is made of.** Place, hour, price all lived on the
   appointment; clearing first would have produced a fact with holes in it.
4. **One sentence per outcome, never one softened sentence.** A permanent fact cannot be taken
   back, so "it went well" recorded on an encounter that went badly is wrong forever.

### What the return value is for

It answers with a **ticket**, not a Bool, because the answer is not always known at the call.
Zero means refused outright — empty text, no contact, no session — and there is nothing to ask
about. Otherwise:

```reds
let ticket = client.CharacterKnows(contactId, line, AiNpcUntilForever());
AiNpcTicketState(ticket);      // Done / Pending / Failed / Unknown
AiNpcTicketReason(ticket);     // plain text, empty unless it failed
```

In the ordinary case the ticket comes back **already resolved**, so a caller who cares asks
immediately and a caller who does not ignores it entirely.

| State | Means |
|---|---|
| `Done` | recorded |
| `Pending` | there is no conversation for that contact yet. ai_npc holds the fact and records it the moment that contact's next prompt is built, which is before the reply it would have to be true for. **Treat it as kept** — a fallback here would state the same thing twice |
| `Failed` | the player turned memory off, or the contact keeps no memory. `AiNpcTicketReason` says which |
| `Unknown` | **not a failure.** Resolved tickets are kept in a bounded ring, so an old id simply falls out of it. A mod that reads this as "it did not work" announces to the player something that never happened |
| `Cancelled` | you withdrew it yourself with `CancelWantsToSay` |
| `Refused` | the player turned off *Characters May Write First* |

The last two never come back from `CharacterKnows`; they exist for `CharacterWantsToSay` below.
They are kept out of `Failed` for one reason: **`Failed` is the verdict your fallback fires on**,
and neither of those is a case where it should.

If you have a bounded fallback for a real failure — restating it from `GetLiveContext` for a
while — this is how you choose it. You can also be told instead of asking: `OnTicketSettled` on
a listener carries the same ticket and the same verdict.

Two more things it saves you from getting wrong:

- **Idempotent on exact text.** Calling it twice for one event — a reload, a listener that
  fires twice — leaves one line. Two *different* wordings of one event are two facts, so build
  the sentence the same way every time rather than composing it freshly.
- **Nothing expands your placeholders here.** `<now>` is run through
  `AiNpcExpandTemplateFor` on the way into the prompt; the memory block is rendered verbatim.
  Call `AiNpcExpand(text)` yourself first, or a `{they}` reaches the model as four literal
  characters and stays there for the rest of the playthrough.

`GetSeedFacts()` on a provider is the same destination reached at a different moment: it is
applied once, at the first compaction, for what a character knew *before* anything was said.
For anything that happens later, this call is the door.

### The transient half is attributed too

`AiNpcUntilNextReply()` lands in a per-contact, per-mod slot. Restating it replaces **your**
line and leaves everyone else's alone, and what waits is concatenated in id order when the
next reply is generated.

That is why the client exists rather than a free function: with an anonymous write, a second
mod seeding for the same contact erased the first, silently, and both callers were told it had
worked. There is a character budget per line and a shared one for the block —
`client.ContextBudgetLeft(contactId)` answers "will my next line fit", and anything dropped is
named in the log.

### Putting words in the conversation

Different job, and the past tense is the point — **nothing is sent**. No push notification, no
phone screen, no chat opened, no reply generated. Your mod already owns how a message reaches
the player; these put the same line where the model and the chat overlay can both read it.

```reds
client.CharacterWrote(contactId, "I'm two streets away. Stay put.");
client.PlayerWrote(contactId, "on my way");
client.OpenConversation(contactId);            // -> Int32; opens the chat, wherever the player is
client.ForgetConversation(contactId);          // irreversible, and refused for a vanilla contact

AiNpcPlayerHasWritten(contactId);              // -> Bool
AiNpcReadConversation(contactId);              // -> array<ref<AiNpcMessage>>: .text, .fromPlayer
```

Both writes answer with a code, and the three refusals are three different jobs — which is why
they are not one `false`. Check it before you notify: telling the player about a message that
was never filed is the failure this code exists to make visible.

```reds
let wrote = client.CharacterWrote(contactId, "I'm two streets away. Stay put.");
if Equals(wrote, AiNpcWriteOk()) {
    // filed in the thread; now notify however your mod notifies
} else {
    if Equals(wrote, AiNpcWriteFloorHeld()) {
        // somebody's scene owns the thread. AiNpcFloorHeldBy says who,
        // OnFloorChanged on your listener is when to try again.
    }
    // AiNpcWriteNoSession -- ai_npc is not up. Retry at your next attach.
    // AiNpcWriteEmpty    -- empty id or empty text. A call site to fix, not a state to wait out.
}
```

There is no "not driven" among them, on purpose: seeding a thread for a contact ai_npc does
not drive *yet* is the normal way to hand a conversation its starting point. `AiNpcDrivesCharacter`
is that question, and it is a separate one.

Both writes are **refused while another mod holds the floor** on that contact: splicing a line
into the middle of somebody's scripted scene is exactly the incoherence the floor prevents.
`AiNpcFloorHeldBy` says who has it.

`ForgetConversation` is the one irreversible call in the API, and it refuses outright for a
contact your mod did not declare — a mod cannot wipe a vanilla character's history or another
mod's thread. Every call is logged with its author whether it succeeds or not.

**Write first, notify second.** A mod that pushed its own notification without writing here
produced the exact bug this exists to prevent: the phone thread showing a message the chat
overlay had never seen, and the model opening a conversation without knowing what its own
character had just written.

`AiNpcPlayerHasWritten` is offered because every life cycle needs it and the alternative is
looping over the conversation yourself: a contact V has answered has a history, and erasing it
is the only irreversible thing an integration can do.

### Having a character write first

`CharacterWrote` above puts *your* words in the thread. This one asks for *hers*: you state a
reason, and ai_npc generates a message in her voice, files it, and pushes an SMS notification
when the phone is closed — so it reaches a player who is doing something else, which is the
whole point.

```reds
let ticket = client.CharacterWantsToSay("panam",
    "V has not been in touch for three days. You are worried, so you ask whether "
    + "everything is all right.");
```

State the reason **in your own words, addressed to the character**, exactly as for
`CharacterKnows`. It reaches the model untouched, and V never reads it.

**Why a reason and not a line.** Your own text is right for an SMS your quest wrote — you own
it. It is wrong for "she noticed V has gone quiet", which the model writes better than you do,
and writes in the player's language for nothing.

**The optional third argument: what she is after while writing.** The reason says what
happened; `intent` says what she is *trying to do* about it. It replaces the `<intent>` section
for that one generation and nothing else — nothing is stored, and she is exactly what she was
the moment the message is written.

```reds
let ticket = client.CharacterWantsToSay("panam",
    "You have just seen how many people follow that page of V's. You are writing about it now.",
    "You want a straight answer about how far this goes and where it stops.");
```

Leave it empty and she writes under what she always wants — which is the right answer more
often than not. It is the wrong one exactly when a **tracked quest** has replaced her standing
intent with something that excludes your subject: Panam mid-*Riders on the Storm* is told
"nothing else matters until Saul is out", and an unprompted message about anything else is then
one parenthetical line at the end of the transcript arguing with a whole section of the system
prompt. The section wins.

Three tiers, resolved in `AiNpcIntentOf`: what you stated here, then the tracked mission, then
the character's durable intent. It outranks the mission deliberately — the mission describes a
life, your intent describes an occasion.

**Present tense, and a ticket.** Nothing is recorded at the call. You state that she has
something to say; whether it becomes a message, and when, is ai_npc's answer, and it comes back
on the ticket — `Pending` at the call, `Done` once the line is in the thread, `Failed` with a
reason if it never got there. `0` means refused outright and there is nothing to query.

**What decides *when* is yours.** A mod that wants a character to notice a silence knows that
silence better than ai_npc could: `AiNpcReadConversation` carries `gameTimeSeconds` on every
message, so "how long since" is a subtraction — evaluated lazily, on an event that survives a
save load, never on a `DelayCallback`, which does not. ai_npc keeps only the guards that are not
yours to hold. It owns **no schedule and no threshold** — *when* a character has something to
say stays entirely your question. What it does own is the cost of a turn the player never typed:

| refused when | because | waitable |
|---|---|---|
| another mod holds the floor | the scene in progress owns the thread | **yes** |
| a generation is already running | one at a time, and the lane is one for the whole session | **yes** |
| she wrote first less than a minute ago | the debounce, below | **yes** |
| the queue is full | eight waiting, all mods together | no |
| the player turned it off | *Characters May Write First*, and it is only the player's call | no |
| ai_npc does not drive this contact | `AiNpcDrivesCharacter` is the question that says so | no |
| the day's token budget is spent | the player's ceiling, and this counts against it | no |

The waitable column is what the policy argument below acts on, and nothing else does.

Every one of those is reported **on the ticket and nowhere else**. Nothing appears on the
player's screen and nothing is written into the thread — nobody is waiting for a message they
never asked for, so an operator line there would arrive out of nowhere and then come back in
the next prompt as something that was said.

### Now, or within a window

The fourth argument decides what happens when the lane is not free. Two values, and the second
one carries its own bound:

```reds
client.CharacterWantsToSay("panam", reason, "", AiNpcSayNow());        // the default
client.CharacterWantsToSay("panam", reason, "", AiNpcSayWithin(180));  // seconds of play
```

`AiNpcSayNow` is now or never: every refusal in the table comes straight back on the ticket, and
that is what this call has always done — a call written before this argument existed keeps its
exact behaviour. `AiNpcSayWithin(n)` queues the reason instead, sends it the moment the floor,
the lane and the debounce all allow it, and fails it if that has not happened within `n`
seconds. Nothing else is on offer, and the missing third option is deliberate: **"as soon as
possible" with no bound is not implementable honestly.** You write the reason in the present
tense, so a reason delivered long after its moment is a message that argues with the game.

Choose by what you wrote, not by how much you want it delivered. *"She has just watched V walk
past"* is only true now. *"She has been worried since this morning"* survives a wait.

**The clock is the player's, not Night City's.** Three minutes here is three minutes of play —
the same choice the floor lease makes, and for the same reason: the city's clock runs some sixty
times faster, so a window in game seconds would lapse before the player finished reading.

**One minute between two unprompted messages on one contact.** That is the debounce, and it is
not a schedule: it does not decide when your character speaks, only how fast anything may. It
exists so a trigger that fires in a loop cannot spend the player's daily quota in a burst. Ask
for a window shorter than what is left of it and the call is refused immediately rather than
queued — a wait that could never have worked is not a wait worth making you sit through.

**The queue holds eight, all mods together, and one entry per mod per contact.** Restating
replaces your own entry and keeps its place in the line; it never gives you a second slot. A
full queue refuses at once whatever window you asked for.

### Withdrawing one

```reds
client.CancelWantsToSay(ticket);   // -> Bool
```

For the moment that passed: the player walked into the room, the quest moved on, your own scene
started. `true` means there was something to take back. `false` is the honest answer to
cancelling twice, to cancelling somebody else's ticket, and to cancelling one whose request has
already gone out — a generation in flight cannot be recalled, and a call that claimed otherwise
would have you announce a message the player is about to receive as stopped.

The ticket settles as `Cancelled`, not `Failed`. **Your fallback must not fire for it.**

### Nothing waits across a save load

The queue is thrown away with the session, deliberately: the world on the other side of a reload
is not the world the reason was written about. Nothing is resolved on the way out — a reloaded
game answers `Unknown` to a ticket from the session before.

Which means **the idempotence is yours**, and it is not free. A permanent fact is de-duplicated
on its exact text; a message is not, and a reason re-stated after a reload that already went out
before the save is a character saying the same thing twice. Gate your retry on something you
persist: a quest fact you set from `OnTicketSettled` when the verdict is `Done`, or
`AiNpcReadConversation`, which does survive the reload.

**It can act, not only speak.** The reason lands where V's message would, so it has the same
pull on the model and the command vocabulary fires from it. A birthday reason produced
`[ACTION:GIVE_EDDIES:1000]` unasked — the character sent V money. That is the feature working, but
it means this is not a read-only call: it spends a request, it can move eddies under the
generic transfer cap, and it can trigger any action your own extension claims. State reasons
you would be happy for her to act on.

**A contact that answers from its own script is not consulted here.** `GetScriptedReply` asks
what it answers *to a message*, and there is no message. If you declared such a contact,
`CharacterWrote` is the call you want — you own its text, and it costs no request.


**Have a fallback, and it is yours to hold.** Most of the refusals above are ordinary conditions
rather than faults — a day whose budget is spent, another mod mid-scene, a window that closed. So
a moment your content depends on will sometimes not be written, and nothing appears on the
player's screen to say why. Watch the ticket and write your own line with `CharacterWrote` when
it comes back `Failed`; `OnTicketSettled` carries the verdict with its ticket id, so there is
nothing to correlate by hand.

ai_npc does not hold that line for you, and the omission is deliberate: a fallback is your text,
in your voice. The shape that works is three tiers — ask for a generated line, fall back to an
authored one, and let the authored one be the floor that always exists.

**`Failed` only.** `Cancelled` is your own withdrawal. `Refused` is the player having said no to
being written to at all — and the question they answered is about *being written to out of
nowhere*, not about who writes the words. An authored SMS pushed in its place is the same thing
they refused, arriving anyway from a mod that read the verdict as a technical hiccup.

ai_npc cannot stop you, and does not pretend to: `CharacterWrote` sends nothing, so the
notification that would break the setting is one on your side that this mod never sees. It is a
rule, and `AiNpcMayWriteFirst()` is how you honour it before you even arm a trigger.
---

## Reading the player's settings

Read-only, and only the ones that decide how your own text should read. The player answers
once, in *Mod Settings → AI NPC*; a second mod asking the same question with its own switch is
how somebody ends up consenting twice and being contradicted by whichever one they forgot.

```reds
AiNpcAllowsExplicitContent()   // -> Bool, true at both NSFW tiers
AiNpcChosenTone()              // -> String, "normal" | "nsfw" | "nsfw_hard"
AiNpcChosenLanguage()          // -> String, "fr" / "en" / ...
AiNpcSpeaksOfPlayerAsMale()    // -> Bool
AiNpcMayWriteFirst()           // -> Bool, and see CharacterWantsToSay above
```

Prefer `AiNpcAllowsExplicitContent()` unless you genuinely have three registers of text.
Comparing the code by hand is what breaks the day a tier is added, and it breaks in the
direction nobody tests: a string that matches nothing reads as *not explicit* here, and as
whatever your `if` happens to say over there.

Codes rather than enums, deliberately. You take ai_npc as an optional dependency, so every
type of ours has to be named inside your `@if(ModuleExists("AiNpc"))` block — a `String` and a
`Bool` do not, which is what lets you store the answer in a field your degraded build also has.

**What the tier is, and what it is not.** It constrains what the *model* is asked to write.
ai_npc does not gate its own **authored** text on it: a hand-written line ships as written,
because a corpus somebody wrote is not a thing the mod second-guesses at runtime. If you use
this to hide your own written content, that is a rule of yours — a defensible one, and not one
you are inheriting from us.

There is no setter, and there will not be one. A mod that could raise the tier could consent
on the player's behalf.

## Sharing ai_npc's storage — never open it yourself

If your mod keeps files in `<game>\r6\storages\AiNpc\`, ask ai_npc for the handle:

```reds
let storage = AiNpcSharedStorage();            // may be null before ai_npc is up
```

**Do not call `FileSystem.GetStorage("AiNpc")`.** RedFileSystem allows exactly one claimant per
storage name and does not fail softly. A second one gets

```
Attempt to access storage "AiNpc" several times. Only one mod can access its own storage
with RedFileSystem. Access to this storage has been permanently revoked for this session.
```

and the mod that loses is ai_npc, which then has no journal — every conversation reads empty —
and no `settings.json`, so every request goes out unconfigured and comes back
`[NO SIGNAL: HTTP 0]`. Nothing in the redscript log mentions any of it; the only trace is
`red4ext/logs/redfilesystem-*.log`, which is therefore the first file to open when a mod
behaves as though its files had vanished.

Open it once and pass the handle around. Even repeated calls from the *same* mod are a risk —
the message says "several times".

**Name your files with the client.** `client.FileName("state")` gives you
`mod.<your_mod_id>.state.json`, which is not decoration: ai_npc's config loader globs
`characters.*.json` and `facts.*.json`, so a file of yours that happens to match gets parsed
as a character definition and reported as broken.

---

## Contact hashes

If you also register the contact with Phone Extension Framework, it identifies contacts by
an `Int32` hash rather than a string. `AiNpcContactKey(contactId)` derives one that is
stable across sessions and versions:

```reds
public func GetContactHash() -> Int32 {
    return AiNpcContactKey("MyModContact01");
}
```

Values land in `[1000000000, 1008000009]`. That does not prove no vanilla journal hash
sits in that range, so verify your contact does not shadow a real one — `Register` only
guards against collisions between registered providers.

---

## Being reachable in the phone

Registering a provider makes a contact **supported**. It does not make it **visible** — the
row the player clicks comes from the phone's contact array, which is normally filled by
whatever framework your mod already uses. Two things go wrong there, they look identical in
game ("my contact is not in the list") and they need opposite fixes.

**The entry exists but is empty.** The phone does not draw a `ContactData` that has no
messages, so a contact whose entry omits `hasMessages` / `messagesCount` appears only once a
real thread exists — it works in testing, right after the first message, and looks broken on
a fresh save. Nothing logs it: the contact is registered, it is in the array, it is simply
never drawn.

You do not have to do anything about this one. Every registered provider's entry is repaired
automatically, and the repair only raises those flags when they are unset, so a correct entry
is left alone and your message preview is never touched. It mutates an entry that is already
there, so it cannot produce a second row.

**The entry does not exist at all.** Nothing supplies it, so there is nothing to repair.
Opt in, and a row is created for you:

```reds
public func WantsPhoneContact() -> Bool {
    return true;
}

// Optional; defaults to PhoneAvatars.Avatar_Unknown
public func GetPhoneAvatarId() -> TweakDBID {
    return t"PhoneAvatars.Avatar_Sandra_Dorsett";
}
```

`WantsPhoneContact` defaults to **false**, and leaving it there is right for most providers:
if your mod already registers the contact with Phone Extension, NightlyNow or a journal
entry, opting in gives the player the same correspondent twice. Turn it on only for a contact
nothing else supplies.

**Notifications, when the phone framework is not the vanilla one.** ai_npc pushes an SMS
through the vanilla phone, addressed by display name, whenever a line lands and no surface
painted it. That is right for a vanilla contact and wrong for one that lives in NightlyNow's
HoloSystem or Phone Extension, where a thread is addressed by hash — the notification would
lead nowhere when the player taps it, and your contact list would not be refreshed. Take it
over:

```reds
public func Notify(text: String) -> Bool {
    // push it through your own framework, bound to your own thread
    return true;      // false falls through to ai_npc's vanilla push
}
```

**The write is not yours and never becomes yours.** The line is already in the conversation
store before `Notify` is called. Only the notification moves. A mod that notified without
writing produced exactly the bug this ordering prevents: a phone thread showing a message the
chat overlay had never seen.

It is called only when nothing rendered the line, so an open chat needs no notification —
which makes it the ordinary path for `CharacterWantsToSay`, whose whole purpose is to reach a
player who is doing something else.

Both passes skip built-in contacts, and both check the array for your `contactId` first, so
they are safe to run on every call — which the phone does, often.

**Ordering.** REDscript applies `@wrapMethod` in compile order and the last one compiled is the
outermost, so a wrapper that sits inside another mod's never sees the entries that mod adds.
That is not theoretical: this pass originally lived in `r6\scripts\ai_npc\`, ended up inside
Phone Extension's wrapper, saw only the vanilla array, and did nothing at all — silently,
because "found nothing to repair" and "was never given anything" looked the same.

It now ships in `r6\scripts\zzz_ai_npc_phone\`, whose name exists only to sort last. Renaming
that folder reintroduces the bug. A mod sorting after it would put us back inside — which is
why repair is automatic and injection is opt-in: the automatic half's worst case is "no
change", never "two rows".

---

## Reading and repairing the journal from outside

Four functions, all `String` in and `String` out, in `api/AiNpcJournalApi.reds`. They exist for
two callers that want the same thing: a person typing into the CET console, and a mod that
would rather not depend on `AiNpcConversation` to move a history around. Failures come back
as a sentence saying what was refused, never as a bare `false`.

| Function | Answers |
|---|---|
| `AiNpcJournalStatus()` | the pointer this session restored, and each contact's message count |
| `AiNpcJournalBranches()` | every branch on disk, replayed to its head — where an import pointer comes from |
| `AiNpcJournalPointerNow()` | this savegame's pointer, as `"b14:467"`, or `""` before its first message |
| `AiNpcJournalImport(pointer)` | adopts that history and forks into a branch of this save's own |

Those four are the **redscript** surface. From **CET** the way in is the store itself: a
redscript class inside a module is reached by its module-qualified name, and its public
methods are callable directly. There is no Lua global named after the functions above — a
bare `AiNpcJournalStatus()` in the console is a nil value.

| Store method | Function above | Cost |
|---|---|---|
| `DescribeState()` | `AiNpcJournalStatus()` | free — reads live state |
| `JournalBranchRows()` | — | one read per branch file, no parse: `id 	 parent 	 head 	 lines 	 present 	 current`, for a UI |
| `DescribeBranches()` | `AiNpcJournalBranches()` | same rows, rendered as text for a console |
| `DescribeBranchDetail(p)` | `AiNpcJournalDetail(p)` | **a full replay of that one branch** — contacts, counts, last message |
| `GetPointer()` | `AiNpcJournalPointerNow()` | free |
| `ImportFromPointer(p)` | `AiNpcJournalImport(p)` | a replay and a fork |

The split between rows and detail is the load-bearing part. Listing used to replay every
branch to count its conversations — several thousand JSON parses, most of them for branches
nobody was going to choose, before a window could draw its first row. A listing exists to be
scanned: it reads a file's length and its last operation, and nothing else. The replay happens
to the one branch somebody points at.

```lua
local store = Game.GetScriptableSystemsContainer():Get("AiNpc.AiNpcConversationStore")
print(store:DescribeBranches())
print(store:ImportFromPointer("b14:467"))
```

The mod ships a CET window that wraps exactly that — branch table, per-branch preview, restore
with an undo — at `bin\x64\plugins\cyber_engine_tweaks\mods\ai_npc_debug\`, inside the same
archive as the scripts, so it arrives through the normal install and needs no separate step.
Where CET is not installed, that folder is simply never read. Its functions are also reachable
from the console as `GetMod("ai_npc_debug").status()`, `.branches()`, `.detail("b14:96")` and
`.restore("b14:467")`.

From **another mod**, with ai_npc optional, exactly as with the rest of this API:

```swift
@if(ModuleExists("AiNpc"))
public func MyModImportHistory(pointer: String) -> String {
    return AiNpc.AiNpcJournalImport(pointer);
}

@if(!ModuleExists("AiNpc"))
public func MyModImportHistory(pointer: String) -> String {
    return "ai_npc is not installed.";
}
```

All four are safe to call at any moment: with no session loaded the store does not exist,
and each says so rather than failing. `AiNpcJournalImport` additionally refuses while the
phone is open — the chat UI holds what it drew, and replacing the history underneath it
would leave the player reading messages that no longer exist.

There is no Mod Settings entry for this and there cannot be: Mod Settings has booleans,
numbers and dropdowns, and a journal pointer is text. The two ways in are therefore the
console and the `importConversationsFrom` key in `settings.json` — see the README.

---

## Where each piece ends up

The system prompt is assembled in this order. Knowing which tag your text lands in is
usually enough to explain a reply you did not expect:

```
--- invariant, and cacheable as a prefix ------------------------------------
<system>        fiction, rules
<explicitness>  what may be written         <- "tone": Normal / NSFW / NSFW_Hard
<character>     bio                         <- GetBio / "bio"
<player>        who V is                    <- life path + gender + "appearance",
                                               or "playerDescription" replacing all three
<relationship>  how they see V              <- GetRelationship / "relationship"
<interactions>  what texting can and cannot do
<world_background>  the world, and how a local reacts to it
<mechanics>     how the world works         <- worldMechanics, and nothing about commands
<commands>      what this contact may DO    <- every AddAction whose tag this contact carries
<language>      language instruction
--- volatile ----------------------------------------------------------------
<memory>        what fell out of the window <- see MEMORY.md; absent until compacted
                                            <- + client.CharacterKnows(.., Forever): permanent
<intent>        what they want from V       <- GetIntent / "intent"
                                            <- GetQuestIntent / "questIntents" while tracked
<quest>         quest context               <- GetQuestContext / "questContexts"
<now>         the clock, volatile context <- + GetLiveContext
                                            <- + client.CharacterKnows(..): spent on one reply
                                            <- + a fact watch's `event`, framed [WORLD EVENT:]
<explicitness>  the tier 1 ban, restated    <- level 1 only; the upper tiers close on nothing
```

**Blocks are ordered by increasing volatility, and that is a rule.** Everything invariant
comes first, then the memory (rewritten about once every ten turns), then what changes on
every single message. OpenAI-compatible backends discount a repeated *prefix* from around a
thousand tokens; the in-game clock used to sit inside `<system>`, so the identical prefix
ended around token 200 and nothing was ever discounted. If you add a section, decide how
often it changes and put it where that answer says.

The closing `<explicitness>` stays last despite being invariant: it is a recency device, it
is one line, and everything after the cacheable prefix is uncached anyway.

It carries a prohibition, not a tier: a model drifts back towards saying less than it was
allowed, never more, so only level 1 closes the prompt with anything. Replacing a tier
through `tone` in `prompts.json` replaces the tier text only -- a player who rewrites level 1

Every one of those sections is built **for a contact id**, which is the identity of a
conversation throughout the mod: the string the phone selected, stored verbatim, never
reconstructed from anything else. A generation is addressed once, when it is sent, and the
reply, the history write and any action tags all go back to that same id -- so opening
another contact while a character is still typing cannot move the answer. The chat only
renders the bubble when it happens to be open on that contact; otherwise the reply arrives
as a notification.

`prompts.json` reaches the sections that are not per-character — `interactions`,
`worldBackground`, `worldMechanics`, `rules` and `languages`. Same rule throughout: an absent
or empty key keeps the built-in text, a string replaces, an object contributes by key. There
is no `tone` key: `<explicitness>` is the player's setting.

### What every character already knows about Night City

`worldBackground` is not empty by default, and a character you register inherits it without
asking. It is `AiNpcBuiltinWorldLore()`, and it is **not a fact sheet** — the facts are the
bottom third of it. What the block is for is a *posture*: how someone born here reacts to a
subject nobody wrote a rule about.

- **LIVED** — nothing in the city surprises the character, who lives on a short horizon; the
  city does not move them, people do. Written as experience rather than as a claim about the
  world.
- **HOW IT SHOWS** — habituation shows in what is *left out*: no alarm, no lecture, no
  procedure, and **no remark about how this world works** — a local does not explain the local
  weather. Same shape as the `TIME:` rule: know it, never write it. A bad thing is still
  allowed to be bad.
- **CALIBRATION** — three wrong/right pairs. One of them is on a subject no paragraph below
  covers, which is the pair that shows the posture generalises instead of looking things up.
- **BODY / VIOLENCE / SEX / ECONOMY / COST** — the facts, as the material that makes the
  posture plausible. Chrome and biomonitors; violence ordinary, paid, institutional and
  advertised; sex work a licensed trade; nothing a right and everything a price, with the
  corps above all of it; and what this world charges instead — eddies, data, reputation.
  `ECONOMY` states how power is arranged and says outright that it is **not a verdict on
  it** — V may be a corpo, Takemura is loyal to one, and an opinion stated here would
  outweigh every bio that disagrees.
- **NIGHT CITY** — the inverse of that ban, and the block says so: districts, places,
  corps, gangs, people and slang that exist **to be spoken**, for a model whose knowledge of
  the setting is thin. If you are adding setting detail of your own, this is the rubric it
  belongs in.

Its last line, `WORDS`, is **the only part of the block that changes with the language**, and
it is a table rather than a translation: Cyberpunk 2077's own localisation kept some terms
(eddies, choom, corpo, joytoy, fixer, netrunner) and localised others, so French says
*charcudoc*, *paumard*, *trait plat*, *danse sensorielle* — and the French line names the
English forms only to ban them. English is the default; a language with no table of its own
gets the English words plus the instruction to prefer its own official terms. Adding a
language is one `case` in `AiNpcWorldLoreWords`, and `tools/lint.ps1` pins the terms so a
table cannot silently fall back to English.

**This exists because a prompt that states no rule gets the model's own**, and the model's
own are ours. Left unstated, characters hand out twenty-first century health advice —
condoms, testing, *be careful* — inside a setting that engineered the problem away. It is
not a tone problem and it does not respond to a stricter guardrail; the fix is to state the
world. If your character sounds oddly prudish about a subject Night City finds unremarkable,
check whether something upstream replaced this section.

**And the second failure, which the first fix caused**: a world stated as declarative prose
is a world the model recites. Given *disease is a bill, not a fear*, it answers a friend in
trouble with *that's just Night City, you get used to it* — the instruction, paraphrased,
which on a serious subject reads as monstrous rather than as local colour. That is what the
posture rubrics and the ban on narrating the norm are for. **If you replace this section,
carry that ban into your own text**, or you inherit the recitation with the freedom.

It grants nothing and forbids nothing about explicitness — that stays with the tone tier
and with your own `speechStyle`. Attitudes stay with your character too: disapproval is
perfectly in character, it just has this world's reasons rather than ours.

If your character genuinely needs a different world — an AI, someone off-world, a construct
— replace the section through `prompts.worldBackground`. It no longer takes V's description
with it: that is `<player>` now, replaced separately through `prompts.playerDescription`.

`<player>` is built from three things: V's life path and gender, both read from the save and
never configurable, and the player's own `appearance` line from `settings.json`, appended to
them. `playerDescription` — global or per-contact — replaces the lot, life path included.

For a contact that has never seen V — an unknown number, a bot, a stranger — set
`playerDescription` to what that contact actually knows rather than trying to blank it:
*"You have never met V and have no idea what {they} look like."* Stating the ignorance beats
an empty section, which the model fills in on its own.

### Adding to the city instead of replacing it

Replacing `worldBackground` is the wrong tool when your mod puts something new *in* Night
City rather than taking a character out of it — a piece of hardware people have heard of, a
shop, a rumour. Every override is a silent loss of what it replaces, and the built-in lore is
what keeps characters from applying present-day reflexes to this setting.

```reds
client.RegisterWorldKnowledge("implants", "Sensory implants of this kind are sold openly in "
                                        + "Night City; most people know somebody who has one.")
```

- **Additive.** It joins `<world_background>` after the built-in text *and* after anything
  `prompts.json` says. Neither is diminished, and a contact whose background is overridden
  still gets it — they live in the same city as everybody else.
- **Told to every drivable character**, with no audience filter in this first shape.
- **Idempotent by subject**, like extensions: registering the same subject again replaces.
  Register on every attach and keep no state of your own — nothing here survives a save load.
- **Concatenated in `<modId>:<subject>` order**, never registration order, so the prompt does
  not change between two launches of the same save. No contribution may depend on running
  before or after another.
- **Bounded at 1200 characters per contribution.** Over that it is *refused*, not clipped:
  the return value is `false` and the reason is in the log, at the moment you can still
  shorten the text. `false` always means **not stated**.
- **Withdrawn by `UnregisterAll()`** with everything else your client holds.

This is not the same thing as an extension with an empty contact list, and the difference is
the regime rather than the audience: an extension speaks into `<now>`, which is for what is
true *now* and is budgeted per message because several mods describing one moment drown the
message V actually wrote. A standing fact about the city is stated once, in the invariant half
of the prompt, and does not compete with anybody's account of the moment.
