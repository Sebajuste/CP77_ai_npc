#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>

#include "HttpStream.hpp"

#include <cstdio>
#include <mutex>

namespace ainpc::http
{
namespace
{
// Generous, because the point of the numbers is to end an infinite wait rather than to enforce
// a deadline. The receive timeout is per read and not per reply: a stream that has gone this
// long without a byte is dead, keep-alive comments included.
constexpr int kResolveMs = 15000;
constexpr int kConnectMs = 15000;
constexpr int kSendMs = 30000;
constexpr int kReceiveMs = 60000;

// One request at a time, because one worker thread runs them. The slot exists so Cancel() can
// close the handle a blocked read is sitting on: closing it is the documented way to abort a
// synchronous WinHTTP operation, and there is no other.
std::mutex g_liveMutex;
HINTERNET g_liveRequest = nullptr;
bool g_cancelled = false;

std::string Describe(const char* aWhat, DWORD aError)
{
    char buffer[160];
    std::snprintf(buffer, sizeof(buffer), "%s (WinHTTP error %lu)", aWhat, aError);
    return buffer;
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

std::wstring Header(HINTERNET aRequest, DWORD aInfoLevel, const wchar_t* aName)
{
    DWORD size = 0;
    WinHttpQueryHeaders(aRequest, aInfoLevel, aName, WINHTTP_NO_OUTPUT_BUFFER, &size, WINHTTP_NO_HEADER_INDEX);
    if (size == 0 || GetLastError() != ERROR_INSUFFICIENT_BUFFER)
    {
        return {};
    }
    std::wstring value(size / sizeof(wchar_t), L'\0');
    if (!WinHttpQueryHeaders(aRequest, aInfoLevel, aName, value.data(), &size, WINHTTP_NO_HEADER_INDEX))
    {
        return {};
    }
    value.resize(size / sizeof(wchar_t));
    while (!value.empty() && value.back() == L'\0')
    {
        value.pop_back();
    }
    return value;
}
} // namespace

StreamOutcome PostStream(const std::wstring& aUrl, const std::vector<std::wstring>& aHeaders,
                         const std::string& aBody, const ByteSink& aSink)
{
    StreamOutcome outcome;

    URL_COMPONENTS parts{};
    parts.dwStructSize = sizeof(parts);
    parts.dwHostNameLength = 1;
    parts.dwUrlPathLength = 1;
    if (!WinHttpCrackUrl(aUrl.c_str(), 0, 0, &parts))
    {
        outcome.transportError = Describe("the endpoint is not a URL WinHTTP can read", GetLastError());
        return outcome;
    }
    const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
    const std::wstring path(parts.lpszUrlPath, parts.dwUrlPathLength);

    HINTERNET session = WinHttpOpen(L"ai_npc/1.0", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                    WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session)
    {
        outcome.transportError = Describe("no HTTP session could be opened", GetLastError());
        return outcome;
    }
    WinHttpSetTimeouts(session, kResolveMs, kConnectMs, kSendMs, kReceiveMs);

    HINTERNET connection = WinHttpConnect(session, host.c_str(), parts.nPort, 0);
    if (!connection)
    {
        outcome.transportError = Describe("the provider could not be reached", GetLastError());
        WinHttpCloseHandle(session);
        return outcome;
    }

    const DWORD flags = parts.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET request = WinHttpOpenRequest(connection, L"POST", path.c_str(), nullptr, WINHTTP_NO_REFERER,
                                           WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!request)
    {
        outcome.transportError = Describe("the request could not be built", GetLastError());
        WinHttpCloseHandle(connection);
        WinHttpCloseHandle(session);
        return outcome;
    }

    {
        std::lock_guard<std::mutex> guard(g_liveMutex);
        if (g_cancelled)
        {
            WinHttpCloseHandle(request);
            WinHttpCloseHandle(connection);
            WinHttpCloseHandle(session);
            outcome.transportError = "the plugin is shutting down";
            return outcome;
        }
        g_liveRequest = request;
    }

    for (const std::wstring& header : aHeaders)
    {
        WinHttpAddRequestHeaders(request, header.c_str(), static_cast<DWORD>(header.size()),
                                 WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);
    }

    if (!WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, const_cast<char*>(aBody.data()),
                            static_cast<DWORD>(aBody.size()), static_cast<DWORD>(aBody.size()), 0))
    {
        outcome.transportError = Describe("the request could not be sent", GetLastError());
    }
    else if (!WinHttpReceiveResponse(request, nullptr))
    {
        outcome.transportError = Describe("the provider never answered", GetLastError());
    }
    else
    {
        DWORD status = 0;
        DWORD size = sizeof(status);
        if (WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                                WINHTTP_HEADER_NAME_BY_INDEX, &status, &size, WINHTTP_NO_HEADER_INDEX))
        {
            outcome.status = static_cast<int>(status);
        }
        outcome.date = Narrow(Header(request, WINHTTP_QUERY_DATE, WINHTTP_HEADER_NAME_BY_INDEX));

        // A body that is not 200 is not a stream: it is one error object, and the lane reads it
        // whole. Accumulating it here rather than pushing it at a sink that expects SSE keeps
        // the parser from being handed something it would report as a broken stream.
        const bool streaming = outcome.status == 200;

        char buffer[4096];
        for (;;)
        {
            DWORD read = 0;
            if (!WinHttpReadData(request, buffer, sizeof(buffer), &read))
            {
                if (outcome.status == 200)
                {
                    outcome.transportError = Describe("the stream broke while it was being read", GetLastError());
                }
                break;
            }
            if (read == 0)
            {
                break;
            }
            if (streaming)
            {
                if (!aSink(buffer, read))
                {
                    break;
                }
            }
            else
            {
                outcome.body.append(buffer, read);
            }
        }
    }

    bool mine = false;
    {
        std::lock_guard<std::mutex> guard(g_liveMutex);
        if (g_liveRequest == request)
        {
            g_liveRequest = nullptr;
            mine = true;
        }
    }
    if (mine)
    {
        WinHttpCloseHandle(request);
    }
    WinHttpCloseHandle(connection);
    WinHttpCloseHandle(session);
    return outcome;
}

void Cancel()
{
    std::lock_guard<std::mutex> guard(g_liveMutex);
    g_cancelled = true;
    if (g_liveRequest)
    {
        WinHttpCloseHandle(g_liveRequest);
        g_liveRequest = nullptr;
    }
}
} // namespace ainpc::http
