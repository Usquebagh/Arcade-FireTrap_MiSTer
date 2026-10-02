#!/usr/bin/env python3
"""Side-by-side of simulation frames and MAME reference frames, plus a diff image.
Usage: compare.py <out.png> <sim.png|ppm> <mame.png> [...pairs]
MAME references are native (-norotate) 256x240 snapshots."""
import sys
from PIL import Image, ImageChops, ImageDraw

out, pairs = sys.argv[1], list(zip(sys.argv[2::2], sys.argv[3::2]))
W, H = 256, 240
sheet = Image.new("RGB", (W * 3 + 8, len(pairs) * (H + 14)), "gray")
d = ImageDraw.Draw(sheet)
for i, (a, b) in enumerate(pairs):
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB")
    diff = ImageChops.difference(ia, ib)
    bad = sum(1 for p in diff.getdata() if max(p) > 24)
    print(f"{a} vs {b}: {bad} px differ")
    y = i * (H + 14)
    for j, (img, label) in enumerate([(ia, a), (ib, b), (diff.point(lambda v: min(255, v * 4)), f"diff: {bad} px")]):
        sheet.paste(img, (j * (W + 4), y + 14))
        d.text((j * (W + 4) + 2, y + 1), label.rsplit("/", 1)[-1], fill="yellow")
sheet.save(out)
