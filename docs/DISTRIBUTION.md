# Which lanes may be shipped, and to whom

Researched 2026-08-25 against the primary sources. `ARCHITECTURE.md` § 4 says how the three
lanes work; this file decides which of them may be put in a player's hands, and why.
Nothing here is legal advice -- it is a reading of the published terms, with the citations, so
the next reader can check it rather than re-derive it.

## The frontier is not where it looks

Two questions get conflated, and separating them is the whole content of this file:

**"Is it coding or gaming?"** is not the question. No clause anywhere says the output of a
coding CLI must be code. Chasing that reading produces a wrong answer in both directions.

**The questions that decide it are:**

1. **Whose credentials, and does the mod touch them?** Every provider draws a hard line at
   intermediating somebody else's account -- shipping a key, proxying, capturing a session
   token.
2. **Did the provider write an exception for third-party products?** One of them did. The
   other did not, and that asymmetry is the entire difference between the two CLI lanes.

The mod spawns the published binary and never sees the token. That single architectural fact
is what puts the Claude lane on the right side of the line -- and it is precisely what OpenClaw
did the other way in April 2026, when it replayed OAuth tokens inside its own harness and
Anthropic cut it off.

## The three lanes

| lane | develop / debug | ship to a modder | ship to a player |
|---|---|---|---|
| **OpenRouter** | yes | yes | **yes** -- the only one |
| **Claude Code** | yes | yes | permitted on the mechanism, with a reserve on quotas |
| **Codex** | tolerated, not conforming | same | **no** |

### OpenRouter -- clean

Each player brings their own key; the mod intermediates nothing and resells nothing. Its terms
forbid *"reselling API access to Models"* and *"developing a competing service"*; neither
applies. Crucially it says **nothing about the purpose of use** -- it is a general inference
API, so roleplay is an ordinary use of it, and there is no coding-tool framing to be excused
from.

Two things it does not settle. **Content** is deferred to each model's and provider's own
terms, so the safe-for-work question is per-model, not per-lane. And OpenRouter accepts
accounts **from 13**, which makes the 18+ notice ours to give, not theirs.

### Claude Code -- explicitly permitted, with conditions

<https://code.claude.com/docs/en/legal-and-compliance> has a section titled *"Can customers
offer Claude Code in their products?"*. It answers yes, subject to four conditions:

| condition | where we stand |
|---|---|
| the binary must not be modified, and its auth methods not removed or restricted | met -- the plugin spawns `claude` as published |
| no paying for, reselling, or intermediating usage on end users' behalf | met -- no credential ships |
| no collecting, storing or intermediating Claude.ai credentials or session tokens; sign-in completes through Anthropic's own flow | met -- the CLI owns its auth |
| agree to the Commercial Terms of Service | **open** -- declarative, not yet done |

And the sentence that settles the player's side outright:

> *"Nor does it prevent an end user from signing in to the unmodified Claude Code binary with
> their own Claude subscription."*

**The clause that decides it is about billing, not about coding.** The same page's
*Authentication and credential use* section is the strongest text against this lane, and it is
what makes the lane legitimate once read to the end:

> *"OAuth authentication is intended exclusively for purchasers of Claude Free, Pro, Max, Team,
> and Enterprise subscription plans and is designed to support ordinary use of Claude Code and
> other native Anthropic applications."*
>
> *"Developers building products or services that interact with Claude's capabilities … should
> use API key authentication … Anthropic does not permit third-party developers to offer
> Claude.ai login into their own applications, or to route requests through Free, Pro, or Max
> plan credentials on behalf of their users."*

The line is subscription versus API, and it turns on four words: **on behalf of their users**.
Nothing is routed here. The plugin spawns the published binary on the player's own machine,
under the player's own sign-in, for that player, and the usage bills to them. The sentence
quoted just above is that same section's own carve-out, two paragraphs further down it.

**The reserve is on finality, and it is one sentence.** The same page's *Acceptable use*
section says advertised Pro/Max limits *"assume ordinary, individual usage of Claude Code and
the Agent SDK"*. A mod generating NPC dialogue turn after turn is individual; it is less
obviously ordinary usage of a coding agent. That is a quota lever Anthropic holds over the
player's account -- not a bar on distributing the mod.

**Trademark.** The page allows saying in plain text that a product runs Claude Code. It
forbids the Claude or Anthropic name in a product or feature name, in a logo, or in any way
suggesting endorsement. **This has not been audited against the Mod Settings labels.**

### Codex -- no carve-out exists

OpenAI's consumer Terms of Use, under *What you cannot do*, forbid *"Automatically or
programmatically extracting data or Output"*. That is `codex exec` plus stdout parsing,
exactly, **whatever the purpose** -- the mechanism is what is named. No OpenAI page carves out
an exception for third-party products; the absence is not a permission.

**Read directly 2026-08-27**, in the EEA version, which is the one that governs here. The
wording above is verbatim from it, and two neighbouring clauses settle the two objections
usually raised against this reading:

- **The EU interoperability argument does not reach it.** The bullet on reverse engineering
  carries an explicit reservation -- *"(except to the extent this restriction is prohibited by
  applicable law)"* -- and the extraction bullet does not. The reservation was written where
  OpenAI meant it, and omitted where it did not. Reading a stdout is also not decompilation:
  nothing is taken apart here, a service is consumed through its own client.
- **Circumvention is named separately**: *"Interfering with or disrupting our Services,
  including circumventing any rate limits or restrictions"*.

