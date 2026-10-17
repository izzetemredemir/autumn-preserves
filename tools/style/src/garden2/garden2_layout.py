#!/usr/bin/env python3
"""Source of game/assets/sprites/garden/garden_props.json (ART-GARDEN2), its debug overlay and the mock.

Garden coordinates: 16 px cells on the 30x17 map, pixels with y down (garden_layout.gd). A prop's "cell" is the
bottom-left cell its sprite stands on; "offset" is the sprite's top-left relative to that cell's top-left.
Point lists (truck_bed, chimney, perches, cat_spot_px) are garden pixels; perches and cat_spot_px are FEET
(bottom-centre of the critter's frame).
  python3 tools/style/src/garden2/garden2_layout.py   -> JSON + tools/style/review/garden2_layout.png
                                                        + tools/style/review/garden2_mock.png
Checks (exit 1): no prop blocks a path, road, bed, tree, sign, door, mailbox, compost, gate, pumpkin, spawn or
cat spot, and every interact cell is reachable from the door.
"""
import json
import os
import re
import sys
from collections import deque

from PIL import Image, ImageDraw

SPR = "game/assets/sprites/garden"
OUT = f"{SPR}/garden_props.json"
SHOT = "tools/style/review/gallery/garden.png"
DEBUG = "tools/style/review/garden2_layout.png"
MOCK = "tools/style/review/garden2_mock.png"
T = 16
W, H = 30, 17

# --- garden_layout.gd, mirrored for the checks -------------------------------------------------------------
HOUSE = (10, 0, 8, 6)
DOOR = [(13, 5), (14, 5)]
MAILBOX = (11, 6)
COMPOST = (12, 11)
TREES = [(3, 7), (3, 13), (24, 15)]
BEDS = [(7, 8), (10, 8), (7, 11), (10, 11), (7, 14), (10, 14)]
PATH_COLS = [13, 14]
ROAD_ROWS = [9, 10]
GATE = [(13, 16), (14, 16)]
GATE_SIGN = (19, 15)
TOWN_SIGN = (27, 11)
ROAD_EXIT = [(29, 9), (29, 10)]
SPAWNS = [(13, 6), (13, 15), (28, 9)]
PUMPKINS = [(8, 4), (27, 3), (16, 12), (27, 14)]
CAT_SPOTS_OLD = [(15, 6), (12, 11), (9, 8), (12, 15)]  # CatRules.SPOTS
# The house sprite: feet (224, 96), top-left (153, -4); chimney mouth at sprite (112, 3).
CHIMNEY = (153 + 112, -4 + 3)


def rect_cells(c, r, w, h):
    return [(x, y) for y in range(r, r + h) for x in range(c, c + w)]


