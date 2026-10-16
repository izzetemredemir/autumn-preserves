#!/usr/bin/env python3
"""ART-MG-A: procedural / hand-drawn small art for stir_pot and pack_jar.
Writes the text sources (tools/style/src/minigames/*.txt) and renders them with tools/pipeline/ascii_sprite.py.
Run from the repo root:  python3 tools/style/src/minigames/make_mg_art.py
Piece sprites use five marker greys = ingredient ramp tones 0..4 (dark -> light); the game recolours them.
"""
import math
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from scipy.spatial import ConvexHull

SRC = Path("tools/style/src/minigames")
STIR = Path("game/assets/sprites/minigames/stir_pot")
JAR = Path("game/assets/sprites/minigames/pack_jar")
SRC.mkdir(parents=True, exist_ok=True)

ROLES = """legend . transparent
legend k ink
legend T stone_700
legend S stone_500
legend s stone_300
legend h sage_400
legend c cream_100
legend C cream_400
legend g gold_300
legend G gold_200
legend y gold_700
legend a amber_600
legend b bark_500
legend B bark_700
legend D bark_900
legend w water_700
legend W water_900
legend v water_600
legend e wine_700
legend r leaf_red_500
legend p leaf_peach_300
legend 0 111010
legend 1 49423d
legend 2 81746a
legend 3 b9a697
legend 4 f2d9c5
"""


def emit(name, grid, out, header=""):
    h, w = len(grid), len(grid[0])
    assert all(len(r) == w for r in grid), name
    txt = f"# {name} {w}x{h} {header}\n" + ROLES + "frame\n" + "\n".join("".join(r) for r in grid) + "\n"
    (SRC / f"{name}.txt").write_text(txt)
    subprocess.run(["python3", "tools/pipeline/ascii_sprite.py", "render", str(SRC / f"{name}.txt"), "--out", str(out)],
                   check=True, stdout=subprocess.DEVNULL)


def blank(w, h):
    return [["."] * w for _ in range(h)]


def put(g, x, y, ch):
    if 0 <= y < len(g) and 0 <= x < len(g[0]):
        g[y][x] = ch


def outline(g, ch="0"):
    """Add a 1px outline (4-neighbour) inside the grid around non-transparent pixels."""
    h, w = len(g), len(g[0])
    res = [r[:] for r in g]
    for y in range(h):
        for x in range(w):
            if g[y][x] == ".":
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and g[ny][nx] != ".":
                        res[y][x] = ch
                        break
    return res


def rot90(g):
    return [list(r) for r in zip(*g[::-1])]


# ------------------------------------------------------------------ pieces (ramp markers 0-4)
def p_rings():  # cucumber slice, top view, 16x16
    g = blank(16, 16)
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 7.5, y - 7.5)
            if d <= 7.6:
                g[y][x] = "0" if d > 6.6 else ("1" if d > 5.6 else "3")
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 7.5, y - 7.5)
            if g[y][x] == "3":
                if d < 3.2:
                    g[y][x] = "4"
                if d > 4.6:
                    g[y][x] = "2" if (x + y) % 2 == 0 else "3"
    for (x, y) in ((7, 5), (5, 8), (9, 8), (7, 9)):
        put(g, x, y, "2")
    for (x, y) in ((3, 3), (4, 2)):
        put(g, x, y, "4")
    return g


def p_slice():  # apple/quince/pear slice, vertical 16x32
    w, h = 16, 32
    g = blank(w, h)
    for y in range(h):
        for x in range(w):
            d = math.hypot((x - 7.5) / 7.7, (y - 15.5) / 15.7)
            if d <= 1.0:
                g[y][x] = "0" if d > 0.92 else ("2" if d > 0.84 else "4")
    for y in range(h):
        for x in range(w):
            if g[y][x] == "4":
                d = math.hypot((x - 7.5) / 7.7, (y - 15.5) / 15.7)
                if x > 9 and d > 0.5:
                    g[y][x] = "3"
                if x > 11 and d > 0.7:
                    g[y][x] = "1" if d > 0.78 else "3"
    for x in range(1, 15):  # right skin shade
        for y in range(h):
            if g[y][x] == "2" and x >= 9:
                g[y][x] = "1"
    for y in range(11, 21):  # core
        for x in range(5, 11):
            d = math.hypot((x - 7.5) / 2.9, (y - 15.5) / 4.9)
            if d <= 1:
                g[y][x] = "3" if d > 0.55 else "4"
    for (x, y) in ((7, 13), (8, 14), (7, 17), (8, 18)):
        put(g, x, y, "0")
    for y in range(4, 9):
        put(g, 4, y, "4" if y != 6 else "3")
    return g