The one argument that survives is the framing: the list is introduced by *"You may not use our
Services for any illegal, harmful, or abusive activity. For example, you are prohibited from"*,
so the bullets can be read as illustrations rather than an independent enumeration. It is
arguable. It is not solid, and it is not something to put in an installer.

Two traps worth recording:

- **The Services Agreement is the wrong document** for a player. It scopes itself to
  *"OpenAI's services for businesses, enterprises, or developers"*. It binds you if you take an
  API or Business contract; it does not govern a ChatGPT Plus subscription. (Its section 3.3
  is still worth reading for intent: (f) bars extracting data other than as permitted, (i) bars
  *"configuring the Services to avoid Usage Limits"*.)
- **`codex login` working is a capability, not a permission.** The technical ability to
  authenticate says nothing about the licence to drive the result from a program.

This also means the developer lane is not spotless: driving `codex exec` from the mod to debug
it is the same extraction clause. Tolerated in practice, non-conforming on paper. Say so rather
than pretending otherwise.

## What follows

**Ship OpenRouter to players.** Keep the two CLI lanes as developer lanes and never promote
them. A clean split between "player lane" and "dev lane" documents in one sentence; a
per-provider special case has to be re-explained at every release.

**Do not re-add a direct Anthropic or OpenAI API lane as the compliance answer.** OpenRouter
already is it, and it resells both at list price to the cent (`claude-sonnet-5` is 2.00/10.00
on both sides -- checked 2026-08-25), so a direct lane buys the player nothing on cost either.
The `OpenAI` lane was removed for product reasons; see `ARCHITECTURE.md` § 4,
"The CLI lanes are subscription-only".

**Done 2026-08-25, rebuilt 2026-08-27, in the installer and in the file that outlives it.**
`fomod/ModuleConfig.xml` asks WHO IS INSTALLING rather than which lane is best: "I am here to
play" against "I am writing an add on for AI NPC". An option marked recommended among three
still reads as one of three ways to play; an identity does not. The developer lane then costs
two more pages, in this order: the warning ALONE, as a question whose safe answer is first and
preselected, so accepting is an act and declining lands the player back on OpenRouter; then
instructions only, one page per lane.

**The installer offers no Codex option, and the reason is engineering, not licensing.** The
mod does offer that lane in Mod Settings and in the CET window, so "we may not invite people to
it" cannot be the reason: those are invitations too, only later ones. What holds on every
surface is that the warning travels with the lane, in the same words. What the installer asks
in addition is that a lane has been seen working in the game at least once, and Codex has not:
no preset in `package.ps1`, no run in game, its safe-for-work tier unmeasured. That is a
sufficient reason on its own, it is true, and it does not have to borrow authority from a
clause. It also says exactly what would reopen the question. `src/AI NPC - read me.txt` repeats it, because the installer screen
cannot be reopened and Vortex renders its links as dead plain text.

**The wording must not be simplified into "the licence forbids it".** It does not, for Claude:
Anthropic permits an end user to sign in to the unmodified binary, which is what the plugin
does, and claiming otherwise in a shipped installer would be both false and a contradiction of
the position that keeps the lane legitimate. What both texts say instead is true of both
providers: the plans' limits assume ordinary individual use, OpenAI's terms are stricter still,
and either provider may act on the account. Restricting the lane to developers is our product
decision, not a licence obligation, and it does not need to borrow authority it does not have.

Still open, none of them code:

1. accept Anthropic's Commercial Terms of Service;
2. audit the Mod Settings labels and the release page against the trademark rule;
3. an 18+ notice (OpenRouter accepts accounts from 13; the notice is ours to give);
The in-game switch was the fourth, and it is closed. Two surfaces, both fed from one string
each so the wording cannot drift apart:

- **Mod Settings** -- `AiNpcSystem.aiModel`'s `displayValues` name the lanes for what they are
  for ("Claude CLI - mod authors only"), and the option's description carries the warning. The
  label matters more than the description here: a dropdown is read as a list of labels.
- **The CET Setup tab** -- `AiNpcSetup.DescribeProviders()`, which the window renders verbatim
  (`init.lua` builds its buttons from the first word of each line, so the warning rides on the
  lane's own line and blank lines are skipped by both the window and `tools\lint.ps1`). Each
  CLI lane states it separately, in the same words, so neither reads as the exception.

## Sources

- <https://code.claude.com/docs/en/legal-and-compliance> -- read in full; the decisive page
- <https://www.anthropic.com/legal/consumer-terms> -- the general bar on *"automated or
  non-human means"*, from which the page above is the explicit carve-out
- <https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan>
  -- Agent SDK credits, **paused 2026-06-15**; the billing question is still open upstream
- <https://cdn.openai.com/osa/openai-services-agreement.pdf> -- read in full; scope and s. 3.3
- <https://openai.com/policies> -- the consumer Terms of Use, **EEA version, read in full
  2026-08-27**. Which version applies depends on where you live and the site serves it
  accordingly, so reach it from that index rather than by a remembered slug. `openai.com` and
  `help.openai.com` return 403 to our tooling: this one was read in a browser and pasted back,
  and that is the only way to re-read it
- <https://openrouter.ai/terms>
- The OpenClaw episode, for the shape of the line:
  <https://www.theregister.com/2026/04/06/anthropic_closes_door_on_subscription/> and
  <https://venturebeat.com/technology/anthropic-reinstates-openclaw-and-third-party-agent-usage-on-claude-subscriptions-with-a-catch>
