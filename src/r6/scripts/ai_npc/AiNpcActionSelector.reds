// The second message of the action pass, and how its answer is read.
//
// PURE: no game API, no state, no config -- the same two halves the repair pass keeps apart,
// for the same reason. What decides whether this pass runs at all is AiNpcActionService.
//
// WHAT THIS PROMPT DOES NOT CARRY, and it is the whole point: no world, no character sheet, no
// explicitness tier, no form rubrics. None of them decides whether money changed hands. What
// is left is the command table, the last few messages, and the reply that was just written --
// about a twentieth of a conversation prompt, and an instruction to act that no longer
// competes with five thousand tokens of setting.
//
// The reply is quoted as the character's own line, ending the thread rather than handing it
// over: AiNpcTranscriptHandover asks a model to CONTINUE writing, and this one is asked to
// read what was written. A selector that ended on "Judy Alvarez: " would answer with dialogue.

module AiNpc

// Enough to see what was agreed and not enough to re-play the conversation. The plan's figure,
// and it is a budget as much as a window: this request runs once per reply, so what it carries
// is paid on every message.
func AiNpcActionSelectorWindow() -> Int32 {
    return 6;
}

// The word for "nothing happened", which is the answer most turns deserve. Written out because
// the reader below and the prompt have to agree on it, and a model that answers with an empty
// line is indistinguishable from one that failed.
func AiNpcActionSelectorNone() -> String {
    return "NONE";
}

func AiNpcActionSelectorAsk(transcript: String, npcName: String, reply: String) -> String {
    return transcript + npcName + ": " + AiNpcTranscriptLine(reply) + "\n\n"
        + "Read the last message only. If it carries out one of the commands above, write that "
        + "command alone, on one line, with no other text. If it does not, write "
        + AiNpcActionSelectorNone() + ".";
}

/// Reading the answer ///

// A tag, or "" for nothing to do.
//
// Tolerant on ONE axis and strict everywhere else: a model answering the bare verb form
// without its brackets is answering correctly in the wrong dress, and it is what most of them
// did on the probe -- 15 answers out of 20. The brackets are punctuation this mod invented so
// a command could be found inside prose; here there is no prose to find it in. Everything past
// that goes through AiNpcFindActionTags like any other tag, so a selector cannot invent a
// command shape the dispatcher does not know.
func AiNpcActionSelectorTag(answer: String) -> String {
    let text = AiNpcCollapseSpaces(AiNpcTranscriptLine(answer));
    if Equals(StrLen(text), 0) {
        return "";
    }

    let bracketed = AiNpcFirstActionTag(text);
    if NotEquals(StrLen(bracketed), 0) {
        return AiNpcActionSelectorRefusal(bracketed) ? "" : bracketed;
    }

    // No brackets: take the run of characters that starts at the verb marker and ends at the
    // first space, which is exactly what a well-formed tag may contain.
    let marker = "ACTION:";
    let start = StrFindFirst(text, marker);
    if start < 0 {
        return "";
    }
    let rest = StrRight(text, StrLen(text) - start);
    let end = StrFindFirst(rest, " ");
    if end >= 0 {
        rest = StrLeft(rest, end);
    }

    let tag = "[" + rest + "]";
    if !AiNpcActionTagIsWellFormed(tag) {
        return "";
    }
    return AiNpcActionSelectorRefusal(tag) ? "" : tag;
}

// "Nothing happened" is an answer, and the prompt asks for it by name -- so NONE arrives in
// every dress the commands do: bare, as ACTION:NONE, bracketed. All of them mean the same thing
// as an empty answer, and none of them is a command that failed: dispatching one would log a
// verb naming nothing while the model did exactly as it was told.
func AiNpcActionSelectorRefusal(tag: String) -> Bool {
    let segments = AiNpcActionTagSegments(tag);
    if Equals(ArraySize(segments), 0) {
        return true;
    }
    return Equals(StrUpper(segments[0]), AiNpcActionSelectorNone());
}
