using System.Text.RegularExpressions;

namespace VoiceExtract;

// Les archives de doublage du jeu vues comme un seul corpus : le jeu de base et
// Phantom Liberty, chacun avec son dossier de langue. Rien n'est ecrit ici, jamais.
internal sealed class VoiceSource : IDisposable
{
    private readonly List<ArchiveIndex> _archives = new();
    private readonly List<string> _directories = new();
    private string[] _voiceLines;

    public IReadOnlyList<string> ArchiveFiles => _archives
        .Select(a => Path.Combine(Path.GetFileName(Path.GetDirectoryName(a.FilePath)), Path.GetFileName(a.FilePath)))
        .ToArray();

    public static VoiceSource Open(string gameDirectory, string language)
    {
        var source = new VoiceSource();
        foreach (var (folder, tree) in new[] { ("content", "base"), ("ep1", "ep1") })
        {
            var archive = Path.Combine(gameDirectory, "archive", "pc", folder, "lang_" + language + "_voice.archive");
            if (!File.Exists(archive))
            {
                continue;
            }
            source._archives.Add(ArchiveIndex.Open(archive));
            source._directories.Add(Path.Combine(tree, "localization", LocaleFolder(language), "vo"));
        }
        if (source._archives.Count == 0)
        {
            throw new FileNotFoundException(
                "aucune archive de doublage " + language + " sous " + gameDirectory);
        }
        return source;
    }

    // Le doublage "vo_holocall" et "vo_helmet" est filtre a la prise : c'est le meme
    // comedien passe a la radio, et un moteur de clonage apprendrait le filtre.
    // Les "voice sets" -- jeton `vs` dans le nom -- sont les repliques d'ambiance et de combat :
    // des interjections lancees a la volee, souvent passees a la radio dans la fiction. Elles ne
    // sont pas du dialogue, et une seule suffit a donner un timbre metallique a tout l'extrait :
    // celle de Jackie etait deux fois plus forte que ses repliques de scene et deux fois plus
    // etroite de bande. Ecarte pour ce qu'elle est, pas pour ce qu'elle mesure.
    private static readonly Regex VoiceSet = new(@"_vsets?_", RegexOptions.IgnoreCase);

    public IEnumerable<string> LinesMatching(DepotDictionary dictionary, string pattern, string exclude)
    {
        var regex = new Regex(pattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        var rejected = exclude is null
            ? null
            : new Regex(exclude, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        return AllLines(dictionary).Where(path =>
        {
            var name = Path.GetFileName(path);
            return regex.IsMatch(name)
                   && !VoiceSet.IsMatch(name)
                   && (rejected is null || !rejected.IsMatch(name));
        });
    }

    // Le dictionnaire fait 135 Mo : on ne le traverse qu'une fois, et on garde les
    // 110 000 chemins de doublage qui en sortent.
    private string[] AllLines(DepotDictionary dictionary)
    {
        _voiceLines ??= _directories
            .SelectMany(dictionary.UnderDirectory)
            .Where(p => p.EndsWith(".wem", StringComparison.OrdinalIgnoreCase))
            .ToArray();
        return _voiceLines;
    }

    public byte[] ReadRaw(string depotPath) => ReadRawByHash(Fnv1a64.OfDepotPath(depotPath));

    public byte[] ReadRawByHash(ulong hash)
    {
        foreach (var archive in _archives)
        {
            var raw = archive.ReadRawByHash(hash);
            if (raw is not null)
            {
                return raw;
            }
        }
        return null;
    }

    private static string LocaleFolder(string language) => language switch
    {
        "en" => "en-us",
        "fr" => "fr-fr",
        "de" => "de-de",
        "es-es" => "es-es",
        "it" => "it-it",
        "jp" => "jp-jp",
        "kr" => "kr-kr",
        "pl" => "pl-pl",
        "pt" => "pt-br",
        "ru" => "ru-ru",
        "zh-cn" => "zh-cn",
        _ => throw new ArgumentException("langue de doublage inconnue : " + language),
    };

    public void Dispose()
    {
        foreach (var archive in _archives)
        {
            archive.Dispose();
        }
    }
}
