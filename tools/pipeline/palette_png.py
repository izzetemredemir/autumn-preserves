#!/usr/bin/env python3
"""Make Nx1 palette/ramp textures for shaders from .hex files or a ramps JSON.

  palette_png.py tools/palettes/main.hex --out game/assets/palettes/main.png        # 32x1
  palette_png.py --ramps tools/palettes/fish_ramps.json --out-dir game/assets/palettes/ramps   # one 4x1 per ramp
Import the PNGs in Godot with filter Nearest (project default after setup_project.sh).
"""
import argparse
import json
import os

from PIL import Image


def hexes(path):
    out = []
    for line in open(path, encoding="utf-8"):
        line = line.strip().lstrip("#")
        if line:
            out.append(tuple(int(line[i:i + 2], 16) for i in (0, 2, 4)))
    return out


def save(colors, path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    im = Image.new("RGBA", (len(colors), 1))
    im.putdata([c + (255,) for c in colors])
    im.save(path)
    print(f"{path} {len(colors)}x1")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("hex", nargs="?")
    p.add_argument("--out")
    p.add_argument("--ramps")
    p.add_argument("--out-dir")
    a = p.parse_args()
    if a.hex:
        save(hexes(a.hex), a.out or os.path.splitext(a.hex)[0] + ".png")
    if a.ramps:
        with open(a.ramps, encoding="utf-8") as f:
            for name, cols in json.load(f).items():
                save([tuple(int(c.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) for c in cols],
                     os.path.join(a.out_dir or ".", f"{name}.png"))
    if not a.hex and not a.ramps:
        p.error("give a .hex file and/or --ramps")


if __name__ == "__main__":
    main()
