class_name GardenSpot
extends Node2D
## One thing in the garden (GD-GARDEN): "house" | "door" | "tree" | "bed" | "compost" | "mailbox" | "gate" |
## "gate_sign" | "town_sign". Position is the feet (bottom-centre of its cells) so the y-sorted object layer
## orders it against Granny. Fruit trees use tree_<type>_ripe/_bare sprites when they exist (the bare apple
## tree stands in for the others, with their fruit drawn on); the rest are palette-coloured placeholder shapes
## until the garden props (art-bible §3.6) land. No rules here: the scene passes the state in.
## `highlighted`: Granny faces it. `glow`: Granny's To-Do points here (blinking outline + bobbing arrow).

const TILE := 16
## Approved tree sprites, first match wins: tree_<type>_ripe.png / tree_<type>_bare.png (art-bible §3.6).
const TREE_DIRS := ["res://assets/sprites/forest/", "res://assets/sprites/world/"]
const CANDIDATE_TREE := "res://assets/sprites/forest/candidates/tree_apple_%s.png"
const OUTLINE := preload("res://shaders/outline_highlight.gdshader")

const C_INK := Color("111010")
const C_SLATE := Color("23282a")
const C_STONE_DARK := Color("49423d")
const C_STONE := Color("81746a")
const C_STONE_LIGHT := Color("b4b3a0")
const C_RED_DARK := Color("a22512")
const C_RED := Color("c94d2e")
const C_PEACH := Color("e19064")
const C_AMBER := Color("b66813")
const C_GOLD := Color("e5bd7f")
const C_GOLD_LIGHT := Color("dbcc83")
const C_BARK_DARK := Color("50361e")
const C_BARK := Color("83571e")
const C_BARK_LIGHT := Color("c58845")
const C_CREAM_DARK := Color("b9a697")
const C_CREAM := Color("f2d9c5")
const C_OLIVE_DARK := Color("314524")
const C_OLIVE := Color("53612e")
const C_OLIVE_MID := Color("747c37")
const C_OLIVE_LIGHT := Color("b1a13d")
const C_OLIVE_PALE := Color("b7b768")
const C_PLUM := Color("3d1f29")
const C_WINE := Color("62272c")
const C_WATER := Color("415c5d")
## Fruit spots on the stand-in canopy, sprite coordinates relative to the feet.
const FRUIT_SPOTS := [Vector2(-18, -62), Vector2(-6, -70), Vector2(8, -64), Vector2(18, -54), Vector2(-12, -48),
	Vector2(2, -54), Vector2(14, -42), Vector2(-22, -40)]
const SIGN_POST := 12

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

var _sprite: Sprite2D
var _ripe: Texture2D
var _bare: Texture2D
var _label: Label
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
	queue_redraw()


func set_mail(p_unread: int) -> void:
	if p_unread != unread:
		unread = p_unread
		_restyle()


## Sign text (already translated). Call once the spot is in the tree so the theme font is known.
func set_label(text: String) -> void:
	if _label == null:
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
		queue_redraw()


func _restyle() -> void:
	set_process(glow or is_ready() or unread > 0)
	_blink_on = true
	_update_outline()
	queue_redraw()


func _update_outline() -> void:
	if _sprite == null:
		return
	var mat := _sprite.material as ShaderMaterial
	mat.set_shader_parameter("enabled", highlighted or (glow and _blink_on))
	mat.set_shader_parameter("outline_color", C_CREAM if glow and not highlighted else C_GOLD)


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
		_sprite = Sprite2D.new()
		_sprite.centered = false
		_sprite.show_behind_parent = true  # fruit spots and frames draw over it
		var mat := ShaderMaterial.new()
		mat.shader = OUTLINE
		_sprite.material = mat
		add_child(_sprite)
	var sz := _bare.get_size()
	_sprite.position = Vector2(-floori(sz.x * 0.5), -sz.y)
	_update_outline()


static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _local_rect() -> Rect2:
	match kind:
		"house":
			return Rect2(-48, -80, 96, 80)
		"door":
			return Rect2(-12, -28, 24, 28)
		"tree":
			return Rect2(-24, -72, 48, 72)
		"bed":
			return Rect2(-16, -22, 32, 22)
		"compost":
			return Rect2(-8, -18, 16, 18)
		"mailbox":
			return Rect2(-8, -22, 20, 22)
		"gate":
			return Rect2(-18, -31, 36, 31)
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
		"house":
			_draw_house()
		"door":
			_draw_door()
		"tree":
			_draw_tree()
		"bed":
			_draw_bed()
		"compost":
			_draw_compost()
		"mailbox":
			_draw_mailbox()
		"gate":
			_draw_gate()
		"gate_sign", "town_sign":
			_draw_sign()
	if kind != "tree" or _sprite == null:
		if highlighted or (glow and _blink_on):
			_frame(_local_rect(), C_GOLD if highlighted else C_CREAM)
	if glow:
		var top_y := _local_rect().position.y
		if _sprite != null:
			top_y = minf(top_y, _sprite.position.y)
		_arrow(Vector2(0, top_y - 2 - _bob))


