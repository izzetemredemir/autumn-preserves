#!/usr/bin/env python3
"""Writes the ascii_sprite sources for the press/knead mini-game small sprites (ART-MG-B).
Run from repo root: python3 tools/style/src/minigames/gen_mg.py, then render each .txt with ascii_sprite.py."""
import math

OUT = "tools/style/src/minigames"
LEG = """legend . transparent
legend k ink
legend d bark_900
legend b bark_700
legend t bark_500
legend g gold_300
legend c cream_100
legend r cream_400
legend s stone_500
legend S stone_700
legend w wine_700
legend R leaf_red_500
legend G water_600
legend H gold_200
legend e olive_800
legend p leaf_peach_300
legend P amber_600
"""


def write(name, frames):
    with open(f"{OUT}/{name}.txt", "w") as f:
        f.write(LEG)
        for fr in frames:
            f.write("frame\n" + "\n".join("".join(r) for r in fr) + "\n")


def grid(w, h):
    return [["."] * w for _ in range(h)]


# --- lever: 3 frames 56x30, screw centre at x=6 (pivot), bar goes right, end tilts ---
def lever(end_dy):
    g = grid(56, 30)
    px, py = 6, 15
    for x in range(0, 52):
        yc = py + round(end_dy * max(0, x - px) / 46.0)
        for dy in range(-2, 2):
            if 0 <= yc + dy < 30:
                g[yc + dy][x] = "k" if dy in (-2, 1) else ("t" if dy == -1 else "b")
    cy = py + end_dy
    for dy in range(-4, 5):
        for dx in range(-4, 5):
            if dx * dx + dy * dy <= 17:
                x, y = 50 + dx, cy + dy
                if 0 <= y < 30 and 0 <= x < 56:
                    g[y][x] = "k" if dx * dx + dy * dy > 11 else ("t" if dx + dy < 0 else "b")
    for dy in range(-4, 6):
        for dx in range(-3, 4):
            g[py + dy][px + dx] = "k" if abs(dx) == 3 or dy in (-4, 5) else "s"
    return g


write("press_lever", [lever(-10), lever(0), lever(10)])


# --- bottle 24x56: glass walls only, interior transparent (juice drawn behind) ---
def bottle():
    w, h = 24, 56
    g = grid(w, h)
    for y in range(h - 1):
        if y < 14:
            x0, x1 = 8, 15
        elif y < 20:
            x0, x1 = 8 - (y - 13), 15 + (y - 13)
        else:
            x0, x1 = 2, 21
        g[y][x0] = "k"
        g[y][x1] = "k"
        g[y][x0 + 1] = "r" if y > 1 else "c"
        g[y][x1 - 1] = "s"
    for x in range(2, 22):
        g[55][x] = "k"
    for x in range(8, 16):
        g[0][x] = "k"
    for y in range(24, 50):
        g[y][4] = "c" if y % 7 else "r"
    return g


write("press_bottle", [bottle()])


# --- beat markers 8x20: normal, perfect, good, miss ---
def marker(f, fl):
    g = grid(8, 20)
    for y in range(20):
        for x in range(8):
            if x in (0, 7) and y in (0, 19):
                continue
            g[y][x] = "k" if (x in (0, 7) or y in (0, 19)) else f
    for y in range(2, 6):
        g[y][2] = fl
    return g


write("press_beat", [marker("c", "r"), marker("H", "g"), marker("e", "c"), marker("w", "R")])


# --- hit frame 28x36 ---
def hitline():
    g = grid(28, 36)
    for y in range(36):
        for x in range(28):
            if x in (0, 27) or y in (0, 35):
                g[y][x] = "r"
    for y in range(36):
        g[y][13] = g[y][14] = "g"
    for y in range(1, 35):
        g[y][1] = g[y][26] = "k"
    return g


write("press_hit", [hitline()])


