extends RefCounted
## ENDING · The visit's own beats (docs/story.md §6.1). The pantry rail, the letter paper, the credits book and the
## snow are the farewell's shots (scenes/farewell/farewell_shots.gd), used as they are; these add the people.
## Each beat is a full-screen Control in the 480x270 design space; the director (finale.gd) calls at(t) every frame
## with the seconds since the beat began, so any moment can be drawn again (seek, smoke shots). Whole pixels only.
##   KitchenBeat  morning kitchen: a knock at the door, Granny walks over to open it
##   GardenBeat   the garden: Nora (red scarf, travel bag), Mia and Leo come up from the gate; the children wave, then
##                Leo runs to his wooden train and Mia to her rag rabbit; the cat gets up from the doorstep.
##                With `snowing` it is the first snow over the same garden (SnowShot) and the one line
##   PantryBeat   the farewell's shelf pan with Mia and Leo in front of the shelves, looking up at the jars

const Shots := preload("res://scenes/farewell/farewell_shots.gd")
const Villager := preload("res://scenes/market/villager.gd")
const W := 480
const H := 270
const INK := Color("111010")
const CREAM := Color("f2d9c5")
const CREAM_LO := Color("b9a697")
const GOLD := Color("e5bd7f")
const TAN := Color("c58845")
const BROWN := Color("83571e")
const BARK := Color("50361e")
const RED := Color("a22512")
const PEACH := Color("e19064")
const NIGHT := Color("23282a")
const GRANNY_KITCHEN := "res://assets/sprites/granny/granny_kitchen.png"
const GRANNY_IDLE := "res://assets/sprites/granny/granny_idle.png"
const CAT_SLEEP := "res://assets/sprites/cat/cat_sleep.png"
const CAT_IDLE := "res://assets/sprites/cat/cat_idle.png"


## Base of the beats: full screen, ignores the mouse (the director reads input), and the shared helpers.
class Beat:
	extends Control

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Nora, the grandchildren's mother: an adult villager in a grey-teal winter coat with a red scarf and a travel bag.
	## Built from the villager part sheets with palette ramps only (no new art).
	static func nora_look() -> Dictionary:
		return {"arch": "woman", "fem": true, "skirt": false, "hair": "long", "hat": "none", "glasses": false,
			"beard": false, "moustache": false, "scarf": true, "carry": "bag", "cane": false, "umbrella": false, "outfit": "",
			"colors": {"skin": ["e19064", "e5bd7f", "f2d9c5", "c94d2e"], "hair": ["3d1f29", "50361e", "83571e"],
				"coat": ["2e3f3f", "415c5d", "567c7d"], "lower": ["23282a", "49423d", "81746a"], "shoes": ["3d1f29", "50361e"],
				"accent": ["62272c", "a22512", "c94d2e"], "hat": ["62272c", "a22512", "c94d2e"], "shirt": ["b9a697", "f2d9c5"]}}


	static func look_of(id: String) -> Dictionary:
		return nora_look() if id == "nora" else Grandkid.look_of(id)


	static func tex(path: String) -> Texture2D:
		return load(path) as Texture2D if ResourceLoader.exists(path) else null


	## A sprite showing one frame of a horizontal strip; `feet` is the bottom centre.
	static func strip_sprite(path: String, frame_w: int) -> Sprite2D:
		var s := Sprite2D.new()
		s.texture = tex(path)
		s.centered = false
		s.region_enabled = true
		s.region_rect = Rect2(0, 0, frame_w, s.texture.get_height() if s.texture != null else 0)
		return s


	static func set_frame(s: Sprite2D, path: String, frame: int, feet: Vector2) -> void:
		if s.texture == null or s.texture.resource_path != path:
			s.texture = tex(path)
		if s.texture == null:
			return
		var fw := int(s.region_rect.size.x)
		var n := maxi(s.texture.get_width() / maxi(fw, 1), 1)
		var fh := s.texture.get_height()
		s.region_rect = Rect2((frame % n) * fw, 0, fw, fh)
		s.position = (feet - Vector2(fw / 2, fh)).floor()


	## Piecewise-linear track [[t, Vector2], ...]: {"pos", "dir"} (dir is zero while standing).
	static func track(keys: Array, t: float) -> Dictionary:
		if t <= float(keys[0][0]):
			return {"pos": keys[0][1], "dir": Vector2.ZERO}
		for i in range(1, keys.size()):
			var b: Array = keys[i]
			if t <= float(b[0]):
				var a: Array = keys[i - 1]
				var k := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
				var from: Vector2 = a[1]
				var to: Vector2 = b[1]
				return {"pos": from.lerp(to, k), "dir": to - from}
		return {"pos": keys[-1][1], "dir": Vector2.ZERO}


	static func view_of(dir: Vector2) -> String:
		if absf(dir.x) > absf(dir.y):
			return "right" if dir.x > 0 else "left"
		return "front" if dir.y > 0 else "back"


	static func bubble(text: String) -> PanelContainer:
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(Shots.Shot.make_label(text))
		return p


