#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "VoiceMake.hpp"

#include "Json.hpp"
#include "PocketVoice.hpp"
#include "VoiceArchive.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

// Le convertisseur Wwise Vorbis -> Ogg, adapte a des tampons memoire par
// tools\pocket-engine\patch-decoder.py. Ses en-tetes sont bruts : `using namespace std` en
// portee de fichier, macros de version. Inclus ici et nulle part ailleurs.
#include "wwriff.h"

namespace ainpc::voicemake
{
namespace
{
// Le decodeur Ogg, en un seul fichier. Compile ici plutot que dans son unite : il est en C, il
// veut ses propres macros, et il n'a qu'un seul appelant.
#define STB_VORBIS_NO_PUSHDATA_API
#define STB_VORBIS_NO_STDIO
#include "stb_vorbis.c"

// Un tampon mono en flottant et son taux, ce que toutes les etapes se passent.
struct Clip
{
    std::vector<float> samples;
    int rate = 0;
};

// Les seuils de la recette, tous lus dans le fichier plutot que codes ici : ce sont eux qui
// font qu'une reference fabriquee en jeu est la meme que celle du banc.
struct Settings
{
    int sampleRate = 48000;
    double gapSeconds = 0.25;
    double silenceFloor = 0.004;
    double maxSeconds = 40.0;
    double targetRms = 0.1;
    double peakCeiling = 0.98;
};

std::wstring Parent(const std::wstring& aPath)
{
    const size_t slash = aPath.find_last_of(L"\\/");
    return slash == std::wstring::npos ? L"" : aPath.substr(0, slash);
}

std::wstring GameRoot(const std::wstring& aPluginDirectory)
{
    return Parent(Parent(Parent(aPluginDirectory)));
}

std::wstring VoicesDir(const std::wstring& aPluginDirectory)
{
    const std::wstring root = GameRoot(aPluginDirectory);
    return root.empty() ? L"" : root + L"\\r6\\storages\\AiNpc\\voices";
}

std::wstring RecipePath(const std::wstring& aPluginDirectory)
{
    return aPluginDirectory + L"\\voices-recipe.json";
}

std::wstring CodebooksPath(const std::wstring& aPluginDirectory)
{
    return aPluginDirectory + L"\\models\\packed_codebooks_aoTuV_603.bin";
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

bool ReadWholeFile(const std::wstring& aPath, std::string& aOut)
{
    std::ifstream file(aPath, std::ios::binary);
    if (!file)
    {
        return false;
    }
    std::ostringstream buffer;
    buffer << file.rdbuf();
    aOut = buffer.str();
    return true;
}

// Un .wem de doublage vers du PCM mono flottant. Deux etapes, et aucun fichier entre elles :
// ww2ogg reconstitue l'en-tete Vorbis que Wwise a retire, stb_vorbis decode le resultat.
bool DecodeWem(const std::vector<uint8_t>& aWem, const std::string& aCodebooks, Clip& aOut)
{
    std::string ogg;
    try
    {
        Wwise_RIFF_Vorbis converter("line.wem", reinterpret_cast<const char*>(aWem.data()),
                                    static_cast<long>(aWem.size()), aCodebooks,
                                    /*inline_codebooks*/ false, /*full_setup*/ false,
                                    kNoForcePacketFormat);
        std::ostringstream out(std::ios::binary);
        converter.generate_ogg(out);
        ogg = out.str();
    }
    catch (...)
    {
        // ww2ogg leve des types a lui pour toute anomalie de flux. Une replique illisible est
        // un cas ordinaire -- un correctif a pu reencoder le doublage -- pas une raison de
        // faire tomber la voie parlee.
        return false;
    }
    if (ogg.empty())
    {
        return false;
    }

    int channels = 0;
    int rate = 0;
    short* samples = nullptr;
    const int frames = stb_vorbis_decode_memory(reinterpret_cast<const unsigned char*>(ogg.data()),
                                                static_cast<int>(ogg.size()), &channels, &rate, &samples);
    if (frames <= 0 || channels <= 0 || samples == nullptr)
    {
        free(samples);
        return false;
    }

    aOut.rate = rate;
    aOut.samples.resize(static_cast<size_t>(frames));
    for (int i = 0; i < frames; ++i)
    {
        int sum = 0;
        for (int c = 0; c < channels; ++c)
        {
            sum += samples[static_cast<size_t>(i) * channels + c];
        }
        aOut.samples[static_cast<size_t>(i)] = static_cast<float>(sum) / (channels * 32768.0f);
    }
    free(samples);
    return true;
}

// Coupe le silence de tete et de queue : les repliques de jeu portent souvent une amorce muette
// qui, mise bout a bout, gonfle la duree sans porter de voix.
void Trim(Clip& aClip, double aFloor)
{
    size_t first = 0;
    while (first < aClip.samples.size() && std::fabs(aClip.samples[first]) < aFloor)
    {
        ++first;
    }
    size_t last = aClip.samples.empty() ? 0 : aClip.samples.size() - 1;
    while (last > first && std::fabs(aClip.samples[last]) < aFloor)
    {
        --last;
    }
    if (last <= first)
    {
        aClip.samples.clear();
        return;
    }
    aClip.samples = std::vector<float>(aClip.samples.begin() + first, aClip.samples.begin() + last + 1);
}

double Sinc(double aX)
{
    return std::fabs(aX) < 1e-9 ? 1.0 : std::sin(3.14159265358979323846 * aX) / (3.14159265358979323846 * aX);
}

// Sinus cardinal fenetre plutot qu'interpolation lineaire. Le lineaire suffirait a la duree mais
// replierait le spectre au-dessus de la moitie du taux cible, et ce repli s'entend sur les
// sifflantes -- precisement ce qu'un moteur de clonage ecoute.
void Resample(Clip& aClip, int aTargetRate)
{
    if (aClip.rate == aTargetRate || aClip.samples.empty())
    {
        aClip.rate = aTargetRate;
        return;
    }
    constexpr int kHalfWidth = 24;
    const double ratio = static_cast<double>(aTargetRate) / aClip.rate;
    const double cutoff = (ratio < 1.0 ? ratio : 1.0) * 0.92;
    const size_t length = static_cast<size_t>(aClip.samples.size() * ratio);
    std::vector<float> out(length);

    for (size_t i = 0; i < length; ++i)
    {
        const double center = i / ratio;
        const long first = static_cast<long>(std::floor(center)) - kHalfWidth;
        const long last = static_cast<long>(std::floor(center)) + kHalfWidth;
        double sum = 0.0;
        double weight = 0.0;
        for (long j = first; j <= last; ++j)
        {
            if (j < 0 || static_cast<size_t>(j) >= aClip.samples.size())
            {
                continue;
            }
            const double x = j - center;
            const double t = (x + kHalfWidth) / (2.0 * kHalfWidth);
            if (t < 0.0 || t > 1.0)
            {
                continue;
            }
            const double window = 0.42 - 0.5 * std::cos(2 * 3.14159265358979323846 * t) +
                                  0.08 * std::cos(4 * 3.14159265358979323846 * t);
            const double w = Sinc(x * cutoff) * window;
            sum += aClip.samples[static_cast<size_t>(j)] * w;
            weight += w;
        }
        const double value = weight == 0.0 ? 0.0 : sum / weight;
        out[i] = static_cast<float>(value < -1.0 ? -1.0 : (value > 1.0 ? 1.0 : value));
    }
    aClip.samples = std::move(out);
    aClip.rate = aTargetRate;
}

// Les repliques ne sont PAS mises au meme niveau les unes des autres : le rapport de niveau
// entre deux prises est une information sur la voix, et l'egaliser fabrique une dynamique
// ecrasee que le moteur reproduit ensuite. Une seule mise a niveau, ici, sur l'extrait entier.
void Level(std::vector<float>& aSamples, const Settings& aSettings)
{
    double square = 0.0;
    double peak = 0.0;
    for (float sample : aSamples)
    {
        square += static_cast<double>(sample) * sample;
        peak = peak > std::fabs(sample) ? peak : std::fabs(sample);
    }
    if (aSamples.empty())
    {
        return;
    }
    const double rms = std::sqrt(square / aSamples.size());
    if (rms < 1e-9)
    {
        return;
    }
    const double byRms = aSettings.targetRms / rms;
    const double byPeak = aSettings.peakCeiling / (peak > 1e-6 ? peak : 1e-6);
    const double gain = byRms < byPeak ? byRms : byPeak;
    for (float& sample : aSamples)
    {
        const double scaled = sample * gain;
        sample = static_cast<float>(scaled < -1.0 ? -1.0 : (scaled > 1.0 ? 1.0 : scaled));
    }
}

bool WriteWav(const std::wstring& aPath, const std::vector<float>& aSamples, int aRate)
{
    std::ofstream file(aPath, std::ios::binary);
    if (!file)
    {
        return false;
    }
    const uint32_t dataBytes = static_cast<uint32_t>(aSamples.size() * 2);
    const auto put32 = [&file](uint32_t v) { file.write(reinterpret_cast<const char*>(&v), 4); };
    const auto put16 = [&file](uint16_t v) { file.write(reinterpret_cast<const char*>(&v), 2); };

    file.write("RIFF", 4);
    put32(36 + dataBytes);
    file.write("WAVE", 4);
    file.write("fmt ", 4);
    put32(16);
    put16(1);
    put16(1);
    put32(static_cast<uint32_t>(aRate));
    put32(static_cast<uint32_t>(aRate) * 2);
    put16(2);
    put16(16);
    file.write("data", 4);
    put32(dataBytes);
    for (float sample : aSamples)
    {
        const double scaled = std::lround(sample * 32767.0);
        const int16_t pcm = static_cast<int16_t>(scaled < -32768 ? -32768 : (scaled > 32767 ? 32767 : scaled));
        file.write(reinterpret_cast<const char*>(&pcm), 2);
    }
    return file.good();
}

Settings SettingsFrom(const json::Value& aRecipe)
{
    Settings settings;
    const json::Value* block = aRecipe.Find("settings");
    if (block == nullptr || !block->IsObject())
    {
        return settings;
    }
    const auto number = [block](const char* key, double fallback) {
        const json::Value* value = block->Find(key);
        return value != nullptr && value->kind == json::Kind::Number ? value->number : fallback;
    };
    settings.sampleRate = static_cast<int>(number("sampleRate", settings.sampleRate));
    settings.gapSeconds = number("gapSeconds", settings.gapSeconds);
    settings.silenceFloor = number("silenceFloor", settings.silenceFloor);
    settings.maxSeconds = number("maxSeconds", settings.maxSeconds);
    settings.targetRms = number("targetRms", settings.targetRms);
    settings.peakCeiling = number("peakCeiling", settings.peakCeiling);
    return settings;
}

uint64_t HashFromHex(const std::string& aHex)
{
    uint64_t value = 0;
    for (char c : aHex)
    {
        int digit;
        if (c >= '0' && c <= '9') { digit = c - '0'; }
        else if (c >= 'a' && c <= 'f') { digit = c - 'a' + 10; }
        else if (c >= 'A' && c <= 'F') { digit = c - 'A' + 10; }
        else { continue; }
        value = (value << 4) | static_cast<uint64_t>(digit);
    }
    return value;
}

// La langue du joueur d'abord : son doublage est installe dans sa langue, et un clone fabrique
// ailleurs parlerait avec l'accent de la mauvaise -- entendu le 2026-08-31, sur une premiere
// serie tiree par erreur de l'archive anglaise. L'anglais n'est le repli que si la recette
// ignore la sienne.
const json::Value* VoiceFor(const json::Value& aRecipe, const std::string& aName,
                            const std::string& aWanted, std::string& aLanguage)
{
    const json::Value* voices = aRecipe.Find("voices");
    if (voices == nullptr || !voices->IsArray())
    {
        return nullptr;
    }
    const json::Value* fallback = nullptr;
    for (const json::Value& voice : voices->items)
    {
        if (voice.StringAt("voice") != aName)
        {
            continue;
        }
        const std::string language = voice.StringAt("language");
        if (language == aWanted)
        {
            aLanguage = language;
            return &voice;
        }
        if (language == "en" && fallback == nullptr)
        {
            fallback = &voice;
            aLanguage = language;
        }
    }
    return fallback;
}

// Le nom de la voix est celui du fichier de reference sans son extension : `judy.wav` pour le
// casting, `civ_mid_f_21_enus_25.wav` pour une voix que n'importe quelle fiche peut nommer.
std::string VoiceNameOf(const std::string& aVoiceFile)
{
    const size_t dot = aVoiceFile.find_last_of('.');
    return dot == std::string::npos ? aVoiceFile : aVoiceFile.substr(0, dot);
}

// Le facteur de relecture d'une voix derivee ; 1 quand la recette n'en dit rien.
double ShiftOf(const json::Value& aVoice)
{
    const json::Value* shift = aVoice.Find("shift");
    return shift != nullptr && shift->kind == json::Kind::Number && shift->number > 0.0 ? shift->number : 1.0;
}
} // namespace

bool Possible(const std::wstring& aPluginDirectory)
{
    return !aPluginDirectory.empty() && voice::CanClone(aPluginDirectory) &&
           FileExists(RecipePath(aPluginDirectory)) && FileExists(CodebooksPath(aPluginDirectory));
}

bool Make(const std::wstring& aPluginDirectory, const std::string& aVoiceFile, const std::string& aLanguage,
          std::string& aWhy)
{
    const std::wstring voicesDir = VoicesDir(aPluginDirectory);
    if (voicesDir.empty())
    {
        aWhy = "the game root could not be found";
        return false;
    }
    const std::wstring target = voicesDir + L"\\" + Widen(aVoiceFile);
    if (FileExists(target))
    {
        aWhy = "a reference is already there";
        return false;
    }
    if (!Possible(aPluginDirectory))
    {
        aWhy = "no recipe or no codebooks beside the plugin";
        return false;
    }

    std::string recipeText;
    if (!ReadWholeFile(RecipePath(aPluginDirectory), recipeText))
    {
        aWhy = "the recipe could not be read";
        return false;
    }
    json::Value recipe;
    if (!json::Parse(recipeText, recipe) || !recipe.IsObject())
    {
        aWhy = "the recipe is not readable JSON";
        return false;
    }

    const std::string wanted = archive::ArchiveCodeForLocale(aLanguage);
    if (wanted.empty())
    {
        aWhy = "no voice-over is known for the locale " + aLanguage;
        return false;
    }

    const std::string name = VoiceNameOf(aVoiceFile);
    std::string language;
    const json::Value* voice = VoiceFor(recipe, name, wanted, language);
    if (voice == nullptr)
    {
        aWhy = "the recipe has no voice named " + name;
        return false;
    }
    const json::Value* lines = voice->Find("lines");
    if (lines == nullptr || !lines->IsArray() || lines->items.empty())
    {
        aWhy = "the recipe lists no lines for " + name;
        return false;
    }

    archive::VoiceArchives archives;
    if (!archives.Open(GameRoot(aPluginDirectory), language))
    {
        aWhy = "no " + language + " voice-over archive in this installation";
        return false;
    }

    const Settings settings = SettingsFrom(recipe);
    const std::string codebooks = Narrow(CodebooksPath(aPluginDirectory));

    std::vector<float> assembled;
    const size_t gap = static_cast<size_t>(settings.gapSeconds * settings.sampleRate);
    const size_t ceiling = static_cast<size_t>(settings.maxSeconds * settings.sampleRate);
    int kept = 0;
    int missing = 0;

    for (const json::Value& line : lines->items)
    {
        if (assembled.size() >= ceiling)
        {
            break;
        }
        std::vector<uint8_t> wem;
        Clip clip;
        if (!archives.Read(HashFromHex(line.StringAt("hash")), wem) ||
            !DecodeWem(wem, codebooks, clip))
        {
            ++missing;
            continue;
        }
        Trim(clip, settings.silenceFloor);
        if (clip.samples.empty())
        {
            ++missing;
            continue;
        }
        Resample(clip, settings.sampleRate);
        if (!assembled.empty())
        {
            assembled.insert(assembled.end(), gap, 0.0f);
        }
        assembled.insert(assembled.end(), clip.samples.begin(), clip.samples.end());
        ++kept;
    }

    if (kept == 0)
    {
        aWhy = "none of the " + std::to_string(lines->items.size()) + " lines could be read";
        return false;
    }
    if (assembled.size() > ceiling)
    {
        assembled.resize(ceiling);
    }
    Level(assembled, settings);

    // Une voix derivee annonce une autre frequence que celle de ses echantillons : relue plus vite,
    // hauteur et formants montent ensemble. Rien d'autre ne change, et c'est ce que le banc a
    // fait entendre.
    const int announced = static_cast<int>(std::lround(settings.sampleRate * ShiftOf(*voice)));
    CreateDirectoryW(Parent(target).c_str(), nullptr);
    if (!WriteWav(target, assembled, announced))
    {
        aWhy = "the reference could not be written to r6\\storages";
        return false;
    }

    char note[200];
    std::snprintf(note, sizeof(note), "%d line(s) in %s, %.1f s%s", kept, language.c_str(),
                  static_cast<double>(assembled.size()) / settings.sampleRate,
                  missing > 0 ? (", " + std::to_string(missing) + " missing").c_str() : "");
    aWhy = note;
    return true;
}
} // namespace ainpc::voicemake
