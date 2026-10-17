extends RefCounted
## FIRST-60B · Three beats (valley, cottage, garden; the jar and snow beats stay as classes). FIRST-60 · The premise intro's timeline and its painted beats, made from the game's own art:
##   valley   the title painting at 2x, panning over the river and the hills (glints, birds, leaves)
##   cottage  the same painting at 2x, tilting up Granny's cottage to the chimney smoke
##   jar      the pantry at 2x: three of her jars on the shelf (JarIcon), one catching the light
##   snow     the far range at 2x: snow settles on the peaks and falls behind the hills, autumn leaves in front
##   garden   her garden at 1x as the garden scene draws it, Granny at the door, leaves falling
## Each beat dithers in over the one before (dither_mask.gdshader, no alpha) and pans in whole screen pixels.
## Everything is a function of the beat's local time, so the intro can seek (smoke shots, the UI audit).

const MASK := preload("res://ui/transition/dither_mask.gdshader")
const TITLE_ART := "res://assets/sprites/scenes/bg_title.png"
const PANTRY_ART := "res://assets/sprites/scenes/bg_pantry.png"
const GRANNY_IDLE := "res://assets/sprites/granny/granny_idle.png"
const COTTAGE := "res://assets/sprites/garden/garden_cottage.png"
const TREE_ART := "res://assets/sprites/forest/tree_%s_ripe.png"
const BACKDROP := "res://scenes/garden/garden_backdrop.gd"
const BG := Color("3d1f29")
const CREAM := Color("f2d9c5")
const CREAM_LO := Color("b9a697")
const GLASS := Color("b4b3a0")

## [id, line key, seconds on screen]. The first FADE seconds of a beat overlap the end of the one before.
const BEATS := [
	["valley", "PREMISE_1", 4.0],
	["cottage", "PREMISE_3", 4.2],
	["garden", "PREMISE_5", 3.8],
]
const FADE := 0.5


static func count() -> int:
	return BEATS.size()


static func start(i: int) -> float:
	var s := 0.0
	for k in clampi(i, 0, BEATS.size()):
		s += float(BEATS[k][2])
	return s


static func total() -> float:
	return start(BEATS.size())


## The beat whose line is showing at intro time `t` (the last one after the end).
static func index_at(t: float) -> int:
	for i in BEATS.size():
		if t < start(i + 1):
			return i
	return BEATS.size() - 1


## Whether beat `i` is drawn at `t`: from its start until the next beat has fully dithered in over it.
static func shown(i: int, t: float) -> bool:
	if t < start(i):
		return false
	return i == BEATS.size() - 1 or t < start(i + 1) + FADE


## Dither level (0..16) of beat `i` at `t`: it comes in over FADE seconds, the first one over the title.
static func level(i: int, t: float) -> int:
	return clampi(int(16.0 * (t - start(i)) / FADE), 0, 16)


static func make(i: int) -> Beat:
	var b: Beat
	match String(BEATS[i][0]):
		"valley":
			b = ArtBeat.new(TITLE_ART, Vector2i(400, 250), Vector2i(452, 206))
			b.fx = TitleFx.new(1601)
			b.fx.smoke = false
			b.fx.front = false
			b.fx.bird_y = 128
			b.fx_t0 = 9.0  # the flock is over the river while the beat runs
		"cottage":
			b = ArtBeat.new(TITLE_ART, Vector2i(8, 252), Vector2i(26, 150))
			b.fx = TitleFx.new(1602)
			b.fx.birds = false
			b.fx.glints = false
			b.fx.front = false
		"jar":
			b = JarBeat.new(PANTRY_ART, Vector2i(480, 40), Vector2i(462, 84))
		"snow":
			b = SnowBeat.new(TITLE_ART, Vector2i(340, 150), Vector2i(480, 176))
			b.fx = TitleFx.new(1604)
			b.fx.smoke = false
			b.fx.birds = false
			b.fx.motes = false
			b.fx.front = false
		_:
			b = GardenBeat.new()
	b.dur = float(BEATS[i][2])
	return b


## Base: a full-screen Control with its own dither mask; `at(local)` sets the moment and redraws.
class Beat:
	extends Control
	var dur := 4.0
	var t := 0.0
	var fx: TitleFx = null
	var fx_t0 := 0.0
	var _mat := ShaderMaterial.new()

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mat.shader = MASK
		material = _mat

	func set_level(l: int) -> void:
		_mat.set_shader_parameter("level", l)

	func at(local: float) -> void:
		t = local
		queue_redraw()

	## Children draw through the same mask.
	func adopt(n: CanvasItem) -> void:
		n.use_parent_material = true
		add_child(n)


