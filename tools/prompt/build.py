# -*- coding: utf-8 -*-
"""The prompt itself. Mirrors AiNpcPromptBuild.reds.

    fixture (a conversation) + corpus (the mod's own text) -> {system, user}

THE ASSEMBLY IS NOT COPIED, IT IS WALKED. corpus.json carries the ordered list of blocks
AiNpcBuildSystemPrompt emits -- its `frame` -- and this file walks that list, resolving each
node. A block moved, added or removed in the .reds moves, appears or disappears here on the
next extraction, without a line changing in this file. A node whose shape nothing here knows
raises, naming the call, rather than being skipped: a prompt missing a section is worse than
no prompt at all, because it still answers.

The one thing the frame cannot show is control flow. Three blocks in the mod are wrapped in
`if NotEquals(StrLen(x), 0)` -- <player>, <memory> and <tone> -- and they all follow the same
shape: a tag, one local, the closing tag. So the rule here is stated once and applies to all
three: a concatenation whose local resolves to empty emits nothing. AiNpcSection already
carries that rule for every other block.

What the fixture supplies is exactly what a live session would have: the clock, the tracked
quest, V, the tier, the language, the romance, and whatever a third-party mod seeded into
<now>. Nothing is read from this machine, so the same fixture gives the same bytes today
and next year.
"""

import memory as memory_block
import transcript
from resolve import Env, ResolveError, resolve
from sections import Character, Sections, background_with


class BuildError(Exception):
    pass


