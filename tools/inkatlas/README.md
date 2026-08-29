# inkatlasgen

Writes an `.inkatlas` that points at one `.xbm` and names one part -- the whole image.

WolvenKit's GUI generator produces an empty `inkTextureAtlas` (236 bytes, no slot, no
texture), so the file is built here instead of by hand in the property editor: a generated
file can be regenerated, and a hand-edited binary cannot be reviewed.

```powershell
dotnet run --project tools\inkatlas -- "nightcityagenda\icons\nca_agenda_mono.xbm" nca_agenda `
    source\archive\nightcityagenda\icons\nca_agenda_mono.inkatlas
```

The three slots (one per `inkETextureResolution`) all get the same texture and the same
part name: the icon is one image, and a slot left empty is an icon that vanishes at that
resolution. Depot paths are lowercase with backslashes -- an archive stores FNV1a64 of the
lowercased path, so the case in this argument is the case the game looks up.

Needs the WolvenKit 8.20 DLLs at `CP77_mods\WolvenKit-8.20.0\` (referenced by the csproj)
and dotnet 8.
