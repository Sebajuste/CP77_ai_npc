#include "Stream.hpp"

#include "Json.hpp"
#include "Transport.hpp"

namespace ainpc::stream
{
namespace
{
bool IsSpace(char aByte)
{
    return aByte == ' ' || aByte == '\t' || aByte == '\r' || aByte == '\n';
}

std::string Trimmed(const std::string& aText)
{
    size_t first = 0;
    while (first < aText.size() && IsSpace(aText[first]))
    {
        ++first;
    }
    size_t last = aText.size();
    while (last > first && IsSpace(aText[last - 1]))
    {
        --last;
    }
    return aText.substr(first, last - first);
}

// How many bytes of terminator start at `aAt`, or 0. The ellipsis is one character in three
// bytes, and it ends a sentence exactly as a full stop does.
size_t TerminatorAt(const std::string& aText, size_t aAt)
{
    const char byte = aText[aAt];
    if (byte == '.' || byte == '!' || byte == '?')
    {
        return 1;
    }
    if (aText.compare(aAt, 3, "\xE2\x80\xA6") == 0)
    {
        return 3;
    }
    return 0;
}

// What may stand between a terminator and the whitespace after it: a closing quote or bracket
// belongs to the sentence it closes. The three multi-byte ones are the punctuation French
// dialogue actually uses.
size_t CloserAt(const std::string& aText, size_t aAt)
{
    const char byte = aText[aAt];
    if (byte == '"' || byte == '\'' || byte == ')' || byte == ']' || byte == '}')
    {
        return 1;
    }
    if (aText.compare(aAt, 2, "\xC2\xBB") == 0)
    {
        return 2;
    }
    if (aText.compare(aAt, 3, "\xE2\x80\x9D") == 0 || aText.compare(aAt, 3, "\xE2\x80\x99") == 0)
    {
        return 3;
    }
    return 0;
}

// One past the end of a complete sentence, or npos when the buffer holds none yet.
//
// A terminator at the very end of the buffer is NOT a cut: the next read decides whether it was
// the end of a sentence or the middle of a number. Waiting costs one chunk; guessing costs a
// sentence spoken in halves.
size_t FindCut(const std::string& aBuffer)
{
    size_t at = 0;
    while (at < aBuffer.size())
    {
        if (aBuffer[at] == '\n')
        {
            if (Trimmed(aBuffer.substr(0, at)).size() >= kShortestSentence)
            {
                return at + 1;
            }
            ++at;
            continue;
        }

        const size_t terminator = TerminatorAt(aBuffer, at);
        if (terminator == 0)
        {
            ++at;
            continue;
        }

        size_t end = at + terminator;
        for (;;)
        {
            const size_t more = end < aBuffer.size() ? TerminatorAt(aBuffer, end) : 0;
            const size_t closing = (more == 0 && end < aBuffer.size()) ? CloserAt(aBuffer, end) : 0;
            if (more == 0 && closing == 0)
            {
                break;
            }
            end += more + closing;
        }

        if (end >= aBuffer.size())
        {
            return std::string::npos;
        }
        if (IsSpace(aBuffer[end]) && Trimmed(aBuffer.substr(0, end)).size() >= kShortestSentence)
        {
            return end;
        }
        at = end;
    }
    return std::string::npos;
}
} // namespace

std::string WithStreamOptions(const std::string& aChatBody)
{
    const size_t brace = aChatBody.find('{');
    if (brace == std::string::npos)
    {
        return aChatBody;
    }

    size_t after = brace + 1;
    while (after < aChatBody.size() && IsSpace(aChatBody[after]))
    {
        ++after;
    }
    const bool empty = after >= aChatBody.size() || aChatBody[after] == '}';

    std::string keys = "\"stream\":true,\"stream_options\":{\"include_usage\":true}";
    if (!empty)
    {
        keys += ",";
    }
    return aChatBody.substr(0, brace + 1) + keys + aChatBody.substr(brace + 1);
}

/// The SSE reader ///

void SseReader::Feed(const char* aBytes, size_t aCount, std::vector<std::string>& aPayloads)
{
    m_bytes.append(aBytes, aCount);

    size_t start = 0;
    for (;;)
    {
        const size_t newline = m_bytes.find('\n', start);
        if (newline == std::string::npos)
        {
            break;
        }
        size_t end = newline;
        if (end > start && m_bytes[end - 1] == '\r')
        {
            --end;
        }
        TakeLine(m_bytes.substr(start, end - start), aPayloads);
        start = newline + 1;
    }
    m_bytes.erase(0, start);
}

void SseReader::Finish(std::vector<std::string>& aPayloads)
{
    if (!m_bytes.empty())
    {
        std::string last = m_bytes;
        m_bytes.clear();
        if (!last.empty() && last.back() == '\r')
        {
            last.pop_back();
        }
        TakeLine(last, aPayloads);
    }
    TakeLine("", aPayloads);
}

void SseReader::TakeLine(const std::string& aLine, std::vector<std::string>& aPayloads)
{
    if (aLine.empty())
    {
        if (m_haveData)
        {
            aPayloads.push_back(m_data);
        }
        m_data.clear();
        m_haveData = false;
        return;
    }

    // A comment. OpenRouter sends these to keep the connection open, and a client that hands
    // every line to a JSON parser dies on them with "unexpected end of JSON input".
    if (aLine[0] == ':')
    {
        return;
    }

    if (aLine.compare(0, 5, "data:") != 0)
    {
        // event:, id:, retry: and anything else the protocol carries. None of them says
        // anything this lane needs.
        return;
    }

    size_t value = 5;
    if (value < aLine.size() && aLine[value] == ' ')
    {
        ++value;
    }
    if (m_haveData)
    {
        m_data += "\n";
    }
    m_data += aLine.substr(value);
    m_haveData = true;
}

/// The splitter ///

void SentenceSplitter::Feed(const std::string& aDelta, std::vector<std::string>& aSentences)
{
    m_buffer += aDelta;

    for (;;)
    {
        const size_t cut = FindCut(m_buffer);
        if (cut == std::string::npos)
        {
            return;
        }
        const std::string sentence = Trimmed(m_buffer.substr(0, cut));
        m_buffer.erase(0, cut);
        if (!sentence.empty())
        {
            aSentences.push_back(sentence);
        }
    }
}

std::string SentenceSplitter::Finish()
{
    const std::string left = Trimmed(m_buffer);
    m_buffer.clear();
    return left;
}

/// The chunks ///

Chunk ReadChunk(const std::string& aPayload)
{
    Chunk chunk;
    if (aPayload == "[DONE]")
    {
        chunk.readable = true;
        chunk.done = true;
        return chunk;
    }

    json::Value root;
    if (!json::Parse(aPayload, root) || !root.IsObject())
    {
        return chunk;
    }
    chunk.readable = true;

    if (const json::Value* error = root.Find("error"))
    {
        chunk.error = error->IsString() ? error->text : error->StringAt("message", "the provider reported an error");
        if (chunk.error.empty())
        {
            chunk.error = "the provider reported an error";
        }
    }

    if (const json::Value* choices = root.Find("choices"))
    {
        if (choices->IsArray() && !choices->items.empty())
        {
            const json::Value& choice = choices->items[0];
            if (const json::Value* delta = choice.Find("delta"))
            {
                chunk.delta = delta->StringAt("content");
            }
            const json::Value* reason = choice.Find("finish_reason");
            chunk.finished = reason != nullptr && reason->IsString() && !reason->text.empty();
        }
    }

    // AFTER finish_reason, AND THAT IS THE POINT. OpenRouter sends the usage block in a chunk
    // of its own, after the one that ended the reply, and a client that stops reading at
    // finish_reason loses it -- silently, with a reply that looks perfect. This mod has a
    // ledger and a daily cap that both live on these three numbers.
    if (const json::Value* usage = root.Find("usage"))
    {
        if (usage->IsObject())
        {
            chunk.haveUsage = true;
            chunk.promptTokens = usage->IntAt("prompt_tokens");
            chunk.completionTokens = usage->IntAt("completion_tokens");
            if (const json::Value* details = usage->Find("prompt_tokens_details"))
            {
                chunk.cachedTokens = details->IntAt("cached_tokens");
            }
        }
    }

    return chunk;
}

/// The assembler ///

void Assembler::Feed(const char* aBytes, size_t aCount, std::vector<std::string>& aSentences)
{
    std::vector<std::string> payloads;
    m_reader.Feed(aBytes, aCount, payloads);
    for (const std::string& payload : payloads)
    {
        Take(ReadChunk(payload), aSentences);
    }
}

void Assembler::Finish(std::vector<std::string>& aSentences)
{
    std::vector<std::string> payloads;
    m_reader.Finish(payloads);
    for (const std::string& payload : payloads)
    {
        Take(ReadChunk(payload), aSentences);
    }

    const std::string last = m_splitter.Finish();
    if (!last.empty())
    {
        aSentences.push_back(last);
    }
}

void Assembler::Take(const Chunk& aChunk, std::vector<std::string>& aSentences)
{
    if (!aChunk.readable)
    {
        return;
    }
    if (!aChunk.error.empty() && m_error.empty())
    {
        m_error = aChunk.error;
    }
    if (!aChunk.delta.empty())
    {
        m_text += aChunk.delta;
        m_splitter.Feed(aChunk.delta, aSentences);
    }
    // [DONE] counts as an ending too. It is the server saying it has nothing more to send,
    // which is the same fact finish_reason states -- and reading only one of the two would
    // report a whole reply as a broken stream on any provider that sends the other.
    if (aChunk.finished || aChunk.done)
    {
        m_finished = true;
    }
    if (aChunk.haveUsage)
    {
        m_haveUsage = true;
        m_promptTokens = aChunk.promptTokens;
        m_completionTokens = aChunk.completionTokens;
        m_cachedTokens = aChunk.cachedTokens;
    }
}

std::string Assembler::Response() const
{
    return MakeChatResponse(m_text, m_haveUsage, m_promptTokens, m_completionTokens, m_cachedTokens);
}
} // namespace ainpc::stream
