# -*- coding: utf-8 -*-
"""The cast sheets, read out of src\\r6\\scripts\\ai_npc\\cast\\.

One sheet is one file is one character -- identity, bio, relationship, romance, quest
contexts -- and that is the whole of what the mod knows about them. This file turns those
eleven functions into data, by walking their statements the way the game would.

It executes nothing beyond what a sheet actually does: bind a local, set a field, push a
quest line or a variant, return the definition. A sheet that reaches for anything else stops
the extraction with the file and line, because a construct nobody here understands is text
that would otherwise go missing from every prompt built offline.

Sheets may call one another -- Jackie's post-heist variant takes its bio from the NCPD
archive sheet -- so sheets are resolved lazily by name, and a cycle is reported rather than
recursed into.
"""

import io
import os
import re

from redsvalue import Reader, RedsParseError, function_body, tokenize

# The fields a sheet may set, and what an unset one means. Mirrors AiNpcCharacterDef in
# AiNpcConfigModel.reds; a field added there and not here is reported by check_fields().
DEF_FIELDS = {
    "contactId": "",
    "displayName": "",
    "bio": "",
    "relationship": "",
    "romance": "",
    "liveContext": "",
    "speechStyle": "",
    # Le registre a voix haute. Vide, le rendu retombe sur `speechStyle` -- six des neuf fiches
    # decrivent une personne et se lisent telles quelles.
    "spokenStyle": "",
    # La voix qui dit ce personnage, par palier : {clone, fallback}. Rien du prompt n'en depend,
    # mais le lecteur refuse un champ qu'il ne connait pas, et c'est ce qui le tient a jour.
    "voice": None,
    "romanceable": False,
    "romanced": False,
    "allowsMemory": True,
    "knowsPlayerLifePath": True,
    "enabled": True,
    "source": "",
    "romanceFact": "",
    "intent": "",
}

# AiNpcPromptOverrides, same contract. Every one of these is a section override consulted
# before the built-in text -- see AiNpcPromptOverridesFor.
# Contributed by key: "rules" (<system_rules>) and "interactions". Replaced whole: the rest.
# No tone lane at all -- <explicitness> is the player's setting and nothing may rewrite it.
OVERRIDE_FIELDS = (
    "rules", "interactions", "speechStyle", "language", "playerDescription",
    "worldBackground", "worldMechanics",
)

VARIANT_FIELDS = ("when", "bio", "relationship", "liveContext", "speechStyle", "intent")


