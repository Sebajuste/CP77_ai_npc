using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace VoiceExtract;

internal sealed class VoiceEntry
{
    [JsonPropertyName("contactId")] public string ContactId { get; set; }
    [JsonPropertyName("file")] public string File { get; set; }
    [JsonPropertyName("seconds")] public double Seconds { get; set; }
    [JsonPropertyName("sampleRate")] public int SampleRate { get; set; }
    [JsonPropertyName("channels")] public int Channels { get; set; }
    [JsonPropertyName("source")] public string Source { get; set; }
    [JsonPropertyName("pattern")] public string Pattern { get; set; }
    [JsonPropertyName("lines")] public int Lines { get; set; }
    [JsonPropertyName("madeAt")] public string MadeAt { get; set; }
}

internal sealed class Manifest
{
    [JsonPropertyName("voices")] public List<VoiceEntry> Voices { get; set; } = new();

    // Une execution sur un seul personnage ne doit pas effacer les neuf autres du manifeste :
    // leurs .wav sont toujours la, et un manifeste qui ne les decrit plus fait disparaitre des
    // voix pour tout ce qui le lit. Les entrees de cette execution remplacent les leurs, les
    // autres sont reprises telles quelles.
    public void MergeInto(string file)
    {
        var merged = new List<VoiceEntry>();
        if (System.IO.File.Exists(file))
        {
            var previous = JsonSerializer.Deserialize<Manifest>(System.IO.File.ReadAllText(file));
            var written = Voices.Select(v => v.ContactId).ToHashSet(StringComparer.OrdinalIgnoreCase);
            merged.AddRange(previous.Voices.Where(v => !written.Contains(v.ContactId)));
        }
        merged.AddRange(Voices);

        var order = VoiceCast.All.Select((c, i) => (c.Name, i))
            .ToDictionary(x => x.Name, x => x.i, StringComparer.OrdinalIgnoreCase);
        merged = merged.OrderBy(v => order.TryGetValue(v.ContactId, out var i) ? i : int.MaxValue).ToList();

        var json = JsonSerializer.Serialize(new Manifest { Voices = merged },
                                            new JsonSerializerOptions { WriteIndented = true });
        System.IO.File.WriteAllText(file, json + "\n", new UTF8Encoding(false));
    }
}