func _draw_house() -> void:
	# roof
	draw_rect(Rect2(-48, -80, 96, 36), C_INK)
	draw_rect(Rect2(-47, -79, 94, 33), C_RED_DARK)
	for row in 4:
		var y := -76 + row * 8
		draw_rect(Rect2(-47, y, 94, 1), C_WINE)
		for i in 12:
			draw_rect(Rect2(-45 + i * 8 + (row % 2) * 4, y + 2, 4, 2), C_RED)
	draw_rect(Rect2(24, -80, 9, 12), C_INK)  # chimney
	draw_rect(Rect2(25, -80, 7, 11), C_STONE)
	draw_rect(Rect2(25, -80, 7, 2), C_STONE_LIGHT)
	draw_rect(Rect2(-48, -46, 96, 3), C_BARK_DARK)  # eave
	# walls: cream plaster, timber posts
	draw_rect(Rect2(-46, -43, 92, 39), C_INK)
	draw_rect(Rect2(-45, -43, 90, 38), C_CREAM)
	draw_rect(Rect2(-45, -43, 90, 3), C_CREAM_DARK)
	for x in [-45, -19, 16, 42]:
		draw_rect(Rect2(x, -43, 3, 38), C_BARK)
		draw_rect(Rect2(x, -43, 1, 38), C_BARK_DARK)
	for wx in [-38, 22]:
		_window(Vector2(wx, -36))
	draw_rect(Rect2(-47, -5, 94, 5), C_INK)  # stone footing
	draw_rect(Rect2(-46, -5, 92, 4), C_STONE)
	for i in 8:
		draw_rect(Rect2(-44 + i * 12, -4, 7, 1), C_STONE_LIGHT)


func _window(o: Vector2) -> void:
	draw_rect(Rect2(o, Vector2(16, 14)), C_BARK_DARK)
	draw_rect(Rect2(o + Vector2(1, 1), Vector2(14, 12)), C_GOLD)
	draw_rect(Rect2(o + Vector2(2, 2), Vector2(4, 3)), C_GOLD_LIGHT)
	draw_rect(Rect2(o + Vector2(7, 1), Vector2(2, 12)), C_BARK)
	draw_rect(Rect2(o + Vector2(1, 6), Vector2(14, 2)), C_BARK)
	# flower box
	draw_rect(Rect2(o + Vector2(-2, 14), Vector2(20, 4)), C_BARK_DARK)
	draw_rect(Rect2(o + Vector2(-1, 14), Vector2(18, 3)), C_BARK)
	for i in 4:
		draw_rect(Rect2(o + Vector2(1 + i * 4, 12), Vector2(2, 2)), C_RED if i % 2 == 0 else C_PEACH)


func _draw_door() -> void:
	draw_rect(Rect2(-11, -30, 22, 27), C_INK)
	draw_rect(Rect2(-10, -29, 20, 26), C_BARK_DARK)
	draw_rect(Rect2(-9, -27, 18, 24), C_BARK)
	for x in [-5, 0, 5]:
		draw_rect(Rect2(x, -27, 1, 24), C_BARK_DARK)
	draw_rect(Rect2(-9, -27, 18, 1), C_BARK_LIGHT)
	draw_rect(Rect2(-9, -18, 18, 1), C_BARK_DARK)
	draw_rect(Rect2(5, -16, 2, 2), C_GOLD)  # knob
	draw_rect(Rect2(-13, -3, 26, 3), C_INK)  # doorstep
	draw_rect(Rect2(-12, -3, 24, 2), C_STONE_LIGHT)


