# -*- coding: utf-8 -*-
"""A fixture: one pre-recorded conversation, and the game state it happened in.

This is the input side of the whole tooling. Everything the prompt builder would have read
from a live session -- the clock, V's gender and life path, the tracked quest, the tone tier,
the reply language, whether the romance is on, what a third-party mod seeded into <now> --
is a field here. Nothing is guessed and nothing defaults to "whatever the machine has": a
fixture that does not say is a fixture that says the mod's own default, and two runs of the
same file a month apart produce the same bytes.

    {
      "name": "river-night-shift",
      "contact": "river_ward",
      "language": "French",
      "tone": "nsfw_hard",
      "romanced": true,
      "player": {"gender": "Female", "lifePath": "streetkid"},
      "quest": {"key": "the_hunt", "name": "The Hunt", "objective": "Trouver Randy"},
      "now": "2d 07:42",
      "messages": [
        {"from": "V", "text": "Je rentre", "at": "1d 23:10"},
        {"from": "npc", "text": "Texte-moi quand tu rentres vraiment.", "at": "1d 23:12"}
      ],
      "ask": "Je suis rentree cheri"
    }

Times are in-game: "HH:MM" on day zero, or "<n>d HH:MM" for a later day, or a plain number of
seconds. They are what the gap markers are computed from, so a fixture that wants to test a
three-day silence simply writes one.

An unknown key is an error rather than a shrug. A misspelled field that silently did nothing
would produce a prompt that looks right and tests something else.
"""

import io
import json
import os
import re

TIME_RE = re.compile(r"^(?:(\d+)d\s+)?(\d{1,2}):(\d{2})$")

TONES = ("normal", "nsfw", "nsfw_hard")
GENDERS = ("Male", "Female")
LANGUAGES = ("English", "Spanish", "French", "German", "Italian",
             "Portuguese", "Russian", "Ukraine")

PLAYER_KEYS = ("gender", "lifePath", "appearance", "description")

KEYS = (
    "name", "note", "contact", "language", "tone", "romanced", "postHeist",
    "romanceFailed", "randyDead",
    "evelynDead", "evelynRescued", "cloudsSettled", "leftNightCity",
    "johnnyRevealed", "johnnyDateDone", "confidedInV",
    "player", "quest", "now", "messages", "ask", "speaksFirst", "reason", "intent",
    "memory", "memoryEnabled", "pendingContext", "weather",
    "extensionContext",
    "extensionRules", "extensionInteractions", "extensionIntent",
    "extensionActions", "worldKnowledge", "characterAdditions",
    "prompts", "overrides", "sheet",
)

# What a fixture may say about a contact the built-in cast does not hold -- one registered by
# another mod through AiNpcContactProvider. Same fields as a cast sheet, because that is what
# a provider answers with; a fixture for a built-in contact may also use them to change one
# field of the shipped sheet without touching src\.
SHEET_KEYS = ("displayName", "bio", "relationship", "romance", "romanceable",
              "liveContext", "speechStyle", "questContexts", "variants",
              "allowsMemory", "knowsPlayerLifePath", "prompts",
              # The declarative veto, by command head: "[ACTION:GIVE_EDDIES:". It replaced
              # allowsGenericTransfer, a flag named after the one command it could refuse --
              # and which this schema still accepted afterwards, so a fixture setting it was
              # writing a key nothing read. A joytoy's client is exactly the case: the mod
              # calls SuppressAction on the transfer, and without this the offline block
              # offered a command the game withholds.
              "suppressActions", "actions")

# One declaration, in the shape AiNpcAction builds. A contact supplied by a fixture has no
# .reds to declare from, and a command reaches <commands> only by being declared -- so
# without this key the commands another mod contributes cannot be measured offline at all.
ACTION_KEYS = ("tag", "prompt", "fact", "value", "parameters")
PARAM_KEYS = ("name", "text")

MEMORY_KEYS = ("chronicle", "facts", "threads", "pacts", "tone", "coveredUpTo")


class FixtureError(Exception):
    pass


