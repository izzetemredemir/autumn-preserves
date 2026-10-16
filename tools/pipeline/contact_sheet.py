#!/usr/bin/env python3
"""Put many small images on one upscaled sheet (nearest-neighbour, crisp pixels).

Review a whole batch with ONE image read instead of one read per asset, and hand
the same sheet to the human. Transparent pixels show over --bg.

  python contact_sheet.py tools/style/anchor_*_gray.png --out /tmp/sheet.png --scale 4
  python contact_sheet.py game/assets/sprites/fish --out sheet.png --cols 6 --labels
"""
import argparse
import glob
import os

from PIL import Image, ImageDraw


def collect(inputs):
    files = []
    for item in inputs:
        if os.path.isdir(item):
            files += sorted(glob.glob(os.path.join(item, "**", "*.png"), recursive=True))
        else:
            files += sorted(glob.glob(item)) or [item]
    return [f for f in files if os.path.isfile(f)]


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("inputs", nargs="+", help="files, globs or directories")
    p.add_argument("--out", required=True)
    p.add_argument("--scale", type=int, default=4, help="integer upscale factor")
    p.add_argument("--cols", type=int, default=0, help="0 = auto")
    p.add_argument("--pad", type=int, default=4, help="padding in source pixels")
    p.add_argument("--bg", default="1e1b45", help="background hex")
    p.add_argument("--labels", action="store_true", help="print file stem under each cell")
    p.add_argument("--max-px", type=int, default=1600, help="shrink scale until the sheet fits this width")
    args = p.parse_args()

    files = collect(args.inputs)
    if not files:
        raise SystemExit("no images found")
    ims = [Image.open(f).convert("RGBA") for f in files]
    cw = max(i.width for i in ims) + args.pad
    ch = max(i.height for i in ims) + args.pad + (8 if args.labels else 0)
    cols = args.cols or min(len(ims), max(1, int(len(ims) ** 0.5 + 0.999)))
    rows = (len(ims) + cols - 1) // cols
    scale = args.scale
    while scale > 1 and (cols * cw + args.pad) * scale > args.max_px:
        scale -= 1
    bg = tuple(int(args.bg[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
    sheet = Image.new("RGBA", (cols * cw + args.pad, rows * ch + args.pad), bg)
    for k, im in enumerate(ims):
        x = args.pad + (k % cols) * cw
        y = args.pad + (k // cols) * ch
        sheet.alpha_composite(im, (x, y))
    sheet = sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)
    if args.labels:
        d = ImageDraw.Draw(sheet)
        for k, f in enumerate(files):
            x = (args.pad + (k % cols) * cw) * scale
            y = (args.pad + (k // cols) * ch + ch - 8) * scale
            d.text((x, y), os.path.splitext(os.path.basename(f))[0][:24], fill=(244, 236, 223, 255))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    sheet.save(args.out)
    print(f"{args.out} {sheet.width}x{sheet.height} ({len(ims)} images, scale {scale})")


if __name__ == "__main__":
    main()
