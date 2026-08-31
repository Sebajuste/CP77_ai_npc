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

---

## Measured in game, 2026-08-31: it works, and the window is two seconds

One conversation with Judy: two replies on `OpenRouter`, the third on `OpenRouterStream`.

```
20:02:04   the request leaves
20:02:11   first sentence delivered          +7 s
20:02:13   second sentence, then the end     +9 s
```

**The token trap is cleared.** The streamed reply carries its usage block —
`prompt_tokens: 4770`, `completion_tokens: 83`, `total_tokens: 4853` — so the daily cap and the
usage ledger see exactly what the classic lane gives them. The streamed block does omit `cost`,
which the classic one carries; nothing reads it (`AiNpcResponses.reds` takes the three token
fields and the cached count, and no more), so nothing is lost.

**And the window is two seconds, not the three the voice needs.** With a cloned voice at 1.4×
real time, a first sentence worth five seconds of audio costs about 3.5 s to synthesise: speech
would start around +10.5 s instead of +12.5 s. Streaming *moves* the wait; it does not hide it.

**Why, and it is not the transport's fault.** The first sentence delivered was 140 characters.
Seven of those nine seconds were spent writing that sentence, not waiting for the first token —
the splitter waits for a full stop, and the model writes long.

Two ways to widen the window, neither of which touches the transport:

- **split on more than a full stop.** A comma or a semicolon past a length threshold would cut
  the 140-character opening in two and hand the voice something to say seconds earlier. The
  splitter is pure and already under test, so this is a fixture and a threshold.
- **ask the model for shorter opening sentences.** That is a prompt change, and this project
  does not reword a prompt alone.

Measure again after either: the number that matters is the gap between the first sentence and
the complete reply, and it is written down here so the next decision argues with a figure rather
than a memory.

---

## Status, 2026-08-31: built, green offline, never launched

All four steps are in. Nothing below has been proved in game, and the last section of this brief
says exactly which claims a launch owns.

**The lane.** A fourth provider, `OpenRouterStream`, beside `OpenRouter` and not replacing it.
Same endpoint, same key, same model and routing preference, same request body -- only the pipe
differs. `RedHttpClient` is untouched and the default provider has not moved.

**Where each piece lives.**

| File | What it is |
|---|---|
| `plugin/Stream.cpp` | the SSE reader, the sentence splitter, the chunk reader and the assembler. Pure -- no RED4ext, no Windows, no socket -- and in `plugin/test/run.ps1` |
| `plugin/HttpStream.cpp` | WinHTTP: one POST whose body is read as it arrives, plus the cancel that lets the game close |
| `plugin/OpenRouterStream.cpp` | the lane: headers, the stream flags, the failures, and the measurement |
| `plugin/ScriptApi.cpp` | routes the provider name, and carries sentences and replies to the game thread in one ordered queue |
| `AiNpcStreamDeliver.reds` | the side channel's door in script |

**Traps.** All three are fixtures in `plugin/test/TestHost.cpp`: the usage block after
`finish_reason` (asserted on a stream fed one byte at a time), the `: OPENROUTER PROCESSING`
comment lines, and a stream that stops mid-reply -- which produces a 502 through
`HandleRequestFailure` rather than a truncated reply written into the thread.

**Two things this needed that the brief did not name.**

- The speech worker held ONE pending line and replaced it. Handing it the sentences of one reply
  would have kept the first and the last and dropped everything between, which makes step 4
  meaningless. It is now a bounded FIFO (`plugin/Speech.cpp`); `Speak()` appends instead of
  replacing.
- `Transport.hpp` said the plugin must never learn what OpenRouter is. It does now, and the head
  of that file says so and says why the streaming lane is deliberately not an `ITransport`.

**What the voice does with a sentence.** It speaks it when a call is connected, and otherwise
does nothing: the written surfaces are read, not heard. The call lane does not generate replies
yet, so in practice the audible half waits on the holo lane -- the sentences themselves arrive
and are logged either way, which is what the measurement needs.

**Where to read the number.** `red4ext\logs\ai_npc-*.log`, one line per streamed request:

```
request 1000003 streamed 5 sentence(s): first ready after 812 ms, whole reply after 4210 ms
```

That gap is the whole point of this work. If it is small, the model streams too coarsely for a
voice to hide inside it, and that is the result -- not a bug to go looking for.

**Offline, at the time of writing.** `plugin/test/run.ps1`: 241 checks, 0 failures.
`tools/compile-check.ps1`: clean, 0 warnings. `tools/lint.ps1`: all checks passed.
`plugin/build.ps1`: builds, 236.5 KB.
