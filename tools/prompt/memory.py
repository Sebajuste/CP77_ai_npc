# -*- coding: utf-8 -*-
"""The <memory> block. Mirrors AiNpcMemoryRenderParts in AiNpcMemory.reds.

What the character remembers of everything that has fallen out of the transcript: the
chronicle, the facts, the open threads, what was agreed, the tone. Its prose comes from the
corpus like every other authored text; its structure -- which list is printed under which
label, in which order -- is mirrored here, because it is a loop and not a literal.

Each label is taken from the corpus rather than typed, and taken BY POSITION with its first
bytes asserted. If AiNpcMemoryRenderParts gains a section or reorders one, the assertion fires
with the name of the section it expected, which is the loud failure this tooling is built
around -- a memory block that quietly loses its FACTS list would still look like a prompt.

WHICH PART A RECIPE DROPS IS NOT A LIST KEPT HERE. Every line of the block is written inside
`if AiNpcRecipeWants(recipe, "memory", ...)`, and the extraction keeps that question with the
line -- so a recipe asking for ["facts"] drops the rest by the sources' own guard. What this
file answers is the other half of each guard, the emptiness of the list it is about to print,
because it tests exactly that a line above and two answers to one question is how they come
to disagree.
"""

from guard import guard_of, node_of, satisfied
from resolve import Env, resolve
from transcript import format_elapsed


class MemoryShapeError(Exception):
    pass


def _part(parts, index, expected, label):
    if index >= len(parts):
        raise MemoryShapeError(
            "AiNpcMemoryRenderParts no longer has a %s section (part %d of %d)"
            % (label, index, len(parts)))
    tree = parts[index]
    head = _head(node_of(tree))
    if not head.startswith(expected):
        raise MemoryShapeError(
            "AiNpcMemoryRenderParts part %d should be %s (starting %r), found %r"
            % (index, label, expected, head))
    return tree


def _head(tree):
    """What a part starts with: its first bytes, or the name of the call that writes them.

    Every section label is a function now -- AiNpcMemorySectionFacts and its neighbours --
    so a positional check against "FACTS:" would only ever see the empty head of a call node.
    Naming the call is the stronger assertion anyway: a label whose TEXT changed is a
    deliberate edit to one function, where a label whose CALL changed is a section that moved.
    """
    if isinstance(tree, str):
        return tree
    if isinstance(tree, dict) and "call" in tree:
        return tree["call"]
    if isinstance(tree, dict) and "concat" in tree:
        return _head(tree["concat"][0])
    return ""


def render(corpus, memory, now_seconds, recipe):
    """The block, or "" when there is nothing to remember -- or nothing left to render.

    The recipe is a parameter and not a default: this block is the one a recipe trims most,
    and a builder that forgot to pass it would render every section and look right.
    """
    sections = corpus["sections"]
    if not (memory["facts"] or memory["threads"] or memory["pacts"]
            or memory["chronicle"] or memory["tone"]):
        return ""

    parts = sections["memoryParts"]
    elapsed_part = _part(parts, 0, "The most recent", "the elapsed line")
    chronicle_part = _part(parts, 1, "AiNpcMemorySectionChronicle", "the chronicle line")
    facts_label = _part(parts, 2, "AiNpcMemorySectionFacts", "the FACTS label")
    fact_part = _part(parts, 3, "- ", "a fact line")
    threads_label = _part(parts, 4, "AiNpcMemorySectionOpen", "the OPEN label")
    thread_part = _part(parts, 5, "- ", "a thread line")
    agreed_label = _part(parts, 6, "AiNpcMemorySectionAgreed", "the AGREED label")
    pact_part = _part(parts, 7, "- ", "a pact line")
    tone_part = _part(parts, 8, "AiNpcMemorySectionTone", "the TONE line")

    rendered = _renderer(recipe, memory)

    calls = {
        "AiNpcMemorySectionChronicle": lambda: sections["memoryChronicle"],
        "AiNpcMemorySectionFacts": lambda: sections["memoryFacts"],
        "AiNpcMemorySectionOpen": lambda: sections["memoryOpen"],
        "AiNpcMemorySectionAgreed": lambda: sections["memoryAgreed"],
        "AiNpcMemorySectionTone": lambda: sections["memoryTone"],
    }

    body = []

    if rendered(chronicle_part):
        body.append(rendered.text(chronicle_part,
                                  Env({"memory": {"chronicle": memory["chronicle"]}}, calls)))

    if rendered(facts_label):
        body.append(rendered.text(facts_label, Env(calls=calls)))
        for index in range(len(memory["facts"])):
            body.append(rendered.text(
                fact_part, Env({"memory": {"facts": memory["facts"]}, "i": index}, calls)))

    if rendered(threads_label):
        body.append(rendered.text(threads_label, Env(calls=calls)))
        threads = [{"text": text} for text in memory["threads"]]
        for index in range(len(threads)):
            body.append(rendered.text(
                thread_part, Env({"memory": {"threads": threads}, "i": index}, calls)))

    if rendered(agreed_label):
        body.append(rendered.text(agreed_label, Env(calls=calls)))
        for index, pact in enumerate(memory["pacts"]):
            # "(overdue) " is the mod's own marker, computed there from the pact's horizon
            # and the clock. A fixture states the outcome instead of the horizon: what is
            # being tested is a prompt that carries an overdue promise, not the arithmetic
            # that decided it was overdue -- which AiNpcTests already pins in the game.
            # The marker is written under the same guard as the pact lines, so it comes out
            # of the extraction wrapped like them; the fixture has already decided whether
            # this pact is overdue, which is the only question that guard adds here.
            marker = node_of(sections["memoryOverdue"]) if pact["overdue"] else ""
            body.append(rendered.text(pact_part,
                                      Env({"memory": {"pacts": memory["pacts"]},
                                           "i": index, "marker": marker}, calls)))

    if rendered(tone_part):
        body.append(rendered.text(tone_part, Env({"memory": {"tone": memory["tone"]}}, calls)))

    # The header goes on only once something survived, which is the order AiNpcMemoryRenderParts
    # writes the block in: a header with nothing under it reads as instructions, and a model
    # reading instructions answers them.
    if not body:
        return ""

    out = [sections["memoryHeader"]]
    elapsed = format_elapsed(memory["coveredUpTo"], now_seconds)
    if elapsed:
        out.append(resolve(node_of(elapsed_part), Env({"elapsed": elapsed}, calls)))
    return "".join(out + body)


class _renderer(object):
    """Whether a harvested part is written, and its text once it is.

    Called for the answer, `.text()` for the line. Both go through node_of, so a guarded part
    and a bare one are one shape everywhere below.
    """

    def __init__(self, recipe, memory):
        self.recipe = recipe
        self.truths = {
            'NotEquals(StrLen(memory.chronicle),0)': bool(memory["chronicle"]),
            'ArraySize(memory.facts)>0': bool(memory["facts"]),
            'ArraySize(memory.threads)>0': bool(memory["threads"]),
            'ArraySize(memory.pacts)>0': bool(memory["pacts"]),
            'NotEquals(StrLen(memory.tone),0)': bool(memory["tone"]),
        }

    def __call__(self, part):
        when = guard_of(part)
        if when is None:
            return True
        return satisfied(when, self.recipe, self.truths, "the memory block")

    @staticmethod
    def text(part, env):
        return resolve(node_of(part), env)
