# The voice lane: what ships, what is made locally, and the seam between them

The mod ships **no voice data**. It ships the ability to speak, and reads whatever voices are
present. Making a voice that sounds like the game's own character is a separate, optional,
out-of-game step the player performs once.

That split is not a legal fig leaf bolted onto a technical plan — it is the only shape that
works, and each half fails without it:

- **the mod cannot do the making.** It is redscript plus a small DLL. Decoding Wwise
  soundbanks, mapping line ids to a speaker and assembling thirty clean seconds is hundreds of
  megabytes of intermediates and minutes of work. That is not a thing a game mod does while the
  player waits at a loading screen.
- **the tool cannot do the speaking.** It has no session, no contact, no reply.

Mantella and SkyrimNet both land here — voices are an installation step, not a feature of the
mod. What this document adds is that **the artefact between the two halves is ours**, specified
below, rather than an accident of whichever tool made it.

---

## 1. The three tiers, and what each needs from the player

| tier | voice | what the player installs |
|---|---|---|
| `recollé` | Windows' own | nothing |
| `neuronal` | a generic neural voice | a local engine |
| `cloné` | as close to the game's as we can get | an engine **and** a reference clip |

**The first two ship working.** A player who installs nothing still hears a character speak.
That is the floor, and it is what makes the voice lane an improvement rather than a dependency.

The third needs one file per character, and where that file comes from is not the mod's
business — see § 3.

---

## 2. The seam: a folder and a manifest, never a code dependency

The tool writes; the mod reads. Neither imports the other, and the mod must run identically
when the tool has never been installed.

```
r6\storages\AiNpc\voices\
    voices.json          the manifest: which character has what
    judy.wav             a reference clip
    panam.wav
```

**`r6\storages\` and nowhere else.** It is the one place this project may write at runtime,
precisely because Vortex does not manage it — `r6\audioware\` and `r6\scripts\` are hardlinks
into the staging folder, and writing there corrupts the source copy of a mod, silently. A voice
made after installation is not part of the mod and must not sit where the mod's own files sit.

### What the artefact is: the clip, not the embedding

A speech engine turns a reference clip into a speaker embedding. It is tempting to store that
embedding, since it is what the model actually consumes and computing it costs a second.

**Store the clip.** The embedding is bound to one engine *and one model version* — Zonos caches
its own under `cache\embeds\Zonos-v0.1-transformer\`, and the version is in the path for a
reason. A clip survives changing the engine, upgrading the model, or the player switching tiers;
an embedding survives none of those, and a stale one fails in the worst way available: it works,
and sounds like somebody else.

The engines already cache embeddings themselves, keyed by the clip. Storing the clip therefore
costs nothing per reply and keeps the artefact portable.

### The manifest

Per character: the file, where it came from, how long it is, and when it was made. The origin
matters because a clip a player recorded and a clip taken from the game are the same file to us
and not the same thing to them.

A character with no entry falls back to the tier below, **per character**. A player will have
Judy and not Rogue, and the mod has to be right in that state rather than treating "cloned
voices" as one switch.

---

## 3. The tool, and the one thing that decides whether it is a weekend or a month

It runs outside the game, once, on the player's own files, and produces the folder above.

The steps are known, except one:

1. find the voice-over archives — known;
2. read `.opusinfo` / `.opuspak` and decode the Opus streams — known, and WolvenKit does it,
   though **the assembly that carries audio export is not the one this repo's `wkdump` harness
   holds**: it has `Common`, `Core` and `RED4`, no audio at all, and its own sources never
   mention opus, `.wem` or soundbanks;
3. **keep only the lines spoken by one character** — answered, see below;
4. concatenate thirty clean seconds, write the clip and the manifest entry.

### Step 3 is a filename, not a puzzle

`cp2077-voiceswap` does this by **regular expression on the depot path**: its documented example
is `v_(?!posessed).*_f_.*` for female V's lines, excluding the Johnny-possessed variants. The
speaker is in the path. No metadata to cross-reference, no matching subtitles to audio.

The real dependency is elsewhere and is a data one: **archives store only the FNV1a64 of the
lowercased path**, never the path. Filtering by regex therefore needs a dictionary of known
paths — the one WolvenKit ships. That is what the tool must carry, and it is the thing to
verify before anything else: whether the paths for one character resolve on a plain install.

### A reference does not have to come from the game

The cloning measured on 2026-08-31 used a Piper output as its reference — a generated French
voice, cloned successfully. Any clean thirty seconds works.

So the tool is one supplier of clips, not the definition of the tier. A player who drops their
own recording in gets the `cloné` tier with no extraction at all, and the archive route can fail
without taking the feature with it.

---

## 4. What this does not fix

**The wait.** Zonos synthesises at about 1.4× real time, so a four-second reply is three seconds
of silence first. Cloning changes who speaks, not when.

Cutting the reply into sentences helps, but the better answer hides the synthesis inside a delay
the player is already paying: **stream the model's output, and send each sentence to the voice as
it completes.** The first sentence is spoken while the model is still writing the second, so the
voice costs nothing the text lane was not costing already.

**Our transport cannot do that today, and that is the real work.** The speaking lane posts a
request and waits for a whole reply; RedHttpClient is a request/response API with no streaming.
The lane that *could* stream is the one in `ai_npc.dll` — it already owns an HTTP client's worth
of ground, it already runs off the game thread, and **it is already where the audio lives**. A
streaming request there, feeding sentences to the speech worker as they arrive, is the single
change that makes a cloned voice arrive on time.

So the order is: streaming first, voices second. A beautiful voice that arrives three seconds
late is the defect Mantella's players report most, and it would be ours by construction.
