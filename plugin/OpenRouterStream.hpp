// The streaming lane: OpenRouter, over a socket this plugin owns, delivering sentences as they
// complete and one whole reply at the end.
//
// It sits BESIDE the transport the mod already has and does not replace it. RedHttpClient stays,
// the OpenRouter provider stays, and this is a second provider a player selects. Moving the
// whole lane in here would drop a plugin dependency, which is a real gain and a separate
// decision.
//
// Transport.hpp says the plugin knows about CLI backends only and must never learn what
// OpenRouter is. This file is the stated exception and it is deliberately not an ITransport:
// there is no executable, no command line and no auth check to build, and forcing it into that
// shape would leave five methods answering "not applicable". What it shares with a CLI backend
// is the only thing that matters -- it receives the body an HTTP lane would have posted and
// answers in the same dialect, so the mod keeps one request builder and one response parser.

#pragma once

#include <functional>
#include <string>

#include "Transport.hpp"

namespace ainpc::openrouter
{
// The name script sends across for this lane, and a contract with AiNpcProviderName.
const char* ProviderName();

// One finished sentence. `aLast` is true on the call that ends the stream, and that call may
// carry an empty text -- the reply having ended exactly on a sentence already delivered is the
// ordinary case, and the voice still needs to be told there is no more.
using SentenceSink = std::function<void(const std::string& aText, bool aLast)>;

struct Streamed
{
    ChatReply reply;

    // The server's own `Date` header, empty when it sent none.
    std::string date;

    int sentences = 0;

    // THE NUMBER THIS WHOLE LANE EXISTS FOR: how long the player waits for something the voice
    // can start speaking, against how long they would wait for the whole reply. -1 when no
    // sentence completed before the end, which would mean the model streams too coarsely for
    // any of this to buy anything -- a result worth having, and one only the log can show.
    long long firstSentenceMs = -1;
    long long totalMs = 0;
};

// Blocking, and never on the game thread. `aOnSentence` is called on the calling thread as each
// sentence completes.
Streamed Stream(const std::string& aChatBody, const std::string& aApiKey, const SentenceSink& aOnSentence);
} // namespace ainpc::openrouter