class Builder(object):
    def __init__(self, corpus, fixture):
        self.corpus = corpus
        self.fixture = fixture
        self.texts = corpus["sections"]

        # The shipped sheet, then whatever the fixture says about it. A contact the cast does
        # not hold is one another mod registers through AiNpcContactProvider: the fixture
        # carries its sheet instead, which is the same set of fields a provider answers with.
        sheet = dict(corpus["cast"].get(fixture["contact"]) or {})
        sheet.update(fixture["sheet"])
        if not sheet.get("displayName"):
            raise BuildError(
                "no contact %r in the corpus, and the fixture's sheet gives no displayName. "
                "The built-in cast is %s; a contact registered by another mod needs a "
                "\"sheet\" block in the fixture."
                % (fixture["contact"], ", ".join(sorted(corpus["cast"]))))

        # A contact that answers from its own script is never handed to a model: the mod asks
        # before a prompt is built, and a prompt built here would be one nothing ever sends.
        if sheet.get("scriptedReply"):
            raise BuildError(
                "%r answers one recorded line to every message and never reaches a model; "
                "there is no prompt to build for it." % (fixture["contact"],))

        self.character = Character(sheet, fixture)
        self.sections = Sections(corpus, fixture, self.character)

    # ── the system prompt ────────────────────────────────────────────────────

    def system(self):
        out = []
        for node in self.texts["frame"]:
            out.append(self._node(node))
        return "".join(out)

    def _node(self, node):
        # A guarded block: <tag>local</tag>, emitted only when the local has something to
        # say. See the rule in this file's header.
        if isinstance(node, dict) and "concat" in node:
            locals_in_node = [part["ref"] for part in node["concat"]
                              if isinstance(part, dict) and "ref" in part]
            if locals_in_node and all(not self._local(name) for name in locals_in_node):
                return ""
        try:
            return resolve(node, self.env())
        except ResolveError as error:
            raise BuildError("%s\n  in prompt block: %r" % (error, node))

    def env(self):
        return Env(values=_Locals(self), calls={
            "AiNpcSection": self._section,
            "AiNpcGetConversationTypePrompt": lambda _c: self.sections.tone_prompt(),
            "AiNpcGetCharacterBio": lambda _c: self.sections.character_bio(),
            "AiNpcCharacterAdditionsText": lambda _c: self.sections.character_additions(),
            "AiNpcWorldBackgroundWith": background_with,
            "AiNpcGetRelationship": lambda _c: self.sections.relationship(),
            "AiNpcGetWorldInteractions": lambda _c: self.sections.world_interactions(),
            "AiNpcGetWorldBackground": lambda _c: self.sections.world_background(),
            "AiNpcGetCurrentTime": lambda: transcript.clock_label(self.fixture["now"]),
            "AiNpcWeatherLine": self._weather,
            "AiNpcExpandTemplateFor": lambda _c, text: self.sections.expand(text),
            "AiNpcExtensionLiveContext": lambda _ctx: self._extension_context(),
            "AiNpcGetWorldMechanics": lambda _c: self.sections.world_mechanics(),
            "AiNpcBuildActionTable": lambda _c: None,
            "AiNpcRenderActionBlock": lambda _ctx, _table: self.sections.command_block(),
            "AiNpcExtensionIntent": lambda _ctx: self.sections.extension_intent(),
            "AiNpcJoinLines": lambda first, second: (
                first if not second else second if not first else first + chr(10) + second),
            "AiNpcIntentOf": lambda _c, _key, requested: (
                requested or self.sections.intent()),
            "AiNpcQuestContext": lambda _c, _key: self.sections.quest_context(),
            "provider.GetLiveContext": self.sections.live_context,
        })

    def _weather(self):
        """AiNpcWeather's line. The word is the fixture's; the frame around it is the mod's."""
        word = self.fixture["weather"]
        if not word:
            return ""
        return "CURRENT WEATHER: %s\n" % word

    @staticmethod
    def _section(tag, body):
        """AiNpcSection: a tag, or nothing at all when it has nothing to say."""
        if not body:
            return ""
        return "<%s>%s</%s>" % (tag, body, tag)

    # ── the locals the frame reads ───────────────────────────────────────────

    def _local(self, name):
        if name == "systemRules":
            return self.sections.system_rules()
        # The contact's own intention. What extensions add to it is joined by the frame,
        # through AiNpcJoinLines, exactly as the mod does.
        if name == "intent":
            return self.sections.expand(self.sections.intent())
        if name == "playerSection":
            return self.sections.player_section()
        if name == "memoryBlock":
            return self._memory()
        if name == "questKey":
            return self.fixture["quest"]["key"]
        if name == "pendingContext":
            return self.fixture["pendingContext"]
        if name == "intentOverride":
            return self.fixture["intent"]
        # The closing line of <explicitness>, restating the player's tier last.
        if name == "closingRule":
            return self.sections.tone_reminder()
        # The sheet's own <now> line, already newline-terminated by sections.live_context.
        # The frame assigns it to a local so it can test it for emptiness before appending,
        # which is why it shows up here at all.
        if name == "live":
            return self.sections.live_context()
        if name in ("contactId", "ctx", "provider"):
            return self.fixture["contact"]
        raise BuildError(
            "AiNpcBuildSystemPrompt reads a local named %r that this builder does not "
            "compute. It is new, or it was renamed -- add it here." % (name,))

    def _memory(self):
        if not self.fixture["memoryEnabled"] or not self.character.allows_memory():
            return ""
        return memory_block.render(self.corpus, self.fixture["memory"], self.fixture["now"])

    def _extension_context(self):
        """<now> lines contributed by extensions: the romance rubric, then the fixture's.

        Each line gets its own newline, as AiNpcExtensionLiveContext does. The romance line
        goes first because ai_npc's own rubric registers first and the registry keeps the
        order; a fixture standing in for a third-party mod is therefore appended after it.
        """
        lines = []
        romance = self.sections.romance_line()
        if romance:
            lines.append(self.sections.expand(romance))
        for line in self.fixture["extensionContext"]:
            if line:
                lines.append(self.sections.expand(line))
        return "".join(line + "\n" for line in lines)

    # ── the user message ─────────────────────────────────────────────────────

    def user(self):
        """The transcript, then the turn handed to the character mid-sentence."""
        messages = self._window()
        name = self.character.display_name
        history = transcript.history(messages, name, self.fixture["now"])

        if self.fixture["speaksFirst"]:
            last_line = resolve(self.texts["reasonLine"], Env(calls={
                "AiNpcTranscriptLine": transcript.transcript_line,
            }, values={"reason": self.fixture["reason"]}))
        else:
            last_line = "V: " + self.fixture["ask"]

        return history + resolve(self.texts["handover"],
                                 Env({"lastLine": last_line, "npcName": name}))

    def _window(self):
        """What the transcript sends: everything with memory on, a window with it off."""
        messages = self.fixture["messages"]
        if self.fixture["memoryEnabled"]:
            return messages
        return _trim(messages, self.texts["memoryLegacyMaxTurns"])

    # ── the result ───────────────────────────────────────────────────────────

    def prompt(self):
        return {
            "fixture": self.fixture["name"],
            "contact": self.fixture["contact"],
            # Le nom que le transcript met devant chaque ligne, et que la regle de langue
            # interdit au modele de recopier. Il voyage avec le prompt pour que send.py
            # puisse verifier cette clause sans relire la fixture, comme il le fait deja
            # pour la langue attendue.
            "speaker": self.character.display_name,
            "modVersion": self.corpus["modVersion"],
            "system": self.system(),
            "user": self.user(),
        }


class _Locals(dict):
    """The frame's locals, computed on demand -- a section nobody asks for is not built."""

    def __init__(self, builder):
        dict.__init__(self)
        self.builder = builder

    def __contains__(self, name):
        return True

    def __getitem__(self, name):
        return self.builder._local(name)


def _trim(messages, max_turns):
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


def build(corpus, fixture):
    return Builder(corpus, fixture).prompt()
