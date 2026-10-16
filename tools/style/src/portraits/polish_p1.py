#!/usr/bin/env python3
"""ART-POLISH-2: hand clean-up of the P1 portraits (Vito, Edith, Mia). Palette colours only, no generation.
Run from the repo root on the ORIGINAL portraits (git checkout the three PNGs first to re-run):
  python3 tools/style/src/portraits/polish_p1.py
- all: despeckle skin noise inside the face box
- Vito: red vest -> plum/brown
- Edith: round glasses with a readable rim, bridge and lens glint
- Mia: raincoat a stronger yellow
"""
import pathlib
from PIL import Image

DIR = pathlib.Path("game/assets/sprites/portraits")
SKIN = {"e5bd7f", "e19064", "f2d9c5", "c58845"}


def hx(p):
    return "%02x%02x%02x" % p[:3]


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def despeckle(im, box, passes=2):
    px = im.load()
    x0, y0, x1, y1 = box
    for _ in range(passes):
        src = im.copy().load()
        for y in range(y0, y1):
            for x in range(x0, x1):
                p = src[x, y]
                if not p[3] or hx(p) not in SKIN:
                    continue
                nb = [src[x + dx, y + dy] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
                if any(hx(n) == hx(p) for n in nb if n[3]):
                    continue
                cand = [hx(n) for n in nb if n[3] and hx(n) in SKIN]
                if cand:
                    px[x, y] = rgb(max(set(cand), key=cand.count))


def remap(im, table, y0=0, y1=48, x0=0, x1=48):
    px = im.load()
    src = im.copy().load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            p = src[x, y]
            if p[3] and hx(p) in table:
                px[x, y] = rgb(table[hx(p)])


def put(im, pts, col):
    px = im.load()
    for x, y in pts:
        px[x, y] = rgb(col)


def vito():
    f = DIR / "portrait_vito.png"
    im = Image.open(f).convert("RGBA")
    despeckle(im, (13, 13, 37, 31))
    # vest (below the collar): scarlet -> plum, old dark -> deeper plum, bright -> brown
    remap(im, {"a22512": "62272c", "62272c": "3d1f29", "c94d2e": "83571e"}, y0=31)
    im.save(f)


def edith():
    f = DIR / "portrait_edith.png"
    im = Image.open(f).convert("RGBA")
    despeckle(im, (12, 11, 37, 28))
    rim = "3d1f29"
    for cx in (21, 28):  # two 6x5 rings: x cx..cx+5, y 17..21
        put(im, [(x, 17) for x in range(cx + 1, cx + 5)] + [(x, 21) for x in range(cx + 1, cx + 5)], rim)
        put(im, [(cx, y) for y in (18, 19, 20)] + [(cx + 5, y) for y in (18, 19, 20)], rim)
        put(im, [(x, y) for x in range(cx + 1, cx + 5) for y in (18, 19, 20)], "e5bd7f")  # clear lens
        put(im, [(cx + 1, 18)], "f2d9c5")  # glint
        put(im, [(cx + 2, 19), (cx + 3, 19)], "111010")  # eye
    put(im, [(26, 19), (27, 19)], rim)  # bridge
    put(im, [(20, 19), (19, 18)], rim)  # temple arm on the viewer's left
    im.save(f)


def mia():
    f = DIR / "portrait_mia.png"
    im = Image.open(f).convert("RGBA")
    despeckle(im, (13, 8, 37, 30))
    remap(im, {"dbcc83": "c5bf3f", "c5bf3f": "b1a13d", "b1a13d": "9b8039"}, y0=28)
    im.save(f)


vito()
edith()
mia()
