#!/usr/bin/env python3
"""Recolor value-map sprites with color ramps and render retro "era" variants.

A value map is a sprite drawn with 5 grays (see pixel_cleanup.py --mode value-map):
  #000000 outline · #404040 tone0 (dark) · #808080 tone1 · #c0c0c0 tone2 · #ffffff tone3 (highlight)
One value map + N ramps + M eras = N×M sprites without drawing anything new.
This previews what an in-engine palette-swap shader will produce, before any code exists.

Eras (outline-preserving 2× downsample for the low ones):
  bit1  2 colors (--ink/--paper), shadow tone dithered
  tone4 4 greens (--tone4), handheld look
  bit8  outline + 2 ramp tones (3 colors per sprite)
  bit16 full 4-tone ramp
  holo  bit16 + iridescent row bands (--holo)

  python variants.py tools/style/anchor_goldfish_gray.png --ramps tools/palettes/fish_ramps.json \
      --ramp-names orange blue --eras bit1 tone4 bit8 bit16 holo --sheet /tmp/variants.png
"""
import argparse
import json
import os

import numpy as np
from PIL import Image

LEVEL = {0: -1, 64: 0, 128: 1, 192: 2, 255: 3}
ALL_ERAS = ["bit1", "tone4", "bit8", "bit16", "holo"]


def hexc(h):
    h = h.strip().lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.uint8)


def load_value_map(path):
    a = np.array(Image.open(path).convert("RGBA"))
    op = a[..., 3] == 255
    lv = np.full(op.shape, -2, int)
    for v, t in LEVEL.items():
        lv[(a[..., 0] == v) & op] = t
    bad = op & (lv == -2)
    if bad.any():
        raise SystemExit(f"{path}: {int(bad.sum())} pixels are not one of the 5 value-map grays "
                         "(run pixel_cleanup.py --mode value-map first)")
    return lv, op


def down2(lv, op):
    """2× downsample that keeps the silhouette: a cell is opaque if ≥2 of its 4 pixels are,
    its tone is the median body tone, and the new border becomes outline again."""
    h, w = lv.shape
    L = np.full((h // 2, w // 2), -1, int)
    O = np.zeros((h // 2, w // 2), bool)
    for y in range(h // 2):
        for x in range(w // 2):
            cell = lv[2 * y:2 * y + 2, 2 * x:2 * x + 2][op[2 * y:2 * y + 2, 2 * x:2 * x + 2]]
            if len(cell) >= 2:
                O[y, x] = True
                body = [t for t in cell if t >= 0]
                L[y, x] = int(np.median(body)) if body else -1
    pad = np.pad(O, 1)
    edge = O & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    L[edge] = -1
    return L, O


def render(lv, op, ramp, era, opt):
    if era in ("bit16", "holo"):
        L, O = lv, op
    else:
        L, O = down2(lv, op)
    out = np.zeros(L.shape + (4,), np.uint8)
    out[..., 3] = np.where(O, 255, 0)
    for y, x in zip(*np.nonzero(O)):
        t = L[y, x]
        if era == "bit1":
            c = opt["ink"] if t < 0 else ((opt["ink"] if (x + y) % 2 == 0 else opt["paper"]) if t == 0 else opt["paper"])
        elif era == "tone4":
            c = opt["tone4"][0] if t < 0 else opt["tone4"][min(3, t + 1)]
        elif era == "bit8":
            c = opt["ink"] if t < 0 else (ramp[1] if t <= 1 else ramp[2])
        else:
            c = opt["ink"] if t < 0 else ramp[t]
            if era == "holo" and t >= 1:
                band = opt["holo"][(y // 3) % len(opt["holo"])]
                c = ((c.astype(int) + band.astype(int)) // 2).astype(np.uint8)
        out[y, x, :3] = c
    img = Image.fromarray(out, "RGBA")
    if era not in ("bit16", "holo"):
        img = img.resize((lv.shape[1], lv.shape[0]), Image.NEAREST)
    return img


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("value_maps", nargs="+")
    p.add_argument("--ramps", required=True, help='JSON file {"name": ["dark","mid","light","highlight"], ...}')
    p.add_argument("--ramp-names", nargs="*", default=None, help="subset of ramps (default: all)")
    p.add_argument("--eras", nargs="*", default=ALL_ERAS, choices=ALL_ERAS)
    p.add_argument("--ink", default="0d0b1a")
    p.add_argument("--paper", default="f4ecdf")
    p.add_argument("--tone4", nargs=4, default=["0f380f", "306230", "8bac0f", "9bbc0f"])
    p.add_argument("--holo", nargs="+", default=["9af0e0", "d08cc0", "ffc56b"])
    p.add_argument("--out-dir", help="write <stem>__<ramp>__<era>.png files here")
    p.add_argument("--sheet", help="write one preview sheet (rows = sprite×ramp, cols = eras)")
    p.add_argument("--scale", type=int, default=4)
    p.add_argument("--bg", default="1e1b45")
    args = p.parse_args()
    if not args.out_dir and not args.sheet:
        raise SystemExit("give --out-dir and/or --sheet")

    with open(args.ramps, encoding="utf-8") as f:
        ramps = {k: [hexc(c) for c in v] for k, v in json.load(f).items()}
    names = args.ramp_names or list(ramps)
    opt = {"ink": hexc(args.ink), "paper": hexc(args.paper),
           "tone4": [hexc(c) for c in args.tone4], "holo": [hexc(c) for c in args.holo]}

    rows = []
    for path in args.value_maps:
        lv, op = load_value_map(path)
        stem = os.path.splitext(os.path.basename(path))[0]
        for name in names:
            row = [render(lv, op, ramps[name], era, opt) for era in args.eras]
            rows.append(row)
            if args.out_dir:
                os.makedirs(args.out_dir, exist_ok=True)
                for era, img in zip(args.eras, row):
                    img.save(os.path.join(args.out_dir, f"{stem}__{name}__{era}.png"))
    if args.sheet:
        cw = max(r[0].width for r in rows) + 8
        ch = max(r[0].height for r in rows) + 8
        bg = tuple(hexc(args.bg).tolist()) + (255,)
        sheet = Image.new("RGBA", (len(args.eras) * cw + 8, len(rows) * ch + 8), bg)
        for r, row in enumerate(rows):
            for c, img in enumerate(row):
                sheet.alpha_composite(img, (8 + c * cw, 8 + r * ch))
        sheet = sheet.resize((sheet.width * args.scale, sheet.height * args.scale), Image.NEAREST)
        os.makedirs(os.path.dirname(os.path.abspath(args.sheet)), exist_ok=True)
        sheet.save(args.sheet)
        print(f"{args.sheet} {sheet.width}x{sheet.height} ({len(rows)} rows × {len(args.eras)} eras)")
    if args.out_dir:
        print(f"{len(rows) * len(args.eras)} files in {args.out_dir}")


if __name__ == "__main__":
    main()