def parse_time(value, where):
    """In-game seconds from "HH:MM", "<n>d HH:MM", or a raw number."""
    if isinstance(value, bool):
        raise FixtureError("%s: a time cannot be a boolean" % where)
    if isinstance(value, int):
        return value
    if not isinstance(value, str):
        raise FixtureError("%s: expected a time, got %r" % (where, value))
    match = TIME_RE.match(value.strip())
    if not match:
        raise FixtureError('%s: expected "HH:MM" or "<n>d HH:MM", got %r' % (where, value))
    days = int(match.group(1) or 0)
    hours = int(match.group(2))
    minutes = int(match.group(3))
    if hours > 23 or minutes > 59:
        raise FixtureError("%s: %r is not a time of day" % (where, value))
    return days * 86400 + hours * 3600 + minutes * 60


def load(path):
    """One fixture file, validated, with every default filled in."""
    raw = json.load(io.open(path, encoding="utf-8"))
    if not isinstance(raw, dict):
        raise FixtureError("%s: a fixture is an object" % path)

    where = os.path.basename(path)
    unknown = sorted(set(raw) - set(KEYS))
    if unknown:
        raise FixtureError("%s: unknown key(s) %s -- known keys are %s"
                           % (where, ", ".join(unknown), ", ".join(sorted(KEYS))))

    fixture = {
        "name": raw.get("name") or os.path.splitext(where)[0],
        "note": raw.get("note", ""),
        "contact": _required(raw, "contact", where),
        "sheet": _sheet(raw.get("sheet", {}), where),
        "language": _one_of(raw.get("language", "English"), LANGUAGES, "language", where),
        "tone": _one_of(raw.get("tone", "normal"), TONES, "tone", where),
        "romanced": bool(raw.get("romanced", False)),
        "postHeist": bool(raw.get("postHeist", False)),
        # The arc outcomes. Read from quest facts in game (AiNpcStoryState); stated by the
        # fixture here, because a prompt built offline has no save to ask.
        "romanceFailed": bool(raw.get("romanceFailed", False)),
        "randyDead": bool(raw.get("randyDead", False)),
        # What the character has lived through. Ordered oldest to newest on purpose: in a real
        # save each one implies the ones above it, and a fixture that sets a later state
        # without the earlier ones describes a playthrough that cannot exist.
        "evelynRescued": bool(raw.get("evelynRescued", False)),
        "evelynDead": bool(raw.get("evelynDead", False)),
        "cloudsSettled": bool(raw.get("cloudsSettled", False)),
        "leftNightCity": bool(raw.get("leftNightCity", False)),
        # What somebody other than V has been told. Same ordering rule as the block above: the
        # drive-in cannot have happened in a save where Johnny never took the wheel.
        "johnnyRevealed": bool(raw.get("johnnyRevealed", False)),
        "johnnyDateDone": bool(raw.get("johnnyDateDone", False)),
        # What THIS character has told V about themselves. False by default, like the two
        # above: a confidence has to be earned in the save, and claiming one that never
        # happened is the failure this condition exists to stop.
        "confidedInV": bool(raw.get("confidedInV", False)),
        "memoryEnabled": bool(raw.get("memoryEnabled", True)),
        # Mod Settings > Command Handling, whose default is Embedded: the command vocabulary
        # is rendered into the conversation prompt. Dedicated moves it into the action pass's
        # own request, so the character is asked for prose and nothing else -- which is a
        # different prompt, and the reason this is a field rather than an assumption.
        "pendingContext": raw.get("pendingContext", ""),
        # The word AiNpcWeatherLine puts in <now>. "" removes the line, which the game never
        # does -- kept so its absence can be measured.
        "weather": raw.get("weather", "clear"),
        "extensionContext": list(raw.get("extensionContext", [])),
        "extensionActions": list(raw.get("extensionActions", [])),
        # What another mod registered about Night City itself, through
        # client.RegisterWorldKnowledge. A list of texts, already in the "<modId>:<subject>"
        # order the registry keeps them in -- offline there is no registration to sort.
        "worldKnowledge": list(raw.get("worldKnowledge", [])),
        # The same registry, addressed to this contact instead of to the city, through
        # client.RegisterCharacterAddition. It joins the end of the bio and replaces
        # nothing, so a fixture that says nothing here describes a contact nobody touched.
        "characterAdditions": list(raw.get("characterAdditions", [])),
        # prompts.json and a contact override. Their "rules" key is a {KEY: text} object in
        # both files, flattened here into the ordered list AiNpcRuleContributions builds.
        "prompts": _with_rules(raw.get("prompts", {})),
        # Ce qu'une extension tierce contribue a <system_rules>, meme forme que "rules".
        "extensionRules": _with_rules({"rules": raw.get("extensionRules", {})})["rules"],
        "extensionInteractions": _with_rules(
            {"rules": raw.get("extensionInteractions", {})})["rules"],
        # Ce qu'une extension tierce ajoute a <intent>, une ligne par extension.
        "extensionIntent": list(raw.get("extensionIntent", [])),
        "overrides": _with_rules(raw.get("overrides", {})),
        "speaksFirst": bool(raw.get("speaksFirst", False)),
        "reason": raw.get("reason", ""),
        # The second half of CharacterWantsToSay, and not the same thing as the reason:
        # the reason is what she writes about, in the slot V's line occupied, and this is
        # what she wants while writing it. It outranks the mission and the standing want
        # for this one message, and it is stored nowhere -- so a fixture states it per
        # conversation, exactly as a mod passes it per generation.
        "intent": raw.get("intent", ""),
        "ask": raw.get("ask", ""),
    }

    player = dict(raw.get("player", {}))
    unknown = sorted(set(player) - set(PLAYER_KEYS))
    if unknown:
        raise FixtureError("%s: unknown player key(s) %s" % (where, ", ".join(unknown)))
    fixture["player"] = {
        "gender": _one_of(player.get("gender", "Female"), GENDERS, "player.gender", where),
        "lifePath": player.get("lifePath", ""),
        "appearance": player.get("appearance", ""),
        "description": player.get("description", ""),
    }

    quest = dict(raw.get("quest", {}))
    fixture["quest"] = {
        "key": quest.get("key", ""),
        # The journal's own title. In game it is localized like the objective beside it; a
        # fixture states it, since there is no journal to read it out of.
        "name": quest.get("name", ""),
        "objective": quest.get("objective", ""),
    }

    fixture["messages"] = _messages(raw.get("messages", []), where)

    # The clock the request is sent at. Defaults to the last stored message rather than to
    # zero: a fixture that does not care about time should not accidentally open a gap.
    if "now" in raw:
        fixture["now"] = parse_time(raw["now"], "%s: now" % where)
    elif fixture["messages"]:
        fixture["now"] = fixture["messages"][-1]["at"]
    else:
        fixture["now"] = 0

    fixture["memory"] = _memory(raw.get("memory", {}), where)

    if fixture["speaksFirst"] and not fixture["reason"]:
        raise FixtureError("%s: speaksFirst needs a reason -- it is what the character is "
                           "writing about" % where)
    if fixture["intent"] and not fixture["speaksFirst"]:
        raise FixtureError("%s: an intent is passed with CharacterWantsToSay, so it only "
                           "reaches a prompt the character writes first -- set speaksFirst, "
                           "or state the want on the sheet" % where)
    if not fixture["speaksFirst"] and not fixture["ask"]:
        raise FixtureError("%s: no ask -- a fixture is a conversation plus the line V is "
                           "sending now" % where)

    return fixture


