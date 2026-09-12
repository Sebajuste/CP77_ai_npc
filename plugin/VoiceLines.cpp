#include "VoiceLines.hpp"

#include <map>
#include <mutex>

namespace ainpc::voicelines
{
namespace
{
std::mutex g_lock;
std::map<std::string, std::vector<std::string>> g_declared;
} // namespace

bool Declare(const std::string& aVoiceName, const std::vector<std::string>& aFileNames)
{
    std::lock_guard<std::mutex> guard(g_lock);
    const auto found = g_declared.find(aVoiceName);
    if (found != g_declared.end() && found->second == aFileNames)
    {
        return false;
    }
    g_declared[aVoiceName] = aFileNames;
    return true;
}

std::vector<std::string> For(const std::string& aVoiceName)
{
    std::lock_guard<std::mutex> guard(g_lock);
    const auto found = g_declared.find(aVoiceName);
    return found == g_declared.end() ? std::vector<std::string>{} : found->second;
}
} // namespace ainpc::voicelines
