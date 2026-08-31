// One ordered list of messages, each tagged with its author. It replaces two parallel arrays
// persisted as "|"-joined strings, whose three failure modes this model cannot express: the
// arrays were trimmed independently, so message N of V ended up paired with an older reply;
// any "|" typed or generated split one message into two; and a missing separator on one path
// merged two replies into one entry.
//
// Every function here is pure, which is what makes them directly testable.
//
// The record itself is api\AiNpcMessage.reds: a consumer reads the fields of what
// AiNpcReadConversation hands back, so the type is contract and the operations over it are
// not.

module AiNpc

func AiNpcMessageNew(text: String, fromPlayer: Bool) -> ref<AiNpcMessage> {
    return AiNpcMessageNewAt(text, fromPlayer, AiNpcTimeUnknown());
}

func AiNpcMessageNewAt(text: String, fromPlayer: Bool, gameTimeSeconds: Int32,
                       opt channel: AiNpcChannelId) -> ref<AiNpcMessage> {
    let message = new AiNpcMessage();
    message.text = text;
    message.fromPlayer = fromPlayer;
    message.gameTimeSeconds = gameTimeSeconds;
    message.channel = channel;
    return message;
}

// Named rather than written as 0 in a dozen places, because the point is that it is not a
// time.
func AiNpcTimeUnknown() -> Int32 {
    return 0;
}

func AiNpcMessageHasTime(message: ref<AiNpcMessage>) -> Bool {
    return IsDefined(message) && NotEquals(message.gameTimeSeconds, AiNpcTimeUnknown());
}

// A constant rather than a literal, so the transcript and the UI cannot disagree about what
// to hide.
func AiNpcSystemEventMarker() -> String {
    return "!?";
}

// Models routinely prefix replies with newlines or spaces; strip them before storing so
// the same text always compares equal and renders identically.
func AiNpcTrimLeadingBlanks(text: String) -> String {
    let result = text;
    while StrBeginsWith(result, "\n") || StrBeginsWith(result, " ") || StrBeginsWith(result, "\r") || StrBeginsWith(result, "\t") {
        result = StrRight(result, StrLen(result) - 1);
    }
    return result;
}

// Both ends. A model's own reply rarely needs it -- the leading trim above is what a stored
// message wants -- but a reply we have CUT a command out of does: the command sits last and on
// its own line, so removing it hands the player a bubble padded with the blank lines that used
// to frame it.
func AiNpcTrimBlanks(text: String) -> String {
    let result = AiNpcTrimLeadingBlanks(text);
    while StrEndsWith(result, "\n") || StrEndsWith(result, " ") || StrEndsWith(result, "\r") || StrEndsWith(result, "\t") {
        result = StrLeft(result, StrLen(result) - 1);
    }
    return result;
}

// One message as exactly one line. The transcript's grammar is "one line, one speaker", and
// the stop sequences, response extraction and the summariser all lean on it -- but a stored
// message may contain newlines, and every line after the first reached the prompt with no name
// in front of it, free to read as the other speaker.
//
// Flattened rather than repeating the label per line: the label belongs to the message, and a
// name repeated mid-reply teaches the roleplay lane to write its own.
func AiNpcTranscriptLine(text: String) -> String {
    let flat = AiNpcReplaceAll(AiNpcReplaceAll(AiNpcReplaceAll(text, "\r\n", " "), "\n", " "), "\r", " ");
    return AiNpcCollapseSpaces(flat);
}

// One line of a message for a listing: newlines flattened, clipped so a long reply cannot push
// a table's columns apart.
public func AiNpcClipText(text: String, maxLength: Int32) -> String {
    let flat = AiNpcReplaceAll(AiNpcReplaceAll(text, "\r\n", " "), "\n", " ");
    if maxLength <= 0 || StrLen(flat) <= maxLength {
        return flat;
    }
    return StrLeft(flat, maxLength) + "...";
}

func AiNpcHistoryAppend(messages: array<ref<AiNpcMessage>>, text: String, fromPlayer: Bool) -> array<ref<AiNpcMessage>> {
    return AiNpcHistoryAppendAt(messages, text, fromPlayer, AiNpcTimeUnknown());
}

