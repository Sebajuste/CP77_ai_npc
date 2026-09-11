// Playing sound from memory, with no file anywhere.
//
// The mod's own depot is not writable: r6\audioware\ is Vortex's, its files are hardlinks
// into the staging folder, and writing there writes through the link into the source copy of
// a mod. r6\storages\ is writable and is not a depot any audio engine reads. So a generated
// utterance -- which is what a text-to-speech lane produces -- has nowhere to be a file, and
// the only remaining path is a buffer.
//
// This plays that buffer through waveOut, which is Windows' own mixer and not the game's.
// What that costs is stated once, here, because no caller can work it out:
//
//   - no ducking against game audio, and no game volume slider;
//   - it keeps playing while the game is paused or alt-tabbed;
//   - it goes to the output the game plays on (ProcessOutput.hpp), and to the system default
//     only when that cannot be found.
//
// No RED4ext dependency, on purpose: that is what lets plugin\test\run.ps1 build and run it
// outside the game.

#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace ainpc::audio
{
// Uncompressed PCM, the only thing waveOut takes.
struct Format
{
    uint32_t sampleRate = 22050;
    uint16_t channels = 1;
    uint16_t bitsPerSample = 16;
};

// Why a buffer was refused. Every failure names itself: a voice that does not come out is
// otherwise indistinguishable from a voice that was never asked for.
enum class Status
{
    Ok = 0,
    EmptyBuffer,
    UnsupportedFormat,
    NoDevice,       // waveOutOpen refused -- no output, or the device is held exclusively
    WriteFailed,
    NotWave,        // the RIFF image is not a WAVE
    NotPcm,         // a WAVE, but compressed
    Truncated,      // the image ends inside the data it announces
};

const char* Describe(Status aStatus);

// Plays raw samples. The buffer is COPIED, so the caller's memory is free on return.
//
// Returns immediately: playback runs on a thread of its own, which is why this is callable
// from the game thread. A second call replaces what is playing -- one voice at a time, since
// two characters talking over each other is not a feature.
Status Play(const void* aSamples, size_t aBytes, const Format& aFormat);

// UNE PRISE DE PAROLE QUI ARRIVE EN MORCEAUX.
//
// Play() veut la replique entiere avant d'en jouer la premiere milliseconde, et c'est ce qui
// coutait le plus a la voie parlee : le moteur produit son premier morceau en 123 ms et
// personne ne l'entendait avant la fin de la synthese, une a deux secondes plus tard.
//
// « Une voix a la fois » ne bouge pas -- c'est la meme voix, elle arrive en plusieurs fois.
// Open() coupe ce qui jouait, exactement comme un second Play().
//
//   Open(format)          ouvre une replique ; poursuit la sortie ouverte au meme format,
//                         coupe celle d'un autre format
//   Push(bytes)           met un morceau a la file ; il joue apres ceux deja ecrits
//   Close()               la replique est finie
//
// LA SORTIE SURVIT A SES REPLIQUES. Une sortie qui vient d'ouvrir avale le debut de son premier
// tampon, donc elle reste ouverte, nourrie de silence, et ne se ferme qu'apres 20 s sans servir.
// Une replique attend au plus 100 ms de silence deja en file.
//
// Push() apres Close(), ou sans Open(), rend NoDevice : une replique fermee ne se rouvre pas, et
// une voix qui reprendrait apres sa fin serait un morceau joue hors de son tour.
Status Open(const Format& aFormat);
Status Push(const void* aSamples, size_t aBytes);
void Close();

// Ouvre la sortie d'avance, sans replique, pour que la parole a venir trouve un flux en marche.
// Appelee quand une reponse est demandee, pendant que le modele ecrit. Une sortie deja ouverte,
// a n'importe quel format, est seulement prolongee : amorcer ne coupe personne. `aOpened` dit
// si elle a du s'ouvrir.
Status Prime(const Format& aFormat, bool& aOpened);

// Ce que la sortie a fait depuis la derniere lecture, remis a zero par elle.
//
//   openings   repliques qui ont du ouvrir la sortie -- chacune a perdu son debut
//   gaps       fois ou une replique ouverte a vide la file avant son morceau suivant : la
//              synthese n'a pas suivi la lecture, et un silence s'est glisse dans la phrase
struct Counters
{
    uint32_t openings = 0;
    uint32_t gaps = 0;
};
Counters TakeCounters();

// Marque les morceaux a venir comme appartenant a cette replique. Zero pour "sans replique",
// ce qui est le cas d'un bip.
//
// Une file qui ne sait pas ce qu'elle joue ne peut pas etre suivie : le sous-titre devrait
// deviner une duree, et deviner faux est ce qui faisait sauter l'affichage a la derniere phrase
// pendant que la premiere se jouait encore.
void SetLine(uint32_t aLine);

// La replique dont le son sort MAINTENANT du haut-parleur : celle du premier morceau que le
// peripherique n'a pas encore rendu. Zero quand plus rien ne joue.
uint32_t PlayingLine();

// The same, from a WAV image held in memory: header and samples as a file would have them,
// but never written down. The whole RIFF walk is here and validates as one -- a caller gets
// a Status, never a half-parsed header.
Status PlayWav(const void* aImage, size_t aBytes);

// A tone, generated rather than loaded: the one sound this mod can make with no asset to
// ship, no manifest to declare and no file to read. It is what proves the path.
struct Sound
{
    std::vector<uint8_t> samples;
    Format format;
};

Sound Tone(double aSeconds, double aHertz, double aAmplitude);

// Which output the last Play() actually went to, as Windows names it.
//
// "It played, and I heard nothing" is the answer that costs the most time. The name says
// whether the sound followed the game or fell back to the system default. Empty before the
// first play.
std::string DeviceName();

// Every output Windows can see, in its own order.
std::vector<std::string> Outputs();

// Silence now, and the output closes. Safe to call when nothing is playing.
void Stop();

// Reste-t-il de la parole a entendre ? Le silence de la sortie ouverte ne compte pas.
bool IsPlaying();
}
