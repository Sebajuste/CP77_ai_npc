# -*- coding: utf-8 -*-
"""The prompt itself. Mirrors AiNpcPromptBuild.reds.

    fixture (a conversation) + corpus (the mod's own text) -> {system, user}

THE ASSEMBLY IS NOT COPIED, IT IS WALKED. corpus.json carries the ordered list of blocks
AiNpcBuildSystemPrompt emits -- its `frame` -- and this file walks that list, resolving each
node. A block moved, added or removed in the .reds moves, appears or disappears here on the
next extraction, without a line changing in this file. A node whose shape nothing here knows
raises, naming the call, rather than being skipped: a prompt missing a section is worse than
no prompt at all, because it still answers.

The frame shows one kind of control flow, and only one: what a RECIPE decides. A node the
sources wrote inside `if AiNpcRecipeHas(...)` carries that question with it -- see guard.py --
and the walk below asks the recipe instead of rendering everything. Every other condition is
lost in extraction, on purpose, and two rules stand in for them: a concatenation whose local
resolves to empty emits nothing, and AiNpcSection drops a tag with nothing under it.

THE DEFAULT IS EVERY BLOCK AT EVERY PART, which is what an install with no recipes.json
renders and what verify.py compares byte for byte. A recipe is what a bench hands in to
measure a cheaper prompt; it is never what the regression check builds.

What the fixture supplies is exactly what a live session would have: the clock, the tracked
quest, V, the tier, the language, the romance, and whatever a third-party mod seeded into
<now>. Nothing is read from this machine, so the same fixture gives the same bytes today
and next year.
"""

import memory as memory_block
import recipe as recipes
import transcript
from guard import guard_of, node_of, satisfied
from resolve import Env, ResolveError, resolve
from sections import Character, Sections, background_with


class BuildError(Exception):
    pass


