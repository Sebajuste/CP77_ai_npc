# -*- coding: utf-8 -*-
"""Fixtures in, prompts out. The whole point of this directory.

    python tools\\prompt\\generate.py                       # every fixture
    python tools\\prompt\\generate.py --fixture river-*      # some of them
    python tools\\prompt\\generate.py --pass thinking        # the compaction, not the reply
    python tools\\prompt\\generate.py --recipe compact       # a cheaper prompt, from the template
    python tools\\prompt\\generate.py --recipes recipes.json --recipe mine
    python tools\\prompt\\generate.py --out D:\\runs\\0.9.5    # somewhere else
    python tools\\prompt\\generate.py --print river-night-shift

Each fixture becomes one file under out\\<mod version>\\<fixture>.<pass>[.<recipe>].json, holding
exactly what the mod would POST -- a system message and a user message -- plus the version and
the corpus hash they were built from. That last part is what makes a provider comparison mean
something later: a run is attached to the ai_npc it was produced by, and two runs of different
versions never get quietly averaged together. The pass and the recipe are in the name for the
same reason: two prompts built from one fixture are two different requests, and a bench that
mixed them would average a trimmed prompt with a full one.

TWO PASSES ARE BUILT HERE, and it is the two a fixture can describe on its own. `repair` and
`actions` both read a reply a model has already written -- a run's output, not a fixture's
input -- so they are built by whoever holds those replies, through passes.py. See
ai_npc_lab\\action-bench.

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
import passes                                           # noqa: E402
import recipe as recipes                                # noqa: E402
from build import BuildError                            # noqa: E402
from recipe import RecipeError                          # noqa: E402

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


def main(argv=None):
    use_utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", nargs="*", default=None,
                        help="fixture name or glob; every fixture by default")
    parser.add_argument("--out", default=OUT, help="where the prompts are written")
    parser.add_argument("--pass", dest="which", default="speaking",
                        choices=list(passes.FROM_FIXTURE),
                        help="quelle passe construire. `speaking` est celle qui repond au "
                             "joueur ; `thinking` est la compaction qui tourne dans son dos "
                             "toutes les seize turns, et dont l echec est muet. Les deux "
                             "autres passes du mod, repair et actions, lisent une reponse "
                             "deja ecrite : elles se batissent par passes.py")
    parser.add_argument("--recipe", default=None,
                        help="quelle recette rend le prompt systeme. Par defaut : celle que "
                             "le gabarit livre declare active, qui rend tout. Une recette ne "
                             "concerne que la passe speaking")
    parser.add_argument("--recipes", default=None, metavar="FICHIER",
                        help="un recipes.json a lire, au lieu du gabarit livre avec le mod")
    parser.add_argument("--print", dest="show", default=None,
                        help="print one fixture's prompt instead of writing it")
    args = parser.parse_args(argv)

    corpus = extract.load()
    passes.check(corpus)
    digest = corpus_hash(corpus)
    version = corpus["modVersion"]

    try:
        recipe = recipes.load(corpus, args.recipes, args.recipe)
    except RecipeError as error:
        print("RECIPE REFUSED:\n%s" % error)
        return 1
    for issue in recipe.issues:
        print("%s" % issue)

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
            prompt = (passes.thinking(corpus, data) if args.which == "thinking"
                      else passes.speaking(corpus, data, recipe))
            prompt["pass"] = args.which
            prompt["modVersion"] = version
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

        # The pass and the recipe are part of the name, because they are part of the
        # request: the compaction of a fixture and its reply are two files, and the same
        # reply under two recipes is two more. The recipe appears only where it decided
        # something -- the compaction builds both its halves itself.
        parts = [name, args.which]
        if prompt.get("recipe"):
            parts.append(prompt["recipe"])
        out_path = os.path.join(target, ".".join(parts) + ".json")
        io.open(out_path, "w", encoding="utf-8", newline="\n").write(
            json.dumps(prompt, ensure_ascii=False, indent=2, sort_keys=True))
        print("%-28s %6d + %5d chars  -> %s"
              % (name, len(prompt["system"]), len(prompt["user"]),
                 os.path.relpath(out_path, HERE)))

    if failed:
        print("\n%d fixture(s) failed." % failed)
        return 1
    print("\nai_npc %s, corpus %s, pass %s, recipe %s, %d prompt(s)."
          % (version, digest, args.which, recipe.name, len(paths)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