# --- the props -----------------------------------------------------------------------------------------------
HEN_RUN = (19, 4, 4, 4)          # cols 19-22, rows 4-7: fenced, hens and the rooster walk its free cells
TRUCK_CELL = (24, 8)             # cols 24-27, rows 6-8, facing left, the bed over cols 26-27
PROPS = [
    {"id": "gravel", "sheet": "garden_gravel.png", "frame_w": 76, "frame_h": 22, "frames": 1,
     "cell": TRUCK_CELL, "offset": (-6, -6), "blocked": [], "interact": [], "z": "back"},
    {"id": "truck", "sheet": "garden_truck.png", "frame_w": 64, "frame_h": 48, "frames": 1,
     "cell": TRUCK_CELL, "offset": (0, -32), "blocked": rect_cells(24, 7, 4, 2),
     "interact": [(26, 9), (27, 9), (23, 7)], "z": "y"},
    {"id": "run_back", "sheet": "garden_run_back.png", "frame_w": 68, "frame_h": 74, "frames": 1,
     "cell": (19, 7), "offset": (-2, -58), "blocked": rect_cells(*HEN_RUN), "interact": [], "z": "back"},
    {"id": "coop", "sheet": "garden_coop.png", "frame_w": 32, "frame_h": 35, "frames": 1,
     "cell": (19, 5), "offset": (0, -19), "blocked": rect_cells(19, 4, 2, 2), "interact": [(18, 5)], "z": "y"},
    {"id": "run_front", "sheet": "garden_run_front.png", "frame_w": 68, "frame_h": 12, "frames": 1,
     "cell": (19, 7), "offset": (-2, 6), "blocked": [], "interact": [(20, 8), (21, 8)], "z": "y"},
    {"id": "hive_1", "sheet": "garden_hive.png", "frame_w": 16, "frame_h": 20, "frames": 2,
     "cell": (6, 4), "offset": (0, -4), "blocked": [(6, 4)], "interact": [(6, 5)], "z": "y"},
    {"id": "hive_2", "sheet": "garden_hive.png", "frame_w": 16, "frame_h": 20, "frames": 2,
     "cell": (7, 3), "offset": (0, -4), "blocked": [(7, 3)], "interact": [(7, 4)], "z": "y"},
    {"id": "clothesline", "sheet": "garden_clothesline.png", "frame_w": 64, "frame_h": 32, "frames": 3,
     "cell": (23, 4), "offset": (0, -16), "blocked": rect_cells(23, 4, 4, 1), "interact": [(24, 5), (25, 5)],
     "z": "y"},
    {"id": "scarecrow", "sheet": "garden_scarecrow.png", "frame_w": 20, "frame_h": 36, "frames": 2,
     "cell": (5, 9), "offset": (-2, -20), "blocked": [(5, 9)], "interact": [(5, 10)], "z": "y"},
    {"id": "bench", "sheet": "garden_bench.png", "frame_w": 32, "frame_h": 20, "frames": 1,
     "cell": (16, 6), "offset": (0, -4), "blocked": [(16, 6), (17, 6)], "interact": [(16, 7), (17, 7)], "z": "y"},
]
# Animated critters and effects that are not props: frame size and what each frame is.
SHEETS = {
    "truck_bed": {"sheet": "garden_truck_bed.png", "frame_w": 18, "frame_h": 12,
                  "frames": ["hay_pumpkins", "grape_crates", "apple_baskets", "pumpkins_blanket"]},
    "hen": {"sheet": "garden_hen.png", "frame_w": 12, "frame_h": 12, "feet": [6, 11], "faces": "right",
            "frames": ["idle", "walk_1", "walk_2", "peck_1", "peck_2", "flap_1", "flap_2"],
            "variants": ["rust", "cream"], "note": "frames 0-6 rust, 7-13 cream (same order)"},
    "rooster": {"sheet": "garden_rooster.png", "frame_w": 12, "frame_h": 14, "feet": [6, 13], "faces": "right",
                "frames": ["idle", "crow_1", "crow_2", "walk_1", "walk_2"]},
    "bee": {"sheet": "garden_bee.png", "frame_w": 2, "frame_h": 2, "frames": ["wings_up", "wings_down"]},
    "crow": {"sheet": "garden_crow.png", "frame_w": 10, "frame_h": 8, "feet": [5, 7], "faces": "right",
             "frames": ["sit", "caw", "flap_1", "flap_2"]},
    "smoke": {"sheet": "garden_smoke.png", "frame_w": 6, "frame_h": 6, "frames": ["small", "puff", "thin"]},
    "leafburst": {"sheet": "garden_leafburst.png", "frame_w": 4, "frame_h": 4,
                  "frames": ["red", "gold", "amber", "deep_red"]},
}
FRAME_NOTES = {
    "hive_1": "frames: plain, bees at the entrance", "hive_2": "frames: plain, bees at the entrance",
    "clothesline": "frames: three wind flutter poses (loop 0-1-2-1)", "scarecrow": "frames: two sway poses",
}
TRUCK_ORIGIN = (TRUCK_CELL[0] * T, (TRUCK_CELL[1] + 1) * T - 48)   # garden_truck.png top-left
TRUCK_BED = (TRUCK_ORIGIN[0] + 44, TRUCK_ORIGIN[1] + 10)   # top-left of a garden_truck_bed.png frame
SCARECROW_ORIGIN = (5 * T - 2, 10 * T - 36)
COOP_ORIGIN = (19 * T, 6 * T - 35)
PERCHES = {  # crow feet: both arm tips and the hat; the truck roof; the hen house ridge
    "scarecrow": [(SCARECROW_ORIGIN[0] + 3, SCARECROW_ORIGIN[1] + 14),
                  (SCARECROW_ORIGIN[0] + 17, SCARECROW_ORIGIN[1] + 14),
                  (SCARECROW_ORIGIN[0] + 10, SCARECROW_ORIGIN[1] + 1)],
    "truck": [(TRUCK_ORIGIN[0] + 35, TRUCK_ORIGIN[1] + 11)],
    "coop": [(COOP_ORIGIN[0] + 16, COOP_ORIGIN[1] + 1)],
}
CAT_SPOTS = [  # cell (not walkable while the cat is there), feet pixel (the cat node's position)
    {"id": "truck_hood", "cell": (24, 7), "px": (TRUCK_ORIGIN[0] + 15, TRUCK_ORIGIN[1] + 22)},
    {"id": "bench", "cell": (17, 6), "px": (16 * T + 22, 6 * T + 8)},
]


