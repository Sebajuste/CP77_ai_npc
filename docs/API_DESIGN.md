# Why the API has the shape it has

Companion to [API.md](API.md), which is the reference. This file holds the reasoning: the rules
that are not obvious from a signature, the failures that produced them, and the things a future
change must not undo. Nothing here is needed to write an integration; it is needed to argue
with one.

---

## Shapes and names

### A free function reads, a client method writes

One rule decides which shape a call has, and an integrator can hold it in their head: **if you
needed the client, you changed something.**

The write forms used to be free functions. They are gone, not deprecated: an anonymous write
cannot be budgeted per mod, told apart in a listener, or refused when it would land in the
middle of somebody's scene. `AiNpcOpenClient("your_mod_id")` is the whole migration.

The author is carried on the object rather than as an `opt sourceId` on each call. Restated at
every call site, one typo creates a ghost author whose facts nobody can find, budget or retract.
First claim on a `modId` wins, as for a `contactId`, so an attribution is never ambiguous — a
collision model, not a threat model. Nothing stops a mod claiming a name first.

### Three shapes, and the shape says what the name answers

| Shape | Means | Examples |
|---|---|---|
| subject + tense | a statement about the world | `CharacterKnows`, `PlayerWrote` |
| verb first | an order to ai_npc | `OpenConversation`, `AiNpcOpenClient` |
| question | the character answering about itself | `IsAvailable()`, `GetLiveContext()` |

Inside a statement the **tense** carries the how: past means it already happened and you are
recording it — nothing is sent; present means a state you are setting, held until the bound you
give.

A name like `ThreadSay` promises both, and this mod paid for that once: the anonymous-contact
probe notified the player without writing to the store, so the phone showed a message the chat
overlay had never seen and the model opened a conversation not knowing what its own character
had just written. That failure is why `CharacterWrote` is past tense and sends nothing.

### Vocabularies are functions, not enums

A public enum forces a *guarded declaration* in a mod that takes ai_npc optionally, where a
function forces only a guarded wrapper. `Int32` crosses the `@if` boundary; a vocabulary does
not. The same reasoning makes `AiNpcChosenTone()` return a code rather than the enum: a consumer
cannot name a type of ours outside its `@if` block, but it can store a `String` in a field its
degraded build also has.

The price is that no type keeps two vocabularies apart — comparing an outcome against the wrong
constant compiles, warns nothing, and *matches* if the two share a number. So the compared ones
occupy **disjoint ranges**: ticket states `0–3` (plus 4 and 5), open outcomes `10–14`, write
outcomes `20–24`. A confusion then matches nothing at all instead of matching the wrong thing.
`0` is left unused in the outcome ranges so a default-initialised `Int32` is never an outcome.

The bounds stay at `0` and `1`, outside the scheme: they are passed, never compared, and `0` has
to be what an `opt` parameter defaults to. `AiNpcUntilNextReply` is `0` because it is the safe
direction — a wrong permanent fact cannot be taken back, a wrong transient one is gone after one
generation.

### A channel is named, because the set is open

Every other vocabulary here is an `Int32`. The channel is a `String`, and the exception has one
reason: the others are **closed** and this one is not. There is a written channel and a holo
call today; a face-to-face channel is planned, and nothing says it is the last.

A closed vocabulary fails safely when a consumer confuses two constants — that is what the
disjoint ranges above buy. An open one fails the other way, and the failure is not in ai_npc's
code at all. A listener writes what anybody would write:

```swift
if Equals(ev.channel, holo) { /* spoken */ } else { /* texting */ }
```

The day a third channel ships, that `else` receives it. The build is already published, the
compiler has nothing to say, and a face-to-face conversation is rendered as an SMS thread. No
version of numbering avoids it — the bug is the exhaustive `else`, not the type.

So the medium is handed over as **a name plus the two predicates a renderer actually needs** —
`spoken`, `showsInThread`. A predicate has no `else` to fall into: a channel added later
declares both, and the code already written keeps being right. The name is there for the case
the predicates cannot serve, which is real — a mod written *for* the holo lane, or for the
face-to-face one, knows exactly which it wants and should not have to infer it from two
booleans. Hence the rule the reference states: compare the name for a channel you know, branch
on the predicates for every other.

