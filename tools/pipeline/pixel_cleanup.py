#!/usr/bin/env python3
"""Turn a high-res AI "pixel art" image into clean, on-palette pixel art.

Spec: docs/art-bible.md §8.1. Steps per frame:
  background key (optional) -> crop to content -> fit to target size
  -> resample (block center or box average) -> alpha threshold
  -> palette snap in OKLab (no dithering) -> optional 1 px outline.
Prints a JSON report to stdout; exits 1 if the result breaks a rule
(off-palette pixels, partial alpha, too many colors).
"""
import argparse
import csv
import datetime
import hashlib
import json
import os
import sys

import numpy as np
from PIL import Image

GRAYS = np.array([[0, 0, 0], [64, 64, 64], [128, 128, 128], [192, 192, 192], [255, 255, 255]], dtype=np.float64)
LOG_COLUMNS = ["asset_id", "file_path", "family", "model", "prompt_sha1", "seed", "reference_image",
               "date_utc", "cleanup_args", "aseprite_edited", "approved_by", "notes"]


def parse_size(text):
    if text.lower() == "any":  # --check only: accept the file's own size
        return None
    w, h = text.lower().split("x")
    return int(w), int(h)


def load_palette(path):
    """One .hex file, or several joined with commas (e.g. main.hex,tone4.hex for era sheets)."""
    cols = []
    for one in path.split(","):
        for line in open(one, encoding="utf-8"):
            line = line.strip().lstrip("#")
            if line:
                cols.append([int(line[i:i + 2], 16) for i in (0, 2, 4)])
    if not cols:
        sys.exit(f"empty palette: {path}")
    return np.array(cols, dtype=np.float64)


def srgb_to_oklab(rgb):
    """rgb: (..., 3) in 0-255 -> (..., 3) OKLab."""
    c = rgb / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                   [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]])
    m2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                   [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]])
    lms = np.cbrt(lin @ m1.T)
    return lms @ m2.T


def key_background(arr, tolerance):
    """If the image is (almost) fully opaque, make the corner color transparent."""
    alpha = arr[..., 3]
    if (alpha < 250).mean() > 0.01:
        return arr  # already has real transparency
    h, w = alpha.shape
    corners = np.array([arr[0, 0, :3], arr[0, w - 1, :3], arr[h - 1, 0, :3], arr[h - 1, w - 1, :3]], dtype=np.float64)
    bg = np.median(corners, axis=0)
    dist = np.sqrt(((arr[..., :3].astype(np.float64) - bg) ** 2).sum(axis=-1))
    out = arr.copy()
    out[dist <= tolerance, 3] = 0
    return out


def crop_to_content(arr, threshold):
    ys, xs = np.nonzero(arr[..., 3] >= threshold)
    if len(xs) == 0:
        return arr
    return arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def resample(arr, tw, th, fit, method):
    """Map the source onto a tw x th grid. Returns float RGBA array (th, tw, 4)."""
    sh, sw = arr.shape[:2]
    out = np.zeros((th, tw, 4), dtype=np.float64)
    if fit == "none":
        cw, ch, ox, oy = tw, th, 0, 0
        sx0, sy0, sx1, sy1 = 0.0, 0.0, float(sw), float(sh)
    elif fit == "cover":
        scale = max(tw / sw, th / sh)
        vis_w, vis_h = tw / scale, th / scale
        sx0, sy0 = (sw - vis_w) / 2, (sh - vis_h) / 2
        sx1, sy1 = sx0 + vis_w, sy0 + vis_h
        cw, ch, ox, oy = tw, th, 0, 0
    else:  # contain
        scale = min(tw / sw, th / sh)
        cw, ch = max(1, round(sw * scale)), max(1, round(sh * scale))
        ox, oy = (tw - cw) // 2, (th - ch) // 2
        sx0, sy0, sx1, sy1 = 0.0, 0.0, float(sw), float(sh)
    bw, bh = (sx1 - sx0) / cw, (sy1 - sy0) / ch
    src = arr.astype(np.float64)
    for j in range(ch):
        y0, y1 = sy0 + j * bh, sy0 + (j + 1) * bh
        for i in range(cw):
            x0, x1 = sx0 + i * bw, sx0 + (i + 1) * bw
            if method == "center":
                px = src[min(sh - 1, int((y0 + y1) / 2)), min(sw - 1, int((x0 + x1) / 2))]
            else:  # box: alpha-weighted average of the block
                block = src[int(y0):max(int(y0) + 1, int(y1)), int(x0):max(int(x0) + 1, int(x1))].reshape(-1, 4)
                a = block[:, 3:4]
                px = np.zeros(4)
                px[3] = a.mean()
                if a.sum() > 0:
                    px[:3] = (block[:, :3] * a).sum(axis=0) / a.sum()
            out[oy + j, ox + i] = px
    return out