func AiNpcHistoryAppendAt(messages: array<ref<AiNpcMessage>>, text: String, fromPlayer: Bool,
                          gameTimeSeconds: Int32, opt channel: AiNpcChannelId) -> array<ref<AiNpcMessage>> {
    let result = AiNpcHistoryCopy(messages);
    ArrayPush(result, AiNpcMessageNewAt(AiNpcTrimLeadingBlanks(text), fromPlayer, gameTimeSeconds,
        channel));
    return result;
}

// Keeps the last `maxTurns` exchanges -- 2*maxTurns messages -- but never opens the window on
// a reply, which would orphan it from the message it answers. It widens backwards by one
// instead, so the effective bound is 2*maxTurns+1: narrowing forwards would drop the question
// too, costing a full turn of context on every trim.
//
// The widening applies only when the window moved, and never to enforce "a history starts with
// V": a conversation can open with the character -- every seeded message does -- and dropping
// the first message when there is nothing to back up to windows such a history down to
// nothing. Nothing downstream needs that invariant, since authorship is read per message.
func AiNpcHistoryTrim(messages: array<ref<AiNpcMessage>>, maxTurns: Int32) -> array<ref<AiNpcMessage>> {
    let result: array<ref<AiNpcMessage>>;
    if maxTurns <= 0 {
        return result;
    }

    let size = ArraySize(messages);
    let start = 0;
    if size > maxTurns * 2 {
        start = size - maxTurns * 2;
        // start >= 1 here, so backing up one is always in range.
        if !messages[start].fromPlayer {
            start -= 1;      // widen back onto the message this reply answers
        }
    }

    let i = start;
    while i < size {
        ArrayPush(result, messages[i]);
        i += 1;
    }
    return result;
}

// Drops the last exchange: the trailing reply if there is one, then the message it answered.
func AiNpcHistoryUndo(messages: array<ref<AiNpcMessage>>) -> array<ref<AiNpcMessage>> {
    let keep = ArraySize(messages);

    if keep > 0 && !messages[keep - 1].fromPlayer {
        keep -= 1;
    }
    if keep > 0 && messages[keep - 1].fromPlayer {
        keep -= 1;
    }

    let result: array<ref<AiNpcMessage>>;
    let i = 0;
    while i < keep {
        ArrayPush(result, messages[i]);
        i += 1;
    }
    return result;
}

// True when V spoke last and the character still owes a reply.
func AiNpcHistoryHasPendingReply(messages: array<ref<AiNpcMessage>>) -> Bool {
    let size = ArraySize(messages);
    if size == 0 {
        return false;
    }
    return messages[size - 1].fromPlayer;
}

// The most recent message that carries one, scanned backwards so a history predating the
// field answers unknown instead of the time of some arbitrary later write.
func AiNpcHistoryLastTime(messages: array<ref<AiNpcMessage>>) -> Int32 {
    let i = ArraySize(messages) - 1;
    while i >= 0 {
        if AiNpcMessageHasTime(messages[i]) {
            return messages[i].gameTimeSeconds;
        }
        i -= 1;
    }
    return AiNpcTimeUnknown();
}

// A duration in words, with no "ago"/"later" framing so the callers add their own. The largest
// unit alone, never "2 hours 13 minutes": a model reads both the same way and the second costs
// more tokens on every marker. It stops at days, since "9 days" stays readable where "216
// hours" does not.
func AiNpcFormatDuration(seconds: Int32) -> String {
    if seconds < 60 {
        return "moments";
    }
    if seconds < 3600 {
        let minutes = seconds / 60;
        if Equals(minutes, 1) {
            return "a minute";
        }
        return s"\(minutes) minutes";
    }
    if seconds < 86400 {
        let hours = seconds / 3600;
        if Equals(hours, 1) {
            return "an hour";
        }
        return s"\(hours) hours";
    }
    let days = seconds / 86400;
    if Equals(days, 1) {
        return "a day";
    }
    return s"\(days) days";
}

