extends Node2D
## GD-GARDEN / ART-GARDEN · Static garden dressing over the ground tiles and under everything that y-sorts:
## the painted ground (leaf-covered lawn, the dirt path and road, the back hedge; it covers the whole map, the
## tiles only show in the margin of wider windows), the decor (pumpkins, flower clumps, leaf piles) and the
## wooden fence (left, right, bottom, with gaps for the gate and the town road). All sprites, integer positions.

const Layout := preload("res://scenes/garden/garden_layout.gd")
const T := 16
const GROUND := preload("res://assets/sprites/garden/garden_ground.png")
const DECOR := preload("res://assets/sprites/garden/garden_decor.png")  ## 16x12 frames: Layout.D_*
const FENCE_H := preload("res://assets/sprites/garden/garden_fence_h.png")  ## 16x16: run with post, rails only
const FENCE_V := preload("res://assets/sprites/garden/garden_fence_v.png")  ## 16x16: side run, bottom-left corner
const DECOR_SIZE := Vector2i(16, 12)
## Side-run rows drawn next to the road gap: the run stops at its post (fence_v rows 0-12 / 3-15).
const RUN_TO_POST := 13


func _draw() -> void:
	draw_texture(GROUND, Vector2.ZERO)
	for d in Layout.DECOR:
		var c: Vector2i = d[0]
		var pos := Vector2(c.x * T, (c.y + 1) * T - DECOR_SIZE.y)
		_frame(DECOR, int(d[1]), DECOR_SIZE, pos)
	var bottom := Layout.H - 1
	for y in range(Layout.HEDGE_ROWS, bottom):
		for x in [0, Layout.W - 1]:
			_side(Vector2i(x, y))
	_frame(FENCE_V, 1, Vector2i(T, T), Vector2(0, bottom * T))
	_frame(FENCE_V, 1, Vector2i(T, T), Vector2((Layout.W - 1) * T, bottom * T), true)
	for x in range(1, Layout.W - 1):
		var c := Vector2i(x, bottom)
		if Layout.is_gate(c):
			continue
		var by_gate := Layout.is_gate(c + Vector2i.LEFT) or Layout.is_gate(c + Vector2i.RIGHT)
		_frame(FENCE_H, 1 if by_gate else 0, Vector2i(T, T), Vector2(x * T, bottom * T))


## One side-fence cell; next to the road gap the rail ends at the post instead of running into the opening.
func _side(c: Vector2i) -> void:
	if Layout.is_road_exit(c):
		return
	var pos := Vector2(c.x * T, c.y * T)
	if Layout.is_road_exit(c + Vector2i.DOWN):
		draw_texture_rect_region(FENCE_V, Rect2(pos, Vector2(T, RUN_TO_POST)), Rect2(0, 0, T, RUN_TO_POST))
	elif Layout.is_road_exit(c + Vector2i.UP):
		var cut := T - RUN_TO_POST
		draw_texture_rect_region(FENCE_V, Rect2(pos + Vector2(0, cut), Vector2(T, RUN_TO_POST)),
			Rect2(0, cut, T, RUN_TO_POST))
	else:
		_frame(FENCE_V, 0, Vector2i(T, T), pos)


## Frame `i` of a one-row sheet at a whole-pixel position; `flip` mirrors it (the right-hand fence corner).
func _frame(tex: Texture2D, i: int, size: Vector2i, pos: Vector2, flip := false) -> void:
	var src := Rect2(i * size.x, 0, size.x, size.y)
	if flip:
		draw_set_transform(pos + Vector2(size.x, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), src)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect_region(tex, Rect2(pos, size), src)
