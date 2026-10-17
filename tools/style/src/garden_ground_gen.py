#!/usr/bin/env python3
"""GARDEN-GROUND: repaints the garden's ground (480x272) as a calm dry lawn with leaf drifts in patches.

Starts from the first painted version (tools/style/raw/garden_ground_v1_game.png, the leaf carpet) and keeps its
back hedge and its dirt path and road pixel for pixel. Everything else becomes a lawn of three muted tones
(gold_700, olive_500, olive_600) with sparse grass tufts. The old leaf carpet stays only inside drifts: under the
three trees, in stretches along the hedge and the fences, and as single leaves scattered on the grass; the drift
edges break up into separate leaves. Worn dirt rings the four P0 beds and the compost bin, and the hens have
scratched the floor of their run bare. Positions mirror game/scenes/garden/garden_layout.gd and garden_props.json:
move them and this file together. Deterministic (fixed seed), palette tools/palettes/autumn.hex only.
  python3 tools/style/src/garden_ground_gen.py   (from the repo root)
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
SRC = os.path.join(ROOT, "tools/style/raw/garden_ground_v1_game.png")
OUT = os.path.join(ROOT, "game/assets/sprites/garden/garden_ground.png")
W, H, T = 480, 272, 16
SEED = 1610

# garden_layout.gd (cells -> pixels)
PATH_X = (13 * T, 15 * T)  # PATH_COLS 13-14
ROAD_Y = (9 * T, 11 * T)  # ROAD_ROWS 9-10
TREE_FEET = [(3 * T + 8, 8 * T), (3 * T + 8, 14 * T), (24 * T + 8, 16 * T)]  # apple, quince, walnut
BEDS = [(7, 8), (10, 8), (7, 11), (10, 11)]  # P0 beds (left cell); the P1 pair at row 14 stays lawn
COMPOST = (190, 171, 210, 193)
HEN_RUN = (19 * T, 4 * T, 23 * T, 8 * T)  # garden_props.json hen_run [19, 4, 4, 4]

HEX = [h.strip() for h in open(os.path.join(ROOT, "tools/palettes/autumn.hex")) if h.strip()]


def rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.uint8)


C = {h: rgb(h) for h in HEX}
LAWN_DARK, LAWN_MID, LAWN_LIGHT = "747c37", "9b8039", "b1a13d"  # art bible 1.3: dry grass
TUFT_DARK, TUFT_DEEP, TUFT_TIP = "747c37", "53612e", "c5bf3f"
DIRT, DIRT_DARK, DIRT_LIGHT = "c58845", "83571e", "e5bd7f"
PATH_COLS = {"e5bd7f", "f2d9c5", "dbcc83"}  # the painted path's light dirt
HEDGE_DARK = {"111010", "23282a", "50361e", "3d1f29", "53612e", "314524"}
LEAF_GAP = {"83571e", "50361e", "9b8039", "b1a13d", "c5bf3f", "b7b768", "747c37", "53612e", "3d1f29"}

# Leaf stamps: l light (top-left), b body, d dark. Light comes from the top left, so no mirroring.
STAMPS = [
    [".l.b.", "lbbbd", ".bbd.", "..d.."],
    [".lb.", "lbbd", ".bdd", "..d."],
    [".l.", "lbd", ".d."],
    ["lb..", "bbbd", ".dd."],
    ["..l..", "llbbb", ".bbbd", "bbddd", "..d.."],
    ["lb", "bd"],
    [".lb", "lbd", "bd."],
]
BIG = [0, 1, 3, 4, 6]
LEAF_COLOURS = [  # (light, body, dark), weight
    (("e19064", "c94d2e", "a22512"), 0.34),
    (("c94d2e", "a22512", "62272c"), 0.2),
    (("c58845", "b66813", "83571e"), 0.2),
    (("e5bd7f", "c58845", "b66813"), 0.14),
    (("e5bd7f", "e19064", "c94d2e"), 0.12),
]


def value_noise(rng, cell, shape=(H, W)):
    """Smooth value noise in 0..1 with lattice spacing `cell` px."""
    gh, gw = shape[0] // cell + 3, shape[1] // cell + 3
    lat = rng.random((gh, gw))
    ys, xs = np.mgrid[0:shape[0], 0:shape[1]] / cell
    y0, x0 = ys.astype(int), xs.astype(int)
    fy, fx = ys - y0, xs - x0
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a, b = lat[y0, x0], lat[y0, x0 + 1]
    c, d = lat[y0 + 1, x0], lat[y0 + 1, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def noise_1d(rng, n, cell):
    lat = rng.random(n // cell + 3)
    t = np.arange(n) / cell
    i = t.astype(int)
    f = t - i
    f = f * f * (3 - 2 * f)
    return lat[i] * (1 - f) + lat[i + 1] * f


def rect_dist(x0, y0, x1, y1):
    ys, xs = np.mgrid[0:H, 0:W] + 0.5
    dx = np.maximum(np.maximum(x0 - xs, xs - x1), 0)
    dy = np.maximum(np.maximum(y0 - ys, ys - y1), 0)
    return np.hypot(dx, dy)


def main():
    rng = np.random.default_rng(SEED)
    src = np.array(Image.open(SRC).convert("RGB"))
    assert src.shape == (H, W, 3), src.shape
    hexes = np.vectorize(lambda r, g, b: "%02x%02x%02x" % (r, g, b))(src[..., 0], src[..., 1], src[..., 2])
    isin = lambda s: np.isin(hexes, list(s))
    ys, xs = np.mgrid[0:H, 0:W]

    # 1. what stays from v1: the hedge (down to its dark lower edge) and the path and road
    dark = isin(HEDGE_DARK)
    line = np.array([max([y for y in range(14, 40) if dark[y, x]] or [26]) + 1 for x in range(W)])
    line = np.clip(ndimage.median_filter(line, size=7, mode="nearest"), 24, 36)
    hedge = ys < line[None, :]
    band = ((xs >= PATH_X[0] - 7) & (xs < PATH_X[1] + 7) & (ys >= 20)) | \
           ((ys >= ROAD_Y[0] - 7) & (ys < ROAD_Y[1] + 7) & (xs >= PATH_X[1] - 4))
    dirt = isin(PATH_COLS) & band
    path = ndimage.binary_closing(dirt, structure=np.ones((5, 5)), iterations=1) & band
    path = ndimage.binary_opening(path, structure=np.ones((3, 3))) & band
    path = ndimage.binary_fill_holes(path)
    lab, n = ndimage.label(path)
    sizes = ndimage.sum(path, lab, range(1, n + 1))
    path = lab == (1 + int(np.argmax(sizes)))
    keep = hedge | path

    # 2. lawn: three tones from low-frequency noise, ragged edges from fine noise, sparse speckle
    t = 0.66 * value_noise(rng, 52) + 0.34 * value_noise(rng, 19) + 0.12 * (rng.random((H, W)) - 0.5)
    q_dark, q_light = np.quantile(t, [0.13, 0.82])
    out = np.empty((H, W, 3), dtype=np.uint8)
    tone = np.where(t < q_dark, 0, np.where(t > q_light, 2, 1))
    speck = rng.random((H, W))
    tone = np.where((speck < 0.025) & (tone == 1), 0, tone)
    tone = np.where((speck > 0.98) & (tone == 1), 2, tone)
    for i, h in enumerate((LAWN_DARK, LAWN_MID, LAWN_LIGHT)):
        out[tone == i] = C[h]

    def put(x, y, h, mask=None):
        if 0 <= x < W and 0 <= y < H and not keep[y, x] and (mask is None or mask[y, x]):
            out[y, x] = C[h]

    # grass tufts: a dark blade pair, sometimes with a light tip
    tufts = rng.random((H, W)) < 1 / 85
    for y, x in zip(*np.nonzero(tufts)):
        dk = TUFT_DEEP if tone[y, x] == 0 else TUFT_DARK
        kind = rng.integers(4)
        if kind == 0:
            put(x, y, dk); put(x + 2, y, dk); put(x + 1, y + 1, dk)
        elif kind == 1:
            put(x, y, TUFT_TIP if tone[y, x] == 2 else LAWN_LIGHT); put(x, y + 1, dk)
        elif kind == 2:
            put(x, y, dk); put(x + 1, y + 1, dk); put(x + 1, y, LAWN_LIGHT)
        else:
            put(x, y, dk); put(x, y + 1, dk); put(x + 1, y + 1, dk)

    # 3. worn dirt: around the P0 beds and the compost bin, and the hens' scratched run floor
    wn = value_noise(rng, 5) - 0.5
    wear = np.full((H, W), 99.0)
    for cx, cy in BEDS:
        x0, y1 = cx * T, (cy + 1) * T
        wear = np.minimum(wear, rect_dist(x0, y1 - 18, x0 + 32, y1) - 4.5)
    wear = np.minimum(wear, rect_dist(*COMPOST) - 3.0)
    run = rect_dist(HEN_RUN[0] + 7, HEN_RUN[1] + 10, HEN_RUN[2] - 7, HEN_RUN[3] - 7) - 2.0
    wear = np.minimum(wear, run)
    wear = wear + 5.0 * wn
    soil = (wear < 0) & ~keep
    rim = (wear >= 0) & (wear < 1.4) & ~keep & (rng.random((H, W)) < 0.5)
    r = rng.random((H, W))
    out[soil] = C[DIRT]
    out[soil & (r < 0.07)] = C[DIRT_DARK]
    out[soil & (r > 0.95)] = C[DIRT_LIGHT]
    out[rim] = C[DIRT_DARK]
    straw = (run < -3 + 3.0 * wn) & ~keep & (r > 0.86) & (r < 0.93)
    out[straw] = C["dbcc83"]

    # 4. leaf drifts: density from the trees, the hedge and the fences, broken up by noise
    rho = np.zeros((H, W))
    for fx, fy in TREE_FEET:
        d = np.hypot((xs - fx) / 36.0, (ys - fy + 6) / 20.0)
        rho = np.maximum(rho, 1.0 - d)
    def strip(dist, along, n, cell, width):
        seg = np.clip(noise_1d(rng, n, cell) * 2.4 - 1.1, 0, 1)
        w = width * seg[along]
        return np.where(w > 0.5, 1.0 - dist / np.maximum(w, 0.5), 0.0)
    rho = np.maximum(rho, strip(np.maximum(xs - 15, 0), ys, H, 26, 20))  # left fence
    rho = np.maximum(rho, strip(np.maximum(464 - xs, 0), ys, H, 26, 20))  # right fence
    rho = np.maximum(rho, strip(np.maximum(258 - ys, 0), xs, W, 30, 18))  # bottom fence
    rho = np.maximum(rho, strip(np.maximum(ys - line[None, :], 0), xs, W, 34, 14))  # under the hedge
    rho = rho + 0.34 * (value_noise(rng, 9) - 0.5) + 0.14 * (value_noise(rng, 4) - 0.5)
    core = (rho > 0.42) & ~keep & ~soil
    core = ndimage.binary_opening(core, structure=np.ones((3, 3)))
    edge_px = core & ~ndimage.binary_erosion(core, structure=np.ones((5, 5)))
    carpet = core & ~(edge_px & isin(LEAF_GAP))  # at the drift's edge only whole leaves stay, the gaps are grass
    out[carpet] = src[carpet]

    # separate leaves: thick at the drift edges, rare on the open lawn, a few on the dirt
    p = np.clip((rho - 0.12) / 0.3, 0, 1) * 0.05 + 0.0007
    p = np.where(soil, 0.004, p)
    seeds = (rng.random((H, W)) < p) & ~keep & ~core
    weights = np.array([w for _, w in LEAF_COLOURS])
    for y, x in zip(*np.nonzero(seeds)):
        big = rho[y, x] < 0.12  # alone on the lawn: only the bigger leaves, the small ones read as specks
        shape = STAMPS[BIG[rng.integers(len(BIG))] if big else rng.integers(len(STAMPS))]
        cols = LEAF_COLOURS[rng.choice(len(LEAF_COLOURS), p=weights / weights.sum())][0]
        for dy, row in enumerate(shape):
            for dx, ch in enumerate(row):
                if ch != ".":
                    put(x + dx, y + dy, cols["lbd".index(ch)])

    out[keep] = src[keep]
    Image.fromarray(out, "RGB").convert("RGBA").save(OUT)
    used = len(np.unique(out.reshape(-1, 3), axis=0))
    print(f"wrote {os.path.relpath(OUT, ROOT)} {W}x{H}, {used} colours; path px {int(path.sum())}, "
          f"hedge px {int(hedge.sum())}, drift px {int(core.sum())}, leaves {int(seeds.sum())}, dirt px {int(soil.sum())}")


if __name__ == "__main__":
    main()
