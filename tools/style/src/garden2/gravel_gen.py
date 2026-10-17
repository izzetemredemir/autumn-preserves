#!/usr/bin/env python3
"""Writes gravel.txt: the gravel patch under Walter's truck (76x22, a ground decal, no outline).

A ragged ellipse of small stones (stone ramp, a few cream and bark specks), darker where the truck shades it,
with a few fallen leaves on top. Deterministic (fixed seed), so re-running gives the same patch.
  python3 tools/style/src/garden2/gravel_gen.py   (build.sh runs it, then renders gravel.txt)
"""
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 76, 22
CX, CY, RX, RY = 37.5, 12.0, 37.0, 9.6
# Shadow under the truck body (patch coordinates): the truck stands at patch x 6..69, its wheels touch y 20.
SHADOW = (12, 14, 66, 21)


def main():
    rnd = random.Random(1950)
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            d = ((x + 0.5 - CX) / RX) ** 2 + ((y + 0.5 - CY) / RY) ** 2
            edge = 0.78 + 0.22 * rnd.random()
            if d > edge:
                row.append(".")
                continue
            shade = SHADOW[0] <= x <= SHADOW[2] and SHADOW[1] <= y <= SHADOW[3]
            r = rnd.random()
            if shade:
                ch = "t" if r < 0.55 else ("x" if r < 0.8 else "m")
            elif r < 0.50:
                ch = "m"
            elif r < 0.72:
                ch = "s"
            elif r < 0.88:
                ch = "t"
            elif r < 0.95:
                ch = "c"
            else:
                ch = "B"
            row.append(ch)
        rows.append(row)
    # a few leaves blown onto the gravel (outside the shadow)
    for x, y, a, b in [(4, 9, "r", "R"), (71, 10, "A", "g"), (8, 17, "A", "g"), (69, 16, "r", "R"), (40, 4, "y", "A")]:
        if rows[y][x] != ".":
            rows[y][x] = a
            rows[y][x + 1] = a
            rows[y + 1][x] = b
    lines = ["# Gravel patch under the truck (ART-GARDEN2), 76x22, ground decal drawn under everything (z back).",
             "# Written by gravel_gen.py; no outline.", "legend . transparent"]
    for k, v in [("m", "stone_500"), ("s", "stone_300"), ("t", "stone_700"), ("x", "slate_900"), ("c", "cream_400"),
                 ("B", "bark_900"), ("r", "leaf_red_500"), ("R", "leaf_red_700"), ("A", "amber_600"),
                 ("g", "gold_700"), ("y", "gold_300")]:
        lines.append(f"legend {k} {v}")
    lines.append("frame")
    lines += ["".join(r) for r in rows]
    with open(os.path.join(HERE, "gravel.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
