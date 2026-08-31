using System.Reflection;

namespace VoiceExtract;

internal sealed class Options
{
    public string Game { get; private set; } = @"D:\Jeux\Cyberpunk 2077";

    public string WolvenKit { get; private set; } = BuiltInWolvenKitDirectory();

    public string Out { get; private set; } = "dist/voices";

    public string Cache { get; private set; } = "tools/voice-extract/cache";

    public string Language { get; private set; } = "fr";

    public bool ListOnly { get; private set; }

    public bool ShowLines { get; private set; }

    public string Pattern { get; private set; }

    public string Exclude { get; private set; }

    public int Rate { get; private set; } = 48000;

    public bool Raw { get; private set; }

    public List<string> Characters { get; } = new();

    public static Options Parse(string[] args)
    {
        var options = new Options();
        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--game": options.Game = args[++i]; break;
                case "--wolvenkit": options.WolvenKit = args[++i]; break;
                case "--out": options.Out = args[++i]; break;
                case "--cache": options.Cache = args[++i]; break;
                case "--language": options.Language = args[++i]; break;
                case "--list": options.ListOnly = true; break;
                case "--show-lines": options.ShowLines = true; break;
                case "--pattern": options.Pattern = args[++i]; break;
                case "--exclude": options.Exclude = args[++i]; break;
                case "--rate": options.Rate = int.Parse(args[++i]); break;
                case "--raw": options.Raw = true; break;
                default:
                    if (args[i].StartsWith("--"))
                    {
                        throw new ArgumentException("option inconnue : " + args[i]);
                    }
                    options.Characters.Add(args[i]);
                    break;
            }
        }
        if (options.Characters.Count == 0)
        {
            options.Characters.AddRange(VoiceCast.All.Select(c => c.ContactId));
        }
        return options;
    }

    private static string BuiltInWolvenKitDirectory()
        => Assembly.GetExecutingAssembly()
               .GetCustomAttributes<AssemblyMetadataAttribute>()
               .FirstOrDefault(a => a.Key == "WolvenKitDir")?.Value
           ?? throw new InvalidOperationException("WolvenKitDir absent des metadonnees de l'assembly");
}
