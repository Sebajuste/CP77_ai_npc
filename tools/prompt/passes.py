# -*- coding: utf-8 -*-
"""The passes: one request the mod makes, as its two messages. Mirrors AiNpcPass.reds.

A request is two messages, always, and the mod's own words for the halves are `instruction`
and `ask`. A pass names the builders of both; a recipe describes what the CONVERSATION
instruction renders, block by block, and nothing else. Bound to the compaction, a recipe
saying `character: ["bio"]` would render nothing at all -- which is why this file exists
beside recipe.py rather than inside it.

    pass       instruction                     ask
    speaking   the eleven blocks               the transcript, handed over mid-sentence
    thinking   the compaction instruction      the memory request body
    repair     the command vocabulary          the broken tag, and what to do about it
    actions    the command vocabulary          the thread, the reply, and one question
    test       two literals                    two literals

`test` is not built here. It is a connection check whose two halves are literals written at
the send site, and a bench measuring it would measure whether a provider answers at all.

WHAT KEEPS THIS TABLE HONEST. The names and the sources below are the mod's, mirrored the way
every renderer in this directory is mirrored -- and `check` puts them against what
AiNpcPass.reds actually returns, harvested into corpus.json. A pass added there, a source
renamed, and the offline table stops the run instead of building a prompt for a pass that no
longer exists.
"""

import build
import memoryprompt
import transcript
from resolve import Env, resolve
from sections import Character


class PassError(Exception):
    pass


class Pass(object):
    def __init__(self, name, instruction, ask):
        self.name = name
        self.instruction = instruction
        self.ask = ask


# In the order AiNpcPassNames lists them.
PASSES = (
    Pass("speaking", "conversation", "conversation"),
    Pass("thinking", "memory", "memory"),
    Pass("repair", "commands", "repair"),
    Pass("test", "test", "test"),
    Pass("actions", "commands", "selector"),
)

# Les passes qu'une fixture decrit a elle seule. `repair` et `actions` lisent une reponse
# deja ecrite -- la sortie d'une course, pas l'entree d'une fixture -- donc elles se batissent
# la ou ces reponses vivent, et `test` n'a pas de prompt du tout.
FROM_FIXTURE = ("speaking", "thinking")


def named(name):
    for entry in PASSES:
        if entry.name == name:
            return entry
    raise PassError("no pass named %r. The mod makes: %s"
                    % (name, ", ".join(entry.name for entry in PASSES)))


def check(corpus):
    """That this table and AiNpcPass.reds name the same passes and the same sources."""
    sections = corpus["sections"]
    lanes = sorted(sections["lanes"].values())
    mine = sorted(entry.name for entry in PASSES)
    if lanes != mine:
        raise PassError("the mod's lanes are %s and this table has %s. A pass was added or "
                        "renamed; teach passes.py what it sends." % (lanes, mine))

    for half, harvested in (("instruction", sections["passInstructionSources"]),
                            ("ask", sections["passAskSources"])):
        theirs = sorted(set(harvested))
        ours = sorted({getattr(entry, half) for entry in PASSES})
        if theirs != ours:
            raise PassError("the mod's %s sources are %s and this table names %s."
                            % (half, theirs, ours))


# ── The four passes that have a prompt to build ──────────────────────────────

def speaking(corpus, fixture, recipe=None):
    """The reply: the eleven blocks, and the transcript handed over mid-sentence."""
    return build.build(corpus, fixture, recipe)


def thinking(corpus, fixture):
    """The compaction. It builds both its halves itself, so no recipe reaches it.

    The folded batch is what LEAVES the window; offline the fixture's own messages are
    replayed as if they just had, with its existing memory as the input.
    """
    character = Character(_sheet(corpus, fixture), fixture)
    gender = "V is a woman." if fixture["player"]["gender"] == "Female" else "V is a man."
    lines = transcript.history(fixture["messages"], character.display_name, fixture["now"])
    return {
        "fixture": fixture["name"],
        "contact": fixture["contact"],
        "pass": "thinking",
        "system": memoryprompt.instruction(corpus),
        "user": memoryprompt.request_body(corpus, fixture["memory"], character.display_name,
                                          gender, lines),
    }


def repair(corpus, fixture, tag, recipe=None):
    """The bracket correction: the vocabulary, and the tag that is not in it.

    The smallest request the mod makes -- no persona, no memory, no transcript. `tag` is the
    malformed command a reply carried, which is the whole of what this pass reads.
    """
    ask = resolve(corpus["sections"]["repairAsk"], Env({"tag": tag}))
    return {
        "fixture": fixture["name"],
        "contact": fixture["contact"],
        "pass": "repair",
        "system": vocabulary(corpus, fixture, recipe),
        "user": ask,
    }


def actions(corpus, fixture, reply, recipe=None):
    """The action selection: the vocabulary, the last few messages, and the reply.

    The thread ends on the reply and then on a question, never on the handover -- a selector
    asked to continue "Judy Alvarez: " answers with dialogue instead of reading it.

    V's pending line belongs to the thread here, and it does in the game too: the message has
    been stored by the time a reply exists to read.
    """
    builder = build.Builder(corpus, fixture, recipe)
    return {
        "fixture": fixture["name"],
        "contact": fixture["contact"],
        "pass": "actions",
        "system": vocabulary(corpus, fixture, recipe),
        "user": selector_ask(corpus, builder.character.display_name,
                             fixture["messages"] + [_asked(fixture)], reply),
    }


def selector_ask(corpus, npc, messages, reply):
    """The second half of the action pass, over any thread that ends on V's line.

    Its own function because two benches need it over threads that are not a fixture's: a
    real conversation read out of a save is the same request, and a second construction of it
    would be a second prompt to keep in step with the mod.
    """
    window = transcript.trim(messages, corpus["sections"]["selectorWindow"])
    thread = transcript.history(window, npc, transcript.TIME_UNKNOWN)
    return resolve(corpus["sections"]["selectorAsk"], Env(
        {"transcript": thread, "npcName": npc, "reply": reply},
        {"AiNpcTranscriptLine": transcript.transcript_line,
         "AiNpcActionSelectorNone": lambda: corpus["sections"]["selectorNone"]}))


def vocabulary(corpus, fixture, recipe=None):
    """AiNpcActionVocabularyFor: the command block, or "" when the recipe dropped it.

    The same object the conversation prompt renders, and the same refusal: with no vocabulary
    a bracket in a reply is prose, and there is nothing for either pass to be about.
    """
    builder = build.Builder(corpus, fixture, recipe)
    if not builder.recipe.has("commands"):
        return ""
    return builder.sections.command_block()


def _sheet(corpus, fixture):
    sheet = dict(corpus["cast"].get(fixture["contact"]) or {})
    sheet.update(fixture["sheet"])
    return sheet


def _asked(fixture):
    """V's pending line, as the stored message it has become by the time a reply exists."""
    return {"fromPlayer": True, "text": fixture["ask"], "at": fixture["now"]}
