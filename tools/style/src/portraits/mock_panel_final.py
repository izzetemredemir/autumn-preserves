#!/usr/bin/env python3
"""x2 mock: each portrait candidate inside the 9-slice paper panel (16x16, margin 5)."""
import sys
from PIL import Image
M = 5
panel = Image.open("game/assets/sprites/ui/ui_panel_paper.png").convert("RGBA")
def nine(w, h):
    out = Image.new("RGBA", (w, h))
    pw, ph = panel.size
    xs = [(0, M, 0, M), (M, pw - M, M, w - M), (pw - M, pw, w - M, w)]
    ys = [(0, M, 0, M), (M, ph - M, M, h - M), (ph - M, ph, h - M, h)]
    for sx0, sx1, dx0, dx1 in xs:
        for sy0, sy1, dy0, dy1 in ys:
            t = panel.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.NEAREST)
            out.paste(t, (dx0, dy0))
    return out
names = ["tonty", "barnaby", "rosie", "pip", "mia", "leo"]
W = H = 64
sheet = Image.new("RGBA", ((W+4) * 6 + 4, H + 8), (35, 40, 42, 255))
for i, n in enumerate(names):
    p = nine(W, H)
    p.alpha_composite(Image.open(f"game/assets/sprites/portraits/portrait_{n}.png").convert("RGBA").crop((0,0,48,48)), (8, 8))
    sheet.alpha_composite(p, (4 + i * (W + 4), 4))
sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save("tools/style/review/portraits_final_panel_x2.png")
