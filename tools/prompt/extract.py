# -*- coding: utf-8 -*-
"""Reads the mod's own sources into corpus.json.

    python tools\\prompt\\extract.py
    python tools\\prompt\\extract.py --check      # fails if corpus.json is stale

corpus.json is the ONE file the offline prompt builder reads, and nothing writes it by hand.
It carries three things: the cast sheets, the built-in section texts, and the assembly frame
of AiNpcBuildSystemPrompt -- the ordered list of blocks the mod actually emits. The builder
walks that frame rather than a copy of it, so a block added, removed or reordered in the
.reds is added, removed or reordered offline on the next extraction, and a block whose shape
this tooling has never seen stops the extraction instead of vanishing from the prompt.

--check is what belongs in a test suite: it re-extracts into memory and compares. A red line
there means the sources moved and the corpus did not, which is the only way an offline prompt
can quietly stop matching the one the game sends.
"""

import argparse
import hashlib
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from castreader import CastReader, check_fields, normalise      # noqa: E402
from redsvalue import RedsParseError                            # noqa: E402
from sectionreader import SOURCES, read_all                     # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
SCRIPTS = os.path.join(REPO, "src", "r6", "scripts", "ai_npc")
CAST = os.path.join(SCRIPTS, "cast")
CORPUS = os.path.join(HERE, "corpus.json")


def use_utf8_stdout():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass


def digest(path):
    return hashlib.sha1(io.open(path, "rb").read()).hexdigest()[:12]


def build_corpus():
    """Everything the offline builder needs, read from the .reds sources."""
    reader = CastReader(CAST)
    cast = {}
    for function in reader.sheet_names():
        sheet = normalise(reader.read(function))
        if not sheet["contactId"]:
            raise RedsParseError("%s has no contactId" % function)
        cast[sheet["contactId"]] = sheet

    sections = read_all(SCRIPTS)

    # Which files the corpus was read from, and what they hashed to. A stale corpus is
    # visible from this block alone, without re-running the readers.
    sources = {}
    for name in sorted(SOURCES):
        sources[name] = digest(os.path.join(SCRIPTS, name))
    for name in sorted(os.listdir(CAST)):
        if name.endswith(".reds"):
            sources["cast/" + name] = digest(os.path.join(CAST, name))

    unknown = check_fields(io.open(
        os.path.join(SCRIPTS, "AiNpcConfigModel.reds"), encoding="utf-8").read())

    return {
        "modVersion": sections["version"],
        "sources": sources,
        "unknownSheetFields": unknown,
        "cast": cast,
        "sections": sections,
    }


def load():
    """The corpus as it stands on disk. Raises if it was never extracted."""
    if not os.path.exists(CORPUS):
        raise IOError("no corpus.json -- run: python tools\\prompt\\extract.py")
    return json.load(io.open(CORPUS, encoding="utf-8"))


def dump(corpus):
    return json.dumps(corpus, ensure_ascii=False, indent=2, sort_keys=True)


def main(argv=None):
    use_utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="compare with corpus.json instead of writing it")
    args = parser.parse_args(argv)

    try:
        corpus = build_corpus()
    except RedsParseError as error:
        print("EXTRACTION FAILED: %s" % error)
        print("A construct in the sources is one this reader does not handle. Teach it the "
              "shape rather than editing corpus.json by hand.")
        return 1

    text = dump(corpus)

    if args.check:
        if not os.path.exists(CORPUS):
            print("corpus.json is missing -- run tools\\prompt\\extract.py")
            return 1
        current = io.open(CORPUS, encoding="utf-8").read()
        if current != text:
            print("corpus.json is STALE: the .reds sources have moved since it was written.")
            print("Run: python tools\\prompt\\extract.py")
            return 1
        print("corpus.json is current (ai_npc %s, %d contacts)."
              % (corpus["modVersion"], len(corpus["cast"])))
        return 0

    io.open(CORPUS, "w", encoding="utf-8", newline="\n").write(text)
    print("corpus.json written: ai_npc %s, %d contacts, %d sections."
          % (corpus["modVersion"], len(corpus["cast"]), len(corpus["sections"])))
    if corpus["unknownSheetFields"]:
        print("NOTE: AiNpcCharacterDef declares fields this tooling ignores: %s"
              % ", ".join(corpus["unknownSheetFields"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
