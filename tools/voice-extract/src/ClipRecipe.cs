namespace VoiceExtract;

// Les seuils de fabrication d'une reference. Ils sont ici parce qu'ils se discutent :
// c'est la seule chose du programme qu'on retouche apres avoir ecoute le resultat.
internal sealed class ClipRecipe
{
    // 48 kHz, le taux des archives : le reechantillonnage ne fait que retirer de la matiere.
    // Ecoute du 2026-08-31, sur la meme replique et la meme voix : « le 48k est aussi beaucoup
    // plus precis ». `-Rate 22050` reste possible pour un moteur qui l'exigerait.
    public int SampleRate { get; init; } = 48000;

    public double TargetSeconds { get; init; } = 30.0;

    public double MaxSeconds { get; init; } = 40.0;

    public double MinLineSeconds { get; init; } = 2.0;

    public double MaxLineSeconds { get; init; } = 8.0;

    public double GapSeconds { get; init; } = 0.25;

    // -48 dBFS : sous ce niveau une replique de jeu est du bruit de salle, pas de la voix.
    public double SilenceFloor { get; init; } = 0.004;

    // Une replique enregistree bas est une prise lointaine ou traitee dans la fiction. La
    // remonter au niveau des autres remonte aussi son fond ; on l'ecarte au lieu de la reparer.
    public double MinLineRms { get; init; } = 0.05;

    public double TargetRms { get; init; } = 0.1;

    public double PeakCeiling { get; init; } = 0.98;

}
