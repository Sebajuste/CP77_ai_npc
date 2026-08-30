# -*- coding: utf-8 -*-
"""What each section says for one fixture. Mirrors AiNpcPromptSections.reds.

Every section in this mod is chosen the same way, and the order is the whole of the rule:

    the contact's own override   (a provider's GetPromptOverrides, or a sheet's `prompts`)
    the player's prompts.json    (the global override)
    the built-in text            (what the corpus holds)

That chain is implemented once, in `configured`, exactly as AiNpcConfiguredSection does it --
including the template expansion the two override lanes get and the built-in text does not.

The rest of the file is one function per section, each answering for the fixture's language,
tone tier, romance state and V. Nothing here reads a machine, a clock or an environment
variable: the same fixture and the same corpus give the same bytes on any day.
"""

import re

from resolve import evaluate, Env, resolve
from template import expand, gendered_word
from transcript import clock_label


TAG_RE = re.compile(r"</|<[A-Za-z0-9_/|]+>")


def looks_like_markup(text):
    """AiNpcTextLooksLikeMarkup: a tag, not an angle bracket.

    `<3` is in a shipped speech style and `->` is in half the sheets, so what is refused is
    the shape that changes the structure -- a closing tag, or a name between brackets.
    """
    return bool(TAG_RE.search(text or ""))


def safe_section_text(text, budget):
    """AiNpcSafeSectionText: the text, or nothing at all. Refused whole, never clamped."""
    if not text:
        return ""
    if looks_like_markup(text) or len(text) > budget:
        return ""
    return text


def background_with(background, addition):
    """AiNpcWorldBackgroundWith: a newline between them, and neither one invented.

    The mod calls it in two places now -- the city's lore joined to what mods registered
    about Night City, and a contact's bio joined to what they added to that one character --
    so the join lives here once rather than twice. The newline is the whole of it: the
    built-in lore ends on a rubric line, and a bare concatenation would make an addition
    read as the tail of the previous claim.
    """
    if not addition:
        return background
    if not background:
        return addition
    return background + "\n" + addition


class Character(object):
    """A contact, as the prompt builder sees it: sheet plus fixture state.

    Mirrors AiNpcDefContactProvider -- the variant lanes included, since a variant is how
    Jackie becomes the NCPD archive after the heist and how a sheet answers differently to a
    male or a female V. A fixture states the conditions; nothing is inferred.
    """

    CONDITIONS = ("postHeist", "preHeist", "romanced", "notRomanced",
                  "playerMale", "playerFemale", "romanceFailed", "randyDead",
                  "evelynDead", "evelynRescued", "cloudsSettled", "leftNightCity",
                  "johnnyRevealed", "johnnyDateDone", "confidedInV")

    def __init__(self, sheet, fixture):
        self.sheet = sheet or {}
        self.fixture = fixture
        self.truths = {
            "postHeist": fixture["postHeist"],
            "preHeist": not fixture["postHeist"],
            "romanced": fixture["romanced"],
            "notRomanced": not fixture["romanced"],
            "playerMale": fixture["player"]["gender"] == "Male",
            "playerFemale": fixture["player"]["gender"] == "Female",
            "romanceFailed": fixture["romanceFailed"],
            "randyDead": fixture["randyDead"],
            "evelynDead": fixture["evelynDead"],
            "evelynRescued": fixture["evelynRescued"],
            "cloudsSettled": fixture["cloudsSettled"],
            "leftNightCity": fixture["leftNightCity"],
            "johnnyRevealed": fixture["johnnyRevealed"],
            "johnnyDateDone": fixture["johnnyDateDone"],
            "confidedInV": fixture["confidedInV"],
        }

    @property
    def display_name(self):
        return self.sheet.get("displayName", "")

    def field(self, name):
        """A sheet field, with the first matching variant winning -- as GetBio does."""
        for variant in self.sheet.get("variants", []):
            text = variant.get(name, "")
            if text and self._holds(variant.get("when", "")):
                return text
        return self.sheet.get(name, "")

    def _holds(self, condition):
        if condition not in self.CONDITIONS:
            raise KeyError("unknown variant condition %r; AiNpcVariantConditions lists %s"
                           % (condition, ", ".join(self.CONDITIONS)))
        return self.truths[condition]

    @property
    def overrides(self):
        """The contact's section overrides: the sheet's own, then the fixture's."""
        merged = dict(self.sheet.get("prompts", {}))
        merged.update(self.fixture["overrides"])
        return merged

    def suppressed_actions(self):
        """Commands this sheet refuses, by head.

        The declarative half of the veto, and the only way a character declared by a file can
        turn down a command granted to everyone. It replaced allowsGenericTransfer, which was a
        flag named after the one command it could refuse.
        """
        return self.sheet.get("suppressActions", [])

    def allows_memory(self):
        return self.sheet.get("allowsMemory", True)

    def knows_life_path(self):
        """Whether <target> tells this contact where V comes from. Mirrors the provider."""
        return self.sheet.get("knowsPlayerLifePath", True)

    def is_romance_capable(self):
        """Could V be with them, as opposed to are they. Mirrors IsRomanceCapable.

        Declared, never inferred from the romance fact: whether a character can be romanced at
        all is a fixed property of who they are, and it is written on the sheet as one.
        """
        return bool(self.sheet.get("romanceable", False))