class CastReader(object):
    def __init__(self, cast_dir):
        self.cast_dir = cast_dir
        self.sources = {}          # file name -> source text
        self.functions = {}        # AiNpcSheetX -> file name
        self.cache = {}
        self.pending = set()
        self._load()

    def _load(self):
        for name in sorted(os.listdir(self.cast_dir)):
            if not name.endswith(".reds"):
                continue
            path = os.path.join(self.cast_dir, name)
            source = io.open(path, encoding="utf-8").read()
            self.sources[name] = source
            for match in re.finditer(r"func\s+(AiNpcSheet\w+)\s*\(", source):
                self.functions[match.group(1)] = name

    def sheet_names(self):
        return sorted(self.functions)

    def read(self, function_name):
        """One sheet, as a plain dict. Recurses into sheets it borrows from."""
        if function_name in self.cache:
            return self.cache[function_name]
        if function_name in self.pending:
            raise RedsParseError("cast sheets form a cycle at %s" % function_name)
        if function_name not in self.functions:
            raise RedsParseError("no cast sheet named %s" % function_name)

        self.pending.add(function_name)
        where = self.functions[function_name]
        reader = function_body(self.sources[where], function_name, where)
        sheet = self._run(reader, where)
        self.pending.discard(function_name)
        self.cache[function_name] = sheet
        return sheet

    # ── The sheet as a sequence of statements ────────────────────────────────

    def _run(self, reader, where):
        env = {}
        returned = None

        while reader.peek().kind != "end":
            token = reader.peek()

            if token.kind == "ident" and token.value == "let":
                reader.next()
                name = reader.expect_ident()
                reader.expect_punct("=")
                env[name] = self._value(reader.expression(), env, reader)
                reader.expect_punct(";")
                continue

            if token.kind == "ident" and token.value == "return":
                reader.next()
                returned = self._value(reader.expression(), env, reader)
                reader.expect_punct(";")
                continue

            if token.kind == "ident" and token.value == "ArrayPush":
                self._array_push(reader, env)
                continue

            if token.kind == "ident":
                self._assignment(reader, env)
                continue

            reader.fail("unexpected %r at the start of a statement" % (token.value,))

        if not isinstance(returned, dict) or returned.get("__type__") != "AiNpcCharacterDef":
            raise RedsParseError("%s: the sheet does not return a character definition" % where)
        return returned

    def _assignment(self, reader, env):
        name = reader.expect_ident()
        reader.expect_punct(".")
        field = reader.expect_ident()

        # `over.SetRule("KEY", "text")`: the one method a sheet calls, and the only way it
        # contributes a rubric of <system_rules>. Same effect as an ArrayPush into `rules`.
        if reader.peek().kind == "punct" and reader.peek().value == "(":
            self._set_rule(reader, env, name, field)
            return

        # `c.voice.fallback = "eve"` : une affectation dans un objet que la fiche vient de poser
        # dans un champ. Un seul niveau -- au-dela, la fiche decrirait une structure plutot qu'un
        # personnage, et ce lecteur doit le refuser plutot que de le suivre.
        nested = None
        if reader.peek().kind == "punct" and reader.peek().value == ".":
            reader.expect_punct(".")
            nested = field
            field = reader.expect_ident()

        reader.expect_punct("=")
        value = self._value(reader.expression(), env, reader)
        reader.expect_punct(";")

        target = env.get(name)
        if not isinstance(target, dict):
            reader.fail("assignment to unknown object %r" % (name,))
        if nested is not None:
            inner = target.get(nested)
            if not isinstance(inner, dict):
                reader.fail("%r is not an object this sheet has created" % (nested,))
            self._set_field(inner, field, value, reader)
            return
        self._set_field(target, field, value, reader)

    def _set_field(self, target, field, value, reader):
        kind = target.get("__type__")
        known = {
            "AiNpcCharacterDef": set(DEF_FIELDS) | {"prompts"},
            "AiNpcPromptOverrides": set(OVERRIDE_FIELDS),
            "AiNpcCharacterVariant": set(VARIANT_FIELDS),
            "AiNpcArcBeat": {"fact", "atLeast", "text", "unlessFact"},
            # Quelle voix dit ce personnage, par palier. Rien du prompt n'en depend ; le lecteur
            # la connait parce qu'il refuse ce qu'il ne connait pas, et c'est ce qui le tient a
            # jour avec AiNpcConfigModel.reds.
            "AiNpcVoiceDef": {"clone", "fallback"},
        }.get(kind)
        if known is None:
            reader.fail("assignment on an object of unknown type %r" % (kind,))
        if field not in known:
            reader.fail("%s has no field %r known to this reader; "
                        "add it here and to the builder" % (kind, field))
        target[field] = value

    # The two methods a sheet calls, and the only way it contributes a rubric. The field they
    # write is the block's, so a reader that knows one knows both.
    RULE_METHODS = {"SetRule": "rules", "SetInteraction": "interactions"}

    def _set_rule(self, reader, env, name, method):
        field = self.RULE_METHODS.get(method)
        if field is None:
            reader.fail("%s.%s(...) is a method this reader does not know" % (name, method))
        reader.expect_punct("(")
        key = self._value(reader.expression(), env, reader)
        reader.expect_punct(",")
        text = self._value(reader.expression(), env, reader)
        reader.expect_punct(")")
        reader.expect_punct(";")

        target = env.get(name)
        if not isinstance(target, dict):
            reader.fail("%s on unknown object %r" % (method, name))
        rules = target.setdefault(field, [])
        for rule in rules:
            if rule["key"] == key:
                rule["text"] = text
                return
        rules.append({"key": key, "text": text})

    def _array_push(self, reader, env):
        reader.next()                       # ArrayPush
        reader.expect_punct("(")
        target_name = reader.expect_ident()
        reader.expect_punct(".")
        array_field = reader.expect_ident()
        reader.expect_punct(",")
        item = self._value(reader.expression(), env, reader)
        reader.expect_punct(")")
        reader.expect_punct(";")

        target = env.get(target_name)
        if not isinstance(target, dict):
            reader.fail("ArrayPush into unknown object %r" % (target_name,))
        target.setdefault(array_field, []).append(item)

    # ── Values ───────────────────────────────────────────────────────────────

    def _value(self, tree, env, reader):
        """A parsed expression, resolved to a string, a bool or an object."""
        if isinstance(tree, (str, bool)):
            return tree

        if "concat" in tree:
            parts = [self._value(part, env, reader) for part in tree["concat"]]
            for part in parts:
                if not isinstance(part, str):
                    reader.fail("concatenation of something that is not text")
            return "".join(parts)

        if "ref" in tree:
            name = tree["ref"]
            if name not in env:
                reader.fail("unknown local %r" % (name,))
            return env[name]

        if "member" in tree:
            name, field = tree["member"]
            source = env.get(name)
            if not isinstance(source, dict):
                reader.fail("field access on unknown object %r" % (name,))
            return source.get(field, "")

        if "new" in tree:
            return {"__type__": tree["new"]}

        if "call" in tree:
            return self._call(tree, env, reader)

        reader.fail("unsupported expression in a cast sheet: %r" % (tree,))

    def _call(self, tree, env, reader):
        name = tree["call"]
        args = [self._value(arg, env, reader) for arg in tree["args"]]

        if name == "AiNpcQuest":
            if len(args) != 2:
                reader.fail("AiNpcQuest takes a key and a text")
            return {"questKey": args[0], "text": args[1]}

        if name == "AiNpcAction":
            if len(args) != 3:
                reader.fail("AiNpcAction takes a tag, a prompt and a fact")
            return {"tag": args[0], "prompt": args[1], "fact": args[2], "value": 1}

        # An arc beat never reaches the prompt: it is recorded into the contact's memory at
        # runtime, when its quest fact crosses. Read so that a sheet declaring one still
        # extracts, and carried into the corpus so a fixture could seed it as a memory line.
        if name == "AiNpcBeat":
            if len(args) != 2:
                reader.fail("AiNpcBeat takes a fact and a text")
            return {"__type__": "AiNpcArcBeat", "fact": args[0], "text": args[1],
                    "atLeast": 1, "unlessFact": ""}

        # One recorded line, in one language. A sheet that carries any never reaches a model
        # at all -- see build.py, which refuses to build a prompt for such a contact.
        if name == "AiNpcLine":
            if len(args) != 2:
                reader.fail("AiNpcLine takes a language and a text")
            return {"language": args[0], "text": args[1]}

        if name == "AiNpcVariant":
            if len(args) != 1:
                reader.fail("AiNpcVariant takes a condition")
            return {"__type__": "AiNpcCharacterVariant", "when": args[0]}

        if name.startswith("AiNpcSheet"):
            return self.read(name)

        reader.fail("a cast sheet calls %s(), which this reader does not know" % name)


