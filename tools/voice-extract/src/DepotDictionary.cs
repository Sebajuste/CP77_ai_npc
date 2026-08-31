using WolvenKit.Core.Compression;

namespace VoiceExtract;

// Le dictionnaire des chemins depot connus, embarque dans WolvenKit.Common sous forme
// d'une ressource KARK de 135 Mo. Sans lui aucun filtre par chemin n'est possible :
// une archive ne retient que le FNV1a64 du chemin.
internal sealed class DepotDictionary
{
    private const string Resource = "WolvenKit.Common.Resources.usedhashes.kark";

    private readonly string _file;

    private DepotDictionary(string file) => _file = file;

    public IEnumerable<string> UnderDirectory(string directory)
    {
        var prefix = directory.EndsWith('\\') ? directory : directory + '\\';
        foreach (var path in File.ReadLines(_file))
        {
            if (path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                yield return path;
            }
        }
    }

    public static DepotDictionary Load(string cacheFile)
    {
        if (!File.Exists(cacheFile))
        {
            Directory.CreateDirectory(Path.GetDirectoryName(cacheFile));
            File.WriteAllBytes(cacheFile, Decompress());
        }
        return new DepotDictionary(cacheFile);
    }

    private static byte[] Decompress()
    {
        var common = typeof(WolvenKit.Common.Services.HashService).Assembly;
        using var stream = common.GetManifestResourceStream(Resource)
            ?? throw new InvalidOperationException("ressource absente de WolvenKit.Common : " + Resource);
        if (!Oodle.DecompressBuffer(stream, out var plain))
        {
            throw new InvalidOperationException("Oodle a refuse " + Resource);
        }
        return plain;
    }
}
