# Plan: the robustness pass before 1.0

Written 2026-08-26 from a static analysis of the whole tree (metrics on code only, comments
and string literals excluded) and a read of the five pipelines end to end. This document is
the brief for the agent that will do the work: what is wrong, **why it is wrong**, the shape
the correction has to take, and what must not be touched.

Nothing here is a bug report to be closed. Each item names a cause that lives somewhere
specific, and the correction goes to that place.

## How to work on this

The two rules from `CP77_mods/CLAUDE.md` decide every judgement call below, so they are
repeated here in the form they take for this particular work:

**No fix.** Not one of these items is to be closed by a guard bolted onto the symptom. A
`if (thing_is_null) return;` in front of a dereference, a boolean added beside a boolean that
already exists, a special case for the one input that broke — all of these make the next
reader's job harder and leave the cause in place. When a correction wants to restructure,
restructure. When the clean correction turns out to be larger than this document assumes,
**say so to the user instead of shrinking it into a patch**.

**One file, one responsibility.** Item F below adds a concept. A concept is a file.
Do not append it to the bottom of the nearest existing file because that is where the caller
happens to live.

**No recursion.** Loop with an explicit queue and a visited set. This matters for item D,
which is about a recursion that must remain impossible.

Also true, and cheaper to read here than to rediscover:

- REDscript has no `continue` and no `try`/`catch`. Restructure with nested `if`/`else`.
- Indexing the result of a call reads empty. `Foo()[0]` compiles, warns nothing, and yields
  nothing. Assign to a local first.
- `.reds` files are UTF-8 **without BOM**. Use Edit, or Python with
  `io.open(..., encoding="utf-8")`. Never `Get-Content` → `Set-Content`.
- `tools/compile-check.ps1` shares a work directory between concurrent runs. Pass your own
  `-WorkDir`, or a peer agent's run will fail with a message that blames the game install.
- Several agents share this working tree. Check `git status` before believing that something
  you did not write is your own doing.
- **Never deploy.** Build the zips with `tools/package.ps1`; the user installs them in Vortex.

### What "done" means

Each item carries an acceptance check. They are checks, not descriptions: each one is a thing
that can come back false. If a check cannot fail, it is not a check — rewrite it before
claiming the item.

Run `powershell -File tools\test.ps1 -WorkDir <your own>` before and after. It is green today;
it must be green after, including the release-shape compile and the C++ suite.

## The state of the code, so the pass is not over-scoped

Measured, not impressions. This is a healthy tree and most of it should be left alone.

| | redscript | C++ |
|---|---|---|
| files / SLOC | 110 / 17 538 | 20 / 2 409 |
| SLOC per function, median / p90 / max | 6 / 25 / 126 | 15 / 46 / 114 |
| cyclomatic complexity, median / p90 / max | 2 / 6 / 30 | 2 / 10 / 21 |
| functions above CC 10 | 1.4 % | 9.1 % |
| duplication, 8-line window | 8.4 % | — |
| average fan-out | 3.2 | — |

The duplication is almost entirely `cast/` character sheets, which are declarative data, not
copied logic. The high-CC functions in `plugin/` are flat dispatches of named error cases at
depth 2–3 — that is good code, and **CC is the wrong lens on it**. Do not "simplify" them.

Two structural facts are worth knowing but are **not part of this pass**, and must not be
started as a side effect of it:

