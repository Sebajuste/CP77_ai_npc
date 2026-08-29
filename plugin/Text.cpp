#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "Text.hpp"

namespace ainpc
{
std::wstring Widen(const std::string& aUtf8)
{
    if (aUtf8.empty())
    {
        return L"";
    }
    const int needed = MultiByteToWideChar(CP_UTF8, 0, aUtf8.c_str(), static_cast<int>(aUtf8.size()), nullptr, 0);
    if (needed <= 0)
    {
        return L"";
    }
    std::wstring out(static_cast<size_t>(needed), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, aUtf8.c_str(), static_cast<int>(aUtf8.size()), out.data(), needed);
    return out;
}

std::string LastLine(const std::string& aText)
{
    size_t end = aText.find_last_not_of(" \t\r\n");
    if (end == std::string::npos)
    {
        return "";
    }
    const size_t start = aText.find_last_of('\n', end);
    const size_t from = (start == std::string::npos) ? 0 : start + 1;
    std::string line = aText.substr(from, end - from + 1);
    while (!line.empty() && (line.front() == ' ' || line.front() == '\r' || line.front() == '\t'))
    {
        line.erase(line.begin());
    }
    return line;
}
} // namespace ainpc