`String` rather than `Int32` also because it costs nothing here. The reason vocabularies are
functions is that an `Int32` crosses the `@if` boundary where a type does not; a `String`
crosses it the same way, and a degraded build stores `""`. It reads in a log, it needs no range
reserved, and a mod that one day brings its own surface can carry its own name without ai_npc
minting a number for it. This is the shape `tags` already has, for the same reason.

The enum behind it, `AiNpcChannelId`, stays internal and always will. It is the **disk value**:
numbered, with the written channel at zero so every line stored before the field reads back as
what it was. Exporting it would publish a numbering that exists to keep old journals readable,
and invite exactly the exhaustive comparison above.

### Codes rather than `Bool`, where the refusals are different jobs

`CharacterWrote` fails three ways, and a `Bool` collapsed a held floor — temporary, with a
defined moment to retry — into the same answer as a misspelt contact id. `OpenConversation` is
the same argument: *already there* is success, *not driven* is a configuration mistake, *floor
held* is a reason to wait.

There is deliberately no "not driven" among the write codes. Seeding a thread for a contact
ai_npc does not drive **yet** is the normal way to hand a conversation its starting point;
`AiNpcDrivesCharacter` is a separate question.

### The facade holds no logic

Every function in `api\AiNpcApi.reds` and every method on `AiNpcClient` is one delegating line.
A consumer taking ai_npc optionally mirrors this behind `@if(ModuleExists("AiNpc"))` and writes
the degraded half itself, so anything computed in the facade is something that mirror would have
to reimplement identically — and a divergence between two halves compiles, logs nothing, and
shows up in game as a bug somewhere else entirely.

### The export cut

Measured 2026-08-22: 66 files, 351 `public func`, 63 `public class`, of which one integrating
mod used about twenty-five. 351 exports is an accident, and the next integrator calls
`AiNpcClipText` because it was reachable.

