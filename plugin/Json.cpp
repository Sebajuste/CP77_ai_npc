#include "Json.hpp"

#include <cstdlib>

namespace ainpc::json
{
namespace
{
// How deep a document may nest before it is refused.
//
// This is a RESOURCE bound, not a crash guard -- the difference matters, because it used to be
// the crash guard and that was the wrong fix. The parser below holds its nesting on the heap,
// so a deep document costs memory and nothing else; without a bound it would cost unbounded
// memory, which is the only reason a number is still here. Real payloads nest three or four
// deep.
constexpr int kMaxDepth = 64;

// The lexer. Everything here reads forward over the input and never calls itself.
struct Reader
{
    const std::string& in;
    size_t at = 0;

    bool Done() const
    {
        return at >= in.size();
    }

    char Peek() const
    {
        return at < in.size() ? in[at] : '\0';
    }

    void SkipSpace()
    {
        while (at < in.size())
        {
            const char c = in[at];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
            {
                ++at;
            }
            else
            {
                break;
            }
        }
    }

    bool Literal(const char* aWord)
    {
        const size_t length = std::char_traits<char>::length(aWord);
        if (in.compare(at, length, aWord) != 0)
        {
            return false;
        }
        at += length;
        return true;
    }

    // Appends one code point as UTF-8. The whole reason this function exists is that a
    // \u escape arrives as UTF-16, and pasting the low byte would silently turn every
    // accent into a different letter.
    static void AppendUtf8(std::string& aOut, unsigned int aCodePoint)
    {
        if (aCodePoint < 0x80)
        {
            aOut.push_back(static_cast<char>(aCodePoint));
        }
        else if (aCodePoint < 0x800)
        {
            aOut.push_back(static_cast<char>(0xC0 | (aCodePoint >> 6)));
            aOut.push_back(static_cast<char>(0x80 | (aCodePoint & 0x3F)));
        }
        else if (aCodePoint < 0x10000)
        {
            aOut.push_back(static_cast<char>(0xE0 | (aCodePoint >> 12)));
            aOut.push_back(static_cast<char>(0x80 | ((aCodePoint >> 6) & 0x3F)));
            aOut.push_back(static_cast<char>(0x80 | (aCodePoint & 0x3F)));
        }
        else
        {
            aOut.push_back(static_cast<char>(0xF0 | (aCodePoint >> 18)));
            aOut.push_back(static_cast<char>(0x80 | ((aCodePoint >> 12) & 0x3F)));
            aOut.push_back(static_cast<char>(0x80 | ((aCodePoint >> 6) & 0x3F)));
            aOut.push_back(static_cast<char>(0x80 | (aCodePoint & 0x3F)));
        }
    }

    bool Hex4(unsigned int& aOut)
    {
        if (at + 4 > in.size())
        {
            return false;
        }
        aOut = 0;
        for (int i = 0; i < 4; ++i)
        {
            const char c = in[at + i];
            aOut <<= 4;
            if (c >= '0' && c <= '9')
            {
                aOut |= static_cast<unsigned int>(c - '0');
            }
            else if (c >= 'a' && c <= 'f')
            {
                aOut |= static_cast<unsigned int>(c - 'a' + 10);
            }
            else if (c >= 'A' && c <= 'F')
            {
                aOut |= static_cast<unsigned int>(c - 'A' + 10);
            }
            else
            {
                return false;
            }
        }
        at += 4;
        return true;
    }

    bool String(std::string& aOut)
    {
        if (Peek() != '"')
        {
            return false;
        }
        ++at;

        while (at < in.size())
        {
            const char c = in[at++];
            if (c == '"')
            {
                return true;
            }
            if (c != '\\')
            {
                aOut.push_back(c);
                continue;
            }
            if (at >= in.size())
            {
                return false;
            }

            const char escape = in[at++];
            switch (escape)
            {
            case '"': aOut.push_back('"'); break;
            case '\\': aOut.push_back('\\'); break;
            case '/': aOut.push_back('/'); break;
            case 'b': aOut.push_back('\b'); break;
            case 'f': aOut.push_back('\f'); break;
            case 'n': aOut.push_back('\n'); break;
            case 'r': aOut.push_back('\r'); break;
            case 't': aOut.push_back('\t'); break;
            case 'u':
            {
                unsigned int unit = 0;
                if (!Hex4(unit))
                {
                    return false;
                }
                // A high surrogate is only half a character. Paired with the low one that
                // must follow it, or the emoji and the rarer CJK become two broken bytes.
                if (unit >= 0xD800 && unit <= 0xDBFF && at + 1 < in.size() && in[at] == '\\' && in[at + 1] == 'u')
                {
                    const size_t mark = at;
                    at += 2;
                    unsigned int low = 0;
                    if (Hex4(low) && low >= 0xDC00 && low <= 0xDFFF)
                    {
                        unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
                    }
                    else
                    {
                        at = mark;
                    }
                }
                AppendUtf8(aOut, unit);
                break;
            }
            default:
                return false;
            }
        }
        return false;
    }