# --- crimp points 6x6: idle / done / cursor ---
def pt(f, o):
    g = grid(6, 6)
    for y in range(6):
        for x in range(6):
            if (x, y) in ((0, 0), (5, 0), (0, 5), (5, 5)):
                continue
            g[y][x] = o if x in (0, 5) or y in (0, 5) else f
    return g


write("knead_point", [pt("c", "k"), pt("G", "k"), pt("R", "k")])


# --- dough squash steps, 72x44: soft blob, shadow under it ---
def dough(step):
    W, H = 72, 44
    g = grid(W, H)
    rx = (56 + step * 4) / 2.0
    ry = (40 - step * 4) / 2.0
    cx, cy = W / 2.0, H - 4 - ry
    for y in range(H):
        for x in range(W):
            dx = (x + .5 - cx) / rx
            dy = (y + .5 - cy) / ry
            d = dx * dx + dy * dy
            if d <= 1.0:
                if d > 0.88:
                    g[y][x] = "k"
                else:
                    lit = (dx * -0.5 + dy * -0.9) > 0.35
                    g[y][x] = "c" if lit else ("g" if dy < 0.35 else "t")
            else:
                sy = (y + .5 - (H - 3)) / 3.0
                if (dx * dx + sy * sy) <= 1.05 and y > cy + ry * 0.6:
                    g[y][x] = "P"
    return g


write("knead_dough", [dough(s) for s in range(5)])


# --- hands 32x24: up / down (left hand, fingers point right; right is flipped in game) ---
def hand(down):
    g = grid(32, 24)
    oy = 3 if down else 0
    def put(x, y, c):
        if 0 <= x < 32 and 0 <= y + oy < 24:
            g[y + oy][x] = c
    # palm
    for y in range(3, 20):
        for x in range(4, 28):
            dx = (x - 14.5) / 11.0
            dy = (y - 11.5) / 8.0
            d = dx * dx + dy * dy
            if d <= 1.0:
                put(x, y, "k" if d > 0.8 else ("p" if dy < 0.2 else "P"))
    # four fingers, rounded, with ink gaps
    for i, fy in enumerate((6, 9, 12, 15)):
        ln = (7, 8, 7, 5)[i]
        for x in range(22, 22 + ln):
            put(x, fy, "k" if x == 21 + ln else "p")
            put(x, fy + 1, "P")
            put(x, fy + 2, "k")
        put(22 + ln, fy + 1, "k")
    # thumb
    for x in range(10, 20):
        put(x, 3, "k")
        put(x, 4, "p")
    # sleeve
    for y in range(5, 18):
        for x in range(0, 7):
            put(x, y, "k" if x == 0 or y in (5, 17) else ("R" if y < 12 else "w"))
    return g


write("knead_hands", [hand(0), hand(1)])


# --- pie plate (r92), filling disc (r62), crust overlay (168x168) ---
def disc(R, f):
    S = R * 2
    g = grid(S, S)
    for y in range(S):
        for x in range(S):
            d = math.hypot(x + .5 - R, y + .5 - R)
            if d <= R:
                g[y][x] = "k" if d > R - 1 else f(d, x, y)
    return g


write("pie_plate", [disc(92, lambda d, x, y: "r" if d > 86 else ("c" if d > 84 else "S"))])
write("pie_filling", [disc(62, lambda d, x, y: ("t" if (x + y) % 6 == 0 else "g") if d < 55 else "g")])


def crust_fx():
    S, R = 168, 84
    g = grid(S, S)
    for y in range(S):
        for x in range(S):
            d = math.hypot(x + .5 - R, y + .5 - R)
            a = math.atan2(y + .5 - R, x + .5 - R)
            if 62 <= d <= R:
                if d > R - 1.5:
                    g[y][x] = "d"
                elif d < 63.5:
                    g[y][x] = "b"
                elif d > R - 6 and math.sin(a * 24) > 0.2:
                    g[y][x] = "d"
                elif d < 72 and -2.6 < a < -0.7 and (x + y) % 3 == 0:
                    g[y][x] = "c"
    return g


write("pie_crust_fx", [crust_fx()])
