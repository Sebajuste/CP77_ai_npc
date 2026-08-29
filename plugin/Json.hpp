// The smallest JSON this plugin can do its job with.
//
// It needs JSON in both directions and cannot borrow the mod's: RedData lives in redscript,
// on the other side of the boundary. It also cannot take a dependency -- the plugin builds
// with cl.exe and a header-only SDK, and keeping it that way is a deliberate decision
// recorded in build.ps1.
//
// So this is a reader and a writer for exactly what crosses the boundary: an OpenAI-style
// request body coming in, a CLI's own output being read, an OpenAI-style response going out.
// No schema, no pretty printing, no number formatting beyond integers.
//
// UTF-8 is not an afterthought here. The characters speak French; \u escapes are decoded to
// UTF-8 including surrogate pairs, and the writer escapes only what JSON requires, leaving
// multi-byte sequences untouched. A mangled accent is invisible until it reaches a bubble.

#pragma once

#include <string>
#include <utility>
#include <vector>

namespace ainpc::json
{
enum class Kind
{
    Null,
    Bool,
    Number,
    String,
    Array,
    Object
};

struct Value
{
    Kind kind = Kind::Null;
    bool boolean = false;
    double number = 0.0;
    std::string text;
    std::vector<Value> items;                          // Array
    std::vector<std::pair<std::string, Value>> fields; // Object

    // Null when the key is absent or this is not an object. Callers are expected to check;
    // there is no exception to catch and no default to be surprised by.
    const Value* Find(const char* aKey) const;

    // Typed reads with a fallback, for the many places where "absent" and "wrong type" are
    // the same thing to the caller.
    std::string StringAt(const char* aKey, const std::string& aFallback = "") const;
    long long IntAt(const char* aKey, long long aFallback = 0) const;
    bool BoolAt(const char* aKey, bool aFallback = false) const;

    bool IsObject() const
    {
        return kind == Kind::Object;
    }
    bool IsArray() const
    {
        return kind == Kind::Array;
    }
    bool IsString() const
    {
        return kind == Kind::String;
    }
};

// False on malformed input, and the value is then meaningless. There is no error position:
// what the caller does with a body it cannot read is the same whatever byte broke it.
bool Parse(const std::string& aInput, Value& aOut);

// A JSON string literal, quotes included.
std::string Quote(const std::string& aText);
} // namespace ainpc::json
