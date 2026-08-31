# Brief: streaming the model's reply, so the voice arrives on time

A work order for one agent, working alone. Everything it needs is here; it has none of the
conversation this came from.

---

## Why, in one measurement

A cloned voice on this project's reference machine (RTX 4080 SUPER) synthesises at about **1.4×
real time**. A four-second reply therefore costs **three seconds of silence** before the
character starts speaking. That is the single most reported complaint against the comparable
Skyrim mods, and it would be ours by construction.

Cutting the finished reply into sentences helps a little. The real answer hides the synthesis
inside a delay the player is **already paying**: stream the model's output, and hand each
sentence to the voice as it completes. The first sentence is spoken while the model is still
writing the second, so the voice costs nothing the text lane was not already costing.

---

## The invariant that makes this safe

**Streaming is additive. The reply pipeline still receives one complete reply.**

Everything downstream — the action commands, the repair pass, the memory service, the write into
the thread, the surfaces — works on a whole text and keeps working on a whole text. The partial
deliveries are a **side channel for the voice** and for nothing else.

Any design where the existing pipeline has to understand fragments is the wrong one. If a step
seems to need it, stop and say so rather than widening the change.

---

## Where the client goes, and why it is not where you would first look

**Not `RedHttpClient`.** It is a request/response API that hands over a complete `HttpResponse`.
There is no partial delivery to be had from it.

**In `ai_npc.dll`**, because everything the job needs is already there:

- a worker thread, and a queue that delivers onto the **game thread** through RED4ext's `Running`
  game state — read the head of `plugin/ScriptApi.cpp`, the three rules at the top are the
  contract;
- `plugin/SettingsFile.cpp` already reads `settings.json`, so the API key needs no new path;
- **the speech worker is already in this process** (`plugin/Speech.cpp`). A finished sentence
  goes from the SSE parser to the synthesiser without crossing any boundary.

Use **WinHTTP**: it reads a response body incrementally and does TLS natively, so nothing new is
linked beyond `winhttp.lib`.

---

## The three traps, all documented, none obvious

1. **The token accounting arrives after the end.** Ask for
   `"stream_options": {"include_usage": true}`, and keep reading **past** the chunk carrying
   `finish_reason` — OpenRouter sends the usage block after it. A client that stops at
   `finish_reason` silently loses the numbers, and this mod has a usage ledger *and* a daily
   token cap that depend on them. (This is a real bug filed against litellm.)
2. **OpenRouter emits SSE comment lines** (`: ...`) to keep the connection alive. A parser that
   treats every line as JSON dies on them with "unexpected end of JSON input". Skip any line that
   is not `data: `. (A real bug filed against another client.)
3. **A stream can die mid-reply.** The speaking lane has a watchdog expecting one answer. A
   broken stream must produce a failure the lane already understands, not a silence — see
   `HandleRequestFailure` in `AiNpcHttp.reds` for the single exit every failed request takes.

---

## What to build, in order, and where each step can kill the next

### 1. The parser and the splitter, pure, and asserted offline

Put them in their own translation unit with **no RED4ext dependency**, and add it to
`plugin/test/run.ps1`. That file links only the non-RED4ext sources on purpose: it is what lets
half of this plugin be checked without launching the game. `plugin/Audio.cpp` is the pattern to
copy.

- an SSE reader: bytes in, complete `data:` payloads out, tolerant of split chunks (an event can
  arrive across two reads), of comment lines, and of `[DONE]`;
- a sentence splitter: deltas in, sentences out. Split on `.` `!` `?` followed by whitespace or
  end, with a **minimum length** so `M.` and `22h.` do not cut, and a mandatory flush at the end
  of the stream so the last sentence is never swallowed.

Assert both on fixtures: a stream cut mid-JSON, a comment line, a usage block after
`finish_reason`, an abbreviation mid-sentence, a reply with no terminator at all.

> **Kill:** if either needs the game to be asserted, the seam is wrong. These are text in, text
> out.

### 2. The request, delivering the whole reply and nothing else

Make the streaming request, accumulate every delta, and deliver **one** complete reply through
the existing path. No partial delivery yet.

> This is the step that proves the transport without touching a single behaviour. At the end of
> it the mod works exactly as before, over a different pipe.
>
> **Kill:** any difference in what the player sees. Same reply, same actions, same journal, same
> token counts — the usage numbers especially, since trap 1 lives here.

### 3. The partial channel

Deliver each finished sentence as it arrives, in addition to the final complete reply. The
redscript side gets the same plain global it gets today, called several times with the same
request id plus a "final" flag — **no new native class**. Read the head of
`AiNpcCliNative.reds` before considering one: every declared native type is one more line in the
error that stops *the game* from starting when a plugin fails to load.

### 4. The voice consumes it

The spoken side takes sentences; the written side keeps taking the finished reply. Nothing else
subscribes.

---

## Scope: what this brief does not authorise

- **Do not remove `RedHttpClient`.** Moving the whole lane into the DLL would drop a plugin
  dependency, which is a real gain and a separate decision. This work sits **beside** the
  existing transport, selectable, and off by default until it has been measured against it.
- **Do not touch the surfaces, the store, the memory service or the action lane.** If a step
  needs one of them, the invariant above has been broken.
- Do not implement the speech side beyond handing sentences to the existing worker.

---

## How you know it worked

- **Offline**: `plugin/test/run.ps1` green, including the new fixtures. `tools/compile-check.ps1`
  green with **your own `-WorkDir`** — the default is shared and collides with other agents.
  `tools/lint.ps1` green.
- **In game, and only the user can do this**: a reply arrives identical to before, the daily
  token count moves by the same amount as a non-streamed reply, and the log shows sentences
  delivered before the reply completes.

The number worth writing down is **the delay between the request leaving and the first sentence
being ready**, compared with the delay to the complete reply. That difference is the whole point
of this work, and it is what tells you whether the voice can hide inside it.

---

## Constraints, not negotiable

Read `../CLAUDE.md` (the `CP77_mods` one) first. What bites here:

- **Never deploy.** Build the zip with `tools/package.ps1`; the user installs through Vortex.
  Never write into `D:\Jeux\Cyberpunk 2077\`.
- **Never block the game thread.** Rule 1 at the top of `plugin/ScriptApi.cpp`. A network read
  on the game thread is a frozen game.
- **Encoding**: UTF-8 without BOM. Never `Get-Content` → `Set-Content` on an accented file.
  Replies contain French text; a mangled byte filed once poisons a contact's history for good —
  see `AiNpcUtf8`.
- **Never kill a process by image name.** Track the PID you started.
- **Work in your own git worktree.** No bare `git stash`: the stack is shared.

## What must not be claimed

That it works, before a launch. Offline proves the parser and that it compiles — never that a
reply arrived, that the tokens were counted, or that a sentence reached the voice. And if the
measurement in the last section shows the first sentence is not meaningfully earlier than the
whole reply, say that: it would mean the model streams too coarsely for this to buy anything, and
that is a result worth having.
