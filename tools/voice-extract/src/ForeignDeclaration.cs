namespace VoiceExtract;

// Ce qu'un AUTRE mod doit ecrire pour que sa voix existe chez le joueur.
//
// ai_npc ne livre de recette que pour son propre casting. Un mod qui donne la parole a un
// personnage vanilla qu'ai_npc ignore -- Fingers, par exemple -- ne peut pas demander « toutes
// les repliques de cette etiquette » : les archives ne portent que des hachages de chemin. Il
// nomme donc ses repliques, et c'est cette liste-la que l'outil imprime ici, prete a coller
// dans son `GetVoice()` ou dans sa fiche JSON.
//
// La liste est celle qui a servi a l'extrait qu'on vient d'ecouter, dans cet ordre : ce qui est
// juge est ce qui sera dit.
internal static class ForeignDeclaration
{
    public static void Print(string voiceName, IReadOnlyList<KeptLine> kept)
    {
        Console.WriteLine();
        Console.WriteLine($"    declaration pour un autre mod -- {kept.Count} replique(s) :");
        Console.WriteLine();
        Console.WriteLine("    voice.clone = \"" + voiceName + ".wav\";");
        foreach (var line in kept)
        {
            Console.WriteLine("    ArrayPush(voice.cloneLines, \"" + Path.GetFileName(line.DepotPath) + "\");");
        }
        Console.WriteLine();
    }
}
