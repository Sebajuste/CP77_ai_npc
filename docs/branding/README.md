# Branding

Two names, and they never meet.

**AGENT LINK** is what the app is called in Night City -- the name under the icon of a
terminal, the address in the browser bar (`NETdir://agentlink.nc`), the title on every page.
An Agent is the pocket assistant a citizen carries; this site is its companion on a desk.

**AI NPC** is what the mod is called on Nexus, in the file names and in Mod Settings, where
the reader is a modder choosing a download. It says what the thing is made of, which is
exactly what an in-world application would never announce.

`tools/make-icon.py` (PIL, drawn at 4x and downsampled) produces both. Edit the script, not
the PNGs.

| file | for |
|---|---|
| `agentlink_logo_1024/512/256/128.png` | the app icon, colour, transparent background |
| `agentlink_icon_mono_256/128.png` | white silhouette, in case a site icon turns out to be tinted |
| `ainpc_nexus_thumb_1280x720.png` | the Nexus main image |

The drawing is the Agent and what it is linked to: the handset, a conversation on it, the
arcs of what the desk hears, one unread. Same chamfered plate and same palette as
NightCityAgenda's `agenda.nc`, so the two read as siblings if a player has both installed
and meets them in the same browser's site list.

## From a PNG to an icon on a terminal

```
docs/branding/*.png   --(WolvenKit GUI, by hand)--->  source/archive/.../*.xbm
                      --(tools/inkatlas)----------->  source/archive/.../*.inkatlas
                      --(tools/build-archive.ps1)-->  src/archive/pc/mod/ai_npc.archive
```

Only the first arrow is a person, and only when the drawing changes. The other two run
inside `package.ps1`.

**The import, in the GUI** (WolvenKit 8.20, `CP77_mods\WolvenKit-8.20.0\`): open
`ai_npc.cpmodproj` in the repo root -- the PNGs are already in `source\raw\agentlink\icons\`
at the depot path they should keep -- then Import Tool on each, texture group
`TEXG_Generic_UI`. What the GUI does **not** do: its inkatlas generator writes an empty
`inkTextureAtlas` (236 bytes, no slot, no texture), and no menu fills one in from an image.
Never use **Pack & Install**, which writes straight into the game folder and around Vortex.

**The atlas, by script:**

```powershell
dotnet run --project tools\inkatlas -- "agentlink\icons\agentlink.xbm" agentlink `
    source\archive\agentlink\icons\agentlink.inkatlas
```

`AiNpcTerminalSite.reds` names that path and the part `agentlink`. A monochrome atlas built
the same way from `agentlink_mono.xbm` is the fallback if the browser turns out to tint the
icon slot -- switching is one line.

**The archive:** `powershell -File tools\build-archive.ps1`, which `package.ps1` runs itself.
It calls WolvenKit's own `ArchiveWriter` -- the same code the GUI's Pack Project calls.

`fomod\ModuleConfig.xml` lists `archive\` in `requiredInstallFiles`. Without that line the
file travels in the zip and is never installed, which looks exactly like a broken icon path.
