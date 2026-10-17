"""Tiny helpers for the ART-GARDEN2 generators: compose hand-drawn ASCII parts into frames and write an
ascii_sprite.py source. A part is a block of text (one char per pixel, '.' = transparent); placing it with
outline=True rings its own fill with ink first, so overlapping parts stay readable (each keeps its contour).
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
INK = "k"
LEGEND = {  # one shared legend for every garden2 source
    "k": "ink", "D": "plum_900", "W": "wine_700", "R": "leaf_red_700", "r": "leaf_red_500", "p": "leaf_peach_300",
    "A": "amber_600", "g": "gold_700", "y": "gold_300", "G": "gold_200", "C": "cream_100", "c": "cream_400",
    "s": "stone_300", "m": "stone_500", "t": "stone_700", "x": "slate_900", "B": "bark_900", "b": "bark_700",
    "o": "bark_500", "w": "water_700", "q": "water_600", "v": "sage_400", "V": "olive_600", "O": "olive_800",
    "e": "olive_900", "l": "olive_300", "L": "olive_500", "u": "water_500", "n": "water_800",
}


def part(text):
    """Text block -> list of rows (leading/trailing blank lines dropped, rows padded to the same width)."""
    rows = [r for r in text.strip("\n").split("\n")]
    w = max(len(r) for r in rows)
    return [r.ljust(w, ".") for r in rows]


def blank(w, h):
    return [["."] * w for _ in range(h)]


def place(grid, rows, x, y, outline=False, flip=False):
    """Draw `rows` with its top-left at (x, y); '.' is transparent. outline: ink ring around this part."""
    h, w = len(grid), len(grid[0])
    if flip:
        rows = [r[::-1] for r in rows]
    filled = set()
    for j, r in enumerate(rows):
        for i, ch in enumerate(r):
            if ch != ".":
                filled.add((x + i, y + j))
    if outline:
        for (px, py) in filled:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (px + dx, py + dy)
                if q not in filled and 0 <= q[0] < w and 0 <= q[1] < h:
                    grid[q[1]][q[0]] = INK
    for j, r in enumerate(rows):
        for i, ch in enumerate(r):
            if ch != "." and 0 <= x + i < w and 0 <= y + j < h:
                grid[y + j][x + i] = ch


def ring(grid):
    """Ink outline around the whole frame silhouette (like ascii_sprite.py --outline)."""
    h, w = len(grid), len(grid[0])
    add = []
    for y in range(h):
        for x in range(w):
            if grid[y][x] != ".":
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and grid[ny][nx] not in (".", INK):
                    add.append((x, y))
                    break
    for x, y in add:
        grid[y][x] = INK


def write(name, header, frames):
    """frames: list of grids (lists of char lists). Writes <name>.txt next to this file."""
    used = sorted({ch for f in frames for row in f for ch in row} - {"."})
    lines = [f"# {h}" for h in header.split("\n")] + ["legend . transparent"]
    lines += [f"legend {k} {LEGEND[k]}" for k in used]
    for f in frames:
        lines.append("frame")
        lines += ["".join(r) for r in f]
    with open(os.path.join(HERE, f"{name}.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