func _draw_tree() -> void:
	if _sprite != null:
		if fruit and _ripe == null:
			for p in FRUIT_SPOTS:
				draw_rect(Rect2(p, Vector2(4, 4)), C_INK)
				draw_rect(Rect2(p, Vector2(3, 3)), color)
				draw_rect(Rect2(p, Vector2(1, 1)), C_CREAM)
		return
	# no sprites at all: chunky placeholder canopy
	draw_rect(Rect2(-4, -18, 8, 18), C_INK)
	draw_rect(Rect2(-3, -18, 6, 18), C_BARK)
	draw_rect(Rect2(-3, -18, 2, 18), C_BARK_DARK)
	draw_rect(Rect2(-18, -52, 36, 36), C_INK)
	draw_rect(Rect2(-17, -51, 34, 34), C_OLIVE if fruit else C_OLIVE_DARK)
	draw_rect(Rect2(-15, -49, 24, 6), C_OLIVE_MID if fruit else C_OLIVE)
	if fruit:
		for p in [Vector2(-12, -44), Vector2(2, -46), Vector2(-6, -34), Vector2(8, -30), Vector2(-14, -26), Vector2(10, -40)]:
			draw_rect(Rect2(p, Vector2(4, 4)), C_INK)
			draw_rect(Rect2(p, Vector2(3, 3)), color)


func _draw_bed() -> void:
	draw_rect(Rect2(-16, -14, 32, 14), C_INK)
	draw_rect(Rect2(-15, -13, 30, 12), C_BARK)
	draw_rect(Rect2(-15, -13, 30, 1), C_BARK_LIGHT)
	draw_rect(Rect2(-14, -12, 28, 7), C_BARK_DARK)  # soil
	draw_rect(Rect2(-13, -10, 26, 1), C_PLUM)
	draw_rect(Rect2(-13, -7, 26, 1), C_PLUM)
	draw_rect(Rect2(-15, -5, 30, 1), C_BARK_LIGHT)  # front board
	draw_rect(Rect2(-15, -2, 30, 1), C_BARK_DARK)
	if fertilized:
		for p in [Vector2(-11, -11), Vector2(-3, -8), Vector2(6, -11), Vector2(11, -8)]:
			draw_rect(Rect2(p, Vector2(1, 1)), C_AMBER)
	if crop == "":
		return
	var grown := float(grow_days - days_left) / float(grow_days)
	for x in [-9, 0, 9]:
		if days_left <= 0:
			_plant_ready(x)
		elif grown <= 0.0:
			draw_rect(Rect2(x - 1, -8, 3, 1), C_BARK_LIGHT)  # seed mound
			draw_rect(Rect2(x, -9, 1, 1), C_CREAM_DARK)
		elif grown < 0.5:
			_sprout(x)
		else:
			_young(x)
	if days_left <= 0 and _blink_on:
		draw_rect(Rect2(12, -21, 1, 3), C_GOLD_LIGHT)
		draw_rect(Rect2(11, -20, 3, 1), C_GOLD_LIGHT)


## Two seed leaves on a short stem.
func _sprout(x: int) -> void:
	draw_rect(Rect2(x, -10, 1, 3), C_OLIVE_MID)
	draw_rect(Rect2(x - 2, -12, 2, 2), C_OLIVE_LIGHT)
	draw_rect(Rect2(x + 1, -12, 2, 2), C_OLIVE_LIGHT)
	draw_rect(Rect2(x - 2, -11, 1, 1), C_OLIVE_MID)
	draw_rect(Rect2(x + 2, -11, 1, 1), C_OLIVE_MID)


## A small leafy plant, no fruit yet.
func _young(x: int) -> void:
	draw_rect(Rect2(x - 3, -14, 7, 6), C_INK)
	draw_rect(Rect2(x - 2, -15, 5, 1), C_INK)
	draw_rect(Rect2(x - 2, -14, 5, 6), C_OLIVE)
	draw_rect(Rect2(x - 3, -13, 7, 4), C_OLIVE)
	draw_rect(Rect2(x - 2, -14, 3, 2), C_OLIVE_MID)
	draw_rect(Rect2(x - 1, -14, 1, 1), C_OLIVE_PALE)
	draw_rect(Rect2(x, -8, 1, 1), C_OLIVE_DARK)


func _plant_ready(x: int) -> void:
	draw_rect(Rect2(x - 4, -16, 9, 9), C_INK)
	draw_rect(Rect2(x - 3, -15, 7, 7), C_OLIVE)
	draw_rect(Rect2(x - 3, -15, 5, 3), C_OLIVE_MID)
	draw_rect(Rect2(x - 2, -15, 2, 1), C_OLIVE_PALE)
	draw_rect(Rect2(x + 1, -12, 3, 5), C_INK)
	draw_rect(Rect2(x + 1, -12, 2, 4), color)
	draw_rect(Rect2(x + 1, -12, 1, 1), C_CREAM)


