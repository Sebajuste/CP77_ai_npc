#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "PocketVoice.hpp"

#include "Audio.hpp"

#include <atomic>
#include <cmath>
#include <fstream>
#include <mutex>

namespace ainpc::voice
{
namespace
{
// L'API C de PocketTTS.cpp, declaree ici plutot qu'incluse : l'amont n'a pas d'en-tete, tout
// vit dans un seul .cpp. La declarer nous-memes garde ce fichier independant de ses internes,
// et c'est la surface que l'amont a ecrite pour etre embarquee.
//
// `ptt_set_eos_extra` est notre ajout, applique par tools\pocket-engine\patch-runtime.py.
extern "C"
{
void* ptt_create(const char* models_dir, const char* voices_dir, const char* tokenizer_path,
                 const char* precision, float temperature, int lsd_steps, int num_threads);
void ptt_set_eos_extra(void* handle, int frames);
void ptt_destroy(void* handle);
void ptt_free_audio(float* samples);
void* ptt_stream_start(void* handle, const char* text, const char* voice);
int ptt_stream_read(void* stream_ctx, float** out_samples, int* out_len);
void ptt_stream_end(void* stream_ctx);
}

constexpr uint32_t kSampleRate = 24000;
constexpr uint16_t kChannels = 1;
constexpr uint16_t kBits = 16;

// Le fichier sans lequel le francais babille. Sa presence est aussi ce qui distingue un pack
// de modeles complet d'un dossier a moitie copie, alors il sert de sentinelle.
const wchar_t* kSentinel = L"\\models\\bos_before_voice.bin";

std::wstring Parent(const std::wstring& aPath)
{
    const size_t slash = aPath.find_last_of(L"\\/");
    return slash == std::wstring::npos ? L"" : aPath.substr(0, slash);
}

// red4ext\plugins\ai_npc -> la racine du jeu, comme SettingsFile.cpp la trouve.
std::wstring GameRoot(const std::wstring& aPluginDirectory)
{
    return Parent(Parent(Parent(aPluginDirectory)));
}

std::wstring ModelsDir(const std::wstring& aPluginDirectory)
{
    return aPluginDirectory + L"\\models";
}

std::wstring VoicesDir(const std::wstring& aPluginDirectory)
{
    const std::wstring root = GameRoot(aPluginDirectory);
    return root.empty() ? L"" : root + L"\\r6\\storages\\AiNpc\\voices";
}

bool FileExists(const std::wstring& aPath)
{
    const DWORD attributes = GetFileAttributesW(aPath.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}

std::string Narrow(const std::wstring& aWide)
{
    if (aWide.empty())
    {
        return {};
    }
    const int count = WideCharToMultiByte(CP_UTF8, 0, aWide.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (count <= 1)
    {
        return {};
    }
    std::string out(static_cast<size_t>(count - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, aWide.c_str(), -1, out.data(), count, nullptr, nullptr);
    return out;
}

std::wstring Widen(const std::string& aUtf8)
{
    if (aUtf8.empty())
    {
        return {};
    }
    const int count = MultiByteToWideChar(CP_UTF8, 0, aUtf8.c_str(), -1, nullptr, 0);
    if (count <= 1)
    {
        return {};
    }
    std::wstring out(static_cast<size_t>(count - 1), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, aUtf8.c_str(), -1, out.data(), count);
    return out;
}

// La valeur que le runtime ne sait pas lire, ecrite a cote des modeles par export-models.py.
// Absente, on laisse le calcul automatique -- ce qui est juste pour les onze modeles qui ne
// declarent rien, et faux pour le seul qui declare.
int FramesAfterEos(const std::wstring& aModelsDir)
{
    std::ifstream file(aModelsDir + L"\\frames_after_eos.txt");
    int frames = -1;
    if (file >> frames && frames >= 0)
    {
        return frames;
    }
    return -1;
}

// Le moteur, cree une fois et garde. Le charger coute deux secondes, et il tient l'etat de voix
// de chaque personnage deja clone -- le jeter entre deux repliques ferait repayer les deux
// secondes et le clonage.
struct Engine
{
    std::mutex mutex;
    void* handle = nullptr;
    bool tried = false;
    std::string why;
};

Engine& TheEngine()
{
    static Engine engine;
    return engine;
}

// Leve par la voie parlee quand le joueur raccroche, lue entre deux tranches. Un atomique
// plutot qu'un champ du moteur : elle est ecrite depuis le fil de jeu pendant que le worker
// tient le verrou du moteur, et attendre ce verrou pour demander l'arret le rendrait inutile.
std::atomic<bool>& TheCancel()
{
    static std::atomic<bool> cancel{false};
    return cancel;
}

// Sous verrou de l'appelant.
void* Acquire(Engine& aEngine, const std::wstring& aPluginDirectory)
{
    if (aEngine.handle != nullptr || aEngine.tried)
    {
        return aEngine.handle;
    }
    aEngine.tried = true;

    const std::wstring models = ModelsDir(aPluginDirectory);
    const std::wstring voices = VoicesDir(aPluginDirectory);
    if (voices.empty())
    {
        aEngine.why = "the game root could not be found from the plugin directory";
        return nullptr;
    }

    // Zero fils demande au moteur la moitie des coeurs. Mesure du 2026-09-01 : un seul fil est
    // le pire reglage possible -- 1,02x le temps reel contre 2,3x -- et c'est le defaut de la
    // bibliotheque sous-jacente, pas un choix.
    aEngine.handle = ptt_create(Narrow(models).c_str(), Narrow(voices).c_str(),
                                Narrow(models + L"\\tokenizer.model").c_str(), "int8", 0.7f, 1, 0);
    if (aEngine.handle == nullptr)
    {
        aEngine.why = "the speech model refused to load";
        return nullptr;
    }

    const int frames = FramesAfterEos(models);
    if (frames >= 0)
    {
        ptt_set_eos_extra(aEngine.handle, frames);
    }
    return aEngine.handle;
}

// Le flottant du moteur vers le PCM 16 bits de la voie audio, en bornant. Le moteur ne sature
// pas de lui-meme : mesure sur les rendus du banc, les cretes vont de 0,27 a 0,59.
void AppendPcm(const float* aSamples, int aCount, std::vector<uint8_t>& aOut)
{
    for (int i = 0; i < aCount; ++i)
    {
        float value = aSamples[i];
        value = value < -1.0f ? -1.0f : (value > 1.0f ? 1.0f : value);
        const int16_t pcm = static_cast<int16_t>(std::lround(value * 32767.0f));
        aOut.push_back(static_cast<uint8_t>(pcm & 0xFF));
        aOut.push_back(static_cast<uint8_t>((pcm >> 8) & 0xFF));
    }
}
} // namespace

bool Available(const std::wstring& aPluginDirectory)
{
    return !aPluginDirectory.empty() && FileExists(aPluginDirectory + kSentinel);
}

bool HasVoiceFor(const std::wstring& aPluginDirectory, const std::string& aVoiceFile)
{
    if (aVoiceFile.empty())
    {
        return false;
    }
    const std::wstring voices = VoicesDir(aPluginDirectory);
    return !voices.empty() && FileExists(voices + L"\\" + Widen(aVoiceFile));
}

bool HasCatalogueVoice(const std::wstring& aPluginDirectory, const std::string& aVoiceName)
{
    if (aVoiceName.empty())
    {
        return false;
    }
    return FileExists(ModelsDir(aPluginDirectory) + L"\\catalogue\\" + Widen(aVoiceName) + L".kv");
}

void CancelCurrent()
{
    TheCancel().store(true);
}

bool Render(const std::wstring& aPluginDirectory, const std::string& aVoiceFile,
            const std::string& aUtf8Text, bool aSilent, std::string& aWhy)
{
    TheCancel().store(false);
    if (aUtf8Text.empty())
    {
        aWhy = "nothing to say";
        return false;
    }
    // Un `.wav` est une reference a cloner, tout autre nom est une voix de catalogue. Le moteur
    // fait la meme lecture du meme nom : un seul contrat, et rien a se dire en plus.
    const bool clone = aVoiceFile.size() > 4 && aVoiceFile.compare(aVoiceFile.size() - 4, 4, ".wav") == 0;
    const bool present = clone ? HasVoiceFor(aPluginDirectory, aVoiceFile)
                               : HasCatalogueVoice(aPluginDirectory, aVoiceFile);
    if (!present)
    {
        aWhy = std::string(clone ? "no reference voice file " : "no catalogue voice ") +
               (aVoiceFile.empty() ? std::string("(none named)") : aVoiceFile);
        return false;
    }

    Engine& engine = TheEngine();
    std::lock_guard<std::mutex> guard(engine.mutex);

    void* handle = Acquire(engine, aPluginDirectory);
    if (handle == nullptr)
    {
        aWhy = engine.why;
        return false;
    }

    // Le moteur ouvre un fil pour produire ses morceaux ; on les consomme jusqu'a epuisement,
    // donc du point de vue de l'appelant ceci est bloquant, comme SAPI l'etait. Ce qui a change
    // est que le SON, lui, commence des le premier morceau.
    void* stream = ptt_stream_start(handle, aUtf8Text.c_str(), aVoiceFile.c_str());
    if (stream == nullptr)
    {
        aWhy = "the voice could not be started";
        return false;
    }

    audio::Format format;
    format.sampleRate = kSampleRate;
    format.channels = kChannels;
    format.bitsPerSample = kBits;

    // Ouvert AVANT le premier morceau : ouvrir coute quelques dizaines de millisecondes, et les
    // payer entre la synthese et le son rendrait les 123 ms a moitie.
    bool opened = false;
    if (!aSilent)
    {
        const audio::Status status = audio::Open(format);
        if (status != audio::Status::Ok)
        {
            ptt_stream_end(stream);
            aWhy = audio::Describe(status);
            return false;
        }
        opened = true;
    }

    std::vector<uint8_t> pcm;
    size_t total = 0;
    float* chunk = nullptr;
    int count = 0;
    bool cancelled = false;
    while (ptt_stream_read(stream, &chunk, &count) == 1)
    {
        pcm.clear();
        AppendPcm(chunk, count, pcm);
        ptt_free_audio(chunk);
        total += pcm.size();
        if (opened && !pcm.empty())
        {
            audio::Push(pcm.data(), pcm.size());
        }
        if (TheCancel().load())
        {
            cancelled = true;
            break;
        }
    }
    ptt_stream_end(stream);
    if (opened)
    {
        audio::Close();
    }

    if (cancelled)
    {
        aWhy = "the line was cut short";
        return false;
    }

    if (total == 0)
    {
        aWhy = "the voice produced no samples";
        return false;
    }
    return true;
}

uint32_t SampleRate()
{
    return kSampleRate;
}

uint16_t Channels()
{
    return kChannels;
}

uint16_t BitsPerSample()
{
    return kBits;
}

void Shutdown()
{
    Engine& engine = TheEngine();
    std::lock_guard<std::mutex> guard(engine.mutex);
    if (engine.handle != nullptr)
    {
        ptt_destroy(engine.handle);
        engine.handle = nullptr;
    }
    engine.tried = false;
}
} // namespace ainpc::voice
