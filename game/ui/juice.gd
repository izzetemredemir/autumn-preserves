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
static func sfx_pitched(owner: Node, id: String, semitones: float, volume_db := 0.0) -> void:
	var path := SFX_DIR + id + ".wav"
	if not ResourceLoader.exists(path):
		path = SFX_DIR + id + "_01.wav"
	if not ResourceLoader.exists(path) or owner == null or not owner.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	p.pitch_scale = pow(2.0, semitones / 12.0)
	p.volume_db = volume_db
	owner.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## FUN-MG · A small round puff of `colors` pixels out from `at` (flour, foam, steam): `count` 2 px specks that shrink.
static func puff(parent: Node, at: Vector2, colors: Array, count := 6, speed := 34.0, z := 45) -> Node2D:
	var b := Burst.make(parent, at, z)
	var r := rng()
	for i in (maxi(1, count / 3) if calm else count):
		var a := r.randf() * TAU
		var v := Vector2(cos(a), sin(a) * 0.7) * speed * r.randf_range(0.4, 1.0)
		b.add(DUST, Vector2.ZERO, v + Vector2(0, -8), 20.0, r.randf_range(0.25, 0.42), colors[i % colors.size()])
	return b


## FUN-MG · Juice droplets: `count` 2 px drops thrown from `at` with velocity `vel` (spread by `spread`) under gravity.
static func droplets(parent: Node, at: Vector2, vel: Vector2, colors: Array, count := 5, spread := 14.0,
		gravity := 260.0, life := 0.4, z := 45) -> Node2D:
	var b := Burst.make(parent, at, z)
	var r := rng()
	for i in (maxi(1, count / 3) if calm else count):
		var v := vel + Vector2(r.randf_range(-spread, spread), r.randf_range(-spread, spread) * 0.7)
		b.add(DOT, Vector2.ZERO, v, gravity, life * r.randf_range(0.8, 1.2), colors[i % colors.size()])
	return b


## FUN-MG · The sparkle burst for a 3-star result, with its chime.
static func star_burst(owner: Node2D, area: Rect2, z := 60) -> void:
	sparkle(owner, area, 14, z)
	sfx_pitched(owner, "sfx_sparkle", 0.0)


## FUN-MG · A streak counter ("x2", "x3"...) that pops on every hit past the first and plays a note one step higher
## each time; a break steps it down through palette greys and hides it (no sound, no harsh flash).
static func combo(parent: Node, pos: Vector2, z := 12) -> Combo:
	var c := Combo.new()
	c.position = (pos - c.size * 0.5).round()  # `pos` is the centre
	c.z_index = z
	parent.add_child(c)
	return c


const COMBO_NOTES := [0, 2, 4, 7, 9, 12]  ## semitones above the base note, a major pentatonic climb


class Combo extends Label:
	var count := 0
	var _fade: Tween

	func _init() -> void:
		size = Vector2(40, 22)
		var bg := StyleBoxFlat.new()  # a plum tab behind the number so it reads on any background
		bg.bg_color = C_SHADOW
		bg.border_color = C_GOLD
		bg.set_border_width_all(1)
		bg.content_margin_top = 1
		add_theme_stylebox_override("normal", bg)
		vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_theme_font_size_override("font_size", 18)
		add_theme_color_override("font_color", C_GOLD)
		visible = false

	## One more hit in a row.
	func hit(sound := true) -> void:
		count += 1
		if _fade != null:
			_fade.kill()
		if count < 2:
			return
		text = tr("MG_COMBO") % count
		add_theme_color_override("font_color", C_GOLD)
		visible = true
		Juice.pop(self, 1.6, 0.16)
		if sound:
			Juice.sfx_pitched(self, "sfx_star_pop", COMBO_NOTES[mini(count - 2, COMBO_NOTES.size() - 1)], -4.0)

	## The streak broke: fade out in steps through gold, stone and shadow.
	func broke() -> void:
		var shown := visible and count >= 2
		count = 0
		if not shown:
			return
		if _fade != null:
			_fade.kill()
		_fade = create_tween()
		for c: Color in [C_STONE, C_CREAM_LO, C_SHADOW]:
			_fade.tween_callback(add_theme_color_override.bind("font_color", c))
			_fade.tween_interval(0.16)
		_fade.tween_callback(set_visible.bind(false))


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
