# -*- coding: utf-8 -*-
"""The built-in prompt sections, read out of the .reds sources.

Everything a prompt is made of that is NOT a cast sheet: <system_rules>, <world_lore> and its
per-language WORDS table, the three tone tiers and their reminders, the language rule, the
speech style, V's description clauses, the money-transfer mechanics. All of it is authored
text, all of it lives in string literals, and none of it is copied here.

WHAT IS HARVESTED AND WHAT IS NOT. A section function in the mod has the same shape every
time: consult the contact override, consult prompts.json, and otherwise return the built-in
text. Only that last return is harvested -- the two override lanes are configuration, and a
fixture supplies them itself. Functions that answer per language or per tier are harvested
by branch, keyed by the enum member the branch matches.

The scanner is deliberately blunt: it walks the token stream of one function and records
every `return`, every assignment and every `+=`. It understands no control flow, which is
why what it produces is then picked apart by name here, in the open, rather than trusted
wholesale.
"""

import io
import os

from redsvalue import RedsParseError, function_body


class Harvest(object):
    """Everything one function says, without any idea of when it says it."""

    def __init__(self):
        self.returns = []        # (case label or None, tree)
        self.assigns = {}        # name -> [tree, ...] in source order
        self.appends = {}        # name -> [tree, ...] in source order
        self.pushes = {}         # ArrayPush target -> [tree, ...] in source order

    def final_return(self):
        """The unconditional return at the end -- the built-in text of a section."""
        for label, tree in reversed(self.returns):
            if label is None:
                return tree
        raise RedsParseError("no unconditional return to harvest")

    def by_case(self):
        """Every `case X.Member: return ...` branch, keyed by the member name."""
        return {label: tree for label, tree in self.returns if label}

    def first_assign(self, name):
        values = self.assigns.get(name)
        if not values:
            raise RedsParseError("nothing assigned to %r" % (name,))
        return values[0]

    def last_assign(self, name):
        values = self.assigns.get(name)
        if not values:
            raise RedsParseError("nothing assigned to %r" % (name,))
        return values[-1]


def harvest(source, function_name, where):
    reader = function_body(source, function_name, where)
    if reader is None:
        raise RedsParseError("%s: no function %s" % (where, function_name))

    out = Harvest()
    case_label = None

    while reader.peek().kind != "end":
        token = reader.peek()

        if token.kind == "ident" and token.value == "case":
            reader.next()
            label = None
            while not reader.at_punct(":"):
                nxt = reader.next()
                if nxt.kind in ("ident", "num"):
                    label = nxt.value
                if nxt.kind == "end":
                    reader.fail("unterminated case label")
            reader.next()
            case_label = label
            continue

        if token.kind == "ident" and token.value == "default" and reader.peek(1).kind == "punct" \
                and reader.peek(1).value == ":":
            reader.next()
            reader.next()
            case_label = "default"
            continue

        if token.kind == "ident" and token.value == "return":
            reader.next()
            if reader.at_punct(";"):
                reader.next()
                tree = ""
            else:
                tree = reader.expression()
                reader.expect_punct(";")
            out.returns.append((case_label, tree))
            case_label = None
            continue

        if token.kind == "ident" and _is_assignment(reader):
            name = reader.expect_ident()
            reader.next()                                   # '='
            tree = reader.expression()
            reader.expect_punct(";")
            out.assigns.setdefault(name, []).append(tree)
            continue

        # `ArrayPush(list, value)`, flattened the same way an append is: the conditions
        # around it are lost on purpose, and a value that ends up empty is dropped by
        # whoever renders the list.
        if token.kind == "ident" and token.value == "ArrayPush":
            reader.next()
            reader.expect_punct("(")
            name = reader.expect_ident()
            reader.expect_punct(",")
            tree = reader.expression()
            reader.expect_punct(")")
            reader.expect_punct(";")
            out.pushes.setdefault(name, []).append(tree)
            continue

        if token.kind == "ident" and _is_append(reader):
            name = reader.expect_ident()
            reader.next()                                   # '+'
            reader.next()                                   # '='
            tree = reader.expression()
            reader.expect_punct(";")
            out.appends.setdefault(name, []).append(tree)
            continue

        reader.next()

    return out


