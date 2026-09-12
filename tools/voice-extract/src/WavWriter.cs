using System.Text;

namespace VoiceExtract;

// WAV PCM 16 bits mono : le format que les moteurs de synthese acceptent sans discuter.
internal static class WavWriter
{
    public static void Write(string file, PcmClip clip)
    {
        var rate = clip.SampleRate;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(file)));
        using var stream = File.Create(file);
        using var w = new BinaryWriter(stream, Encoding.ASCII);

        var dataBytes = clip.Samples.Length * 2;
        w.Write(Encoding.ASCII.GetBytes("RIFF"));
        w.Write(36 + dataBytes);
        w.Write(Encoding.ASCII.GetBytes("WAVE"));
        w.Write(Encoding.ASCII.GetBytes("fmt "));
        w.Write(16);
        w.Write((short)1);
        w.Write((short)1);
        w.Write(rate);
        w.Write(rate * 2);
        w.Write((short)2);
        w.Write((short)16);
        w.Write(Encoding.ASCII.GetBytes("data"));
        w.Write(dataBytes);
        foreach (var sample in clip.Samples)
        {
            w.Write((short)Math.Clamp(Math.Round(sample * 32767.0), short.MinValue, short.MaxValue));
        }
    }
}
