# Pull ONE file out of a base game archive, by depot path.
#
# The whole-archive extractor next door writes every entry; basegame_4_gamedata is far too
# large for that to be reasonable when the target is four quest files. Same segment rules --
# only the first segment is the CR2W and only it is decompressed.
import ctypes
import mmap
import os
import struct
import sys

OODLE = r"D:\Jeux\Cyberpunk 2077\bin\x64\oo2ext_7_win64.dll"
MASK = 0xFFFFFFFFFFFFFFFF

_lib = ctypes.WinDLL(OODLE)
_dec = _lib.OodleLZ_Decompress
_dec.restype = ctypes.c_int64
_dec.argtypes = [ctypes.c_char_p, ctypes.c_int64, ctypes.c_char_p, ctypes.c_int64,
                 ctypes.c_int32, ctypes.c_int32, ctypes.c_int32,
                 ctypes.c_void_p, ctypes.c_int64, ctypes.c_void_p, ctypes.c_void_p,
                 ctypes.c_void_p, ctypes.c_int64, ctypes.c_int32]


def oodle(src, out_size):
    dst = ctypes.create_string_buffer(out_size)
    n = _dec(src, len(src), dst, out_size, 0, 0, 0, None, 0, None, None, None, 0, 3)
    if n != out_size:
        raise RuntimeError("oodle failed %d != %d" % (n, out_size))
    return dst.raw[:out_size]


def fnv1a64(text):
    h = 0xCBF29CE484222325
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * 0x100000001B3) & MASK
    return h


def pull(archive, depot_path, out_path):
    want = fnv1a64(depot_path.lower())
    with open(archive, "rb") as handle:
        data = mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ)
        index_pos, = struct.unpack_from("<Q", data, 8)
        index_size, = struct.unpack_from("<I", data, 16)
        _fto, _fts, _crc, count, segments, _deps = struct.unpack_from("<IIQIII", data, index_pos)
        base = index_pos + 8 + 8 + 12
        target = None
        for i in range(count):
            name_hash, _ts, _inline, seg_start, seg_end, _ds, _de = struct.unpack_from(
                "<QQIIIII", data, base + i * 56)
            if name_hash == want:
                target = (seg_start, seg_end)
                break
        if target is None:
            raise SystemExit("not in %s: %s" % (os.path.basename(archive), depot_path))

        seg_base = base + count * 56
        out = bytearray()
        seg_start, seg_end = target
        for si in range(seg_start, seg_end):
            offset, disk, size = struct.unpack_from("<QII", data, seg_base + si * 16)
            blob = data[offset:offset + disk]
            if si > seg_start or disk == size:
                out += blob
            elif blob[:4] == b"KARK":
                usize, = struct.unpack_from("<I", blob, 4)
                out += oodle(blob[8:], usize)
            else:
                out += oodle(blob, size)
        data.close()

    with open(out_path, "wb") as handle:
        handle.write(bytes(out))
    print("%s  ->  %s  (%d bytes)" % (depot_path, out_path, len(out)))


if __name__ == "__main__":
    pull(sys.argv[1], sys.argv[2], sys.argv[3])
