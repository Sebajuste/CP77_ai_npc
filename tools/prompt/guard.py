# -*- coding: utf-8 -*-
"""The one condition the offline builder keeps: what a recipe answers.

The section scanner understands no control flow and says so -- an `if` around a piece of
prompt is lost, and whoever renders the list drops what comes out empty. That stays true of
every condition but one. A recipe decides whether a block is written at all, so a guard read
as "always" would rebuild a prompt the mod does not send, and rebuild it plausibly.

So a `+=` inside `if AiNpcRecipeHas(...)` or `if AiNpcRecipeWants(...)` comes back wrapped:

    {"when": {"recipe": [{"block": "world", "part": "background"}], "clauses": []},
     "node": <the tree>}

and everything not so guarded comes back exactly as it did before, condition and all.

WHAT STANDS BESIDE A RECIPE CALL IS KEPT WITH IT. `AiNpcRecipeHas(recipe, "commands") &&
!AiNpcActionsAreDedicated()` is one condition, and keeping half of it would render the
command block in a configuration where the mod moves it to another request. The other half
is kept as its source text, in `clauses`, and the builder must bind a truth for it by that
same text or stop -- which is the loud failure this whole directory is built around.

Two shapes raise rather than being guessed at: a recipe call under `!`, and one under `||`.
Both would silently invert what a block renders -- and both raise ONLY when something the
scanner records stands inside them, because `if !AiNpcRecipeHas(recipe, "now") { return ""; }`
is how a renderer opens and there is nothing in it to guess at.
"""

from redsvalue import RedsParseError

RECIPE_CALLS = ("AiNpcRecipeHas", "AiNpcRecipeWants")


class Guard(object):
    """What must be true for the statements inside one `if` to run."""

    def __init__(self, recipe=None, clauses=None, refusal=""):
        self.recipe = recipe or []
        self.clauses = clauses or []
        # Set when the condition names a recipe in a shape this reader will not guess at.
        # Carried rather than raised, because an empty block is not a guess.
        self.refusal = refusal

    def touches_recipe(self):
        return bool(self.recipe) or bool(self.refusal)

    def merged_with(self, other):
        return Guard(self.recipe + other.recipe, self.clauses + other.clauses,
                     self.refusal or other.refusal)

    def as_json(self):
        return {"recipe": self.recipe, "clauses": self.clauses}


def wrap(guards, tree):
    """The tree, under whichever of the enclosing guards a recipe decides.

    Unguarded, or guarded by nothing a recipe answers: the tree itself, as before.
    """
    merged = Guard()
    for guard in guards:
        merged = merged.merged_with(guard)
    if merged.refusal:
        raise RedsParseError(merged.refusal)
    if not merged.touches_recipe():
        return tree
    return {"when": merged.as_json(), "node": tree}


def guard_of(node):
    """The guard on a harvested node, or None."""
    if isinstance(node, dict) and "when" in node:
        return node["when"]
    return None


def node_of(node):
    """The tree a harvested node carries, guard or no guard."""
    if isinstance(node, dict) and "when" in node:
        return node["node"]
    return node


def satisfied(when, recipe, truths, where):
    """Whether a guarded statement runs: what the recipe answers, and what stands beside it.

    A clause with no truth bound raises, naming it. That is the whole contract of `clauses`:
    the scanner kept half a condition it could not read, and the builder either knows what
    that half means or must not render the block.
    """
    for entry in when["recipe"]:
        if "part" in entry:
            if not recipe.wants(entry["block"], entry["part"]):
                return False
        elif not recipe.has(entry["block"]):
            return False

    for clause in when["clauses"]:
        if clause not in truths:
            raise RedsParseError(
                "%s: the sources guard this block with `%s`, and nothing offline says whether "
                "it holds. Bind a truth for it rather than rendering the block anyway."
                % (where, clause))
        if not truths[clause]:
            return False
    return True


def read_condition(tokens, where):
    """One `if` condition, as a Guard. Only the recipe half is understood."""
    recipe = []
    clauses = []
    try:
        for clause in _split_conjunction(tokens, where):
            entry = _recipe_entry(clause, where)
            if entry is None:
                clauses.append(_text_of(clause))
            else:
                recipe.append(entry)
    except RedsParseError as refusal:
        return Guard(refusal=str(refusal))
    return Guard(recipe, clauses)


def _split_conjunction(tokens, where):
    """The clauses of `a && b && c`. A recipe call under `||` raises."""
    clauses = [[]]
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token.kind == "punct" and token.value in "&|" and index + 1 < len(tokens) \
                and tokens[index + 1].kind == "punct" and tokens[index + 1].value == token.value:
            if token.value == "|":
                if any(_names_recipe(clause) for clause in clauses) \
                        or _names_recipe(tokens[index + 2:]):
                    raise RedsParseError(
                        "%s: a recipe call under `||`. This reader reads conjunctions, and a "
                        "guess at an alternative would render a block the mod does not."
                        % (where,))
                clauses[-1].append(token)
                index += 1
                continue
            clauses.append([])
            index += 2
            continue
        clauses[-1].append(token)
        index += 1
    return [clause for clause in clauses if clause]


def _names_recipe(tokens):
    return any(token.kind == "ident" and token.value in RECIPE_CALLS for token in tokens)


def _recipe_entry(clause, where):
    """`AiNpcRecipeHas(recipe, "x")` or `AiNpcRecipeWants(recipe, "x", "y")`, or None."""
    if not _names_recipe(clause):
        return None
    if clause[0].kind == "punct" and clause[0].value == "!":
        raise RedsParseError(
            "%s: a negated recipe call, %s. This reader reads what a recipe asks FOR; a "
            "negation would invert a block without a word." % (where, _text_of(clause)))

    call = clause[0]
    if call.kind != "ident" or call.value not in RECIPE_CALLS:
        raise RedsParseError(
            "%s: a recipe call inside a larger expression, %s. Give it its own clause."
            % (where, _text_of(clause)))

    words = [token.value for token in clause if token.kind == "str"]
    if call.value == "AiNpcRecipeHas":
        if len(words) != 1:
            raise RedsParseError("%s: AiNpcRecipeHas takes one block name, got %r"
                                 % (where, words))
        return {"block": words[0]}
    if len(words) != 2:
        raise RedsParseError("%s: AiNpcRecipeWants takes a block and a part, got %r"
                             % (where, words))
    return {"block": words[0], "part": words[1]}


def _text_of(tokens):
    """A clause as the sources spell it -- the key a builder binds a truth to."""
    out = []
    for token in tokens:
        if token.kind == "str":
            out.append('"%s"' % token.value)
        else:
            out.append(token.value)
    return "".join(out)
