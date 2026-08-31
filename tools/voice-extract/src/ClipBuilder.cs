namespace VoiceExtract;

internal sealed record LineMeasure(string DepotPath, double Seconds, double Rms, string Verdict);

internal sealed record KeptLine(string DepotPath, PcmClip Native);

internal sealed record VoiceReference(PcmClip Clip, IReadOnlyList<KeptLine> Kept, IReadOnlyList<LineMeasure> Examined);

// Assemble une reference d'une trentaine de secondes a partir des repliques d'un
// personnage : plusieurs repliques moyennes valent mieux qu'une longue, et deux voisines de
// la meme scene se ressemblent trop pour apporter deux fois de la matiere.
//
// Les repliques ne sont PAS mises au meme niveau les unes des autres. Le rapport de niveau
// entre deux prises est une information sur la voix ; l'egaliser fabrique une dynamique
// ecrasee que le moteur de clonage reproduit ensuite. Une seule mise a niveau, a la fin,
// sur l'extrait entier.
internal static class ClipBuilder
{
    public static VoiceReference Build(IEnumerable<string> depotPaths, VoiceSource source, ClipRecipe recipe)
    {
        var candidates = ExamineOrder(depotPaths);
        var taken = new List<float>();
        var kept = new List<KeptLine>();
        var examined = new List<LineMeasure>();
        var gap = new float[(int)(recipe.GapSeconds * recipe.SampleRate)];

        foreach (var depotPath in candidates)
        {
            if (taken.Count >= recipe.TargetSeconds * recipe.SampleRate)
            {
                break;
            }
            var (native, measure) = Prepare(depotPath, source, recipe);
            examined.Add(measure);
            if (native is null)
            {
                continue;
            }
            if (taken.Count > 0)
            {
                taken.AddRange(gap);
            }
            taken.AddRange(Resampler.To(native, recipe.SampleRate).Samples);
            kept.Add(new KeptLine(depotPath, native));
        }

        var ceiling = (int)(recipe.MaxSeconds * recipe.SampleRate);
        if (taken.Count > ceiling)
        {
            taken.RemoveRange(ceiling, taken.Count - ceiling);
        }
        var clip = new PcmClip(taken.ToArray(), recipe.SampleRate);
        return new VoiceReference(Levelled(clip, recipe), kept, examined);
    }

    private static PcmClip Levelled(PcmClip clip, ClipRecipe recipe)
    {
        var rms = clip.Rms;
        if (rms < 1e-9)
        {
            return clip;
        }
        var gain = Math.Min(recipe.TargetRms / rms, recipe.PeakCeiling / Math.Max(clip.Peak, 1e-6));
        return clip.Scaled(gain);
    }

    private static (PcmClip, LineMeasure) Prepare(string depotPath, VoiceSource source, ClipRecipe recipe)
    {
        var wem = source.ReadRaw(depotPath);
        var decoded = wem is null ? null : WemDecoder.Decode(wem);
        if (decoded is null)
        {
            return (null, new LineMeasure(depotPath, 0, 0, "illisible"));
        }
        var trimmed = decoded.Trimmed(recipe.SilenceFloor);
        var measure = new LineMeasure(depotPath, trimmed.Seconds, trimmed.Rms, "prise");

        if (trimmed.Seconds < recipe.MinLineSeconds || trimmed.Seconds > recipe.MaxLineSeconds)
        {
            return (null, measure with { Verdict = "duree" });
        }
        if (trimmed.Rms < recipe.MinLineRms)
        {
            return (null, measure with { Verdict = "niveau" });
        }
        return (trimmed, measure);
    }

    // L'ordre d'examen, et c'est lui qui decide de quoi l'extrait est fait.
    //
    // Trier par chemin puis avancer a pas fixe ne marche PAS : la boucle s'arrete des les
    // 30 secondes atteintes, donc elle n'examine qu'une dizaine de candidats, tous pris au
    // debut de la liste. Sur Judy cela donnait `finalboards`, `mq055`, `q004`, `q105` --
    // messages holo et appartement -- et jamais `sq026` ni `sq030`, ses 780 repliques de
    // dialogue, qui viennent plus loin dans l'alphabet.
    //
    // La cle de tri est donc un hachage du chemin : les dix premiers candidats examines sont
    // deja un echantillon de tout le corpus, et l'ordre reste le meme d'une execution a l'autre.
    private static IEnumerable<string> ExamineOrder(IEnumerable<string> depotPaths)
        => depotPaths.OrderBy(Fnv1a64.OfDepotPath).ToArray();
}
