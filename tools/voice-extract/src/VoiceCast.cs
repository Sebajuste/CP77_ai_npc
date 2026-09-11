namespace VoiceExtract;

// Une voix que la recette sait refaire, le motif qui choisit ses repliques parmi les noms de
// fichiers de doublage, et le facteur qui la derive. Le motif porte sur le NOM DE FICHIER seul,
// pas sur le chemin.
//
// `Name` est le nom du fichier de reference sans son extension : c'est par lui qu'une fiche
// designe une voix (`clone`), et pas par un contact.
//
// `Shift` relit la reference plus vite ou plus lentement : hauteur et formants bougent ensemble,
// et c'est ce qui fait d'une voix du jeu une personne nouvelle.
internal sealed record CastVoice(string Name, string Pattern, double Shift, string Note);

internal static class VoiceCast
{
    // River Ward parle sous l'etiquette "sobchak" : ses trois quetes (sq012, sq021,
    // sq029) sont la preuve, aucun fichier ne porte "river".
    public static readonly CastVoice[] All =
    {
        new("judy", "^judy_", 1.0, null),
        new("panam", "^panam_", 1.0, null),
        new("river_ward", "^sobchak_", 1.0, "etiquette de doublage : sobchak"),
        new("takemura", "^takemura_", 1.0, null),
        new("songbird", "^songbird_", 1.0, "Phantom Liberty : archive ep1"),
        new("rogue", "^rogue_", 1.0, null),
        new("victor_vector", "^victor_vector_", 1.0, null),
        new("kerry_eurodyne", "^kerry_", 1.0, null),
        new("jackie", "^jackie_", 1.0, null),

        // Des passantes anonymes, pour les personnages que le jeu n'a pas doubles. Choisies a
        // l'oreille le 2026-09-10 : une voix sans role nomme ne rappelle aucune comedienne.
        new("civ_high_f_02_enus_30-x1.08", "^civ_high_f_02_enus_30_", 1.08, "passante anonyme, derivee"),
        new("civ_mid_f_21_enus_25", "^civ_mid_f_21_enus_25_", 1.0, "passante anonyme"),
    };

    // Des contacts du mod qui ne sont pas des voix. `stud` (Jesse) est un personnage original :
    // aucun doublage vanilla. `jackie_dead` est un etat de contact, pas quelqu'un qui parle.
    public static readonly string[] WithoutVanillaVoice = { "stud", "jackie_dead" };

    public static CastVoice Find(string name)
        => All.FirstOrDefault(c => string.Equals(c.Name, name, StringComparison.OrdinalIgnoreCase));
}
