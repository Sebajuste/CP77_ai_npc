namespace VoiceExtract;

// Une voix que la recette sait refaire, et le motif qui choisit ses repliques parmi les noms de
// fichiers de doublage. Le motif porte sur le NOM DE FICHIER seul, pas sur le chemin.
//
// `Name` est le nom du fichier de reference sans son extension : c'est par lui qu'une fiche
// designe une voix (`clone`), et pas par un contact. Une voix derivee n'a pas d'entree : la fiche
// declare `shift`, et la DLL fabrique `<Name>-x<shift>.wav` depuis celle-ci.
//
// `Exclude` retire des repliques que le motif attrape mais que la voix ne doit pas apprendre.
internal sealed record CastVoice(string Name, string Pattern, string Note, string Exclude = null);

internal static class VoiceCast
{
    // River Ward parle sous l'etiquette "sobchak" : ses trois quetes (sq012, sq021,
    // sq029) sont la preuve, aucun fichier ne porte "river".
    public static readonly CastVoice[] All =
    {
        new("judy", "^judy_", null),
        new("panam", "^panam_", null),
        new("river_ward", "^sobchak_", "etiquette de doublage : sobchak"),
        new("takemura", "^takemura_", null),
        new("songbird", "^songbird_", "Phantom Liberty : archive ep1"),
        new("rogue", "^rogue_", null),
        new("victor_vector", "^victor_vector_", null),
        new("kerry_eurodyne", "^kerry_", null),
        new("jackie", "^jackie_", null),

        // V dit les repliques que le joueur tape pendant un holo. Le jeton `_f_` / `_m_` est le
        // timbre de voix choisi a la creation, pas le corps. Les `finalboards` sont les messages
        // holo de l'epilogue : passees a la radio, et une seule a passe le seuil de niveau.
        new("v_female", "^v_.*_f_[0-9a-f]+\\.wem$", "V, timbre feminin", "_finalboards_"),
        new("v_male", "^v_.*_m_[0-9a-f]+\\.wem$", "V, timbre masculin", "_finalboards_"),

        // Des passantes anonymes, pour les personnages que le jeu n'a pas doubles. Choisies a
        // l'oreille le 2026-09-10 : une voix sans role nomme ne rappelle aucune comedienne.
        new("civ_high_f_02_enus_30", "^civ_high_f_02_enus_30_", "passante anonyme"),
        new("civ_mid_f_21_enus_25", "^civ_mid_f_21_enus_25_", "passante anonyme"),

        // Le pot des inconnus qu'un mod fait naitre en jeu, relus a une vitesse tiree par contact
        // (AiNpcStrangerVoice). Pas choisis a l'oreille : les etiquettes enus les plus fournies.
        new("civ_mid_m_10_enus_30", "^civ_mid_m_10_enus_30_", "passant anonyme"),
        new("civ_mid_m_04_enus_30", "^civ_mid_m_04_enus_30_", "passant anonyme"),
        new("civ_high_m_07_enus_40", "^civ_high_m_07_enus_40_", "passant anonyme"),
        new("civ_high_m_02_enus_30", "^civ_high_m_02_enus_30_", "passant anonyme"),
        new("civ_mid_m_05_enus_40", "^civ_mid_m_05_enus_40_", "passant anonyme"),
        new("civ_high_f_01_enus_25", "^civ_high_f_01_enus_25_", "passante anonyme"),
        new("civ_high_f_04_enus_50", "^civ_high_f_04_enus_50_", "passante anonyme"),
    };

    // Des contacts du mod qui ne sont pas des voix. `stud` (Jesse) est un personnage original :
    // aucun doublage vanilla. `jackie_dead` est un etat de contact, pas quelqu'un qui parle.
    public static readonly string[] WithoutVanillaVoice = { "stud", "jackie_dead" };

    public static CastVoice Find(string name)
        => All.FirstOrDefault(c => string.Equals(c.Name, name, StringComparison.OrdinalIgnoreCase));
}