def fixed_blocked():
    """Cells the scene already uses (or that must stay free): props may not block them."""
    s = set(DOOR) | {MAILBOX, COMPOST, GATE_SIGN, TOWN_SIGN} | set(TREES) | set(GATE) | set(ROAD_EXIT)
    s |= set(SPAWNS) | set(PUMPKINS) | set(CAT_SPOTS_OLD)
    for b in BEDS:
        s |= {b, (b[0] + 1, b[1])}
    for y in range(H):
        for x in range(W):
            if x in PATH_COLS and y >= 6 or y in ROAD_ROWS and x > PATH_COLS[1]:
                s.add((x, y))
    return s


def is_open(c):
    x, y = c
    hx, hy, hw, hh = HOUSE
    if not (0 <= x < W and 0 <= y < H) or y < 2 or (hx <= x < hx + hw and hy <= y < hy + hh) or c in PUMPKINS:
        return False
    if c in GATE or c in ROAD_EXIT:
        return True
    return 0 < x < W - 1 and y < H - 1


def check():
    errs = []
    taken = fixed_blocked()
    spot_cells = set(DOOR) | {MAILBOX, COMPOST, GATE_SIGN, TOWN_SIGN} | set(TREES) | set(GATE)
    for b in BEDS:
        spot_cells |= {b, (b[0] + 1, b[1])}
    blocked = set()
    for p in PROPS:
        for c in p["blocked"]:
            if c in taken:
                errs.append(f"{p['id']} blocks {c}")
            if not is_open(c):
                errs.append(f"{p['id']} blocks a closed cell {c}")
            blocked.add(c)
    for cs in CAT_SPOTS:
        if cs["cell"] not in blocked:
            errs.append(f"cat spot {cs['id']} {cs['cell']} is not inside a prop")
    walk = lambda c: is_open(c) and c not in blocked and c not in spot_cells
    seen = {SPAWNS[0]}
    q = deque([SPAWNS[0]])
    while q:
        x, y = q.popleft()
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + d[0], y + d[1])
            if n not in seen and walk(n):
                seen.add(n)
                q.append(n)
    for p in PROPS:
        for c in p["interact"]:
            if c not in seen:
                errs.append(f"{p['id']} interact {c} unreachable")
    for c in [(s[0], s[1]) for s in SPAWNS] + [(b[0], b[1] + 1) for b in BEDS[:4]]:
        if c not in seen:
            errs.append(f"{c} unreachable")
    sheets = [(p["sheet"], p["frame_w"], p["frame_h"], p["frames"]) for p in PROPS]
    for s in SHEETS.values():
        n = len(s["frames"]) * len(s.get("variants", [0]))
        sheets.append((s["sheet"], s["frame_w"], s["frame_h"], n))
    for sheet, fw, fh, n in sheets:
        path = f"{SPR}/{sheet}"
        if os.path.exists(path) and Image.open(path).size != (fw * n, fh):
            errs.append(f"{sheet} is {Image.open(path).size}, expected {(fw * n, fh)}")
    return errs, blocked


