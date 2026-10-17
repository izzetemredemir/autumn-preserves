class_name Juice
extends RefCounted
## FEEL · Shared game-feel helpers for the most-seen moments: whole pixels, palette colours only, no partial alpha,
## short (under a second) and never blocking input. Everything a helper makes frees itself. Randomness here is
## visual only (its own generator), never game state. No reduced-motion setting exists yet; `calm` is the switch
## for one (true: no squash, wiggle or flash, bursts keep a few pixels).

const C_SHADOW := Color("3d1f29")  ## plum_900, hard ground shadow (art bible §2.5)
const C_CREAM := Color("f2d9c5")
const C_CREAM_LO := Color("b9a697")
const C_STONE := Color("b4b3a0")
const C_GOLD := Color("e5bd7f")
const C_GOLD_HI := Color("dbcc83")
const RIBBON_COLORS := ["c94d2e", "e5bd7f", "e19064", "738c7a", "f2d9c5", "b66813"]
const SFX_DIR := "res://assets/audio/sfx/"

## Particle shapes drawn by Burst.
enum { DOT, RIBBON, SPARKLE, DUST }

static var calm := false
static var _rng: RandomNumberGenerator


static func rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


## Squash and stretch from the feet: Controls pivot on their bottom centre, Node2Ds on their origin.
static func squash(ci: CanvasItem, amount := 0.25, time := 0.16) -> Tween:
	if ci is Control:
		var c := ci as Control
		c.pivot_offset = Vector2(floorf(c.size.x * 0.5), c.size.y)
	var t := ci.create_tween()
	if calm:
		return t
	ci.set("scale", Vector2(1.0 + amount, 1.0 - amount))
	t.tween_property(ci, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return t


## A quick grow-and-settle around the centre (counters, icons).
static func pop(ci: CanvasItem, peak := 1.4, time := 0.14) -> Tween:
	if ci is Control:
		var c := ci as Control
		c.pivot_offset = (c.size * 0.5).floor()
	var t := ci.create_tween()
	if calm:
		return t
	ci.set("scale", Vector2(peak, peak))
	t.tween_property(ci, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return t


## Whole-pixel side-to-side wiggle on `position.x` (2-3 frames), back to where it was.
static func wiggle(ci: CanvasItem, px := 1, step := 0.05) -> Tween:
	var x: float = ci.get("position").x
	var t := ci.create_tween()
	if calm:
		return t
	for dx in [px, -px, px, 0]:
		t.tween_property(ci, "position:x", x + dx, step)
	return t


## A few pixels of dust kicked out sideways from a bottom edge `half` px either side of `at` (a jar set down).
static func dust_puff(parent: Node, at: Vector2, half := 8, z := 45) -> Node2D:
	var b := Burst.make(parent, at, z)
	var r := rng()
	for side in [-1, 1]:
		for i in (1 if calm else 4):
			b.add(DUST, Vector2(side * (half - 1 + i), -r.randi_range(0, 2)),
				Vector2(side * r.randf_range(18.0, 40.0), -r.randf_range(6.0, 18.0)), 50.0,
				r.randf_range(0.22, 0.34), C_CREAM_LO if i % 2 == 0 else C_STONE)
	return b


## Paper ribbons bursting up from `at` (spread over `width` px) and twirling down: "New recipe!".
static func ribbons(parent: Node, at: Vector2, width := 40, count := 16, z := 60) -> Node2D:
	var b := Burst.make(parent, at, z)
	var r := rng()
	for i in (int(count / 3.0) if calm else count):
		var x := r.randf_range(-width * 0.5, width * 0.5)
		b.add(RIBBON, Vector2(x, 0), Vector2(x * 1.6 + r.randf_range(-20.0, 20.0), -r.randf_range(60.0, 110.0)), 190.0,
			r.randf_range(0.6, 0.95), Color(RIBBON_COLORS[r.randi_range(0, RIBBON_COLORS.size() - 1)]))
	return b


## Plus-shaped twinkles scattered in `area` (local to `parent`), each living a moment.
static func sparkle(parent: Node, area: Rect2, count := 6, z := 60) -> Node2D:
	var b := Burst.make(parent, area.position, z)
	var r := rng()
	for i in (mini(count, 2) if calm else count):
		var p := Vector2(r.randf() * area.size.x, r.randf() * area.size.y)
		var part := b.add(SPARKLE, p, Vector2(0, -r.randf_range(4.0, 10.0)), 0.0, r.randf_range(0.35, 0.6), C_CREAM)
		part.age = -r.randf() * 0.25
	return b


## A warm ordered-dither flash over `rect` (local to `parent`): 50% then 25% of `color`, then gone (~0.2 s).
static func dither_flash(parent: Node, rect: Rect2, color := C_GOLD, z := 30) -> Node2D:
	var f := DitherFlash.new()
	f.rect = Rect2(rect.position.round(), rect.size.round())
	f.color = color
	f.z_index = z
	f.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(f)
	if calm:
		f.life = 0.08
	return f


## Plays sfx `id` (or its _01 variation) on the SFX bus at `semitones` up: rising notes (stars one by one).
## Its own short-lived player, so the shared Audio voices keep their random pitch.
static func sfx_pitched(owner: Node, id: String, semitones: float) -> void:
	var path := SFX_DIR + id + ".wav"
	if not ResourceLoader.exists(path):
		path = SFX_DIR + id + "_01.wav"
	if not ResourceLoader.exists(path) or owner == null or not owner.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	p.pitch_scale = pow(2.0, semitones / 12.0)
	owner.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Pixel particles integrated per frame and drawn on whole pixels; frees itself when the last one is gone.
class Burst extends Node2D:
	var parts: Array[Part] = []

	static func make(parent: Node, at: Vector2, z: int) -> Burst:
		var b := Burst.new()
		b.position = at.round()
		b.z_index = z
		parent.add_child(b)
		return b

	func add(kind: int, p: Vector2, v: Vector2, gravity: float, life: float, c: Color) -> Part:
		var part := Part.new()
		part.kind = kind
		part.p = p
		part.v = v
		part.g = gravity
		part.life = life
		part.c = c
		parts.append(part)
		return part

	func _process(dt: float) -> void:
		var alive := false
		for part in parts:
			part.age += dt
			if part.age < 0.0:
				alive = true
				continue
			part.v.y += part.g * dt
			if part.kind == RIBBON:
				part.v.x *= 1.0 - minf(1.0, dt * 3.0)  # paper slows down and drifts
				part.v.y = minf(part.v.y, 34.0)
			part.p += part.v * dt
			alive = alive or part.age < part.life
		queue_redraw()
		if not alive:
			queue_free()

	func _draw() -> void:
		for part in parts:
			if part.age < 0.0 or part.age >= part.life:
				continue
			var q := part.p.round()
			var k := part.age / part.life
			match part.kind:
				RIBBON:  # twirls: tall, edge-on, flat, edge-on...
					match int(part.age * 16.0) % 4:
						0:
							draw_rect(Rect2(q.x, q.y - 1, 2, 4), part.c)
						2:
							draw_rect(Rect2(q.x - 1, q.y, 4, 2), part.c)
						_:
							draw_rect(Rect2(q.x, q.y, 2, 2), part.c)
				SPARKLE:
					if int(part.age * 20.0) % 3 == 2:
						continue  # flicker
					var c := C_CREAM if k < 0.35 else (C_GOLD_HI if k < 0.7 else C_GOLD)
					var arm := 2 if k < 0.5 else 1
					draw_rect(Rect2(q.x - arm, q.y, arm * 2 + 1, 1), c)
					draw_rect(Rect2(q.x, q.y - arm, 1, arm * 2 + 1), c)
				DUST:
					var s := 2 if k < 0.5 else 1
					draw_rect(Rect2(q, Vector2(s, s)), part.c)
				_:
					draw_rect(Rect2(q, Vector2(2, 2)), part.c)


class Part extends RefCounted:
	var kind := DOT
	var p := Vector2.ZERO
	var v := Vector2.ZERO
	var g := 0.0
	var life := 0.5
	var age := 0.0
	var c := Color.WHITE


## Ordered 2x2 dither of one colour over a rect: half the pixels, then a quarter, then gone.
class DitherFlash extends Node2D:
	var rect := Rect2()
	var color := C_GOLD
	var life := 0.22
	var _age := 0.0
	var _half: ImageTexture
	var _quarter: ImageTexture

	func _ready() -> void:
		_half = _pattern([Vector2i(0, 0), Vector2i(1, 1)])
		_quarter = _pattern([Vector2i(0, 0)])

	func _pattern(on: Array) -> ImageTexture:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for p: Vector2i in on:
			img.set_pixelv(p, color)
		return ImageTexture.create_from_image(img)

	func _process(dt: float) -> void:
		_age += dt
		queue_redraw()
		if _age >= life:
			queue_free()

	func _draw() -> void:
		draw_texture_rect(_half if _age < life * 0.45 else _quarter, rect, true)
