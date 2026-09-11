#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>

#include "Audio.hpp"
#include "ProcessOutput.hpp"

#include <chrono>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace ainpc::audio
{
namespace
{
// Un morceau de la prise de parole. waveOut veut que les echantillons ET l'en-tete restent en
// place jusqu'a ce qu'il rende le morceau -- longtemps apres que l'appelant est reparti -- donc
// chacun possede sa memoire et ne bouge plus. `unique_ptr` parce que la file grandit pendant
// que le pilote tient des pointeurs dedans : un vecteur qui se reallouerait les invaliderait.
struct Chunk
{
    std::vector<uint8_t> samples;
    WAVEHDR header{};
    bool prepared = false;

    // A quelle replique ce morceau appartient. C'est par lui qu'on sait ce qui sort du
    // haut-parleur a cet instant, plutot que par un chronometre lance a cote.
    uint32_t line = 0;

    // Du silence ecrit par la sortie elle-meme pour ne jamais tomber a vide.
    bool filler = false;
};

// Une sortie qui vient d'ouvrir avale le debut de son premier tampon : 150 ms de bip n'ont pas
// ete entendus (2026-08-31). Elle reste donc ouverte et nourrie de silence tant que la voix a
// servi recemment, et la parole arrive sur un flux deja en marche.
constexpr std::chrono::seconds kLinger{20};

// Le silence d'avance que la sortie garde en file. Borne aussi ce qu'une replique attend
// derriere lui.
constexpr uint32_t kFillerMilliseconds = 50;
constexpr uint32_t kFillerAhead = 2;

// One voice, and the state that outlives the call that started it.
struct Voice
{
    // Ouvrir, amorcer et arreter se suivent sous ce verrou : le fil de jeu amorce pendant que le
    // worker ouvre, et deux ouvertures croisees laisseraient un fil de vidange joignable ecrase.
    // Le fil de vidange ne le prend jamais.
    std::mutex lifecycle;

    std::mutex mutex;
    HWAVEOUT device = nullptr;
    std::vector<std::unique_ptr<Chunk>> chunks;
    std::thread drain;
    // La replique dont les morceaux arrivent. Ecrite avant de remplir, lue par chaque morceau.
    uint32_t line = 0;

    // Le format de la prise en cours. Une phrase qui arrive au meme format continue la prise
    // ouverte ; un format different est une autre voix, et celle-la remplace.
    Format format{};
    // La replique en cours est finie. La sortie, elle, reste ouverte jusqu'a kLinger.
    bool closed = false;
    // Stop() : le fil de vidange ferme sans attendre kLinger.
    bool stopping = false;
    std::string device_name;

    // Le dernier instant ou la voix a servi : parole en file, amorce ou ouverture.
    std::chrono::steady_clock::time_point lastUse{};

    // La replique ouverte a deja pousse un morceau ; avant, une file vide n'est pas un trou.
    bool lineHeard = false;
    bool starving = false;
    Counters counters{};

    // A LA FIN DU PROCESSUS, et c'est le fil de vidange qui l'exige.
    //
    // Il se termine tout seul quand la prise est finie, mais l'objet std::thread reste
    // JOIGNABLE tant que personne ne l'a joint -- et detruire un std::thread joignable appelle
    // std::terminate. Le mod ne le voyait pas parce que speech::Shutdown() appelle Stop(), qui
    // joint ; un banc qui sort sans Stop plantait a l'exit, apres avoir tout joue correctement.
    // Mesure du 2026-09-02, code de sortie 0xC0000409.
    ~Voice()
    {
        if (device != nullptr)
        {
            waveOutReset(device);
        }
        stopping = true;
        if (drain.joinable())
        {
            drain.join();
        }
    }
};

Voice& TheVoice()
{
    static Voice voice;
    return voice;
}

// Closes the device and releases every buffer, on the drain thread or on Stop's caller.
// waveOutReset must have run first, or unpreparing a header still queued fails.
void Release(Voice& aVoice)
{
    if (aVoice.device == nullptr)
    {
        return;
    }
    for (auto& chunk : aVoice.chunks)
    {
        if (chunk->prepared)
        {
            waveOutUnprepareHeader(aVoice.device, &chunk->header, sizeof(WAVEHDR));
        }
    }
    waveOutClose(aVoice.device);
    aVoice.device = nullptr;
    aVoice.chunks.clear();
    aVoice.closed = false;
    aVoice.stopping = false;
    aVoice.lineHeard = false;
    aVoice.starving = false;
}

bool Done(const Chunk& aChunk)
{
    return (aChunk.header.dwFlags & WHDR_DONE) != 0;
}

// Reste-t-il de la parole a entendre ? Sous le verrou de l'appelant.
bool SpeechPending(const Voice& aVoice)
{
    for (const auto& chunk : aVoice.chunks)
    {
        if (!chunk->filler && !Done(*chunk))
        {
            return true;
        }
    }
    return false;
}

size_t PendingBytes(const Voice& aVoice)
{
    size_t bytes = 0;
    for (const auto& chunk : aVoice.chunks)
    {
        if (!Done(*chunk))
        {
            bytes += chunk->samples.size();
        }
    }
    return bytes;
}

// Rend la memoire des morceaux joues. Une sortie ouverte pour tout un appel ne peut pas les
// garder jusqu'a sa fermeture. waveOut les rend dans l'ordre d'ecriture.
void Recycle(Voice& aVoice)
{
    auto played = aVoice.chunks.begin();
    while (played != aVoice.chunks.end() && Done(**played))
    {
        waveOutUnprepareHeader(aVoice.device, &(*played)->header, sizeof(WAVEHDR));
        ++played;
    }
    aVoice.chunks.erase(aVoice.chunks.begin(), played);
}

// Sous le verrou de l'appelant, sur une sortie ouverte.
Status Write(Voice& aVoice, std::unique_ptr<Chunk> aChunk)
{
    aChunk->header.lpData = reinterpret_cast<LPSTR>(aChunk->samples.data());
    aChunk->header.dwBufferLength = static_cast<DWORD>(aChunk->samples.size());

    if (waveOutPrepareHeader(aVoice.device, &aChunk->header, sizeof(WAVEHDR)) != MMSYSERR_NOERROR)
    {
        return Status::WriteFailed;
    }
    aChunk->prepared = true;
    if (waveOutWrite(aVoice.device, &aChunk->header, sizeof(WAVEHDR)) != MMSYSERR_NOERROR)
    {
        waveOutUnprepareHeader(aVoice.device, &aChunk->header, sizeof(WAVEHDR));
        return Status::WriteFailed;
    }
    aVoice.chunks.push_back(std::move(aChunk));
    return Status::Ok;
}

// Garde kFillerAhead morceaux de silence d'avance quand la parole n'en fournit pas assez.
void TopUp(Voice& aVoice)
{
    const uint32_t blockAlign = aVoice.format.channels * (aVoice.format.bitsPerSample / 8u);
    const size_t fillerBytes = static_cast<size_t>(aVoice.format.sampleRate) * kFillerMilliseconds / 1000u * blockAlign;
    // Le silence du PCM 8 bits est au milieu de l'echelle, pas a zero.
    const uint8_t zero = aVoice.format.bitsPerSample == 8 ? 0x80 : 0x00;

    while (PendingBytes(aVoice) < fillerBytes * kFillerAhead)
    {
        auto chunk = std::make_unique<Chunk>();
        chunk->samples.assign(fillerBytes, zero);
        chunk->filler = true;
        // Un trou au milieu d'une replique lui appartient encore : le sous-titre ne clignote pas.
        chunk->line = aVoice.closed ? 0 : aVoice.line;
        if (Write(aVoice, std::move(chunk)) != Status::Ok)
        {
            return;
        }
    }
}

// Joins the previous voice before starting a new one. Called with the lock NOT held: the
// drain thread takes it to finish, so joining under the lock deadlocks.
void StopAndJoin()
{
    Voice& voice = TheVoice();
    std::thread previous;
    {
        std::lock_guard<std::mutex> guard(voice.mutex);
        if (voice.device != nullptr)
        {
            waveOutReset(voice.device);
        }
        // Sans cette marque le fil de vidange attendrait kLinger avant de sortir, et le join
        // ci-dessous avec lui.
        voice.stopping = true;
        previous = std::move(voice.drain);
    }
    if (previous.joinable())
    {
        previous.join();
    }
    {
        std::lock_guard<std::mutex> guard(voice.mutex);
        Release(voice);
    }
}

// Reads a little-endian value at an offset the caller has already bounds-checked.
uint32_t ReadU32(const uint8_t* aAt)
{
    return static_cast<uint32_t>(aAt[0]) | (static_cast<uint32_t>(aAt[1]) << 8) |
           (static_cast<uint32_t>(aAt[2]) << 16) | (static_cast<uint32_t>(aAt[3]) << 24);
}

uint16_t ReadU16(const uint8_t* aAt)
{
    return static_cast<uint16_t>(static_cast<uint16_t>(aAt[0]) | (static_cast<uint16_t>(aAt[1]) << 8));
}

bool FourCC(const uint8_t* aAt, const char* aTag)
{
    return std::memcmp(aAt, aTag, 4) == 0;
}

constexpr uint16_t kFormatPcm = 1;
constexpr uint16_t kFormatExtensible = 0xFFFE;

// Device names reach redscript through Beep(), and this folder's encoding rule is hard: the
// A variants of the waveOut calls hand back the system ANSI codepage, so an accented device
// name -- "Casque pour telephone" with its accents -- would cross the boundary as mojibake.
// The W variants and one conversion keep it UTF-8 all the way.
std::string Utf8(const wchar_t* aText)
{
    if (aText == nullptr || aText[0] == L'\0')
    {
        return {};
    }
    const int bytes = WideCharToMultiByte(CP_UTF8, 0, aText, -1, nullptr, 0, nullptr, nullptr);
    if (bytes <= 1)
    {
        return {};
    }
    std::string out(static_cast<size_t>(bytes - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, aText, -1, out.data(), bytes, nullptr, nullptr);
    return out;
}

// Where a sound actually went, in words -- the answer to the one report that costs the most
// time, "it says ok and I hear nothing".
//
// waveOutGetID is asked of the OPEN handle, because WAVE_MAPPER is a request rather than a
// device. It does not always answer: on this machine it hands back the mapper's own id, whose
// caps are named "Microsoft Sound Mapper" in the system language -- a name that identifies
// nothing. That case is reported as what it is instead of being dressed up, and the number of
// outputs goes with it either way, since "one output" and "four outputs" turn the same
// silence into two different problems.
std::string NameOfOutput(HWAVEOUT aHandle, bool aFollowsProcess)
{
    const UINT count = waveOutGetNumDevs();
    std::string named = "the Windows default output, which the mapper would not name";

    UINT id = 0;
    WAVEOUTCAPSW caps{};
    if (waveOutGetID(aHandle, &id) == MMSYSERR_NOERROR && id != static_cast<UINT>(WAVE_MAPPER) &&
        waveOutGetDevCapsW(id, &caps, sizeof(caps)) == MMSYSERR_NOERROR)
    {
        named = Utf8(caps.szPname);
    }

    const std::string origin = aFollowsProcess
                                   ? "the game's own output, "
                                   : "the game's output not found, so ";
    return origin + named + " (" + std::to_string(count) + " output(s) on this machine)";
}

void Drain()
{
    Voice& self = TheVoice();
    for (;;)
    {
        {
            std::lock_guard<std::mutex> guard(self.mutex);
            if (self.device == nullptr)
            {
                return;
            }
            Recycle(self);

            const auto now = std::chrono::steady_clock::now();
            const bool speaking = SpeechPending(self);
            if (speaking)
            {
                self.lastUse = now;
            }
            else if (!self.closed && self.lineHeard && !self.starving)
            {
                self.starving = true;
                self.counters.gaps += 1;
            }

            if (self.stopping || (self.closed && !speaking && now - self.lastUse >= kLinger))
            {
                waveOutReset(self.device);
                Release(self);
                return;
            }
            TopUp(self);
        }
        Sleep(10);
    }
}

// Sous le verrou de l'appelant, une fois tout ce qui precedait joint et rendu.
Status OpenDevice(Voice& aVoice, const Format& aFormat, bool aLineOpen)
{
    // Asked at every opening, not once: the player can move the game to another output mid-session.
    const std::optional<unsigned> processOutput = ProcessOutput();
    const UINT target = processOutput ? *processOutput : WAVE_MAPPER;

    WAVEFORMATEX wave{};
    wave.wFormatTag = WAVE_FORMAT_PCM;
    wave.nChannels = aFormat.channels;
    wave.nSamplesPerSec = aFormat.sampleRate;
    wave.wBitsPerSample = aFormat.bitsPerSample;
    wave.nBlockAlign = static_cast<WORD>(aFormat.channels * (aFormat.bitsPerSample / 8));
    wave.nAvgBytesPerSec = aFormat.sampleRate * wave.nBlockAlign;

    if (waveOutOpen(&aVoice.device, target, &wave, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR)
    {
        aVoice.device = nullptr;
        return Status::NoDevice;
    }

    aVoice.device_name = NameOfOutput(aVoice.device, processOutput.has_value());
    aVoice.format = aFormat;
    aVoice.closed = !aLineOpen;
    aVoice.stopping = false;
    aVoice.lineHeard = false;
    aVoice.starving = false;
    aVoice.lastUse = std::chrono::steady_clock::now();

    // Le silence part tout de suite : c'est lui que l'ouverture avale, pas la parole.
    TopUp(aVoice);
    aVoice.drain = std::thread(&Drain);
    return Status::Ok;
}

bool SameFormat(const Format& aLeft, const Format& aRight)
{
    return aLeft.sampleRate == aRight.sampleRate && aLeft.channels == aRight.channels &&
           aLeft.bitsPerSample == aRight.bitsPerSample;
}

bool Supported(const Format& aFormat)
{
    return aFormat.channels != 0 && aFormat.sampleRate != 0 &&
           (aFormat.bitsPerSample == 8 || aFormat.bitsPerSample == 16);
}
}

const char* Describe(Status aStatus)
{
    switch (aStatus)
    {
    case Status::Ok: return "ok";
    case Status::EmptyBuffer: return "empty buffer";
    case Status::UnsupportedFormat: return "unsupported format";
    case Status::NoDevice: return "no output device accepted the format";
    case Status::WriteFailed: return "the device refused the buffer";
    case Status::NotWave: return "not a RIFF/WAVE image";
    case Status::NotPcm: return "a WAVE, but not uncompressed PCM";
    case Status::Truncated: return "the image ends inside its own data chunk";
    }
    return "unknown";
}

Sound Tone(double aSeconds, double aHertz, double aAmplitude)
{
    Sound sound;
    sound.format = Format{};

    const size_t frames = static_cast<size_t>(aSeconds * sound.format.sampleRate);
    sound.samples.resize(frames * 2);
    for (size_t i = 0; i < frames; ++i)
    {
        const double t = static_cast<double>(i) / sound.format.sampleRate;
        const auto value =
            static_cast<int16_t>(aAmplitude * 32767.0 * std::sin(6.283185307179586 * aHertz * t));
        sound.samples[i * 2] = static_cast<uint8_t>(value & 0xFF);
        sound.samples[i * 2 + 1] = static_cast<uint8_t>((value >> 8) & 0xFF);
    }
    return sound;
}

Status Open(const Format& aFormat)
{
    if (!Supported(aFormat))
    {
        return Status::UnsupportedFormat;
    }

    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> lifecycle(voice.lifecycle);
    {
        // UNE REPLIQUE N'EST PAS UNE SUITE DE REPLIQUES. La deuxieme phrase d'une reponse coupait
        // la premiere au milieu d'un mot quand chaque phrase ouvrait sa propre prise (2026-09-02).
        // Une sortie ouverte au meme format se poursuit : la phrase se range derriere ce qui reste.
        std::lock_guard<std::mutex> guard(voice.mutex);
        if (voice.device != nullptr && !voice.stopping && SameFormat(voice.format, aFormat))
        {
            voice.closed = false;
            voice.lineHeard = false;
            voice.starving = false;
            voice.lastUse = std::chrono::steady_clock::now();
            return Status::Ok;
        }
    }

    StopAndJoin();

    std::lock_guard<std::mutex> guard(voice.mutex);
    const Status opened = OpenDevice(voice, aFormat, true);
    if (opened == Status::Ok)
    {
        voice.counters.openings += 1;
    }
    return opened;
}

Status Prime(const Format& aFormat, bool& aOpened)
{
    aOpened = false;
    if (!Supported(aFormat))
    {
        return Status::UnsupportedFormat;
    }

    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> lifecycle(voice.lifecycle);
    {
        // Une sortie deja ouverte, a n'importe quel format, garde ce qu'elle joue : amorcer ne
        // coupe personne.
        std::lock_guard<std::mutex> guard(voice.mutex);
        if (voice.device != nullptr && !voice.stopping)
        {
            voice.lastUse = std::chrono::steady_clock::now();
            return Status::Ok;
        }
    }

    // Joint le fil de vidange d'une sortie fermee par kLinger, que personne n'a encore joint.
    StopAndJoin();

    std::lock_guard<std::mutex> guard(voice.mutex);
    const Status opened = OpenDevice(voice, aFormat, false);
    aOpened = opened == Status::Ok;
    return opened;
}

Status Push(const void* aSamples, size_t aBytes)
{
    if (aSamples == nullptr || aBytes == 0)
    {
        return Status::EmptyBuffer;
    }

    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);
    // Une replique fermee ne se rouvre pas : un morceau ecrit apres sa fin jouerait hors de son
    // tour, ou derriere la suivante.
    if (voice.device == nullptr || voice.closed || voice.stopping)
    {
        return Status::NoDevice;
    }

    auto chunk = std::make_unique<Chunk>();
    chunk->samples.assign(static_cast<const uint8_t*>(aSamples),
                          static_cast<const uint8_t*>(aSamples) + aBytes);
    chunk->line = voice.line;
    const Status written = Write(voice, std::move(chunk));
    if (written == Status::Ok)
    {
        voice.lineHeard = true;
        voice.starving = false;
        voice.lastUse = std::chrono::steady_clock::now();
    }
    return written;
}

Counters TakeCounters()
{
    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);
    const Counters taken = voice.counters;
    voice.counters = Counters{};
    return taken;
}

void SetLine(uint32_t aLine)
{
    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);
    voice.line = aLine;
}

