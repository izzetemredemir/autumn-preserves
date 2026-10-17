#!/usr/bin/env python3
"""Rough layout guide for bg_market (ART-MARKET): pieces of bg_town plus blocky stand-ins for the stalls.

The edit model redraws this as one painting (image 1 = this guide, image 2 = bg_town as the style reference),
so the open cobbles (Granny's stall area, the back lane, the front lane, the side gaps) land where the
market layout needs them. Output: tools/style/raw/market_guide.png (480x270) and a x2 copy for the upload.
  python3 tools/style/src/market/market_guide.py
"""
from PIL import Image, ImageDraw

TOWN = "game/assets/sprites/scenes/bg_town.png"
OUT = "tools/style/raw/market_guide.png"
OUT2 = "tools/style/raw/market_guide_x2.png"

INK = "#111010"
BARK9, BARK7, BARK5 = "#50361e", "#83571e", "#c58845"
RED7, RED5, PEACH = "#a22512", "#c94d2e", "#e19064"
GOLD7, AMBER, GOLD3, GOLD2 = "#9b8039", "#b66813", "#e5bd7f", "#dbcc83"
CREAM4, CREAM1 = "#b9a697", "#f2d9c5"
OLIVE8, OLIVE6, OLIVE5 = "#53612e", "#747c37", "#b1a13d"
PLUM, WINE = "#3d1f29", "#62272c"
STONE7, STONE5 = "#49423d", "#81746a"


