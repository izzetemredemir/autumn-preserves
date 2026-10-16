class_name GardenSpot
extends Node2D
## One thing in the garden (GD-GARDEN, ART-GARDEN): "house" | "door" | "tree" | "bed" | "compost" | "mailbox" |
## "gate" | "gate_sign" | "town_sign". Position is the feet (bottom-centre of its cells) so the y-sorted object layer
## orders it against Granny. Art: fruit trees use tree_<type>_ripe/_bare (the bare apple tree stands in for others,
## with their fruit drawn on); everything else comes from assets/sprites/garden/ (art-bible §3.6): the cottage front
## (the door is part of it), plank beds with crop growth stages, compost bin, mailbox, gate, sign posts with a
## 9-slice board. No rules here: the scene passes the state in.
## `highlighted`: Granny faces it. `glow`: Granny's To-Do points here (outline or frame blinking + bobbing arrow).

const TILE := 16
## Approved tree sprites, first match wins: tree_<type>_ripe.png / tree_<type>_bare.png (art-bible §3.6).
const TREE_DIRS := ["res://assets/sprites/forest/", "res://assets/sprites/world/"]
const CANDIDATE_TREE := "res://assets/sprites/forest/candidates/tree_apple_%s.png"
const CROP_SHEET := "res://assets/sprites/garden/garden_crop_%s.png"
const OUTLINE := preload("res://shaders/outline_highlight.gdshader")
const COTTAGE := preload("res://assets/sprites/garden/garden_cottage.png")
const BED := preload("res://assets/sprites/garden/garden_bed.png")  ## 32x18: plain, fertilized
const COMPOST := preload("res://assets/sprites/garden/garden_compost.png")  ## 20x22: low, full
const MAILBOX := preload("res://assets/sprites/garden/garden_mailbox.png")  ## 16x26: flag down, up gold, up red
const GATE := preload("res://assets/sprites/garden/garden_gate.png")  ## 46x42: closed, open
const SIGN := preload("res://assets/sprites/garden/garden_sign.png")  ## post, 9-slice board, arrow tip
const SACK := preload("res://assets/sprites/garden/garden_sack.png")
## Sprite-sheet kinds: [texture, frames, top-left of the frame relative to the feet]. They get the outline shader.
const SHEETS := {
	"house": [COTTAGE, 1, Vector2(-71, -100)],
	"compost": [COMPOST, 2, Vector2(-10, -21)],
	"mailbox": [MAILBOX, 3, Vector2(-8, -25)],
	"gate": [GATE, 2, Vector2(-23, -41)],
}
## Crop sheets: 11x14 frames seed, sprout, half, ready, fruit-only (recoloured for a variety's colour shift).
const CROP_FRAME := Vector2i(11, 14)
const F_SEED := 0
const F_SPROUT := 1
const F_HALF := 2
const F_READY := 3
const F_FRUIT := 4
const PLANT_X := [-9, 0, 9]
const PLANT_TOP := -22  ## crop frame top in bed space: its soil mound sits on the bed's soil
const SIGN_POST := 12
const POST_SRC := Rect2(0, 0, 4, 14)
const BOARD_SRC := Rect2(12, 0, 12, 12)
const TIP_SRC := Rect2(24, 0, 6, 11)

const C_INK := Color("111010")
const C_CREAM := Color("f2d9c5")
const C_GOLD := Color("e5bd7f")
const C_GOLD_LIGHT := Color("dbcc83")
const C_RED := Color("c94d2e")
## Fruit spots on the stand-in canopy, sprite coordinates relative to the feet.
const FRUIT_SPOTS := [Vector2(-18, -62), Vector2(-6, -70), Vector2(8, -64), Vector2(18, -54), Vector2(-12, -48),
	Vector2(2, -54), Vector2(14, -42), Vector2(-22, -40)]

## Recoloured fruit frames, "<crop>:<shift>" -> Texture2D.
static var _fruit_cache := {}

var kind := ""
var index := -1
var cells: Array[Vector2i] = []
var color := Color("c94d2e")  ## fruit or crop colour
var highlighted := false:
	set(v):
		if v != highlighted:
			highlighted = v
			_restyle()
var glow := false:
	set(v):
		if v != glow:
			glow = v
			_t = 0.0
			_restyle()

# tree
var tree_type := ""
var fruit := true
var refill_in := 0
# bed
var crop := ""
var days_left := 0
var grow_days := 1
var fertilized := false
# compost bin
var compost := 0
var compost_per := 5
var fertilizer := 0
# mailbox
var unread := 0
# gate
var open := false