# ---------------------------------------------------------------- 1. the knock

class KitchenBeat:
	extends Beat
	const DURATION := 8.0
	const KNOCK_AT := 1.2
	const KNOCK_UNTIL := 4.2
	const WALK_FROM := 2.6
	const WALK_TO := 6.6
	const GRANNY_SIZE := Vector2i(44, 88)
	const START := Vector2(72, 96)  ## top-left, by the stove (as in the kitchen)
	const END := Vector2(366, 108)  ## by the door
	const STEP_SEC := 0.28
	var _bg: Texture2D
	var _granny: Texture2D
	var _pos := START
	var _frame := 0
	var _knock: PanelContainer

	func setup(knock_text: String) -> void:
		_bg = tex(Shots.KITCHEN_BG)
		_granny = tex(GRANNY_KITCHEN)
		_knock = bubble(knock_text)
		_knock.position = Vector2(352, 40)
		add_child(_knock)
		at(0.0)

	func duration() -> float:
		return DURATION

	func at(t: float) -> void:
		var k := clampf((t - WALK_FROM) / (WALK_TO - WALK_FROM), 0.0, 1.0)
		var walking := k > 0.0 and k < 1.0
		var lift := 1 if walking and int(t / STEP_SEC) % 2 == 0 else 0
		_pos = (START.lerp(END, k) - Vector2(0, lift)).floor()
		_frame = 1 if fposmod(t, 3.1) > 2.95 else 0  # a blink now and then
		_knock.visible = t >= KNOCK_AT and t < KNOCK_UNTIL
		queue_redraw()

	func _draw() -> void:
		if _bg != null:
			draw_texture(_bg, Vector2.ZERO)
		else:
			draw_rect(Rect2(0, 0, W, H), BARK)
		if _granny != null:
			draw_texture_rect_region(_granny, Rect2(_pos, Vector2(GRANNY_SIZE)),
				Rect2(_frame * GRANNY_SIZE.x, 0, GRANNY_SIZE.x, GRANNY_SIZE.y))


# ---------------------------------------------------------------- 2./3. the garden, then the first snow

