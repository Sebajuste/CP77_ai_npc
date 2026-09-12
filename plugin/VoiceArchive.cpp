#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "VoiceArchive.hpp"

#include <cstring>
#include <unordered_map>

namespace ainpc::archive
{
namespace
{
// La disposition d'une archive RDAR, lue une fois et pas devinee : en-tete de 32 octets, dont
// l'offset de la table a +8 et sa taille a +16. Dans la table, le nombre de fichiers a +16, le
// nombre de segments a +20, les entrees a partir de +28 sur 56 octets chacune -- hachage en
// tete, premier segment a +20 -- puis les segments, 16 octets chacun.
constexpr size_t kHeaderSize = 32;
constexpr size_t kEntriesAt = 28;
constexpr size_t kEntrySize = 56;
constexpr size_t kSegmentSize = 16;

template <typename T>
T ReadAt(const std::vector<uint8_t>& aBytes, size_t aOffset)
{
    T value{};
    std::memcpy(&value, aBytes.data() + aOffset, sizeof(T));
    return value;
}

// Onze doublages, et la correspondance n'est pas une regle : "pt-br" donne l'archive "pt",
// "es-es" se garde entier, "zh-cn" aussi. Le dossier depot, lui, ne suit pas l'archive : le
// doublage mexicain est celui d'Espagne, sous `es-es`. Une table courte vaut mieux qu'une regle
// qui a tort trois fois.
constexpr struct
{
    const char* locale;
    const char* code;
    const char* folder;
} kDubs[] = {
    {"en-us", "en", "en-us"},     {"fr-fr", "fr", "fr-fr"},     {"de-de", "de", "de-de"},
    {"es-es", "es-es", "es-es"},  {"es-mx", "es-es", "es-es"},  {"it-it", "it", "it-it"},
    {"jp-jp", "jp", "jp-jp"},     {"kr-kr", "kr", "kr-kr"},     {"pl-pl", "pl", "pl-pl"},
    {"pt-br", "pt", "pt-br"},     {"ru-ru", "ru", "ru-ru"},     {"zh-cn", "zh-cn", "zh-cn"},
};

} // namespace

std::string ArchiveCodeForLocale(const std::string& aLocale)
{
    for (const auto& entry : kDubs)
    {
        if (aLocale == entry.locale)
        {
            return entry.code;
        }
    }
    return {};
}

std::string VoFolderForLocale(const std::string& aLocale)
{
    for (const auto& entry : kDubs)
    {
        if (aLocale == entry.locale)
        {
            return entry.folder;
        }
    }
    return {};
}

uint64_t HashOfDepotPath(const std::string& aDepotPath)
{
    uint64_t hash = 14695981039346656037ULL;
    for (char raw : aDepotPath)
    {
        unsigned char c = static_cast<unsigned char>(raw);
        if (c == '/')
        {
            c = '\\';
        }
        if (c >= 'A' && c <= 'Z')
        {
            c = static_cast<unsigned char>(c - 'A' + 'a');
        }
        hash ^= c;
        hash *= 1099511628211ULL;
    }
    return hash;
}

struct VoiceArchives::Volume
{
    HANDLE file = INVALID_HANDLE_VALUE;
    // hachage -> (offset, taille) du seul segment du fichier.
    std::unordered_map<uint64_t, std::pair<int64_t, uint32_t>> files;
};

namespace
{
bool ReadExact(HANDLE aFile, int64_t aOffset, size_t aCount, std::vector<uint8_t>& aOut)
{
    LARGE_INTEGER position{};
    position.QuadPart = aOffset;
    if (!SetFilePointerEx(aFile, position, nullptr, FILE_BEGIN))
    {
        return false;
    }
    aOut.resize(aCount);
    size_t done = 0;
    while (done < aCount)
    {
        DWORD read = 0;
        const DWORD want = static_cast<DWORD>(aCount - done > 0x10000000 ? 0x10000000 : aCount - done);
        if (!ReadFile(aFile, aOut.data() + done, want, &read, nullptr) || read == 0)
        {
            return false;
        }
        done += read;
    }
    return true;
}

} // namespace

// Un fichier compresse ou en plusieurs segments est simplement ignore : ce lecteur ne sert
// qu'au doublage, et le doublage n'en a aucun.
VoiceArchives::Volume* VoiceArchives::OpenVolume(const std::wstring& aPath)
{
    // FILE_SHARE_WRITE autant que READ : le jeu tient ces memes archives ouvertes, et un
    // lecteur ne doit jamais poser un verrou plus fort que ce qu'il lit.
    HANDLE file = CreateFileW(aPath.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        return nullptr;
    }

    std::vector<uint8_t> header;
    if (!ReadExact(file, 0, kHeaderSize, header) || std::memcmp(header.data(), "RDAR", 4) != 0)
    {
        CloseHandle(file);
        return nullptr;
    }

    const int64_t indexOffset = ReadAt<int64_t>(header, 8);
    const int32_t indexSize = ReadAt<int32_t>(header, 16);
    std::vector<uint8_t> index;
    if (indexSize <= 28 || !ReadExact(file, indexOffset, static_cast<size_t>(indexSize), index))
    {
        CloseHandle(file);
        return nullptr;
    }

    const int32_t fileCount = ReadAt<int32_t>(index, 16);
    const int32_t segmentCount = ReadAt<int32_t>(index, 20);
    const size_t segmentsAt = kEntriesAt + static_cast<size_t>(fileCount) * kEntrySize;
    if (fileCount < 0 || segmentCount < 0 ||
        segmentsAt + static_cast<size_t>(segmentCount) * kSegmentSize > index.size())
    {
        CloseHandle(file);
        return nullptr;
    }

    auto* volume = new VoiceArchives::Volume();
    volume->file = file;
    volume->files.reserve(static_cast<size_t>(fileCount));
    for (int32_t i = 0; i < fileCount; ++i)
    {
        const size_t at = kEntriesAt + static_cast<size_t>(i) * kEntrySize;
        const uint64_t hash = ReadAt<uint64_t>(index, at);
        const int32_t first = ReadAt<int32_t>(index, at + 20);
        const int32_t last = ReadAt<int32_t>(index, at + 24);
        if (first < 0 || first >= segmentCount || last != first + 1)
        {
            continue; // plusieurs segments : pas du doublage
        }
        const size_t segment = segmentsAt + static_cast<size_t>(first) * kSegmentSize;
        const int64_t offset = ReadAt<int64_t>(index, segment);
        const uint32_t packed = ReadAt<uint32_t>(index, segment + 8);
        const uint32_t size = ReadAt<uint32_t>(index, segment + 12);
        if (packed != size)
        {
            continue; // compresse : ce lecteur ne traverse pas Oodle
        }
        volume->files.emplace(hash, std::make_pair(offset, size));
    }
    return volume;
}

bool VoiceArchives::Open(const std::wstring& aGameRoot, const std::string& aLanguage)
{
    Close();
    if (aGameRoot.empty() || aLanguage.empty())
    {
        return false;
    }

    const std::wstring language(aLanguage.begin(), aLanguage.end());
    // Le jeu de base puis Phantom Liberty. L'extension est facultative, et son absence est
    // ordinaire plutot qu'une erreur.
    for (const wchar_t* folder : {L"content", L"ep1"})
    {
        const std::wstring path =
            aGameRoot + L"\\archive\\pc\\" + folder + L"\\lang_" + language + L"_voice.archive";
        if (Volume* volume = OpenVolume(path))
        {
            m_volumes.push_back(volume);
        }
    }
    return !m_volumes.empty();
}

bool VoiceArchives::IsOpen() const
{
    return !m_volumes.empty();
}

bool VoiceArchives::Read(uint64_t aHash, std::vector<uint8_t>& aOut) const
{
    for (const Volume* volume : m_volumes)
    {
        const auto found = volume->files.find(aHash);
        if (found != volume->files.end())
        {
            return ReadExact(volume->file, found->second.first, found->second.second, aOut);
        }
    }
    return false;
}

bool VoiceArchives::Has(uint64_t aHash) const
{
    for (const Volume* volume : m_volumes)
    {
        if (volume->files.find(aHash) != volume->files.end())
        {
            return true;
        }
    }
    return false;
}

void VoiceArchives::Close()
{
    for (Volume* volume : m_volumes)
    {
        if (volume->file != INVALID_HANDLE_VALUE)
        {
            CloseHandle(volume->file);
        }
        delete volume;
    }
    m_volumes.clear();
}

VoiceArchives::~VoiceArchives()
{
    Close();
}
} // namespace ainpc::archive
