# -*- coding: utf-8 -*-
"""The conversation as the model receives it. Mirrors AiNpcHistory.reds.

The transcript is the user message: every stored line as "V: ..." or "<name>: ...", the gap
markers that measure silence between them, and the handover token that hands the turn to the
character mid-sentence.

WHY THIS IS MIRRORED AND NOT EXTRACTED. Everything here is arithmetic on a clock -- when a
gap is worth a marker, how a duration is worded, how an hour is printed. There is no authored
text in it beyond a handful of words ("moments", "a day", "later"), and arithmetic cannot be
read out of literals. It is pinned instead by the round trip in verify.py: a captured prompt
carries real markers, and a mirror that words a duration differently fails there.

The one thing that is NOT arithmetic -- the handover token -- is read from the corpus, since
a byte of difference there changes what the model is being asked to continue.
"""


def trim_leading_blanks(text):
    return text.lstrip(" \t\r\n")


def collapse_spaces(text):
    while "  " in text:
        text = text.replace("  ", " ")
    return text


def transcript_line(text):
    """One stored message, flattened onto a single line.

    The flattening is a guard, not cosmetics: a newline inside a message could otherwise
    open a line that reads as "V: ..." and forge a turn into the transcript.
    """
    flat = text.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
    return collapse_spaces(flat)


def format_duration(seconds):
    if seconds < 60:
        return "moments"
    if seconds < 3600:
        minutes = seconds // 60
        return "a minute" if minutes == 1 else "%d minutes" % minutes
    if seconds < 86400:
        hours = seconds // 3600
        return "an hour" if hours == 1 else "%d hours" % hours
    days = seconds // 86400
    return "a day" if days == 1 else "%d days" % days


def clock_label(game_time_seconds):
    minutes_of_day = (game_time_seconds // 60) % 1440
    hours = minutes_of_day // 60
    minutes = minutes_of_day % 60
    suffix = "pm" if hours >= 12 else "am"
    if hours > 12:
        hours -= 12
    if hours == 0:
        hours = 12
    return "%d:%02d%s" % (hours, minutes, suffix)


def format_elapsed(from_seconds, now_seconds):
    if from_seconds == TIME_UNKNOWN or now_seconds == TIME_UNKNOWN:
        return ""
    elapsed = now_seconds - from_seconds
    if elapsed < 0:
        return ""
    return format_duration(elapsed) + " ago"


TIME_UNKNOWN = 0
GAP_MIN_SECONDS = 1800        # 30 in-game minutes
GAP_CLOCK_SECONDS = 21600     # 6 in-game hours


def gap_marker(from_seconds, now_seconds):
    if from_seconds == TIME_UNKNOWN or now_seconds == TIME_UNKNOWN:
        return ""
    gap = now_seconds - from_seconds
    if gap < GAP_MIN_SECONDS:
        return ""
    if gap < GAP_CLOCK_SECONDS:
        return "(%s later)" % format_duration(gap)
    clock = clock_label(now_seconds)
    if gap < 86400:
        return "(%s later, %s)" % (format_duration(gap), clock)
    days = (now_seconds // 86400) - (from_seconds // 86400)
    if days <= 1:
        return "(the next day, %s)" % clock
    return "(%d days later, %s)" % (days, clock)


def trim(messages, max_turns):
    """AiNpcHistoryTrim: the last N turns, widened back onto the message a reply answers."""
    if max_turns <= 0:
        return []
    size = len(messages)
    start = 0
    if size > max_turns * 2:
        start = size - max_turns * 2
        if not messages[start]["fromPlayer"]:
            start -= 1
    return messages[start:]


def history(messages, npc_name, now_seconds):
    """Every stored message, with the markers between them and the trailing one."""
    out = []
    previous = TIME_UNKNOWN
    for message in messages:
        marker = gap_marker(previous, message["at"])
        if marker:
            out.append(marker + "\n")
        speaker = "V" if message["fromPlayer"] else npc_name
        out.append("%s: %s\n" % (speaker, transcript_line(message["text"])))
        if message["at"] != TIME_UNKNOWN:
            previous = message["at"]
    trailing = gap_marker(previous, now_seconds)
    if trailing:
        out.append(trailing + "\n")
    return "".join(out)