    // A scalar: string, number, true, false, null. Never a container.
    bool Scalar(Value& aOut)
    {
        const char c = Peek();
        if (c == '"')
        {
            aOut.kind = Kind::String;
            return String(aOut.text);
        }
        if (c == 't')
        {
            aOut.kind = Kind::Bool;
            aOut.boolean = true;
            return Literal("true");
        }
        if (c == 'f')
        {
            aOut.kind = Kind::Bool;
            aOut.boolean = false;
            return Literal("false");
        }
        if (c == 'n')
        {
            aOut.kind = Kind::Null;
            return Literal("null");
        }

        // strtod is enough: nothing here needs more precision than a token count and a dollar
        // figure, and both survive a double intact.
        const char* begin = in.c_str() + at;
        char* end = nullptr;
        const double parsed = std::strtod(begin, &end);
        if (end == begin)
        {
            return false;
        }
        at += static_cast<size_t>(end - begin);
        aOut.kind = Kind::Number;
        aOut.number = parsed;
        return true;
    }
};

// Where the loop is between two tokens.
enum class Step
{
    Opened,    // a container was just opened: its first key, its first value, or its closer
    Key,       // inside an object, a key must come next
    Value,     // a value must come next
    Separator, // a value has just been completed: a comma or a closer must come next
};
} // namespace

const Value* Value::Find(const char* aKey) const
{
    if (kind != Kind::Object)
    {
        return nullptr;
    }
    for (const auto& field : fields)
    {
        if (field.first == aKey)
        {
            return &field.second;
        }
    }
    return nullptr;
}

std::string Value::StringAt(const char* aKey, const std::string& aFallback) const
{
    const Value* found = Find(aKey);
    return (found && found->kind == Kind::String) ? found->text : aFallback;
}

long long Value::IntAt(const char* aKey, long long aFallback) const
{
    const Value* found = Find(aKey);
    return (found && found->kind == Kind::Number) ? static_cast<long long>(found->number) : aFallback;
}

bool Value::BoolAt(const char* aKey, bool aFallback) const
{
    const Value* found = Find(aKey);
    return (found && found->kind == Kind::Bool) ? found->boolean : aFallback;
}

// ── ITERATIVE, AND THAT IS THE POINT ────────────────────────────────────────
//
// This parser does not call itself. Nesting is held in `open`, a plain vector used as a
// stack, so the depth of a document costs heap and never call frames.
//
// The version before this one was a recursive descent, and a recursive descent turns "how
// deeply is this document nested" into "how deep is the stack of the thread parsing it". That
// thread is inside the game process, and not every document reaching here is ours: settings.json
// is edited by the player and sits in a folder any mod can write to, and a CLI's stdout is only
// as well-formed as the CLI. A file of ten thousand open brackets took the game down with it.
// A depth limit made that particular file safe; it left the shape of the bug in place.
//
// There is no set of visited nodes, and there is nothing missing: the input is a token stream
// and the output is a tree, so nothing is ever reached twice and there are no cycles to detect.
// What an explicit stack replaces is the call stack, not a graph traversal.
//
// A completed container is MOVED into its parent rather than pointed at. That is what makes
// the stack safe: holding a pointer into a parent's vector would dangle the moment that vector
// grew, which is the trap this shape of parser usually falls into.
bool Parse(const std::string& aInput, Value& aOut)
{
    Reader reader{aInput};

    std::vector<Value> open;            // the containers currently unclosed
    std::vector<std::string> keys;      // the key awaiting a value, one per open level
    Value root;
    bool haveRoot = false;

    // Attaches a finished value to whatever is waiting for it. False means the document tried
    // to carry a second root.
    const auto deliver = [&](Value&& aValue) -> bool
    {
        if (open.empty())
        {
            if (haveRoot)
            {
                return false;
            }
            root = std::move(aValue);
            haveRoot = true;
            return true;
        }

        Value& parent = open.back();
        if (parent.kind == Kind::Object)
        {
            parent.fields.emplace_back(std::move(keys.back()), std::move(aValue));
            keys.back().clear();
        }
        else
        {
            parent.items.push_back(std::move(aValue));
        }
        return true;
    };

    // Pops the innermost container and hands it to its parent.
    const auto close = [&](char aCloser) -> bool
    {
        if (open.empty())
        {
            return false;
        }
        const bool isObject = open.back().kind == Kind::Object;
        if ((aCloser == '}') != isObject)
        {
            return false; // "[1}" and friends
        }

        Value finished = std::move(open.back());
        open.pop_back();
        keys.pop_back();
        return deliver(std::move(finished));
    };

    Step step = Step::Value;

    for (;;)
    {
        reader.SkipSpace();

        if (reader.Done())
        {
            // A clean ending is one root, fully closed. The tree is handed over only then:
            // a caller must never be given the half-built remains of a document that turned
            // out to be malformed three bytes later.
            if (!haveRoot || !open.empty())
            {
                return false;
            }
            aOut = std::move(root);
            return true;
        }

        const char c = reader.Peek();

        switch (step)
        {
        case Step::Opened:
        case Step::Value:
        {
            // A closer is legal here only on a container that was just opened -- otherwise it
            // is a trailing comma, which is not JSON.
            if ((c == '}' || c == ']'))
            {
                if (step != Step::Opened || !close(c))
                {
                    return false;
                }
                ++reader.at;
                step = Step::Separator;
                break;
            }

            // An object that was just opened wants a key before a value.
            if (step == Step::Opened && !open.empty() && open.back().kind == Kind::Object)
            {
                step = Step::Key;
                continue;
            }

            if (c == '{' || c == '[')
            {
                if (static_cast<int>(open.size()) >= kMaxDepth)
                {
                    return false;
                }
                Value container;
                container.kind = (c == '{') ? Kind::Object : Kind::Array;
                open.push_back(std::move(container));
                keys.emplace_back();
                ++reader.at;
                step = Step::Opened;
                break;
            }

            Value scalar;
            if (!reader.Scalar(scalar) || !deliver(std::move(scalar)))
            {
                return false;
            }
            step = Step::Separator;
            break;
        }

        case Step::Key:
        {
            // Only reachable inside an object.
            if (c == '}')
            {
                return false; // a trailing comma before the closer
            }
            std::string key;
            if (!reader.String(key))
            {
                return false;
            }
            reader.SkipSpace();
            if (reader.Peek() != ':')
            {
                return false;
            }
            ++reader.at;
            keys.back() = std::move(key);
            step = Step::Value;
            break;
        }

        case Step::Separator:
        {
            if (c == ',')
            {
                if (open.empty())
                {
                    return false; // a comma outside any container
                }
                ++reader.at;
                step = (open.back().kind == Kind::Object) ? Step::Key : Step::Value;
                break;
            }
            if (c == '}' || c == ']')
            {
                if (!close(c))
                {
                    return false;
                }
                ++reader.at;
                break; // stays in Separator: the container just became a completed value
            }
            // Anything else is trailing content. A CLI that printed a log line before its
            // JSON is exactly the case worth refusing rather than half-reading.
            return false;
        }
        }
    }
}

std::string Quote(const std::string& aText)
{
    std::string out;
    out.reserve(aText.size() + 2);
    out.push_back('"');
    for (const unsigned char c : aText)
    {
        switch (c)
        {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\b': out += "\\b"; break;
        case '\f': out += "\\f"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20)
            {
                static const char* digits = "0123456789abcdef";
                out += "\\u00";
                out.push_back(digits[(c >> 4) & 0x0F]);
                out.push_back(digits[c & 0x0F]);
            }
            else
            {
                // Everything from 0x20 up is passed through byte for byte, which is what
                // keeps a UTF-8 accent an accent instead of an escape sequence nobody asked
                // for.
                out.push_back(static_cast<char>(c));
            }
            break;
        }
    }
    out.push_back('"');
    return out;
}
} // namespace ainpc::json
