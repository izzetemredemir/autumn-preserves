#!/usr/bin/env python3
"""Writes truck_bed.txt: the seasonal load in Walter's truck bed, 18x12 frames drawn over garden_truck.png at
truck pixel (44, 10) (garden_props.json "truck_bed"). Row 11 is the bed floor, just above the near rim, so the
loads sit inside the bed. Frames: hay and two pumpkins (days 1-7), grape crates (Grape Harvest), apple
baskets (Apple Moon), pumpkins and a folded plaid blanket with frost (First Frost).
  python3 tools/style/src/garden2/truck_bed_gen.py   (build.sh renders it)
"""
from parts import blank, part, place, write

W, H = 18, 12
PUMPKIN = part("""
...BV..
.AyAyA.
AyyAAAg
AyAAAgg
.AAggg.
""")
PUMPKIN_S = part("""
..BV.
.yAA.
yyAAg
AAAgg
""")
HAY = part("""
GGbGGGbGG
GyBGyGBGy
yybyyybyg
ygbyygbgy
yybyyybyg
gyBgyyBgg
ggbgggbgg
""")
CRATE = part("""
oooooooo
bBbbbbBb
oooooooo
bBbbbbBb
oooooooo
""")
GRAPES = part("""
...WcVV.
.WWDWWc.
WcWWDWcW
DWWDWWDW
""")
GRAPES_B = part("""
..cW.....
.WWDWcW..
WDWcWWDWV
DWWDWWDWW
""")
BASKET = part("""
gogogogo
ogogogog
gogogogo
.ogogog.
""")
APPLES = part("""
..rp..r.
.rprRrpR
rprRrprR
RrRRrRRr
""")
APPLES_B = part("""
...p.....
.rprRrp..
rprRrprRr
RrRRrRRrR
""")
BLANKET = part("""
CrCCCrCCCr
CrCCCrCCCr
RRRRRRRRRR
CrCCCrCCCr
crcccrcccr
CrCCCrCCCr
crcccrcccr
""")
FROST = [(2, 7), (4, 8), (12, 4), (15, 5), (8, 9)]


def frame(parts):
    g = blank(W, H)
    for rows, x, y in parts:
        place(g, rows, x, y, outline=True)
    return g


def main():
    hay = frame([(HAY, 9, 5), (PUMPKIN, 0, 7), (PUMPKIN_S, 5, 8)])
    grapes = frame([(GRAPES, 0, 3), (CRATE, 0, 7), (GRAPES_B, 9, 4), (CRATE, 10, 7)])
    apples = frame([(APPLES, 0, 4), (BASKET, 0, 8), (APPLES_B, 9, 5), (BASKET, 10, 8)])
    frost = frame([(BLANKET, 8, 5), (PUMPKIN, 0, 7), (PUMPKIN_S, 5, 8)])
    for x, y in FROST:
        if frost[y][x] not in (".", "k"):
            frost[y][x] = "C"
    write("truck_bed", "Seasonal load in the truck bed (ART-GARDEN2), 18x12 x4: hay_pumpkins, grape_crates,\n"
          "apple_baskets, pumpkins_blanket. Written by truck_bed_gen.py (outlined parts); drawn at truck (44, 10).",
          [hay, grapes, apples, frost])


if __name__ == "__main__":
    main()
