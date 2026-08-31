namespace VoiceExtract;

// Un personnage du mod, et le motif qui selectionne ses repliques parmi les noms de
// fichiers de doublage. Le motif porte sur le NOM DE FICHIER seul, pas sur le chemin.
internal sealed record VoiceCharacter(string ContactId, string Pattern, string Note);

internal static class VoiceCast
{
    // River Ward parle sous l'etiquette "sobchak" : ses trois quetes (sq012, sq021,
    // sq029) sont la preuve, aucun fichier ne porte "river".
    public static readonly VoiceCharacter[] All =
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
        new("jackie_dead", "^jackie_", "meme voix que jackie"),
    };

    // "stud" (Jesse) est un personnage original du mod : aucun doublage vanilla.
    public static readonly string[] WithoutVanillaVoice = { "stud" };

    public static VoiceCharacter Find(string contactId)
        => All.FirstOrDefault(c => string.Equals(c.ContactId, contactId, StringComparison.OrdinalIgnoreCase));
}