def snap(frame, palette, mode, threshold):
    """Binary alpha + nearest palette color (OKLab). Returns uint8 RGBA."""
    opaque = frame[..., 3] >= threshold
    rgb = frame[..., :3]
    if mode == "value-map":
        lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
        idx = np.abs(lum[..., None] - GRAYS[None, None, :, 0]).argmin(axis=-1)
        out_rgb = GRAYS[idx]
    else:
        lab = srgb_to_oklab(rgb)
        pal_lab = srgb_to_oklab(palette)
        d = ((lab[..., None, :] - pal_lab[None, None, :, :]) ** 2).sum(axis=-1)
        out_rgb = palette[d.argmin(axis=-1)]
    out = np.zeros(frame.shape, dtype=np.uint8)
    out[..., :3] = np.where(opaque[..., None], out_rgb, 0).astype(np.uint8)
    out[..., 3] = np.where(opaque, 255, 0)
    return out


def top_colors(snapped, palette, n):
    """Sub-palette: the n most used palette colors of a first snap (plus the darkest one used,
    so outlines survive). Re-snapping to it removes stray off-hue pixels and caps the color count."""
    counts = {}
    for img in snapped:
        for c in img[img[..., 3] == 255][:, :3].tolist():
            counts[tuple(c)] = counts.get(tuple(c), 0) + 1
    if len(counts) <= n:
        return palette
    used = sorted(counts, key=counts.get, reverse=True)
    darkest = min(used, key=lambda c: 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2])
    keep = used[:n]
    if darkest not in keep:
        keep[-1] = darkest
    return np.array(keep, dtype=np.float64)


def thin_outline(img):
    """Double outlines → single: drop darkest-color pixels that touch transparency but have no
    lighter opaque 4-neighbour (they sit outside another outline pixel). One pass."""
    op = img[..., 3] == 255
    if not op.any():
        return img
    lum = 0.2126 * img[..., 0] + 0.7152 * img[..., 1] + 0.0722 * img[..., 2]
    dark = op & (lum <= lum[op].min() + 0.5)
    pad = lambda m, v: np.pad(m, 1, constant_values=v)
    t, c = pad(~op, True), pad(op & ~dark, False)
    touches_t = t[:-2, 1:-1] | t[2:, 1:-1] | t[1:-1, :-2] | t[1:-1, 2:]
    touches_c = c[:-2, 1:-1] | c[2:, 1:-1] | c[1:-1, :-2] | c[1:-1, 2:]
    out = img.copy()
    out[dark & touches_t & ~touches_c] = 0
    return out


def edge_mask(img):
    """Opaque pixels with a transparent (or out-of-bounds) 4-neighbour."""
    op = img[..., 3] == 255
    pad = np.pad(op, 1, constant_values=False)
    neigh_all = pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
    return op & ~neigh_all


def despeckle(img):
    """Replace orphan pixels: if >=3 of the 4 neighbours share one other opaque color, take it."""
    out = img.copy()
    h, w = img.shape[:2]
    for y in range(h):
        for x in range(w):
            if img[y, x, 3] != 255:
                continue
            neigh = [tuple(img[ny, nx]) for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1))
                     if 0 <= ny < h and 0 <= nx < w and img[ny, nx, 3] == 255]
            for c in set(neigh):
                if c != tuple(img[y, x]) and neigh.count(c) >= 3:
                    out[y, x] = c
                    break
    return out


def apply_outline(img, mode, palette):
    edges = edge_mask(img)
    if mode == "value-map":
        dark = GRAYS[0]
    else:
        dark = palette[(0.2126 * palette[:, 0] + 0.7152 * palette[:, 1] + 0.0722 * palette[:, 2]).argmin()]
    img[edges, :3] = dark.astype(np.uint8)
    return img


def report(img, palette, mode, max_colors):
    op = img[..., 3] == 255
    partial = int(((img[..., 3] > 0) & (img[..., 3] < 255)).sum())
    colors = {tuple(c) for c in img[op][:, :3].tolist()}
    allowed = {tuple(c) for c in (GRAYS if mode == "value-map" else palette).astype(int).tolist()}
    off = int(sum(1 for c in img[op][:, :3].tolist() if tuple(c) not in allowed))
    return {"unique_colors": len(colors), "off_palette_pixels": off, "partial_alpha_pixels": partial,
            "exceeds_max_colors": bool(max_colors and len(colors) > max_colors)}


