#!/usr/bin/env python3
"""Source of game/assets/sprites/market/market_layout.json (ART-MARKET) and its debug overlay.

All points are read off bg_market.png (480x270 base, y down) and are FEET positions. The walk graph only uses
open cobbles: the back lane in front of the bakery, wine stall and post office (y ~124), the two gaps beside
Granny's stall, the browse lane right in front of her counter (y 242, one node per jar column) and the
through lane along the bottom. Entries are graph nodes on the screen edges.
  python3 tools/style/src/market/market_layout.py      -> JSON + tools/style/review/market_layout.png
"""
import json
import math

from PIL import Image, ImageDraw

BG = "game/assets/sprites/market/bg_market.png"
STALL = "game/assets/sprites/market/stall_granny.png"
OUT = "game/assets/sprites/market/market_layout.json"
DEBUG = "tools/style/review/market_layout.png"
MOCK = "tools/style/review/market_mock.png"

STALL_POS = (153, 110)          # top-left of stall_granny.png (180x125, foot line row 121, shadow below)
CELLS = (6, 46, 144, 48)        # 6x2 jar cells, stall-local (stall_finish.py)
SIGN = (35, 3, 111, 15)         # blank sign plate, stall-local
GRANNY = (163, 120)             # Granny's feet in the nook, stall-local

NODES = {
    # back lane
    "back_w": (0, 125), "bakery_l": (40, 125), "bakery": (76, 126), "gap_l_top": (142, 127),
    "behind_l": (196, 124), "wine": (244, 123), "behind_r": (292, 124), "gap_r_top": (341, 127),
    "post": (412, 127),
    # gaps beside Granny's stall
    "gap_l": (142, 178), "gap_l_low": (142, 236), "gap_r": (341, 180), "gap_r_low": (341, 238),
    # browse lane in front of Granny's counter (one node per jar column, then her nook)
    "jar0": (171, 243), "jar1": (195, 243), "jar2": (219, 243), "jar3": (243, 243), "jar4": (267, 243),
    "jar5": (291, 243), "granny": (316, 243),
    # through lane and the front stalls
    "front_w": (0, 250), "grocer": (70, 229), "front_l": (100, 256), "front_cl": (190, 259),
    "front_cr": (290, 259), "front_r": (382, 256), "books": (410, 233), "front_e": (479, 250),
    "bottom_l": (110, 269), "bottom_r": (400, 269),
}
EDGES = [
    ("back_w", "bakery_l"), ("bakery_l", "bakery"), ("bakery", "gap_l_top"), ("gap_l_top", "behind_l"),
    ("behind_l", "wine"), ("wine", "behind_r"), ("behind_r", "gap_r_top"), ("gap_r_top", "post"),
    ("gap_l_top", "gap_l"), ("gap_l", "gap_l_low"), ("gap_r_top", "gap_r"), ("gap_r", "gap_r_low"),
    ("gap_l_low", "jar0"), ("jar0", "jar1"), ("jar1", "jar2"), ("jar2", "jar3"), ("jar3", "jar4"),
    ("jar4", "jar5"), ("jar5", "granny"), ("granny", "gap_r_low"),
    ("front_w", "grocer"), ("front_w", "front_l"), ("grocer", "front_l"), ("grocer", "gap_l_low"),
    ("front_l", "gap_l_low"), ("front_l", "front_cl"), ("front_cl", "front_cr"), ("front_cr", "front_r"),
    ("front_cl", "jar1"), ("front_cr", "jar5"), ("front_r", "gap_r_low"), ("front_r", "books"),
    ("gap_r_low", "books"), ("books", "front_e"), ("front_r", "front_e"),
    ("front_l", "bottom_l"), ("front_r", "bottom_r"),
]
ENTRIES = ["back_w", "front_w", "front_e", "bottom_l", "bottom_r"]
VENDORS = [  # stand = where the neighbour stands, front = the graph node where customers stop
    {"id": "baker", "name": "Rosie", "stand": (24, 124), "front": "bakery", "goods": "bread"},
    {"id": "vintner", "name": "Vito", "stand": (318, 122), "front": "wine", "goods": "grapes"},
    {"id": "grocer", "name": "Barnaby", "stand": (24, 229), "front": "grocer", "goods": "produce"},
    {"id": "librarian", "name": "Edith", "stand": (462, 228), "front": "books", "goods": "books"},
    {"id": "postman", "name": "Pip", "stand": (456, 124), "front": "post", "goods": "letters"},
]
PIGEON_ZONES = [(20, 238, 70, 22), (358, 240, 100, 20), (200, 262, 80, 6), (24, 119, 84, 7)]
# roof / awning / lantern perches (feet of a bird sitting there)
PERCHES = [(50, 26), (100, 26), (136, 29), (208, 30), (266, 30), (338, 32), (402, 17),
           (32, 131), (96, 131), (372, 131), (446, 131)]
