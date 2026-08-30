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
"""

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
    head = tree if isinstance(tree, str) else _head(tree)
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


def render(corpus, memory, now_seconds):
    """The block, or "" when there is nothing to remember."""
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

    calls = {
        "AiNpcMemorySectionChronicle": lambda: sections["memoryChronicle"],
        "AiNpcMemorySectionFacts": lambda: sections["memoryFacts"],
        "AiNpcMemorySectionOpen": lambda: sections["memoryOpen"],
        "AiNpcMemorySectionAgreed": lambda: sections["memoryAgreed"],
        "AiNpcMemorySectionTone": lambda: sections["memoryTone"],
    }

    out = [sections["memoryHeader"]]

    elapsed = format_elapsed(memory["coveredUpTo"], now_seconds)
    if elapsed:
        out.append(resolve(elapsed_part, Env({"elapsed": elapsed}, calls)))

    if memory["chronicle"]:
        out.append(resolve(chronicle_part,
                           Env({"memory": {"chronicle": memory["chronicle"]}}, calls)))

    if memory["facts"]:
        out.append(resolve(facts_label, Env(calls=calls)))
        for index, fact in enumerate(memory["facts"]):
            out.append(resolve(fact_part,
                               Env({"memory": {"facts": memory["facts"]}, "i": index}, calls)))

    if memory["threads"]:
        out.append(resolve(threads_label, Env(calls=calls)))
        threads = [{"text": text} for text in memory["threads"]]
        for index in range(len(threads)):
            out.append(resolve(thread_part,
                               Env({"memory": {"threads": threads}, "i": index}, calls)))

    if memory["pacts"]:
        out.append(resolve(agreed_label, Env(calls=calls)))
        for index, pact in enumerate(memory["pacts"]):
            # "(overdue) " is the mod's own marker, computed there from the pact's horizon
            # and the clock. A fixture states the outcome instead of the horizon: what is
            # being tested is a prompt that carries an overdue promise, not the arithmetic
            # that decided it was overdue -- which AiNpcTests already pins in the game.
            marker = sections["memoryOverdue"] if pact["overdue"] else ""
            out.append(resolve(pact_part,
                               Env({"memory": {"pacts": memory["pacts"]},
                                    "i": index, "marker": marker}, calls)))

    if memory["tone"]:
        out.append(resolve(tone_part, Env({"memory": {"tone": memory["tone"]}}, calls)))

    return "".join(out)
