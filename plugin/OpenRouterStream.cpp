#include "OpenRouterStream.hpp"

#include "HttpStream.hpp"
#include "Stream.hpp"
#include "Text.hpp"

#include <chrono>
#include <vector>

namespace ainpc::openrouter
{
namespace
{
constexpr const wchar_t* kEndpoint = L"https://openrouter.ai/api/v1/chat/completions";

// What the HTTP lane sends, plus the one this lane needs. The referer and the title are what
// OpenRouter attributes the traffic by, and a mod that dropped them on one lane would appear to
// be two applications.
std::vector<std::wstring> Headers(const std::string& aApiKey)
{
    return {
        L"Content-Type: application/json",
        L"Accept: text/event-stream",
        L"Authorization: Bearer " + Widen(aApiKey),
        L"HTTP-Referer: https://www.nexusmods.com/cyberpunk2077",
        L"X-Title: Cyberpunk 2077 AI NPC",
    };
}

long long MillisecondsSince(const std::chrono::steady_clock::time_point& aStart)
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - aStart).count();
}
} // namespace

const char* ProviderName()
{
    return "OpenRouterStream";
}

Streamed Stream(const std::string& aChatBody, const std::string& aApiKey, const SentenceSink& aOnSentence)
{
    Streamed streamed;
    const auto started = std::chrono::steady_clock::now();

    if (aApiKey.empty())
    {
        streamed.reply = Failure(401, "no openRouterApiKey set in r6\\storages\\AiNpc\\settings.json");
        streamed.totalMs = MillisecondsSince(started);
        return streamed;
    }

    stream::Assembler assembler;

    // Delivered as they complete, never held back: holding one until the next arrives would cost
    // the voice exactly the delay this lane was built to remove.
    const auto hand = [&](const std::vector<std::string>& aSentences) {
        for (const std::string& sentence : aSentences)
        {
            if (streamed.firstSentenceMs < 0)
            {
                streamed.firstSentenceMs = MillisecondsSince(started);
            }
            ++streamed.sentences;
            aOnSentence(sentence, false);
        }
    };

    const http::StreamOutcome outcome =
        http::PostStream(kEndpoint, Headers(aApiKey), stream::WithStreamOptions(aChatBody),
                         [&](const char* aBytes, size_t aCount) {
                             std::vector<std::string> sentences;
                             assembler.Feed(aBytes, aCount, sentences);
                             hand(sentences);
                             return true;
                         });

    std::vector<std::string> last;
    assembler.Finish(last);
    hand(last);

    // The end of the stream, always announced, and separately from the sentences. A reply that
    // ended on a sentence already spoken still has to tell the voice there is no more coming --
    // otherwise the last thing it heard is indistinguishable from a pause.
    aOnSentence("", true);

    streamed.date = outcome.date;
    streamed.totalMs = MillisecondsSince(started);

    if (outcome.status == 0)
    {
        streamed.reply = Failure(502, "OpenRouter: " + (outcome.transportError.empty()
                                                            ? std::string("the request never reached the provider")
                                                            : outcome.transportError));
        return streamed;
    }
    if (outcome.status != 200)
    {
        // The provider's own error body, passed through untouched: it is already the shape the
        // mod reads, and rewording it here would hide the sentence that says what to fix.
        streamed.reply.status = outcome.status;
        streamed.reply.body = outcome.body.empty() ? Failure(outcome.status, "OpenRouter answered with no body").body
                                                   : outcome.body;
        return streamed;
    }

    if (!assembler.Error().empty())
    {
        streamed.reply = Failure(502, "OpenRouter: " + assembler.Error());
        return streamed;
    }

    // A stream that stopped without the model saying it had finished. The speaking lane has a
    // watchdog waiting for one answer, and a truncated reply delivered as a good one would reach
    // a bubble mid-sentence and be written into the thread for good -- so this takes the single
    // exit every failed request already takes.
    if (!assembler.Complete())
    {
        streamed.reply = Failure(502, "OpenRouter: the stream ended before the reply did (" +
                                          std::to_string(assembler.Text().size()) + " characters received)");
        return streamed;
    }

    streamed.reply.status = 200;
    streamed.reply.body = assembler.Response();
    return streamed;
}
} // namespace ainpc::openrouter