uint32_t PlayingLine()
{
    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);
    if (voice.device == nullptr)
    {
        return 0;
    }
    for (const auto& chunk : voice.chunks)
    {
        if ((chunk->header.dwFlags & WHDR_DONE) == 0)
        {
            return chunk->line;
        }
    }
    return 0;
}

void Close()
{
    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);
    voice.closed = true;
}

// La replique entiere d'un coup : la meme file, ouverte, remplie et fermee sans respirer. Tout
// ce qui appelait Play() avant le streaming continue de marcher a l'identique -- y compris le
// remplacement, que l'arret explicite conserve maintenant que l'ouverture, elle, prolonge.
Status Play(const void* aSamples, size_t aBytes, const Format& aFormat)
{
    if (aSamples == nullptr || aBytes == 0)
    {
        return Status::EmptyBuffer;
    }

    Stop();
    const Status opened = Open(aFormat);
    if (opened != Status::Ok)
    {
        return opened;
    }
    const Status pushed = Push(aSamples, aBytes);
    Close();
    return pushed;
}

Status PlayWav(const void* aImage, size_t aBytes)
{
    if (aImage == nullptr || aBytes < 44)
    {
        return Status::EmptyBuffer;
    }

    const uint8_t* image = static_cast<const uint8_t*>(aImage);
    if (!FourCC(image, "RIFF") || !FourCC(image + 8, "WAVE"))
    {
        return Status::NotWave;
    }

    Format format;
    const uint8_t* data = nullptr;
    size_t dataBytes = 0;
    bool sawFormat = false;

    // One walk, one verdict. A chunk header is 8 bytes and chunks are word-aligned; anything
    // that does not fit is a truncated image rather than a chunk to skip.
    size_t at = 12;
    while (at + 8 <= aBytes)
    {
        const uint32_t size = ReadU32(image + at + 4);
        const size_t body = at + 8;
        if (body + size > aBytes)
        {
            return Status::Truncated;
        }

        if (FourCC(image + at, "fmt ") && size >= 16)
        {
            const uint16_t tag = ReadU16(image + body);
            if (tag != kFormatPcm && tag != kFormatExtensible)
            {
                return Status::NotPcm;
            }
            format.channels = ReadU16(image + body + 2);
            format.sampleRate = ReadU32(image + body + 4);
            format.bitsPerSample = ReadU16(image + body + 14);
            sawFormat = true;
        }
        else if (FourCC(image + at, "data"))
        {
            data = image + body;
            dataBytes = size;
        }

        at = body + size + (size & 1u);
    }

    if (!sawFormat || data == nullptr)
    {
        return Status::NotWave;
    }
    if (dataBytes == 0)
    {
        return Status::EmptyBuffer;
    }
    return Play(data, dataBytes, format);
}

void Stop()
{
    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> lifecycle(voice.lifecycle);
    StopAndJoin();
}

std::vector<std::string> Outputs()
{
    std::vector<std::string> names;
    const UINT count = waveOutGetNumDevs();
    for (UINT i = 0; i < count; ++i)
    {
        WAVEOUTCAPSW caps{};
        if (waveOutGetDevCapsW(i, &caps, sizeof(caps)) == MMSYSERR_NOERROR)
        {
            // szPname is 32 wide characters including the terminator, so a long name arrives
            // cut. That is the API's limit and not ours; a cut name still identifies a device
            // to the person reading it.
            names.emplace_back(Utf8(caps.szPname));
        }
        else
        {
            names.emplace_back("<unnamed>");
        }
    }
    return names;
}

std::string DeviceName()
{
    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);
    return voice.device_name;
}

bool IsPlaying()
{
    Voice& voice = TheVoice();
    std::lock_guard<std::mutex> guard(voice.mutex);
    return voice.device != nullptr && SpeechPending(voice);
}
}
