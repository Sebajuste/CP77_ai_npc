# -*- coding: utf-8 -*-
"""A recipe, offline. Mirrors AiNpcRecipe.reds and AiNpcRecipeParse.reds.

A recipe answers two questions about the system prompt and nothing else: is this block
rendered, and which of its parts. It carries no order -- the builder walks the mod's own
sequence and asks about each block in turn, exactly as AiNpcBuildSystemPromptWith does.

NOTHING HERE IS A SECOND VOCABULARY. The blocks, their parts, the two required ones and the
sources they admit are read out of AiNpcRecipeSchema.reds into corpus.json, and the built-in
book is the template AiNpcRecipeTemplate.reds writes to disk -- parsed here by the same rules
the mod parses it by, which is what makes "the default recipe" and "every block at every
part" one thing offline as they are in the game.

WHAT THE MOD TOLERATES, THIS REFUSES. A typo in a player's recipes.json costs that key and
the game goes on; offline it would mean measuring a prompt nobody sends, so `load` raises on
anything the parser reports as an error. The wording of each refusal is the mod's.

A refusal costs the recipe it is about, never the file: an error in one recipe of a book is
reported with every other, and only stops the run that asked for that one. The whole book is
parsed either way, because a book that only parses the recipe you named is a book whose other
recipes are wrong the day you name them.
"""

import io
import json

PART_ALL_FALLBACK = "all"


class RecipeError(Exception):
    pass


class Issue(object):
    def __init__(self, level, where, message, name=""):
        self.level = level
        self.where = where
        self.message = message
        # Which recipe it is about, "" for the file itself. What lets a bad recipe cost only
        # the run that names it.
        self.name = name

    def __str__(self):
        return "%s: %s: %s" % (self.level, self.where, self.message)


class BlockSchema(object):
    def __init__(self, key, parts, required=False, sources=None):
        self.key = key
        self.parts = list(parts)
        self.required = required
        self.sources = list(sources or [])

    @property
    def sourced(self):
        return bool(self.sources)

    @property
    def is_message(self):
        return self.key in ("instruction", "ask")


class Schema(object):
    """The block table, in the mod's order -- which is the order of the prompt."""

    def __init__(self, entries):
        self.entries = entries

    def of(self, key):
        for entry in self.entries:
            if entry.key == key:
                return entry
        return None

    def names(self):
        return [entry.key for entry in self.entries]


class Recipe(object):
    """What a prompt renders, block by block. An absent block is a rendered block."""

    def __init__(self, name, blocks=None, issues=None):
        self.name = name
        self.blocks = dict(blocks or {})
        self.issues = list(issues or [])

    def has(self, key):
        block = self.blocks.get(key)
        if block is None:
            return True
        return bool(block["parts"])

    def wants(self, key, part):
        block = self.blocks.get(key)
        if block is None:
            return True
        return part in block["parts"]

    def source_of(self, key):
        block = self.blocks.get(key)
        if block is None:
            return ""
        return block["source"]

    def with_block(self, key, parts, source=""):
        blocks = dict(self.blocks)
        blocks[key] = {"parts": list(parts), "source": source}
        return Recipe(self.name, blocks, self.issues)

    def describe(self):
        """One line per block that differs from the full render."""
        return ", ".join("%s=%s" % (key, ",".join(block["parts"]) or "none")
                         for key, block in sorted(self.blocks.items()))


class Book(object):
    def __init__(self, active, recipes, issues):
        self.active = active
        self.recipes = recipes
        self.issues = issues

    def named(self, name):
        return self.recipes.get(name)

    def errors(self, name=None):
        """The errors that stop a run: the file's own, plus the named recipe's."""
        return [issue for issue in self.issues
                if issue.level == "error" and issue.name in ("", name)]


# ── The schema, read from the sources ────────────────────────────────────────

def schema(corpus):
    sections = corpus["sections"]
    part_all = sections.get("recipePartAll", PART_ALL_FALLBACK)
    lists = {
        "AiNpcTargetSources": sections["targetSources"],
        "AiNpcInteractionSources": sections["interactionSources"],
        "AiNpcPassInstructionSources": sections["passInstructionSources"],
        "AiNpcPassAskSources": sections["passAskSources"],
    }

    entries = []
    for node in sections["recipeSchema"]:
        entries.append(_entry_of(node, part_all, lists))
    return Schema(entries)


