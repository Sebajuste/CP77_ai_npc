// One HTTPS POST whose response body is read as it arrives.
//
// RedHttpClient cannot do this and no amount of care would make it: it is a request/response
// API that hands over a complete HttpResponse, and there is no partial delivery to be had from
// it. That is the whole reason the streaming lane lives in the DLL rather than beside the
// transport that is already there.
//
// WinHTTP, because it reads a body incrementally and does TLS itself: nothing is linked beyond
// winhttp.lib, and no certificate store, no OpenSSL and no second DLL enter the mod.
//
// NEVER ON THE GAME THREAD. Everything here blocks -- see rule 1 at the top of ScriptApi.cpp.

#pragma once

#include <functional>
#include <string>
#include <vector>

namespace ainpc::http
{
struct StreamOutcome
{
    // The HTTP status, or 0 when there never was one -- the request did not reach a server.
    int status = 0;

    // Why there was no status. Empty when there was one.
    std::string transportError;

    // The whole body, for a status that is not 200. A 200 goes to the sink instead, byte by
    // byte, and is not accumulated here.
    std::string body;

    // The server's `Date` header. The mod's token ledger rolls its day from it, so a lane that
    // supplied nothing would leave the daily cap frozen on whatever day it last saw.
    std::string date;
};

// Called once per read, on the calling thread, with whatever arrived. False ends the read.
using ByteSink = std::function<bool(const char*, size_t)>;

// Headers as full lines ("Authorization: Bearer ...").
StreamOutcome PostStream(const std::wstring& aUrl, const std::vector<std::wstring>& aHeaders,
                         const std::string& aBody, const ByteSink& aSink);

// Aborts the read in flight, if any, and refuses the ones after it.
//
// Called when the plugin is unloading. Without it the game would hold itself open for as long
// as the receive timeout, waiting on a socket nobody is going to read -- which is the same
// reason Stop() terminates the CLI job object.
void Cancel();
} // namespace ainpc::http