var _sprite: Sprite2D
var _ripe: Texture2D
var _bare: Texture2D
var _crop_tex: Texture2D
var _fruit_tex: Texture2D
var _label: Label
var _board: NinePatchRect
var _t := 0.0
var _blink_on := true
var _bob := 0


func setup(p_kind: String, p_index: int, p_cells: Array) -> void:
	kind = p_kind
	index = p_index
	cells.assign(p_cells)
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	position = Vector2((lo.x + hi.x + 1) * TILE * 0.5, (hi.y + 1) * TILE)
	if SHEETS.has(kind):
		var s: Array = SHEETS[kind]
		_make_sprite(s[0], int(s[1]), s[2])
		_update_frame()
	set_process(false)
	queue_redraw()


## Trees and the things standing on the grass block Granny; the door is in the cottage, the gate is walked through.
func blocks() -> bool:
	return kind in ["tree", "bed", "compost", "mailbox", "gate_sign", "town_sign"]


func usable() -> bool:
	return kind != "house"


## Click/tap area in world px (at least 16x16, tech-spec §7).
func hit_rect() -> Rect2:
	var r := _local_rect()
	return Rect2(position + r.position, r.size)


## World point just above the thing, for bubbles.
func top() -> Vector2:
	var r := hit_rect()
	return Vector2(r.position.x + r.size.x * 0.5, r.position.y)


## Where shaken fruit starts falling.
func canopy() -> Vector2:
	return position + Vector2(0, -floorf(_bare.get_height() * 0.65) if _bare != null else -28.0)


func set_tree(type: String, has_fruit: bool, refill: int, c: Color) -> void:
	if type != tree_type:
		tree_type = type
		_load_tree_art()
	fruit = has_fruit
	refill_in = refill
	color = c
	if _sprite != null:
		_sprite.texture = _ripe if fruit and _ripe != null else _bare
	queue_redraw()


func set_bed(p_crop: String, p_days_left: int, p_grow_days: int, p_fertilized: bool, c: Color) -> void:
	if p_crop != crop or c != color:
		_crop_tex = _tex(CROP_SHEET % p_crop) if p_crop != "" else null
		_fruit_tex = _fruit_frame(p_crop, c) if _crop_tex != null else null
	crop = p_crop
	days_left = p_days_left
	grow_days = maxi(1, p_grow_days)
	fertilized = p_fertilized
	color = c
	_restyle()


func is_ready() -> bool:
	return kind == "bed" and crop != "" and days_left <= 0


func set_compost(p_compost: int, per: int, p_fertilizer: int) -> void:
	compost = p_compost
	compost_per = maxi(1, per)
	fertilizer = p_fertilizer
	_update_frame()
	queue_redraw()


func set_mail(p_unread: int) -> void:
	if p_unread != unread:
		unread = p_unread
		_restyle()


## Gate leaves swing open while Granny is near (the scene decides), closed otherwise.
func set_open(p_open: bool) -> void:
	if p_open != open:
		open = p_open
		_update_frame()


## Sign text (already translated) on a plank board. Call once the spot is in the tree so the theme font is known.
func set_label(text: String) -> void:
	if _label == null:
		_board = NinePatchRect.new()
		_board.texture = SIGN
		_board.region_rect = BOARD_SRC
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			_board.set_patch_margin(side, 3)
		_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_board)
		_label = Label.new()
		_label.theme_type_variation = &"PaperLabel"
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
	_label.text = text
	_label.reset_size()
	var sz := _label.size
	var x := -floori(sz.x * 0.5) + (-3 if kind == "town_sign" else 0)
	_label.position = Vector2(x, -SIGN_POST - 3 - floori(sz.y))
	var b := _board_rect().grow(1)
	_board.position = b.position
	_board.size = b.size
	queue_redraw()


func pop() -> void:
	scale = Vector2(1.15, 0.88)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Whole-pixel wiggle for "can't do that".
func nudge() -> void:
	var x := position.x
	var t := create_tween()
	for dx in [2, -2, 1, 0]:
		t.tween_property(self, "position:x", x + dx, 0.04)


func _process(delta: float) -> void:
	_t += delta
	var on := fmod(_t, 0.8) < 0.5
	var bob := int(_t * 2.5) % 2
	if on != _blink_on or bob != _bob:
		_blink_on = on
		_bob = bob
		_update_outline()
		_update_frame()
		queue_redraw()


func _restyle() -> void:
	set_process(glow or is_ready() or unread > 0)
	_blink_on = true
	_update_outline()
	_update_frame()
	queue_redraw()


func _outlined() -> bool:
	return _sprite != null and kind != "house"