// The wall clock of an absolute in-game timestamp. Integer arithmetic on the stored seconds
// rather than GameTime.Hours()/Minutes(), so it is assertable without a session and can format
// a past message's time, which the game API cannot do at all.
func AiNpcClockLabel(gameTimeSeconds: Int32) -> String {
    let minutesOfDay = (gameTimeSeconds / 60) % 1440;
    if minutesOfDay < 0 {
        minutesOfDay += 1440;
    }

    let hours = minutesOfDay / 60;
    let minutes = minutesOfDay % 60;

    let suffix = "am";
    if hours >= 12 {
        suffix = "pm";
    }
    if hours > 12 {
        hours -= 12;
    }
    // Midnight and noon are 12, not 0: "0:05am" is not a time anybody writes.
    if Equals(hours, 0) {
        hours = 12;
    }

    // Zero-padded, because "3:5pm" reads as a typo and invites the model to copy it.
    let padded = s"\(minutes)";
    if minutes < 10 {
        padded = s"0\(minutes)";
    }
    return s"\(hours):\(padded)\(suffix)";
}

// How long the character was left waiting. Empty when the question cannot be answered -- no
// stored time, or a clock that moved backwards after an earlier save was reloaded -- which is
// the caller's cue to say nothing: a wrong gap is worse than no gap.
func AiNpcFormatElapsedGameTime(fromSeconds: Int32, nowSeconds: Int32) -> String {
    if Equals(fromSeconds, AiNpcTimeUnknown()) || Equals(nowSeconds, AiNpcTimeUnknown()) {
        return "";
    }
    let elapsed = nowSeconds - fromSeconds;
    if elapsed < 0 {
        return "";
    }
    return AiNpcFormatDuration(elapsed) + " ago";
}

/// Gap markers ///

// Below this, no marker: the messages belong to one continuous exchange. Set above the rhythm
// of an actual conversation -- an hour of chat at a message every ten minutes is one scene.
func AiNpcGapMarkerMinSeconds() -> Int32 {
    return 1800;   // 30 in-game minutes
}

// Above this the duration alone stops being enough: "6 hours later" leaves the character
// guessing whether it is still the same evening, and the clock answers in three tokens.
func AiNpcGapMarkerClockSeconds() -> Int32 {
    return 21600;  // 6 in-game hours
}

// The line inserted between two messages, or "" when the break is not worth one. Four tiers,
// because one format cannot serve every scale:
//
//   under 30 min      nothing -- same conversation
//   30 min .. 6 h     "(2 hours later)"           relative is what carries meaning
//   6 h .. 24 h       "(9 hours later, 7:12am)"   which part of the day matters now
//   over 24 h         "(3 days later, 7:12am)"    "72 hours later" is not readable
//
// Past a day the count comes from the calendar, not the raw gap: a message at 11pm answered at
// 1am two nights later is "2 days later", where the gap alone rounds to one.
func AiNpcHistoryGapMarker(fromSeconds: Int32, nowSeconds: Int32) -> String {
    if Equals(fromSeconds, AiNpcTimeUnknown()) || Equals(nowSeconds, AiNpcTimeUnknown()) {
        return "";
    }
    let gap = nowSeconds - fromSeconds;
    if gap < AiNpcGapMarkerMinSeconds() {
        return "";     // also covers a clock that moved backwards
    }

    if gap < AiNpcGapMarkerClockSeconds() {
        return s"(\(AiNpcFormatDuration(gap)) later)";
    }

    let clock = AiNpcClockLabel(nowSeconds);
    if gap < 86400 {
        return s"(\(AiNpcFormatDuration(gap)) later, \(clock))";
    }

    let days = (nowSeconds / 86400) - (fromSeconds / 86400);
    if days <= 1 {
        return s"(the next day, \(clock))";
    }
    return s"(\(days) days later, \(clock))";
}

// Authorship comes from each message, so a pending exchange ends after V's line instead of
// shifting the pairing. Untimed: every gap marker is suppressed, so a history written before
// timestamps renders byte for byte as it always did.
func AiNpcHistoryTranscript(messages: array<ref<AiNpcMessage>>, npcName: String) -> String {
    return AiNpcHistoryTranscriptAt(messages, npcName, AiNpcTimeUnknown());
}