Cut on 2026-08-28, from 712 top-level exports outside `api\` to 174. Two causes, and the second
was the bigger one: 264 declarations were exported for no reader at all, and 284 only because
the self-tests lived in a separate module and cross-module access needs `public` — so a file
deleted before release was deciding this mod's public ABI. The tests moved into `module AiNpc`
and an empty `AiNpcTestSuite.reds` took over the `ModuleExists` seam. `tools\lint.ps1` ratchets
the number.

---

## The cast

### One provider per contact, and no way around it

Two mods cannot both be right about who Rogue is. `RegisterCharacter` refuses a duplicate and
returns `false` rather than overwriting, so which mod wins never depends on load order.

There used to be a way around it — find the provider, unregister it, wrap it, put it back if
that failed. `AiNpcFindCharacter` existed for that dance and is gone, along with the dance: it
existed only because a contact had one slot, and contributions no longer collide. Wanting to add
to a contact somebody else declared is the normal case, and it has its own door.

Registrations last exactly as long as the session, deliberately: a stale provider outliving the
state it describes is worse than registering again. Conversations are not in that set — they
belong to the journal — so re-registering an id resumes where it left off.

### An extension may only carry what merges

A method joins `AiNpcCharacterExtension` **only if the rule for merging two mods' answers is
written in its contract.** That is why the class is short, and it is why the collisions are
*unsayable* rather than arbitrated.

There are three merge rules, and three is all there is:

| | | |
|---|---|---|
| concatenation | text fragments | everyone contributes |
| veto | permissions | anyone may remove one, nobody may grant one |
| exclusive turn | writing the reply | one holder — the floor |

`GetBio` is absent because two bios concatenated describe nobody. `GetSpeechStyle` is absent
because "relaxed, first names" and "formal, keeps V at arm's length" is not a character, it is a
contradiction, and no ordering rule fixes it.

The gig mod that has Rogue offer work and the Johnny mod that has her suggest a drink only
looked like a conflict because both went through the single provider slot, and the second lost
its whole contribution with nothing to show the player.

`CharacterAlsoIs` is the one exception that is not one: a bio and an addition to it are not two
bios. Whoever declared the character keeps theirs exactly as written.

### Ordering is alphabetical on purpose, and must stay meaningless

Contributions merge in ascending full id, never in registration order. That is not tidiness: the
attachment order of game systems differs between two loads of the same save, so ordering on it
would make the prompt change from one launch to the next — a bug nobody reproduces.

It is stable, and it is **alphabetical, not meaningful**: `johnny_leisure` merges before
`rogue_gigs` whatever the scene between them reads like. So never write a contribution whose
sense depends on running before or after somebody else's. Anything that would need to is not an
addition to a character, it is a disagreement about one.

Naming yourself to sort early buys nothing: fragments concatenate, the veto is order-free, and
two mods claiming one exact tag is reported as a collision before it is dispatched.

### `IsAvailable` and the floor are two questions

"Unreachable in the fiction" belongs to whoever declared the contact. "Busy with my scripted
exchange" is `TakeFloor`. Conflated, two mods could both suspend a contact without either
knowing.

The floor is a **lease, not a lock**. It expires lazily, on read — never on a `DelayCallback`,
which does not survive a save load — so a mod that crashes or is uninstalled mid-scene cannot
hold a character for the rest of the playthrough. Re-taking your own floor extends it, so a long
scene renews without releasing first and opening a gap somebody else can take.

`OnFloorAvailable` is offered to every extension on that contact in id order, so which one gets
it is the same on every machine and every replay.

---

## Commands

### One declaration is both halves

`pattern` is what the model is shown **and** what the dispatcher matches, so a command cannot be
advertised without being implemented, nor implemented without being advertised.

That is a repair, not an aesthetic. This lane used to live in four methods on the extension
class and, under different names, four more on the provider class; the two drifted. One veto was
read by nobody, and one consumer's fragment method never overrode anything and silently
advertised no commands for as long as the feature existed. See `PLAN_ACTION_LANE.md`.

| was | is now |
|---|---|
| `GetActionPromptFragment` | the `prompt` argument of `AddAction`, or `AiNpcActionHandler.GetPrompt` |
| `GetActionTags`, `GetActionTagPrefixes` | the `pattern` argument — one declaration is announcement and claim |
| `TryApplyAction` | `AiNpcActionHandler.OnAction`, returning a result that carries a note |
| `AllowsGenericTransfer` | `client.SuppressAction(AiNpcTransferHead(), tag)` |

They are **gone rather than deprecated**, and the signature break is deliberate: a removed
virtual method leaves an override compiling and silently doing nothing, which is exactly how one
consumer lost its whole rendezvous vocabulary. The compiler saying so is the migration.

### A handler is an object with one method

REDscript has no function values, so a callback is an object. A **wide** interface is one a
consumer silently half-overrides — get the method name wrong and you override nothing, with no
warning — so the interface stays narrow: `OnAction` required, `IsOffered`, `GetPrompt` and
`GetParameters` optional.

`GetParameters` is the second method of that shape, and it is separate from `GetPrompt` because
a slot definition is *shared* — two commands of one mod cite the same slot — and a sentence
cannot be. Folding them together put a slot's two halves a kilobyte apart, which is the
arrangement this replaced.

### The note is why a result is not a `Bool`

A refused command is otherwise invisible: the tag is stripped so the vocabulary does not leak
into the bubble, and the model has already written a message assuming it worked. The note is
handed to the character as something it knows for its next reply, so the refusal comes back in
that character's own voice instead of as a banner.

Leave it empty when the reason is outside the fiction — a permission a config file withdrew —
because the character cannot know that and would only invent an explanation.

### `scopeTag` has no default

An omission must narrow reach, never widen it. A permissive default is found by the player, in
play, on the day the model happens to emit the tag; a refused registration is found by its
author immediately. `AiNpcEveryContactTag()` is how *everyone* is spelled, and it is a decision,
spelled out, listed in the load report so a player can read who granted what to whom.

Tags are **flat**: the colon is a naming convention that keeps mods off each other's names, and
the comparison is on the whole string. There is no hierarchy and no `ainpc:*` — a shallow
hierarchy is already a set, and a wildcard would enrol tags created after the rule was written.

> **A tag is never omitted in order to remove reach.** If leaving one out could take a character
> out of somebody's rule, every tag added later would become one more thing every modder must
> remember to write, and forgetting it would silently break *other mods'* commands.

Tags only ever add; suppression only ever removes. Two levers, one job each — which is what lets
a behaviour be read without knowing which mods are installed. Suppression is **one-way** for the
same reason: nobody can grant back what a mod that took responsibility for a character's economy
removed.

### The offer governs the announcement, the claim governs the strip

Between building the prompt and reading the reply there is a network round trip, and `IsOffered`
can flip inside it. A claim that has stopped offering its command still **owns** its tag: the
tag reaches `OnAction`, is refused, and is stripped. Without that, a bracket leaks into the
player's chat every time a state changes mid-turn.

### `OnAction` must re-check and be idempotent

The prompt that advertised the command was built before V wrote, the offer may be gone, a model
can be argued into emitting a tag it was never shown, and the reply is replayed whole after a
network error. **Every field inside a tag was written by a language model: the arity is all the
dispatcher bought you.** Prefer clamping a number or snapping a name to a known one over
refusing, because a refusal costs the whole command.

### Why a file may only write `ainpc_` facts

The namespace is the design, not a precaution. A tag is a request from a language model, and a
language model can be argued into emitting anything; a file that could name any fact would let
one bracket write `q101_started` and take the playthrough somewhere the quest graph never meant
to go.

That is not a wall a serious mod meets: wanting to move real quest state means wanting to run
code when it moves, which is a script provider — and a provider has always been able to do
anything. **Data stays sandboxed, script stays powerful, and the line between them is one
prefix.**

---

## Statements, tickets and unprompted messages

### Why a ticket and not a `Bool`

The answer is not always known at the call. A contact with no conversation yet is normal to
seed, and the statement settles when that contact next speaks. In the ordinary case the ticket
comes back already resolved, so a caller who cares asks immediately and a caller who does not
ignores it entirely.

The verdicts are separated by **what a fallback should do**, not by how they feel:

- `Pending` is *treat as kept*. ai_npc records it the moment that contact's next prompt is
  built, which is before the reply it would have to be true for; a fallback here states the same
  thing twice.
- `Unknown` is **not a failure**. Resolved tickets live in a bounded ring, so an old id falls
  out of it. A mod reading this as "it did not work" announces to the player something that
  never happened.
- `Cancelled` is your own withdrawal. The author who withdrew did so because the moment had
  passed, and must not have their own fallback fire.
- `Refused` is the player having turned unprompted messages off. The question they answered is
  about *being written to out of nowhere*, not about who writes the words — so an authored SMS
  pushed in its place is the same thing they refused, arriving anyway from a mod that read the
  verdict as a technical hiccup. ai_npc cannot stop that (`CharacterWrote` sends nothing, and
  the notification is on the consumer's side): it is a rule, and `AiNpcMayWriteFirst()` is how
  you honour it before you even arm a trigger.

`Failed` is what is left, and it is the verdict a fallback answers.

### The motel that never happened

Measured 2026-08-22 in ai_npc_joytoys, and it is what produced `CharacterKnows(..., Forever)`.

A meeting was negotiated in the chat, the player walked to it, another mod ran the whole scene,
the client texted afterwards, V answered "that was good" — and the client replied that they had
never met and that he was still standing outside.

He was right to. The transcript held two intentions and two allusions and never one statement,
the appointment had just been cleared from the provider's `GetLiveContext`, and the fallback
line in `<now>` said *"there is no history between you, nothing to refer back to"*. A model
choosing between two allusions and one declarative sentence picks the declarative one.

`UntilForever` is not a bigger `UntilNextReply`. It is the only channel that can win an
argument, because the memory block opens with its own precedence clause:

> *Everything below is something you ALREADY KNOW. Never ask V about it again. Where your
> character description says you do not know something and this block does, **this block is
> right**: the description is how you began, and this is what has happened since.*

Nothing else in the prompt says that. `<now>` cannot: it means "now", and memory means "since".

The four rules in [API.md](API.md#tell-a-character-something-my-systems-know) fall out of that,
and the fourth is the one that bites later: a permanent fact cannot be taken back, so "it went
well" recorded on an encounter that went badly is wrong forever.

### The transient half is attributed, because it was not

With an anonymous write, a second mod seeding for the same contact erased the first — silently,
and both callers were told it had worked. `AiNpcUntilNextReply` now lands in a per-contact,
per-mod slot: restating replaces **your** line and leaves everyone else's alone, and what waits
is concatenated in id order. `ContextBudgetLeft` exists because a budget nobody can read
surfaces as "my mod misbehaves when others are installed".

### A reason, not a line

`CharacterWrote` takes text, and the text is then yours — one language, a voice that is not the
character's. That is right for an SMS your quest wrote and wrong for "she noticed V has gone
quiet", which the model writes better than you do, and writes in the player's language for
nothing.

The `intent` argument answers a different question from the reason: the reason is what just
happened, the intent is what she is trying to do while she writes about it. Three tiers, resolved
in `AiNpcIntentOf`: what you stated, then the tracked mission, then the character's durable
intent. Yours outranks the mission deliberately — the mission describes a life, your intent
describes an occasion. Without that, Panam mid-*Riders on the Storm* is told "nothing else
matters until Saul is out", and an unprompted message about anything else is one parenthetical
line at the end of the transcript arguing with a whole section of the system prompt. The section
wins.

**It can act, not only speak.** The reason lands where V's message would, so the command
vocabulary fires from it. A birthday reason produced `[ACTION:GIVE_EDDIES:1000]` unasked — the
character sent V money. That is the feature working, and it is why the advice is to state reasons
you would be happy for her to act on.

### There is no third policy

`AiNpcSayNow` is now or never; `AiNpcSayWithin(n)` queues and fails at `n`. **"As soon as
possible" with no bound is not implementable honestly**: you write the reason in the present
tense, so a reason delivered long after its moment is a message that argues with the game.

The window is in seconds **of play**, not of Night City — the city's clock runs some sixty times
faster, so a window in game seconds would lapse before the player finished reading. Same choice
as the floor lease, for the same reason.

The **debounce** — one minute between two unprompted messages on one contact — is not a
schedule. It does not decide when your character speaks, only how fast anything may, so that a
trigger firing in a loop cannot spend the player's daily quota in a burst. A window shorter than
what is left of it is refused immediately rather than queued: a wait that could never have
worked is not a wait worth making somebody sit through.

Every refusal is reported **on the ticket and nowhere else**. Nothing is written into the thread
because nobody is waiting for a message they never asked for, so an operator line there would
arrive out of nowhere and then come back in the next prompt as something that was said.

ai_npc holds no fallback for you, and the omission is deliberate: a fallback is your text, in
your voice. The shape that works is three tiers — ask for a generated line, fall back to an
authored one, and let the authored one be the floor that always exists.

### Nothing waits across a save load

The queue is thrown away with the session: the world on the other side of a reload is not the
world the reason was written about. Nothing is resolved on the way out, so a reloaded game
answers `Unknown` to a ticket from the session before.

Which means the idempotence is the caller's, and it is not free. A permanent fact is
de-duplicated on its exact text; a message is not, and a reason re-stated after a reload that
already went out before the save is a character saying the same thing twice.

---

## Prompt composition

### Three regimes, and the name says which

A block belongs to whoever owns what it states, and that decides how a mod reaches it:

| What the block states | Regime | Blocks |
|---|---|---|
| the mod's policy | **composed** by key | `<system_rules>`, `<interactions>` |
| the character | **replaced** whole | `<character>` (SPEECH included), `<relationship>`, `<intent>`, `<target>` |
| the moment | **added** to, with a budget | `<now>`, `<intent>` |
| the player's consent | **nothing** | `<explicitness>` |

In JSON the shape says it too: a string replaces, an object contributes.

`<explicitness>` has no lane at all — no contact override, no `prompts.json` key, no extension.
A mod rewriting it would answer a question that was put to the player. A character who does not
swear says so in its SPEECH rubric; a contact that is not a person says so in rubrics of its
own. The NCPD archive that answers Jackie's number does exactly that, with `NOT JACKIE`, `SCOPE`
and `REGISTER`.

### Why three rubrics refuse every contribution

`FORM`, `TIME` and `LENGTH` are not editorial: they describe the surface the reply lands on. One
message per turn, no `Name:` prefix, a length that fits a phone bubble, and the time markers
ai_npc writes and the model must only read. A contact that won those would break the player's
chat window, not its own characterisation. `PROMISES` is the fourth, in `<interactions>`, and it
is the one clause whose loss the player *sees*: a character promising to come and getting nobody
there reads as the mod being broken. A mod that can really stage a meeting rewrites `REAL` and
inherits the rest.

A key is upper-cased and trimmed before anything else, so `form` is the locked `FORM` rather
than a second rubric contradicting it from the line above.

The `guidelines` key that used to replace the whole block **is refused**, with an error at load.
Nothing can drop the block, reorder it, or silently lose a rule it never mentioned.

### Why a tag in configured text is refused

A `</system_rules>` inside a rubric ends the block early, and whatever follows can restate a
locked rule wherever it likes. The check is for closing tags and `<name>` shapes; `<3`, `->` and
`a < b` are prose and pass. It runs at **every** door — a provider getter, an override,
`facts.*.json`, `AiNpcSeedContext`, a world fact, an extension — because text from outside the
mod is a leaf of the prompt tree, and a leaf carrying a tag stops being one.

Over-budget text is refused **whole rather than clamped**: a section cut in the middle says
something its author did not write.

### Speech style, and why it is additive

A form of address stated once in `relationship` loses against a `MANDATORY` line in the rule
block, every time — a contact described as addressing V formally still answered with slang,
because the French language rule said characters use *tu*. Style stated as `speechStyle` lands
in the rule block itself, at the same weight as the rule it is meant to bend. The T-V distinction
is therefore a **default speech style per language**, not part of the language rule, so a
character can say otherwise.

It is also restated at the end of the prompt inside `<language>` — repetition is what makes a
register survive a long transcript. That second copy is dropped above 400 characters: a provider
may return a whole dossier from `GetSpeechStyle`, and a paragraph that long already dominates by
mass, so copying it only doubles the cost.

### Blocks are ordered by increasing volatility

Everything invariant comes first, then the memory (rewritten about once every ten turns), then
what changes on every single message.

OpenAI-compatible backends discount a repeated *prefix* from around a thousand tokens. The
in-game clock used to sit inside `<system>`, so the identical prefix ended around token 200 and
nothing was ever discounted. If you add a section, decide how often it changes and put it where
that answer says.

The closing `<explicitness>` stays last despite being invariant: it is a recency device, it is
one line, and everything after the cacheable prefix is uncached anyway. It carries a
prohibition, not a tier — a model drifts back towards saying less than it was allowed, never
more, so only level 1 closes the prompt with anything.

Every section is built **for a contact id**, which is the identity of a conversation throughout
the mod: the string the phone selected, stored verbatim, never reconstructed. A generation is
addressed once, when it is sent, and the reply, the history write and any action tags all go back
to that same id — so opening another contact while a character is still typing cannot move the
answer.

### The world block, and the two failures that shaped it

`worldBackground` is not a fact sheet — the facts are its bottom third. What the block is for is
a **posture**: how someone born here reacts to a subject nobody wrote a rule about.

- **LIVED** — nothing in the city surprises the character, who lives on a short horizon; the city
  does not move them, people do.
- **HOW IT SHOWS** — habituation shows in what is *left out*: no alarm, no lecture, no procedure,
  and **no remark about how this world works** — a local does not explain the local weather. Same
  shape as the `TIME:` rule: know it, never write it. A bad thing is still allowed to be bad.
- **CALIBRATION** — three wrong/right pairs, one of them on a subject no paragraph below covers,
  which is the pair that shows the posture generalises instead of looking things up.
- **BODY / VIOLENCE / SEX / ECONOMY / COST** — the facts, as the material that makes the posture
  plausible. `ECONOMY` states how power is arranged and says outright that it is **not a verdict
  on it** — V may be a corpo, Takemura is loyal to one, and an opinion stated here would outweigh
  every bio that disagrees.
- **NIGHT CITY** — the inverse of that ban: districts, places, corps, gangs, people and slang
  that exist **to be spoken**, for a model whose knowledge of the setting is thin. Setting detail
  of your own belongs in this rubric.

**The first failure**: a prompt that states no rule gets the model's own, and the model's own are
ours. Left unstated, characters hand out twenty-first century health advice — condoms, testing,
*be careful* — inside a setting that engineered the problem away. It is not a tone problem and it
does not respond to a stricter guardrail; the fix is to state the world.

**The second, which the first fix caused**: a world stated as declarative prose is a world the
model recites. Given *disease is a bill, not a fear*, it answers a friend in trouble with *that's
just Night City, you get used to it* — the instruction, paraphrased, which on a serious subject
reads as monstrous rather than as local colour. That is what the posture rubrics and the ban on
narrating the norm are for. **If you replace this section, carry that ban into your own text**,
or you inherit the recitation with the freedom.

`WORDS` is the only part of the block that changes with the language, and it is a table rather
than a translation: the game's own localisation kept some terms (eddies, choom, corpo, joytoy,
fixer, netrunner) and localised others, so French says *charcudoc*, *paumard*, *trait plat*,
*danse sensorielle* — and the French line names the English forms only to ban them. Adding a
language is one `case` in `AiNpcWorldLoreWords`; `tools\lint.ps1` pins the terms so a table
cannot silently fall back to English.

`RegisterWorldKnowledge` exists so a mod adding something *to* the city does not have to replace
all of that to say so. It is not an extension with an empty contact list, and the difference is
the regime rather than the audience: an extension speaks into `<now>`, which is budgeted per
message because several mods describing one moment drown the message V actually wrote. A standing
fact about the city is stated once, in the invariant half, and competes with nobody's account of
the moment.

### The tier constrains the model, never the corpus

`AiNpcChosenTone` states what the *model* may be asked to write. ai_npc does not gate its own
**authored** text on it: a hand-written line ships as written, because a corpus somebody wrote is
not a thing the mod second-guesses at runtime. A consumer using it to hide its own written
content is making a rule of its own — a defensible one, and not one inherited from here.

There is no setter, and there will not be one. A mod that could raise the tier could consent on
the player's behalf.

---

## The environment

### RedFileSystem revokes, and the sanction is global

`FileSystem.GetStorage("AiNpc")` is not an accessor, it is a claim of ownership. A second
claimant gets

```
Attempt to access storage "AiNpc" several times. Only one mod can access its own storage
with RedFileSystem. Access to this storage has been permanently revoked for this session.
```

and the storage is lost **for both mods** until the session ends. Measured 2026-08-19: ai_npc
lost its journal (every conversation read empty) and its `settings.json` (every request came back
`[NO SIGNAL: HTTP 0]`) because a companion mod had started opening the `AiNpc` storage of its
own. Nothing in the redscript log mentions any of it; the only trace is
`red4ext\logs\redfilesystem-*.log`, which is therefore the first file to open when a mod behaves
as though its files had vanished.

The message says "several times", so repeated calls from the *same* mod are a risk too. Opening
once in a `ScriptableService` and distributing the handle is the correct pattern, and
`AiNpcSharedStorage()` is that handle.

### `@wrapMethod` ordering, and the phone pass

REDscript applies `@wrapMethod` in compile order and the last one compiled is the outermost, so a
wrapper sitting inside another mod's never sees the entries that mod adds.

Not theoretical: the phone-contact pass originally lived in `r6\scripts\ai_npc\`, ended up inside
Phone Extension's wrapper, saw only the vanilla array, and did nothing at all — silently, because
"found nothing to repair" and "was never given anything" look the same.

It now ships in `r6\scripts\zzz_ai_npc_phone\`, whose name exists only to sort last. **Renaming
that folder reintroduces the bug.** A mod sorting after it would put us back inside — which is
why repair is automatic and injection is opt-in: the automatic half's worst case is "no change",
never "two rows".

### A journal listing must not replay

Listing used to replay every branch to count its conversations — several thousand JSON parses,
most of them for branches nobody was going to choose, before a window could draw its first row.
A listing exists to be scanned: `JournalBranchRows` reads a file's length and its last operation
and nothing else. The replay happens to the one branch somebody points at.

There is no Mod Settings entry for a journal pointer and there cannot be: Mod Settings has
booleans, numbers and dropdowns, and a pointer is text. The two ways in are the console and the
`importConversationsFrom` key in `settings.json`.

---

## Compatibility

### Additive only, once it ships

`@if` tests `ModuleExists` and nothing else — there is no way to compile against a version. A mod
built for a newer API running beside an older one raises `UNRESOLVED_FN`, and that fails the
compilation of *the whole game*, not of the offending mod.

So nothing is removed or given a different signature after release, and new parameters arrive as
`opt`. `AiNpcApiVersion` covers only what a runtime check can cover — behaviour changing at an
unchanged signature — since a missing function is a compile error that never reaches it.

The number is still 1 through the extension rework and through `CharacterWantsToSay` becoming
real: a version is for a consumer holding an older ai_npc against a newer contract, and nothing
has shipped, so moving it now would arrive at 1.0 already spent. It moves on the first release.

### Growing a virtual method's arguments

`opt` covers a free function; for a virtual method it does not. A consumer's override keeps the
old signature, quietly stops overriding, and ai_npc calls its own default — which compiles, logs
nothing, and reads in game as a feature that was never wired.

That is why `AiNpcContactContext` is one parameter rather than a growing argument list: a field
added to a class the consumer never constructs has none of those effects.

### The degraded half is never a stub that logs an error

"ai_npc is not installed" is a supported configuration, not a failure. Return the honest empty
answer and let the caller carry on.

And mirror the facade one function per function, with no logic in the mirror. Whatever the
guarded half computes, the degraded half has to compute identically.
