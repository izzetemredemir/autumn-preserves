class_name TitleFx
extends RefCounted
## FIRST-60 · The life of the title painting (bg_title.png), in its own pixel coordinates: falling leaves (a back
## layer, and a few larger ones that pass in front of the menu), chimney smoke, birds crossing, glints on the river
## and motes shimmering in the low sun. Everything is a function of the time `t`, so any moment can be drawn again
## (the intro seeks, smoke shots repeat). Each mark is whole art pixels in palette colours, drawn at an integer
## `zoom` from an integer `origin`: the intro reuses it over the same painting at 2x.

const SIZE := Vector2i(480, 270)
const ART := "res://assets/sprites/scenes/bg_title.png"
const CHIMNEY := Vector2i(40, 105)  ## chimney mouth of the painted cottage
const RIVER := Rect2i(325, 165, 96, 58)  ## box around the river; glints land on its water pixels only
const WATER := [Color("415c5d"), Color("2e3f3f")]
const MOUNTAIN := Color("81746a")  ## the far grey range (snow caps in the intro's snow beat)
const MOUNTAIN_X := Vector2i(228, 480)
const MOUNTAIN_Y := Vector2i(100, 165)
const MOTES := Rect2i(20, 60, 260, 150)  ## warm light under the big tree and around the cottage
const LEAF := [Color("c94d2e"), Color("e19064"), Color("b66813"), Color("c58845"), Color("e5bd7f")]
const FRONT_LEAF := [Color("c94d2e"), Color("e19064"), Color("c94d2e"), Color("a22512")]
const SMOKE := [Color("b9a697"), Color("81746a")]
const BIRD := Color("3d1f29")
const CREAM := Color("f2d9c5")
const GOLD := Color("e5bd7f")
const PALE := Color("dbcc83")
## Bird frames, 5x2 (wings up, level, down, level), and front-leaf shapes (tilt left, flat, tilt right).
const BIRD_FRAMES := [["x...x", ".xxx."], [".....", "xxxxx"], [".xxx.", "x...x"], [".....", "xxxxx"]]
const FRONT_SHAPES := [["xx...", "xxxx.", ".xxxx", "...x."], ["..x..", "xxxxx", ".xxx.", "..x.."],
	["...xx", ".xxxx", "xxxx.", ".x..."]]
const FLOCK := [Vector2i(0, 0), Vector2i(-9, -5), Vector2i(-17, 3)]
const FLOCK_PERIOD := 22.0
const FLOCK_SPEED := 30.0
const SMOKE_PUFFS := 7
const SMOKE_LIFE := 4.2

static var _water: Array[Vector2i] = []
static var _ridge := PackedInt32Array()

## Parts to draw (the intro turns some off per beat).
var leaves := true
var front := true
var smoke := true
var birds := true
var glints := true
var motes := true
var bird_y := 86

var _back: Array = []  ## [x0, y0, speed, amp, phase, colour]
var _front: Array = []  ## [x0, y0, speed, amp, phase, colour]
var _motes: Array = []  ## [x0, y0, rise, rate, phase]


func _init(seed_value := 1016, back_count := 22, front_count := 6, mote_count := 12) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	for i in back_count:
		_back.append([r.randf_range(0.0, SIZE.x + 40.0), r.randf_range(0.0, SIZE.y + 8.0), r.randf_range(9.0, 20.0),
			r.randf_range(3.0, 9.0), r.randf_range(0.0, TAU), LEAF[r.randi_range(0, LEAF.size() - 1)]])
	for i in front_count:
		_front.append([r.randf_range(0.0, SIZE.x + 40.0), r.randf_range(0.0, SIZE.y + 8.0), r.randf_range(24.0, 34.0),
			r.randf_range(6.0, 12.0), r.randf_range(0.0, TAU), FRONT_LEAF[r.randi_range(0, FRONT_LEAF.size() - 1)]])
	for i in mote_count:
		_motes.append([r.randf_range(0.0, MOTES.size.x), r.randf_range(0.0, MOTES.size.y), r.randf_range(1.5, 4.0),
			r.randf_range(1.2, 2.6), r.randf_range(0.0, TAU)])