- ~~`AiNpcTests.reds` is 3 098 SLOC and 113 functions in one file.~~ **Fait le 2026-08-29** :
  les assertions sont reparties en treize fichiers par sujet sous
  `src\r6\scripts\ai_npc\tests\`, et `package.ps1 -Release` laisse tomber le dossier
  au lieu d'une liste de noms -- un fichier de test ajoute ne peut plus partir chez le joueur.
- The `AiNpcMemory.reds` cluster holds 6 of the 20 most complex functions and is the only
  place where complexity and nesting rise together. It is also the code with the best test
  coverage in the tree. Leave it alone until something is actually wrong with it.

---

# The items

What is left. D is a hazard held off by convention; F is the contract that stops being
changeable at 1.0; G is a decision to take. The items closed by the pass are listed under
"What has been done" and their briefs are gone — git has them.

## D — The template expander's re-entrancy is prevented only by comments

**Where** `AiNpcPromptSections.reds:631` (`AiNpcExpandTemplateFor`), and
`AiNpcTemplate.reds` (`AiNpcExpandTemplateWith`).

**What was measured** The substitution itself is single-pass and safe: a value substituted in
is never re-scanned. The hazard is upstream — the *values* are gathered by calling into code
that may itself expand a template. Two comments in `AiNpcExpandTemplateFor` say which sources
are safe (`AiNpcGenderStatement`, `AiNpcDefaultSpeechStyle`) and which must never be used
(`AiNpcGetSpeechStyle`, `AiNpcGetCharacterName`), because those come straight back in.

**The consequence** The day someone assigns `vars.register = AiNpcGetSpeechStyle()` — which
reads as an improvement — the result is unbounded recursion inside prompt construction, and
the symptom is the game dying with no message that names this file. The invariant is load
bearing and the compiler cannot see it.

**The cause** A rule enforced by prose. It also breaches the no-recursion rule of the repo,
in the only way that rule can be breached without a recursive call being visible.

**The shape of the correction** Make re-entry impossible rather than inadvisable. The
expander refuses to run inside itself: it takes note that a gather is in progress and, if
asked again while it is, returns the text untouched and says so once in the log. That is a
few lines, it is checkable, and it converts a crash into a visible placeholder — which is the
right trade for a prompt fragment. Keep both comments: they still explain *why* the guard
exists, and they are the reason the next reader will not delete it.

Do not attempt this with a recursion depth counter that allows one or two levels. There is no
legitimate nesting here; allowing some would make the rule fuzzy and the bug intermittent.

**Acceptance**
- A test calls the expander with a variable source that re-enters it and asserts the call
  returns, and that the offending placeholder is left as written.
- `tools\prompt` still rebuilds a real prompt byte-identical to the shipped one
  (`test.ps1` already runs this check — it must stay green, which proves the guard costs
  nothing on the normal path).

## F — The public API is the one thing 1.0 freezes, and it is the untested half

**Where** `src/r6/scripts/ai_npc/api/`, plus `AiNpcClientRegistry.reds`, `AiNpcFloor.reds`,
`AiNpcConversationApi.reds`, `AiNpcJournalApi.reds`.

**What was measured** 56 of 107 non-test modules have at least one top-level symbol reached
by the offline suite. The unreached half is mostly the UI layer, which is expected and fine.
It also contains the entire public façade: `AiNpcApi.reds` alone declares 23 free functions,
none of them named anywhere under `tests\`. The machinery underneath — floor leases,
tickets — *is* covered.

**The consequence** The façade is the surface other mods compile against. After 1.0 its
signatures and its refusal behaviour cannot change without breaking installs. It is the only
part of the tree where a mistake becomes permanent, and it is the part nothing asserts.

**A second fact, same place** Third-party extensions and listeners are invoked synchronously
during prompt construction (`AiNpcExtensionRegistry.reds`), and REDscript has no `try`/`catch`.
A badly written extension does not degrade the mod, it stops the prompt from being built.
There is a per-extension `<now>` budget for contributed context, which is the right idea
already applied once — the remaining exposure is what an extension *does*, not how much it
says.

**The shape of the correction, and its limit** Write the tests. Every function in `api/`,
asserted for what it answers when the world is normal **and when it is absent** — no session,
unknown contact id, empty string, a contact that opted out. That second half is the whole
point: the façade's refusal behaviour is its contract just as much as its return type, and it
is currently defined by whatever the implementation happens to do.

Do **not** redesign the API in this pass. If a test reveals a signature that is wrong, stop
and report it to the user — changing the extensibility contract is a decision that belongs
with the joytoys repo, where the spec lives, and not to this brief.

For the synchronous-call exposure: state it in `docs/API.md` as what it is — an extension
that throws takes the prompt with it — and leave it. REDscript gives no containment mechanism,
so any "protection" written here would be theatre.

**Acceptance**
- Every free function declared in `src/r6/scripts/ai_npc/api/` is named by at least one
  assertion in the suite.
- Each of those functions has at least one assertion for its behaviour with an unknown or
  empty contact id.
- `docs/API.md` states the containment limit.

## G — No automated gate

**What was measured** `tools/lint.ps1`, `compile-check.ps1`, `package.ps1` and
`plugin/test/run.ps1` are unusually thorough — single source of truth for the version, a
recursive credential scan, the FOMOD XML parsed on the *staged* copy, every `<folder source>`
checked to exist, the zip re-opened and inspected after compression. Nothing triggers any of
it. There is no workflow file for this project (the two under `vendor/` belong to the
RED4ext SDK).

**The consequence** Every guarantee above holds only for the runs somebody remembered to
make. In-game results are additionally a replayed cache file, so a green `test.ps1` can be
reporting a run from days ago.

**The shape of the correction** This is a decision for the user, not for the agent. Report it
and ask; do not add CI on your own initiative, and above all do not weaken any existing check
to make one pass.

## H — Accepted as they are

Recorded so the next reader does not open them again believing they were missed.

**The plugin's job queue is unbounded and has no cancellation.** `ScriptApi.cpp:370` always
accepts; one worker drains it serially at up to 180 s per job. A request whose script-side
watchdog already fired still runs to completion and still costs a subscription call.

*Resolution:* bound the queue and let `Send` return `false` on overflow — script already
treats `false` as "the transport refused it" and reports it correctly, so this needs no new
surface. Do **not** add a cancellation channel: it means a second native entry point, and
`AiNpcCliNative.reds` records what each declared native costs on the day the DLL fails to
load — one more line in a script-validation error that stops the game from starting. The
residual (a timed-out request finishes and is discarded) is accepted for 1.0.

*Status:* the queue bound is worth doing in this pass. The residual is not a defect to fix.

**`settings.json` is re-read on every request from the worker thread** while script may be
rewriting it. The share mode permits a torn read; the parse then fails and the settings fall
back to defaults, which means "look on PATH" — usually correct, and never wrong in a way that
loses data. *Status:* accepted. Not worth a lock across a process boundary.

**`cmd.exe` command lines refuse an embedded quote but not `%`.** `Process.cpp` refuses a
line containing `\"` before routing a `.cmd` shim through the command processor, and explains
why. `%VAR%` is still expanded by cmd at parse time. It cannot break out of the quoted region,
so it substitutes a value, it does not start a command. *Status:* accepted; note it in the
comment that already discusses the two-parser problem, so the next reader knows it was
considered rather than missed.

