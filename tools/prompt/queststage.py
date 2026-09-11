# -*- coding: utf-8 -*-
"""What a character says about a quest, and WHEN it becomes true.

A quest is tracked from its first second to its last, so one account written for the whole of
it is mounted at the first message -- Takemura named Oda's refusal and Hanako's parade before
V had walked to the meeting. A sheet dates its stages instead, and the save decides which one
is read.

Mirrors AiNpcQuestTextIn in AiNpcConfigModel.reds: stages are declared in the order they
happen, and the last one whose fact is posed wins.
"""

STAGE_KEYS = ("sinceFact", "unlessFact", "text")


def quest_stages(entries):
    """The extracted entries as {questKey: [stage, ...]}, keeping declaration order."""
    out = {}
    for entry in entries:
        stage = {key: entry.get(key, "") for key in STAGE_KEYS}
        out.setdefault(entry["questKey"], []).append(stage)
    return out


def as_stages(value):
    """One sheet value in either form. A fixture may write a plain string for a quest whose
    account never changes, which is most of them."""
    if isinstance(value, str):
        return [{"sinceFact": "", "unlessFact": "", "text": value}]
    return [{key: stage.get(key, "") for key in STAGE_KEYS} for stage in value]


def holds(stage, posed):
    if not stage["sinceFact"] and not stage["unlessFact"]:
        return True
    if stage["sinceFact"] and stage["sinceFact"] not in posed:
        return False
    return not stage["unlessFact"] or stage["unlessFact"] not in posed


def quest_account(table, key, posed):
    """The account true right now, or "" -- the quest has nothing to say yet, or nothing at
    all. A dated stage never answers before its fact: that is the whole point of dating it."""
    if not key:
        return ""
    text = ""
    for stage in as_stages(table.get(key, [])):
        if holds(stage, posed):
            text = stage["text"]
    return text
