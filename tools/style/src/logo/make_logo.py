#!/usr/bin/env python3
"""Autumn Preserves logo: jar on a plum roundel. Run from repo root: python3 tools/style/src/logo/make_logo.py
Writes game/icon.png (1024), icon.ico, icon.icns, splash, wordmark, PWA icons, review sheet. Palette colours only, no partial alpha."""
import os, subprocess, shutil, tempfile
from PIL import Image, ImageDraw, ImageFont

C = dict(plum=(0x3d,0x1f,0x29), plum2=(0x62,0x27,0x2c), gold=(0xe5,0xbd,0x7f), gold2=(0xc5,0x88,0x45),
         goldd=(0xb6,0x68,0x13), cream=(0xf2,0xd9,0xc5), cream2=(0xb9,0xa6,0x97), glass=(0xb4,0xb3,0xa0), glass2=(0x81,0x74,0x6a),
         red=(0xa2,0x25,0x12), red2=(0xc9,0x4d,0x2e), peach=(0xe1,0x90,0x64), bark=(0x83,0x57,0x1e))
G = "game"
SPLASH_BG = (0x2a, 0x1a, 0x1f, 255)


def roundel(s):
    n = 32 * s
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0)); px = im.load()
    c = (n - 1) / 2
    for y in range(n):
        for x in range(n):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
            if d <= n / 2 + 0.2:
                px[x, y] = (C["gold"] if d > n / 2 - 0.9 else C["plum"]) + (255,)
                if s == 2 and n / 2 - 3.3 < d <= n / 2 - 2.3:
                    px[x, y] = C["plum2"] + (255,)
    return im


def jar(s, detail):
    im = roundel(s); d = ImageDraw.Draw(im)

    def R(x0, y0, x1, y1, col):
        d.rectangle([x0 * s, y0 * s, (x1 + 1) * s - 1, (y1 + 1) * s - 1], fill=C[col] + (255,))

    def P(x, y, col): R(x, y, x, y, col)
    # metal lid + cloth skirt
    R(10, 6, 21, 8, "gold"); R(10, 8, 21, 8, "gold2"); R(11, 5, 20, 5, "gold"); P(10, 6, "plum"); P(21, 6, "plum")
    R(9, 9, 22, 10, "red2"); R(9, 10, 22, 10, "red"); P(9, 9, "red"); P(22, 9, "red")
    for x in range(10, 22, 3): P(x, 9, "cream")
    # glass
    R(11, 11, 20, 12, "glass"); R(10, 13, 21, 26, "glass"); R(11, 27, 20, 27, "glass2"); R(10, 26, 21, 26, "glass2")
    # jam
    R(11, 14, 20, 25, "red2"); R(11, 22, 20, 25, "red"); R(11, 14, 20, 14, "peach")
    # label + leaf
    R(12, 17, 19, 23, "cream"); R(12, 23, 19, 23, "cream2")
    P(15, 18, "goldd"); R(14, 19, 17, 19, "goldd"); R(14, 20, 17, 20, "goldd"); R(15, 21, 16, 21, "goldd"); P(16, 22, "bark")
    R(10, 13, 10, 25, "cream")
    if detail:
        R(11, 14, 11, 21, "peach"); P(15, 20, "red"); P(16, 20, "red"); P(15, 19, "peach")
        R(21, 14, 21, 24, "glass2"); R(11, 11, 20, 11, "cream2"); P(12, 12, "cream")
    return im


def save(im, p):
    os.makedirs(os.path.dirname(p), exist_ok=True); im.save(p)


def up(im, k): return im.resize((im.width * k, im.height * k), Image.NEAREST)


def main():
    j32, j64 = jar(1, False), jar(2, True)
    out = "tools/style/src/logo"
    save(j32, f"{out}/logo_32.png"); save(j64, f"{out}/logo_64.png")
    big = up(j64, 16); save(big, f"{G}/icon.png")
    big.save(f"{G}/icon.ico", sizes=[(s, s) for s in (16, 32, 48, 64, 128, 256)])
    tmp = tempfile.mkdtemp(); iset = f"{tmp}/icon.iconset"; os.makedirs(iset)
    for sz in (16, 32, 64, 128, 256, 512):
        for r in (1, 2):
            px = sz * r
            src = j32 if px == 32 else (j64 if px == 64 else big)
            im = up(src, px // src.width) if (px > src.width and px % src.width == 0) else src.resize((px, px), Image.NEAREST)
            im.save(f"{iset}/icon_{sz}x{sz}{'@2x' if r == 2 else ''}.png")
    subprocess.run(["iconutil", "-c", "icns", iset, "-o", f"{G}/icon.icns"], check=True)
    shutil.rmtree(tmp)
    for n in (144, 180, 512):
        save(big.resize((n, n), Image.NEAREST), f"game/web_icons/icon_{n}.png")

    font = ImageFont.truetype(f"{G}/assets/fonts/m6x11plus.ttf", 18)  # 18 is the font's clean size; 16 garbled the letters

    def text_img(txt, col):
        m = Image.new("L", (200, 24), 0); dd = ImageDraw.Draw(m); dd.fontmode = "1"
        dd.text((0, 0), txt, font=font, fill=255); m = m.crop(m.getbbox())
        t = Image.new("RGBA", m.size, (0, 0, 0, 0)); t.paste(Image.new("RGBA", m.size, col + (255,)), mask=m.point(lambda v: 255 if v > 127 else 0))
        return t
    word = text_img("Autumn Preserves", C["gold"]); shadow = text_img("Autumn Preserves", C["bark"])

    def lettering(k):
        w, h = word.size
        im = Image.new("RGBA", ((w + 1) * k, (h + 1) * k), (0, 0, 0, 0))
        im.alpha_composite(up(shadow, k), (0, k)); im.alpha_composite(up(word, k), (0, 0)); return im
    L = lettering(2)
    wm = Image.new("RGBA", (32 + 8 + L.width, 32), (0, 0, 0, 0))
    wm.alpha_composite(j32, (0, 0)); wm.alpha_composite(L, (40, (32 - L.height) // 2))
    save(wm, f"{G}/assets/sprites/ui/logo_wordmark.png")
    sp = Image.new("RGBA", (480, 270), SPLASH_BG)
    sp.alpha_composite(up(j32, 4), (176, 38)); sp.alpha_composite(L, ((480 - L.width) // 2, 38 + 128 + 24))
    save(sp, f"{G}/splash.png")
    sheet = Image.new("RGBA", (40 + 192 + 40 + 192 + 40 + 256 + 40 + 16 + 40, 300), SPLASH_BG)
    x = 40
    for im, k in ((j32, 6), (j64, 3), (j64, 4)):
        u = up(im, k); sheet.alpha_composite(u, (x, 20)); x += u.width + 40
    sheet.alpha_composite(j32.resize((16, 16), Image.NEAREST), (x, 20))
    save(sheet, "tools/style/review/logo/logo_sheet.png")


main()
