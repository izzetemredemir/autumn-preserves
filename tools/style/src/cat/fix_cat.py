#!/usr/bin/env python3
"""ART-POLISH-2: strip the teal/stone rim fringe from the cat sheets and redraw the head of cat_look (3/4 view).
Run from the repo root: python3 tools/style/src/cat/fix_cat.py  (reads cat_look_head.txt; the fringe pass is idempotent)."""
import pathlib
from PIL import Image

SPR = pathlib.Path("game/assets/sprites/cat")
HEAD = pathlib.Path(__file__).parent / "cat_look_head.txt"
DARK = {"415c5d", "2e3f3f", "49423d"}
LIGHT = {"4e7664", "738c7a", "567c7d", "b7b768", "81746a", "b4b3a0"}
LEG = {"d": "50361e", "g": "b66813", "s": "83571e", "n": "c58845", "p": "e5bd7f", "o": "e19064",
       "e": "111010", "y": "b7b768", "m": "3d1f29", ".": None}


def hx(p):
    return "%02x%02x%02x" % p[:3]


def defringe(im):
    src = im.copy().load()
    px = im.load()
    W, H = im.size
    for y in range(H):
        for x in range(W):
            p = src[x, y]
            if p[3] and (hx(p) in DARK or hx(p) in LIGHT):
                c = "50361e" if hx(p) in DARK else "83571e"
                px[x, y] = tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
    return im


for n in ("idle", "purr", "look", "sleep"):
    f = SPR / f"cat_{n}.png"
    defringe(Image.open(f).convert("RGBA")).save(f)

# --- cat_look head: 3 frames of 12x10 at (7,0); body (rows 10+) is kept
look = Image.open(SPR / "cat_look.png").convert("RGBA")
frames = [b.splitlines() for b in HEAD.read_text().split("frame\n")[1:]]
px = look.load()
for i, rows in enumerate(frames):
    ox = i * 24
    for y in range(0, 10):
        for x in range(6, 20):
            px[ox + x, y] = (0, 0, 0, 0)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if LEG[ch]:
                px[ox + 7 + x, y] = tuple(int(LEG[ch][k:k + 2], 16) for k in (0, 2, 4)) + (255,)
look.save(SPR / "cat_look.png")
