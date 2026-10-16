#!/usr/bin/env python3
"""Review sheets: icons_x4.png (contact sheet) and icons_on_ground_x2.png (icons on forest tiles).
Run from the repo root after build.py."""
import json, subprocess, sys, pathlib
from PIL import Image

ICONS = pathlib.Path("game/assets/sprites/icons")
REV = pathlib.Path("tools/style/review")

atlas = Image.open(ICONS / "icons.png").convert("RGBA")
meta = json.load(open(ICONS / "icons.json"))
ids = list(meta["icons"])
# x4 sheet: 6 columns, 8 px padding on a neutral mid bg
cols, pad = meta["cols"], 8
rows = (len(ids) + cols - 1) // cols
S = 4
sheet = Image.new("RGBA", (cols * (16 * S + pad) + pad, rows * (16 * S + pad) + pad), (0x49, 0x42, 0x3d, 255))
for n, i in enumerate(ids):
    cx, cy = meta["icons"][i]
    cell = atlas.crop((cx * 16, cy * 16, cx * 16 + 16, cy * 16 + 16)).resize((16 * S, 16 * S), Image.NEAREST)
    sheet.alpha_composite(cell, (pad + (n % cols) * (16 * S + pad), pad + (n // cols) * (16 * S + pad)))
sheet.save(REV / "icons_x4.png")

# on-ground x2: one band per ground type (grass, leaves, dirt), 7 icons per band, each icon on its own 2x2 tile block
tiles = Image.open("game/assets/sprites/tiles/forest_tiles.png").convert("RGBA")
per = 7
bands = [0, 1, 2]
nrows = (len(ids) + per - 1) // per
canvas = Image.new("RGBA", (per * 16, nrows * len(bands) * 16), (0, 0, 0, 255))
for b, trow in enumerate(bands):
    for n, i in enumerate(ids):
        x, y = n % per, n // per
        tile = tiles.crop(((n % 4) * 16, trow * 16, (n % 4) * 16 + 16, trow * 16 + 16))
        px, py = x * 16, (y * len(bands) + b) * 16
        canvas.paste(tile, (px, py))
        cx, cy = meta["icons"][i]
        canvas.alpha_composite(atlas.crop((cx * 16, cy * 16, cx * 16 + 16, cy * 16 + 16)), (px, py))
canvas.resize((canvas.width * 2, canvas.height * 2), Image.NEAREST).save(REV / "icons_on_ground_x2.png")
