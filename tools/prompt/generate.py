# -*- coding: utf-8 -*-
"""Fixtures in, prompts out. The whole point of this directory.

    python tools\\prompt\\generate.py                       # every fixture
    python tools\\prompt\\generate.py --fixture river-*      # some of them
    python tools\\prompt\\generate.py --out D:\\runs\\0.9.5  # somewhere else
    python tools\\prompt\\generate.py --print river-night-shift

Each fixture becomes one file under out\\<mod version>\\<fixture>.json, holding exactly what
the mod would POST -- a system message and a user message -- plus the version and the corpus
hash they were built from. That last part is what makes a provider comparison mean something
later: a run is attached to the ai_npc it was produced by, and two runs of different versions
never get quietly averaged together.

Nothing here talks to a provider. Sending is a separate lane with its own keys, its own rate
limits and its own failure modes; this one is offline, deterministic and free.
"""

import argparse
import fnmatch
import hashlib
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import extract                                          # noqa: E402
import fixture as fixtures                              # noqa: E402
import memoryprompt                                     # noqa: E402
import transcript                                       # noqa: E402
from build import BuildError, build                     # noqa: E402

FIXTURES = os.path.join(HERE, "fixtures")
OUT = os.path.join(HERE, "out")


def use_utf8_stdout():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass


def corpus_hash(corpus):
    """What the prompts were built from, in twelve characters."""
    text = json.dumps(corpus, ensure_ascii=False, sort_keys=True)
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]


def fixture_paths(patterns):
    if not os.path.isdir(FIXTURES):
        return []
    # *.oracle.json is a fixture's companion -- which capture it must reproduce -- and not
    # a fixture. See verify.py.
    names = sorted(name for name in os.listdir(FIXTURES)
                   if name.endswith(".json") and not name.endswith(".oracle.json"))
    if patterns:
        kept = []
        for name in names:
            stem = os.path.splitext(name)[0]
            if any(fnmatch.fnmatch(stem, pattern) for pattern in patterns):
                kept.append(name)
        names = kept
    return [os.path.join(FIXTURES, name) for name in names]


def memory_prompt(corpus, data):
    """Le prompt de la voie pensante pour cette fixture.

    Le lot compacte est ce qui SORT de la fenetre ; hors ligne on rejoue les messages de la
    fixture comme s ils venaient d en sortir, avec sa memoire existante en entree. C est ce
    que AiNpcMemoryService assemble, et les deux moities portent les memes noms -- system et
    user -- pour que send.py n ait pas a savoir de quelle voie il s agit.
    """
    name = (data["sheet"].get("displayName")
            or corpus["cast"].get(data["contact"], {}).get("displayName", "")
            or data["contact"])
    gender = "V is a woman." if data["player"]["gender"] == "Female" else "V is a man."
    lines = transcript.history(data["messages"], name, data["now"])
    return {
        "fixture": data["name"],
        "contact": data["contact"],
        "lane": "memory",
        "modVersion": corpus["modVersion"],
        "system": memoryprompt.instruction(corpus),
        "user": memoryprompt.request_body(corpus, data["memory"], name, gender, lines),
    }


def main(argv=None):
    use_utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", nargs="*", default=None,
                        help="fixture name or glob; every fixture by default")
    parser.add_argument("--out", default=OUT, help="where the prompts are written")
    parser.add_argument("--lane", default="speaking", choices=["speaking", "memory"],
                        help="quelle des deux voies construire. `speaking` est celle qui "
                             "repond au joueur ; `memory` est la compaction qui tourne dans "
                             "son dos toutes les seize turns, et dont l echec est muet")
    parser.add_argument("--print", dest="show", default=None,
                        help="print one fixture's prompt instead of writing it")
    args = parser.parse_args(argv)

    corpus = extract.load()
    digest = corpus_hash(corpus)
    version = corpus["modVersion"]

    paths = fixture_paths([args.show] if args.show else args.fixture)
    if not paths:
        print("no fixtures matched. They live in tools\\prompt\\fixtures\\.")
        return 1

    target = os.path.join(args.out, version)
    if not args.show:
        if not os.path.isdir(target):
            os.makedirs(target)

    failed = 0
    for path in paths:
        name = os.path.splitext(os.path.basename(path))[0]
        try:
            data = fixtures.load(path)
            prompt = (memory_prompt(corpus, data) if args.lane == "memory"
                      else build(corpus, data))
        except (fixtures.FixtureError, BuildError, KeyError) as error:
            print("%-28s FAILED: %s" % (name, error))
            failed += 1
            continue

        prompt["corpus"] = digest
        # La langue attendue voyage avec le prompt : send.py note la reponse sans avoir a
        # relire la fixture, et un resultat archive reste lisible seul.
        prompt["language"] = data["language"]

        if args.show:
            print("=== system (%d chars) ===" % len(prompt["system"]))
            print(prompt["system"])
            print("=== user (%d chars) ===" % len(prompt["user"]))
            print(prompt["user"])
            return 0

        suffix = ".memory" if args.lane == "memory" else ""
        out_path = os.path.join(target, name + suffix + ".json")
        io.open(out_path, "w", encoding="utf-8", newline="\n").write(
            json.dumps(prompt, ensure_ascii=False, indent=2, sort_keys=True))
        print("%-28s %6d + %5d chars  -> %s"
              % (name, len(prompt["system"]), len(prompt["user"]),
                 os.path.relpath(out_path, HERE)))

    if failed:
        print("\n%d fixture(s) failed." % failed)
        return 1
    print("\nai_npc %s, corpus %s, %d prompt(s)." % (version, digest, len(paths)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
