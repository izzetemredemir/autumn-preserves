class_name PackJarRules
extends RefCounted
## Pure rules of pack_jar (spec 11.2): grid size, fill ratio, brine band, stars. No autoload dependencies.

const COLS := 6
const ROWS := 8
const LINE_ROWS := 7
const BELOW_LINE_CELLS := COLS * LINE_ROWS
const BRINE_BAND := 1


static func piece_size(texture: String) -> Vector2i:
	match texture:
		"slices":
			return Vector2i(1, 2)
		"strips":
			return Vector2i(1, 3)
		"caps":
			return Vector2i(2, 1)
	return Vector2i(1, 1)


## filled = occupied cells below the fill line.
static func fill_ratio(filled: int) -> float:
	return clampf(float(filled) / float(BELOW_LINE_CELLS), 0.0, 1.0)


## True when the brine surface (in rows) is within +-1 row of the fill line.
static func brine_in_band(level_rows: float) -> bool:
	return absi(roundi(level_rows) - LINE_ROWS) <= BRINE_BAND


static func stars_for(fill: float, brine_ok: bool) -> int:
	var s := 3 if fill >= 0.9 else (2 if fill >= 0.75 else 1)
	if not brine_ok:
		s -= 1
	return maxi(s, 1)


## grid is bottom-first rows of columns; counts non-zero cells below the line.
static func count_below_line(grid: Array) -> int:
	var n := 0
	for r in mini(LINE_ROWS, grid.size()):
		for c in grid[r]:
			if int(c) != 0:
				n += 1
	return n


## Column heights (top occupied row + 1).
static func heights_of(grid: Array) -> Array:
	var h: Array = []
	for c in COLS:
		var top := 0
		for r in grid.size():
			if int(grid[r][c]) != 0:
				top = r + 1
		h.append(top)
	return h


## Resting row for a w-wide piece at column x: lowest position above all covered columns.
static func landing_row(heights: Array, x: int, w: int) -> int:
	var row := 0
	for c in range(x, x + w):
		row = maxi(row, int(heights[c]))
	return row