class Sections(object):
    def __init__(self, corpus, fixture, character):
        self.corpus = corpus
        self.texts = corpus["sections"]
        self.fixture = fixture
        self.character = character

    # ── the override chain ───────────────────────────────────────────────────

    SECTION_BUDGET = 4000

    def configured(self, contact_text, global_text):
        for text in (contact_text, global_text):
            text = safe_section_text(text, self.SECTION_BUDGET)
            if text:
                return self.expand(text)
        return ""

    def expand(self, text):
        return expand(text, self)

    def clock(self):
        """The in-game hour the request is sent at, as {time} and <now> print it."""
        return clock_label(self.fixture["now"])

    def env(self, values=None, calls=None, truths=None):
        """An environment with what every extracted tree may mention about this fixture.

        contactId and language turn up as arguments in the harvested calls -- the sources
        pass them down -- so they are bound once here rather than at each call site.
        """
        bound = {"contactId": self.fixture["contact"], "language": self.fixture["language"]}
        bound.update(values or {})
        female = self.fixture["player"]["gender"] == "Female"
        facts = {"isFemale": female, "isMale": not female}
        facts.update(truths or {})
        return Env(bound, calls, facts)

    def override(self, name):
        return self.character.overrides.get(name, "")

    def prompts(self, name):
        return self.fixture["prompts"].get(name, "")

    # ── the sections ─────────────────────────────────────────────────────────

    # SPEECH is locked because it MOVED: the register is rendered in <character> now, and a
    # rubric taken here would state it twice.
    LOCKED_RULES = {"system_rules": ("FORM", "TIME", "LENGTH", "SPEECH"),
                    "interactions": ("PROMISES",)}
    RULE_BUDGET = 600
    RULE_TOTAL_BUDGET = 2000

    def system_rules(self):
        """<system_rules>, composed. The mod's rubrics, then everyone else's."""
        return self.composed_block("system_rules", self.core_rules(),
                                   self.override("rules") or [],
                                   self.fixture["prompts"].get("rules", []),
                                   self.romance_rule() + self.fixture["extensionRules"])

    def composed_block(self, block, core, from_contact, from_config, from_extensions):
        """Mirrors AiNpcComposedRules and AiNpcRenderRules, refusals included.

        The order is the precedence -- contact, prompts.json, extensions -- and the first
        source to name a rubric owns it. A builder more permissive than the mod would sign
        off prompts the game never sends, so every refusal is repeated here.
        """
        rules = list(core)
        contributions = []
        for source in (from_contact, from_config, from_extensions):
            claimed = {self.rule_key(rule["key"]) for rule in contributions}
            for rule in source:
                if self.rule_key(rule["key"]) not in claimed:
                    contributions.append(rule)

        spent = 0
        for rule in contributions:
            key = self.rule_key(rule["key"])
            text = self.expand(rule["text"])
            if self.rule_refusal(block, key, text):
                continue
            if spent + len(text) > self.RULE_TOTAL_BUDGET:
                continue
            spent += len(text)

            entry = {"key": key, "text": text, "labelled": True}
            existing = [i for i, r in enumerate(rules) if r["key"] == key]
            if existing:
                rules[existing[0]] = entry
                continue
            at = [i for i, r in enumerate(rules) if r["key"] == "LENGTH"]
            rules.insert(at[0] if at else len(rules), entry)

        body = ""
        for rule in rules:
            if not rule["text"]:
                continue
            if rule["labelled"]:
                body += "%s: %s" % (rule["key"], rule["text"]) + chr(10)
            else:
                body += rule["text"] + chr(10)
        if not body:
            return ""
        return "<%s>%s%s</%s>" % (block, chr(10), body, block)

    @staticmethod
    def rule_key(raw):
        """AiNpcRuleKey: one spelling per rubric, so a locked key cannot be dodged by case."""
        return (raw or "").strip().upper()

    def rule_refusal(self, block, key, text):
        """AiNpcRuleRefusal, in the same order and for the same reasons."""
        if not key:
            return "a rule with no key"
        if key in self.LOCKED_RULES.get(block, ()):
            return "one of the rubrics ai_npc keeps"
        if not text.strip():
            return "empty"
        if looks_like_markup(text):
            return "carrying markup"
        if len(text) > self.RULE_BUDGET:
            return "over the per-rubric budget"
        return ""

    def core_rules(self):
        """The rubrics AiNpcCoreRules pushes, resolved against this fixture."""
        env = self.env(
            {"speech": self.speech_style(), "gender": self.gender_statement()},
            {"AiNpcGetLanguagePrompt": lambda _contact: self.language_prompt(),
             "AiNpcGetSpeechStyle": lambda _contact: self.speech_style(),
             "AiNpcGenderStatement": self.gender_statement,
             "AiNpcRuleOf": lambda key, text: {"key": key, "text": text, "labelled": True},
             "AiNpcRawRuleOf": lambda key, text: {"key": key, "text": text, "labelled": False}})
        # evaluate, not resolve: a rubric is an object, and resolve insists on text.
        return [evaluate(tree, env) for tree in self.texts["coreRules"]]

    def extension_intent(self):
        """What extensions add to <intent>, one line each -- mirrors AiNpcExtensionIntent."""
        lines = [self.expand(line) for line in self.fixture["extensionIntent"] if line]
        return "".join(line + chr(10) for line in lines)

    def romance_rule(self):
        """AiNpcRomanceExtension.GetRules: the refusal is a rule, not a fact of the moment."""
        if self.fixture["romanced"] or not self.character.is_romance_capable():
            return []
        return [{"key": "ROMANCE", "text": self.texts["romanceRefusal"]}]

    def romance_rule(self):
        """AiNpcRomanceExtension.GetRules: the refusal is a rule, not a fact of the moment."""
        if self.fixture["romanced"] or not self.character.is_romance_capable():
            return []
        return [{"key": "ROMANCE", "text": self.texts["romanceRefusal"]}]

    def contributed_rules(self):
        """The sheet's rubrics, then prompts.json's, then every extension's.

        Same precedence as AiNpcRuleContributions: the first source to name a rubric owns it,
        and an extension speaks last because it applies to contacts it never declared.
        """
        out = list(self.override("rules") or [])
        for source in (self.fixture["prompts"].get("rules", []),
                       self.romance_rule(),
                       self.fixture["extensionRules"]):
            seen = {self.rule_key(rule["key"]) for rule in out}
            for rule in source:
                if self.rule_key(rule["key"]) not in seen:
                    out.append(rule)
        return out

    def language_prompt(self):
        override = self.override("language")
        if override:
            return override
        configured = self.fixture["prompts"].get("languages", {}).get(self.fixture["language"], "")
        if configured:
            return configured
        return self.by_language(self.texts["languagePrompt"])

    def speech_style(self):
        # The contact's own style comes from the sheet first -- a provider's GetSpeechStyle --
        # and only then from a section override, which is the order AiNpcGetSpeechStyle uses.
        contact_style = self.character.field("speechStyle") or self.override("speechStyle")
        configured = self.configured(contact_style, self.prompts("speechStyle"))
        if configured:
            return configured
        return self.default_speech_style()

    def default_speech_style(self):
        """The language's own form of address, for {register}. Mirrors AiNpcDefaultSpeechStyle."""
        return self.by_language(self.texts["defaultSpeechStyle"])

    def gender_statement(self):
        return self.by_language(self.texts["genderStatement"])

    def world_interactions(self):
        """<interactions>, composed like <system_rules>. PROMISES is the mod's own."""
        return self.composed_block("interactions", self.core_interaction_rules(),
                                   self.override("interactions") or [],
                                   self.fixture["prompts"].get("interactions", []),
                                   self.fixture["extensionInteractions"])

    def core_interaction_rules(self):
        env = self.env({}, {"AiNpcRuleOf": lambda key, text: {"key": key, "text": text,
                                                              "labelled": True}})
        return [evaluate(tree, env) for tree in self.texts["coreInteractionRules"]]

    def world_background(self):
        """The world, plus whatever another mod added to it.

        Additive in BOTH branches, as AiNpcGetWorldBackground is: an override replaces the
        lore, never the standing facts other mods registered about the city.
        """
        configured = self.configured(self.override("worldBackground"),
                                     self.prompts("worldBackground"))
        if configured:
            return self.world_knowledge_with(configured)
        return self.world_knowledge_with(resolve(self.texts["worldLore"], self.env(
            calls={"AiNpcWorldLoreWords": lambda _language: self.by_language(
                self.texts["worldLoreWords"])})))

    def world_knowledge_with(self, background):
        """AiNpcWorldBackgroundWith + AiNpcWorldKnowledgeFragment: raw, one per line."""
        return background_with(background, self._fragment("worldKnowledge"))

    def character_additions(self):
        """AiNpcCharacterAdditionsText: what another mod added to THIS character.

        The same registry as worldKnowledge, read with the contact as audience instead of
        the city -- so the same shape offline, and empty for every fixture that does not
        say otherwise, which is what makes it safe to call with no guard.
        """
        return self._fragment("characterAdditions")

    def _fragment(self, key):
        """AiNpcWorldKnowledgeFragment: the entries of one audience, raw, one per line."""
        return "".join(text + "\n" for text in self.fixture[key] if text)

    def world_mechanics(self):
        """<mechanics>: prose about how the world works, and nothing about any command.

        Mirrors AiNpcGetWorldMechanics, which carries no built-in text: it used to hold the
        eddie-transfer block as well, and a contact that opted out of transfers lost this whole
        section with it -- including an override written about something else.
        """
        override = self.override("worldMechanics")
        if override:
            return self.expand(override)
        return self.configured("", self.prompts("worldMechanics"))

    def tone_prompt(self):
        """The explicitness tier, with the crude table of the fixture's language folded in.

        No contribution lane of any kind: the tier answers a question put to the player, so
        neither a contact nor prompts.json can reach it. The two upper tiers name the table
        through a local, so it is bound here rather than resolved as a call.
        """
        return resolve(self.texts["tone"][self.fixture["tone"]], self.env(
            values={"crudeWords": self.by_language(self.texts["crudeWords"])}))

    def tone_reminder(self):
        return self.texts["toneReminder"][self.fixture["tone"]]

    def character_bio(self):
        bio = self.character.field("bio")
        if bio:
            return self.expand(bio)
        return self.texts["bioFallback"]

    def relationship(self):
        return self.expand(self.character.field("relationship"))

    def player_section(self):
        configured = self.configured(self.override("playerDescription"), "")
        return configured or self.player_description()

    def player_description(self):
        """V, as <target> describes {them}. Mirrors AiNpcPlayerDescriptionFor."""
        player = self.fixture["player"]
        if player["description"]:
            return player["description"]

        female = player["gender"] == "Female"
        env = self.env(truths={"Equals(gender,AiNpcGender.Female)": female})

        parts = self.texts["playerDescription"]
        out = ""
        # AiNpcPlayerDescriptionSeenBy: a contact that answers false to KnowsPlayerLifePath is
        # not told where V comes from. The sheet says so, since a provider is what answers it.
        if player["lifePath"] and self.character.knows_life_path():
            out += resolve(parts[0], self.env({"lifePath": player["lifePath"]}))
        out += resolve(parts[1], env)

        # Ce que le joueur a ecrit, ajoute tel quel. Le redscript passe par
        # AiNpcTrimBothEnds ; ici strip() dit la meme chose sur les memes caracteres.
        appearance = player["appearance"].strip()
        if appearance:
            out += resolve(parts[2], self.env({"trimmed": appearance}))
        return out

    def quest_context(self):
        """The <quest> block: heading, account, live objective. Mirrors AiNpcQuestBlock.

        The sheet supplies the account alone. The other two parts come from the game -- the
        journal's own title for the quest, and what V is doing at this second -- so offline
        they come from the fixture.
        """
        key = self.fixture["quest"]["key"]
        if not key:
            return ""
        account = self.character.sheet.get("questContexts", {}).get(key, "")
        if not account:
            return ""

        name = self.fixture["quest"].get("name", "")
        heading = resolve(self.texts["questHeading"],
                          self.env({"questName": name})) if name else ""
        block = heading + self.texts["questAccountLabel"] + account

        objective = self.fixture["quest"]["objective"]
        if not objective:
            return block
        return block + " " + resolve(self.texts["situationClause"],
                                     self.env({"objective": objective}))

    def intent(self):
        """What this contact wants of V: the tracked quest's answer, or the durable one.

        Mirrors AiNpcIntentFor. The cascade is quest over sheet and never the other way, and
        an absent quest entry leaves the durable intention standing rather than blanking it.
        """
        key = self.fixture["quest"]["key"]
        if key:
            quest_intent = self.character.sheet.get("questIntents", {}).get(key, "")
            if quest_intent:
                return quest_intent
        return self.character.field("intent")

    def command_block(self):
        """<commands>: every command this contact has, rendered from its declaration.

        Mirrors AiNpcRenderActionBlock over the table AiNpcResolveClaims builds. The order is
        the registry's -- ascending full id -- which puts ai_npc's own command first and a
        sheet's own ("cast:<contact>:<verb>") after it.

        Only two declarers exist offline: the built-in transfer, granted to every contact
        unless the sheet suppresses it, and the sheet's own actions, scoped to itself. An
        extension contributes no commands any more; a mod that wants one declares it.
        """
        lines = ""

        cap = self.env(calls={
            "AiNpcTransferCap": lambda: resolve(self.texts["transferCap"], self.env()),
            "IntToString": lambda value: str(value),
        })
        transfer_head = self.texts["transferPattern"].split("{")[0]
        transfer_slot = ""
        if transfer_head not in self.character.suppressed_actions():
            pattern = self.texts["transferPattern"]
            transfer_slot = "{" + pattern.split("{", 1)[1].split("}", 1)[0] + "}"
            lines += pattern + ": " + resolve(self.texts["transferPrompt"], cap) + "\n"

        # First definition wins, and the same mod redefining a slot is not a conflict -- it is
        # its second command reusing what its first declared. Mirrors AiNpcCollectActionParams.
        # Offline there is one declarer, so a cross-mod clash cannot arise here; the shape is
        # kept identical anyway, because a builder that differs is a builder nobody can trust.
        definitions = ""
        seen = []
        # The built-in transfer declares its own slot like anybody else. It is rendered
        # on a separate path here -- it has no sheet entry -- so its definition has to be
        # seeded before the sheet's, which is also the order the registry gives it.
        if transfer_slot:
            seen.append(transfer_slot)
            definitions += (transfer_slot + ": "
                            + resolve(self.texts["transferAmount"], cap) + "\n")
        for action in self.character.sheet.get("actions", []):
            if action["tag"] in self.character.suppressed_actions():
                continue
            lines += action["tag"] + ": " + self.expand(action["prompt"]) + "\n"
            for param in action.get("parameters", []):
                if param["name"] in seen:
                    continue
                seen.append(param["name"])
                definitions += param["name"] + ": " + self.expand(param["text"]) + "\n"

        if not lines:
            return ""
        return resolve(self.texts["actionBlock"],
                       self.env(values={"lines": lines, "definitions": definitions}, calls={
                           "AiNpcActionBlockOpen": lambda: self.texts["actionBlockOpen"],
                       }))

    def romance_line(self):
        """The romance extension's contribution to <now>: the fact, never the rule.

        Being romanced is true of the two of them; refusing advances is an instruction, and
        it is contributed as a ROMANCE rubric instead -- see romance_rule.
        """
        if self.fixture["romanced"]:
            return self.character.sheet.get("romance", "")
        return ""

    def live_context(self):
        """The sheet's own <now> line, RAW.

        Mirrors provider.GetLiveContext, which hands back the field untouched; the newline
        that separates it from the next <now> contributor is added by the frame, in
        AiNpcBuildSystemPrompt. Terminating it here too is the mistake that produces a blank
        line in the block, and it is invisible in every fixture whose sheet leaves the field
        empty -- which was all of them until Judy.
        """
        return self.character.field("liveContext")

    # ── language tables ──────────────────────────────────────────────────────

    def by_language(self, table):
        language = self.fixture["language"]
        return resolve(table.get(language, table.get("default", "")), self.env())

    # ── what the template needs ──────────────────────────────────────────────

    def gendered(self, index):
        return gendered_word(self.texts, index,
                             self.fixture["player"]["gender"] == "Male")
