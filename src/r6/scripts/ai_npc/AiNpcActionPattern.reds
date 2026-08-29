// The grammar of a command declaration: "[ACTION:TRICK:{place}:{hour}:{price}]".
//
// One pattern is BOTH halves of a command. The model reads it, and the dispatcher matches
// against it. That is the whole point of the file: announcing a command nobody implements and
// implementing one nobody announced were two independent mistakes for as long as the two
// halves were written in two places, and both were made -- see docs/PLAN_ACTION_LANE.md, D2.
// Here they cannot be, because there is only one thing to write.
//
// A slot occupies a whole colon-separated segment. That is a restriction and it buys the
// arity: a tag with the wrong number of fields is recognised as a fumbled command rather than
// handed to a consumer to index out of bounds. A value carrying a colon cannot be expressed;
// nothing in either mod needs one, and inventing an escape for a case that does not exist
// would be a grammar nobody can read.
//
// A TRAILING slot may be optional -- "{days?}" -- and that is not a convenience. A model asked
// for five fields writes three when only three were agreed, and a rendezvous that carried a
// day and a protection clause only when they came up is a real command in ai_npc_joytoys, not
// an imagined one. What optional does NOT do is weaken the guarantee: `params` always holds
// one entry per slot, and an absent optional is "" -- the same "unspecified" the consumer
// already has to handle, rather than a shorter array to measure.
//
// Optional slots may only follow other optional slots. A hole in the middle is unreadable
// both ways: the model cannot know which field it skipped, and the match cannot know either.
//
// PURE: no game API, no state, no config.
module AiNpc

/// The declaration ///

public class AiNpcActionPattern {
    public let raw: String;

    // The verb -- "TRICK". The command's name, and the half of its identity a mod does not
    // choose twice: the full id is "<modId>:<verb>".
    public let verb: String;

    // Everything up to the first slot, which is what a live tag is recognised by. Ends with a
    // colon when there are slots, and is the whole tag when there are none.
    public let head: String;

    // The pattern's segments, verb included: a literal to match, or "{name}" to capture.
    public let segments: array<String>;

    // Every slot, optional ones included: `params` is always this long.
    public let arity: Int32;

    // How many the model has to write. Below this a tag is a fumble; between the two it is a
    // command that said only what was agreed.
    public let required: Int32;

    public func IsExact() -> Bool {
        return Equals(this.arity, 0);
    }
}

/// Reading one ///

func AiNpcSlotIsSlot(segment: String) -> Bool {
    return StrBeginsWith(segment, "{")
        && StrEndsWith(segment, "}")
        && StrLen(segment) > 2;
}

func AiNpcSlotIsOptional(segment: String) -> Bool {
    return AiNpcSlotIsSlot(segment) && StrEndsWith(segment, "?}");
}

// The slot as a parameter is named: "{days?}" and "{days}" are one thing asked for twice, so a
// declaration defines it once and the optional mark stays where it belongs -- in the pattern,
// which is the half that says what the model may leave out.
func AiNpcSlotName(segment: String) -> String {
    if !AiNpcSlotIsSlot(segment) {
        return "";
    }
    if AiNpcSlotIsOptional(segment) {
        return StrLeft(segment, StrLen(segment) - 2) + "}";
    }
    return segment;
}

// Do the definitions cover the pattern, and does the pattern use them all?
//
// Both directions matter and they fail differently. A slot with no definition hands the model
// a name nobody explained -- it reads "{venue}" and invents what it means. A definition no
// slot cites is text occupying the prompt to teach a word that never appears. Neither shows up
// as an error at run time: the first produces a plausible wrong tag, the second produces a
// slightly longer prompt, and both are the kind of thing that is only ever found by looking.
func AiNpcActionParamsRefusal(pattern: ref<AiNpcActionPattern>,
                                     parameters: array<ref<AiNpcActionParam>>) -> String {
    if !IsDefined(pattern) {
        return "";
    }

    let defined: array<String>;
    let i = 0;
    while i < ArraySize(parameters) {
        let param = parameters[i];
        if !IsDefined(param) || Equals(StrLen(param.name), 0) {
            return "a parameter with no name";
        }
        if !AiNpcSlotIsSlot(param.name) {
            return "\"" + param.name + "\" is not a slot -- a parameter is named as the pattern "
                + "writes it, braces included";
        }
        if Equals(StrLen(param.text), 0) {
            return "parameter " + param.name + " has no definition";
        }
        if ArrayContains(defined, param.name) {
            return "parameter " + param.name + " is defined twice";
        }
        ArrayPush(defined, param.name);
        i += 1;
    }

    let cited: array<String>;
    i = 0;
    while i < ArraySize(pattern.segments) {
        let name = AiNpcSlotName(pattern.segments[i]);
        if NotEquals(StrLen(name), 0) {
            ArrayPush(cited, name);
        }
        i += 1;
    }

    i = 0;
    while i < ArraySize(defined) {
        if !ArrayContains(cited, defined[i]) {
            return "parameter " + defined[i] + " is defined but never used by " + pattern.raw;
        }
        i += 1;
    }
    return "";
}

