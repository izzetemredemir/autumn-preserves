#!/usr/bin/env python3
"""BIOMES (P1) art: vineyard and creek ground tiles, vines, elder, rose bush, wild bee hive and the six P1 icons.
Deterministic (fixed seeds), palette only, no partial alpha. Run from the repo root (numpy + Pillow):
    python3 tools/procedural/biome_art.py
Writes
  game/assets/sprites/tiles/{vineyard,creek}_tiles.png + .json  (16x16 cells, 4 variants per row, rows = WildGen
      ids 0 grass, 1 leaves, 2 dirt, 3 water, 4 path, 5 stone, 6 bank; ordered dither only, seamless)
  game/assets/sprites/forest/decor_vine.png, tree_grape_ripe.png, tree_grape_bare.png   (16x30, drawn here)
  game/assets/sprites/forest/tree_elderberry_{ripe,bare}.png   (64x80, from the approved pear tree: fruit painted
      over with leaves, then elderberry umbels; bark greyed)
  game/assets/sprites/forest/bush_rosehip_{ripe,bare}.png      (32x32, the approved blackberry bush recoloured)
  game/assets/sprites/forest/bee_hive_{ripe,bare}.png          (24x28, text source src/bee_hive.src)
  game/assets/sprites/icons/{grape,rosehip,elderberry,hazelnut,chestnut,oyster_mushroom}.png (src/icons_p1.src)
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tiles as T  # noqa: E402  ART-01 helpers: palette, tileable value noise, ordered dither, specks

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).resolve().parent / "src"
TILES = ROOT / "game/assets/sprites/tiles"
FOREST = ROOT / "game/assets/sprites/forest"
ICONS = ROOT / "game/assets/sprites/icons"
ASCII = ROOT / "tools/pipeline/ascii_sprite.py"
ROWS = ["grass", "leaves", "dirt", "water", "path", "stone", "bank"]
VARIANTS = 4
INK = (0x11, 0x10, 0x10)


def c(h):
    return T.c(h)


# ---------------------------------------------------------------- tiles

def pebbles(img, rng, n):
    """2x2 grey pebbles with a light top-left pixel and a dark bottom-right one (wrapping)."""
    for _ in range(n):
        y, x = rng.integers(0, T.T, 2)
        for dy, dx, col in ((0, 0, "b4b3a0"), (0, 1, "81746a"), (1, 0, "81746a"), (1, 1, "49423d")):
            img[(y + dy) % T.T, (x + dx) % T.T] = c(col)


def vineyard_tile(row, v):
    rng = np.random.default_rng(7100 + 10 * ROWS.index(row) + v)
    img = np.zeros((T.T, T.T, 3), np.uint8)
    n = T.tnoise(rng)
    if row == "grass":  # mown lane grass, a little greener than the forest's
        img[:] = c("b1a13d")
        T.dither(img, 1 - n, 0.0, 0.55, c("747c37"))
        T.dither(img, n, -0.2, 0.35, c("b7b768"))
        T.specks(img, rng, 4, "53612e", ((0, 0), (1, 0)))
        T.specks(img, rng, 2, "dbcc83")
    elif row == "leaves":  # fallen vine leaves, gold and red
        img[:] = c("b66813")
        T.dither(img, n, 0.1, 0.7, c("e5bd7f"))
        T.dither(img, 1 - n, -0.2, 0.3, c("83571e"))
        for col, k in (("c94d2e", 4), ("dbcc83", 3), ("a22512", 2), ("9b8039", 2)):
            T.specks(img, rng, k, col, T.two(rng))
    elif row == "dirt":  # tilled strip under a vine row: furrows across
        img[:] = c("83571e")
        T.dither(img, n, 0.05, 0.55, c("c58845"))
        for y in (3, 7, 11, 15):
            for x in range(T.T):
                if (x + v + y) % 5 != 0:
                    img[y, x] = c("50361e")
        T.specks(img, rng, 3, "b66813")
    elif row == "bank":
        return creek_tile("bank", v)
    else:
        return T.make(row, v)
    return img


def creek_tile(row, v):
    rng = np.random.default_rng(8200 + 10 * ROWS.index(row) + v)
    img = np.zeros((T.T, T.T, 3), np.uint8)
    n = T.tnoise(rng)
    if row == "grass":  # lush grass by the water
        img[:] = c("747c37")
        T.dither(img, n, 0.05, 0.6, c("b1a13d"))
        T.dither(img, 1 - n, -0.15, 0.35, c("53612e"))
        T.specks(img, rng, 4, "314524", ((0, 0), (1, 0)))
        T.specks(img, rng, 2, "b7b768")
        T.specks(img, rng, 1, "738c7a")
    elif row == "leaves":  # wet leaf litter
        img[:] = c("83571e")
        T.dither(img, n, 0.1, 0.6, c("b66813"))
        T.dither(img, 1 - n, -0.2, 0.35, c("50361e"))
        for col, k in (("c94d2e", 3), ("9b8039", 3), ("62272c", 2), ("e5bd7f", 1)):
            T.specks(img, rng, k, col, T.two(rng))
    elif row == "dirt":  # mud
        img[:] = c("50361e")
        T.dither(img, n, 0.1, 0.6, c("83571e"))
        T.dither(img, 1 - n, -0.2, 0.25, c("3d1f29"))
        T.specks(img, rng, 3, "49423d")
    elif row == "water":  # a deeper creek, current lines along the flow (west -> east)
        img[:] = c("415c5d")
        T.dither(img, 1 - n, 0.0, 0.5, c("2e3f3f"))
        T.dither(img, n, -0.1, 0.35, c("567c7d"))
        for _ in range(3):
            y, x = rng.integers(0, T.T, 2)
            for dx in range(4):
                img[y, (x + dx) % T.T] = c("738c7a")
    elif row == "bank":  # sandy bank with pebbles
        img[:] = c("c58845")
        T.dither(img, n, 0.05, 0.5, c("e5bd7f"))
        T.dither(img, 1 - n, -0.2, 0.3, c("9b8039"))
        pebbles(img, rng, 3)
        T.specks(img, rng, 2, "83571e")
    else:
        return T.make(row, v)
    return img


def write_tiles(biome, fn):
    atlas = np.zeros((T.T * len(ROWS), T.T * VARIANTS, 3), np.uint8)
    for r, row in enumerate(ROWS):
        for v in range(VARIANTS):
            atlas[r * T.T:(r + 1) * T.T, v * T.T:(v + 1) * T.T] = fn(row, v)
    rgba = np.dstack([atlas, np.full(atlas.shape[:2], 255, np.uint8)])
    Image.fromarray(rgba, "RGBA").save(TILES / f"{biome}_tiles.png")
    meta = {"image": f"{biome}_tiles.png", "tile_size": T.T, "columns": VARIANTS, "rows": len(ROWS),
            "note": "keys are WildGen T_* ids (6 = T_BANK); cells are [col,row]; pick variant by hash(x,y) % variants",
            "tiles": {str(i): {"name": n, "cells": [[v, i] for v in range(VARIANTS)]} for i, n in enumerate(ROWS)}}
    (TILES / f"{biome}_tiles.json").write_text(json.dumps(meta, indent=1) + "\n")


# ---------------------------------------------------------------- small helpers

def canvas(w, h):
    return np.zeros((h, w, 4), np.uint8)


def put(img, x, y, col):
    if 0 <= x < img.shape[1] and 0 <= y < img.shape[0]:
        img[y, x] = (*c(col), 255)


def outline(img, col=INK):
    """1 px 4-neighbour outline in `col` around opaque pixels, inside the canvas only."""
    a = img[:, :, 3] > 0
    ring = np.zeros_like(a)
    ring[1:, :] |= a[:-1, :]
    ring[:-1, :] |= a[1:, :]
    ring[:, 1:] |= a[:, :-1]
    ring[:, :-1] |= a[:, 1:]
    ring &= ~a
    img[ring] = (*col, 255)
    return img


def save(img, path):
    Image.fromarray(img, "RGBA").save(path)


# ---------------------------------------------------------------- vines (16x30)

# Leaf clumps back to front: (cx, cy, r, ramp). Ramps dark -> light: shadow, base, light.
GOLD = ("9b8039", "b66813", "e5bd7f")
RED = ("a22512", "c94d2e", "e19064")
OLIVE = ("53612e", "747c37", "b1a13d")
CLUMPS = [(2, 11, 4.2, OLIVE), (13, 11, 4.2, GOLD), (8, 7, 4.6, GOLD), (3, 7, 3.6, RED), (12, 6, 3.8, OLIVE),
          (6, 13, 3.6, RED), (11, 14, 3.4, GOLD), (0, 9, 3.0, GOLD), (15, 9, 3.0, RED)]


def vine(grapes):
    W, H = 16, 30
    img = canvas(W, H)
    # gnarled trunk, light from the left
    for y in range(15, H):
        x = 7 if y < 22 or y > 26 else 6
        put(img, x, y, "c58845" if y % 4 else "83571e")
        put(img, x + 1, y, "83571e")
        put(img, x + 2, y, "50361e")
    put(img, 5, 27, "83571e")
    put(img, 10, 27, "50361e")
    for cx, cy, r, ramp in CLUMPS:
        for y in range(H):
            for x in range(W):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                d2 = dx * dx + dy * dy
                if d2 > r * r:
                    continue
                if d2 > (r - 1.1) ** 2 and dx + dy > 0:
                    col = ramp[0]  # rim on the shadow side: where clumps overlap
                elif dx + dy < -r * 0.75:
                    col = ramp[2]  # top-left light
                else:
                    col = ramp[1]
                put(img, x, y, col)
    if grapes:  # two bunches hanging under the leaves: 2x2 berries, dark plum with a wine and a dusty pixel
        for bx, by, widths in ((4, 14, (3, 3, 2, 1)), (10, 16, (3, 2, 2, 1))):
            put(img, bx + 2, by - 1, "50361e")
            for k, n in enumerate(widths):
                x0 = bx + (3 - n)
                for j in range(n):
                    x, y = x0 + 2 * j, by + 2 * k
                    put(img, x, y, "62272c")
                    put(img, x + 1, y, "3d1f29")
                    put(img, x, y + 1, "3d1f29")
                    put(img, x + 1, y + 1, "23282a")
                    if (j + k) % 2 == 0:
                        put(img, x, y, "81746a")
    outline(img)
    # leaves that reach the side edges carry on into the next vine of the row: no outline there
    return img


# ---------------------------------------------------------------- derived: rose bush, elder

def recolor(path, mapping, rows=None):
    im = np.array(Image.open(path).convert("RGBA"))
    out = im.copy()
    for src, dst in mapping.items():
        m = np.all(im[:, :, :3] == c(src), axis=2) & (im[:, :, 3] > 0)
        if rows is not None:
            m[: rows[0], :] = False
            m[rows[1]:, :] = False
        out[m, :3] = c(dst)
    return out


def rose_bushes():
    hips = {"3d1f29": "a22512", "62272c": "c94d2e", "23282a": "62272c", "b9a697": "e19064", "81746a": "c94d2e",
            "a22512": "e19064"}
    ripe = recolor(FOREST / "bush_blackberry_ripe.png", hips)
    save(ripe, FOREST / "bush_rosehip_ripe.png")
    # rose leaves turn amber in autumn: the bare bush is the blackberry's, warmer
    bare = recolor(FOREST / "bush_blackberry_bare.png", {"9b8039": "b66813", "c5bf3f": "e5bd7f", "b7b768": "dbcc83"})
    save(bare, FOREST / "bush_rosehip_bare.png")


PEAR_FRUIT = ("dbcc83", "c5bf3f")
UMBEL = [(dx, dy) for dy, half in ((-1, 2), (0, 3), (1, 3), (2, 2)) for dx in range(-half, half + 1)]
UMBEL_STALKS = [(0, -2), (0, -3), (-1, -2), (1, -2), (-2, -2), (2, -2)]


def elders():
    pear = np.array(Image.open(FOREST / "tree_pear_ripe.png").convert("RGBA"))
    H, W = pear.shape[:2]
    fruit = np.zeros((H, W), bool)
    for h in PEAR_FRUIT:
        fruit |= np.all(pear[:, :, :3] == c(h), axis=2) & (pear[:, :, 3] > 0)
    # fruit outlines: dark pixels touching fruit inside the canopy go too
    grown = fruit.copy()
    grown[1:, :] |= fruit[:-1, :]
    grown[:-1, :] |= fruit[1:, :]
    grown[:, 1:] |= fruit[:, :-1]
    grown[:, :-1] |= fruit[:, 1:]
    dark = np.all(pear[:, :, :3] == c("3d1f29"), axis=2)
    grown &= (fruit | dark) & (pear[:, :, 3] > 0)
    # fruit centres (connected blobs), for the umbels
    centres = []
    seen = np.zeros_like(fruit)
    for y in range(H):
        for x in range(W):
            if fruit[y, x] and not seen[y, x]:
                stack, pts = [(y, x)], []
                seen[y, x] = True
                while stack:
                    py, px = stack.pop()
                    pts.append((py, px))
                    for qy, qx in ((py + 1, px), (py - 1, px), (py, px + 1), (py, px - 1)):
                        if 0 <= qy < H and 0 <= qx < W and fruit[qy, qx] and not seen[qy, qx]:
                            seen[qy, qx] = True
                            stack.append((qy, qx))
                if len(pts) >= 6:
                    centres.append((round(sum(p[0] for p in pts) / len(pts)), round(sum(p[1] for p in pts) / len(pts))))
    # the pears become leaf clumps: same shape and shading, olive tones (light, mid, rim)
    leafy = pear.copy()
    to_leaf = {"dbcc83": "b1a13d", "c5bf3f": "747c37", "3d1f29": "53612e"}
    for y in range(H):
        for x in range(W):
            if grown[y, x]:
                leafy[y, x, :3] = c(to_leaf.get("%02x%02x%02x" % tuple(pear[y, x, :3]), "747c37"))
    # elder bark is grey-brown and corky: below the canopy only
    trunk_top = max(cy for cy, _ in centres) + 4 if centres else H // 2
    for src, dst in {"c58845": "b4b3a0", "83571e": "81746a", "b66813": "81746a", "50361e": "49423d"}.items():
        m = np.all(leafy[:, :, :3] == c(src), axis=2)
        m[:trunk_top, :] = False
        leafy[m, :3] = c(dst)
    save(leafy, FOREST / "tree_elderberry_bare.png")
    ripe = leafy.copy()

    def px(x, y, col):
        if 0 <= x < W and 0 <= y < H and ripe[y, x, 3] and tuple(ripe[y, x, :3]) != INK:
            ripe[y, x, :3] = c(col)
    for cy, cx in centres:
        for dx, dy in UMBEL_STALKS:
            px(cx + dx, cy + dy, "a22512")
        for dx, dy in UMBEL:  # a dome of dark berries, lit from the top left
            px(cx + dx, cy + dy, "23282a" if (dx + dy) % 2 else "3d1f29")
        for dx, dy in ((-2, 0), (-1, -1), (0, 0)):
            px(cx + dx, cy + dy, "62272c")
    save(ripe, FOREST / "tree_elderberry_ripe.png")
    return len(centres)


# ---------------------------------------------------------------- text sources (ascii_sprite.py)

LEGEND = """legend . transparent
legend i ink
legend r leaf_red_500
legend R leaf_red_700
legend p leaf_peach_300
legend g gold_300
legend G gold_200
legend a amber_600
legend o gold_700
legend b bark_700
legend B bark_900
legend n bark_500
legend c cream_100
legend C cream_400
legend l olive_600
legend L olive_800
legend e olive_300
legend E olive_200
legend k olive_500
legend w plum_900
legend W wine_700
legend s stone_300
legend S stone_500
legend t stone_700
legend v water_800
legend V water_600
legend x sage_400
legend q olive_900
legend u water_900
legend z slate_900
"""


def read_src(path, width):
    out, cur = {}, None
    for line in path.read_text().splitlines():
        if line.startswith("#"):
            continue
        if line.startswith("== "):
            cur = line[3:].strip()
            out[cur] = []
        elif cur is not None and line.strip():
            out[cur].append(line.ljust(width, "."))
    return out


def render_text(rows, out, w, h):
    rows = rows + ["." * w] * (h - len(rows))
    assert len(rows) == h and all(len(r) == w for r in rows), (out, [len(r) for r in rows])
    tmp = SRC / ".render.tmp.txt"
    tmp.write_text(LEGEND + "frame\n" + "\n".join(rows) + "\n")
    try:
        subprocess.check_call([sys.executable, str(ASCII), "render", str(tmp), "--out", str(out), "--outline"],
                              stdout=subprocess.DEVNULL)
    finally:
        tmp.unlink()


def main():
    TILES.mkdir(parents=True, exist_ok=True)
    write_tiles("vineyard", vineyard_tile)
    write_tiles("creek", creek_tile)
    bare = vine(False)
    save(bare, FOREST / "decor_vine.png")
    save(bare, FOREST / "tree_grape_bare.png")
    save(vine(True), FOREST / "tree_grape_ripe.png")
    rose_bushes()
    n = elders()
    for state, rows in read_src(SRC / "bee_hive.src", 24).items():
        render_text(rows, FOREST / f"bee_hive_{state}.png", 24, 28)
    icons = read_src(SRC / "icons_p1.src", 16)
    for i, rows in icons.items():
        render_text(rows, ICONS / f"{i}.png", 16, 16)
    print("tiles: vineyard, creek · vines · rose bush · elder (%d umbels) · hive · %d icons" % (n, len(icons)))


if __name__ == "__main__":
    main()