func _draw_compost() -> void:
	draw_rect(Rect2(-8, -16, 16, 16), C_INK)
	draw_rect(Rect2(-7, -15, 14, 4), C_PLUM)  # what's inside, seen from above
	var heap := clampi(compost, 0, compost_per)
	if heap > 0:
		var w := 2 + roundi(10.0 * heap / compost_per)
		draw_rect(Rect2(-floori(w * 0.5), -15, w, 3), C_OLIVE_MID)
		draw_rect(Rect2(-floori(w * 0.5) + 1, -15, maxi(1, w - 4), 1), C_AMBER)
	for i in 3:
		var y := -11 + i * 4
		draw_rect(Rect2(-7, y, 14, 3), C_BARK)
		draw_rect(Rect2(-7, y, 14, 1), C_BARK_LIGHT)
	for i in mini(fertilizer, 3):  # sacks of fertilizer leaning on the bin
		var x := 9 + i * 4
		draw_rect(Rect2(x - 1, -8, 6, 8), C_INK)
		draw_rect(Rect2(x, -7, 4, 7), C_CREAM_DARK)
		draw_rect(Rect2(x, -8, 4, 1), C_BARK_LIGHT)
		draw_rect(Rect2(x + 1, -4, 2, 1), C_OLIVE_MID)


func _draw_mailbox() -> void:
	draw_rect(Rect2(-2, -11, 4, 11), C_INK)
	draw_rect(Rect2(-1, -11, 2, 11), C_BARK)
	draw_rect(Rect2(-7, -20, 14, 10), C_INK)
	draw_rect(Rect2(-6, -19, 12, 8), C_RED_DARK)
	draw_rect(Rect2(-6, -19, 12, 2), C_RED)
	draw_rect(Rect2(-4, -15, 6, 1), C_INK)  # slot
	if unread <= 0:
		draw_rect(Rect2(6, -17, 2, 6), C_INK)  # flag down: nothing new
		draw_rect(Rect2(6, -13, 3, 2), C_GOLD)
		return
	draw_rect(Rect2(-4, -17, 6, 2), C_CREAM)  # an envelope peeking out of the slot
	draw_rect(Rect2(-4, -16, 6, 1), C_CREAM_DARK)
	draw_rect(Rect2(6, -27, 2, 16), C_INK)  # flag raised, blinking
	draw_rect(Rect2(7, -26, 5, 4), C_INK)
	draw_rect(Rect2(7, -26, 4, 3), C_GOLD if _blink_on else C_RED)


func _draw_gate() -> void:
	for sx in [-17, 13]:
		draw_rect(Rect2(sx, -28, 4, 28), C_INK)
		draw_rect(Rect2(sx + 1, -27, 2, 27), C_BARK)
		draw_rect(Rect2(sx + 1, -27, 1, 27), C_BARK_LIGHT)
	draw_rect(Rect2(-19, -31, 38, 4), C_INK)  # arch beam with a leaf garland
	draw_rect(Rect2(-18, -30, 36, 2), C_BARK)
	draw_rect(Rect2(-18, -30, 36, 1), C_BARK_LIGHT)
	for i in 6:
		draw_rect(Rect2(-15 + i * 6, -28, 3, 2), [C_RED, C_GOLD, C_AMBER][i % 3])
	# gate leaves swung open against the fence
	for side in [-1, 1]:
		var x0 := -13 if side < 0 else 9
		draw_rect(Rect2(x0, -14, 4, 12), C_INK)
		draw_rect(Rect2(x0 + 1, -13, 2, 10), C_BARK_LIGHT)
		draw_rect(Rect2(x0 + 1, -9, 2, 1), C_BARK_DARK)


func _draw_sign() -> void:
	draw_rect(Rect2(-2, -SIGN_POST - 1, 4, SIGN_POST + 1), C_INK)
	draw_rect(Rect2(-1, -SIGN_POST, 2, SIGN_POST), C_BARK)
	if _label == null:
		return
	var b := _board_rect()
	draw_rect(b.grow(1), C_INK)
	draw_rect(b, C_BARK)
	draw_rect(b.grow(-1), C_CREAM)
	if kind == "town_sign":  # arrow tip pointing along the road
		var tip := Vector2(b.end.x, b.position.y + floorf(b.size.y * 0.5))
		for i in 4:
			draw_rect(Rect2(tip.x + i, tip.y - 3 + i, 1, 7 - i * 2), C_INK)
			if i < 3:
				draw_rect(Rect2(tip.x - 1 + i, tip.y - 2 + i, 1, 5 - i * 2), C_CREAM)


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
