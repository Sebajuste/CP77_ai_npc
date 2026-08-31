namespace VoiceExtract;

// 48 kHz vers 22050 Hz par sinus cardinal fenetre. Une interpolation lineaire
// suffirait a la duree mais replierait le spectre au-dessus de 11 kHz, et ce repli
// s'entend sur les sifflantes — precisement ce qu'un moteur de clonage ecoute.
internal static class Resampler
{
    private const int HalfWidth = 24;

    public static PcmClip To(PcmClip clip, int targetRate)
    {
        if (clip.SampleRate == targetRate)
        {
            return clip;
        }
        var ratio = (double)targetRate / clip.SampleRate;
        var cutoff = Math.Min(1.0, ratio) * 0.92;
        var length = (int)(clip.Samples.Length * ratio);
        var output = new float[length];

        for (var i = 0; i < length; i++)
        {
            var center = i / ratio;
            var first = (int)Math.Floor(center) - HalfWidth;
            var last = (int)Math.Floor(center) + HalfWidth;
            var sum = 0.0;
            var weight = 0.0;
            for (var j = first; j <= last; j++)
            {
                if (j < 0 || j >= clip.Samples.Length)
                {
                    continue;
                }
                var x = j - center;
                var w = Sinc(x * cutoff) * Blackman(x);
                sum += clip.Samples[j] * w;
                weight += w;
            }
            output[i] = (float)Math.Clamp(weight == 0 ? 0 : sum / weight, -1.0, 1.0);
        }
        return new PcmClip(output, targetRate);
    }

    private static double Sinc(double x)
        => Math.Abs(x) < 1e-9 ? 1.0 : Math.Sin(Math.PI * x) / (Math.PI * x);

    private static double Blackman(double x)
    {
        var t = (x + HalfWidth) / (2.0 * HalfWidth);
        if (t < 0 || t > 1)
        {
            return 0;
        }
        return 0.42 - 0.5 * Math.Cos(2 * Math.PI * t) + 0.08 * Math.Cos(4 * Math.PI * t);
    }
}