def main():
    town = Image.open(TOWN).convert("RGB")
    im = Image.new("RGB", (480, 270))
    # cobbles everywhere: the town's open lower band, tiled
    cob = town.crop((0, 196, 480, 270))
    for y in range(-30, 270, cob.height):
        im.paste(cob, (0, y))
    # tree band across the top (the big maple canopy, tiled)
    canopy = town.crop((150, 0, 330, 96))
    for x in (-60, 120, 300):
        im.paste(canopy, (x, 0))
    d = ImageDraw.Draw(im)
    # low hedge / bushes behind the back row
    d.rectangle((0, 88, 480, 118), fill=OLIVE8)
    for x in range(0, 480, 14):
        d.ellipse((x - 4, 80, x + 14, 104), fill=OLIVE6 if x % 28 else RED5)
    # post office, right back (town piece, lifted so its steps meet the back lane at y 122)
    po = town.crop((312, 0, 480, 172))
    po = po.resize((po.width * 4 // 5, po.height * 4 // 5), Image.NEAREST)
    im.paste(po, (346, -16))
    d.rectangle((346, 118, 480, 124), fill=STONE5)

    # --- back row (ground line y 122) ---
    # Rosie's bread stall, left back
    stall(d, 14, 26, 128, 122, (RED5, CREAM1))
    for i in range(5):  # loaves and round breads on the counter
        x = 26 + i * 21
        d.ellipse((x, 78, x + 16, 90), fill=AMBER, outline=BARK9)
        d.line((x + 4, 82, x + 12, 82), fill=GOLD3)
    for x in (24, 98):  # baskets with baguettes in front
        d.rectangle((x, 100, x + 20, 116), fill=BARK5, outline=BARK9)
        d.line((x + 4, 92, x + 8, 104), fill=GOLD3, width=3)
        d.line((x + 12, 90, x + 14, 104), fill=GOLD3, width=3)
    # Vito's grapes and wine barrels, centre back (above Granny's stall)
    stall(d, 186, 34, 294, 120, (WINE, CREAM1))
    for i in range(5):  # grape bunches
        x = 196 + i * 19
        for j in range(3):
            d.ellipse((x + j * 3, 84 + j * 3, x + 10 - j * 2, 92 + j * 3), fill=PLUM if (i + j) % 2 else WINE)
    for x in (160, 300):  # barrels on both sides
        barrel(d, x, 88, 22, 32)
    barrel(d, 168, 72, 18, 18)

    # --- front row (ground line y 212) ---
    # Barnaby's produce cart, left front
    d.rectangle((14, 172, 120, 200), fill=BARK7, outline=BARK9)
    for y in (180, 190):
        d.line((16, y, 118, y), fill=BARK9)
    d.line((120, 186, 144, 198), fill=BARK9, width=3)  # cart handle
    for cx in (34, 100):  # wheels
        d.ellipse((cx - 13, 186, cx + 13, 212), fill=BARK9, outline=INK)
        d.ellipse((cx - 8, 191, cx + 8, 207), fill=BARK5)
    piles = [(20, AMBER), (38, RED5), (56, OLIVE6), (74, AMBER), (92, RED7), (106, OLIVE5)]
    for x, c in piles:
        d.ellipse((x, 156, x + 18, 176), fill=c, outline=BARK9)
    d.rectangle((8, 136, 126, 150), fill=OLIVE6)  # small canopy on two poles
    for x in range(8, 126, 12):
        d.rectangle((x, 136, x + 5, 150), fill=CREAM1)
    for x in (12, 120):
        d.line((x, 150, x, 172), fill=BARK9, width=2)
    # Edith's flowers and books, right front
    stall(d, 356, 130, 470, 212, (OLIVE6, CREAM1), counter=176)
    for i, c in enumerate((RED5, GOLD3, PEACH, RED7, GOLD2)):  # flower buckets
        x = 364 + i * 20
        d.rectangle((x + 2, 186, x + 14, 208), fill=STONE5, outline=STONE7)
        d.ellipse((x - 2, 172, x + 18, 190), fill=c, outline=BARK9)
    for i, c in enumerate((RED7, OLIVE8, AMBER, WINE)):  # book stacks on the counter
        x = 370 + i * 24
        for j in range(3):
            d.rectangle((x, 166 - j * 5, x + 16, 170 - j * 5), fill=c if j % 2 else CREAM4, outline=BARK9)

    # lamp posts with lanterns between the stalls
    for x in (146, 334):
        d.rectangle((x - 1, 54, x + 2, 214), fill=STONE7)
        d.rectangle((x - 5, 52, x + 6, 66), fill=GOLD2, outline=BARK9)
        d.rectangle((x - 3, 212, x + 4, 216), fill=STONE7)
    # bunting garlands (two swags across the square)
    for (x0, y0, x1, y1, sag) in ((0, 18, 146, 54, 16), (146, 54, 334, 54, 22), (334, 54, 400, 30, 12),
                                  (0, 52, 146, 58, 10), (334, 58, 480, 44, 10)):
        swag(d, x0, y0, x1, y1, sag)
    im.save(OUT)
    im.resize((960, 540), Image.NEAREST).save(OUT2)
    print(OUT, OUT2)


def stall(d, x0, y0, x1, y1, stripes, counter=None):
    """Awning stall in front view: stripes on top, posts, a plank counter."""
    cy = counter if counter is not None else y1 - 40
    d.rectangle((x0 + 4, y0 + 20, x1 - 4, cy), fill=BARK9)  # dark inside
    for x in (x0 + 2, x1 - 6):
        d.rectangle((x, y0, x + 4, y1), fill=BARK7, outline=BARK9)
    a, b = stripes
    for i, x in enumerate(range(x0 - 4, x1 + 4, 10)):
        d.rectangle((x, y0, min(x + 9, x1 + 4), y0 + 22), fill=a if i % 2 == 0 else b)
        d.ellipse((x, y0 + 18, min(x + 9, x1 + 4), y0 + 28), fill=a if i % 2 == 0 else b)
    d.rectangle((x0, cy, x1, y1 - 2), fill=BARK7, outline=BARK9)  # counter front
    d.rectangle((x0, cy, x1, cy + 4), fill=BARK5)


def barrel(d, x, y, w, h):
    d.rounded_rectangle((x, y, x + w, y + h), radius=5, fill=BARK7, outline=BARK9)
    for yy in (y + h // 4, y + 3 * h // 4):
        d.line((x + 1, yy, x + w - 1, yy), fill=STONE7, width=2)
    d.line((x + 3, y + 2, x + 3, y + h - 3), fill=BARK5)


def swag(d, x0, y0, x1, y1, sag):
    cols = (RED5, GOLD3, OLIVE6, CREAM1, AMBER)
    n = max(2, (x1 - x0) // 10)
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t + sag * 4 * t * (1 - t)))
    d.line(pts, fill=BARK9, width=1)
    for i in range(1, n):
        x, y = pts[i]
        d.polygon([(x - 3, y), (x + 3, y), (x, y + 7)], fill=cols[i % len(cols)])


if __name__ == "__main__":
    main()
