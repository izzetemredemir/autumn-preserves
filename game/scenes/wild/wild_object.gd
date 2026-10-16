class_name WildObject
extends Node2D
## One thing on a wild map. Ground pickups use ART-04's 16x16 icons (res://assets/sprites/icons/<type>.png);
## trees and bushes use ART-FOREST's sprites (res://assets/sprites/forest/): decor_tree_<kind>,
## tree_<type>_ripe|bare (bare once shaken), bush_<type>_ripe|bare (bare once picked). A type without a sprite
## falls back to a palette-coloured placeholder shape.
## kind: "decor" | "fruit_tree" | "bush" | "ground" | "exit". Position is the feet (bottom-centre of `cell`);
## sprites hang bottom-centred from it, so the y-sorted object layer puts Granny behind trees she stands above.

const C_INK := Color("111010")
const C_BARK := Color("50361e")
const C_BARK_MID := Color("83571e")
const C_BARK_LIGHT := Color("c58845")
const C_CREAM := Color("f2d9c5")
const C_GOLD := Color("e5bd7f")
const C_OLIVE_DARK := Color("314524")
const C_OLIVE := Color("53612e")
const C_OLIVE_MID := Color("747c37")
const C_SHADOW := Color("3d1f29")  ## plum_900: hard ground shadow to the lower right (art-bible §2.5)
## Ground-shadow half widths under sprites, by kind
const SHADOW_HALF := {"decor": 9, "fruit_tree": 11, "bush": 8}
## Decor canopies by kind: [shade, base, light]
const CANOPY := {
	"maple": ["a22512", "c94d2e", "e19064"],
	"birch": ["9b8039", "e5bd7f", "dbcc83"],
	"oak": ["53612e", "747c37", "b1a13d"],
}
const CANOPY_KINDS := ["maple", "birch", "oak"]
const ICON := "res://assets/sprites/icons/%s.png"
const SPRITE := "res://assets/sprites/forest/%s.png"

static var _icons := {}
static var _sprites := {}

var kind := ""
var id := -1
var cell := Vector2i.ZERO
var info: Dictionary = {}
var color := Color("c94d2e")  ## fruit, berry or pickup colour
var done := false  ## shaken tree, picked bush
var _icon: Texture2D
var highlighted := false:
	set(v):
		if v != highlighted:
			highlighted = v
			queue_redraw()


func setup(p_kind: String, p_info: Dictionary, p_color: Color) -> void:
	kind = p_kind
	info = p_info
	id = int(p_info.get("id", -1))
	cell = Vector2i(int(p_info.get("x", 0)), int(p_info.get("y", 0)))
	color = p_color
	position = Vector2(cell.x * 16 + 8, cell.y * 16 + 16)
	if kind == "ground":
		_icon = icon_for(String(p_info.get("type", "")))
	queue_redraw()


## The type's 16x16 icon, or null while it doesn't exist.
static func icon_for(type: String) -> Texture2D:
	if not _icons.has(type):
		var path := ICON % type
		_icons[type] = load(path) if type != "" and ResourceLoader.exists(path) else null
	return _icons[type]


## A forest sprite by file name (no extension), or null while it doesn't exist.
static func sprite(file: String) -> Texture2D:
	if not _sprites.has(file):
		var path := SPRITE % file
		_sprites[file] = load(path) if ResourceLoader.exists(path) else null
	return _sprites[file]


## Trees stand in the way; pickups and the exit lie on walkable ground.
func blocks() -> bool:
	return kind == "decor" or kind == "fruit_tree"


func usable() -> bool:
	return kind != "decor" and not (done and kind != "fruit_tree")


## Click/tap area in world px (at least 16x16, tech-spec §7).
func hit_rect() -> Rect2:
	return Rect2(position + _local_rect().position, _local_rect().size)


func set_done(v: bool) -> void:
	if v == done:
		return
	done = v
	queue_redraw()
	if done and kind == "ground":
		vanish()


func pop() -> void:
	scale = Vector2(1.25, 0.8)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Whole-pixel wiggle for "can't do that".
func nudge() -> void:
	var x := position.x
	var t := create_tween()
	for dx in [2, -2, 1, 0]:
		t.tween_property(self, "position:x", x + dx, 0.04)


func vanish() -> void:
	var y := position.y
	var t := create_tween()
	t.tween_property(self, "position:y", y - 6, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(queue_free)


func _local_rect() -> Rect2:
	match kind:
		"decor":
			return Rect2(-12, -34, 24, 34)
		"fruit_tree":
			return Rect2(-16, -42, 32, 42)
	return Rect2(-8, -16, 16, 16)


func _draw() -> void:
	var tex := _texture()
	if tex != null:
		var hw := int(SHADOW_HALF.get(kind, 0))
		if hw > 0:
			draw_rect(Rect2(4 - hw, -4, hw * 2 - 4, 4), C_SHADOW)
			draw_rect(Rect2(2 - hw, -3, hw * 2, 2), C_SHADOW)
		draw_texture(tex, Vector2(-floorf(tex.get_width() * 0.5), -tex.get_height()))
	else:
		_draw_placeholder()
	if highlighted:
		var r := _local_rect()
		draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), C_GOLD)
		draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), C_GOLD)
		draw_rect(Rect2(r.position, Vector2(1, r.size.y)), C_GOLD)
		draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), C_GOLD)


