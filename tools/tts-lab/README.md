# tts-lab — calibrating the voice, from the best rendering down

**Not a search for a winner.** Every engine is run on this machine, from the best rendering to
the worst, so that the ladder can be measured rather than argued — and the mod ends with
**presets**, chosen by what the player's machine can do. A build with a 4080 and one with an
integrated GPU do not get the same voice, and the only way to say what each gets is to have
measured both ends here.

That is the same shape as the model lanes: one dimension, several tiers, a default that works
everywhere and better options for those who can run them.

Outside the game, on purpose. What decides here is an ear and a stopwatch, and neither needs
Cyberpunk to be running. The mod already plays whatever buffer it is handed
(`plugin/Audio.cpp`); what this answers is what should fill it.

**Every run records the machine it ran on** — CPU, cores, GPU, VRAM — into `out/results.json`,
appended rather than overwritten. A table of timings without the machine that produced them says
nothing about the machine in front of the player, and a preset is exactly a pairing of the two.

Nothing here ships. `tools/` is development tooling — see the table in `CLAUDE.md`.

---

## The questions, in the order that lets you stop

Each one can kill the next. Do them in order.

1. **Does a CPU engine speak acceptable French, faster than real time?**
   If no, the whole "local voice" branch is dead and the answer is a cloud service or nothing.
   Nothing about timbre matters yet.

2. **Does the timbre converter run on that output, on CPU, inside the budget?**
   The converter is the part that makes it Judy rather than a narrator. OpenVoice's converter is
   documented at under 100 ms per utterance and 3–5× real time on one core; this is where that
   claim meets this machine.

3. **Does it sound like her?**
   No metric. Listen to the `.wav` files.

### What question 2 turned out to be

The first plan was Piper plus a tone-colour converter: cheap words, cloned timbre. The
arithmetic worked — `1/13 + 1/4` of real time — and it answered the wrong question. **A
converter changes timbre, not prosody.** Piper's delivery is flat, and converting it to Judy's
timbre yields a robotic Judy. Heard on 2026-08-31, and it is why the ladder starts at the top
now: intonation comes from model capacity (Piper ~20M parameters, XTTS a few hundred, Zonos
1.6B), not from a stage bolted on afterwards.

### The tiers

| tier | what it is | what it needs |
|---|---|---|
| `cloné` | the character's own timbre, prosody generated | a GPU, and a local server |
| `neuronal` | generated prosody, generic voice | CPU only |
| `recollé` | recorded fragments, prosody from rules | nothing at all |

A local server is addressed over HTTP — the shape XTTS and Zonos both take, and SkyrimNet's
design. The API is not guessed: copy `server.example.json` to `server.json` and describe it
there.

The number that matters throughout is **time to first sound**, not total time. A reply that
starts speaking in 400 ms and finishes in four seconds beats one that appears whole in two —
the player is waiting for the first syllable, not the last.

---

## What is measured

For every line and every engine:

| column | meaning |
|---|---|
| `first_ms` | wall time until the first audio byte exists. The one that matters. |
| `total_ms` | until the utterance is complete |
| `audio_s` | how long the result plays for |
| `rtf` | `audio_s / (total_ms/1000)` — above 1.0 is faster than real time |

`first_ms` equals `total_ms` for an engine that has no streaming. That is not a flaw in the
measurement, it is the fact being measured.

---

## Running it

```
python tools\tts-lab\lab.py                 # every engine that is installed
python tools\tts-lab\lab.py --engine sapi   # just one
```

**SAPI needs nothing installed.** It goes through PowerShell's `System.Speech`, which is part of
Windows, so the lab runs on a bare machine and has a reference to compare against — the voice
the mod speaks with today.

Everything else needs models, and downloading a few hundred megabytes is the user's call, not
the agent's:

```
powershell -File tools\tts-lab\fetch.ps1 -Piper
```

## The lines

`lines.json`, and they are deliberately not "testing one two three". A real reply carries
apostrophes, slang, a number, and a length that no demo sentence has. An engine that handles
*Bonjour* and stumbles on *T'as qu'à passer, j'suis à l'atelier jusqu'à 22h* has not been tested.

## Measured, 2026-08-31

SAPI (Windows, concatenative) against Piper `fr_FR-siwis-medium` (neural, CPU), on the six
lines of `lines.json`.

| line | audio | piper `infer_ms` | piper rtf |
|---|---|---|---|
| court | 1.3 s | 97 | 13.0 |
| elisions | 3.6 s | 254 | 14.1 |
| nombre | 2.9 s | 223 | 13.2 |
| argot | 4.8 s | 361 | 13.3 |
| longue | 12.3 s | 936 | 13.2 |
| question | 2.9 s | 198 | 14.5 |

**Question 1 is answered: yes.** A CPU engine speaks French at **13× real time**, steadily,
whatever the length. A reply of the size this mod actually produces — three to five seconds of
speech — costs **200 to 360 ms of model time**. That is not close to a budget; it is a tenth of
one.

