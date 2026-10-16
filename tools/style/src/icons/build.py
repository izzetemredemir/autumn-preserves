#!/usr/bin/env python3
"""Build icon PNGs, atlas icons.png and icons.json from icons.src. Run from the repo root:
python3 tools/style/src/icons/build.py"""
import json, subprocess, sys, pathlib
from PIL import Image

SRC = pathlib.Path(__file__).parent
OUT = pathlib.Path("game/assets/sprites/icons")
ASCII = "tools/pipeline/ascii_sprite.py"
COLS = 6
LEGEND = """legend . transparent
legend i ink
legend r leaf_red_500
legend R leaf_red_700
legend p leaf_peach_300
legend g gold_300
legend G gold_200
legend a amber_600
legend o gold_700
legend b bark_700
legend B bark_900
legend n bark_500
legend c cream_100
legend C cream_400
legend l olive_600
legend L olive_800
legend e olive_300
legend E olive_200
legend k olive_500
legend w plum_900
legend W wine_700
legend s stone_300
legend S stone_500
legend t stone_700
legend v water_800
legend V water_600
legend x sage_400
legend q olive_900
legend u water_900
legend z slate_900
"""

icons = {}
cur = None
for line in (SRC / "icons.src").read_text().splitlines():
    if line.startswith("#"):
        continue
    if line.startswith("== "):
        cur = line[3:].strip()
        icons[cur] = []
    elif cur is not None and line.strip():
        icons[cur].append(line.ljust(16, "."))

OUT.mkdir(parents=True, exist_ok=True)
bodies = {}
for i, rows in icons.items():
    assert all(len(r) == 16 for r in rows), (i, [len(r) for r in rows])
    rows = rows + ["." * 16] * (16 - len(rows))
    assert len(rows) == 16, i
    bodies[i] = "frame\n" + "\n".join(rows) + "\n"


def render(text, out, extra=()):
    tmp = SRC / ".build.tmp.txt"
    tmp.write_text(LEGEND + text)
    try:
        subprocess.check_call([sys.executable, ASCII, "render", str(tmp), "--out", str(out), "--outline", *extra])
    finally:
        tmp.unlink()


# --- post pass: selective outline + 1 px contact shadow (art-bible: rim on the lit edge takes the local darkest tone)
INK = (0x11, 0x10, 0x10)
RIM = {  # fill colour -> darkest tone of its ramp
    "c94d2e": "62272c", "e19064": "62272c", "a22512": "62272c", "62272c": "3d1f29", "3d1f29": "3d1f29",
    "e5bd7f": "50361e", "dbcc83": "50361e", "b66813": "50361e", "9b8039": "50361e",
    "50361e": "50361e", "83571e": "50361e", "c58845": "50361e",
    "f2d9c5": "81746a", "b9a697": "81746a",
    "314524": "314524", "53612e": "314524", "747c37": "314524", "b1a13d": "314524", "b7b768": "314524", "c5bf3f": "314524",
    "2e3f3f": "2e3f3f", "275e4c": "2e3f3f", "4e7664": "2e3f3f", "738c7a": "2e3f3f", "567c7d": "2e3f3f", "415c5d": "2e3f3f",
    "b4b3a0": "49423d", "81746a": "49423d", "49423d": "49423d",
}
SHADOW = (0x50, 0x36, 0x1e)


def hx(c):
    return "%02x%02x%02x" % c[:3]


def post(img):
    px = img.load()
    W, H = img.size
    src = img.copy().load()

    def fill(x, y):
        return 0 <= x < W and 0 <= y < H and src[x, y][3] and src[x, y][:3] != INK

    def empty(x, y):
        return not (0 <= x < W and 0 <= y < H) or src[x, y][3] == 0
    for y in range(H):
        for x in range(W):
            if src[x, y][:3] == INK and src[x, y][3]:
                for dx, dy in ((1, 0), (0, 1)):
                    if fill(x + dx, y + dy) and (empty(x - 1, y) or empty(x, y - 1)) and not (empty(x - 1, y) and empty(x, y - 1) is False and False):
                        r = RIM.get(hx(src[x + dx, y + dy]))
                        if r:
                            px[x, y] = tuple(int(r[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
                        break
    # contact shadow: row under the lowest outline pixel of each column, trimmed one px at both ends
    cols = [x for x in range(W) if any(src[x, y][3] for y in range(H))]
    low = {x: max(y for y in range(H) if src[x, y][3]) for x in cols}
    if low:
        base = max(low.values())
        span = [x for x in cols if low[x] >= base - 1]
        if span and base < H - 1:
            for x in span[1:-1]:
                if src[x, base + 1][3] == 0:
                    px[x, base + 1] = SHADOW + (255,)
    return img


def post_png(path):
    im = Image.open(path).convert("RGBA")
    post(im).save(path)


for i, b in bodies.items():
    render(b, OUT / f"{i}.png")
    post_png(OUT / f"{i}.png")
render("".join(bodies.values()), OUT / "icons.png", ("--cols", str(COLS)))
atlas = Image.open(OUT / "icons.png").convert("RGBA")
for n in range(len(bodies)):
    cx, cy = (n % COLS) * 16, (n // COLS) * 16
    atlas.paste(post(atlas.crop((cx, cy, cx + 16, cy + 16))), (cx, cy))
atlas.save(OUT / "icons.png")
json.dump({"cell": [16, 16], "cols": COLS,
           "icons": {i: [n % COLS, n // COLS] for n, i in enumerate(bodies)}},
          open(OUT / "icons.json", "w"), indent=1)
print(len(bodies), "icons")