## This object's sprite in its current state, or null (ground icons and the exit draw themselves).
func _texture() -> Texture2D:
	var state := "bare" if done else "ripe"
	match kind:
		"decor":
			return sprite("decor_tree_" + _decor_kind())
		"fruit_tree":
			return sprite("tree_%s_%s" % [String(info.get("type", "")), state])
		"bush":
			return sprite("bush_%s_%s" % [String(info.get("type", "")), state])
	return null


## WildGen's decor kind ("maple" | "birch" | "oak"); anything else maps onto one of them.
func _decor_kind() -> String:
	var k := String(info.get("kind", ""))
	return k if CANOPY.has(k) else CANOPY_KINDS[absi(hash(k)) % CANOPY_KINDS.size()]


func _draw_placeholder() -> void:
	match kind:
		"decor":
			_draw_decor()
		"fruit_tree":
			_draw_fruit_tree()
		"bush":
			_draw_bush()
		"ground":
			_draw_ground()
		"exit":
			_draw_exit()


func _draw_decor() -> void:
	var k := _decor_kind()
	var c: Array = CANOPY[k]
	var trunk := Color("b9a697") if k == "birch" else C_BARK
	draw_rect(Rect2(-2, -12, 4, 12), trunk)
	draw_rect(Rect2(-1, -2, 2, 2), C_INK)
	_blob(Rect2(-11, -32, 22, 20), Color(c[0]), Color(c[1]), Color(c[2]))


func _draw_fruit_tree() -> void:
	draw_rect(Rect2(-3, -14, 6, 14), C_BARK_MID)
	draw_rect(Rect2(-3, -14, 2, 14), C_BARK)
	if done:
		_blob(Rect2(-15, -40, 30, 26), C_OLIVE_DARK, C_OLIVE, C_OLIVE_MID)
		return
	_blob(Rect2(-15, -40, 30, 26), C_OLIVE, C_OLIVE_MID, Color("b1a13d"))
	for p in [Vector2(-9, -33), Vector2(3, -36), Vector2(-3, -27), Vector2(7, -26), Vector2(-12, -23), Vector2(9, -32)]:
		draw_rect(Rect2(p, Vector2(4, 4)), C_INK)
		draw_rect(Rect2(p + Vector2(0, 0), Vector2(3, 3)), color)


func _draw_bush() -> void:
	_blob(Rect2(-8, -12, 16, 12), C_OLIVE_DARK, C_OLIVE, C_OLIVE_MID)
	if done:
		draw_rect(Rect2(-5, -9, 1, 4), C_BARK_LIGHT)
		draw_rect(Rect2(3, -10, 1, 5), C_BARK_LIGHT)
		return
	for p in [Vector2(-5, -9), Vector2(1, -10), Vector2(4, -6), Vector2(-2, -5)]:
		draw_rect(Rect2(p, Vector2(2, 2)), color)


func _draw_ground() -> void:
	if _icon != null:
		draw_texture(_icon, Vector2(-8, -16))
		return
	var t := String(info.get("type", ""))
	var group := String(Data.ingredients().get(t, {}).get("group", ""))
	if group == "mushroom":
		draw_rect(Rect2(-1, -6, 3, 5), C_CREAM)
		draw_rect(Rect2(-5, -10, 10, 4), color)
		draw_rect(Rect2(-4, -11, 8, 1), color)
		draw_rect(Rect2(-5, -6, 10, 1), C_INK)
	else:
		draw_rect(Rect2(-3, -8, 6, 6), C_INK)
		draw_rect(Rect2(-3, -8, 5, 5), color)
		draw_rect(Rect2(-2, -7, 1, 1), C_CREAM)


func _draw_exit() -> void:
	draw_rect(Rect2(-1, -10, 2, 10), C_BARK)
	draw_rect(Rect2(-7, -15, 14, 7), C_BARK)
	draw_rect(Rect2(-6, -14, 12, 5), C_BARK_LIGHT)
	# arrow pointing down, out of the forest
	draw_rect(Rect2(-1, -14, 2, 3), C_BARK)
	draw_rect(Rect2(-3, -11, 6, 1), C_BARK)
	draw_rect(Rect2(-2, -10, 4, 1), C_BARK)


## A chunky round-ish canopy from rects: shade, base and a light corner.
func _blob(r: Rect2, shade: Color, base: Color, light: Color) -> void:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	draw_rect(Rect2(x + 3, y, w - 6, h), C_INK)
	draw_rect(Rect2(x, y + 3, w, h - 6), C_INK)
	draw_rect(Rect2(x + 1, y + 1, w - 2, h - 2), C_INK)
	draw_rect(Rect2(x + 3, y + 1, w - 6, h - 2), shade)
	draw_rect(Rect2(x + 1, y + 3, w - 2, h - 6), shade)
	draw_rect(Rect2(x + 3, y + 1, w - 6, h - 5), base)
	draw_rect(Rect2(x + 1, y + 3, w - 2, h - 9), base)
	draw_rect(Rect2(x + 4, y + 2, floorf(w * 0.4), 3), light)
	draw_rect(Rect2(x + 2, y + 4, 3, floorf(h * 0.3)), light)