def _is_assignment(reader):
    # `x = ...` and not `x == y`, which is a comparison this scanner must walk past.
    after = reader.peek(1)
    if after.kind != "punct" or after.value != "=":
        return False
    then = reader.peek(2)
    return not (then.kind == "punct" and then.value == "=")


def _is_append(reader):
    return (reader.peek(1).kind == "punct" and reader.peek(1).value == "+"
            and reader.peek(2).kind == "punct" and reader.peek(2).value == "=")


# ── The sections themselves ──────────────────────────────────────────────────

# file -> the functions harvested from it. Written out rather than discovered, because a
# section that quietly stops being harvested is a section that quietly stops being in the
# prompt, and a list nobody maintains cannot fail loudly.
SOURCES = {
    "AiNpcPromptSections.reds": (
        "AiNpcCoreInteractionRules", "AiNpcBuiltinWorldLoreFor",
        "AiNpcWorldLoreWords", "AiNpcGetConversationTypePrompt", "AiNpcGetToneReminder",
        "AiNpcCoreRules",
    ),
    "AiNpcLanguage.reds": ("AiNpcBuiltinLanguageRule", "AiNpcDefaultSpeechStyle",
                           "AiNpcCrudeWordsFor"),
    # The built-in command, declared through the same door a mod uses. Its pattern and its
    # trigger sentence are what the block shows, so both are read rather than re-typed.
    "AiNpcTransferHandler.reds": ("AiNpcTransferPattern", "AiNpcTransferPrompt",
                                  "AiNpcTransferAmountParam", "AiNpcTransferCap"),
    "AiNpcActionPrompt.reds": ("AiNpcActionBlockAround", "AiNpcActionBlockOpen"),
    "AiNpcPlayer.reds": (
        "AiNpcGenderStatementFor", "AiNpcPlayerDescriptionFor",
        "AiNpcGetGenderedWord",
    ),
    "AiNpcContacts.reds": ("AiNpcGetAllContactIds", "AiNpcGetCharacterBio"),
    "AiNpcRomanceExtension.reds": ("AiNpcRomanceRefusalLine",),
    "AiNpcContextData.reds": ("AiNpcSituationClause", "AiNpcQuestHeading",
                              "AiNpcQuestAccountLabel"),
    "AiNpcPromptBuild.reds": ("AiNpcBuildSystemPrompt", "AiNpcTranscriptHandover",
                              "AiNpcTranscriptReasonLine"),
    "AiNpcMemory.reds": ("AiNpcMemoryRenderAt", "AiNpcMemorySectionAgreed",
                         "AiNpcMemorySectionChronicle", "AiNpcMemoryLegacyMaxTurns",
                         # The thinking lane: memory compaction. A second call to the model,
                         # with a strict output contract.
                         "AiNpcMemoryInstructionBase", "AiNpcMemoryInstructionFold",
                         "AiNpcMemorySectionFacts", "AiNpcMemorySectionOpen",
                         "AiNpcMemorySectionTone", "AiNpcMemoryPactHorizonWord"),
    "AiNpcVersion.reds": ("AiNpcVersion",),
}


