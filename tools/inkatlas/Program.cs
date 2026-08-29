// Writes a single-texture inkatlas: one texture, one named part, whole image.
// args: <texture depot path> <part name> <out .inkatlas>
using WolvenKit.RED4.Types;
using WolvenKit.RED4.Archive.CR2W;
using WolvenKit.RED4.Archive.IO;

var texture  = args[0];
var partName = args[1];
var outPath  = args[2];

var atlas = new inkTextureAtlas
{
    ActiveTexture       = Enums.inkTextureType.StaticTexture,
    CookingPlatform     = Enums.ECookingPlatform.PLATFORM_PC,
    IsSingleTextureMode = true,
};

// Slots is fixed size, one per inkETextureResolution. All three get the same texture and
// the same part: the icon is one image, and a player at 1080p must not get an empty slot.
for (var i = 0; i < atlas.Slots.Count; i++)
{
    var slot = new inkTextureSlot { Texture = new CResourceAsyncReference<CBitmapTexture>(texture) };
    slot.Parts.Add(new inkTextureAtlasMapper
    {
        PartName               = partName,
        ClippingRectInPixels   = new Rect  { Left = 0,  Top = 0,  Right = 0,  Bottom = 0  },
        ClippingRectInUVCoords = new RectF { Left = 0f, Top = 0f, Right = 1f, Bottom = 1f },
    });
    atlas.Slots[i] = slot;
}

var file = new CR2WFile { RootChunk = atlas };
using (var fs = System.IO.File.Create(outPath))
using (var w = new CR2WWriter(fs))
    w.WriteFile(file);
Console.WriteLine($"wrote {outPath} ({new System.IO.FileInfo(outPath).Length} bytes) -> {texture} / {partName}");