class Builder(object):
    def __init__(self, corpus, fixture, recipe=None):
        self.corpus = corpus
        self.fixture = fixture
        self.texts = corpus["sections"]
        # No recipe named is an install with no recipes.json: every block, every part.
        self.recipe = recipe or recipes.full(corpus)

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
        when = guard_of(node)
        if when is not None:
            if not satisfied(when, self.recipe, self._truths(), "the prompt frame"):
                return ""
            node = node_of(node)

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

    def _truths(self):
        """The half of a guard the scanner could not read, answered by the fixture.

        Every clause the sources put beside a recipe call is here under its own source text,
        and an unknown one stops the build in guard.satisfied rather than rendering a block
        the mod would not have.
        """
        return {
            # Mod Settings > Command Handling. Dedicated moves the vocabulary out of this
            # prompt and into the action pass's own request; Embedded is the shipped default.
            "!AiNpcActionsAreDedicated()": not self.fixture["commandsDedicated"],
            # Offline a contact always has a sheet, which is what a provider answers with.
            "IsDefined(provider)": True,
            "NotEquals(StrLen(live),0)": bool(self.sections.live_context()),
        }

    def env(self):
        return Env(values=_Locals(self), calls={
            "AiNpcSection": self._section,
            "AiNpcGetSystemRules": lambda _c: self.sections.system_rules(),
            "AiNpcGetConversationTypePrompt": lambda _c: self.sections.tone_prompt(),
            "AiNpcRenderCharacter": lambda _c, _r: self._character(),
            "AiNpcRenderTarget": lambda _c, _r: self._target(),
            "AiNpcGetRelationship": lambda _c: self.sections.relationship(),
            "AiNpcGetWorldInteractions": lambda _c: self.sections.world_interactions(),
            "AiNpcGetWorldBackground": lambda _c: self.sections.world_background(),
            "AiNpcGetWorldMechanics": lambda _c: self.sections.world_mechanics(),
            "AiNpcBuildActionTable": lambda _c: None,
            "AiNpcRenderActionBlock": lambda _ctx, _table: self.sections.command_block(),
            "AiNpcRenderMemoryBlock": lambda _c, _r: self._memory(),
            "AiNpcRenderIntent": lambda _c, _ctx, _key, override, _r: self._intent(override),
            "AiNpcQuestContext": lambda _c, _key, _r: self._quest(),
            "AiNpcRenderNow": lambda _c, _ctx, _p, _pending, _r: self._now(),
            "AiNpcGetCurrentTime": lambda: transcript.clock_label(self.fixture["now"]),
            "AiNpcWeatherLine": self._weather,
            "AiNpcExpandTemplateFor": lambda _c, text: self.sections.expand(text),
            "AiNpcExtensionLiveContext": lambda _ctx: self._extension_context(),
            "AiNpcExtensionIntent": lambda _ctx: self.sections.extension_intent(),
            "AiNpcJoinLines": lambda first, second: (
                first if not second else second if not first else first + chr(10) + second),
            "AiNpcIntentOf": lambda _c, _key, requested: (
                requested or self.sections.intent()),
            "provider.GetLiveContext": self.sections.live_context,
        })

    # ── the blocks a recipe divides ──────────────────────────────────────────
    # Every one of them is rendered WHOLE here, which is the default recipe: the shipped
    # template renders every block at every part, and tools\lint.ps1 fails if it ever stops
    # doing so. A player's own recipes.json is not a fixture and is not reconstructed --
    # what this tool checks is the prompt the mod builds out of the box.

    def _character(self):
        """AiNpcRenderCharacter: the bio, what another mod appended, then the register."""
        if not self.recipe.has("character"):
            return ""
        body = ""
        if self.recipe.wants("character", "bio"):
            body = self.sections.character_bio()
        if self.recipe.wants("character", "additions"):
            body = background_with(body, self.sections.character_additions())
        if self.recipe.wants("character", "speech"):
            style = self.sections.speech_style()
            if style:
                body = background_with(body, "%s: %s" % (self.texts["speechKey"], style))
        return self._section("character", body)

    def _target(self):
        """AiNpcRenderTarget: who the character is writing to, by the source named.

        One source, so one branch, as in the .reds: the parser has already refused anything
        else by name, and a fallback here would be a second place deciding what an unknown
        word means.
        """
        if not self.recipe.has("target"):
            return ""
        source = self.recipe.source_of("target") or self.texts["targetDefaultSource"]
        if source != "player":
            return ""
        return self._section("target", self.sections.player_section())

    def _quest(self):
        """AiNpcQuestContext: the block, and the two parts the journal answers.

        `context` decides the whole block and not one line of it: the name and the objective
        are written INTO the account's frame, so a recipe that drops the account has nothing
        left to frame. That is the .reds's own shape, mirrored rather than tidied.
        """
        if not self.recipe.has("quest") or not self.recipe.wants("quest", "context"):
            return ""
        return self.sections.quest_context(
            with_name=self.recipe.wants("quest", "name"),
            with_objective=self.recipe.wants("quest", "objective"))

    def _intent(self, override):
        """AiNpcRenderIntent: the contact's own, then what extensions want of V.

        The body only. The frame puts <intent> around it, as it does for every block whose
        renderer answers a string rather than a section.
        """
        if not self.recipe.has("intent"):
            return ""
        own = ""
        if self.recipe.wants("intent", "own"):
            own = self.sections.expand(override or self.sections.intent())
        added = ""
        if self.recipe.wants("intent", "extensions"):
            added = self.sections.extension_intent()
        return background_with(own, added)

    def _now(self):
        """AiNpcRenderNow: the block walked part by part, as the memory block is.

        Each part carries the recipe answer the sources guarded it with, so this walk is the
        frame's walk, one level down.
        """
        if not self.recipe.has("now"):
            return ""
        body = "".join(self._node(part) for part in self.texts["nowParts"])
        return self._section("now", body)

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
        if name in ("contactId", "ctx", "provider", "recipe"):
            return self.fixture["contact"]
        raise BuildError(
            "AiNpcBuildSystemPrompt reads a local named %r that this builder does not "
            "compute. It is new, or it was renamed -- add it here." % (name,))

    def _memory(self):
        if not self.fixture["memoryEnabled"] or not self.character.allows_memory():
            return ""
        return memory_block.render(self.corpus, self.fixture["memory"], self.fixture["now"],
                                   self.recipe)

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
        return transcript.trim(messages, self.texts["memoryLegacyMaxTurns"])

    # ── the result ───────────────────────────────────────────────────────────

    def prompt(self):
        return {
            "fixture": self.fixture["name"],
            "recipe": self.recipe.name,
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


def build(corpus, fixture, recipe=None):
    return Builder(corpus, fixture, recipe).prompt()