def _with_rules(raw):
    out = dict(raw or {})
    rules = out.get("rules")
    if isinstance(rules, dict):
        out["rules"] = [{"key": key, "text": text} for key, text in rules.items()]
    return out


def _sheet(raw, where):
    unknown = sorted(set(raw) - set(SHEET_KEYS))
    if unknown:
        raise FixtureError("%s: unknown sheet key(s) %s -- a sheet holds %s"
                           % (where, ", ".join(unknown), ", ".join(SHEET_KEYS)))
    sheet = dict(raw)
    sheet["actions"] = [_action(action, where) for action in raw.get("actions", [])]
    return sheet


def _action(raw, where):
    unknown = sorted(set(raw) - set(ACTION_KEYS))
    if unknown:
        raise FixtureError("%s: unknown action key(s) %s -- an action holds %s"
                           % (where, ", ".join(unknown), ", ".join(ACTION_KEYS)))
    for key in ("tag", "prompt"):
        if not raw.get(key):
            raise FixtureError("%s: an action needs a %s" % (where, key))
    # The same shape AiNpcActionTagIsWellFormed holds a declaration to: a whole pattern, not a
    # prefix. What the model reads is this line, so the fields belong in it --
    # "[ACTION:TRICK:PLACE:HOUR:PRICE]", never "[ACTION:TRICK:".
    if not raw["tag"].startswith("[ACTION:") or not raw["tag"].endswith("]"):
        raise FixtureError("%s: %r is not a tag pattern -- it opens with [ACTION: and closes "
                           "on ]" % (where, raw["tag"]))
    return {"tag": raw["tag"], "prompt": raw["prompt"],
            "fact": raw.get("fact", ""), "value": raw.get("value", 1),
            "parameters": [_param(p, raw["tag"], where)
                           for p in raw.get("parameters", [])]}