// Same, with the breaks in time made visible. `nowSeconds` is the clock at the moment the
// prompt is built, and it earns the last marker: the silence between the final stored message
// and the line V is about to send, which is the one the character most needs. Pass
// AiNpcTimeUnknown() to render no trailing marker.
//
// Markers sit on their own line, in parentheses, and never touch the "V: " / "<name>: " grammar
// the stop sequences rely on. Neither can a message: AiNpcTranscriptLine flattens its
// newlines, so every line of the result carries a name.
//
// `previous` advances only across messages that carry a time, so an untimed one in the middle
// does not break the chain and the next timed message still measures from the last real
// timestamp.
func AiNpcHistoryTranscriptAt(messages: array<ref<AiNpcMessage>>, npcName: String, nowSeconds: Int32) -> String {
    let result = "";
    let previous = AiNpcTimeUnknown();

    let i = 0;
    while i < ArraySize(messages) {
        let marker = AiNpcHistoryGapMarker(previous, messages[i].gameTimeSeconds);
        if NotEquals(StrLen(marker), 0) {
            result += marker + "\n";
        }

        if messages[i].fromPlayer {
            result += "V: " + AiNpcTranscriptLine(messages[i].text) + "\n";
        } else {
            result += npcName + ": " + AiNpcTranscriptLine(messages[i].text) + "\n";
        }

        if AiNpcMessageHasTime(messages[i]) {
            previous = messages[i].gameTimeSeconds;
        }
        i += 1;
    }

    let trailing = AiNpcHistoryGapMarker(previous, nowSeconds);
    if NotEquals(StrLen(trailing), 0) {
        result += trailing + "\n";
    }
    return result;
}

func AiNpcHistoryCopy(messages: array<ref<AiNpcMessage>>) -> array<ref<AiNpcMessage>> {
    let result: array<ref<AiNpcMessage>>;
    let i = 0;
    while i < ArraySize(messages) {
        ArrayPush(result, messages[i]);
        i += 1;
    }
    return result;
}

/// Legacy migration ///

// Splits a legacy "a|b|c|" field. Trailing separators produce empties and are dropped;
// interior empties are kept positionally and filtered by the caller, since an empty reply
// meant "awaiting generation" and its slot still pairs with a message of V's.
func AiNpcSplitLegacyField(raw: String) -> array<String> {
    let result: array<String>;
    if Equals(StrLen(raw), 0) {
        return result;
    }

    let parts = StrSplit(raw, "|");
    let lastMeaningful = -1;
    let i = 0;
    while i < ArraySize(parts) {
        if NotEquals(StrLen(parts[i]), 0) {
            lastMeaningful = i;
        }
        i += 1;
    }

    i = 0;
    while i <= lastMeaningful {
        ArrayPush(result, parts[i]);
        i += 1;
    }
    return result;
}

// Rebuilds an ordered history from the two-field format. Empty replies and the "!?" system
// marker are dropped. Reached only by a save written before the journal existed.
func AiNpcHistoryFromLegacy(vMessagesRaw: String, npcResponsesRaw: String) -> array<ref<AiNpcMessage>> {
    let playerParts = AiNpcSplitLegacyField(vMessagesRaw);
    let npcParts = AiNpcSplitLegacyField(npcResponsesRaw);

    let count = ArraySize(playerParts);
    if ArraySize(npcParts) > count {
        count = ArraySize(npcParts);
    }

    let result: array<ref<AiNpcMessage>>;
    let i = 0;
    while i < count {
        if i < ArraySize(playerParts) && NotEquals(playerParts[i], AiNpcSystemEventMarker()) && NotEquals(StrLen(playerParts[i]), 0) {
            ArrayPush(result, AiNpcMessageNew(AiNpcTrimLeadingBlanks(playerParts[i]), true));
        }
        if i < ArraySize(npcParts) && NotEquals(StrLen(npcParts[i]), 0) {
            ArrayPush(result, AiNpcMessageNew(AiNpcTrimLeadingBlanks(npcParts[i]), false));
        }
        i += 1;
    }
    return result;
}
