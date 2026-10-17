#!/usr/bin/env python3
"""Exact layout guide for stall_granny.png (ART-MARKET): Granny's market stall in front view, 180x112.

Geometry (stall-local pixels, the same numbers go into market_layout.json):
  sign board   x 32..147, y 0..21 (blank plate 112x18 at 34,2)
  awning       x 0..179,  y 14..37 (scalloped hem 32..37)
  posts        x 2..6 and 173..177
  jar counter  x 6..149,  y 52..99 = the 6x2 grid of 24 px cells (top row on a step shelf, bottom row on the counter)
  counter skirt y 100..111
  Granny's nook x 152..172 (she stands there, feet on y 111)
Writes tools/style/raw/stall_granny_guide.png (200x112 with 10 px margins) and a x5 copy for the upload.
  python3 tools/style/src/market/stall_guide.py
"""
from PIL import Image, ImageDraw

OUT = "tools/style/raw/stall_granny_guide.png"
OUT5 = "tools/style/raw/stall_granny_guide_x5.png"
BG = "#c8c8c8"
INK = "#111010"
BARK9, BARK7, BARK5 = "#50361e", "#83571e", "#c58845"
RED7, RED5 = "#a22512", "#c94d2e"
GOLD3, GOLD2 = "#e5bd7f", "#dbcc83"
CREAM4, CREAM1 = "#b9a697", "#f2d9c5"
PLUM = "#3d1f29"
M = 10  # margin on each side


def main():
    im = Image.new("RGB", (180 + 2 * M, 112), BG)
    d = ImageDraw.Draw(im)

    def r(x0, y0, x1, y1, c):
        d.rectangle((x0 + M, y0, x1 + M, y1), fill=c)

    # back wall in the awning's shadow (whole width between the posts)
    r(7, 36, 172, 111, BARK9)
    for x in range(12, 172, 9):
        r(x, 38, x, 111, PLUM)
    # step shelf behind the top jar row, shelf board, riser behind the bottom row
    r(6, 52, 149, 73, BARK9)
    r(6, 74, 149, 76, BARK5)
    r(6, 74, 149, 74, GOLD3)
    r(6, 77, 149, 97, BARK7)
    for y in (83, 90):
        r(6, y, 149, y, BARK9)
    # counter top and the red cloth skirt with cream trim
    r(4, 98, 151, 100, BARK5)
    r(4, 98, 151, 98, GOLD2)
    r(4, 101, 151, 109, RED5)
    for x in range(4, 151, 8):
        r(x, 101, x + 3, 109, RED7 if (x // 8) % 2 else RED5)
    r(4, 101, 151, 102, CREAM1)
    r(4, 110, 151, 111, BARK9)
    # end post of the counter (separates Granny's nook)
    r(148, 52, 151, 111, BARK7)
    # posts
    for x in (2, 173):
        r(x, 30, x + 4, 111, BARK7)
        r(x, 30, x, 111, BARK5)
    # awning stripes and scalloped hem
    for i, x in enumerate(range(0, 180, 10)):
        c = RED5 if i % 2 == 0 else CREAM1
        r(x, 14, x + 9, 31, c)
        d.ellipse((x + M, 27, x + 9 + M, 37), fill=c)
    r(0, 14, 179, 15, RED7)
    # sign board (blank)
    r(32, 0, 147, 21, INK)
    r(33, 1, 146, 20, BARK7)
    r(34, 2, 145, 19, GOLD3)
    im.save(OUT)
    im.resize((im.width * 5, im.height * 5), Image.NEAREST).save(OUT5)
    print(OUT, OUT5)


if __name__ == "__main__":
    main()