def to_json():
    props = []
    for p in PROPS:
        d = {k: (list(v) if isinstance(v, tuple) else v) for k, v in p.items()}
        d["blocked"] = [list(c) for c in p["blocked"]]
        d["interact"] = [list(c) for c in p["interact"]]
        if p["id"] in FRAME_NOTES:
            d["note"] = FRAME_NOTES[p["id"]]
        props.append(d)
    return {
        "notes": "ART-GARDEN2. 16 px cells, garden pixels (y down). cell = bottom-left cell the sprite stands on, "
                 "offset = sprite top-left from that cell's top-left. z back = drawn under everything (ground); "
                 "z y = y-sorted by the bottom edge of its cell row. perches and cat_spot_px are feet points "
                 "(bottom-centre of the critter frame). hen_run is fenced and all blocked for Granny; the hens "
                 "walk its cells except the coop's. truck_bed is the top-left of a garden_truck_bed.png frame. "
                 "The cat spots on the truck hood and the bench sit above their prop's sort line: draw the cat "
                 "over the prop there. The chimney point is under the HUD bar at the default view.",
        "props": props,
        "hen_run": list(HEN_RUN),
        "truck_bed": list(TRUCK_BED),
        "chimney": list(CHIMNEY),
        "perches": {k: [list(p) for p in v] for k, v in PERCHES.items()},
        "cat_spots": [list(c["cell"]) for c in CAT_SPOTS],
        "cat_spot_ids": [c["id"] for c in CAT_SPOTS],
        "cat_spot_px": [list(c["px"]) for c in CAT_SPOTS],
        "sheets": SHEETS,
    }


def compact(text):
    """Indented JSON with short lists (numbers, strings, lists of number pairs) kept on one line."""
    flat = r'(?:-?\d+|"[^"\n]*")'
    text = re.sub(r"\[\s+(" + flat + r"(?:,\s+" + flat + r")*)\s+\]",
                  lambda m: "[" + ", ".join(x.strip() for x in re.split(r",\s+", m.group(1))) + "]", text)
    pair = r"\[[^\[\]\n]*\]"
    return re.sub(r"\[\s+(" + pair + r"(?:,\s+" + pair + r")*)\s+\]",
                  lambda m: "[" + ", ".join(x.strip() for x in re.split(r",\s+(?=\[)", m.group(1))) + "]", text)


def sprite(sheet, fw, fh, frame=0):
    path = f"{SPR}/{sheet}"
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGBA")
    return im.crop((frame * fw, 0, frame * fw + fw, fh))


def compose(base, frame_pick=None, placeholders=True):
    canvas = base.copy()
    order = sorted(PROPS, key=lambda p: (p["z"] != "back", (p["cell"][1] + 1) * T))
    for p in order:
        x = p["cell"][0] * T + p["offset"][0]
        y = p["cell"][1] * T + p["offset"][1]
        f = (frame_pick or {}).get(p["id"], 0)
        im = sprite(p["sheet"], p["frame_w"], p["frame_h"], f)
        if im is None:
            if placeholders:
                d = ImageDraw.Draw(canvas)
                d.rectangle([x, y, x + p["frame_w"] - 1, y + p["frame_h"] - 1], outline=(242, 217, 197, 255))
                d.text((x + 2, y + 2), p["id"][:6], fill=(242, 217, 197, 255))
            continue
        canvas.alpha_composite(im, (x, y))
        if p["id"] == "truck":
            load = sprite(SHEETS["truck_bed"]["sheet"], SHEETS["truck_bed"]["frame_w"], SHEETS["truck_bed"]["frame_h"])
            if load is not None:
                canvas.alpha_composite(load, TRUCK_BED)
    return canvas


