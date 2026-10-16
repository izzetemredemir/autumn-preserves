#!/usr/bin/env python3
"""Compose a screen mock from a JSON layout: background + sprites at exact pixel positions.

Check layout, scale and readability of real assets BEFORE any game code exists.
Layout file:
{
  "background": "tools/style/anchor_room.png",      // or {"size": [480, 270], "color": "1e1b45"}
  "crop": [56, 45, 480, 270],                         // optional: x, y, w, h (e.g. the safe area)
  "layers": [                                          // drawn in order; pos is after crop
    {"img": "tools/style/anchor_fishbowl.png", "pos": [165, 86]},
    {"img": "out/variants/goldfish__orange__bit16.png", "pos": [224, 146]},
    {"img": "game/assets/sprites/room/obj_record_player.png", "pos": [12, 182], "frame": [0, 4]}  // frame i of n
  ],
  "views": [                                           // optional extra crops (e.g. zoomed views)
    {"name": "bowl_closeup", "rect": [120, 82, 240, 135]}
  ],
  "scale": 2,
  "out": "tools/style/mock_room.png"
}
  python compose_mock.py layout.json
"""
import json
import os
import sys

from PIL import Image


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    with open(sys.argv[1], encoding="utf-8") as f:
        lay = json.load(f)
    bg = lay["background"]
    if isinstance(bg, str):
        canvas = Image.open(bg).convert("RGBA")
    else:
        h = bg.get("color", "000000")
        canvas = Image.new("RGBA", tuple(bg["size"]), tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,))
    if "crop" in lay:
        x, y, w, h = lay["crop"]
        canvas = canvas.crop((x, y, x + w, y + h))
    for layer in lay.get("layers", []):
        im = Image.open(layer["img"]).convert("RGBA")
        if "frame" in layer:  # [i, n]: take frame i of a horizontal n-frame sheet
            i, n = layer["frame"]
            fw = im.width // n
            im = im.crop((i * fw, 0, (i + 1) * fw, im.height))
        canvas.alpha_composite(im, tuple(layer["pos"]))
    scale = int(lay.get("scale", 2))
    out = lay["out"]
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    canvas.resize((canvas.width * scale, canvas.height * scale), Image.NEAREST).save(out)
    print(out, f"{canvas.width}x{canvas.height} ×{scale}")
    stem, ext = os.path.splitext(out)
    for v in lay.get("views", []):
        x, y, w, h = v["rect"]
        vout = f"{stem}_{v['name']}{ext}"
        k = max(1, 960 // w)
        canvas.crop((x, y, x + w, y + h)).resize((w * k, h * k), Image.NEAREST).save(vout)
        print(vout, f"{w}x{h} ×{k}")


if __name__ == "__main__":
    main()