def p_strip():  # pepper strip, vertical 16x48
    w, h = 16, 48
    g = blank(w, h)
    for y in range(h):
        bend = int(round(math.sin(y / 47 * math.pi) * 1.5))
        for x in range(2, 14):
            xx = x + bend - 1
            ty = min(y, h - 1 - y)
            inset = 0 if ty > 3 else (3 - ty)
            if x < 2 + inset or x > 13 - inset:
                continue
            put(g, xx, y, "2")
        # shading across the strip
        row = [i for i, c in enumerate(g[y]) if c == "2"]
        if row:
            for i in row:
                rel = (i - row[0]) / max(1, len(row) - 1)
                g[y][i] = "3" if rel < 0.3 else ("1" if rel > 0.72 else "2")
            if row[0] + 1 < w:
                g[y][row[0] + 1] = "4" if y % 7 not in (0, 1) else "3"
    # seed pips
    for (x, y) in ((8, 14), (9, 15), (7, 28), (8, 29), (9, 38)):
        put(g, x, y, "4")
    return outline(g)


def p_caps():  # mushroom cap + stem, side view, 32x16
    w, h = 32, 16
    g = blank(w, h)
    for y in range(h):
        for x in range(w):
            d = math.hypot((x - 15.5) / 15.2, (y - 10.5) / 9.6)
            if y <= 10 and d <= 1:
                g[y][x] = "2"
    for y in range(11, 15):  # stem
        for x in range(12, 20):
            g[y][x] = "4" if x < 17 else "3"
    for x in range(1, 31):  # gill rim under the cap
        if g[10][x] == "2":
            g[10][x] = "1"
    for y in range(h):
        for x in range(w):
            if g[y][x] == "2":
                d = math.hypot((x - 15.5) / 15.2, (y - 10.5) / 9.6)
                if d > 0.82:
                    g[y][x] = "1"
                elif x < 14 and y < 6:
                    g[y][x] = "3"
    for (x, y) in ((9, 4), (10, 4), (9, 5), (18, 3), (22, 6), (15, 7), (6, 7)):
        put(g, x, y, "4")
    return outline(g)