**`src/archive/pc/mod/ai_npc.archive` is a build product under version control** that
`package.ps1` rewrites on every run, so it shows as modified after every packaging.
*Status:* accepted. It is 20 KB and it guarantees the shipped icon matches the atlas; the
alternative is a build step every contributor must be able to run.

---

## What has been done

- **A — a late HTTP answer delivered as the current one.** The HTTP transport now carries a
  serial and checks it at every entry point, as the CLI one already did.
- **B — a second generation started on top of the first.** The refusal moved into the lane,
  out of the three UI files that were each keeping it.
- **C — two delay callbacks dereferencing a system that may be gone.** They check like the
  three watchdog callbacks always did.
- **E — three unchecked returns in the plugin.** Both job assignments and the scratch
  directory now report their failure instead of losing a guarantee in silence.
- the queue bound of item H, with them.

All of it is green offline and **none of it has been launched**: the acceptance checks that
need a live ScriptableSystem cannot be expressed in this harness, which runs its tests before
any system exists. Those two are named in the report rather than faked here.

## Suggested order

D, then G's decision, then F. F is the largest and is pure addition — no production code
changes, so it cannot destabilise the rest.

Report back with: what changed, what each acceptance check says now, and anything you found
that this document got wrong. The last part is not politeness — this brief was written from a
static read, and a static read is exactly the thing that misses what only running the code
shows.