class GardenBeat:
	extends Beat
	const DURATION := 10.0
	const SNOW_DURATION := 10.0
	const GRANNY_AT := Vector2(222, 104)
	const CAT_AT := Vector2(254, 104)
	const CAT_UP := 7.0
	const TRAIN_AT := Vector2(132, 134)
	const RABBIT_AT := Vector2(330, 132)
	const WAVE := [5.3, 6.7]
	## Feet tracks [[t, pos]]: up the path from the gate, a stop below Granny, then the children run to their toys.
	const TRACKS := {
		"nora": [[0.3, Vector2(234, 300)], [5.2, Vector2(236, 160)]],
		"leo": [[0.8, Vector2(208, 318)], [5.3, Vector2(206, 152)], [6.8, Vector2(206, 152)], [8.4, Vector2(146, 136)]],
		"mia": [[0.5, Vector2(262, 312)], [5.1, Vector2(264, 152)], [6.9, Vector2(264, 152)], [8.6, Vector2(318, 134)]],
	}
	const WALK_FPS := 8.0
	var snowing := false
	var _snow: Shots.SnowShot
	var _granny: Sprite2D
	var _cat: Sprite2D
	var _figs := {}

	## `line`: the snow's one sentence (snowing only).
	func setup(p_snowing: bool, line: String) -> void:
		snowing = p_snowing
		_snow = Shots.SnowShot.new()
		_snow.setup(line)
		add_child(_snow)
		var garden: Node2D = _snow.get_child(0)  # backdrop and garden sprites: the people stand in it, under the snow
		var toys := Node2D.new()
		toys.draw.connect(_draw_toys.bind(toys))
		garden.add_child(toys)
		_granny = strip_sprite(GRANNY_IDLE, 16)
		garden.add_child(_granny)
		_cat = strip_sprite(CAT_SLEEP, 24)
		garden.add_child(_cat)
		for id in ["nora", "leo", "mia"]:
			var v: Villager = Villager.new()
			garden.add_child(v)
			v.setup(look_of(String(id)))
			_figs[id] = v
		if snowing:
			_soften_snow()
		else:
			_snow._fx.visible = false
			_snow._line_box.visible = false
		at(0.0)

	## Swaps the SnowShot's cover for LawnSnow: the same flakes and ledges on the roof, trees and fence, but soft
	## patches and speckles on the lawn instead of straight lines along the path and road edges; none on the people.
	func _soften_snow() -> void:
		var old: Shots.SnowFx = _snow._fx
		var fx := LawnSnow.new()
		var out: Array[Rect2i] = [Rect2i(Vector2i(GRANNY_AT) + Vector2i(-10, -34), Vector2i(20, 36)),
			Rect2i(Vector2i(CAT_AT) + Vector2i(-13, -25), Vector2i(26, 26)),
			Rect2i(Vector2i(TRAIN_AT) + Vector2i(-10, -14), Vector2i(18, 16)),
			Rect2i(Vector2i(RABBIT_AT) + Vector2i(-6, -19), Vector2i(12, 20))]
		for id in TRACKS:
			var feet := Vector2i(TRACKS[id][-1][1])
			out.append(Rect2i(feet + Vector2i(-12, -50), Vector2i(24, 52)))
		fx.keep_out = out
		var ledges: Array = []
		for sp in Shots.GARDEN_SPRITES:
			var path := String(sp[0])
			var t := tex(path if path.begins_with("res://") else Shots.TREE_ART % path)
			if t != null:
				ledges.append([t, sp[1]])
		fx.add_sprites(ledges)
		_snow.add_child(fx)
		_snow.move_child(fx, old.get_index())
		_snow._fx = fx
		old.free()

	func duration() -> float:
		return SNOW_DURATION if snowing else DURATION

	func at(t: float) -> void:
		set_frame(_granny, GRANNY_IDLE, int(t * 2.0), GRANNY_AT)
		if snowing:
			_snow.at(t)
			set_frame(_cat, CAT_IDLE, int(t * 3.0), CAT_AT)
			for id in _figs:
				var keys: Array = TRACKS[id]
				var v: Villager = _figs[id]
				v.position = (keys[-1][1] as Vector2).floor()
				v.show_pose("front", "idle", int(t * 2.0))
			return
		if t < CAT_UP:
			set_frame(_cat, CAT_SLEEP, int(t * 0.8), CAT_AT)
		else:
			set_frame(_cat, CAT_IDLE, int((t - CAT_UP) * 3.0), CAT_AT)
		for id in _figs:
			var v: Villager = _figs[id]
			var tr_at := track(TRACKS[id], t)
			var dir: Vector2 = tr_at.dir
			var lift := 0
			if dir != Vector2.ZERO:
				v.show_pose(view_of(dir), "walk", int(t * WALK_FPS))
			elif id != "nora" and t >= float(WAVE[0]) and t < float(WAVE[1]):
				var f := int(t * 5.0) % 2
				lift = 3 if f == 0 else 0
				v.show_pose("front", "talk" if f == 0 else "idle", 0)
			else:
				v.show_pose("front", "idle", int(t * 2.0))
			v.position = ((tr_at.pos as Vector2) - Vector2(0, lift)).floor()

	## A wooden toy train (Leo's) and a rag rabbit (Mia's), left on the lawn since the summer.
	func _draw_toys(n: Node2D) -> void:
		for ink in [true, false]:
			var p := TRAIN_AT
			_r(n, ink, p.x - 8, p.y - 7, 12, 5, TAN)
			_r(n, ink, p.x + 1, p.y - 12, 5, 5, RED)
			_r(n, ink, p.x - 7, p.y - 10, 2, 3, NIGHT)
			for wx in [-7, -2, 3]:
				_r(n, ink, p.x + wx, p.y - 2, 3, 2, NIGHT)
			if not ink:
				n.draw_rect(Rect2(p.x - 8, p.y - 7, 12, 1), GOLD)
				n.draw_rect(Rect2(p.x + 2, p.y - 11, 3, 2), GOLD)
			var q := RABBIT_AT
			_r(n, ink, q.x - 4, q.y - 7, 8, 7, CREAM_LO)
			_r(n, ink, q.x - 3, q.y - 12, 6, 5, CREAM)
			_r(n, ink, q.x - 3, q.y - 17, 2, 5, CREAM)
			_r(n, ink, q.x + 1, q.y - 17, 2, 5, CREAM)
			if not ink:
				n.draw_rect(Rect2(q.x - 3, q.y - 6, 6, 4), CREAM)
				n.draw_rect(Rect2(q.x - 3, q.y - 16, 1, 3), PEACH)
				n.draw_rect(Rect2(q.x + 2, q.y - 16, 1, 3), PEACH)
				n.draw_rect(Rect2(q.x - 2, q.y - 10, 1, 1), INK)
				n.draw_rect(Rect2(q.x + 1, q.y - 10, 1, 1), INK)
				n.draw_rect(Rect2(q.x - 4, q.y - 8, 8, 1), RED)  # a red ribbon

	## One rect, or its one-pixel ink outline under it (the outline pass draws first).
	func _r(n: Node2D, ink: bool, x: float, y: float, w: int, h: int, c: Color) -> void:
		if ink:
			n.draw_rect(Rect2(x - 1, y - 1, w + 2, h + 2), INK)
		else:
			n.draw_rect(Rect2(x, y, w, h), c)


