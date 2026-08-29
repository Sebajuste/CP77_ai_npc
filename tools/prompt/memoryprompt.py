# -*- coding: utf-8 -*-
"""La voie pensante : la compaction de mémoire, hors ligne. Reflète AiNpcMemory.reds.

Le mod fait **deux** appels au modèle par conversation, et un seul était mesuré. Celui-ci
tourne dans le dos du joueur : toutes les seize turns, ce qui sort de la fenêtre est envoyé
au modèle pour être résumé en une note structurée, qui redevient le bloc `<memory>` du
prompt suivant.

POURQUOI C'EST LA PORTE LA PLUS IMPORTANTE POUR UN MODÈLE FAIBLE. `AiNpcMemoryParse` rejette
la réponse **entière** si elle ne contient aucun en-tête de section : une excuse, un refus,
un paragraphe de prose, une complétion vide n'ont pas de `FACTS:` et sont jetés. Le mod ne
dit rien, la mémoire ne se met simplement jamais à jour, et le personnage oublie tout au bout
d'une fenêtre. C'est la panne la moins visible du mod, et elle se teste en dix requêtes,
parce qu'elle est binaire : la note se parse ou elle ne se parse pas.

Le texte des consignes vient du corpus, comme partout ici. Seul l'assemblage est reflété --
l'ordre des blocs de `AiNpcMemoryRequestBody`, qui est du code et pas du texte.
"""

import re

from resolve import Env, resolve

# Les seuils de la voie, tels que le mod les pose. Le lot compacté est ce qui SORT de la
# fenêtre : le banc rejoue donc les messages de la fixture comme s'ils venaient d'en sortir.
WINDOW_TURNS = 6


def instruction(corpus, folding=False):
    """Le message système : AiNpcMemoryInstruction(folding)."""
    sections = corpus["sections"]
    env = _labels(sections)
    text = resolve(sections["memoryInstruction"], env)
    if folding:
        text += resolve(sections["memoryInstructionFold"], env)
    return text


def request_body(corpus, memory, npc_name, gender_fact, transcript, folding=False):
    """Le message utilisateur : AiNpcMemoryRequestBody, dans le même ordre de blocs.

    L'ordre n'est pas cosmétique. Ce qui est déjà su est passé EN LECTURE SEULE, avec la
    consigne de ne pas le répéter -- c'est ce qui empêche la mémoire d'être re-résumée
    d'elle-même toutes les dix turns et de dériver comme le fait un résumé glissant.
    """
    sections = corpus["sections"]
    facts_label = sections["memoryFacts"]
    open_label = sections["memoryOpen"]
    agreed_label = sections["memoryAgreed"]
    tone_label = sections["memoryTone"]
    chronicle_label = sections["memoryChronicle"]
    horizons = sections["memoryHorizonWords"]

    out = ""

    if folding and memory.get("archive"):
        if memory.get("chronicle"):
            out += "%s %s\n" % (chronicle_label, memory["chronicle"])
        out += "ARCHIVE (older history, fold it into the %s paragraph):\n" % chronicle_label
        for line in memory["archive"]:
            out += "- %s\n" % line
        out += "\n"

    if memory.get("facts"):
        out += "EXISTING FACTS (already recorded, do not repeat):\n"
        for fact in memory["facts"]:
            out += "- %s\n" % fact

    if memory.get("threads"):
        out += open_label + "\n"
        for thread in memory["threads"]:
            out += "- %s\n" % thread

    if memory.get("pacts"):
        out += agreed_label + "\n"
        for pact in memory["pacts"]:
            # "soon | il passe ce soir" -- l'horizon est un mot, pas une date : le modèle
            # n'a pas d'horloge et une date inventée serait pire que pas de date du tout.
            word = horizons[_horizon_index(pact)]
            out += "- %s | %s\n" % (word, pact["text"])

    if memory.get("tone"):
        out += "%s %s\n" % (tone_label, memory["tone"])

    out += "\nWHO IS WHO (ground truth, not to be revised from the messages):\n"
    out += '- V is the player. Every line beginning "V: " is V speaking.\n'
    if gender_fact:
        out += "- %s\n" % gender_fact
    out += '- %s is the character. Every line beginning "%s: " is %s speaking.\n' % (
        npc_name, npc_name, npc_name)
    out += "\nNEW MESSAGES:\n"
    out += transcript
    return out


def _horizon_index(pact):
    """soon | days | open, dans l'ordre où AiNpcMemoryPactHorizonWord les rend."""
    word = (pact.get("horizon") or "open").lower()
    return {"soon": 0, "days": 1, "open": 2}.get(word, 2)


def _labels(sections):
    """Les appels que les consignes contiennent : les noms de sections, et rien d'autre."""
    return Env(calls={
        "AiNpcMemorySectionFacts": lambda: sections["memoryFacts"],
        "AiNpcMemorySectionOpen": lambda: sections["memoryOpen"],
        "AiNpcMemorySectionAgreed": lambda: sections["memoryAgreed"],
        "AiNpcMemorySectionTone": lambda: sections["memoryTone"],
        "AiNpcMemorySectionChronicle": lambda: sections["memoryChronicle"],
    })


# ── Lire la réponse ──────────────────────────────────────────────────────────

def parse(corpus, text):
    """Ce qu'AiNpcMemoryParse en ferait : les sections vues, et si la note est retenue.

    `kept` est le verdict du mod, et c'est un ET logique très simple : sans en-tête de
    section, la note entière est jetée. Le reste du décompte sert à lire *ce qui manque*
    quand un modèle produit une note partielle -- une note sans FACTS n'est pas rejetée,
    elle appauvrit juste la mémoire en silence.
    """
    sections = corpus["sections"]
    labels = {
        "facts": sections["memoryFacts"],
        "open": sections["memoryOpen"],
        "agreed": sections["memoryAgreed"],
        "tone": sections["memoryTone"],
        "chronicle": sections["memoryChronicle"],
    }
    seen = {name: False for name in labels}
    entries = {"facts": 0, "open": 0, "agreed": 0}
    current = None

    for raw in (text or "").replace("\r\n", "\n").split("\n"):
        line = raw.strip()
        matched = None
        for name, label in labels.items():
            if line.startswith(label):
                matched = name
                break
        if matched:
            seen[matched] = True
            current = matched if matched in entries else None
            continue
        if current and line:
            entries[current] += 1

    return {
        "kept": any(seen.values()),
        "sections": sorted(name for name in seen if seen[name]),
        "facts": entries["facts"],
        "open": entries["open"],
        "agreed": entries["agreed"],
        # Une note qui recopie les faits déjà connus fait exactement ce que la consigne
        # interdit, et la mémoire enfle jusqu'au plafond en se répétant.
        "chars": len(text or ""),
    }


def summary(signal):
    """Une ligne pour la console."""
    if not signal["kept"]:
        return "REJETEE (aucun en-tete de section)"
    return "gardee  %-28s %2d faits %2d ouverts %2d accords" % (
        ",".join(signal["sections"]), signal["facts"], signal["open"], signal["agreed"])
