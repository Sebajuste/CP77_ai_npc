using System.Text;

namespace VoiceExtract;

// Les archives ne stockent que le FNV1a64 du chemin depot en minuscules.
internal static class Fnv1a64
{
    public static ulong OfDepotPath(string path)
    {
        ulong hash = 0xCBF29CE484222325;
        foreach (var b in Encoding.UTF8.GetBytes(path.ToLowerInvariant()))
        {
            hash ^= b;
            hash *= 0x100000001B3;
        }
        return hash;
    }
}
