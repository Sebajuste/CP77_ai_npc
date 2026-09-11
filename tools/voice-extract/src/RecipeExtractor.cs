using System.Globalization;
using System.Text.Json;

namespace VoiceExtract;

// Refaire les extraits a partir de la seule recette : les repliques sont designees par leur
// hachage, jamais par leur chemin, et le dictionnaire de WolvenKit n'est pas ouvert.
//
// C'est la moitie que le joueur executera un jour, et c'est ici qu'on verifie qu'elle suffit :
// ce qu'elle produit doit etre identique, octet pour octet, a ce que la selection produit.
internal static class RecipeExtractor
{
    public static int Run(Options options)
    {
        var recipe = JsonSerializer.Deserialize<Recipe>(File.ReadAllText(options.RecipeFile));
        var language = LanguageFor(recipe, options.Language);
        if (!string.Equals(language, options.Language, StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine($"pas de recette en '{options.Language}', repli sur '{language}'");
        }
        using var source = VoiceSource.Open(options.Game, language);
        var settings = SettingsFrom(recipe.Settings);
        var mismatched = 0;

        foreach (var voice in recipe.Voices)
        {
            if (!string.Equals(voice.Language, language, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            if (options.Characters.Count > 0 && !options.Characters.Contains(voice.Voice))
            {
                continue;
            }

            var lines = new List<PcmClip>();
            var missing = 0;
            foreach (var line in voice.Lines)
            {
                var hash = ulong.Parse(line.Hash, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                var wem = source.ReadRawByHash(hash);
                var decoded = wem is null ? null : WemDecoder.Decode(wem);
                if (decoded is null)
                {
                    missing++;
                    continue;
                }
                lines.Add(Resampler.To(decoded.Trimmed(settings.SilenceFloor), settings.SampleRate));
            }
            if (missing > 0)
            {
                Console.WriteLine($"{voice.Voice} : {missing} replique(s) absente(s) de cette installation");
            }
            if (lines.Count == 0)
            {
                continue;
            }

            var clip = ClipBuilder.Assemble(lines, settings);
            var file = Path.Combine(options.Out, voice.Voice + ".wav");
            WavWriter.Write(file, clip, voice.Shift ?? 1.0);
            Console.WriteLine($"{voice.Voice} : {clip.Seconds:F1} s, {lines.Count} repliques, "
                              + $"RMS {clip.Rms:F3}");

            if (options.Against is not null)
            {
                mismatched += Compare(options.Against, voice.Voice, file) ? 0 : 1;
            }
        }

        if (options.Against is null)
        {
            return 0;
        }
        Console.WriteLine(mismatched == 0
            ? "identique a la sortie de reference : la recette suffit"
            : $"{mismatched} extrait(s) different(s) de la sortie de reference");
        return mismatched == 0 ? 0 : 1;
    }

    private static bool Compare(string directory, string name, string produced)
    {
        var expected = Path.Combine(directory, name + ".wav");
        if (!File.Exists(expected))
        {
            Console.WriteLine($"    pas de reference a comparer pour {name}");
            return true;
        }
        var same = File.ReadAllBytes(expected).AsSpan().SequenceEqual(File.ReadAllBytes(produced));
        if (!same)
        {
            Console.WriteLine($"    DIFFERENT de {expected}");
        }
        return same;
    }

    // La langue du joueur d'abord : son doublage est dans sa langue, et un clone fabrique
    // ailleurs parlerait avec l'accent de la mauvaise. L'anglais n'est le repli que si la
    // recette ignore la sienne -- ce qui, sur une installation ordinaire, n'arrive pas.
    private static string LanguageFor(Recipe recipe, string wanted)
    {
        bool Has(string language) => recipe.Voices.Any(
            v => string.Equals(v.Language, language, StringComparison.OrdinalIgnoreCase));

        if (Has(wanted))
        {
            return wanted;
        }
        if (Has("en"))
        {
            return "en";
        }
        return recipe.Voices.FirstOrDefault()?.Language ?? wanted;
    }

    private static ClipRecipe SettingsFrom(RecipeSettings settings) => new()
    {
        SampleRate = settings.SampleRate,
        GapSeconds = settings.GapSeconds,
        SilenceFloor = settings.SilenceFloor,
        MaxSeconds = settings.MaxSeconds,
        TargetRms = settings.TargetRms,
        PeakCeiling = settings.PeakCeiling,
    };
}
