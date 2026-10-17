#!/usr/bin/env python3
"""Writes coop.txt (the hen house, 32x35) and run_back.txt / run_front.txt (the low run fence, 68x74 / 68x12).

Hen house: front view like the cottage, red shingle roof seen from above, plank walls, an arched door with
straw and a cleated ramp, a nest box on the left wall (Granny reaches it from the left), short legs.
Run fence: the garden fence style (bark_500 planks, bark_700 lines, gold_300 post tops) made low: posts every
16 px, two rails. run_back = back rail + both sides (drawn under everything), run_front = the front rail
(y-sorted, so hens walk behind it). Geometry: garden_props.json (run cells cols 19-22, rows 4-7).
  python3 tools/style/src/garden2/coop_gen.py   (build.sh renders them)
"""
from parts import blank, part, place, ring, write


def coop():
    W, H = 32, 34
    g = blank(W, H)
    # roof: trapezoid of red shingles, ridge highlight, darker every third row, eave shadow
    for y in range(0, 13):
        x0, x1 = 6 - y // 2, 25 + y // 2
        for x in range(x0, x1 + 1):
            if y == 0:
                ch = "p"
            elif y == 12:
                ch = "W"
            elif y % 3 == 0:
                ch = "R"
            else:
                ch = "p" if (x + (y // 3) * 2) % 5 == 0 and x < 16 else "r"
            g[y][x] = ch
    for x, y, c in [(10, 4, "A"), (11, 4, "A"), (11, 5, "g"), (20, 7, "y"), (21, 7, "A"), (24, 10, "A")]:
        g[y][x] = c
    # front wall: vertical planks under the eave
    for y in range(13, 28):
        for x in range(3, 29):
            if y == 13:
                ch = "B"
            elif y == 27:
                ch = "b"
            elif x % 4 == 2:
                ch = "b"
            else:
                ch = "y" if x == 3 else "o"
            g[y][x] = ch
    # arched door with straw, cream trim
    door = part("""
.CCCCCC.
CBBBBBBC
CBBBBBBC
CBBBBBBC
CBBBBBBC
CByByBBC
CyyGyyyC
CyGyyGyC
""")
    place(g, door, 12, 19)
    # small round vent under the gable
    place(g, part(".BB.\nBBBB\n.BB."), 14, 14)
    # legs
    for x in (4, 5, 26, 27):
        for y in range(28, 34):
            g[y][x] = "b" if x in (4, 26) else "B"
    # ramp from the door down to the ground, cleats every other row
    for y in range(28, 34):
        for x in range(13, 19):
            g[y][x] = "b" if y % 2 == 1 else "o"
    for y in range(28, 34):
        g[y][13] = "y"
    ring(g)
    # nest box on the left wall: its own outline so it reads in front of the wall
    nest = part("""
bbbbb
GyyyG
ooboo
obboo
ooboo
bbbbb
""")
    place(g, nest, 0, 17, outline=True)
    # one blank row on top so the ridge gets its ink line too (32x35)
    g.insert(0, ["."] * W)
    ring(g)
    return g


POST = part("""
y
o
b
o
b
o
b
""")


def low_rail(g, x0, x1, y):
    """Two rails (bark_500 over bark_700, ink lines) from x0 to x1, top at row y."""
    for x in range(x0, x1 + 1):
        g[y][x] = "k"
        g[y + 1][x] = "o"
        g[y + 2][x] = "k"
        g[y + 4][x] = "k"
        g[y + 5][x] = "b"
        g[y + 6][x] = "k"


def post(g, x, y):
    """A 3 px post (gold top, bark sides) with its ink ring, top-left at (x, y), 9 rows tall."""
    rows = part("""
.y.
yoB
obB
obB
obB
obB
obB
obB
obB
""")
    place(g, rows, x, y, outline=True)


def side(g, x, y0, y1):
    """A side run seen from above: a 2 px rail from y0 to y1 with posts every 16 px (fence_v style)."""
    for y in range(y0, y1 + 1):
        g[y][x] = "k"
        g[y][x + 1] = "o"
        g[y][x + 2] = "b"
        g[y][x + 3] = "k"


def run_back():
    W, H = 68, 74
    g = blank(W, H)
    # back rail along the run's top edge: posts stand on sprite row 11 (garden y 65)
    low_rail(g, 2, 65, 3)
    for x in (16, 32, 48):
        post(g, x, 1)
    # sides from the back corners down to the front corners (front rail: run_front)
    side(g, 1, 10, 70)
    side(g, 63, 10, 70)
    for y in (26, 42, 58):
        place(g, part(".y.\nyoB\nobB\n.B."), 1, y, outline=True)
        place(g, part(".y.\nyoB\nobB\n.B."), 63, y, outline=True)
    post(g, 0, 1)
    post(g, 64, 1)
    return g


def run_front():
    W, H = 68, 12
    g = blank(W, H)
    low_rail(g, 2, 65, 2)
    for x in (0, 16, 32, 48, 64):
        post(g, x, 0)
    return g


def main():
    write("coop", "Hen house (ART-GARDEN2), 32x35, front view, light from the top-left. Written by coop_gen.py.",
          [coop()])
    write("run_back", "Hen run fence, back rail and sides (ART-GARDEN2), 68x74, z back. Written by coop_gen.py.",
          [run_back()])
    write("run_front", "Hen run fence, front rail (ART-GARDEN2), 68x12, y-sorted. Written by coop_gen.py.",
          [run_front()])


if __name__ == "__main__":
    main()
