using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace VoiceExtract;

// Ce qu'il faut pour refaire un extrait SANS le dictionnaire de chemins de WolvenKit.
//
// Le dictionnaire ne sert qu'a CHOISIR les repliques, et ce choix se fait ici, une fois. La
// recette n'en garde que le resultat : les hachages des six a neuf repliques retenues, et les
// seuils avec lesquels on les assemble. Un extracteur cote joueur n'a alors plus qu'a ouvrir
// l'archive, aller chercher ces fichiers-la, les rogner, les coller et mettre a niveau.
//
// Le hachage est une chaine hexadecimale et non un nombre : un FNV1a64 ne tient pas dans le
// double que JSON garantit, et un lecteur qui l'arrondit trouve un fichier absent.
internal sealed class RecipeLine
{
    [JsonPropertyName("hash")] public string Hash { get; set; }
    [JsonPropertyName("path")] public string Path { get; set; }
}

internal sealed class RecipeVoice
{
    // Le nom du fichier de reference sans extension, celui qu'une fiche nomme dans `clone`.
    [JsonPropertyName("voice")] public string Voice { get; set; }
    [JsonPropertyName("language")] public string Language { get; set; }

    // Le facteur de relecture de la reference. Absent, 1 : la voix telle que le jeu la joue.
    [JsonPropertyName("shift")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public double? Shift { get; set; }

    [JsonPropertyName("seconds")] public double Seconds { get; set; }
    [JsonPropertyName("lines")] public List<RecipeLine> Lines { get; set; } = new();
}

// Les seuils d'assemblage, copies de ClipRecipe. Ils sont dans le fichier parce que le lecteur
// n'a pas notre code : une recette qui ne dirait que les fichiers laisserait le joueur deviner
// le rognage et le niveau, et produirait un autre extrait.
internal sealed class RecipeSettings
{
    [JsonPropertyName("sampleRate")] public int SampleRate { get; set; }
    [JsonPropertyName("gapSeconds")] public double GapSeconds { get; set; }
    [JsonPropertyName("silenceFloor")] public double SilenceFloor { get; set; }
    [JsonPropertyName("maxSeconds")] public double MaxSeconds { get; set; }
    [JsonPropertyName("targetRms")] public double TargetRms { get; set; }
    [JsonPropertyName("peakCeiling")] public double PeakCeiling { get; set; }
}

internal sealed class Recipe
{
    [JsonPropertyName("settings")] public RecipeSettings Settings { get; set; }
    [JsonPropertyName("voices")] public List<RecipeVoice> Voices { get; set; } = new();

    public static RecipeSettings SettingsOf(ClipRecipe recipe) => new()
    {
        SampleRate = recipe.SampleRate,
        GapSeconds = recipe.GapSeconds,
        SilenceFloor = recipe.SilenceFloor,
        MaxSeconds = recipe.MaxSeconds,
        TargetRms = recipe.TargetRms,
        PeakCeiling = recipe.PeakCeiling,
    };

    public static RecipeVoice VoiceOf(CastVoice voice, string language, VoiceReference reference) => new()
    {
        Voice = voice.Name,
        Shift = voice.Shift == 1.0 ? null : voice.Shift,
        Language = language,
        Seconds = Math.Round(reference.Clip.Seconds, 2),
        Lines = reference.Kept.Select(k => new RecipeLine
        {
            Hash = Fnv1a64.OfDepotPath(k.DepotPath).ToString("x16"),
            Path = k.DepotPath,
        }).ToList(),
    };

    // Une execution sur un personnage, ou sur une langue, ne doit pas effacer les autres :
    // meme raison que pour le manifeste, et la cle est ici le couple personnage + langue.
    public void MergeInto(string file)
    {
        var merged = new List<RecipeVoice>();
        if (File.Exists(file))
        {
            var previous = JsonSerializer.Deserialize<Recipe>(File.ReadAllText(file));
            var written = Voices.Select(Key).ToHashSet(StringComparer.OrdinalIgnoreCase);
            merged.AddRange(previous.Voices.Where(v => !written.Contains(Key(v))));
        }
        merged.AddRange(Voices);
        merged = merged
            .OrderBy(v => v.Language, StringComparer.Ordinal)
            .ThenBy(v => CastOrder(v.Voice))
            .ToList();

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(file)));
        var json = JsonSerializer.Serialize(new Recipe { Settings = Settings, Voices = merged },
                                            new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(file, json + "\n", new UTF8Encoding(false));
    }

    private static string Key(RecipeVoice voice) => voice.Language + "/" + voice.Voice;

    private static int CastOrder(string name)
    {
        var index = Array.FindIndex(VoiceCast.All,
            c => string.Equals(c.Name, name, StringComparison.OrdinalIgnoreCase));
        return index < 0 ? int.MaxValue : index;
    }
}
