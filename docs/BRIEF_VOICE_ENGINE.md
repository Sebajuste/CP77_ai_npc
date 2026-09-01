# Brief: the speaking engine, inside the DLL

A work order for one agent, working alone. Everything it needs is here; it has none of the
conversation this came from.

---

## What to build

**PocketTTS running inside `ai_npc.dll`**, filling the same buffer SAPI fills today. No GPU, no
Python, no server, no installation for the player.

The seam already exists and was written for this:

```
AiNpcAudio.Speak(text)  ->  ainpc::speech::Speak  ->  SAPI  ->  PCM buffer  ->  ainpc::audio
                                     ^                                            (waveOut)
                                     `-- this is what changes
```

`plugin\Speech.hpp` states the contract in its own words: *"swapping SAPI for a real
text-to-speech service later changes what fills the buffer and nothing else."* Take it at that.

One voice per character, chosen per character:

- a **reference clip** in `r6\storages\AiNpc\voices\`, when the player made one;
- otherwise a **catalogue voice**, from the table in `tools\tts-lab\fallback-voices.json`.

Same model, same code path. Only the reference differs.

---

## What is already known — do not re-research this

### The engine, measured on this machine 2026-09-01 (32 logical cores, no GPU used)

| | |
|---|---|
| French model | **`french_24l` only.** The package refuses `--language french`: *"for technical reasons, only a larger 24-layer model is available for French"* |
| model load | 17 s the first time (download), **2.2 s** after |
| cloning one reference | **1.7 to 2.9 s, once per character** |
| speaking | ~1.3x real time |
| first sound | **190 ms at 4 threads, 164 ms at 8** |

**torch takes ONE thread by default and it is the worst setting**: 1.02x and 411 ms. This is a
configuration line, not a model limit.

**The number that matters is the first sound, not the throughput.** Above 1x real time with
`generate_audio_stream`, the audio never starves: the model produces faster than the player
listens. The voice starts ~190 ms after the text is ready and does not stop.

### What it sounds like, and the target is not "as close as possible"

Heard 2026-09-01: PocketTTS **moves away from the original voices while keeping their
intonation**. Zonos, on the same references, is very close to the originals.

**That distance is wanted, and it is a specification rather than a defect.** Reproducing a
manner of speaking is not reproducing a performance, and that is the better position on the
consent question — see `docs\PLAN_VOICE_LANE.md` § 7. If a later version of PocketTTS clones
better, that is a regression for this mod.

**The spectral metric in `tools\tts-lab` said the opposite and was wrong.** It is retracted in
that README, with why. Do not revive it.

### Licences and access

| | |
|---|---|
| `pocket-tts` package, `PocketTTS.cpp` | MIT |
| weights | CC-BY-4.0, attribution required |
| `kyutai/pocket-tts-without-voice-cloning` | **free**, the model that speaks |
| `kyutai/pocket-tts` | **allow-list**, the model that clones |

The allow-list is granted on this machine. **The package swallows the failure**: `load_model`
tries the cloning weights, catches any exception, and silently loads the ones without. You get a
model that speaks perfectly and refuses to clone, with no message saying why.

### The C++ runtime — documented, not measured here

[PocketTTS.cpp](https://github.com/VolgaGerm/PocketTTS.cpp): single file, MIT, fetches ONNX
Runtime, SentencePiece and dr_wav. Loads INT8 and FP32 ONNX; INT8 is "~4x smaller at comparable
quality". Clones from a WAV, MP3 or FLAC, and **caches voice embeddings on disk**. Announces
9.2x real time and 30 ms time-to-first-audio on a Ryzen 7 3800X.

Every figure in that paragraph comes from its README. None of it has been run.

### The catalogue

26 voices, listed in the **private** `pocket_tts.utils.utils._ORIGINS_OF_PREDEFINED_VOICES`.
They are reference clips, not trained voices, and most come from VCTK and EARS — English
speakers. `marius`, `stuart_bell` and `lola` are unusable (near-silent, near-silent, and 11 s
for a 4 s line). `tools\tts-lab\fallback-voices.json` holds the assignment, corrected by ear.

---

## Measure this first, and stop if it fails

**Does `PocketTTS.cpp` build with MSVC?**

`plugin\build.ps1` drives `cl.exe` directly and says why: *"Deliberately no CMake: the plugin is
a handful of translation units against a header-only SDK."* The upstream README names **CMake
3.28+ and a C++17 compiler (GCC, Clang)** — not MSVC, and it fetches three dependencies.

That single question decides whether this is one build system or two. Answer it before writing
anything else. If it cannot be made to build with `cl.exe`, **say so and stop**: the fallback is
a separate process talking to the DLL, which is a different design and a different brief.

The second gate is cheaper and can be answered the same hour: **what does the INT8 French model
weigh?** 672 MB in fp32. If INT8 is not around 170 MB, the "everything is embedded" premise
needs revisiting before any code is written.

Report both with evidence: the command that built it, or the error that stopped it.

---

## Then, in order

1. **Render one line to a buffer, outside the game**, from C++. No DLL, no RED4ext — a console
   program that produces samples. This is the whole of the engine half and it can be asserted
   without Cyberpunk.
2. **The same, inside `ai_npc.dll`**, off the game thread. `ainpc::speech` already owns a worker
   and a queue; reuse them rather than adding a second.
3. **Carry the contact.** `AiNpcAudio.Speak(text)` does not know who speaks, and a per-character
   voice needs it. This is two lines and it blocks everything else.
4. **Read the voices folder.** `r6\storages\AiNpc\voices\voices.json` — see
   `docs\PLAN_VOICE_LANE.md` § 2 for the manifest. A character with no entry falls back to its
   catalogue voice, **per character**: a player will have Judy and not Rogue.
5. **Stream.** Hand chunks to `ainpc::audio` as they arrive. Step 5 is what turns 1.3x real time
   into a voice that starts in 190 ms, and the streaming lane already landed on the text side
   (`89ba4b2`).

---

## How you know it worked

- **Automatic**: samples come back, the buffer plays, the first sound is under 300 ms, and the
  game thread is never blocked — the queue is `ainpc::speech`'s, not the caller's.
- **By ear, and this needs the user**: it must sound like `tools\tts-lab\out\pocket-<character>-argot.wav`,
  which the Python bench produced from the same references. A C++ path that sounds different
  from the Python one is a bug in the C++ path, and that bench file is the reference to compare
  against.

Say plainly which of the two you did.

---

## Scope: what this brief does not authorise

Two things belong to the channel, not here, and are already written down:

- **the voice gate** — a reply outside the register the performance was recorded for is not
  spoken in the character's voice (`docs\PLAN_HOLO_CHANNEL.md` § 6);
- **the numbers rule** — a numeral glued to its unit derails the engine, and the fix has a
  requested half and a guaranteed half (same section).

Do not implement either. Do not make them impossible either: the engine takes a contact and a
text, and something upstream decides which voice it is handed.

---

## Constraints, and they are not negotiable

Read `..\CLAUDE.md` before starting. The parts that bite here:

- **Never deploy.** The user installs, through Vortex. Build the zip with `tools\package.ps1`;
  never write into `D:\Jeux\Cyberpunk 2077\`.
- **`tools\` never reaches the game — but the model must.** A new kind of artefact under `src\`
  that `package.ps1` does not copy is at the right path in the repo and absent from the zip.
  After packaging, check the archive contents, not `src\`.
- **The mod ships no voice data.** References are made on the player's machine from their own
  copy of the game. The model ships; the voices do not.
- **Attribution.** CC-BY-4.0 requires it. Wherever the model is credited, Kyutai is named.
- **One file, one responsibility. No recursion. Self-commenting code.** A comment states a
  measured trap or an external constraint, never what the code already says.
- **Never kill a process by image name.** Track the PID you started.

---

## What must not be claimed

That it works, before a line has been heard **in game**. Bytes of the right shape prove the
plumbing and nothing about the voice — this project has spent five listening passes learning
that, and every automatic measure that contradicted an ear was the measure that was wrong.

Do not repeat the upstream README's speeds as if they were measured here. Do not revive the
spectral timbre metric. If a step turns out to be impossible, that is a result and it is worth
reporting: write what you measured, with the commands that produced it, including what did not
work and why.
