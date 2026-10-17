#!/usr/bin/env python3
"""SPECIES-GEN icon templates: 16x16 value maps (5 grays) made deterministically from the approved ingredient icons.
Run from repo root:  python3 tools/procedural/species_templates.py
Writes game/assets/masks/species/<template>.png (value maps live under masks/: tech-spec §10, not palette-linted).
At runtime IconLib recolours a template with a species ramp: gray 0 on the silhouette edge -> ink 111010, gray 0
inside -> ramp[0], 64 / 128 / 192 / 255 -> ramp[1..4]. Check: pixel_cleanup.py --check --mode value-map.

Levels per source icon: outline-dark pixels (luminance < 60) -> 0; the body colour (the most used colour above that)
-> 128; darker -> 64; up to +60 lighter -> 192; lighter still -> 255. Two templates are reshaped or drawn here:
mushroom_tall (the porcini with a shorter cap and a longer stalk) and veg_leafy (a leafy bunch, drawn below).
No paid generations.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ICONS = ROOT / "game/assets/sprites/icons"
OUT = ROOT / "game/assets/masks/species"
GRAYS = [0, 64, 128, 192, 255]

# template -> (group, source icon); None = drawn below
TEMPLATES = {
    "fruit_round": ("fruit", "apple"),
    "fruit_cluster": ("fruit", "crabapple"),
    "fruit_pear": ("fruit", "pear"),
    "fruit_bramble": ("fruit", "blackberry"),
    "mushroom_cap": ("mushroom", "porcini"),
    "mushroom_funnel": ("mushroom", "chanterelle"),
    "mushroom_tall": ("mushroom", "porcini"),
    "mushroom_fan": ("mushroom", "oyster_mushroom"),
    "veg_root": ("vegetable", "ginger"),
    "veg_pod": ("vegetable", "chili"),
    "veg_round": ("vegetable", "pepper"),
    "veg_leafy": ("vegetable", None),
}

# mushroom_tall: the porcini cap rows kept (6 of 8), then this thin stalk (digits = levels, "." transparent).
TALL_STALK = """
......04430.....
......04430.....
......04430.....
......04431.....
.....0444310....
.....0000000....
....000000000...
"""
# veg_leafy: three leaves (ellipses: centre x, centre y, radius x, radius y) over a tied stalk bundle.
LEAVES = [(7.5, 5.2, 2.7, 4.9), (3.4, 8.2, 2.3, 3.3), (11.6, 8.2, 2.3, 3.3)]


def lum(rgb):
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


def levels(icon):
    """16x16 int array: -1 transparent, 0..4 value level."""
    a = np.array(Image.open(ICONS / f"{icon}.png").convert("RGBA")).astype(np.float64)
    op = a[..., 3] >= 128
    lv = np.full(op.shape, -1, dtype=np.int64)
    lm = lum(a[..., :3])
    body = [tuple(int(v) for v in a[y, x, :3]) for y, x in zip(*np.nonzero(op & (lm >= 60)))]
    main = max(sorted(set(body)), key=body.count)
    ml = float(lum(np.array(main, dtype=np.float64)))
    for y, x in zip(*np.nonzero(op)):
        v = lm[y, x]
        if v < 60:
            lv[y, x] = 0
        elif v < ml - 15:
            lv[y, x] = 1
        elif v <= ml + 15:
            lv[y, x] = 2
        elif v <= ml + 60:
            lv[y, x] = 3
        else:
            lv[y, x] = 4
    return lv


def tall(lv):
    """The porcini cap (rows 2 and 5 dropped) on a thin stalk (TALL_STALK)."""
    cap = lv[[0, 1, 3, 4, 6, 7]]
    stalk = drawn(TALL_STALK)
    out = np.full((16, 16), -1, dtype=np.int64)
    out[2:2 + len(cap)] = cap
    out[2 + len(cap):2 + len(cap) + len(stalk)] = stalk
    return out


def leafy():
    """Three leaves (lit left, shaded right, a light vein) over a tied stalk bundle, 1 px outline around."""
    lv = np.full((16, 16), -1, dtype=np.int64)
    owner = np.full((16, 16), -1, dtype=np.int64)
    order = [1, 2, 0]  # side leaves first, the centre leaf on top
    for k in order:
        cx, cy, rx, ry = LEAVES[k]
        for y in range(16):
            for x in range(16):
                dx, dy = x - cx, y - cy
                if (dx / rx) ** 2 + (dy / ry) ** 2 > 1.0:
                    continue
                owner[y, x] = k
                if -0.5 <= dx < 0.5 and dy > -ry * 0.6:
                    lv[y, x] = 4
                elif dx < -0.35 * rx:
                    lv[y, x] = 3
                elif dx > 0.4 * rx:
                    lv[y, x] = 1
                else:
                    lv[y, x] = 2
    for y in range(10, 14):  # stalk bundle and its tie
        lv[y, 7], lv[y, 8] = 3, 1
        owner[y, 7] = owner[y, 8] = 3
    lv[11, 6:10] = 4
    owner[11, 6:10] = 3
    # side leaves meet the centre leaf on a dark seam
    for y in range(16):
        for x in range(16):
            if owner[y, x] in (1, 2):
                for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if 0 <= ny < 16 and 0 <= nx < 16 and owner[ny, nx] == 0:
                        lv[y, x] = 0
    out = lv.copy()
    for y in range(16):
        for x in range(16):
            if lv[y, x] >= 0:
                continue
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < 16 and 0 <= nx < 16 and lv[ny, nx] >= 0:
                    out[y, x] = 0
    return out


def drawn(text):
    rows = [r for r in text.strip("\n").splitlines()]
    assert all(len(r) == 16 for r in rows), "drawn rows must be 16 wide"
    return np.array([[-1 if ch == "." else int(ch) for ch in r] for r in rows], dtype=np.int64)


def to_image(lv):
    img = np.zeros((16, 16, 4), dtype=np.uint8)
    for y in range(16):
        for x in range(16):
            if lv[y, x] >= 0:
                g = GRAYS[lv[y, x]]
                img[y, x] = (g, g, g, 255)
    return Image.fromarray(img, "RGBA")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    made = {}
    for name, (group, icon) in TEMPLATES.items():
        if icon is None:
            lv = leafy()
        else:
            lv = levels(icon)
            if name == "mushroom_tall":
                lv = tall(lv)
        to_image(lv).save(OUT / f"{name}.png")
        made[name] = {"group": group, "from": icon or "drawn",
                      "levels": {str(k): int((lv == k).sum()) for k in range(5)}}
    print(json.dumps(made, indent=1))


if __name__ == "__main__":
    main()
