using VoiceExtract;

var options = Options.Parse(args);
WolvenKitAssemblies.UseDirectory(options.WolvenKit);

var dictionary = DepotDictionary.Load(Path.Combine(options.Cache, "depot-paths.txt"));
using var source = VoiceSource.Open(options.Game, options.Language);
Console.WriteLine("archives : " + string.Join(", ", source.ArchiveFiles));

var recipe = new ClipRecipe { SampleRate = options.Rate };
var manifest = new Manifest();
var madeAt = DateTime.Now.ToString("s");

foreach (var contactId in options.Characters)
{
    var character = VoiceCast.Find(contactId);
    if (character is null)
    {
        Console.WriteLine(contactId + " : aucune voix vanilla, personnage ignore");
        continue;
    }

    var pattern = options.Pattern ?? character.Pattern;
    var lines = source.LinesMatching(dictionary, pattern, options.Exclude).ToArray();
    Console.WriteLine($"{contactId} : {lines.Length} repliques selectionnees par {pattern}"
                      + (character.Note is null ? "" : "  (" + character.Note + ")"));
    if (options.ListOnly)
    {
        foreach (var line in lines.Take(5))
        {
            Console.WriteLine("    " + line);
        }
        continue;
    }
    if (lines.Length == 0)
    {
        continue;
    }

    var reference = ClipBuilder.Build(lines, source, recipe);
    if (reference.Kept.Count == 0)
    {
        Console.WriteLine("    aucune replique n'a passe les seuils");
        continue;
    }
    if (options.ShowLines)
    {
        foreach (var m in reference.Examined)
        {
            Console.WriteLine($"      {Path.GetFileName(m.DepotPath),-56} {m.Seconds,5:F1} s  "
                              + $"RMS {m.Rms:F3}  {m.Verdict}");
        }
    }
    var file = contactId + ".wav";
    WavWriter.Write(Path.Combine(options.Out, file), reference.Clip);
    if (options.Raw)
    {
        var index = 0;
        foreach (var line in reference.Kept)
        {
            WavWriter.Write(Path.Combine(options.Out, "raw", $"{contactId}-{++index:D2}.wav"), line.Native);
        }
    }
    Console.WriteLine($"    {file} : {reference.Clip.Seconds:F1} s, {reference.Kept.Count} repliques, "
                      + $"RMS {reference.Clip.Rms:F3}");

    manifest.Voices.Add(new VoiceEntry
    {
        ContactId = contactId,
        File = file,
        Seconds = Math.Round(reference.Clip.Seconds, 2),
        SampleRate = reference.Clip.SampleRate,
        Channels = 1,
        Source = "game archives",
        Pattern = pattern,
        Lines = reference.Kept.Count,
        MadeAt = madeAt,
    });
}

if (!options.ListOnly && manifest.Voices.Count > 0)
{
    var file = Path.Combine(options.Out, "voices.json");
    manifest.MergeInto(file);
    Console.WriteLine("manifeste : " + file);
}