func _update_outline() -> void:
	if not _outlined():
		return
	var mat := _sprite.material as ShaderMaterial
	mat.set_shader_parameter("enabled", highlighted or (glow and _blink_on))
	mat.set_shader_parameter("outline_color", C_CREAM if glow and not highlighted else C_GOLD)


## Sheet frame for the state: compost low/full, mailbox flag (blinking while letters wait), gate closed/open.
func _update_frame() -> void:
	if _sprite == null or _sprite.hframes < 2:
		return
	match kind:
		"compost":
			_sprite.frame = 1 if compost * 2 >= compost_per else 0
		"mailbox":
			_sprite.frame = 0 if unread <= 0 else (1 if _blink_on else 2)
		"gate":
			_sprite.frame = 1 if open else 0


func _make_sprite(tex: Texture2D, frames: int, offset: Vector2) -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.hframes = frames
	_sprite.centered = false
	_sprite.position = offset
	_sprite.show_behind_parent = true  # frames, sacks and crops draw over it
	if kind != "house":
		var mat := ShaderMaterial.new()
		mat.shader = OUTLINE
		_sprite.material = mat
	add_child(_sprite)


func _load_tree_art() -> void:
	_ripe = null
	_bare = null
	for dir in TREE_DIRS:
		var bare := _tex("%stree_%s_bare.png" % [dir, tree_type])
		if bare != null:
			_bare = bare
			_ripe = _tex("%stree_%s_ripe.png" % [dir, tree_type])
			break
	if _bare == null:
		_bare = _tex(CANDIDATE_TREE % "bare")  # stand-in trunk and leaves for every tree type
		_ripe = _tex(CANDIDATE_TREE % "ripe") if tree_type == "apple" else null
	if _bare == null:
		if _sprite != null:
			_sprite.queue_free()
			_sprite = null
		return
	if _sprite == null:
		_make_sprite(_bare, 1, Vector2.ZERO)
	var sz := _bare.get_size()
	_sprite.position = Vector2(-floori(sz.x * 0.5), -sz.y)
	_update_outline()


static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## The crop sheet's fruit-only frame moved along the ingredient ramp to `c` (a variety's colour shift), or null
## when the default colours already match. Pixels keep to the palette: every ramp tone is a palette colour.
func _fruit_frame(p_crop: String, c: Color) -> Texture2D:
	var ramp: Array = Data.ingredients().get(p_crop, {}).get("ramp", [])
	var mid := ramp.find(c.to_html(false))
	if ramp.size() < 5 or mid < 0 or mid == 2:
		return null
	var shift := mid - 2
	var key := "%s:%d" % [p_crop, shift]
	if not _fruit_cache.has(key):
		var src := _crop_tex.get_image()
		src.convert(Image.FORMAT_RGBA8)
		var img := src.get_region(Rect2i(F_FRUIT * CROP_FRAME.x, 0, CROP_FRAME.x, CROP_FRAME.y))
		var map := {}
		for i in ramp.size():
			map[String(ramp[i])] = Color(String(ramp[clampi(i + shift, 0, ramp.size() - 1)]))
		for y in img.get_height():
			for x in img.get_width():
				var px := img.get_pixel(x, y)
				var hex := px.to_html(false)
				if px.a > 0.5 and map.has(hex):
					img.set_pixel(x, y, map[hex])
		_fruit_cache[key] = ImageTexture.create_from_image(img)
	return _fruit_cache[key]


func _local_rect() -> Rect2:
	match kind:
		"house":
			return Rect2(-71, -98, 144, 108)
		"door":
			return Rect2(-12, -29, 24, 29)
		"tree":
			return Rect2(-24, -72, 48, 72)
		"bed":
			return Rect2(-16, -24, 32, 24)
		"compost":
			return Rect2(-9, -20, 18, 20)
		"mailbox":
			return Rect2(-7, -22, 15, 22)
		"gate":
			return Rect2(-22, -40, 44, 40)
		"gate_sign", "town_sign":
			var r := Rect2(-8, -SIGN_POST - 4, 16, SIGN_POST + 4)
			if _label != null:
				r = r.merge(_board_rect())
			return r
	return Rect2(-8, -16, 16, 16)


func _board_rect() -> Rect2:
	var r := Rect2(_label.position, _label.size)
	return Rect2(r.position.x - 3, r.position.y + 1, r.size.x + 6, r.size.y + 1)