## Everything behind the menu: smoke, birds, river glints, light motes, back leaves.
func draw_back(ci: CanvasItem, t: float, origin := Vector2i.ZERO, zoom := 1) -> void:
	if smoke:
		_draw_smoke(ci, t, origin, zoom)
	if birds:
		_draw_birds(ci, t, origin, zoom)
	if glints:
		_draw_glints(ci, t, origin, zoom)
	if motes:
		_draw_motes(ci, t, origin, zoom)
	if leaves:
		for l in _back:
			var p := leaf_pos(l, t)
			var sway := sin(t * 1.4 + float(l[4]))
			var c: Color = l[5]
			if sway > 0.3:
				_px(ci, origin, zoom, p, Vector2i(3, 1), c)
				_px(ci, origin, zoom, p + Vector2i(1, 1), Vector2i(2, 1), c)
			elif sway < -0.3:
				_px(ci, origin, zoom, p, Vector2i(2, 1), c)
				_px(ci, origin, zoom, p + Vector2i(0, 1), Vector2i(3, 1), c)
			else:
				_px(ci, origin, zoom, p, Vector2i(2, 2), c)


## The few larger leaves that drift in front of the menu.
func draw_front(ci: CanvasItem, t: float, origin := Vector2i.ZERO, zoom := 1) -> void:
	if not front:
		return
	for l in _front:
		var p := leaf_pos(l, t)
		var sway := sin(t * 1.1 + float(l[4]))
		var shape: Array = FRONT_SHAPES[0 if sway < -0.35 else (2 if sway > 0.35 else 1)]
		_shape(ci, origin, zoom, p, shape, l[5])


## Whole-pixel position of a leaf at `t`: it falls, drifts right, sways and wraps around the painting.
static func leaf_pos(l: Array, t: float) -> Vector2i:
	var sway := sin(t * 1.4 + float(l[4])) * float(l[3])
	var x := fposmod(float(l[0]) + 4.0 * t, SIZE.x + 40.0) - 20.0 + sway
	var y := fposmod(float(l[1]) + float(l[2]) * t, SIZE.y + 8.0) - 4.0
	return Vector2i(floori(x), floori(y))


## Top-left of bird `i` of the flock at `t`, or (-999, -999) while the flock is away.
func bird_pos(i: int, t: float) -> Vector2i:
	var x := fposmod(t, FLOCK_PERIOD) * FLOCK_SPEED - 24.0
	if x > SIZE.x + 24.0:
		return Vector2i(-999, -999)
	var o: Vector2i = FLOCK[i]
	return Vector2i(floori(x) + o.x, bird_y + o.y + roundi(sin(t * 1.3 + i * 2.0) * 1.5))


func _draw_birds(ci: CanvasItem, t: float, origin: Vector2i, zoom: int) -> void:
	for i in FLOCK.size():
		var p := bird_pos(i, t)
		if p.x < -20:
			continue
		var f := int(t * 7.0 + i * 1.7) % BIRD_FRAMES.size()
		if fposmod(t + i * 0.9, 3.4) > 2.3:
			f = 1  # glide
		_shape(ci, origin, zoom, p, BIRD_FRAMES[f], BIRD)


