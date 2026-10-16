#!/usr/bin/env python3
"""Pixel art as text: draw or fix sprites one character per pixel, render them to PNG.

Why: an agent can read and edit a 32×32 sprite as 32 lines of text far more precisely
than through image tools. The text file is the diffable source; the PNG is the build.

Source format (.txt):
    # comment
    legend . transparent          # one char per line: <char> <hex|transparent|palette role>
    legend # 000000
    legend k ink                  # role names come from --roles (default: art-bible main palette)
    legend value                  # shortcut: . # d m l W = transparent + the 5 value-map grays
    frame                         # each frame starts with "frame"; all frames share one size
    ..##..
    .#ll#.
    frame
    ...

  render: python ascii_sprite.py render src.txt --out sheet.png [--scale 8 --preview prev.png]
          frames go left→right on one row (art-bible §2 sheet rule)
          --variant "#=ink,d=c8692f,m=lamp_400"  (repeatable) re-renders all frames with legend
          overrides and appends them: one source → per-era / per-color strips in one sheet
          --cols N  lays the frames out as an atlas grid (row-major) instead of one row, e.g. 16×16 icon atlases
          --outline [ROLE|hex]  adds a 1 px 4-neighbour outline (default ink) around every frame's shape,
                    so you can draw fills only and let the tool close the silhouette
  dump:   python ascii_sprite.py dump in.png --frames 4 [--legend value] > src.txt
          turns an existing PNG into an editable source (auto legend for non-gray colors)
"""
import argparse
import re
import sys

import numpy as np
from PIL import Image

VALUE_LEGEND = {".": None, "#": "000000", "d": "404040", "m": "808080", "l": "c0c0c0", "W": "ffffff"}
# art-bible §1 Vintage Autumn role names
MAIN_ROLES = {
    "ink": "111010", "slate_900": "23282a", "stone_700": "49423d", "stone_500": "81746a",
    "stone_300": "b4b3a0", "leaf_red_700": "a22512", "leaf_red_500": "c94d2e",
    "leaf_peach_300": "e19064", "gold_700": "9b8039", "amber_600": "b66813", "gold_300": "e5bd7f",
    "gold_200": "dbcc83", "bark_900": "50361e", "bark_700": "83571e", "bark_500": "c58845",
    "cream_400": "b9a697", "cream_100": "f2d9c5", "olive_900": "314524", "olive_800": "53612e",
    "olive_600": "747c37", "olive_500": "b1a13d", "olive_300": "b7b768", "olive_200": "c5bf3f",
    "water_900": "2e3f3f", "water_800": "275e4c", "water_700": "415c5d", "water_600": "4e7664",
    "water_500": "567c7d", "sage_400": "738c7a", "plum_900": "3d1f29", "wine_700": "62272c",
}
AUTO_CHARS = "abcefghijknopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVXYZ0123456789@$%&*+=?"


def color_value(val, roles=MAIN_ROLES):
    val = val.strip().lstrip("#").lower()
    if val == "transparent":
        return None
    if val in roles:
        return roles[val]
    if re.fullmatch(r"[0-9a-f]{6}", val):
        return val
    raise ValueError(val)


def parse_variant(spec):
    out = {}
    for part in spec.split(","):
        ch, _, val = part.partition("=")
        if len(ch) != 1 or not val:
            sys.exit(f"bad --variant entry '{part}' (want <char>=<hex|role|transparent>)")
        try:
            out[ch] = color_value(val)
        except ValueError:
            sys.exit(f"bad color in --variant: '{val}'")
    return out


