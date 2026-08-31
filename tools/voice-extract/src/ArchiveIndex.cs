namespace VoiceExtract;

// Lecture seule d'une archive RDAR : la table des fichiers, et le contenu d'un fichier
// designe par son chemin depot. Les .wem de doublage tiennent en un segment non
// compresse, ce qui evite d'avoir a traverser Oodle ici.
internal sealed class ArchiveIndex : IDisposable
{
    private readonly FileStream _stream;
    private readonly Dictionary<ulong, (int First, int Last)> _entries = new();
    private readonly List<(long Offset, uint ZSize, uint Size)> _segments = new();

    public string FilePath { get; }

    public int FileCount => _entries.Count;

    private ArchiveIndex(string path)
    {
        FilePath = path;
        _stream = File.OpenRead(path);

        var header = Read(0, 32);
        if (header[0] != 'R' || header[1] != 'D' || header[2] != 'A' || header[3] != 'R')
        {
            throw new InvalidDataException(path + " n'est pas une archive RDAR");
        }
        var indexOffset = BitConverter.ToInt64(header, 8);
        var indexSize = BitConverter.ToInt32(header, 16);
        var index = Read(indexOffset, indexSize);

        // en-tete de table : ftOffset(4) ftSize(4) crc(8) fileCount(4) segmentCount(4) depCount(4)
        var fileCount = BitConverter.ToInt32(index, 16);
        var segmentCount = BitConverter.ToInt32(index, 20);
        const int entriesAt = 28;
        for (var i = 0; i < fileCount; i++)
        {
            var at = entriesAt + i * 56;
            var hash = BitConverter.ToUInt64(index, at);
            _entries[hash] = (BitConverter.ToInt32(index, at + 20), BitConverter.ToInt32(index, at + 24));
        }
        var segmentsAt = entriesAt + fileCount * 56;
        for (var i = 0; i < segmentCount; i++)
        {
            var at = segmentsAt + i * 16;
            _segments.Add((BitConverter.ToInt64(index, at),
                           BitConverter.ToUInt32(index, at + 8),
                           BitConverter.ToUInt32(index, at + 12)));
        }
    }

    public static ArchiveIndex Open(string path) => new(path);

    public bool Contains(string depotPath) => _entries.ContainsKey(Fnv1a64.OfDepotPath(depotPath));

    public byte[] ReadRaw(string depotPath)
    {
        var hash = Fnv1a64.OfDepotPath(depotPath);
        if (!_entries.TryGetValue(hash, out var range))
        {
            return null;
        }
        var segment = _segments[range.First];
        if (segment.ZSize != segment.Size)
        {
            throw new NotSupportedException(depotPath + " est compresse ; ce lecteur ne sert qu'aux .wem");
        }
        return Read(segment.Offset, (int)segment.Size);
    }

    private byte[] Read(long offset, int count)
    {
        var buffer = new byte[count];
        _stream.Seek(offset, SeekOrigin.Begin);
        _stream.ReadExactly(buffer, 0, count);
        return buffer;
    }

    public void Dispose() => _stream.Dispose();
}
