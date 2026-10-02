#!/usr/bin/env python3
"""Convert a MAME Fire Trap ROM set into $readmemh files for simulation.
Usage: mkroms.py <dir with unzipped ROMs> <output dir> [set]   (set: firetrap, firetrapa, firetrapj)
Files are found by CRC32 anywhere under the directory (merged sets keep clone files in
subfolders, not always under the clone's own name)."""
import os
import sys
import zlib

# (name, CRC32) as in MAME 0.289 firetrap.cpp
MAIN = {
    "firetrap":  [("di-02.4a", 0x3d1e4bf7), ("di-01.3a", 0x9bbae38b), ("di-00-a.2a", 0xf39e2cf4)],
    "firetrapa": [("di-02.4a", 0x3d1e4bf7), ("di-01.3a", 0x9bbae38b), ("di-00.2a", 0xd0dad7de)],
    "firetrapj": [("fi-03.4a", 0x20b2a4ff), ("fi-02.3a", 0x5c8a0562), ("fi-01.2a", 0xf2412fe8)],
}
MCU = {"firetrap": 0x6340a4d7, "firetrapa": 0x6340a4d7, "firetrapj": 0xe531a633}
CHR = {"firetrap": 0x46721930, "firetrapa": 0x46721930, "firetrapj": 0xa584fc16}
SND = [("snd 10j", 0x8605f6b9), ("snd 12j", 0x49508c93)]
PROM = [("3b", 0x8bb45337), ("4b", 0xd5abfc64), ("1a", 0xd67f3514)]

src, dst = sys.argv[1], sys.argv[2]
name = sys.argv[3] if len(sys.argv) > 3 else "firetrap"

by_crc = {}
for root, _, files in os.walk(src):
    for f in files:
        data = open(os.path.join(root, f), "rb").read()
        by_crc.setdefault(zlib.crc32(data), data)

def get(crc, label):
    if crc not in by_crc:
        sys.exit(f"missing {label} (CRC {crc:08x})")
    return by_crc[crc]

regions = {
    "main.hex": b"".join(get(c, n) for n, c in MAIN[name]),
    "snd.hex":  b"".join(get(c, n) for n, c in SND),
    "mcu.hex":  get(MCU[name], "mcu"),
    "chr.hex":  get(CHR[name], "chars"),
    "prom.hex": b"".join(get(c, n) for n, c in PROM),
}
os.makedirs(dst, exist_ok=True)
for out, data in regions.items():
    with open(os.path.join(dst, out), "w") as fh:
        fh.write("\n".join(f"{b:02x}" for b in data) + "\n")
    print(f"{out}: {len(data)} bytes")