def parse(path, roles=MAIN_ROLES, override=None):
    legend, frames, cur = {}, [], None
    for n, raw in enumerate(open(path, encoding="utf-8"), 1):
        s = raw.strip()
        if not s or s.startswith("# "):          # blank line or comment ("# " — a row never has spaces)
            continue
        if s == "frame":
            cur = []
            frames.append(cur)
            continue
        if s.startswith("legend "):
            parts = s.split()
            if parts[1:] == ["value"]:
                legend.update(VALUE_LEGEND)
                continue
            if len(parts) < 3 or len(parts[1]) != 1:
                sys.exit(f"{path}:{n}: expected 'legend <char> <hex|transparent|role>'")
            try:
                legend[parts[1]] = color_value(parts[2], roles)
            except ValueError:
                sys.exit(f"{path}:{n}: unknown color '{parts[2]}'")
            continue
        if cur is None:
            sys.exit(f"{path}:{n}: sprite rows before the first 'frame'")
        cur.append(s)
    if not frames:
        sys.exit(f"{path}: no frames")
    legend.update(override or {})
    h, w = len(frames[0]), max(len(r) for r in frames[0])
    out = []
    for i, fr in enumerate(frames):
        if len(fr) != h or any(len(r) != w for r in fr):
            sys.exit(f"{path}: frame {i} is not {w}x{h} (rows: {sorted({len(r) for r in fr})}, {len(fr)} rows)")
        a = np.zeros((h, w, 4), np.uint8)
        for y, row in enumerate(fr):
            for x, ch in enumerate(row):
                if ch not in legend:
                    sys.exit(f"{path}: frame {i} row {y} col {x}: char '{ch}' not in legend")
                c = legend[ch]
                if c is not None:
                    a[y, x] = [int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), 255]
        out.append(a)
    return out


def outline(frame, color):
    """1 px outline in the transparent pixels that touch the shape (4-neighbourhood), inside the frame."""
    op = frame[..., 3] > 0
    p = np.pad(op, 1)
    near = p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    out = frame.copy()
    out[near & ~op] = [int(color[0:2], 16), int(color[2:4], 16), int(color[4:6], 16), 255]
    return out


def render(frames, cols=0):
    """One row (default) or an atlas grid of `cols` columns, row-major, no gaps; empty cells stay transparent."""
    if not cols or cols >= len(frames):
        return np.concatenate(frames, axis=1)
    h, w = frames[0].shape[:2]
    rows = -(-len(frames) // cols)
    out = np.zeros((rows * h, cols * w, 4), np.uint8)
    for i, fr in enumerate(frames):
        r, c = divmod(i, cols)
        out[r * h:(r + 1) * h, c * w:(c + 1) * w] = fr
    return out


def dump(img, n_frames, legend_mode):
    a = np.array(img.convert("RGBA"))
    h, w = a.shape[:2]
    fw = w // n_frames
    inv = {v: k for k, v in VALUE_LEGEND.items() if v} if legend_mode == "value" else {}
    role_of = {v: k for k, v in MAIN_ROLES.items()}
    lines, auto = [], iter(AUTO_CHARS)
    lines.append("legend value" if legend_mode == "value" else "legend . transparent")
    extra = {}
    for y in range(h):
        for x in range(w):
            if a[y, x, 3] < 128:
                continue
            hx = "%02x%02x%02x" % tuple(a[y, x, :3])
            if hx not in inv and hx not in extra:
                ch = next(auto)
                extra[hx] = ch
                lines.append(f"legend {ch} {role_of.get(hx, hx)}")
    inv.update(extra)
    for f in range(n_frames):
        lines.append("frame")
        for y in range(h):
            lines.append("".join("." if a[y, x, 3] < 128 else inv["%02x%02x%02x" % tuple(a[y, x, :3])]
                                 for x in range(f * fw, (f + 1) * fw)))
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    r.add_argument("src")
    r.add_argument("--out", required=True)
    r.add_argument("--preview", help="also write an upscaled copy (for review)")
    r.add_argument("--scale", type=int, default=8)
    r.add_argument("--variant", action="append", default=[], help="legend overrides, e.g. '#=ink,m=lamp_400'")
    r.add_argument("--cols", type=int, default=0, help="atlas grid with N columns instead of one row")
    r.add_argument("--outline", nargs="?", const="ink", help="add a 1 px outline (role or hex, default ink)")
    d = sub.add_parser("dump")
    d.add_argument("png")
    d.add_argument("--frames", type=int, default=1)
    d.add_argument("--legend", choices=["value", "auto"], default="auto")
    a = p.parse_args()
    if a.cmd == "render":
        frames = []
        for spec in a.variant or [""]:
            frames += parse(a.src, override=parse_variant(spec) if spec else None)
        if a.outline:
            col = color_value(a.outline)
            frames = [outline(f, col) for f in frames]
        sheet = Image.fromarray(render(frames, a.cols), "RGBA")
        sheet.save(a.out)
        if a.preview:
            sheet.resize((sheet.width * a.scale, sheet.height * a.scale), Image.NEAREST).save(a.preview)
        print(f"{a.out} {sheet.width}x{sheet.height} ({len(frames)} frames)")
    else:
        sys.stdout.write(dump(Image.open(a.png), a.frames, a.legend))


if __name__ == "__main__":
    main()
