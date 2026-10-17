#!/usr/bin/env python3
"""JURY-PANTRY: a brighter, warmer pantry backdrop from bg_pantry.png, palette-clean.

Every dark and mid pixel moves one step up a warm value ladder of the autumn palette (no overlay, no new colour,
no alpha): the near-black shelf backs come up to plum, the plum door to bark, wood and floor one tone lighter.
Pixels keep their place, so the shelf rows, name plates and BG_STRIPS of pantry.gd still line up.

  python3 tools/style/src/pantry/bg_pantry_light.py [--out PATH]
  python3 tools/pipeline/pixel_cleanup.py --check --in game/assets/sprites/scenes/bg_pantry_light.png \
      --size any --palette tools/palettes/autumn.hex
"""
import argparse
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
SRC = ROOT / "game/assets/sprites/scenes/bg_pantry.png"
OUT = ROOT / "game/assets/sprites/scenes/bg_pantry_light.png"

## Darkest first. Colours not listed stay as they are (the lightest tones, small accents). Picked over a redder
## ladder (plum door -> wine) and a darks-only one: brown wood reads warmest and the jars' ink rims stay crisp.
LADDER = {
    "111010": "3d1f29",  # ink -> plum (shelf backs, deep gaps)
    "23282a": "49423d",  # slate -> stone 700
    "3d1f29": "50361e",  # plum -> bark 900 (door planks)
    "50361e": "83571e",  # bark 900 -> bark 700
    "62272c": "83571e",  # wine -> bark 700
    "83571e": "b66813",  # bark 700 -> amber (wood, floor)
    "b66813": "c58845",  # amber -> bark 500
    "49423d": "81746a",  # stone 700 -> stone 500
}


def remap(src: Path, out: Path, table: dict) -> None:
    im = Image.open(src).convert("RGBA")
    px = im.load()
    rgb = {k: tuple(int(v[i:i + 2], 16) for i in (0, 2, 4)) for k, v in table.items()}
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            hit = rgb.get("%02x%02x%02x" % (r, g, b))
            if hit is not None:
                px[x, y] = hit + (a,)
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)
    print("wrote", out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(OUT))
    a = ap.parse_args()
    remap(SRC, Path(a.out), LADDER)


if __name__ == "__main__":
    main()