def p_shreds():  # cabbage shreds pile 16x16
    w, h = 16, 16
    g = blank(w, h)
    for y in range(h):
        for x in range(w):
            d = math.hypot((x - 7.5) / 7.0, (y - 8.5) / 6.5)
            if d <= 1.0:
                g[y][x] = "2"
    for y in range(3, 14):
        for x in range(w):
            if g[y][x] == "2":
                if (y % 4) == 1:
                    g[y][x] = "3" if ((x + y // 4) % 5) < 3 else "1"
                elif (y % 4) == 2 and x % 3 == 0:
                    g[y][x] = "4"
                elif y > 10:
                    g[y][x] = "1"
    return outline(g)


def p_seeds():  # berries cluster 16x16
    g = blank(16, 16)

    def berry(cx, cy, r):
        for y in range(16):
            for x in range(16):
                d = math.hypot(x - cx, y - cy)
                if d <= r:
                    c = "0" if d > r - 1.0 else "2"
                    if c == "2" and (x - cx) + (y - cy) > r * 0.6:
                        c = "1"
                    g[y][x] = c
        put(g, int(round(cx - r * 0.45)), int(round(cy - r * 0.45)), "4")
        put(g, int(round(cx - r * 0.45)) + 1, int(round(cy - r * 0.45)), "3")
    berry(4.5, 10.5, 4.3)
    berry(11.0, 10.5, 4.3)
    berry(7.8, 5.2, 4.3)
    return g


def p_chunks():  # chunk, iso block 16x16
    g = blank(16, 16)
    pts = {"top": [(8, 1), (14, 4), (8, 7), (2, 4)], "left": [(2, 4), (8, 7), (8, 14), (2, 11)],
           "right": [(14, 4), (8, 7), (8, 14), (14, 11)]}
    im = Image.new("L", (16, 16), 0)
    d = ImageDraw.Draw(im)
    for key, ch in (("top", 4), ("left", 2), ("right", 1)):
        d.polygon(pts[key], fill=ch)
    a = np.array(im)
    for y in range(16):
        for x in range(16):
            if a[y][x]:
                g[y][x] = str(a[y][x] if a[y][x] != 4 else 3)
    g = outline(g)
    put(g, 6, 3, "4")
    put(g, 7, 3, "4")
    return g


# ------------------------------------------------------------------ small stir sprites
def s_foam():  # foam clump 14x14
    g = blank(14, 14)
    blobs = [(5, 8, 4.4), (9.5, 8.5, 3.9), (7, 4.5, 3.9)]
    for y in range(14):
        for x in range(14):
            for (cx, cy, r) in blobs:
                if math.hypot(x - cx, y - cy) <= r:
                    g[y][x] = "c"
    for y in range(14):
        for x in range(14):
            if g[y][x] == "c" and (x + y) > 18:
                g[y][x] = "C"
    g = outline(g, "g")
    for (x, y) in ((4, 6), (5, 6), (6, 3), (9, 6)):
        put(g, x, y, "c")
    for (x, y) in ((3, 7), (7, 2)):
        put(g, x, y, "4" if False else "c")
    return g


def s_bubbles():  # 3 frames 8x8 side by side: small, medium, large
    out = []
    for size in (4, 6, 8):
        g = blank(8, 8)
        o = (8 - size) // 2
        r = size / 2
        for y in range(8):
            for x in range(8):
                if math.hypot(x - o - r + 0.5, y - o - r + 0.5) <= r:
                    g[y][x] = "C"
        g = outline(g, "c") if size > 4 else g
        if size == 4:
            for y in range(8):
                for x in range(8):
                    if g[y][x] == "C":
                        g[y][x] = "c"
        put(g, o + 1, o + 1, "c")
        out.append(g)
    return out


def s_needle():  # 30x9 pointer
    g = blank(30, 9)
    for y in range(9):
        half = y if y <= 4 else 8 - y
        for x in range(8):
            if x >= 4 - half and x <= 7:
                g[y][x] = "g"
    for y in range(3, 6):
        for x in range(8, 30):
            g[y][x] = "g"
    g = outline(g, "k")
    for x in range(9, 29):
        put(g, x, 3, "G")
    return g


def s_gauge_frame(w=20, h=154):  # tube frame, hollow interior 16x150 at (2,2)
    g = blank(w, h)
    for y in range(h):
        for x in range(w):
            if 2 <= x < w - 2 and 2 <= y < h - 2:
                continue
            g[y][x] = "S"
    for y in range(h):
        for x in range(w):
            if g[y][x] != ".":
                edge = x in (0, w - 1) or y in (0, h - 1)
                if edge:
                    g[y][x] = "k"
                elif x == 1 or y == 1:
                    g[y][x] = "s"
                elif x == w - 2 or y == h - 2:
                    g[y][x] = "T"
    # inner dark edge line inside the hollow
    return g


# ------------------------------------------------------------------ jar
def jar_front():
    W, H = 112, 142
    g = blank(W, H)
    IX, IY, IW, IH = 8, 4, 96, 128
    for y in range(H):
        for x in range(W):
            pass
    # lip rows 0-3, full width 1..110
    for x in range(1, 111):
        g[0][x] = "k"
        g[1][x] = "s" if 2 <= x <= 109 else "k"
        g[2][x] = "h"
        g[3][x] = "S"
    for y in (1, 2, 3):
        g[y][0] = "k" if y == 1 else "."
        g[y][111] = "k" if y == 1 else "."
    for y in range(1, 4):
        g[y][1] = "k"
        g[y][110] = "k"
    for x in range(3, 109):
        if x < 40 or 50 < x < 56:
            g[1][x] = "c" if x % 9 else "s"
    g[0][0] = g[0][111] = "."
    # body walls
    for y in range(4, 132):
        for x, ch in ((4, "k"), (5, "h"), (6, "s"), (7, "h")):
            g[y][x] = ch
        for x, ch in ((104, "h"), (105, "S"), (106, "h"), (107, "k")):
            g[y][x] = ch
    # bottom: rows 132..137
    for y in range(132, 138):
        k = y - 132
        inset = (0, 0, 1, 2, 3, 4)[k]
        for x in range(4 + inset, 108 - inset):
            col = ("s", "h", "S", "S", "T", "k")[k]
            g[y][x] = col
        g[y][4 + inset] = "k"
        g[y][107 - inset] = "k"
    for x in range(8, 104):
        g[137][x] = "k"
    for x in range(4, 8):
        g[132][x] = "h"
    # rounded inner bottom corners of the glass walls (visual only)
    # drop shadow rows 138..141
    for y in range(138, 142):
        inset = 6 + (y - 138) * 4
        for x in range(inset, 112 - inset):
            g[y][x] = "D"
    # specular streaks inside the glass (sparse, on the front layer)
    for y in list(range(18, 52)) + list(range(58, 64)):
        g[y][IX + 1] = "c"
    for y in range(90, 96):
        g[y][IX + 1] = "C"
    for y in range(24, 30):
        g[y][IX + IW - 3] = "C"
    return g


def jar_back():
    """Interior backdrop 96x128: deep teal glass with a soft darker bottom."""
    w, h = 96, 128
    g = [["W"] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if y > 112 and (x + y) % 2 == 0:
                g[y][x] = "k" if y > 122 else "W"
            elif x > 86 and (x + y) % 3 == 0:
                g[y][x] = "W"
            elif x < 6 and y % 2 == 0 and x % 2 == 0 and y < 100:
                g[y][x] = "w"
    return g


def jar_lid():
    w, h = 112, 10
    g = blank(w, h)
    for y in range(h):
        for x in range(w):
            g[y][x] = "a"
    for x in range(w):
        g[0][x] = "g"
        g[1][x] = "G" if x % 2 == 0 else "g"
        g[h - 2][x] = "y"
        g[h - 1][x] = "k"
    for y in range(h):
        g[y][0] = "k"
        g[y][w - 1] = "k"
    g[0][0] = g[0][w - 1] = "."
    for x in range(6, w - 4, 8):  # ridges
        for y in range(2, h - 2):
            g[y][x] = "y"
            g[y][x + 1] = "a" if y > 2 else "g"
    for y in range(1, h - 2):
        g[y][2] = "G"
    return g


# ------------------------------------------------------------------ stir: masks and spoon sheet
def stir_masks():
    bg = np.array(Image.open(STIR / "stir_bg.png").convert("RGB"))
    c = bg[118, 172]
    m = (bg == c).all(axis=2)
    lab, _ = ndi.label(m)
    region = lab == lab[118, 172]
    ys, xs = np.nonzero(region)
    pts = np.stack([xs, ys], 1)
    hull = ConvexHull(pts)
    poly = [tuple(pts[i]) for i in hull.vertices]
    im = Image.new("L", (480, 270), 0)
    ImageDraw.Draw(im).polygon(poly, fill=1)
    mask = np.array(im).astype(bool)
    mask = ndi.binary_erosion(mask)  # keep the rim art intact
    ys, xs = np.nonzero(mask)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    print("liquid bbox", x0, y0, x1, y1, "centre", (x0 + x1) / 2, (y0 + y1) / 2)
    crop = mask[y0:y1 + 1, x0:x1 + 1]
    inner = ndi.binary_erosion(crop, iterations=3)
    rim = crop & ~inner
    # rim only on the lower-right half, glint on the upper-left
    yy, xx = np.mgrid[0:crop.shape[0], 0:crop.shape[1]]
    lower_right = (xx - crop.shape[1] / 2) + (yy - crop.shape[0] / 2) > 0
    rim_br = rim & lower_right
    glint = np.zeros_like(crop)
    cx, cy = crop.shape[1] / 2, crop.shape[0] / 2
    for ang in np.linspace(math.radians(200), math.radians(250), 30):
        for r in (cx - 8,):
            gx, gy = int(round(cx + math.cos(ang) * r * 1.0)), int(round(cy + math.sin(ang) * (cy - 8)))
            if 0 <= gy < glint.shape[0] and 0 <= gx < glint.shape[1] and crop[gy, gx]:
                glint[gy, gx] = True
    out = {"stir_liquid": crop, "stir_liquid_rim": rim_br, "stir_liquid_glint": glint}
    for name, arr in out.items():
        a = np.zeros(arr.shape + (4,), np.uint8)
        a[arr] = (0xf2, 0xd9, 0xc5, 255)
        Image.fromarray(a, "RGBA").save(STIR / f"{name}.png")
    (SRC / "stir_liquid_origin.txt").write_text(f"liquid mask top-left on the 480x270 screen: {x0} {y0}\n")
    return x0, y0, crop.shape[1], crop.shape[0]


def spoon_sheet(n=16, size=176):
    pal = {"k": (0x11, 0x10, 0x10), "hi": (0xc5, 0x88, 0x45), "mid": (0xc5, 0x88, 0x45), "sh": (0x83, 0x57, 0x1e),
           "dk": (0x50, 0x36, 0x1e), "li": (0xe5, 0xbd, 0x7f)}
    sheet = np.zeros((size, size * n, 4), np.uint8)
    c = size / 2
    for i in range(n):
        a = i * math.tau / n
        d = np.array([math.cos(a), math.sin(a)])
        nrm = np.array([-d[1], d[0]])
        for y in range(size):
            for x in range(size):
                p = np.array([x + 0.5 - c, y + 0.5 - c])
                t = p @ d  # along
                s = p @ nrm  # across
                col = None
                # handle: t 30..84, half-width 1.6 ; outline 2.6
                if 24 <= t <= 85:
                    w = abs(s)
                    if w <= 1.7:
                        col = pal["li"] if s < -0.6 else (pal["sh"] if s > 0.7 else pal["mid"])
                    elif w <= 2.7:
                        col = pal["k"]
                # bowl: ellipse centred t=14, semi-axes 11 x 6.5
                e = math.hypot((t - 15) / 12.0, s / 7.2)
                if e <= 1.0:
                    col = pal["li"] if (e < 0.55 and s < -1) else (pal["sh"] if (e > 0.62 and s > 0) else pal["mid"])
                    if e > 0.62 and s <= 0:
                        col = pal["hi"]
                elif e <= 1.22 and col is None:
                    col = pal["k"]
                if e <= 1.0 and e > 0.8:
                    col = pal["dk"] if s > 1 else col
                if col:
                    sheet[y, i * size + x] = (*col, 255)
    Image.fromarray(sheet, "RGBA").save(STIR / "stir_spoon.png")


def main():
    for name, fn in (("rings", p_rings), ("seeds", p_seeds), ("shreds", p_shreds), ("chunks", p_chunks)):
        emit(f"piece_{name}", fn(), JAR / f"piece_{name}.png", "ramp markers 0-4")
    for name, fn in (("slices", p_slice), ("strips", p_strip), ("caps", p_caps)):
        g = fn()
        emit(f"piece_{name}", g, JAR / f"piece_{name}.png", "ramp markers 0-4")
        emit(f"piece_{name}_r", rot90(g), JAR / f"piece_{name}_r.png", "ramp markers 0-4, rotated 90")
    emit("jar_front", jar_front(), JAR / "jar_front.png", "glass walls, lip, base, shadow; interior hole 96x128 at (8,4)")
    emit("jar_back", jar_back(), JAR / "jar_back.png")
    emit("jar_lid", jar_lid(), JAR / "jar_lid.png")
    emit("stir_foam", s_foam(), STIR / "stir_foam.png")
    b = s_bubbles()
    emit("stir_bubbles", [sum((f[y] for f in b), []) for y in range(8)], STIR / "stir_bubbles.png", "3 frames 8x8")
    emit("stir_needle", s_needle(), STIR / "stir_needle.png")
    emit("stir_gauge_frame", s_gauge_frame(), STIR / "stir_gauge_frame.png")
    stir_masks()
    spoon_sheet()


if __name__ == "__main__":
    main()
