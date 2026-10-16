extends Node2D
## GD-GARDEN · Static garden dressing over the ground tiles and under everything that y-sorts: the back hedge,
## the wooden fence (left, right, bottom, with gaps for the gate and the town road) and flower clumps.
## Palette-coloured placeholder shapes until the garden props (art-bible §3.6) land.

const Layout := preload("res://scenes/garden/garden_layout.gd")
const T := 16

const C_INK := Color("111010")
const C_BARK_DARK := Color("50361e")
const C_BARK := Color("83571e")
const C_BARK_LIGHT := Color("c58845")
const C_OLIVE_DARK := Color("314524")
const C_OLIVE := Color("53612e")
const C_OLIVE_MID := Color("747c37")
const C_OLIVE_LIGHT := Color("b1a13d")
const C_GOLD := Color("e5bd7f")
const C_RED := Color("c94d2e")


func _draw() -> void:
	_draw_hedge()
	_draw_leaf_specks()
	for f in Layout.FLOWERS:
		_flower(f[0], Color(String(f[1])))
	for y in range(Layout.HEDGE_ROWS, Layout.H):
		var left := Vector2i(0, y)
		var right := Vector2i(Layout.W - 1, y)
		if not Layout.is_road_exit(left):
			_fence_side(left)
		if not Layout.is_road_exit(right):
			_fence_side(right)
	for x in Layout.W:
		var c := Vector2i(x, Layout.H - 1)
		if not Layout.is_gate(c):
			_fence_front(c)


## Back hedge along the top rows: overlapping round bushes with a few autumn leaves.
func _draw_hedge() -> void:
	var h := Layout.HEDGE_ROWS * T
	draw_rect(Rect2(0, 0, Layout.W * T, h), C_OLIVE_DARK)
	for i in range(-1, Layout.W * 2 + 1):
		var x := i * 8 - 4
		var y := h - 20 + (i % 3) * 2
		draw_rect(Rect2(x, y, 16, 18), C_INK)
		draw_rect(Rect2(x + 1, y + 1, 14, 16), C_OLIVE)
		draw_rect(Rect2(x + 2, y + 1, 10, 9), C_OLIVE_MID)
		draw_rect(Rect2(x + 3, y + 2, 4, 2), C_OLIVE_LIGHT)
		if i % 4 == 1:
			draw_rect(Rect2(x + 9, y + 6, 2, 2), C_RED)
		elif i % 5 == 2:
			draw_rect(Rect2(x + 5, y + 9, 2, 2), C_GOLD)


## A few fallen leaves blown onto the grass (on every few cells, picked by a stable per-cell hash).
func _draw_leaf_specks() -> void:
	var colors := [C_RED, Color("b66813"), C_GOLD, Color("a22512")]
	for y in range(Layout.HEDGE_ROWS, Layout.H):
		for x in Layout.W:
			var c := Vector2i(x, y)
			var h := Layout.cell_hash(c)
			if h % 4 != 0 or Layout.ground(c) != Layout.T_GRASS:
				continue
			for i in 2:
				var px := x * T + (h >> (3 + i * 4)) % 13 + 1
				var py := y * T + (h >> (5 + i * 4)) % 13 + 1
				draw_rect(Rect2(px, py, 2, 1), colors[(h >> (2 + i)) % colors.size()])


## Side fence seen from above: a rail running down the tile with a post at its middle.
func _fence_side(c: Vector2i) -> void:
	var x := c.x * T + 6
	var y := c.y * T
	draw_rect(Rect2(x, y, 4, T), C_INK)
	draw_rect(Rect2(x + 1, y, 2, T), C_BARK)
	draw_rect(Rect2(x - 1, y + 4, 6, 9), C_INK)
	draw_rect(Rect2(x, y + 5, 4, 7), C_BARK)
	draw_rect(Rect2(x, y + 5, 4, 2), C_BARK_LIGHT)


## Front fence: pickets with two rails, feet on the bottom of the tile.
func _fence_front(c: Vector2i) -> void:
	var x := c.x * T
	var base := (c.y + 1) * T
	draw_rect(Rect2(x, base - 11, T, 2), C_BARK_DARK)
	draw_rect(Rect2(x, base - 6, T, 2), C_BARK_DARK)
	for px in [1, 6, 11]:
		draw_rect(Rect2(x + px, base - 15, 4, 15), C_INK)
		draw_rect(Rect2(x + px + 1, base - 14, 2, 14), C_BARK)
		draw_rect(Rect2(x + px + 1, base - 14, 2, 2), C_BARK_LIGHT)


func _flower(c: Vector2i, petal: Color) -> void:
	var o := Vector2(c.x * T + 4, c.y * T + 6)
	for p in [Vector2(0, 2), Vector2(5, 0), Vector2(3, 5)]:
		draw_rect(Rect2(o + p + Vector2(1, 2), Vector2(1, 3)), C_OLIVE)
		draw_rect(Rect2(o + p, Vector2(3, 2)), petal)
		draw_rect(Rect2(o + p + Vector2(1, 0), Vector2(1, 1)), C_GOLD if petal != C_GOLD else C_RED)
