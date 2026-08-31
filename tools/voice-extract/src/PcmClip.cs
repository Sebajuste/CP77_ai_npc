namespace VoiceExtract;

// Un tampon mono en virgule flottante, et les mesures qu'on lui demande.
internal sealed class PcmClip
{
    public float[] Samples { get; }

    public int SampleRate { get; }

    public PcmClip(float[] samples, int sampleRate)
    {
        Samples = samples;
        SampleRate = sampleRate;
    }

    public double Seconds => (double)Samples.Length / SampleRate;

    public double Rms
    {
        get
        {
            var sum = 0.0;
            foreach (var s in Samples)
            {
                sum += (double)s * s;
            }
            return Samples.Length == 0 ? 0 : Math.Sqrt(sum / Samples.Length);
        }
    }

    public double Peak
    {
        get
        {
            var peak = 0.0;
            foreach (var s in Samples)
            {
                peak = Math.Max(peak, Math.Abs(s));
            }
            return peak;
        }
    }

    public PcmClip Scaled(double gain)
    {
        var scaled = new float[Samples.Length];
        for (var i = 0; i < Samples.Length; i++)
        {
            scaled[i] = (float)Math.Clamp(Samples[i] * gain, -1.0, 1.0);
        }
        return new PcmClip(scaled, SampleRate);
    }

    // Coupe le silence de tete et de queue : les repliques de jeu portent souvent une
    // amorce muette qui, mise bout a bout, gonfle la duree sans porter de voix.
    public PcmClip Trimmed(double threshold)
    {
        var first = 0;
        while (first < Samples.Length && Math.Abs(Samples[first]) < threshold)
        {
            first++;
        }
        var last = Samples.Length - 1;
        while (last > first && Math.Abs(Samples[last]) < threshold)
        {
            last--;
        }
        if (last <= first)
        {
            return new PcmClip(Array.Empty<float>(), SampleRate);
        }
        return new PcmClip(Samples[first..(last + 1)], SampleRate);
    }
}
