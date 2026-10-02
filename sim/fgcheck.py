#!/usr/bin/env python3
"""FG-layer check: compare only the pixels the simulation draws (non-black), so missing
layers don't count. For each sim frame, report the best-matching MAME frame within +-R.
Usage: fgcheck.py <sim dir> <mame dir> <first> <last> [R]"""
import os
import sys
from PIL import Image

sim_dir, ref_dir, first, last = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
R = int(sys.argv[5]) if len(sys.argv) > 5 else 3

def load(p):
    return Image.open(p).convert("RGB").load() if os.path.exists(p) else None

refs = {n: load(f"{ref_dir}/mame_{n:04d}.png") for n in range(first - R, last + R + 1)}
for n in range(first, last + 1):
    s = load(f"{sim_dir}/frame_{n:04d}.png")
    if s is None:
        continue
    pts = [(x, y) for y in range(240) for x in range(256) if s[x, y] != (0, 0, 0)]
    best = None
    for m in range(n - R, n + R + 1):
        r = refs.get(m)
        if r is None:
            continue
        bad = sum(1 for (x, y) in pts if max(abs(a - b) for a, b in zip(s[x, y], r[x, y])) > 24)
        if best is None or bad < best[1]:
            best = (m, bad)
    print(f"sim {n}: {len(pts)} FG px, best MAME frame {best[0]} ({best[0] - n:+d}) with {best[1]} mismatches")
