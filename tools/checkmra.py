#!/usr/bin/env python3
"""Assemble an MRA's ROM image from an unzipped ROM directory (parts matched by CRC, as for
merged sets) and compare it with sim/mkroms.py's rom.bin.
Usage: checkmra.py <mra> <rom dir> <rom.bin>"""
import os, sys, zlib
import xml.etree.ElementTree as ET

mra, romdir, ref = sys.argv[1:4]
by_crc = {}
for root, _, files in os.walk(romdir):
    for f in files:
        d = open(os.path.join(root, f), "rb").read()
        by_crc.setdefault(zlib.crc32(d), d)

img = b""
for p in ET.parse(mra).getroot().find("rom"):
    if p.tag != "part":
        continue
    if p.get("repeat"):
        img += bytes([int(p.text.strip(), 16)]) * int(p.get("repeat"), 0)
    else:
        img += by_crc[int(p.get("crc"), 16)]
want = open(ref, "rb").read()
print(f"{os.path.basename(mra)}: {len(img):#x} bytes, " + ("matches rom.bin" if img == want else "DIFFERS from rom.bin"))
