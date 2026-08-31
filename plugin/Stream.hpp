// Reading a reply while it is still being written, and cutting it into things a voice can say.
//
// A cloned voice on this project's reference machine synthesises at about 1.4x real time, so a
// four-second reply costs three seconds of silence before the character starts speaking. The
// answer is not a faster synthesiser: it is to hand the voice the first sentence while the model
// is still writing the second, and hide the synthesis inside a delay the player is already
// paying for.
//
// STREAMING IS ADDITIVE. Everything downstream of the reply -- the action commands, the repair
// pass, the memory service, the thread, the surfaces -- receives one complete reply and keeps
// receiving one complete reply. What this file produces on the side is for the voice, and for
// nothing else.
//
// Nothing here touches RED4ext, Windows or a socket: bytes in, sentences and a reply out. That
// is what lets the whole of the intelligence be asserted from a fixture in plugin\test, which
// matters more here than anywhere else in the plugin -- an SSE stream has three failure modes
// that a launched game shows as "the character said nothing" and cannot tell apart.

#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace ainpc::stream
{
// The chat body the mod built, asking for it a token at a time.
//
// The body is spliced rather than rebuilt: it carries the slot's parameters -- temperature,
// max_tokens, a routing preference -- and rebuilding it here would mean this file owning a
// second definition of what a request is. It only ever adds two keys.
//
// `include_usage` is not optional for this mod. The usage block is what the ledger charges and
// what the daily cap counts, and a stream without it delivers a reply that cost nothing
// measurable.
std::string WithStreamOptions(const std::string& aChatBody);

// Bytes off the wire, complete `data:` payloads out.
//
// Three things it has to survive, all of them seen in the wild: an event split across two reads
// (the payload comes out on the read that completes it, never in halves), a comment line -- the
// `: ...` keep-alives OpenRouter sends, which a parser that JSON-decodes every line dies on --
// and the `[DONE]` sentinel, which is handed on as a payload rather than swallowed, because
// deciding what it means belongs to the reader of the chunks.
class SseReader
{
public:
    void Feed(const char* aBytes, size_t aCount, std::vector<std::string>& aPayloads);

    // An event that arrived without its blank line, which is what a connection closing looks
    // like.
    void Finish(std::vector<std::string>& aPayloads);

private:
    void TakeLine(const std::string& aLine, std::vector<std::string>& aPayloads);

    std::string m_bytes; // read but not yet a whole line
    std::string m_data;  // the data: lines of the event being read
    bool m_haveData = false;
};

// The shortest a sentence may be before a full stop is allowed to end it.
//
// Without a minimum, "M." ends a sentence, and so do "22h.", "Dr." and every initial in a name.
// The cost of the minimum is the opposite mistake -- two short sentences spoken as one -- which
// nobody can hear.
constexpr size_t kShortestSentence = 20;

// Deltas in, sentences out.
class SentenceSplitter
{
public:
    void Feed(const std::string& aDelta, std::vector<std::string>& aSentences);

    // Everything left, terminated or not. MANDATORY at the end of a stream: a reply ending
    // without punctuation, or on a sentence too short to cut, lives entirely in here.
    std::string Finish();

private:
    std::string m_buffer;
};

// What one OpenRouter chunk carried.
struct Chunk
{
    bool readable = false; // false when the payload was not JSON at all
    bool done = false;     // the [DONE] sentinel
    std::string delta;
    bool finished = false; // a choice carried a finish_reason
    bool haveUsage = false;
    long long promptTokens = 0;
    long long completionTokens = 0;
    long long cachedTokens = 0;
    std::string error; // an error object carried inside the stream
};

Chunk ReadChunk(const std::string& aPayload);

// The whole of what a streamed reply is: the sentences as they complete, and the one complete
// reply behind them.
class Assembler
{
public:
    void Feed(const char* aBytes, size_t aCount, std::vector<std::string>& aSentences);

    // The end of the stream. Hands back the last sentence, which is usually the only one that
    // was never terminated.
    void Finish(std::vector<std::string>& aSentences);

    const std::string& Text() const
    {
        return m_text;
    }

    // Whether the model said it had finished. FALSE AFTER Finish() MEANS THE STREAM DIED
    // MID-REPLY, and the lane must be told that rather than handed a truncated answer.
    bool Complete() const
    {
        return m_finished;
    }

    // An error object OpenRouter put in the stream instead of a reply. Empty when there was
    // none.
    const std::string& Error() const
    {
        return m_error;
    }

    bool HaveUsage() const
    {
        return m_haveUsage;
    }

    // The reply, in the shape the mod's own response parser reads -- the same one the CLI lanes
    // answer in. Nothing downstream learns that this reply arrived in pieces.
    std::string Response() const;

private:
    void Take(const Chunk& aChunk, std::vector<std::string>& aSentences);

    SseReader m_reader;
    SentenceSplitter m_splitter;
    std::string m_text;
    std::string m_error;
    bool m_finished = false;
    bool m_haveUsage = false;
    long long m_promptTokens = 0;
    long long m_completionTokens = 0;
    long long m_cachedTokens = 0;
};
} // namespace ainpc::stream