It also settles the next question before it is asked. OpenVoice's tone-colour converter is
documented at 3–5× real time on one core. Two stages in series cost `1/13 + 1/4 ≈ 0.33` of
real time — still **three times faster than the speech is spoken**. The two-stage pipeline is
arithmetically viable on CPU, on measured numbers rather than hope.

**Read the columns as they are meant.** `first_ms` and `total_ms` are cold: a process launched
and a 63 MB model loaded for one line. The mod will not do that — SkyrimNet's design, a resident
local service, is exactly the thing those columns are not measuring. `infer_ms` is the model
alone, published by the engine, and it is what a resident process costs.

`first_ms` equals `total_ms` for Piper here because `--output_file` writes everything at the
end. Piper can stream with `--output_raw`, and on the 12-second line that is the difference
between speaking after 936 ms and speaking after the first clause. Worth doing before the
converter, because it is the number the player feels.

## The `cloné` tier: Zonos

SkyrimNet drives Zonos over HTTP at `localhost:7860`, using the Windows fork
[langfod/Zonos](https://github.com/langfod/Zonos). Its requirements are hard ones: **Python
3.12, the Visual Studio x64 C++ build tools, and an NVIDIA GPU with 6 GB or more** — Ampere and
older are not supported, Ada and Blackwell are.

### Install (the user's, not the agent's)

1. Take the fork, unzip it.
2. `1_Install.bat` — it builds its own virtual environment and pulls torch and the model.
3. `2_Start_Zonos.bat` starts the fork's Gradio UI on 7860. Useful to prove the install works;
   the bench does not use it.

### Why the bench brings its own server

That fork exposes a Gradio interface and a Python API, and **no REST endpoint**. Driving Gradio
from a bench means binding to a graphical interface — function indices, session hashes, audio
returned as URLs. `server/zonos_server.py` is sixty lines around the Python API instead, and it
gives three things Gradio would not:

- **the speaker embedding is computed once per reference clip and kept.** That is the "clone
  once per NPC" question, answered where it is actually true: encoding the reference voice is
  never paid again. Generation still is, and no cache avoids that.
- **the conditioning parameters are discovered, not guessed.** The exact names for emotion,
  speaking rate and pitch variation are documented neither upstream nor in the fork. The server
  reads `make_cond_dict`'s signature at startup, prints it, serves it on `/health`, and passes
  through only what the installed model accepts. A client sending an unknown key gets it back in
  `X-Rejected-Conditioning` rather than an AttributeError five frames deep.
- **the model's own time is reported separately** from the HTTP round trip, in `X-Infer-Ms`, so
  the table keeps measuring synthesis rather than a loopback.

Run it with the fork's Python — the one that has torch and zonos:

```
<fork>\.venv\Scripts\python.exe tools	ts-lab\server\zonos_server.py --model-dir <fork>
```

It listens on 7861, because 7860 is the fork's own UI. `server.json` already points at it; fill
in `speaker` with the path of a reference `.wav` to clone a character, or leave it empty for the
model's default voice.

Nothing here has been run: the fork is not installed on this machine yet, so every line of this
section is written from the documentation and waits for a first launch to become a measurement.

## The ladder, measured on an RTX 4080 SUPER — 2026-08-31

Warm figures. Zonos' **first** call after a start costs 30 to 50 seconds: Triton compiles its
kernels once. It is not a property of any line — `elisions` was 28 s on the first pass and
2.4 s on the two after it. A resident server pays that once; a bench that reports it as the
cost of speaking would be lying.

| tier | engine | rtf | a 4-second reply takes |
|---|---|---|---|
| `cloné` | Zonos v0.1 (GPU) | 1.3 – 1.55 | ~2.9 s |
| `neuronal` | Piper (CPU) | ~13 | ~0.3 s |
| `recollé` | SAPI | 5 – 46 | ~0.3 s |

**A tenfold gap, and the top of the ladder is the slow one.** That is the whole trade, stated in
numbers rather than adjectives.

### The number that saves it: rtf above 1

Zonos synthesises **faster than the speech is spoken** — 1.4 seconds of audio per second of
compute. So the cost is not throughput, it is the wait before the first syllable: three seconds
of silence after V stops talking, which is precisely the complaint Mantella's players make most.

Cut the reply into sentences and that wait becomes the first sentence alone — roughly 0.7 s for
a short one — and every later sentence is synthesised while the previous one plays, staying
ahead because rtf is above 1. **The fix for the latency is chunking, not a faster model.**

It costs something on our side: `plugin/Audio.cpp` plays one buffer and replaces it on the next
call, which is right for one utterance and wrong for a queue. Sentence streaming needs it to
hold a queue of buffers and play them back to back without a gap. That is a real change, and it
is the one this measurement argues for.

## What this cannot answer

Whether the game's audio engine and a converter can share a machine while the game renders. The
lab runs alone; the game does not. Every number here is an upper bound on what a launch gets.