func _draw() -> void:
	match kind:
		"tree":
			_draw_tree()
		"bed":
			_draw_bed()
		"compost":
			for i in mini(fertilizer, 3):  # sacks of fertilizer leaning on the bin
				draw_texture(SACK, Vector2(8 + i * 5, -9))
		"gate_sign", "town_sign":
			_draw_sign()
	if not _outlined() and kind != "house":
		if highlighted or (glow and _blink_on):
			_frame(_local_rect(), C_GOLD if highlighted else C_CREAM)
	if glow:
		var top_y := _local_rect().position.y
		if _sprite != null:
			top_y = minf(top_y, _sprite.position.y)
		_arrow(Vector2(0, top_y - 2 - _bob))


func _draw_tree() -> void:
	if _sprite == null or not fruit or _ripe != null:
		return
	for p in FRUIT_SPOTS:  # stand-in bare tree: fruit dots in the fruit colour
		draw_rect(Rect2(p, Vector2(4, 4)), C_INK)
		draw_rect(Rect2(p, Vector2(3, 3)), color)
		draw_rect(Rect2(p, Vector2(1, 1)), C_CREAM)


func _draw_bed() -> void:
	draw_texture_rect_region(BED, Rect2(-16, -18, 32, 18), Rect2(32 if fertilized else 0, 0, 32, 18))
	if crop == "":
		return
	var tex := _crop_tex if _crop_tex != null else _tex(CROP_SHEET % "cucumber")  # stand-in plant for crops without art
	var grown := float(grow_days - days_left) / float(grow_days)
	var f := F_READY
	if days_left > 0:
		f = F_SEED if grown <= 0.0 else (F_SPROUT if grown < 0.5 else F_HALF)
	elif _crop_tex == null:
		f = F_HALF
	for i in PLANT_X.size():
		var at := Vector2(PLANT_X[i] - floori(CROP_FRAME.x * 0.5), PLANT_TOP)
		_crop(tex, f, at, i == 1)
		if f == F_READY and _fruit_tex != null:
			_crop(_fruit_tex, 0, at, i == 1)
		elif days_left <= 0 and _crop_tex == null:
			draw_rect(Rect2(at + Vector2(6, 7), Vector2(3, 4)), C_INK)
			draw_rect(Rect2(at + Vector2(6, 7), Vector2(2, 3)), color)
	if days_left <= 0 and _blink_on:  # ready: a small twinkle
		draw_rect(Rect2(12, -25, 1, 3), C_GOLD_LIGHT)
		draw_rect(Rect2(11, -24, 3, 1), C_GOLD_LIGHT)


## One plant frame (frame `f` of a crop sheet, or the whole texture for a recoloured fruit frame); the middle
## plant is mirrored so a row of three doesn't look stamped.
func _crop(tex: Texture2D, f: int, at: Vector2, flip: bool) -> void:
	var src := Rect2(f * CROP_FRAME.x, 0, CROP_FRAME.x, CROP_FRAME.y)
	if flip:
		draw_set_transform(at + Vector2(CROP_FRAME.x, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(tex, Rect2(Vector2.ZERO, CROP_FRAME), src)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect_region(tex, Rect2(at, CROP_FRAME), src)


func _draw_sign() -> void:
	draw_texture_rect_region(SIGN, Rect2(-2, -SIGN_POST - 2, POST_SRC.size.x, POST_SRC.size.y), POST_SRC)
	if _label == null or kind != "town_sign":
		return
	var b := _board_rect().grow(1)  # arrow tip pointing along the road
	var tip := Vector2(b.end.x - 1, b.position.y + floorf((b.size.y - TIP_SRC.size.y) * 0.5))
	draw_texture_rect_region(SIGN, Rect2(tip, TIP_SRC.size), TIP_SRC)


func _frame(r: Rect2, c: Color) -> void:
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), c)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), c)
	draw_rect(Rect2(r.position, Vector2(1, r.size.y)), c)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), c)


## Small down arrow with its tip at `tip`.
func _arrow(tip: Vector2) -> void:
	var t := tip.round()
	draw_rect(Rect2(t.x - 2, t.y - 9, 5, 5), C_INK)
	draw_rect(Rect2(t.x - 4, t.y - 5, 9, 3), C_INK)
	draw_rect(Rect2(t.x - 2, t.y - 2, 5, 2), C_INK)
	draw_rect(Rect2(t.x - 1, t.y, 3, 1), C_INK)
	draw_rect(Rect2(t.x - 1, t.y - 8, 3, 4), C_RED)
	draw_rect(Rect2(t.x - 3, t.y - 4, 7, 1), C_RED)
	draw_rect(Rect2(t.x - 2, t.y - 3, 5, 1), C_RED)
	draw_rect(Rect2(t.x - 1, t.y - 2, 3, 1), C_RED)
	draw_rect(Rect2(t.x, t.y - 1, 1, 1), C_RED)
