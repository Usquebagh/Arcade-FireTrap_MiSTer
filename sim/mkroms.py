#!/usr/bin/env python3
"""Build the MRA-layout ROM image (docs/hardware.md) from a MAME Fire Trap ROM set.
Usage: mkroms.py <dir with unzipped ROMs> <output dir> [set]   (set: firetrap, firetrapa, firetrapj)
Writes rom.bin. Files are found by CRC32 anywhere under the directory (merged sets keep clone
files in subfolders, not always under the clone's own name)."""
import os
import sys
import zlib

# CRC32s as in MAME 0.289 firetrap.cpp
MAIN = {
    "firetrap":  [0x3d1e4bf7, 0x9bbae38b, 0xf39e2cf4],   # di-02.4a, di-01.3a, di-00-a.2a
    "firetrapa": [0x3d1e4bf7, 0x9bbae38b, 0xd0dad7de],   # di-02.4a, di-01.3a, di-00.2a
    "firetrapj": [0x20b2a4ff, 0x5c8a0562, 0xf2412fe8],   # fi-03.4a, fi-02.3a, fi-01.2a
}
SND  = [0x8605f6b9, 0x49508c93]                          # 10j, 12j
MCU  = {"firetrap": 0x6340a4d7, "firetrapa": 0x6340a4d7, "firetrapj": 0xe531a633}
CHR  = {"firetrap": 0x46721930, "firetrapa": 0x46721930, "firetrapj": 0xa584fc16}
PROM = [0x8bb45337, 0xd5abfc64, 0xd67f3514]              # 3b, 4b, 1a
BG1  = [0x441d9154, 0x8e6e7eec, 0xef0a7e23, 0xec080082]  # 3e, 2e, 6e, 4e
BG2  = [0xd11e28e8, 0xc32a21d8, 0x6424d5c3, 0x9b89300a]  # 3j, 2j, 6j, 4j
OBJ  = {                                                 # 17h, 13h, 14h, 15h
    "firetrap":  [0x0de055d7, 0x869219da, 0x6b65812e, 0x3e27f77d],
    "firetrapa": [0x0de055d7, 0x869219da, 0x6b65812e, 0x3e27f77d],
    "firetrapj": [0x0de055d7, 0xdbcdd3df, 0x6b65812e, 0x3e27f77d],
}

src, dst = sys.argv[1], sys.argv[2]
name = sys.argv[3] if len(sys.argv) > 3 else "firetrap"

by_crc = {}
for root, _, files in os.walk(src):
    for f in files:
        data = open(os.path.join(root, f), "rb").read()
        by_crc.setdefault(zlib.crc32(data), data)

def get(crcs):
    out = b""
    for c in crcs:
        if c not in by_crc:
            sys.exit(f"missing ROM with CRC {c:08x}")
        out += by_crc[c]
    return out

img = get(MAIN[name]) + get(SND) + get([MCU[name]]) + get([CHR[name]]) + get(PROM)
assert len(img) == 0x2B300
img += b"\xff" * (0x2C000 - len(img))
img += get(BG1) + get(BG2) + get(OBJ[name])
assert len(img) == 0x8C000
os.makedirs(dst, exist_ok=True)
open(os.path.join(dst, "rom.bin"), "wb").write(img)
print(f"rom.bin: {len(img)} bytes")
