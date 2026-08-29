# -*- coding: utf-8 -*-
"""Mechanical signals about a reply. Not a score.

What these fixtures actually ask -- is she in character, in the right language, did she write
first about the reason she was given -- has no regex, and a scorer would answer it by
deciding what to match. So nothing here judges. It reports the things that ARE mechanical,
because the mod itself treats them mechanically:

    action      the [ACTION:...] tag AiNpcParseActions would strip, if any. Binary, and the
                one thing a run can be right or wrong about without anybody reading it.
    named       the reply opens with "Name:", which the transcript grammar and the stop
                sequences exist to prevent. Always a defect.
    emoji       a pictograph, which <system_rules> forbids. Typed smileys -- :) ;) xD -- are
                allowed and deliberately not matched: they are ASCII, and they are how the
                characters actually write.
    fenced      markdown or meta-text around the reply -- backticks, "Here is", brackets.
                The mod sends the reply through as it stands, so this reaches the player.
    stamped     the reply opens with a time the model wrote itself -- "[6:05am]", "(2 hours
                later)". <system_rules> says the opposite in as many words: read those
                markers, never write one. The mod strips nothing, so it lands on the phone,
                and the next prompt hands it back as if it were a real gap marker.
    leak        a "<|...|>" control token in the reply. The transcript ends on the handover
                tokens, and a model that continues them literally instead of answering hands
                the player raw scaffolding -- the mod strips nothing, so it lands on screen
                as written. Measured on ~1 reply in 6 with thinking turned off.
    language    the language the reply is written in, and whether it is the one the
                conversation is held in. <system_rules> states a mandatory language rule, and
                it is the first thing a small model drops -- it follows the English of the
                instructions instead of the French of the thread. A player would watch their
                characters switch to English overnight, with nothing in game to say so.
                Empty when the reply is too short to decide; a guess would accuse a model of
                a fault it did not commit.
    lines       how many lines came back.
    words       the unit LENGTH is written in -- <system_rules> caps a reply at 60 words, so
                this is the one signal that says whether that rule is being obeyed. Counted
                on whitespace, which is what a model counts too.
    chars       length, which is what the token bill is proportional to.

Read the replies. These signals only say where to look first.
"""

import re

import language

# Le payload est facultatif : [ACTION:OWES_FAVOUR] n'en porte pas, [ACTION:GIVE_EDDIES:750]
# en porte un, et un tag mal ferme n'en est pas un.
ACTION_RE = re.compile(r"\[ACTION:[A-Z0-9_]+(?::[^\]\s]*)?\]")
# La reponse s ouvre sur un nom suivi de deux-points -- la grammaire du transcript, que les
# stop sequences lisent, et que la regle de langue interdit explicitement dans les huit
# langues. Deux mots au plus : un nom d affichage en fait un ou deux, et la version qui en
# acceptait trois marquait "Ein Sprichwort sagt: " comme un nom. \w plutot qu une classe
# ASCII, sinon "Имя:" et "Élise :" passent invisibles -- justement les alphabets que la regle
# nomme. La majuscule est verifiee sur le caractere, pas sur [A-Z], pour la meme raison.
NAMED_RE = re.compile(r"^(\w[\w'’.-]*(?:[  ]\w[\w'’.-]*)?)\s*:\s")
FENCE_RE = re.compile(r"```|^\s*(?:Here is|Here's|Sure[,!]|As an AI|\*[^*]+\*)", re.I)
LEAK_RE = re.compile(r"<\|[a-z_]+\|>")
# Un horodatage ecrit par le modele : "[6:05am]", "(2 hours later)", ou qu il tombe.
# <system_rules> dit exactement l inverse -- "TIME: a line in round brackets ... marks time
# passing between messages. Read them, never write one." Le mod n en retire aucun, donc ca
# arrive tel quel sur le telephone, et pire : le prochain prompt le renvoie au modele comme
# s il etait un vrai marqueur de silence.
#
# SANS ANCRE DE DEBUT. Le motif exigeait "^", donc il ne voyait le defaut que quand la
# reponse COMMENCAIT par l horodatage -- or les modeles l ecrivent surtout a la fin, apres
# leur message. Sur 356 reponses il en comptait 2 et il y en avait 25 : les trois modeles de
# tete du palier payant tournaient a 11-15 %, rapportes a zero. Un controle qui ne mord que
# sur une position dit "propre" pour la mauvaise raison.
TIMESTAMP_RE = re.compile(r"[\[(]\s*\d{1,2}\s*[:h]\s*\d{2}\s*(am|pm)?\s*[\])]"
                          r"|\([^)\n]{0,40}(later|plus tard|spater|später)[^)\n]{0,25}\)",
                          re.I)

# Ranges that carry pictographs and emoji, without pulling in a dependency. Deliberately not
# every symbol: the point is to spot a face or a heart in an SMS, not to police punctuation.
EMOJI_RANGES = (
    (0x1F300, 0x1FAFF),
    (0x2600, 0x27BF),
    (0xFE0F, 0xFE0F),
    (0x2764, 0x2764),
)


def has_emoji(text):
    for char in text:
        code = ord(char)
        for low, high in EMOJI_RANGES:
            if low <= code <= high:
                return True
    return False


def named(stripped, speaker):
    """La reponse s ouvre-t-elle sur un nom et deux-points ?

    Le nom du personnage est verifie tel quel quand on le connait : un nom d affichage peut
    tenir en trois mots ("River Ward"), ce que le motif generique refuse par construction.
    """
    if speaker:
        head = stripped[:len(speaker)]
        rest = stripped[len(speaker):].lstrip()
        if head.lower() == speaker.lower() and rest.startswith(":"):
            return True
    match = NAMED_RE.match(stripped)
    return bool(match) and match.group(1)[:1].isupper()


def signals(text, expected_language="", speaker=""):
    stripped = text.strip()
    actions = ACTION_RE.findall(stripped)
    spoken = language.detect(stripped)
    return {
        "language": spoken,
        # Faux seulement quand la langue est DECIDEE et differente : une reponse trop
        # courte pour trancher n'est pas une faute.
        "wrongLanguage": bool(expected_language and spoken
                              and spoken != expected_language),
        "action": actions[0] if actions else "",
        "actionCount": len(actions),
        "named": named(stripped, speaker),
        "emoji": has_emoji(stripped),
        "fenced": bool(FENCE_RE.search(stripped)),
        "leak": bool(LEAK_RE.search(stripped)),
        "stamped": bool(TIMESTAMP_RE.search(stripped)),
        "lines": len([line for line in stripped.split("\n") if line.strip()]),
        "words": len(stripped.split()),
        "chars": len(stripped),
        "empty": not stripped,
    }


def summary(signal):
    """One short line for the console, defects first."""
    flags = []
    if signal["empty"]:
        flags.append("EMPTY")
    if signal["named"]:
        flags.append("NAMED")
    if signal["emoji"]:
        flags.append("EMOJI")
    if signal["fenced"]:
        flags.append("META")
    if signal.get("leak"):
        flags.append("LEAK")
    if signal.get("stamped"):
        flags.append("TIME")
    if signal.get("wrongLanguage"):
        flags.append("LANG:" + (signal.get("language") or "?"))
    if signal["action"]:
        flags.append(signal["action"])
    if signal["actionCount"] > 1:
        flags.append("x%d" % signal["actionCount"])
    return "%4d chars %3d words %d line(s) %s" % (
        signal["chars"], signal["words"], signal["lines"], " ".join(flags))