## Puffs rise from the chimney and lean left like the painted smoke, growing from 2 px to round 3-4 px blobs, cream
## turning to grey as they thin out.
func _draw_smoke(ci: CanvasItem, t: float, origin: Vector2i, zoom: int) -> void:
	for i in SMOKE_PUFFS:
		var u := fposmod(t + i * SMOKE_LIFE / SMOKE_PUFFS, SMOKE_LIFE) / SMOKE_LIFE
		if u > 0.9:
			continue
		var off := Vector2i(-roundi(u * 11.0 + sin(u * 5.0 + i) * 1.5), -roundi(u * 32.0))
		var s := 2
		if u > 0.78:
			s = 1
		elif u > 0.5:
			s = 4
		elif u > 0.2:
			s = 3
		var p := CHIMNEY + off - Vector2i(s >> 1, s)
		var c: Color = CREAM if u < 0.35 else (SMOKE[0] if u < 0.7 else SMOKE[1])
		if s >= 3:  # round: a plus of two rects
			_px(ci, origin, zoom, p + Vector2i(1, 0), Vector2i(s - 2, s), c)
			_px(ci, origin, zoom, p + Vector2i(0, 1), Vector2i(s, s - 2), c)
		else:
			_px(ci, origin, zoom, p, Vector2i(s, s), c)


func _draw_glints(ci: CanvasItem, t: float, origin: Vector2i, zoom: int) -> void:
	var water := water_pixels()
	if water.is_empty():
		return
	for k in 7:
		var period := 0.9 + 0.13 * k
		var n := floori((t + k * 0.37) / period)
		var u := fposmod(t + k * 0.37, period) / period
		if u > 0.55:
			continue
		var p: Vector2i = water[absi(hash(k * 7919 + n * 104729)) % water.size()]
		_px(ci, origin, zoom, p, Vector2i(2 if u > 0.15 and u < 0.4 else 1, 1), PALE if u < 0.15 else CREAM)


func _draw_motes(ci: CanvasItem, t: float, origin: Vector2i, zoom: int) -> void:
	for m in _motes:
		var tw := sin(t * float(m[3]) + float(m[4]))
		if tw < 0.35:
			continue
		var x := fposmod(float(m[0]) + sin(t * 0.5 + float(m[4])) * 4.0, MOTES.size.x)
		var y := fposmod(float(m[1]) - float(m[2]) * t, MOTES.size.y)
		_px(ci, origin, zoom, MOTES.position + Vector2i(floori(x), floori(y)), Vector2i.ONE, CREAM if tw > 0.8 else GOLD)


## River pixels of the painting that glints may land on (scanned once).
static func water_pixels() -> Array[Vector2i]:
	if _water.is_empty():
		var img := _image()
		if img != null:
			var keys: Array = WATER.map(func(c: Color) -> int: return c.to_rgba32())
			for y in range(RIVER.position.y, RIVER.end.y):
				for x in range(RIVER.position.x, RIVER.end.x):
					if keys.has(img.get_pixel(x, y).to_rgba32()):
						_water.append(Vector2i(x, y))
	return _water


## Per column of the painting, the top row of the far grey range (-1: no mountain there). Scanned once.
static func ridge() -> PackedInt32Array:
	if _ridge.is_empty():
		_ridge.resize(SIZE.x)
		_ridge.fill(-1)
		var img := _image()
		if img != null:
			var key := MOUNTAIN.to_rgba32()
			for x in range(MOUNTAIN_X.x, MOUNTAIN_X.y):
				for y in range(MOUNTAIN_Y.x, MOUNTAIN_Y.y):
					if img.get_pixel(x, y).to_rgba32() == key:
						_ridge[x] = y
						break
	return _ridge


static func _image() -> Image:
	if not ResourceLoader.exists(ART):
		return null
	var img := (load(ART) as Texture2D).get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img


func _shape(ci: CanvasItem, origin: Vector2i, zoom: int, p: Vector2i, rows: Array, c: Color) -> void:
	for y in rows.size():
		var row := String(rows[y])
		var x := 0
		while x < row.length():
			if row[x] != "x":
				x += 1
				continue
			var run := 1
			while x + run < row.length() and row[x + run] == "x":
				run += 1
			_px(ci, origin, zoom, p + Vector2i(x, y), Vector2i(run, 1), c)
			x += run


static func _px(ci: CanvasItem, origin: Vector2i, zoom: int, p: Vector2i, s: Vector2i, c: Color) -> void:
	ci.draw_rect(Rect2(origin + p * zoom, s * zoom), c)
