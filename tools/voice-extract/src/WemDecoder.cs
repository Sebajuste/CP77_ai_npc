using NAudio.Vorbis;
using WolvenKit.Core.Wwise;

namespace VoiceExtract;

// Le doublage de Cyberpunk est du Wwise Vorbis (fmt 0xFFFF, en-tete de 66 octets).
// wwtools le ramene a un Ogg standard, NVorbis le decode.
internal static class WemDecoder
{
    public static PcmClip Decode(byte[] wem)
    {
        var ogg = Wem.Convert(wem);
        if (ogg is null || ogg.Length == 0)
        {
            return null;
        }
        using var source = new MemoryStream(ogg);
        using var reader = new VorbisWaveReader(source);

        var channels = reader.WaveFormat.Channels;
        var mono = new List<float>();
        var frame = new float[channels * 4096];
        int read;
        while ((read = reader.Read(frame, 0, frame.Length)) > 0)
        {
            for (var i = 0; i + channels <= read; i += channels)
            {
                var sum = 0f;
                for (var c = 0; c < channels; c++)
                {
                    sum += frame[i + c];
                }
                mono.Add(sum / channels);
            }
        }
        return mono.Count == 0 ? null : new PcmClip(mono.ToArray(), reader.WaveFormat.SampleRate);
    }
}
