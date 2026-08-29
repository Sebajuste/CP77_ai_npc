# -*- coding: utf-8 -*-
"""Does the offline builder produce what the game produces?

    python tools\\prompt\\verify.py
    python tools\\prompt\\verify.py --fixture panam-on-the-profile --capture captures\\panam_palmer.json

This is the oracle, and the reason the rest of this directory can be trusted. A capture is a
prompt the MOD sent, pulled out of the game log by ai_npc_lab\\unprompted\\capture.py. A fixture
rebuilt from that same conversation must come back byte for byte identical -- system message
and user message both. One differing character is a defect in this tooling, never a detail:
every byte here is something a model reads.

A pair is declared in fixtures\\<name>.oracle.json next to the fixture:

    {"capture": "..\\captures\\panam_palmer.json"}

Nothing else is needed, and nothing about the game is needed at run time. Capturing a new
prompt does need a launch -- but it is the ONE thing that does, it happens when the prompt
builder itself changes, and no fixture has to wait for it.
"""

import argparse
import difflib
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import extract                                      # noqa: E402
import fixture as fixtures                          # noqa: E402
import staleness                                    # noqa: E402
from build import build                             # noqa: E402
from sectionreader import SOURCES                    # noqa: E402

FIXTURES = os.path.join(HERE, "fixtures")


def use_utf8_stdout():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass


def pairs(only=None, capture=None):
    """Every fixture that has an oracle beside it."""
    if capture:
        return [(os.path.join(FIXTURES, only + ".json"), capture)]
    out = []
    for name in sorted(os.listdir(FIXTURES)):
        if not name.endswith(".oracle.json"):
            continue
        stem = name[:-len(".oracle.json")]
        if only and stem != only:
            continue
        oracle = json.load(io.open(os.path.join(FIXTURES, name), encoding="utf-8"))
        out.append((os.path.join(FIXTURES, stem + ".json"),
                    os.path.normpath(os.path.join(FIXTURES, oracle["capture"]))))
    return out


def compare(label, produced, expected):
    """True when identical; otherwise the first difference, in context."""
    if produced == expected:
        print("  %-8s %6d chars  identical" % (label, len(produced)))
        return True

    print("  %-8s DIFFERS (%d chars produced, %d expected)"
          % (label, len(produced), len(expected)))
    for index, (left, right) in enumerate(zip(produced, expected)):
        if left != right:
            start = max(0, index - 90)
            print("    first difference at character %d:" % index)
            print("      produced: ...%s" % produced[start:index + 40].replace("\n", "\\n"))
            print("      captured: ...%s" % expected[start:index + 40].replace("\n", "\\n"))
            break
    else:
        shorter, longer = sorted((produced, expected), key=len)
        print("    one is a prefix of the other; the extra part is:")
        print("      %r" % longer[len(shorter):len(shorter) + 200])

    diff = difflib.unified_diff(expected.split("\n"), produced.split("\n"),
                                "captured", "produced", lineterm="", n=1)
    lines = list(diff)[:40]
    if lines:
        print("    line diff (captured -> produced):")
        for line in lines:
            print("      %s" % line[:160])
    return False


def main(argv=None):
    use_utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", default=None, help="verify only this one")
    parser.add_argument("--capture", default=None,
                        help="a capture to compare against, instead of the declared oracle")
    args = parser.parse_args(argv)

    todo = pairs(args.fixture, args.capture)
    if not todo:
        print("no fixture has an oracle. Declare one in fixtures\\<name>.oracle.json.")
        return 1

    corpus = extract.load()
    failed = 0
    stale = 0
    proving = 0

    for fixture_path, capture_path in todo:
        name = os.path.splitext(os.path.basename(fixture_path))[0]
        capture = json.load(io.open(capture_path, encoding="utf-8"))
        prompt = build(corpus, fixtures.load(fixture_path))

        # Le mod a-t-il bouge depuis cette capture ? La reponse change le sens d une
        # difference, donc elle est calculee AVANT de comparer quoi que ce soit.
        moved = staleness.moved_since(capture, extract.SCRIPTS, extract.CAST, SOURCES)

        print("%s  vs  %s%s" % (name, os.path.basename(capture_path),
                                "   [capture PERIMEE]" if moved else ""))
        if moved:
            newest, when = moved[0]
            print("  %d source(s) du prompt ont change depuis la capture du %s,"
                  % (len(moved), (capture.get("captured") or "?")[:19]))
            print("  la plus recente etant %s (%s)." % (newest, when.strftime("%Y-%m-%d %H:%M")))

        halves = [("system", prompt["system"], capture["system"]),
                  ("user", prompt["user"], capture["user"])]
        divergent = False
        for label, produced, expected in halves:
            same = compare(label, produced, expected)
            if same:
                proving += 1
            elif not moved:
                # Sources inchangees et octets differents : c est l outillage qui ment.
                divergent = True

        if divergent:
            failed += 1
        elif moved:
            stale += 1

    print()
    if failed:
        print("VERIFY FAILED on %d of %d fixture(s)." % (failed, len(todo)))
        print("Aucune source du prompt n a bouge depuis ces captures, et les octets different"
              " quand meme : c est le constructeur hors ligne qui se trompe, pas le mod.")
        return 1

    if stale:
        # Volontairement pas un echec. Une suite rouge que personne ne peut reparer sans
        # lancer le jeu est une suite qu on apprend a ignorer -- et le jour ou elle signale
        # une vraie divergence, plus personne ne la lit. Le travail est nomme, pas punit.
        print("PERIME: %d oracle(s) sur %d precedent le mod actuel. Rien ne prouve qu ils"
              % (stale, len(todo)))
        print("        soient faux -- ils ne prouvent simplement plus rien de la moitie qui")
        print("        a change. %d moitie(s) de prompt restent verifiees a l octet pres."
              % proving)
        print("        A recapturer au prochain lancement :")
        print("          python ai_npc_lab\\unprompted\\capture.py --contact \"<Nom>\"")
        return 0

    print("VERIFIED: %d fixture(s) rebuild the captured prompt exactly (ai_npc %s)."
          % (len(todo), corpus["modVersion"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