## A painting drawn at 2x, its 480x270 window sliding from `pan_from` to `pan_to` (screen offsets into the zoomed art),
## eased in and out.
class ArtBeat:
	extends Beat
	const ZOOM := 2
	var art: Texture2D
	var pan_from := Vector2i.ZERO
	var pan_to := Vector2i.ZERO

	func _init(path: String, from: Vector2i, to: Vector2i) -> void:
		super()
		art = load(path) as Texture2D if ResourceLoader.exists(path) else null
		pan_from = from
		pan_to = to

	func origin() -> Vector2i:
		var k := smoothstep(0.0, 1.0, clampf(t / maxf(dur, 0.01), 0.0, 1.0))
		var o := Vector2(pan_from).lerp(Vector2(pan_to), k).round()
		if art != null:  # wider windows (aspect expand) never see past the painting
			var room := Vector2(art.get_size() * ZOOM) - size
			o = o.clamp(Vector2.ZERO, room.max(Vector2.ZERO))
		return -Vector2i(o)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BG)
		var o := origin()
		if art != null:
			draw_texture_rect(art, Rect2(o, art.get_size() * ZOOM), false)
		_paint(o)
		if fx != null:
			fx.draw_back(self, fx_t0 + t, o, ZOOM)

	func _paint(_o: Vector2i) -> void:
		pass


## The pantry shelf with three of her jars; the middle one catches the light twice.
class JarBeat:
	extends ArtBeat
	const SHELF_Y := 114  ## top of the middle shelf board in bg_pantry.png
	const JAR_X := [318, 350, 382]
	const SPARKLE := [1.1, 2.7]
	var _jars: Array[Texture2D] = []

	func _init(path: String, from: Vector2i, to: Vector2i) -> void:
		super(path, from, to)
		var vars := _varieties()
		for key in [_key("jam", "apple", vars), _key("pickle", "cucumber", vars), _key("fruit_butter", "pear", vars)]:
			if key == "":
				continue
			var img := JarIcon.render(ProductGen.describe(key, vars), "shelf")
			_jars.append(ImageTexture.create_from_image(img))

	static func _varieties() -> Dictionary:
		var tree := Engine.get_main_loop() as SceneTree
		var gs: Node = tree.root.get_node_or_null("GameState") if tree != null else null
		if gs != null and typeof(gs.get("data")) == TYPE_DICTIONARY:
			var v: Variant = (gs.get("data") as Dictionary).get("varieties")
			if typeof(v) == TYPE_DICTIONARY and not (v as Dictionary).is_empty():
				return v
		return VarietyGen.generate_all(1016, 0)

	## "<recipe>|<first variety of type>|-", or "" when the save has no such variety.
	static func _key(recipe: String, type: String, vars: Dictionary) -> String:
		var ids := vars.keys()
		ids.sort()
		for id in ids:
			if String((vars[id] as Dictionary).get("type", "")) == type:
				return "%s|%s|-" % [recipe, id]
		return ""

	func _paint(o: Vector2i) -> void:
		for i in _jars.size():
			var tex := _jars[i]
			var p := Vector2i(int(JAR_X[i]), SHELF_Y - tex.get_height())
			draw_texture_rect(tex, Rect2(o + p * ZOOM, tex.get_size() * ZOOM), false)
		if _jars.size() < 2:
			return
		for s in SPARKLE:
			var u := (t - float(s)) / 0.5
			if u < 0.0 or u > 1.0:
				continue
			var arm := 1 if u < 0.25 or u > 0.75 else 2
			var c := Vector2i(int(JAR_X[1]) + 7, SHELF_Y - _jars[1].get_height() + 9)
			_px(o, c, Vector2i.ONE, CREAM)
			_px(o, c + Vector2i(-arm, 0), Vector2i(arm, 1), CREAM_LO if arm == 1 else CREAM)
			_px(o, c + Vector2i(1, 0), Vector2i(arm, 1), CREAM_LO if arm == 1 else CREAM)
			_px(o, c + Vector2i(0, -arm), Vector2i(1, arm), CREAM_LO if arm == 1 else CREAM)
			_px(o, c + Vector2i(0, 1), Vector2i(1, arm), CREAM_LO if arm == 1 else CREAM)

	func _px(o: Vector2i, p: Vector2i, s: Vector2i, c: Color) -> void:
		draw_rect(Rect2(o + p * ZOOM, s * ZOOM), c)


