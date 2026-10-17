#!/usr/bin/env python3
"""Writes clothesline.txt (64x32 x3), scarecrow.txt (20x36 x2) and bench.txt (32x20) from hand-drawn parts.

Clothesline: two T-posts, a sagging rope (no outline, one dark pixel thick) and Granny's quilt, apron and tea
towel pinned to it. The wind blows from the left: each frame shears the laundry rows to the right by up to
0, 1 and 2 px (loop 0-1-2-1). Scarecrow: straw hat, burlap head with a stitched face, a patched olive coat on
a crossbar; the sway frame moves everything above the coat's hem 1 px right. Bench: a painted garden bench
with a teacup on its saucer and a folded plaid blanket (the cat naps on it).
  python3 tools/style/src/garden2/props_gen.py   (build.sh renders them)
"""
import math

from parts import blank, part, place, ring, write

# --- clothesline ---------------------------------------------------------------------------------------------
CL_W, CL_H = 64, 32
POST = part("""
oooooo
bbbbbb
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
..ob..
""")
QUILT = part("""
cccccccccccccccccc
crrryyyCCCVVVAAAc.
crrryyyCCCVVVAAAc.
cpppAAArrryyyCCCc.
cpppAAArrryyyCCCc.
cpppAAArrryyyCCCc.
cCCCVVVpppAAArrrc.
cCCCVVVpppAAArrrc.
cCCCVVVpppAAArrrc.
cyyyrrrCCCVVVpppc.
cyyyrrrCCCVVVpppc.
ccccccccccccccccc.
""")
APRON = part("""
.C.CCCCCC.C.
.C.CCCCCC.C.
C..CCCCCC..C
..CCCCCCCC..
..CCCrrCCC..
..CCCrrCCc..
.CCCCCCCCcc.
.CCCCCCCCcc.
.rrrrrrrrrr.
""")
TOWEL = part("""
CCCCCCCC
CCCCCCCC
rrrrrrrr
CCCCCCCc
CCCCCCCc
rrrrrrrr
CCCCCCCc
cccccccc
""")
PIN = "o"
LINE_Y0, SAG = 6, 3            # rope height at the posts, sag in the middle
LINE_X0, LINE_X1 = 5, 58
ITEMS = [(QUILT, 8), (APRON, 30), (TOWEL, 46)]   # part, left x


def line_y(x):
    t = (x - LINE_X0) / (LINE_X1 - LINE_X0)
    return LINE_Y0 + round(SAG * math.sin(math.pi * max(0.0, min(1.0, t))))


def clothesline(amp):
    g = blank(CL_W, CL_H)
    place(g, POST, 1, 4, outline=True)
    place(g, POST, 57, 4, outline=True)
    for x in range(LINE_X0, LINE_X1 + 1):
        g[line_y(x)][x] = "B"
    for rows, x0 in ITEMS:
        h, w = len(rows), len(rows[0])
        # shear by the wind (row j moves right by amp * j / h), then hang each column under the rope
        sheared = [["."] * (w + 3) for _ in range(h)]
        for j, r in enumerate(rows):
            dx = round(amp * j / (h - 1)) if h > 1 else 0
            for i, ch in enumerate(r):
                if ch != ".":
                    sheared[j][i + dx] = ch
        filled = set()
        cells = {}
        for j in range(h):
            for i in range(w + 3):
                ch = sheared[j][i]
                if ch == ".":
                    continue
                x = x0 + i
                y = line_y(min(max(x, LINE_X0), LINE_X1)) + 1 + j
                if 0 <= x < CL_W and 0 <= y < CL_H:
                    cells[(x, y)] = ch
                    filled.add((x, y))
        for (x, y) in filled:  # own ink ring, but never over the rope or the posts
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (x + dx, y + dy)
                if q not in filled and 0 <= q[0] < CL_W and 0 <= q[1] < CL_H and g[q[1]][q[0]] == ".":
                    g[q[1]][q[0]] = "k"
        for (x, y), ch in cells.items():
            g[y][x] = ch
        for px in (x0 + 1, x0 + w - 2):   # clothes pegs on the rope
            g[line_y(px)][px] = PIN
    return g


# --- scarecrow -----------------------------------------------------------------------------------------------
SCARECROW = part("""
....................
....................
........gyyg........
.......gyyyyg.......
.......yyyyyy.......
.......rrrrrr.......
...yyyyyyyyyyyyyg...
....gggggggggggg....
......GGGGGGGc......
......GCGGGGGc......
......GkGGGkGc......
......GGGGGGGc......
......GGkGkkGc......
.......GGGGGc.......
.......yy.yyy.......
.yVVVVVVVVVVVVVVVVy.
..yVVVVVVVVVVVVVVy..
..OOOOOVVVVVVOOOOO..
.....OVVVBVVVVO.....
.....OVAAVVVVVO.....
.....OVAAVBVVVO.....
.....OVVVVVVVVO.....
.....OVVVVVrrVO.....
.....OVVVVBrrVO.....
.....OVVVVVVVVO.....
.....OOVOVVOVOO.....
......O.O.O.O.......
......y.yby.y.......
.........bo.........
.........bo.........
.........bo.........
.........bo.........
.........bo.........
.........bo.........
.........bo.........
.........bo.........
""")
SWAY_ROWS = 25   # rows above the coat's hem lean 1 px right in the sway frame


def scarecrow(sway):
    g = blank(20, 36)
    rows = SCARECROW
    if sway:
        rows = ["." + r[:-1] if j < SWAY_ROWS else r for j, r in enumerate(rows)]
    place(g, rows, 0, 0)
    ring(g)
    return g


# --- bench ---------------------------------------------------------------------------------------------------
BENCH = part("""
llllllllllllllllllllllllllllll
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVO
..............................
lVVVVVVVVVVVVVVVVVVVVVVVVVVVVO
VVVVVVVVVVVVVVVVVVVVVVVVVVVVOO
..............................
..............................
llllllllllllllllllllllllllllll
lVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVO
OOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
.lO......................lO...
.VO......................VO...
.VO......................VO...
.VO......................VO...
.VO......................VO...
""")
CUP = part("""
CCCc.
CrrCc
.CC..
ccccc
""")
BLANKET = part("""
.CrCCrCCr.
CrCCrCCrCc
rRrrRrrRrr
CrCCrCCrCc
cRccRccRcc
...CrCc...
....Rc....
""")


def bench():
    g = blank(32, 20)
    place(g, BENCH, 1, 2, outline=True)
    place(g, CUP, 5, 7, outline=True)
    place(g, BLANKET, 17, 7, outline=True)
    return g


def main():
    write("clothesline", "Clothesline (ART-GARDEN2), 64x32 x3 wind flutter frames (loop 0-1-2-1), posts on row 31.\n"
          "Written by props_gen.py (outlined parts, the rope has no outline).",
          [clothesline(a) for a in (0, 1, 2)])
    write("scarecrow", "Scarecrow (ART-GARDEN2), 20x36 x2 sway frames, pole on row 35. Written by props_gen.py.",
          [scarecrow(False), scarecrow(True)])
    write("bench", "Garden bench with a teacup and a folded blanket (ART-GARDEN2), 32x20, legs on row 18.\n"
          "Written by props_gen.py (outlined parts).", [bench()])


if __name__ == "__main__":
    main()