def _entry_of(node, part_all, lists):
    """One ArrayPush of AiNpcRecipeSchema, through the constructor it names."""
    if not isinstance(node, dict) or "call" not in node:
        raise RecipeError("AiNpcRecipeSchema pushes something this reader cannot read: %r"
                          % (node,))
    call, args = node["call"], node["args"]
    key = args[0]

    if call == "AiNpcRecipeBlockSchemaOf":
        return BlockSchema(key, args[1]["array"])
    if call == "AiNpcRecipeWhole":
        return BlockSchema(key, [part_all])
    if call == "AiNpcRecipeRequired":
        return BlockSchema(key, [part_all], required=True)
    if call == "AiNpcRecipeSourced":
        return BlockSchema(key, [part_all], sources=_list_of(args[1], lists))
    if call == "AiNpcRecipePartedSource":
        return BlockSchema(key, args[1]["array"], sources=_list_of(args[2], lists))
    if call == "AiNpcRecipeMessage":
        return BlockSchema(key, [part_all], required=True, sources=_list_of(args[1], lists))
    raise RecipeError(
        "AiNpcRecipeSchema builds a block with %s(), which this reader does not know. It is "
        "new -- teach recipe.py what it means rather than guessing at its parts." % call)


def _list_of(node, lists):
    if isinstance(node, dict) and "array" in node:
        return node["array"]
    if isinstance(node, dict) and node.get("call") in lists:
        return lists[node["call"]]
    raise RecipeError("a schema entry takes its sources from %r, which is not harvested"
                      % (node,))


def full(corpus, name="full"):
    """Every block at every part: the recipe a file is a difference from."""
    recipe = Recipe(name)
    for entry in schema(corpus).entries:
        recipe = recipe.with_block(entry.key, entry.parts)
    return recipe


# ── A file, read the way the mod reads it ────────────────────────────────────

def book(corpus, text=None):
    """A recipes.json text, or the template the mod ships, as a book of recipes."""
    where = "recipes.json" if text is not None else "the shipped template"
    if text is None:
        text = corpus["sections"]["recipeTemplate"]
    root = json.loads(text)

    issues = []
    _report_unknown(root, ["version", "active", "recipes"], where, "", issues)

    active = root.get("active") or "default"
    recipes = {}
    bodies = root.get("recipes")
    if not isinstance(bodies, dict):
        issues.append(Issue("error", where,
                            'missing or non-object "recipes"; the built-in recipe is used.'))
        return Book(active, recipes, issues)

    for name, body in bodies.items():
        if name.startswith("_"):
            continue
        if not isinstance(body, dict):
            issues.append(Issue("error", where,
                                "recipes.%s is not an object; it is ignored." % name))
            continue
        own = []
        recipes[name] = _recipe_from(corpus, body, name, where, own)
        issues.extend(own)

    if active not in recipes:
        issues.append(Issue("error", where,
                            'active names "%s", which no recipe in this file declares; the '
                            "built-in recipe is used." % active))
    return Book(active, recipes, issues)


def load(corpus, path=None, name=None):
    """The recipe to build with: one of a file's, or of the shipped book.

    Raises on anything the parser reports as an error. A recipe read wrong offline is a
    measurement of a prompt the mod does not send, which is worse than no measurement.
    """
    text = io.open(path, encoding="utf-8").read() if path else None
    parsed = book(corpus, text)
    wanted = name or parsed.active

    errors = parsed.errors(wanted)
    if errors:
        raise RecipeError("\n".join(str(issue) for issue in errors))

    recipe = parsed.named(wanted)
    if recipe is None:
        raise RecipeError('no recipe named "%s". This file declares: %s'
                          % (wanted, ", ".join(sorted(parsed.recipes)) or "none"))
    return recipe


