# -*- coding: utf-8 -*-
"""Propose une voix du catalogue PocketTTS par personnage, et rend l'attribution ecoutable.

    python tools\\tts-lab\\pocket-refs.py --catalogue     # d'abord : rendre le catalogue
    python tools\\tts-lab\\assign-fallback.py             # puis : proposer et copier

Le palier de repli ne clone pas : il choisit, parmi les voix pretes du modele, celle qui
approche le mieux le personnage. Ce fichier fait ce choix **sur la hauteur**, et il faut savoir
ce que ca vaut : la hauteur ne dit pas si une voix « fait » le personnage, seule l'oreille le
dit. Elle dit en revanche qu'on ne donnera pas une voix aigue a Takemura, et le genre est le
premier signal que l'oreille attrape.

C'est donc une PROPOSITION a corriger, et `fallback-voices.json` est faite pour etre editee a
la main. Le script ne l'ecrase pas : les attributions deja presentes sont gardees, et seuls les
personnages sans voix en recoivent une.

Sortie : `out\\repli-<personnage>-<replique>.wav`, une copie du rendu de la voix attribuee, pour
entendre l'attribution plutot que le catalogue.
"""
import argparse
import glob
import io
import json
import os
import shutil
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import voice_bench  # noqa: E402

ASSIGNMENT = os.path.join(HERE, "fallback-voices.json")

# Ecartees a la mesure du 2026-09-01, sur la replique `argot` : `marius` ne rend presque rien
# (RMS 0,007), `stuart_bell` est tres bas (0,014), et `lola` etire la meme phrase sur 11 s
# contre 4 a 6 pour les autres.
UNUSABLE = ("marius", "stuart_bell", "lola")


def pitch(path):
    """Hauteur mediane, par autocorrelation sur les trames voisees.

    Avec numpy, qui est deja la : `pocket-tts` l'installe. En Python pur, une reference de
    trente secondes a 48 kHz demande quelques centaines de millions d'operations et le script
    ne rend pas la main.
    """
    import numpy as np

    values, rate = voice_bench.samples(path)
    x = np.asarray(values, dtype=np.float64)
    win, hop = int(0.04 * rate), int(0.02 * rate)
    lo, hi = int(rate / 350.0), int(rate / 70.0)
    floor = 0.3 * float(np.sqrt(np.mean(np.square(x))))

    picks = []
    for i in range(0, len(x) - win, hop):
        seg = x[i:i + win]
        if np.sqrt(np.mean(np.square(seg))) < floor:
            continue
        seg = seg - seg.mean()
        c = np.correlate(seg, seg, "full")[win - 1:]
        if c[0] <= 0:
            continue
        band = c[lo:hi] / c[0]
        k = int(np.argmax(band))
        if band[k] > 0.3:
            picks.append(rate / float(lo + k))
    return float(np.median(picks)) if picks else float("nan")


def catalogue(line):
    """Les voix rendues par `pocket-refs.py --catalogue`, avec leur hauteur."""
    found = {}
    pattern = os.path.join(HERE, "out", "pocket-voix-*-" + line + ".wav")
    for path in sorted(glob.glob(pattern)):
        name = os.path.basename(path)[len("pocket-voix-"):-len("-" + line + ".wav")]
        if name not in UNUSABLE:
            found[name] = (pitch(path), path)
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--line", default="argot")
    parser.add_argument("--voices", default=voice_bench.VOICES)
    args = parser.parse_args()

    voices = catalogue(args.line)
    if not voices:
        raise SystemExit("aucun rendu de catalogue : lancer d'abord pocket-refs.py --catalogue")

    assigned = {}
    if os.path.exists(ASSIGNMENT):
        with io.open(ASSIGNMENT, encoding="utf-8") as handle:
            assigned = json.load(handle).get("fallback", {})

    taken = set(assigned.values())
    print("%-16s %7s -> %-16s %7s" % ("personnage", "F0", "voix", "F0"))
    for contact, reference in voice_bench.references(args.voices):
        if contact in assigned:
            chosen = assigned[contact]
            note = "  (deja attribuee)"
        else:
            target = pitch(reference)
            free = {k: v for k, v in voices.items() if k not in taken}
            chosen = min(free, key=lambda k: abs(free[k][0] - target))
            assigned[contact] = chosen
            taken.add(chosen)
            note = ""
        print("%-16s %6.0f -> %-16s %6.0f%s"
              % (contact, pitch(reference), chosen, voices[chosen][0], note))
        shutil.copyfile(voices[chosen][1],
                        os.path.join(HERE, "out", "repli-%s-%s.wav" % (contact, args.line)))

    with io.open(ASSIGNMENT, "w", encoding="utf-8") as handle:
        handle.write(json.dumps({"fallback": assigned}, indent=2, ensure_ascii=False) + "\n")
    print("\nattribution : " + ASSIGNMENT)
    print("libres : " + ", ".join(sorted(k for k in voices if k not in taken)))


if __name__ == "__main__":
    main()