# ---------------------------------------------------------------- 4. the pantry

class PantryBeat:
	extends Beat
	const PAN_SEC := 7.0
	const KID_SCALE := 2
	const KIDS := {"mia": Vector2(60, 274), "leo": Vector2(420, 274)}
	var pantry: Shots.PantryShot
	var _figs := {}

	func setup(jars: Array, varieties: Dictionary, empty_text: String) -> void:
		pantry = Shots.PantryShot.new()
		pantry.setup(jars, varieties, empty_text)
		pantry._speed = maxf(Shots.PantryShot.MIN_SPEED, pantry.max_offset() / PAN_SEC)  # a shorter rail than the farewell's
		add_child(pantry)
		for id in KIDS:
			var v: Villager = Villager.new()
			add_child(v)
			v.setup(look_of(String(id)))
			v.scale = Vector2(KID_SCALE, KID_SCALE)
			v.position = KIDS[id]
			_figs[id] = v
		at(0.0)

	func duration() -> float:
		return pantry.duration()

	func at(t: float) -> void:
		pantry.at(t)
		for id in _figs:
			var v: Villager = _figs[id]
			# looking up at the shelf, turning to each other now and then
			var turn := fposmod(t + (0.0 if id == "mia" else 2.0), 5.0) > 4.0
			v.show_pose(("right" if id == "mia" else "left") if turn else "back", "idle", int(t * 2.0))