STALL_PERCHES = [(60, 0), (120, 0)]  # on Granny's sign board, stall-local
# extra fluttering bunting (x0, y0, x1, y1, sag) for bunting.png pennants: two near swags across the top edge,
# in front of the painted garlands (those hang lantern to lantern and on the post office)
GARLANDS = [(0, 3, 240, 3, 14), (240, 3, 479, 3, 14)]
MUSICIAN = (372, 122)           # on the post office steps
DOG_SIT = (54, 236)             # by Barnaby's cart
LANTERNS = [(136, 40), (338, 40)]  # painted lantern glass centres (flicker overlay)
SHEETS = {
    "stall_granny": {"file": "stall_granny.png", "frame": [180, 125]},
    "pigeon": {"file": "pigeon.png", "frame": [16, 12], "feet": [8, 11],
               "anims": {"idle": [0], "peck": [1, 2], "walk": [3, 4], "flap": [5, 6, 7]}, "faces": "left"},
    "sparrow": {"file": "sparrow.png", "frame": [8, 8], "feet": [4, 7], "anims": {"sit": [0], "flap": [1, 2]},
                "faces": "left"},
    "dog": {"file": "dog.png", "frame": [24, 18], "feet": [12, 17],
            "anims": {"trot": [0, 1, 2, 3], "sit": [4], "sniff": [5, 6], "wag": [7, 8]}, "faces": "right"},
    "musician": {"file": "musician.png", "frame": [24, 46], "feet": [12, 45], "anims": {"play": [0, 1, 2, 3]}},
    "note": {"file": "note.png", "frame": [8, 8], "anims": {"eighth": [0], "beamed": [1]}},
    "leaf": {"file": "leaf.png", "frame": [4, 4], "anims": {"tints": [0, 1, 2, 3]}},
    "bunting": {"file": "bunting.png", "frame": [6, 6], "anims": {"red": [0, 1], "gold": [2, 3], "olive": [4, 5],
                                                                    "cream": [6, 7]}, "hang": [0, 0], "step": 6},
}


def garland_point(g, t):
    x0, y0, x1, y1, sag = g
    return round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t + sag * 4 * t * (1 - t))


def build():
    names = list(NODES)
    idx = {n: i for i, n in enumerate(names)}
    sx, sy = STALL_POS
    perches = [list(p) for p in PERCHES] + [[sx + x, sy + y] for x, y in STALL_PERCHES]
    perches += [list(garland_point(g, t)) for g in GARLANDS for t in (0.3, 0.7)]
    return {
        "size": [480, 270],
        "background": "bg_market.png",
        "granny_stall": {
            "x": sx, "y": sy, "sprite": "stall_granny.png", "size": [180, 125], "feet_y": sy + 121,
            "counter": [sx + CELLS[0], sy + CELLS[1], CELLS[2], CELLS[3]],
            "sign": [sx + SIGN[0], sy + SIGN[1], SIGN[2], SIGN[3]],
            "granny": [sx + GRANNY[0], sy + GRANNY[1]],
        },
        "vendors": [{"id": v["id"], "name": v["name"], "stand": list(v["stand"]),
                     "front": list(NODES[v["front"]]), "front_node": idx[v["front"]], "goods": v["goods"]}
                    for v in VENDORS],
        "walk": {"nodes": [list(NODES[n]) for n in names], "names": names,
                 "edges": [[idx[a], idx[b]] for a, b in EDGES],
                 "jar_nodes": [idx["jar%d" % i] for i in range(6)], "granny_node": idx["granny"]},
        "entries": [list(NODES[n]) for n in ENTRIES],
        "pigeon_zones": [list(z) for z in PIGEON_ZONES],
        "perches": perches,
        "musician": list(MUSICIAN),
        "dog_sit": list(DOG_SIT),
        "lanterns": [list(p) for p in LANTERNS],
        "garlands": [list(g) for g in GARLANDS],
        "sheets": SHEETS,
    }


def check(lay):
    """Graph sanity: connected, entries are nodes, every vendor front is a node."""
    nodes = [tuple(n) for n in lay["walk"]["nodes"]]
    adj = {i: set() for i in range(len(nodes))}
    for a, b in lay["walk"]["edges"]:
        adj[a].add(b)
        adj[b].add(a)
    seen, todo = {0}, [0]
    while todo:
        for j in adj[todo.pop()]:
            if j not in seen:
                seen.add(j)
                todo.append(j)
    assert len(seen) == len(nodes), "walk graph is not connected"
    for e in lay["entries"]:
        assert tuple(e) in nodes, f"entry {e} is not a node"
        assert e[0] in (0, 479) or e[1] in (0, 269), f"entry {e} is not on the screen edge"
    for v in lay["vendors"]:
        assert tuple(v["front"]) in nodes
    for x, y in nodes:
        assert 0 <= x < 480 and 0 <= y < 270


