# Locate a depot path inside the base game archives, by hash.
#
# An archive stores only FNV1a64 of the lowercase depot path, so a file is found by
# hashing a candidate name rather than by listing anything. Build the set once, then
# test as many candidates as we like.
import glob
import os
import struct
import sys

CONTENT = r"D:\Jeux\Cyberpunk 2077\archive\pc\content"

MASK = 0xFFFFFFFFFFFFFFFF


def fnv1a64(text):
    h = 0xCBF29CE484222325
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * 0x100000001B3) & MASK
    return h


def entry_hashes(path):
    with open(path, "rb") as handle:
        data = handle.read(64)
        magic, _version = struct.unpack_from("<4sI", data, 0)
        if magic != b"RDAR":
            return []
        index_pos, = struct.unpack_from("<Q", data, 8)
        index_size, = struct.unpack_from("<I", data, 16)
        handle.seek(index_pos)
        index = handle.read(index_size)
    _ft_offset, _ft_size, _crc, count, _segments, _deps = struct.unpack_from("<IIQIII", index, 0)
    base = 8 + 8 + 12
    out = []
    for i in range(count):
        name_hash, = struct.unpack_from("<Q", index, base + i * 56)
        out.append(name_hash)
    return out


def build_index():
    table = {}
    for archive in sorted(glob.glob(os.path.join(CONTENT, "*.archive"))):
        for h in entry_hashes(archive):
            table.setdefault(h, os.path.basename(archive))
    return table


def main():
    table = build_index()
    sys.stderr.write("%d entries indexed\n" % len(table))
    found = 0
    for line in sys.stdin:
        candidate = line.strip()
        if not candidate:
            continue
        where = table.get(fnv1a64(candidate.lower()))
        if where:
            found += 1
            print("FOUND  %-70s %s" % (candidate, where))
    sys.stderr.write("%d hit(s)\n" % found)


main()