def _recipe_from(corpus, body, name, where, issues):
    """Every recipe is a DIFFERENCE from the full render, never a declaration of it."""
    recipe = full(corpus, name)
    table = schema(corpus)

    _report_unknown(body, table.names(), where, "%s." % name, issues, name)
    conversation = _describes_conversation(corpus, body)

    for entry in table.entries:
        if entry.key in body:
            parts, source = _block_from(body[entry.key], entry, conversation,
                                        "%s: %s.%s" % (where, name, entry.key), issues, name)
            recipe = recipe.with_block(entry.key, parts, source)
    recipe.issues = [issue for issue in issues if issue.name == name]
    return recipe


def _describes_conversation(corpus, body):
    """A recipe is a conversation recipe until its instruction source says otherwise."""
    instruction = body.get("instruction")
    declared = instruction.get("source", "") if isinstance(instruction, dict) else ""
    if not declared:
        return True
    return declared == corpus["sections"]["passInstructionSources"][0]


def _block_from(value, entry, conversation, where, issues, name):
    if isinstance(value, dict):
        return _block_from_object(value, entry, conversation, where, issues, name)
    if isinstance(value, list):
        return _parts_from_list(value, entry, conversation, where, issues, name), ""
    if isinstance(value, bool):
        if value:
            return entry.parts, ""
        return _dropped(entry, conversation, where, issues, name), ""
    if isinstance(value, str):
        return _parts_from_level(value, entry, conversation, where, issues, name), ""
    if value is None:
        return _dropped(entry, conversation, where, issues, name), ""

    issues.append(Issue("error", where,
                        'a number says nothing about a block. Write "full", "none", null, or '
                        "the list of parts. The block keeps every part.", name))
    return entry.parts, ""


def _block_from_object(obj, entry, conversation, where, issues, name):
    _report_unknown(obj, ["level", "parts", "source"], where, "", issues, name)

    parts = entry.parts
    if "parts" in obj:
        parts = _parts_from_list(obj["parts"], entry, conversation, where, issues, name)
    elif "level" in obj:
        parts = _parts_from_level(obj["level"], entry, conversation, where, issues, name)

    source = obj.get("source") or ""
    if source:
        if not entry.sourced:
            issues.append(Issue("warning", where,
                                '"source" means nothing to this block; it is ignored.', name))
            source = ""
        elif source not in entry.sources:
            issues.append(Issue("error", where,
                                'source "%s" is not one of: %s. The block keeps its built-in '
                                "source." % (source, ", ".join(entry.sources)), name))
            source = ""
    return parts, source


def _parts_from_level(level, entry, conversation, where, issues, name):
    if level == "full":
        return entry.parts
    if level == "none":
        return _dropped(entry, conversation, where, issues, name)
    issues.append(Issue("error", where,
                        '"%s" is not a level. Write "full", "none", null, or the list of '
                        "parts: %s. The block keeps every part."
                        % (level, ", ".join(entry.parts)), name))
    return entry.parts


def _parts_from_list(items, entry, conversation, where, issues, name):
    """The requested parts, in the SCHEMA's order rather than the file's."""
    requested = []
    for item in items if isinstance(items, list) else []:
        if not isinstance(item, str):
            continue
        if item in entry.parts:
            requested.append(item)
        else:
            issues.append(Issue("warning", where,
                                '"%s" is not a part of this block. Known parts: %s.'
                                % (item, ", ".join(entry.parts)), name))

    ordered = [part for part in entry.parts if part in requested]
    if not ordered:
        return _dropped(entry, conversation, where, issues, name)
    return ordered


def _dropped(entry, conversation, where, issues, name):
    if entry.required and entry.is_message:
        issues.append(Issue("error", where,
                            "this block cannot be removed: a request is two messages, and "
                            "this one names one of them. It keeps its source.", name))
        return entry.parts
    if entry.required and conversation:
        issues.append(Issue("error", where,
                            "this block cannot be removed: it carries what the mod and the "
                            "player decided, not what a character says. It keeps every part.",
                            name))
        return entry.parts
    return []


def _report_unknown(owner, allowed, where, prefix, issues, name=""):
    """A leading underscore is a comment: JSON has none, and the template annotates itself."""
    for key in owner:
        if not key.startswith("_") and key not in allowed:
            issues.append(Issue("warning", where,
                                'unknown key "%s%s" is ignored. Known: %s.'
                                % (prefix, key, ", ".join(allowed)), name))
