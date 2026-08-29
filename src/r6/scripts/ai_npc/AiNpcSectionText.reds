// What another mod is allowed to put in the prompt.
//
// The prompt is a tree of tags this mod writes. Text from anywhere else -- a provider, a JSON
// file, an extension, a fact watch -- is a leaf, and a leaf that carries a tag stops being
// one: measured, a "</character>" inside a character addition closes that block and lets what
// follows open a <system_rules> of its own, with its own LENGTH, in a position nobody
// intended. Every locked rule is worth exactly as much as this check.
//
// NOT a ban on the two characters. `<3` is in a shipped speech style, and "->" is in half the
// character sheets: refusing them would refuse the mod's own text and teach authors to work
// around the guard. What is refused is a TAG -- a closing one, or a name between angle
// brackets -- which is the only shape that changes the structure.
//
// Pure, so both halves of the check are assertable without a session.

module AiNpc

// Characters a tag name may hold. Anything else between the brackets makes it prose.
func AiNpcIsTagChar(c: String) -> Bool {
    return NotEquals(StrFindFirst("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_/|", c), -1);
}

func AiNpcTextLooksLikeMarkup(text: String) -> Bool {
    let length = StrLen(text);
    let i = 0;
    while i < length - 1 {
        if Equals(StrMid(text, i, 1), "<") {
            // A closing tag is a tag whatever follows it.
            if Equals(StrMid(text, i + 1, 1), "/") {
                return true;
            }

            let j = i + 1;
            let named = false;
            while j < length && AiNpcIsTagChar(StrMid(text, j, 1)) {
                named = true;
                j += 1;
            }
            if named && j < length && Equals(StrMid(text, j, 1), ">") {
                return true;
            }
        }
        i += 1;
    }
    return false;
}

// The bound on one replaceable section, and deliberately not the rubric number: a bio or a
// world background is a paragraph where a rubric is a line. Refused rather than clamped, like
// every other bound this mod states -- half a sentence in the prompt is worse than none.
func AiNpcSectionBudget() -> Int32 {
    return 4000;
}

// Why a section's text was refused, or "" when it stands. One answer for every door: the
// prompt builder, the config report and the registration calls.
func AiNpcSectionRefusal(text: String) -> String {
    if AiNpcTextLooksLikeMarkup(text) {
        return "carrying markup: a tag would close the block it sits in";
    }
    if StrLen(text) > AiNpcSectionBudget() {
        return s"longer than the \(AiNpcSectionBudget()) characters one section may spend";
    }
    return "";
}

// The text, or nothing plus a line saying whose it was. Every caller that reads text from
// outside this mod goes through here, so a refusal reads the same wherever it happened.
func AiNpcSafeSectionText(text: String, source: String) -> String {
    if Equals(StrLen(text), 0) {
        return "";
    }

    let refusal = AiNpcSectionRefusal(text);
    if NotEquals(StrLen(refusal), 0) {
        AiNpcLog(s"Text from '\(source)' refused: \(refusal).");
        return "";
    }
    return text;
}

// Two contributions to one block, and neither one invented. The newline is the whole of it:
// a bare concatenation would make the second read as the tail of the first claim.
func AiNpcJoinLines(first: String, second: String) -> String {
    if Equals(StrLen(second), 0) {
        return first;
    }
    if Equals(StrLen(first), 0) {
        return second;
    }
    return first + "
" + second;
}