def read_all(script_dir):
    """Every section, as trees, ready to be written to corpus.json."""
    harvested = {}
    for name, functions in SOURCES.items():
        path = os.path.join(script_dir, name)
        source = io.open(path, encoding="utf-8").read()
        for function in functions:
            harvested[function] = harvest(source, function, name)

    def final(function):
        return harvested[function].final_return()

    def cases(function):
        return harvested[function].by_case()

    tone = _pick_tone_args(final("AiNpcGetConversationTypePrompt"))
    reminder = _pick_tone_args(final("AiNpcGetToneReminder"))

    return {
        "version": final("AiNpcVersion"),
        "contactIds": _string_array(final("AiNpcGetAllContactIds")),

        # <interactions>, rubric by rubric, in the order AiNpcCoreInteractionRules pushes them.
        "coreInteractionRules": harvested["AiNpcCoreInteractionRules"].pushes.get("rules", []),
        # <mechanics> carries no built-in text any more: it is prose about how the world works,
        # and Night City needs none explained to somebody who lives in it. The commands moved
        # to their own block, rendered from the declarations.
        "transferCap": final("AiNpcTransferCap"),
        "worldLore": final("AiNpcBuiltinWorldLoreFor"),
        "worldLoreWords": _with_default(harvested["AiNpcWorldLoreWords"]),
        "crudeWords": _with_default(harvested["AiNpcCrudeWordsFor"]),

        "tone": tone,
        "toneReminder": reminder,

        # <system_rules>, rubric by rubric, in the order AiNpcCoreRules pushes them.
        "coreRules": harvested["AiNpcCoreRules"].pushes.get("rules", []),

        "languagePrompt": _with_default(harvested["AiNpcBuiltinLanguageRule"]),
        "defaultSpeechStyle": _with_default(harvested["AiNpcDefaultSpeechStyle"]),
        "genderStatement": cases("AiNpcGenderStatementFor"),
        "genderedWords": cases("AiNpcGetGenderedWord"),

        "playerDescription": harvested["AiNpcPlayerDescriptionFor"].appends.get("result", []),

        "bioFallback": final("AiNpcGetCharacterBio"),
        "romanceRefusal": final("AiNpcRomanceRefusalLine"),
        "situationClause": final("AiNpcSituationClause"),
        "questHeading": final("AiNpcQuestHeading"),
        "questAccountLabel": final("AiNpcQuestAccountLabel"),
        # The framing of the command block. The lines inside it are one per declared command,
        # so only the frame is harvested -- as with the memory block.
        "actionBlock": final("AiNpcActionBlockAround"),
        "actionBlockOpen": final("AiNpcActionBlockOpen"),
        "transferPattern": final("AiNpcTransferPattern"),
        "transferPrompt": final("AiNpcTransferPrompt"),
        "transferAmount": final("AiNpcTransferAmountParam"),
        "handover": final("AiNpcTranscriptHandover"),
        "reasonLine": final("AiNpcTranscriptReasonLine"),

        "memoryHeader": harvested["AiNpcMemoryRenderAt"].first_assign("result"),
        "memoryParts": harvested["AiNpcMemoryRenderAt"].appends.get("result", []),
        "memoryAgreed": final("AiNpcMemorySectionAgreed"),
        "memoryFacts": final("AiNpcMemorySectionFacts"),
        "memoryOpen": final("AiNpcMemorySectionOpen"),
        "memoryTone": final("AiNpcMemorySectionTone"),
        "memoryInstruction": final("AiNpcMemoryInstructionBase"),
        "memoryInstructionFold": final("AiNpcMemoryInstructionFold"),
        # A chain of `if`, not a `switch`: the three words come out in source order (soon,
        # days, open), and that order is what the constructor applies.
        "memoryHorizonWords": [tree for _label, tree in
                               harvested["AiNpcMemoryPactHorizonWord"].returns],
        "memoryOverdue": harvested["AiNpcMemoryRenderAt"].last_assign("marker"),
        "memoryLegacyMaxTurns": int(final("AiNpcMemoryLegacyMaxTurns")["num"]),
        "memoryChronicle": final("AiNpcMemorySectionChronicle"),

        # Every literal the system prompt frames its blocks with, in order. The offline
        # builder mirrors the assembly, and checks each frame token it writes against this
        # list -- so a tag renamed in AiNpcBuildSystemPrompt stops the build instead of
        # producing a prompt with the old tag in it.
        "frame": harvested["AiNpcBuildSystemPrompt"].appends.get("prompt", []),
    }


def _pick_tone_args(tree):
    """The three tier texts out of AiNpcPickTone(tier, normal, nsfw, hard)."""
    if not isinstance(tree, dict) or tree.get("call") != "AiNpcPickTone":
        raise RedsParseError("expected an AiNpcPickTone call, got %r" % (tree,))
    args = tree["args"]
    if len(args) != 4:
        raise RedsParseError("AiNpcPickTone takes a tier and three texts")
    return {"normal": args[1], "nsfw": args[2], "nsfw_hard": args[3]}


def _with_default(harvested):
    """Case branches plus the function's own trailing return, under "default"."""
    out = dict(harvested.by_case())
    try:
        out["default"] = harvested.final_return()
    except RedsParseError:
        pass
    return out


def _string_array(tree):
    if not isinstance(tree, dict) or "array" not in tree:
        raise RedsParseError("expected an array literal, got %r" % (tree,))
    for item in tree["array"]:
        if not isinstance(item, str):
            raise RedsParseError("expected an array of plain strings")
    return list(tree["array"])