## The finale's first snow (coordinator review): like the farewell's SnowFx, but the lawn gets soft patches and
## loose speckles (deterministic, a visual-only generator) instead of dashed lines along the path and road edges.
## Ledges stay on the cottage roof, the trees and the fence. `keep_out`: rects where the people stand.
class LawnSnow:
	extends "res://scenes/farewell/farewell_shots.gd".SnowFx
	const LAWN_TOP := 34  ## below the hedge
	const LAWN_BOTTOM := 250  ## above the fence
	const HOUSE := Rect2i(156, 0, 136, 98)
	const PATCHES := 46
	const SPECKLES := 520
	const COTTAGE_PATH := "res://assets/sprites/garden/garden_cottage.png"
	const ROOF := Rect2i(156, 0, 136, 54)  ## the roof part of the cottage sprite on screen
	const ROOF_PATCHES := 9
	const ROOF_SPECKLES := 220
	var keep_out: Array[Rect2i] = []

	func add_sprites(sprites: Array) -> void:
		var roof_img: Image = null
		var roof_at := Vector2i.ZERO
		for sp in sprites:
			var t: Texture2D = sp[0]
			if t != null:
				_ledges_of(t.get_image(), Vector2i(sp[1]))
				if t.resource_path == COTTAGE_PATH:
					roof_img = t.get_image()
					roof_at = Vector2i(sp[1])
		var fence: Texture2D = load(FENCE) if ResourceLoader.exists(FENCE) else null
		if fence != null:
			var img: Image = fence.get_image().get_region(Rect2i(0, 0, LAYOUT.TILE, LAYOUT.TILE))
			for x in range(1, LAYOUT.W - 1):
				if not LAYOUT.is_gate(Vector2i(x, LAYOUT.H - 1)):
					_ledges_of(img, Vector2i(x * LAYOUT.TILE, (LAYOUT.H - 1) * LAYOUT.TILE))
		var r := RandomNumberGenerator.new()
		r.seed = 3010
		for i in PATCHES:
			var c := Vector2i(r.randi_range(6, W - 6), r.randi_range(LAWN_TOP, LAWN_BOTTOM))
			var rx := r.randi_range(4, 11)
			var ry := maxi(roundi(rx * 0.45), 2)
			for y in range(-ry, ry + 1):
				for x in range(-rx, rx + 1):
					var d := pow(float(x) / rx, 2.0) + pow(float(y) / ry, 2.0)
					if d > 1.0 or (d > 0.55 and r.randf() < 0.45):
						continue
					_lawn(c.x + x, c.y + y, 0 if d < 0.3 else (1 if d < 0.7 else 2))
		for i in SPECKLES:
			_lawn(r.randi_range(0, W - 1), r.randi_range(LAWN_TOP, LAWN_BOTTOM), 1 if r.randf() < 0.7 else 2)
		if roof_img != null:  # soft drifts and speckles on the roof tiles (opaque pixels of the cottage only)
			var on_roof := func(x: int, y: int) -> bool:
				var q := Vector2i(x, y) - roof_at
				return ROOF.has_point(Vector2i(x, y)) and q.x >= 0 and q.y >= 0 and q.x < roof_img.get_width() \
					and q.y < roof_img.get_height() and roof_img.get_pixel(q.x, q.y).a > 0.5
			for i in ROOF_PATCHES:
				var c := Vector2i(r.randi_range(ROOF.position.x + 8, ROOF.end.x - 8), r.randi_range(10, ROOF.end.y - 6))
				var rx := r.randi_range(4, 9)
				for y in range(-2, 3):
					for x in range(-rx, rx + 1):
						var d := pow(float(x) / rx, 2.0) + pow(y / 2.5, 2.0)
						if d <= 1.0 and not (d > 0.5 and r.randf() < 0.5) and on_roof.call(c.x + x, c.y + y):
							_put(c.x + x, c.y + y, 0 if d < 0.4 else 1)
			for i in ROOF_SPECKLES:
				var x := r.randi_range(ROOF.position.x, ROOF.end.x - 1)
				var y := r.randi_range(ROOF.position.y, ROOF.end.y - 1)
				if on_roof.call(x, y):
					_put(x, y, 1)

	func _lawn(x: int, y: int, depth: int) -> void:
		var p := Vector2i(x, y)
		if HOUSE.has_point(p):
			return
		for k in keep_out:
			if k.has_point(p):
				return
		_put(x, y, depth)