def debug(lay):
    bg = Image.open(BG).convert("RGBA")
    st = Image.open(STALL).convert("RGBA")
    gs = lay["granny_stall"]
    bg.alpha_composite(st, (gs["x"], gs["y"]))
    S = 3
    im = bg.resize((480 * S, 270 * S), Image.NEAREST)
    d = ImageDraw.Draw(im)
    nodes = lay["walk"]["nodes"]
    for x, y, w, h in lay["pigeon_zones"]:
        d.rectangle((x * S, y * S, (x + w) * S, (y + h) * S), outline=(120, 200, 255), width=2)
    for g in lay["garlands"]:
        pts = [tuple(c * S for c in garland_point(g, i / 20)) for i in range(21)]
        d.line(pts, fill=(255, 255, 255), width=1)
    x, y, w, h = gs["counter"]
    d.rectangle((x * S, y * S, (x + w) * S, (y + h) * S), outline=(0, 255, 0), width=2)
    for i in range(1, 6):
        d.line(((x + 24 * i) * S, y * S, (x + 24 * i) * S, (y + h) * S), fill=(0, 255, 0))
    d.line((x * S, (y + 24) * S, (x + w) * S, (y + 24) * S), fill=(0, 255, 0))
    x, y, w, h = gs["sign"]
    d.rectangle((x * S, y * S, (x + w) * S, (y + h) * S), outline=(255, 0, 255), width=2)
    for a, b in lay["walk"]["edges"]:
        d.line((nodes[a][0] * S, nodes[a][1] * S, nodes[b][0] * S, nodes[b][1] * S), fill=(255, 255, 0), width=2)
    for i, (x, y) in enumerate(nodes):
        d.ellipse((x * S - 4, y * S - 4, x * S + 4, y * S + 4), fill=(255, 255, 0), outline=(0, 0, 0))
        d.text((x * S + 5, y * S - 12), str(i), fill=(255, 255, 255))
    for x, y in lay["entries"]:
        d.rectangle((x * S - 7, y * S - 7, x * S + 7, y * S + 7), outline=(255, 80, 0), width=3)
    for v in lay["vendors"]:
        x, y = v["stand"]
        d.rectangle(((x - 11) * S, (y - 46) * S, (x + 11) * S, y * S), outline=(255, 60, 60), width=2)
        d.text(((x - 10) * S, (y - 44) * S), v["name"], fill=(255, 255, 255))
        fx, fy = v["front"]
        d.line((x * S, y * S, fx * S, fy * S), fill=(255, 60, 60), width=1)
    for x, y in lay["perches"]:
        d.polygon([(x * S, y * S), (x * S - 6, y * S - 10), (x * S + 6, y * S - 10)], fill=(80, 255, 255))
    x, y = lay["musician"]
    d.rectangle(((x - 12) * S, (y - 46) * S, (x + 12) * S, y * S), outline=(200, 120, 255), width=2)
    d.text(((x - 11) * S, (y - 44) * S), "fiddler", fill=(255, 255, 255))
    x, y = gs["granny"]
    d.rectangle(((x - 11) * S, (y - 46) * S, (x + 11) * S, y * S), outline=(255, 160, 220), width=2)
    x, y = lay["dog_sit"]
    d.rectangle(((x - 12) * S, (y - 18) * S, (x + 12) * S, y * S), outline=(200, 255, 120), width=2)
    for x, y in lay["lanterns"]:
        d.ellipse(((x - 4) * S, (y - 4) * S, (x + 4) * S, (y + 4) * S), outline=(255, 220, 0), width=2)
    im.save(DEBUG)
    print(DEBUG)


def mock(lay):
    """One still of the square with the stall and a few actors on their layout points (for the contact sheet)."""
    d = "game/assets/sprites/market/"
    im = Image.open(BG).convert("RGBA")

    def put(name, i, feet):
        sh = SHEETS[name]
        fw, fh = sh["frame"]
        px, py = sh.get("feet", [0, 0])
        sheet = Image.open(d + sh["file"]).convert("RGBA")
        im.alpha_composite(sheet.crop((i * fw, 0, (i + 1) * fw, fh)), (feet[0] - px, feet[1] - py))

    for g in lay["garlands"]:  # pennants every 6 px along the extra swags
        x0, x1 = g[0], g[2]
        for k, x in enumerate(range(x0, x1 - 5, 6)):
            t = (x - x0) / (x1 - x0)
            put("bunting", (k % 4) * 2 + (k // 4) % 2, garland_point(g, t))
    gs = lay["granny_stall"]
    im.alpha_composite(Image.open(STALL).convert("RGBA"), (gs["x"], gs["y"]))
    put("musician", 0, lay["musician"])
    put("note", 0, (378, 66))
    put("note", 1, (390, 54))
    put("dog", 4, lay["dog_sit"])
    for i, feet in ((0, (40, 252)), (2, (66, 256)), (3, (384, 252)), (1, (412, 256)), (6, (240, 266))):
        put("pigeon", i, feet)
    for p in lay["perches"][1:12:3]:
        put("sparrow", 0, p)
    for i, (x, y) in enumerate(((196, 70), (300, 96), (160, 190), (430, 160))):
        put("leaf", i, (x, y))
    im.save(MOCK)
    print(MOCK)


def main():
    lay = build()
    check(lay)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(lay, f, indent=1)
        f.write("\n")
    print(OUT, len(lay["walk"]["nodes"]), "nodes", len(lay["walk"]["edges"]), "edges")
    debug(lay)
    mock(lay)


if __name__ == "__main__":
    main()
