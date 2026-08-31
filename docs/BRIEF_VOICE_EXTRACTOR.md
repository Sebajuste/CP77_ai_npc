# Brief: the voice-reference extractor

A work order for one agent, working alone. Everything it needs is here; it has none of the
conversation this came from.

---

## What to build

A tool, run **outside the game by the player**, once, that produces reference voice clips for
`ai_npc`'s cloned-voice tier from the player's own copy of Cyberpunk 2077.

```
tools\voice-extract\
    README.md          what it does, how to run it, and what you measured
    <entry point>      one command, named characters in, clips out
```

Output, into `dist\voices\` by default:

```
voices.json            the manifest
judy.wav               one clip per character
panam.wav
```

`voices.json`, one entry per character:

```json
{
  "voices": [
    {
      "contactId": "judy",
      "file": "judy.wav",
      "seconds": 31.4,
      "sampleRate": 22050,
      "channels": 1,
      "source": "game archives",
      "pattern": "<the regex that selected the lines>",
      "lines": 12,
      "madeAt": "2026-09-01T10:00:00"
    }
  ]
}
```

`contactId` uses the mod's own ids — `judy`, `panam`, `river_ward`, `takemura`, `songbird`,
`rogue`, `viktor`, `kerry`, `jackie`, `jesse`. They match the game's journal contact ids, which
was measured: a dump of 176 journal contacts on a live save returned `id='judy'`, `id='panam'`
and so on.

**The tool never writes into the game folder.** The player copies the result to
`<game>\r6\storages\AiNpc\voices\` themselves; the README says so. Read the game's archives,
write nowhere near them.

---

## What is already known — do not re-research this

- **A character is identified by the file path, not by metadata.** `cp2077-voiceswap`
  (github.com/Zhincore/cp2077-voiceswap) selects lines with a regular expression over depot
  paths; its documented example is `v_(?!posessed).*_f_.*` for female V, excluding the
  Johnny-possessed variants. There is no subtitle-to-audio matching to do.
- **Archives store only the FNV1a64 of the lowercased path**, never the path itself. Any
  path-based filter therefore needs a dictionary of known paths. WolvenKit ships one. Obtaining
  and using that dictionary is the first real dependency.
- **Voice-over is Wwise**: `.opusinfo` indexes streams inside `.opuspak`. Decoding is a solved
  problem (WolvenKit's audio export, or `ww2ogg` for `.wem`).
- **This repo has an archive harness already**, at
  `..\NA_PerspectiveFix\tools\wkdump\` — it drives WolvenKit 8.20 assemblies by reflection and
  does RDAR extraction, Oodle, and CR2W read/write. **It cannot help with audio as it stands**:
  its `bin\` holds `WolvenKit.Common`, `WolvenKit.Core` and `WolvenKit.RED4` only, no audio
  assembly, and its own C# never mentions opus, `.wem` or soundbanks. Read it for how it loads
  WolvenKit by reflection; do not expect audio from it.
- **Thirty seconds of clean single-speaker speech is the target.** Voice cloning engines want
  10–30 s. Game voice-over is ideal: studio-clean, one speaker per file, no music.
- The game is at `D:\Jeux\Cyberpunk 2077`.

---

## Measure this first, and stop if it fails

**Can you list, for one character, the depot paths of their voice lines on a plain install?**

That single question decides whether this tool is two days or a month. Answer it before writing
anything else — no extraction, no conversion, no manifest. If the paths for `judy` do not
resolve, say so, write down exactly what you tried, and stop. A tool built around a filter that
cannot select is worse than no tool.

Report the answer with evidence: a handful of real paths, and how many lines the pattern selects.

---

## Then, in order

1. Extract the selected streams for one character.
2. Convert to WAV: mono, 22050 Hz, 16-bit. That is what the speech engines are fed.
3. Concatenate to roughly thirty seconds. **Prefer several medium lines over one long one**, and
   skip anything under about two seconds — grunts and one-word barks make a poor reference.
4. Write the clip and the manifest.
5. Generalise to a list of characters.

---

## How you know it worked

Not "it produced a file". A reference clip is only correct if a cloning engine accepts it and
the result sounds like the character.

- **Automatic**: the clip is mono 22050 Hz, between 20 and 40 seconds, not silent (check the
  RMS, not the file size), and `voices.json` parses.
- **By ear, and this needs the user**: hand the clip to a speech engine and listen. There is a
  bench in this repo at `tools\tts-lab\` with a Zonos client already wired
  (`tools\tts-lab\lab.py`, `zonos.json`); its README says how to run it. A reference is passed
  as `{"path": "<path relative to the server folder>", "meta": {"_type": "gradio.FileData"}}` —
  an absolute path is refused by Gradio's guard, and a plain string fails too. That cost an hour
  to find; do not rediscover it.

Say plainly which of the two you did. Only the user can do the second.

---

## Constraints, and they are not negotiable

Read `..\CLAUDE.md` (the `CP77_mods` one) before starting. The parts that bite here:

- **Never deploy anything.** Do not write into `D:\Jeux\Cyberpunk 2077\`, do not run
  `redMod.exe`, do not copy files into the game. Read the archives, write into this repo.
- **`tools\` never reaches the game.** This tool is development and player-side tooling; it is
  not part of the mod and must not be added to `tools\package.ps1`.
- **Encoding.** Sources are UTF-8 without BOM. Never `Get-Content` → `Set-Content` on a file
  with accents: PowerShell 5.1 re-reads UTF-8 as ANSI and `-Encoding utf8` adds a BOM. Use
  Python's `io.open(..., encoding="utf-8")` or `[System.IO.File]::WriteAllText` with
  `New-Object System.Text.UTF8Encoding($false)`.
- **Never kill a process by image name.** Several agents and the user's own applications run in
  parallel. Track the PID you started (`Start-Process -PassThru`) and stop that one.
- **Work in your own git worktree** and stay in it. Do not use bare `git stash`: the stack is
  shared with other worktrees.
- **Do not ship voice data.** The clips are made on the player's machine from the player's own
  game. Nothing extracted goes into this repository — add `dist\voices\` and any extraction
  cache to `.gitignore`.

---

## What must not be claimed

That it works, before a clip has been through a speech engine and heard. Producing a WAV of the
right shape proves the plumbing and nothing about the voice.

If a step turns out to be impossible, that is a result and it is worth reporting. Write what you
measured, with the commands that produced it, in `tools\voice-extract\README.md` — including the
things that did not work, and why. The next person to touch this will believe that file.
