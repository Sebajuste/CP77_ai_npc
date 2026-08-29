#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Finds -- and removes -- malformed UTF-8 bytes in what the mod has written to disk.

WHY THIS EXISTS

A stray byte in a stored message is invisible from inside the game and fatal to one
contact. The mod re-reads the whole conversation into every request, so a single malformed
byte filed once makes every later request for that contact malformed too; the http client
refuses to send it and the answer is status 0 -- no status, no log line, nothing to read.
The chat simply stops working, on every surface, and it reads in game like a network
problem. That is a full evening of debugging a launch flag that was already correct
(2026-08-22).

REDscript cannot see a byte, so it cannot find this from the inside. This tool can, offline,
without launching the game -- and it is the only thing that can repair a history that was
written before the mod stopped producing the byte in the first place. The production side is
fixed in AiNpcUtf8.reds; this is for what is already on disk.

  python tools\\utf8.py                          # report on the game's storage
  python tools\\utf8.py --storage <dir>          # somewhere else
  python tools\\utf8.py --repair                 # drop the bad bytes, keeping a backup

Quit the game to desktop before repairing: the store appends to these files live, and a
session running over a rewritten file would append to something it no longer matches.
"""

import argparse
import io
import os
import sys

DEFAULT_STORAGE = r"D:\Jeux\Cyberpunk 2077\r6\storages\AiNpc"

# Long enough to recognise the sentence, short enough to stay on one terminal line.
CONTEXT_BEFORE = 60
CONTEXT_AFTER = 30


def scan(data):
    """Byte offsets that are not part of well-formed UTF-8.

    Decoding is done by the standard library and only the offsets it rejects are collected,
    so what counts as malformed here is exactly what counts as malformed for anything else
    reading these files -- rather than a hand-written table of lead bytes that would drift.
    """
    offsets = []
    start = 0
    while start < len(data):
        try:
            data[start:].decode("utf-8")
            break
        except UnicodeDecodeError as error:
            bad = start + error.start
            offsets.append(bad)
            start = start + error.end
    return offsets


def render(data, offset):
    """The bad byte in its sentence, so a reader can tell what was being said."""
    before = data[max(0, offset - CONTEXT_BEFORE):offset].decode("utf-8", "replace")
    after = data[offset + 1:offset + 1 + CONTEXT_AFTER].decode("utf-8", "replace")
    return "%s <0x%02X> %s" % (before, data[offset], after)


def repair(data, offsets):
    """Drops the offending bytes and nothing else.

    Dropping rather than substituting: a replacement character would be a NEW character in
    the middle of a line a character supposedly said, and it would travel into the next
    prompt as if it had been typed. Half an accent is best read as never written.
    """
    keep = bytearray()
    bad = set(offsets)
    for index, byte in enumerate(data):
        if index not in bad:
            keep.append(byte)
    return bytes(keep)


def backup(path):
    """Never overwrites an existing backup: a second repair must not eat the first one.

    Copied as BYTES, unlike journal.py's text backup -- the whole subject here is a file
    that cannot be decoded, and a text round trip would rewrite the very byte being kept.
    """
    n = 0
    while True:
        candidate = "%s.bak%s" % (path, "" if n == 0 else str(n))
        if not os.path.exists(candidate):
            break
        n += 1
    with io.open(path, "rb") as src:
        content = src.read()
    with io.open(candidate, "wb") as dst:
        dst.write(content)
    return candidate


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--storage", default=DEFAULT_STORAGE,
                        help="Folder to scan. Defaults to the game's AiNpc storage.")
    parser.add_argument("--repair", action="store_true",
                        help="Rewrite the affected files without the bad bytes, keeping a backup.")
    args = parser.parse_args()

    if not os.path.isdir(args.storage):
        print("not a folder: %s" % args.storage)
        return 2

    scanned = 0
    damaged = 0
    for root, _, files in os.walk(args.storage):
        for name in sorted(files):
            # A backup is a snapshot of a file that was broken on purpose; reporting it as a
            # finding would make every repair look like it had failed.
            if ".bak" in name:
                continue
            path = os.path.join(root, name)
            with io.open(path, "rb") as handle:
                data = handle.read()
            scanned += 1

            offsets = scan(data)
            if not offsets:
                continue

            damaged += 1
            print("")
            print("%s -- %d malformed byte(s)" % (path, len(offsets)))
            for offset in offsets:
                print("  @%d  %s" % (offset, render(data, offset)))

            if args.repair:
                saved = backup(path)
                with io.open(path, "wb") as handle:
                    handle.write(repair(data, offsets))
                print("  repaired, backup: %s" % saved)

    print("")
    print("%d file(s) scanned, %d damaged." % (scanned, damaged))
    if damaged and not args.repair:
        print("Pass --repair to drop the bad bytes (the game must be closed).")
    return 1 if damaged and not args.repair else 0


if __name__ == "__main__":
    sys.exit(main())
