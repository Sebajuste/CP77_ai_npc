// The shape of a command tag, and nothing about what any command means.
//
// A tag is what a model writes inside its reply to act on the world: [ACTION:GIVE_EDDIES:750].
// This file knows how to recognise one and pull it out of a sentence. Which commands exist,
// who may use them and what firing one does are all somebody else's question --
// AiNpcActionPattern for the grammar of a declaration, AiNpcActionClaim for who owns what.
//
// The split matters because this half is the only one a model can reach. Everything here runs
// on text a language model wrote, so it answers "is this a tag" rather than "is this a tag I
// like", and it never guesses: a malformed bracket is left exactly as written for a caller
// that knows what to do about it.
//
// PURE: no game API, no state, no config.
module AiNpc

// The opening of every tag. One literal, because the extractor below and the pattern parser
// next door have to agree on it, and two spellings of the same constant is how they stop
// agreeing.
func AiNpcActionTagOpen() -> String {
    return "[ACTION:";
}

// The shape a declaration and a live tag both have to satisfy.
//
// No space inside is not cosmetic: the extractor below scans to the first "]", so a tag
// carrying a space would swallow prose up to the next bracket in the message.
func AiNpcActionTagIsWellFormed(tag: String) -> Bool {
    let open = AiNpcActionTagOpen();
    return StrBeginsWith(tag, open)
        && StrEndsWith(tag, "]")
        && StrLen(tag) > StrLen(open) + 1
        && !StrContains(tag, " ");
}

// Every well-formed tag in a reply, in the order written, without repeats.
//
// Unterminated is not a tag: an opening with no "]" ends the scan and yields nothing more,
// rather than returning a head no parser could close. The caller leaves it in the text, where
// the repair pass can still ask the model to rewrite it.
func AiNpcFindActionTags(text: String) -> array<String> {
    let found: array<String>;

    let open = AiNpcActionTagOpen();
    let rest = text;
    let start = StrFindFirst(rest, open);
    while start >= 0 {
        rest = StrRight(rest, StrLen(rest) - start);
        let end = StrFindFirst(rest, "]");
        if end < 0 {
            return found;
        }

        let tag = StrLeft(rest, end + 1);
        if AiNpcActionTagIsWellFormed(tag) && !ArrayContains(found, tag) {
            ArrayPush(found, tag);
        }

        rest = StrRight(rest, StrLen(rest) - (end + 1));
        start = StrFindFirst(rest, open);
    }

    return found;
}

// The first tag alone, for reading a repair back: the model was asked for a command by itself
// and answers with the tag, or the tag wrapped in an apology, or the word NONE.
func AiNpcFirstActionTag(text: String) -> String {
    let tags = AiNpcFindActionTags(text);
    if Equals(ArraySize(tags), 0) {
        return "";
    }
    return tags[0];
}

// What a tag carries between its opening and its closing bracket, split on colons.
//
// "[ACTION:TRICK:JIGJIG:2300]" yields ["TRICK", "JIGJIG", "2300"]. The first segment is the
// verb; a declaration decides what the rest mean.
func AiNpcActionTagSegments(tag: String) -> array<String> {
    let empty: array<String>;
    if !AiNpcActionTagIsWellFormed(tag) {
        return empty;
    }

    let open = AiNpcActionTagOpen();
    let body = StrLeft(StrRight(tag, StrLen(tag) - StrLen(open)), StrLen(tag) - StrLen(open) - 1);
    return StrSplit(body, ":");
}
