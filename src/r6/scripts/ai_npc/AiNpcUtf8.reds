// Text measured and cut in CHARACTERS, not in bytes.
//
// StrLen, StrLeft, StrRight and StrMid count BYTES, and a French accent is two of them. A
// backspace written as StrLeft(text, StrLen(text) - 1) removes half of an "e-acute" and
// leaves the lead byte behind, alone, inside the string, with nothing in the game saying a
// word about it.
//
// The damage is not the display. The broken byte is stored in the journal, and from then on
// EVERY request for that contact carries it: the body is no longer valid UTF-8, the http
// client refuses to send it, and what comes back is status 0 -- no status, no log line,
// nothing to read. One half-deleted accent silences a contact permanently and reads in game
// as a network problem.
//
// Codeware ships UTF8StrLen / UTF8StrLeft / UTF8StrRight / UTF8StrMid, which count
// characters, and this module is a thin layer over them -- named after what a caller wants
// rather than after the encoding, so the byte-counting twin is never the obvious thing to
// reach for.
//
// What NOBODY ships is a validity check: no API answers "is this string well-formed UTF-8",
// and REDscript cannot look at a byte. AiNpcUtf8Clean below is the closest honest thing, a
// round trip through the decoder keeping what comes back whole. Its behaviour on input that
// is ALREADY broken depends on what the Codeware native does with a stray byte, which cannot
// be established offline: the self-tests pin down the well-formed cases, and the broken case
// is marked as needing a live run.
//
// THE RULE: any code that cuts, caps or measures text A PLAYER TYPED uses this module, and
// tools/lint.ps1 enforces it on every file that assembles text from key events. Everything
// else may keep StrLen -- cutting a trailing "\n" is a byte and a character at once, and json
// parsing is byte work by nature.
module AiNpc

/// Measuring and cutting ///

// Length in characters. Zero for the empty string.
func AiNpcUtf8Len(text: String) -> Int32 {
    return UTF8StrLen(text);
}

// The first `count` characters. A count at or above the length returns the text unchanged,
// and a negative one returns nothing, so a caller may hand over an unchecked arithmetic
// result -- which is where the original bug came from.
func AiNpcUtf8Left(text: String, count: Int32) -> String {
    if count <= 0 {
        return "";
    }
    if count >= UTF8StrLen(text) {
        return text;
    }
    return UTF8StrLeft(text, count);
}

// The last `count` characters, same contract as above. This is what a text field shows when
// the value is longer than the box: the caret is at the end, so the tail is the useful half.
func AiNpcUtf8Right(text: String, count: Int32) -> String {
    if count <= 0 {
        return "";
    }
    if count >= UTF8StrLen(text) {
        return text;
    }
    return UTF8StrRight(text, count);
}

// One backspace.
//
// A separate name rather than "Left(text, Len(text) - 1)" spelled out at the call site: the
// subtraction is the whole bug, and a call site that never writes it cannot get it wrong.
func AiNpcUtf8DropLast(text: String) -> String {
    return AiNpcUtf8Left(text, UTF8StrLen(text) - 1);
}

/// Well-formedness ///

// Rebuilds a string one character at a time and keeps what the decoder hands back whole.
//
// The guard for text ENTERING the mod -- what a player typed, and what another mod passes to
// the public API. Not applied to a whole request body: the funnel is one message at a time
// (AiNpcAppendMessage), where the cost is one pass over a sentence rather than a transcript.
//
// A character is kept when its own slice comes back non-empty and still measures one
// character. What a stray byte does here is decided by the Codeware native: if it drops it,
// the byte is removed; if it hands it back as a character of its own, this returns the text
// unchanged. Which is why the fix is BOTH -- correct editing so the byte is never produced,
// and this so a value that arrived from somewhere else is not filed as history forever.
func AiNpcUtf8Clean(text: String) -> String {
    let count = UTF8StrLen(text);
    if count <= 0 {
        return "";
    }

    let result = "";
    let i = 0;
    while i < count {
        let character = UTF8StrMid(text, i, 1);
        if NotEquals(StrLen(character), 0) && Equals(UTF8StrLen(character), 1) {
            result += character;
        }
        i += 1;
    }
    return result;
}

// Whether cleaning would change anything. Compared in BYTES on purpose: two strings of the
// same character count can still differ by a dropped stray byte, and that byte is the whole
// subject.
func AiNpcUtf8IsClean(text: String) -> Bool {
    return Equals(StrLen(AiNpcUtf8Clean(text)), StrLen(text));
}