def critters(canvas):
    """A few hens, the rooster, bees, a crow, smoke and leaves, so the mock shows them at scale."""
    def put(key, frame, feet):
        s = SHEETS[key]
        im = sprite(s["sheet"], s["frame_w"], s["frame_h"], frame)
        if im is None:
            return
        fx, fy = s.get("feet", [s["frame_w"] // 2, s["frame_h"] - 1])
        canvas.alpha_composite(im, (feet[0] - fx, feet[1] - fy))
    put("hen", 0, (21 * T + 8, 5 * T + 13))
    put("hen", 3, (22 * T + 6, 6 * T + 12))
    put("hen", 7 + 1, (20 * T + 8, 7 * T + 10))
    put("rooster", 1, (20 * T + 2, 6 * T + 12))
    put("crow", 0, PERCHES["scarecrow"][1])
    put("bee", 0, (6 * T + 6, 4 * T - 6))
    put("bee", 1, (7 * T + 12, 3 * T - 2))
    put("bee", 0, (6 * T + 2, 3 * T + 2))
    put("smoke", 1, (CHIMNEY[0], CHIMNEY[1] + 40))  # (the real chimney point is under the HUD bar)
    cat = Image.open("game/assets/sprites/cat/cat_sleep.png").convert("RGBA").crop((0, 0, 24, 24))
    x, y = CAT_SPOTS[0]["px"]
    canvas.alpha_composite(cat, (x - 12, y - 24))
    put("leafburst", 0, (21 * T, 3 * T))
    put("leafburst", 1, (26 * T + 6, 5 * T + 4))


def main():
    errs, blocked = check()
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(compact(json.dumps(to_json(), indent=1)) + "\n")
    shot = Image.open(SHOT).convert("RGBA")
    mock = compose(shot, {"hive_1": 1, "clothesline": 1})
    critters(mock)
    os.makedirs(os.path.dirname(MOCK), exist_ok=True)
    mock.resize((mock.width * 3, mock.height * 3), Image.NEAREST).save(MOCK)
    dbg = compose(shot).resize((shot.width * 3, shot.height * 3), Image.NEAREST)
    ov = Image.new("RGBA", dbg.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    k = 3 * T
    for c in fixed_blocked():
        d.rectangle([c[0] * k, c[1] * k, c[0] * k + k - 1, c[1] * k + k - 1], fill=(80, 140, 220, 50))
    for c in blocked:
        d.rectangle([c[0] * k + 2, c[1] * k + 2, c[0] * k + k - 3, c[1] * k + k - 3], outline=(220, 40, 30, 255), width=2)
    for p in PROPS:
        for c in p["interact"]:
            d.ellipse([c[0] * k + 16, c[1] * k + 16, c[0] * k + 31, c[1] * k + 31], fill=(60, 220, 60, 220))
    for cs in CAT_SPOTS:
        x, y = cs["px"]
        d.ellipse([x * 3 - 5, y * 3 - 5, x * 3 + 5, y * 3 + 5], outline=(255, 255, 0, 255), width=2)
    for pts in PERCHES.values():
        for x, y in pts:
            d.rectangle([x * 3 - 3, y * 3 - 3, x * 3 + 3, y * 3 + 3], outline=(0, 255, 255, 255), width=2)
    for x, y in [TRUCK_BED, CHIMNEY]:
        d.rectangle([x * 3 - 3, y * 3 - 3, x * 3 + 3, y * 3 + 3], fill=(255, 0, 255, 255))
    hx, hy, hw, hh = HEN_RUN
    d.rectangle([hx * k, hy * k, (hx + hw) * k - 1, (hy + hh) * k - 1], outline=(255, 160, 0, 255), width=2)
    for x in range(W + 1):
        d.line([(x * k, 0), (x * k, dbg.height)], fill=(255, 255, 255, 40))
    for y in range(H + 1):
        d.line([(0, y * k), (dbg.width, y * k)], fill=(255, 255, 255, 40))
    dbg.alpha_composite(ov)
    dbg.save(DEBUG)
    print(OUT, MOCK, DEBUG)
    if errs:
        print("\n".join("LAYOUT: " + e for e in errs))
        sys.exit(1)


if __name__ == "__main__":
    main()