def _param(raw, tag, where):
    """One slot definition, held to what AiNpcActionParamsRefusal holds a declaration to.

    Both directions are checked in the mod and both are checked here: a slot with no definition
    hands the model a name nobody explained, a definition no slot cites is text teaching a word
    that never appears. Neither fails at run time, which is why they fail here.
    """
    unknown = sorted(set(raw) - set(PARAM_KEYS))
    if unknown:
        raise FixtureError("%s: unknown parameter key(s) %s -- a parameter holds %s"
                           % (where, ", ".join(unknown), ", ".join(PARAM_KEYS)))
    name = raw.get("name", "")
    if not name.startswith("{") or not name.endswith("}"):
        raise FixtureError("%s: %r is not a slot -- a parameter is named as the pattern writes "
                           "it, braces included" % (where, name))
    if not raw.get("text"):
        raise FixtureError("%s: parameter %s has no definition" % (where, name))
    if name not in tag and name[:-1] + "?}" not in tag:
        raise FixtureError("%s: parameter %s is defined but never used by %s"
                           % (where, name, tag))
    return {"name": name, "text": raw["text"]}


def _required(raw, key, where):
    value = raw.get(key)
    if not value:
        raise FixtureError("%s: %s is required" % (where, key))
    return value


def _one_of(value, allowed, key, where):
    if value not in allowed:
        raise FixtureError("%s: %s must be one of %s, got %r"
                           % (where, key, ", ".join(allowed), value))
    return value


def _messages(raw, where):
    out = []
    for index, item in enumerate(raw):
        label = "%s: messages[%d]" % (where, index)
        if not isinstance(item, dict):
            raise FixtureError("%s: expected an object" % label)
        unknown = sorted(set(item) - {"from", "text", "at"})
        if unknown:
            raise FixtureError("%s: unknown key(s) %s" % (label, ", ".join(unknown)))
        sender = item.get("from")
        if sender not in ("V", "npc"):
            raise FixtureError('%s: "from" is "V" or "npc", got %r' % (label, sender))
        out.append({
            "fromPlayer": sender == "V",
            "text": item.get("text", ""),
            "at": parse_time(item["at"], label) if "at" in item else 0,
        })
    return out


def _memory(raw, where):
    unknown = sorted(set(raw) - set(MEMORY_KEYS))
    if unknown:
        raise FixtureError("%s: unknown memory key(s) %s" % (where, ", ".join(unknown)))
    pacts = []
    for index, pact in enumerate(raw.get("pacts", [])):
        if isinstance(pact, str):
            pacts.append({"text": pact, "overdue": False})
            continue
        unknown = sorted(set(pact) - {"text", "overdue"})
        if unknown:
            raise FixtureError("%s: unknown pact key(s) %s" % (where, ", ".join(unknown)))
        pacts.append({"text": pact.get("text", ""), "overdue": bool(pact.get("overdue"))})
    return {
        "chronicle": raw.get("chronicle", ""),
        "facts": list(raw.get("facts", [])),
        "threads": list(raw.get("threads", [])),
        "pacts": pacts,
        "tone": raw.get("tone", ""),
        "coveredUpTo": parse_time(raw["coveredUpTo"], "%s: memory.coveredUpTo" % where)
                       if "coveredUpTo" in raw else 0,
    }


def is_empty_memory(memory):
    return not (memory["facts"] or memory["threads"] or memory["pacts"]
                or memory["chronicle"] or memory["tone"])
