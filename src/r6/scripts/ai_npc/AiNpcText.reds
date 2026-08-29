// Small pure string helpers.
//
// PURE: no game API, no state, no config -- guarded by tools/lint.ps1, which fails the build
// if a game dependency appears here.
module AiNpc

/// Small string utilities ///

// Blanks off both ends.
//
// AiNpcTrimLeadingBlanks does the front alone, because that is the end a stored message is
// judged on: what is in front of the first word decides whether a bubble looks empty. Cutting
// a span out of the MIDDLE of a reply is the case that needs both -- remove the last thing in
// the text and the space that separated it stays behind.
func AiNpcTrimBothEnds(text: String) -> String {
    let result = text;
    while StrEndsWith(result, "\n") || StrEndsWith(result, " ") || StrEndsWith(result, "\r") || StrEndsWith(result, "\t") {
        result = StrLeft(result, StrLen(result) - 1);
    }
    return AiNpcTrimLeadingBlanks(result);
}

func AiNpcJoinStrings(items: array<String>, separator: String) -> String {
    let result = "";
    let i = 0;
    let count = ArraySize(items);
    while i < count {
        if i > 0 {
            result += separator;
        }
        result += items[i];
        i += 1;
    }
    return result;
}

// Insertion sort. The input is a handful of file names, so the simplest correct thing
// wins; what matters is only that the order is total and reproducible.
func AiNpcSortStrings(items: array<String>) -> array<String> {
    let result = items;
    let count = ArraySize(result);
    let i = 1;
    while i < count {
        let current = result[i];
        let j = i - 1;
        while j >= 0 && UnicodeStringCompare(result[j], current) > 0 {
            result[j + 1] = result[j];
            j -= 1;
        }
        result[j + 1] = current;
        i += 1;
    }
    return result;
}

// Runs of spaces collapsed to one. What is left after a tag is cut out of the middle of a
// sentence: the words either side of it kept their separators, and the reader would see the
// gap where the command used to be.
func AiNpcCollapseSpaces(text: String) -> String {
    let result = text;
    while StrContains(result, "  ") {
        result = StrReplace(result, "  ", " ");
    }
    return result;
}

// The same gap, one axis up. A command is written on a line of its own -- that is what the
// command block asks for -- so cutting it out leaves the two newlines that framed it back to
// back with the ones already there, and the reader gets a hole two or three lines deep in the
// middle of a message.
//
// Down to two and no further: two newlines are a paragraph the model wrote, and a pass that
// flattened them would rewrite prose rather than clean up after itself.
func AiNpcCollapseBlankLines(text: String) -> String {
    let result = AiNpcReplaceAll(AiNpcReplaceAll(text, "\r\n", "\n"), "\r", "\n");

    // The space a removed tag leaves on its own line makes the run look like text. Taken out
    // first, or "\n \n\n" survives every pass below by not being a run at all.
    while StrContains(result, "\n \n") {
        result = StrReplace(result, "\n \n", "\n\n");
    }
    while StrContains(result, "\n\n\n") {
        result = StrReplace(result, "\n\n\n", "\n\n");
    }
    return result;
}

func AiNpcIsDigits(text: String) -> Bool {
    let count = StrLen(text);
    if count <= 0 {
        return false;
    }

    let i = 0;
    while i < count {
        let c = StrMid(text, i, 1);
        if StrFindFirst("0123456789", c) < 0 {
            return false;
        }
        i += 1;
    }
    return true;
}

// Where `needle` sits in `items`, or -1. The generic half of AiNpcIdIndexOf, which reads as a
// question about identities and is asked about command heads too.
func AiNpcIndexOfString(items: array<String>, needle: String) -> Int32 {
    let i = 0;
    let count = ArraySize(items);
    while i < count {
        if Equals(items[i], needle) {
            return i;
        }
        i += 1;
    }
    return -1;
}
