# Credits, and where this mod comes from

The mod is released under the MIT licence — `src/`, `plugin/` and `fomod/`, the parts that
ship to a player; `LICENSE` states the scope, and the rest of the repository is not licensed.
That grant says what others may do with the mod. This file says what the mod owes to other
people, which MIT does not require and the modding community does.

The first section is the one that matters, and it is deliberately free of numbers: a
percentage would invite the reader to wonder what the remainder was, when the remainder is
quest names, engine signatures and ordinary English.

---

## 1. Where it comes from

**This is not a fork.**

ai_npc was written from scratch. It is not a fork of **Generative Texting**, of **Immersive
Companion Generative Texting**, or of any other mod in that family, and it ships no line of
their code and none of their prompts. It is not one more variant: it is a different mod that
came from the same idea.

**And it would not exist without them.**

Their mods were installed and played long before a line of this one was written. That is
where the idea came from, and it would never have been thought of without having seen theirs
working first. Thank you to their authors for clearing the road:

- the notion that a character could answer on the player's own in-game phone;
- the approach of feeding quest state into what that character says;
- `jackie_dead` — a contact who answers from the far side of their own death, still one of
  the best ideas in this corner of Cyberpunk modding.

**Deliberate compatibility.** Some things are kept on purpose, so that anyone arriving from
those mods finds what they already know: **T** opens the chat from the phone, and the
contacts carry the same identifiers — `jackie`, `jackie_dead`, `panam`, `kerry_eurodyne`,
`judy`, `songbird`, `river_ward`, `rogue`, `victor_vector`, `takemura`.

**On the early drafts.** The first working version of the engine was built against prompt
text taken from those mods, as scaffolding: it made the machinery testable while it was being
written, and it was never meant to ship. Every character sheet was written from scratch before
release, and nothing was ever published in the meantime. What is in this repository is the
mod, not the scaffolding it was built against.

> **Before publishing.** The names of the upstream authors are recorded in this project's own
> notes rather than in their archives, which carry no authorship metadata at all. Confirm the
> spelling and who did what on the Nexus pages before naming anyone in public.


---

## 2. Frameworks this mod requires

None of them are redistributed here — the player installs each one. Listed with the licence
as verified locally on 2026-08-26; the ones marked *to confirm* were not verifiable from an
installed copy and should be checked against their repository before release.

| Framework | Author | Licence |
|---|---|---|
| [RED4ext](https://github.com/WopsS/RED4ext) | WopsS | to confirm |
| [RED4ext.SDK](https://github.com/WopsS/RED4ext.SDK) (git submodule, build only) | Octavian Dima | MIT — verified |
| [redscript](https://github.com/jac3km4/redscript) | jac3km4 | to confirm |
| [Codeware](https://github.com/psiberx/cp2077-codeware) | psiberx | to confirm |
| [RedData](https://github.com/psiberx/cp2077-red-data) | psiberx | MIT — verified |
| [RedFileSystem](https://github.com/psiberx/cp2077-red-filesystem) | psiberx | MIT — verified |
| [RedHttpClient](https://github.com/rayshader/cp2077-red-httpclient) | rayshader | MIT — verified |
| [Mod Settings](https://www.nexusmods.com/cyberpunk2077/mods/4885) | — | to confirm |
| [Cyber Engine Tweaks](https://www.nexusmods.com/cyberpunk2077/mods/107) (optional) | yamashi and contributors | to confirm |

`AiNpcContactHash` produces the stable identifier that
[Phone Extension Framework](https://www.nexusmods.com/cyberpunk2077/mods/24949) expects, so
custom contacts appear correctly for players who have it.

---

## 3. Assets

- **The AGENT LINK icon** (`source/raw/agentlink/`, packed into
  `src/archive/pc/mod/ai_npc.archive`) is drawn by `tools/make-icon.py` in this repository —
  original work, no third-party image. It rasterises text using two fonts shipped with
  Windows, Bahnschrift and Consolas; the icon is a bitmap, and no font file is redistributed.
- **No other art, audio or text asset is bundled.** The mod ships REDscript, one small
  `.archive` holding that icon, one Lua window for Cyber Engine Tweaks, and the plugin DLL.
- **Game content belongs to CD Projekt Red.** Character names, quest names and the setting
  are theirs. This mod contains none of their files; it refers to their world.

---

## 4. Contributors

*To be filled in before release.* Code, testing, bug reports and translations each deserve a
line here. If the list is empty, say so plainly rather than omitting the section — an absent
credits section reads as an oversight, an empty one reads as an answer.

---

## 5. Tooling

Development only. None of it is redistributed, and none of it is needed to play.

- **WolvenKit 8.20** — referenced by `tools/archive` and `tools/inkatlas` to read and write
  CR2W files. Referenced by absolute path from a local install; no WolvenKit binary is in
  this repository (0 tracked DLLs) and none is shipped.
- **Python 3.10 + Pillow** — the icon generator and the offline prompt tooling.
- **Visual Studio C++ toolset** — builds `ai_npc.dll`. The offline suite skips the C++ tests
  when it is absent rather than failing.

---

## 6. Disclaimer

ai_npc is an unofficial fan-made modification. It is **not affiliated with, endorsed by, or
sponsored by CD Projekt Red**. Cyberpunk 2077 and all related marks are the property of CD
Projekt S.A.

Replies are generated by a large language model chosen and paid for by the player. The mod
sends the player's messages and the character's context to the provider they configure, and
nowhere else. It ships no API key and stores none outside the player's own
`r6/storages/AiNpc/settings.json`.

---

## Short version, for the Nexus page

Written to open the description, in this order on purpose: the fact first, because it is the
question a reader of the Generative Texting family will have; the thanks second, because they
are the longer half and the one that matters. No numbers — a percentage invites the reader to
wonder what the remainder was, and there is no remainder to wonder about.

> **This is not a fork.**
>
> AI NPC was written from scratch. It is not a fork of Generative Texting, of Immersive
> Companion Generative Texting, or of any other mod in that family, and it carries no line of
> their code and none of their prompts. It is not one more variant — it is a different mod
> that came from the same idea.
>
> **And it would not exist without them.**
>
> I played those mods long before I wrote a line of this one. That is where the idea came
> from, and I would never have thought of building it without having seen theirs working
> first. Thank you to their authors for clearing the road: the notion that a character could
> answer on your own in-game phone, the approach of feeding quest state into what they say,
> and `jackie_dead` — a contact who answers from the far side of their own death, still one of
> the best ideas anyone has had in this corner of Cyberpunk modding.
>
> Some things are kept deliberately, so that anyone arriving from those mods finds what they
> already know: **T** still opens the chat from the phone, and the characters carry the same
> contact names.
>
> Built on RED4ext, redscript, Codeware, RedData, RedFileSystem, RedHttpClient and Mod
> Settings — thank you to WopsS, jac3km4, psiberx and rayshader. Cyber Engine Tweaks is
> optional and unlocks the setup and journal windows.
>
> Not affiliated with CD Projekt Red. The mod's own code is MIT; the game and its characters
> are not mine.

Name the upstream authors here only once their names have been confirmed on the Nexus pages.