def append_log(args, out_path):
    new = not os.path.exists(args.log)
    prompt = args.prompt or ""
    if prompt and os.path.isfile(prompt):
        prompt = open(prompt, encoding="utf-8").read()
    row = {
        "asset_id": args.asset_id or os.path.splitext(os.path.basename(out_path))[0],
        "file_path": out_path, "family": args.family or "", "model": args.model or "",
        "prompt_sha1": hashlib.sha1(prompt.encode()).hexdigest() if prompt else "",
        "seed": args.seed or "", "reference_image": args.ref or "",
        "date_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "cleanup_args": " ".join(sys.argv[1:]), "aseprite_edited": "n", "approved_by": "", "notes": "",
    }
    with open(args.log, "a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=LOG_COLUMNS)
        if new:
            w.writeheader()
        w.writerow(row)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--in", dest="src", required=True)
    p.add_argument("--out", help="required unless --check")
    p.add_argument("--check", action="store_true",
                   help="lint --in as is (no transform): palette, partial alpha, colors, frame size; exit 1 on a broken rule")
    p.add_argument("--size", required=True, type=parse_size, help="target size of ONE frame, e.g. 32x32 ('any' with --check: skip the size rule)")
    p.add_argument("--frames", type=int, default=1, help="frames laid out horizontally in the source")
    p.add_argument("--palette", default="tools/palettes/autumn.hex")
    p.add_argument("--mode", choices=["env", "value-map", "fish-grayscale"], default="env",
                   help="env: snap to --palette; value-map (alias fish-grayscale): 5-level gray map for palette-swap shaders")
    p.add_argument("--resample", choices=["center", "box"], default="center")
    p.add_argument("--alpha-threshold", type=int, default=128)
    p.add_argument("--fit", choices=["contain", "cover", "none"], default="contain")
    p.add_argument("--outline", choices=["auto", "none"], default="none")
    p.add_argument("--despeckle", action="store_true", help="remove orphan pixels (majority of 4 neighbours)")
    p.add_argument("--bg", choices=["auto", "none"], default="auto",
                   help="auto: if the source has no transparency, key out the corner color")
    p.add_argument("--bg-tolerance", type=float, default=40.0)
    p.add_argument("--max-colors", type=int, default=0, help="warn+fail above this many colors (0 = off)")
    p.add_argument("--thin-outline", action="store_true", help="collapse 2 px outer outlines to 1 px (after --outline)")
    p.add_argument("--colors", type=int, default=0,
                   help="env: keep only the N most used palette colors and re-snap (art-bible: object ≤12, icon ≤5)")
    p.add_argument("--log")
    p.add_argument("--asset-id")
    p.add_argument("--family")
    p.add_argument("--model")
    p.add_argument("--prompt", help="prompt text or path to a file holding it (only its sha1 is logged)")
    p.add_argument("--seed")
    p.add_argument("--ref", help="reference image used for generation")
    args = p.parse_args()
    if args.mode == "fish-grayscale":
        args.mode = "value-map"

    if args.size is None and not args.check:
        p.error("--size any is only valid with --check")
    tw, th = args.size or (0, 0)
    palette = load_palette(args.palette)
    src = np.array(Image.open(args.src).convert("RGBA"))
    if args.check:
        rep = report(src, palette, args.mode, args.max_colors)
        want = (tw * args.frames, th) if args.size else tuple(src.shape[1::-1])
        rep.update({"in": args.src, "size": f"{src.shape[1]}x{src.shape[0]}", "size_ok": src.shape[1::-1] == want,
                    "pure_black_pixels": int(((src[..., :3] == 0).all(-1) & (src[..., 3] > 0)).sum()) if args.mode == "env" else 0})
        print(json.dumps(rep))
        ok = (rep["off_palette_pixels"] == 0 and rep["partial_alpha_pixels"] == 0 and not rep["exceeds_max_colors"]
              and rep["size_ok"] and rep["pure_black_pixels"] == 0)
        sys.exit(0 if ok else 1)
    if not args.out:
        p.error("--out is required unless --check")
    if args.bg == "auto":
        src = key_background(src, args.bg_tolerance)

    fw = src.shape[1] / args.frames
    raws = []
    for k in range(args.frames):
        part = src[:, int(round(k * fw)):int(round((k + 1) * fw))]
        if args.fit != "none":
            part = crop_to_content(part, args.alpha_threshold)
        raws.append(resample(part, tw, th, args.fit, args.resample))
    if args.colors and args.mode == "env":
        palette = top_colors([snap(r, palette, args.mode, args.alpha_threshold) for r in raws], palette, args.colors)
    frames = []
    for raw in raws:
        frame = snap(raw, palette, args.mode, args.alpha_threshold)
        if args.despeckle:
            frame = despeckle(frame)
        if args.outline == "auto" or args.mode == "value-map":
            frame = apply_outline(frame, args.mode, palette)
        if args.thin_outline:
            frame = thin_outline(frame)
        frames.append(frame)
    sheet = np.concatenate(frames, axis=1)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(args.out)
    rep = report(sheet, palette, args.mode, args.max_colors)
    rep.update({"out": args.out, "size": f"{sheet.shape[1]}x{sheet.shape[0]}", "frames": args.frames,
                "mode": args.mode, "palette": args.palette, "resample": args.resample, "fit": args.fit})
    if args.log:
        append_log(args, args.out)
    print(json.dumps(rep, indent=2))
    ok = rep["off_palette_pixels"] == 0 and rep["partial_alpha_pixels"] == 0 and not rep["exceeds_max_colors"]
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