## Snow beyond the hills: caps settle on the far peaks (deeper on the high ones) and flakes fall behind the ridge.
class SnowBeat:
	extends ArtBeat
	const FLAKES := 64
	const CAP_FROM := 0.5
	const CAP_SEC := 2.6
	const FLAKE_TOP := 64
	var _flakes: Array = []  ## [x, y0, speed, amp, phase, colour]

	func _init(path: String, from: Vector2i, to: Vector2i) -> void:
		super(path, from, to)
		var r := RandomNumberGenerator.new()
		r.seed = 1018
		for i in FLAKES:
			_flakes.append([r.randf_range(TitleFx.MOUNTAIN_X.x, TitleFx.MOUNTAIN_X.y), r.randf_range(0.0, 100.0),
				r.randf_range(5.0, 11.0), r.randf_range(0.5, 2.0), r.randf_range(0.0, TAU), CREAM if r.randf() < 0.7 else GLASS])

	func _paint(o: Vector2i) -> void:
		var ridge := TitleFx.ridge()
		var k := clampf((t - CAP_FROM) / CAP_SEC, 0.0, 1.0)
		for x in range(TitleFx.MOUNTAIN_X.x, TitleFx.MOUNTAIN_X.y):
			var top := ridge[x]
			if top < 0:
				continue
			var d := int(clampi(floori((152 - top) / 5.0) + 1, 0, 5) * k)
			if d > 1 and hash(x * 31) % 3 == 0:
				d -= 1
			if d <= 0:
				continue
			draw_rect(Rect2(o + Vector2i(x, top) * ZOOM, Vector2i(1, d) * ZOOM), CREAM)
			if d >= 3:
				draw_rect(Rect2(o + Vector2i(x, top + d - 1) * ZOOM, Vector2i(1, 1) * ZOOM), CREAM_LO)
		for f in _flakes:
			var x := floori(float(f[0]) + sin(t * 1.2 + float(f[4])) * float(f[3]))
			var y := FLAKE_TOP + floori(fposmod(float(f[1]) + float(f[2]) * t, 100.0))
			var xi := clampi(x, 0, ridge.size() - 1)
			if ridge[xi] >= 0 and y >= ridge[xi]:
				continue  # behind the hills
			draw_rect(Rect2(o + Vector2i(x, y) * ZOOM, Vector2i.ONE * ZOOM), f[5])


## Her garden at 1x, as the garden scene lays it out (garden_backdrop.gd, the cottage, two fruit trees and the
## walnut), Granny waiting at the door, leaves falling.
class GardenBeat:
	extends Beat
	const SPRITES := [[COTTAGE, Vector2i(153, -4)], ["apple", Vector2i(24, 48)], ["quince", Vector2i(24, 144)],
		["walnut", Vector2i(360, 176)]]
	const GRANNY_AT := Vector2i(215, 80)
	var _granny: Texture2D
	var _top: Node2D
	var _fx := TitleFx.new(1605, 22, 0, 0)

	func _init() -> void:
		super()
		_fx.smoke = false
		_fx.birds = false
		_fx.glints = false
		_fx.motes = false
		if ResourceLoader.exists(BACKDROP):
			adopt((load(BACKDROP) as GDScript).new() as Node2D)
		for s in SPRITES:
			var path := String(s[0])
			if not path.begins_with("res://"):
				path = TREE_ART % path
			if not ResourceLoader.exists(path):
				continue
			var sp := Sprite2D.new()
			sp.texture = load(path)
			sp.centered = false
			sp.position = Vector2(s[1])
			adopt(sp)
		_granny = load(GRANNY_IDLE) as Texture2D if ResourceLoader.exists(GRANNY_IDLE) else null
		_top = Node2D.new()
		_top.draw.connect(_draw_top)
		adopt(_top)

	func at(local: float) -> void:
		super(local)
		_top.queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BG)

	func _draw_top() -> void:
		if _granny != null:
			var f := int(t / 0.6) % 2
			_top.draw_texture_rect_region(_granny, Rect2(GRANNY_AT, Vector2(16, 32)), Rect2(f * 16, 0, 16, 32))
		_fx.draw_back(_top, t + 3.0)
