#!/usr/bin/env python3
"""ART-01 procedural forest ground tiles. Deterministic (fixed seeds), seamless, Bayer dither only.
Run from repo root:  python3 tools/procedural/tiles.py
Writes game/assets/sprites/tiles/forest_tiles.png (64x96: 4 variants x 6 rows) and forest_tiles.json.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/assets/sprites/tiles"
T = 16
VARIANTS = 4
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 + 1 / 32
BAY = np.tile(BAYER, (T // 4, T // 4))  # 4 divides 16 -> seamless

# Row index == WildGen tile id (T_GRASS..T_STONE).
ROWS = ["grass", "leaves", "dirt", "water", "path", "stone"]

PAL = {h: tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
       for h in (ROOT / "tools/palettes/autumn.hex").read_text().split()}
RAMPS = json.loads((ROOT / "tools/palettes/autumn_ramps.json").read_text())
for _r in RAMPS.values():
    for _h in _r:
        assert _h in PAL, _h


def c(h):
    return PAL[h]


def tnoise(rng):
    """Tileable value noise (wrapping lattice), normalised to 0..1."""
    acc = np.zeros((T, T))
    ys, xs = np.mgrid[0:T, 0:T]
    for cells, w in ((4, 1.0), (8, 0.5)):
        lat = rng.random((cells, cells))
        fy, fx = ys * cells / T, xs * cells / T
        y0, x0 = fy.astype(int), fx.astype(int)
        ty, tx = fy - y0, fx - x0
        ty, tx = ty * ty * (3 - 2 * ty), tx * tx * (3 - 2 * tx)
        y1, x1 = (y0 + 1) % cells, (x0 + 1) % cells
        acc += w * ((lat[y0, x0] * (1 - tx) + lat[y0, x1] * tx) * (1 - ty)
                    + (lat[y1, x0] * (1 - tx) + lat[y1, x1] * tx) * ty)
    return (acc - acc.min()) / (np.ptp(acc) + 1e-9)


def dither(img, noise, lo, hi, col):
    """Paint col where scaled noise exceeds the Bayer threshold (ordered dither)."""
    img[(noise * (hi - lo) + lo) > BAY] = col


def specks(img, rng, n, col, shape=((0, 0),)):
    for _ in range(n):
        y, x = rng.integers(0, T, 2)
        for dy, dx in shape:
            img[(y + dy) % T, (x + dx) % T] = c(col)


def two(rng):
    return ((0, 0), (0, 1)) if rng.random() < 0.5 else ((0, 0), (1, 0))


def make(row, v):
    rng = np.random.default_rng(1000 * (ROWS.index(row) + 1) + v)
    img = np.zeros((T, T, 3), np.uint8)
    n = tnoise(rng)
    if row == "grass":  # dry olive/gold grass
        img[:] = c("b1a13d")
        dither(img, n, 0.1, 0.6, c("9b8039"))
        dither(img, 1 - n, -0.1, 0.35, c("747c37"))
        specks(img, rng, 5, "747c37", ((0, 0), (1, 0)))
        specks(img, rng, 3, "dbcc83")
    elif row == "leaves":  # leaf litter
        img[:] = c("83571e")
        dither(img, n, 0.1, 0.7, c("b66813"))
        dither(img, 1 - n, -0.2, 0.3, c("50361e"))
        for col, k in (("c94d2e", 4), ("b66813", 3), ("9b8039", 3), ("a22512", 2), ("e5bd7f", 1)):
            specks(img, rng, k, col, two(rng))
    elif row == "dirt":
        img[:] = c("83571e")
        dither(img, n, 0.1, 0.6, c("c58845"))
        dither(img, 1 - n, -0.1, 0.3, c("50361e"))
        specks(img, rng, 4, "50361e")
        specks(img, rng, 3, "b9a697")
    elif row == "path":  # packed sandy path
        img[:] = c("c58845")
        dither(img, n, 0.1, 0.65, c("e5bd7f"))
        dither(img, 1 - n, -0.15, 0.3, c("83571e"))
        specks(img, rng, 4, "9b8039")
        specks(img, rng, 2, "b4b3a0")
    elif row == "stone":  # warm grey
        img[:] = c("81746a")
        dither(img, n, 0.1, 0.65, c("b9a697"))
        dither(img, 1 - n, -0.1, 0.3, c("49423d"))
        specks(img, rng, 3, "49423d", ((0, 0), (0, 1)))
        specks(img, rng, 2, "b9a697")
    elif row == "water":
        img[:] = c("415c5d")
        dither(img, n, 0.1, 0.6, c("567c7d"))
        dither(img, 1 - n, -0.1, 0.3, c("2e3f3f"))
        for _ in range(2):
            y, x = rng.integers(0, T, 2)
            for dx in range(3):
                img[y, (x + dx) % T] = c("738c7a")
    return img


def main():
    atlas = np.zeros((T * len(ROWS), T * VARIANTS, 3), np.uint8)
    for r, row in enumerate(ROWS):
        for v in range(VARIANTS):
            atlas[r * T:(r + 1) * T, v * T:(v + 1) * T] = make(row, v)
    rgba = np.dstack([atlas, np.full(atlas.shape[:2], 255, np.uint8)])
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(OUT / "forest_tiles.png")
    meta = {"image": "forest_tiles.png", "tile_size": T, "columns": VARIANTS, "rows": len(ROWS),
            "note": "keys are WildGen T_* ids; cells are [col,row]; pick variant by hash(x,y) % variants",
            "tiles": {str(i): {"name": n, "cells": [[v, i] for v in range(VARIANTS)]} for i, n in enumerate(ROWS)}}
    (OUT / "forest_tiles.json").write_text(json.dumps(meta, indent=1) + "\n")
    warm = set("a22512 c94d2e e19064 b9a697 f2d9c5 50361e b66813 c58845 83571e e5bd7f 9b8039 dbcc83 b1a13d 3d1f29 62272c".split())
    px = ["%02x%02x%02x" % tuple(p) for p in atlas.reshape(-1, 3)]
    print("warm share (whole atlas): %.1f%%" % (100 * sum(p in warm for p in px) / len(px)))
    land = px[: T * T * VARIANTS * 3] + px[T * T * VARIANTS * 4:]
    print("warm share excluding water row: %.1f%%" % (100 * sum(p in warm for p in land) / len(land)))


if __name__ == "__main__":
    main()
