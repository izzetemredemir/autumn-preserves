#!/usr/bin/env python3
"""Hand finish for stall_granny.png (ART-MARKET).

The cleaned generation (tools/style/raw/market_stall_granny_clean.png, 180x112) has the right parts but its shelves
sit 16 px apart and faint jar ghosts on the back wall. This remaps its rows so the 6x2 jar grid fits exactly
(24 px per row: the top row stands on the step shelf, the bottom row on the counter) and repaints the back wall
as plain dark planks. Every colour comes from the cleaned image, so the result stays on palette.

Final geometry (stall-local, copied into market_layout.json by market_layout.py):
  size 180x125 (foot line row 121, rows 122..124 = hard ground shadow); blank sign plate x 35..145, y 3..17;
  counter cells x 6..149, y 46..93 (6x2, 24 px); Granny's nook x 154..173, her feet at (163, 120).
  python3 tools/style/src/market/stall_finish.py
"""
from PIL import Image

SRC = "tools/style/raw/market_stall_granny_clean.png"
OUT = "game/assets/sprites/market/stall_granny.png"
W, H = 180, 125
SHADOW = (0x83, 0x57, 0x1e)  # bark_700: hard ground shadow, one tone under the cobbles, to the lower right
PLUM, BARK9, WINE = (0x3d, 0x1f, 0x29), (0x50, 0x36, 0x1e), (0x62, 0x27, 0x2c)
# (source rows a..b inclusive) -> (target rows c..d inclusive), nearest-row resampling
ROWS = [((0, 35), (0, 35)),      # sign and awning
        ((36, 62), (36, 69)),    # back wall behind the top jar row
        ((63, 67), (70, 74)),    # step shelf board
        ((68, 78), (75, 93)),    # riser behind the bottom jar row
        ((79, 92), (94, 103)),   # counter board
        ((93, 111), (104, 121))]  # cloth skirt and the foot line
WALL_X = [(6, 148), (154, 173)]  # back wall spans (inside the posts): display, Granny's nook
WALL_ROWS = (37, 69)              # repainted in the display
NOOK_ROWS = (37, 121)             # repainted in the nook
RISER_ROWS = (75, 93)


def main():
    src = Image.open(SRC).convert("RGBA")
    out = Image.new("RGBA", (W, H))
    for (a, b), (c, d) in ROWS:
        for ty in range(c, d + 1):
            sy = a + round((ty - c) * (b - a) / max(1, d - c))
            out.paste(src.crop((0, sy, W, sy + 1)), (0, ty))
    px = out.load()

    def planks(x0, x1, y0, y1, base, seam):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if px[x, y][3] == 0:
                    continue
                k = (x - x0) % 12
                px[x, y] = seam + (255,) if k == 0 else (base + (255,))
        for x in range(x0 + 1, x1 + 1, 12):  # 1 px light edge right of each seam, top-left light
            for y in range(y0, y1 + 1):
                if px[x, y][3]:
                    px[x, y] = WINE + (255,)

    x0, x1 = WALL_X[0]
    planks(x0, x1, WALL_ROWS[0], WALL_ROWS[1], PLUM, BARK9)
    planks(x0, x1, RISER_ROWS[0], RISER_ROWS[1], PLUM, BARK9)
    x0, x1 = WALL_X[1]
    planks(x0, x1, NOOK_ROWS[0], NOOK_ROWS[1] - 1, PLUM, BARK9)
    for y in range(122, 125):  # ground shadow under the foot line, shifted right
        for x in range(4 + (y - 122), W):
            px[x, y] = SHADOW + (255,)
    out.save(OUT)
    print(OUT, out.size)


if __name__ == "__main__":
    main()
