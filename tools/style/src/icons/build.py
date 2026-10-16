#!/usr/bin/env python3
"""Build icon PNGs, atlas icons.png and icons.json from icons.src. Run from the repo root:
python3 tools/style/src/icons/build.py"""
import json, subprocess, sys, pathlib

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


for i, b in bodies.items():
    render(b, OUT / f"{i}.png")
render("".join(bodies.values()), OUT / "icons.png", ("--cols", str(COLS)))
json.dump({"cell": [16, 16], "cols": COLS,
           "icons": {i: [n % COLS, n // COLS] for n, i in enumerate(bodies)}},
          open(OUT / "icons.json", "w"), indent=1)
print(len(bodies), "icons")
