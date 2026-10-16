class_name TitleBackdrop
extends Control
## Title backdrop: dithered sunset sky, hills with autumn trees, Granny's cottage with chimney smoke, falling
## leaves. The static part is baked into one texture per size; leaves and smoke move in whole pixels.
## leaves_only = plain plum background with leaves (premise screen).

const BG := Color("3d1f29")
const SKY := [Color("3d1f29"), Color("62272c"), Color("a22512"), Color("c94d2e"), Color("e19064")]
const SKY_STOPS := [0.0, 0.34, 0.56, 0.72, 0.86]
const SUN := Color("f2d9c5")
const FAR := Color("62272c")
const MID := Color("50361e")
const NEAR := Color("23282a")
const TRUNK := Color("3d1f29")
const CANOPY := [Color("a22512"), Color("c94d2e"), Color("b66813"), Color("e19064"), Color("c58845")]
const LEAF := [Color("c94d2e"), Color("e19064"), Color("b66813"), Color("c58845"), Color("e5bd7f")]
const SMOKE := [Color("b9a697"), Color("81746a")]
const LEAF_COUNT := 22

var leaves_only := false

var _tex: ImageTexture
var _leaves: Array = []
var _chimney := Vector2i(-100, -100)
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 1016
	resized.connect(_rebuild)
	_rebuild()
	for i in LEAF_COUNT:
		_leaves.append(_new_leaf(true))


func _new_leaf(anywhere: bool) -> Dictionary:
	var h := maxf(size.y, 270.0)
	return {
		"x": _rng.randf_range(0.0, maxf(size.x, 480.0)),
		"y": _rng.randf_range(-h, h) if anywhere else -4.0,
		"speed": _rng.randf_range(9.0, 20.0),
		"amp": _rng.randf_range(3.0, 9.0),
		"phase": _rng.randf_range(0.0, TAU),
		"color": LEAF[_rng.randi_range(0, LEAF.size() - 1)],
	}


func _process(delta: float) -> void:
	_t += delta
	if size.x <= 0.0 or size.y <= 0.0:
		return
	for i in _leaves.size():
		var l: Dictionary = _leaves[i]
		l.y += l.speed * delta
		l.x += 4.0 * delta
		if l.y > size.y + 4.0 or l.x > size.x + 8.0:
			_leaves[i] = _new_leaf(false)
			_leaves[i].x = _rng.randf_range(-20.0, size.x)
	queue_redraw()


func _draw() -> void:
	if _tex != null:
		draw_texture(_tex, Vector2.ZERO)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), BG)
	if not leaves_only:
		_draw_smoke()
	for l in _leaves:
		var sway := sin(_t * 1.4 + float(l.phase))
		var p := Vector2i(int(l.x + sway * float(l.amp)), int(l.y))
		var c: Color = l.color
		if sway > 0.3:
			draw_rect(Rect2(p, Vector2i(3, 1)), c)
			draw_rect(Rect2(p + Vector2i(1, 1), Vector2i(2, 1)), c)
		elif sway < -0.3:
			draw_rect(Rect2(p, Vector2i(2, 1)), c)
			draw_rect(Rect2(p + Vector2i(0, 1), Vector2i(3, 1)), c)
		else:
			draw_rect(Rect2(p, Vector2i(2, 2)), c)


func _draw_smoke() -> void:
	for i in 4:
		var life := fmod(_t + i * 0.8, 3.2)
		var off := Vector2i(int(life * 4.0 + sin(life * 2.5) * 2.0), -int(life * 9.0))
		var s := 2 if life < 1.6 else 1
		draw_rect(Rect2(_chimney + off, Vector2i(s + 1, s)), SMOKE[0] if life < 2.2 else SMOKE[1])


func _rebuild() -> void:
	var w := int(size.x)
	var h := int(size.y)
	if w <= 0 or h <= 0:
		return
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	if not leaves_only:
		_paint_scene(img, w, h)
	_tex = ImageTexture.create_from_image(img)
	queue_redraw()


func _paint_scene(img: Image, w: int, h: int) -> void:
	var horizon := int(h * 0.64)
	# Sky bands with a 4-row checker dither at each boundary.
	for i in SKY.size():
		var y0 := int(horizon * float(SKY_STOPS[i]))
		var y1 := horizon if i == SKY.size() - 1 else int(horizon * float(SKY_STOPS[i + 1]))
		img.fill_rect(Rect2i(0, y0, w, y1 - y0), SKY[i])
		if i > 0:
			for y in range(y0 - 2, y0 + 2):
				for x in w:
					if (x + y) % 2 == 0:
						img.set_pixel(x, y, SKY[i] if y < y0 else SKY[i - 1])
	_circle(img, Vector2i(int(w * 0.79), horizon - 22), 17, SUN)
	for x in w:
		var far := horizon - 16 - int(9.0 * sin(x * 0.013 + 1.0) + 5.0 * sin(x * 0.031 + 2.0))
		img.fill_rect(Rect2i(x, far, 1, h - far), FAR)
	for x in w:
		img.fill_rect(Rect2i(x, _mid(x, horizon), 1, h), MID)
	var r := RandomNumberGenerator.new()
	r.seed = 16
	var house_x := int(w * 0.15)
	for i in int(w / 22.0):
		var tx := r.randi_range(0, w - 1)
		var rad := r.randi_range(4, 7)
		var col: Color = CANOPY[r.randi_range(0, CANOPY.size() - 1)]
		if absi(tx - house_x) < 22:
			continue
		var ty := _mid(tx, horizon) + 2
		img.fill_rect(Rect2i(tx - 1, ty - rad - 2, 2, rad + 2), TRUNK)
		_circle(img, Vector2i(tx, ty - rad - (rad >> 1) - 2), rad, col)
	_house(img, house_x, _mid(house_x, horizon) + 3)
	for x in w:
		var near := h - 26 - int(5.0 * sin(x * 0.021 + 0.5) + 3.0 * sin(x * 0.053))
		img.fill_rect(Rect2i(x, near, 1, h - near), NEAR)


func _mid(x: int, horizon: int) -> int:
	return horizon + 14 - int(11.0 * sin(x * 0.009 + 0.3) + 5.0 * sin(x * 0.027 + 1.7))


func _house(img: Image, cx: int, base: int) -> void:
	img.fill_rect(Rect2i(cx + 4, base - 24, 3, 8), MID)
	_chimney = Vector2i(cx + 4, base - 27)
	img.fill_rect(Rect2i(cx - 10, base - 12, 20, 12), Color("c58845"))
	for i in 9:
		img.fill_rect(Rect2i(cx - 12 + i, base - 13 - i, 24 - i * 2, 1), Color("a22512"))
	img.fill_rect(Rect2i(cx - 7, base - 9, 4, 4), Color("e5bd7f"))
	img.fill_rect(Rect2i(cx - 6, base - 9, 1, 4), Color("b66813"))
	img.fill_rect(Rect2i(cx + 2, base - 8, 4, 8), TRUNK)


static func _circle(img: Image, c: Vector2i, rad: int, col: Color) -> void:
	for dy in range(-rad, rad + 1):
		var dx := int(sqrt(float(rad * rad - dy * dy)))
		img.fill_rect(Rect2i(c.x - dx, c.y + dy, dx * 2 + 1, 1), col)