// The pattern, or null with the reason in `refusal`.
//
// Every refusal here is a declaration a mod could not have meant, and each one is a command
// that would otherwise be advertised to a model and then honoured by nobody. Refusing at
// registration puts the mistake in front of its author; the alternative puts a bracket in
// front of the player.
func AiNpcParseActionPattern(raw: String, out refusal: String) -> ref<AiNpcActionPattern> {
    refusal = "";

    if !AiNpcActionTagIsWellFormed(raw) {
        refusal = "not shaped like [ACTION:NAME] -- it must open with \"" + AiNpcActionTagOpen()
            + "\", close with \"]\", and contain no space";
        return null;
    }

    let segments = AiNpcActionTagSegments(raw);
    let count = ArraySize(segments);
    if count < 1 || Equals(StrLen(segments[0]), 0) {
        refusal = "has no verb";
        return null;
    }
    if AiNpcSlotIsSlot(segments[0]) {
        refusal = "puts a slot where the verb belongs; the verb names the command and cannot vary";
        return null;
    }

    let pattern = new AiNpcActionPattern();
    pattern.raw = raw;
    pattern.verb = segments[0];
    pattern.segments = segments;
    pattern.arity = 0;
    pattern.required = 0;

    // The head is read in the same walk that counts the slots: it is exactly the literal run
    // before the first of them.
    let head = AiNpcActionTagOpen();
    let headClosed = false;
    let optionalSeen = false;
    let i = 0;
    while i < count {
        let segment = segments[i];
        if AiNpcSlotIsSlot(segment) {
            pattern.arity += 1;
            headClosed = true;
            if AiNpcSlotIsOptional(segment) {
                optionalSeen = true;
            } else {
                if optionalSeen {
                    refusal = "puts a required field after an optional one; a model that skipped "
                        + "the optional cannot say which field it skipped, and neither can the match";
                    return null;
                }
                pattern.required += 1;
            }
        } else {
            if Equals(StrLen(segment), 0) {
                refusal = "has an empty segment; a literal between two colons cannot match anything";
                return null;
            }
            if !headClosed {
                if i > 0 {
                    head += ":";
                }
                head += segment;
            }
        }
        i += 1;
    }

    if pattern.arity > 0 {
        pattern.head = head + ":";
    } else {
        pattern.head = raw;
    }
    return pattern;
}

/// Matching a live tag ///

// Two answers, and keeping them apart is what lets a fumbled command be told from an unknown
// one.
//
// `headMatched` means the command exists -- the model reached for something real. `complete`
// adds that the fields are there. A tag that matched the head and nothing else is a command
// worth repairing; a tag that matched no head at all is a command nobody declared, and the
// load report already says so.
public class AiNpcPatternMatch {
    public let headMatched: Bool;
    public let complete: Bool;
    public let params: array<String>;
}

func AiNpcMatchActionPattern(pattern: ref<AiNpcActionPattern>, tag: String) -> ref<AiNpcPatternMatch> {
    let match = new AiNpcPatternMatch();
    match.headMatched = false;
    match.complete = false;

    if !IsDefined(pattern) || !AiNpcActionTagIsWellFormed(tag) {
        return match;
    }

    if pattern.IsExact() {
        match.headMatched = Equals(tag, pattern.raw);
        match.complete = match.headMatched;
        return match;
    }

    if !StrBeginsWith(tag, pattern.head) {
        return match;
    }
    match.headMatched = true;

    let actual = AiNpcActionTagSegments(tag);
    let expected = pattern.segments;
    let count = ArraySize(expected);
    let written = ArraySize(actual);

    // The window an optional tail opens. Outside it the tag says too little to run or more
    // than the command has room for, and either way it is a fumble rather than a command.
    let least = count - (pattern.arity - pattern.required);
    if written > count || written < least {
        return match;
    }

    let params: array<String>;
    let i = 0;
    while i < count {
        let segment = expected[i];
        if AiNpcSlotIsSlot(segment) {
            if i >= written {
                // An optional the model did not write. "" is the answer, not a shorter array:
                // the consumer already has to read "unspecified" and now reads it in one place.
                ArrayPush(params, "");
            } else {
                // An empty REQUIRED field is a fumble, not a value: "[ACTION:TRICK::2300:200]"
                // is the model dropping a field, and a consumer handed "" for something it was
                // promised would have to invent what was meant. Read after cleaning, so a
                // field holding only decoration is the dropped field it is.
                let value = AiNpcCleanSlotValue(actual[i]);
                if Equals(StrLen(value), 0) && !AiNpcSlotIsOptional(segment) {
                    return match;
                }
                ArrayPush(params, value);
            }
        } else {
            if i >= written || NotEquals(actual[i], segment) {
                return match;
            }
        }
        i += 1;
    }

    match.complete = true;
    match.params = params;
    return match;
}

/// What the model reads ///

// One line of the command block. The pattern verbatim, so what the model is shown and what the
// dispatcher matches are the same string rather than two that have to be kept in step.
func AiNpcActionPatternLine(pattern: ref<AiNpcActionPattern>, prompt: String) -> String {
    if !IsDefined(pattern) {
        return "";
    }
    return pattern.raw + ": " + prompt;
}