def normalise(sheet):
    """One sheet as the corpus stores it: every field present, defaults filled in."""
    out = dict(DEF_FIELDS)
    for field, default in DEF_FIELDS.items():
        if field in sheet:
            out[field] = sheet[field]

    prompts = sheet.get("prompts")
    overrides = {}
    if isinstance(prompts, dict):
        for field in OVERRIDE_FIELDS:
            value = prompts.get(field, "")
            if value:
                overrides[field] = value
    out["prompts"] = overrides

    out["variants"] = [
        {field: variant.get(field, "") for field in VARIANT_FIELDS}
        for variant in sheet.get("variants", [])
    ]
    out["questContexts"] = {
        quest["questKey"]: quest["text"] for quest in sheet.get("questContexts", [])
    }
    out["questIntents"] = {
        quest["questKey"]: quest["text"] for quest in sheet.get("questIntents", [])
    }
    out["actions"] = list(sheet.get("actions", []))
    # Keyed by language name, "" for the line every unlisted language falls back to. Not part
    # of any prompt either: a contact that carries one answers it instead of being generated.
    out["scriptedReply"] = {
        line["language"]: line["text"] for line in sheet.get("scriptedReply", [])
    }
    out["seedFacts"] = list(sheet.get("seedFacts", []))
    # Not part of any prompt: a beat is recorded into the contact's memory when its quest fact
    # crosses, in game. Carried so a fixture can seed one and test what the character says once
    # it has happened.
    out["arc"] = list(sheet.get("arc", []))
    return out


def check_fields(model_source):
    """Fields declared on AiNpcCharacterDef that this reader has never heard of.

    The sheets do not use every field today, so a silent absence here would not fail on any
    current sheet -- it would fail on the first one that starts using it. Reported at
    extraction time instead, where it is one line of output rather than a missing paragraph
    in a prompt.
    """
    body = re.search(r"class AiNpcCharacterDef \{(.*?)\n\}", model_source, re.S)
    if not body:
        return ["AiNpcCharacterDef not found in AiNpcConfigModel.reds"]
    declared = set(re.findall(r"public let (\w+)\s*:", body.group(1)))
    known = set(DEF_FIELDS) | {"prompts", "variants", "questContexts", "questIntents",
                               "actions", "suppressActions", "tags", "seedFacts", "arc",
                               "scriptedReply"}
    return sorted(declared - known)
