class_name WildObject
extends Node2D
## One thing on a wild map. Ground pickups use ART-04's 16x16 icons (res://assets/sprites/icons/<type>.png);
## trees and bushes use ART-FOREST's sprites (res://assets/sprites/forest/): decor_tree_<kind>,
## tree_<type>_ripe|bare (bare once shaken), bush_<type>_ripe|bare (bare once picked). A type without a sprite
## falls back to a palette-coloured placeholder shape.
## kind: "decor" | "fruit_tree" | "bush" | "ground" | "exit". Position is the feet (bottom-centre of `cell`);
## sprites hang bottom-centred from it, so the y-sorted object layer puts Granny behind trees she stands above.
## Readability (INT-WILD): a fruit tree that still has fruit carries a bobbing paper tag with its fruit's icon
## above the canopy (always, so it never reads as a maple); trees, bushes and ground pickups with something to take
## get a 1 px cream outline while Granny is `near`, and the one she faces a gold outline. Taken things lose both.
## BIOMES: decor kind "vine" (decor_vine), grape vines and elder trees as fruit trees (tree_<type>_ripe|bare, smaller
## than the 64x80 trees: tap area and shadow follow the sprite), kind "hive" (bee_hive_ripe|bare, used like a bush).

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
const C_TAG_EDGE := Color("3d1f29")  ## fruit tag border (plum_900)
## Ground-shadow half widths under sprites, by kind
const SHADOW_HALF := {"decor": 9, "fruit_tree": 11, "bush": 8, "hive": 8}
## Decor canopies by kind: [shade, base, light]
const CANOPY := {
	"maple": ["a22512", "c94d2e", "e19064"],
	"birch": ["9b8039", "e5bd7f", "dbcc83"],
	"oak": ["53612e", "747c37", "b1a13d"],
}
const CANOPY_KINDS := ["maple", "birch", "oak"]
const SPRITE := "res://assets/sprites/forest/%s.png"
## Fruit tag: its tail tip overlaps the canopy top by TAG_OVERLAP px; it bobs 1 px every BOB_MS.
const TAG_OVERLAP := 3
const TAG_HEIGHT := 23
const BOB_MS := 450.0

static var _sprites := {}
static var _outlines := {}  ## "<texture key>|<colour>" -> ImageTexture (null when the image can't be read)
static var _tops := {}  ## texture key -> first opaque row

var kind := ""
var id := -1
var cell := Vector2i.ZERO
var info: Dictionary = {}
var color := Color("c94d2e")  ## fruit, berry or pickup colour
var done := false  ## shaken tree, picked bush
var _icon: Texture2D
var highlighted := false:  ## Granny faces it: gold outline
	set(v):
		if v != highlighted:
			highlighted = v
			queue_redraw()
var near := false:  ## Granny is a few tiles away: cream outline while there is something to take
	set(v):
		if v != near:
			near = v
			queue_redraw()
var _tag: Node2D  ## fruit trees: the paper tag with the fruit icon, drawn above every canopy (z_index)
var _sway := 0  ## FEEL: whole-px canopy offset while the trunk wiggles (0 = still)


func setup(p_kind: String, p_info: Dictionary, p_color: Color) -> void:
	kind = p_kind
	info = p_info
	id = int(p_info.get("id", -1))
	cell = Vector2i(int(p_info.get("x", 0)), int(p_info.get("y", 0)))
	color = p_color
	position = Vector2(cell.x * 16 + 8, cell.y * 16 + 16)
	if kind == "ground" or kind == "fruit_tree":
		_icon = icon_for(String(p_info.get("type", "")))
	if kind == "fruit_tree" and _tag == null:
		_tag = Node2D.new()
		_tag.z_index = 20  # over the canopies in front, under Fx (leaves 40, bubbles 50)
		_tag.draw.connect(_draw_tag)
		add_child(_tag)
	_update_tag()
	queue_redraw()


func _process(_delta: float) -> void:
	if _tag == null or not _tag.visible:
		set_process(false)
		return
	var bob := (floori(Time.get_ticks_msec() / BOB_MS) + cell.x) % 2
	_tag.position = Vector2(0, _tag_tip_y() - bob)


## The type's 16x16 icon, or null while it doesn't exist (SPECIES-GEN: IconLib, so generated species have one too).
static func icon_for(type: String) -> Texture2D:
	return IconLib.ingredient(type)


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


## Something left to take: an unshaken fruit tree, a bush with berries, a ground pickup still lying there, a hive.
func has_take() -> bool:
	return (kind == "fruit_tree" or kind == "bush" or kind == "ground" or kind == "hive") and not done


## World point just above what is drawn (the fruit tag included), for bubbles.
func top() -> Vector2:
	var y := _local_rect().position.y
	var tex := _texture()
	if tex != null:
		y = _sprite_pos(tex).y + opaque_top(tex)
	if _tag != null and _tag.visible:
		y = _tag_tip_y() - TAG_HEIGHT
	return position + Vector2(0, y)


## World point in the middle of a tree's canopy or a bush's leaves, for leaf bursts and falling fruit.
func canopy() -> Vector2:
	var tex := _texture()
	var h := float(tex.get_height()) if tex != null and kind != "ground" else -_local_rect().position.y
	return position + Vector2(0, -roundi(h * 0.58))


## Click/tap area in world px (at least 16x16, tech-spec §7).
func hit_rect() -> Rect2:
	return Rect2(position + _local_rect().position, _local_rect().size)


func set_done(v: bool) -> void:
	if v == done:
		return
	done = v
	_update_tag()
	queue_redraw()
	if done and kind == "ground":
		vanish()


func pop() -> void:
	scale = Vector2(1.25, 0.8)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## FEEL: a 3-frame trunk wiggle (shaken tree): the top half sways 2 px, the next quarter 1 px, the foot stays.
func wiggle() -> void:
	var t := create_tween()
	for s in [2, -2, 1, 0]:
		t.tween_callback(_set_sway.bind(s))
		t.tween_interval(0.055)


func _set_sway(s: int) -> void:
	_sway = 0 if Juice.calm else s
	queue_redraw()


## Whole-pixel wiggle for "can't do that".
func nudge() -> void:
	var x := position.x
	var t := create_tween()
	for dx in [2, -2, 1, 0]:
		t.tween_property(self, "position:x", x + dx, 0.04)


## Picked up: gone at once (FEEL: the scene sends its icon popping up into the HUD bag instead).
func vanish() -> void:
	visible = false
	queue_free()


## Tap area and placeholder frame: the painted canopy for trees (as the garden's trees), the leaves for bushes.
func _local_rect() -> Rect2:
	match kind:
		"decor":
			if _decor_kind() == "vine":
				return Rect2(-8, -24, 16, 24)
			return Rect2(-8, -16, 16, 16) if _cut() else Rect2(-16, -56, 32, 56)
		"fruit_tree":
			var tex := _texture()
			if tex != null and (tex.get_width() < 48 or tex.get_height() < 72):  # vines, elders: the sprite itself
				var sw := maxf(tex.get_width() - 4, 16)
				var sh := maxf(tex.get_height() - opaque_top(tex), 16)
				return Rect2(-floorf(sw * 0.5), -sh, sw, sh)
			return Rect2(-24, -72, 48, 72)
		"bush":
			return Rect2(-14, -30, 28, 30)
		"hive":
			return Rect2(-12, -26, 24, 26)
	return Rect2(-8, -16, 16, 16)


func _draw() -> void:
	var tex := _texture()
	var lit := _outline_color()
	if tex == null:
		_draw_placeholder()
		if lit.a > 0.0:
			_frame(_local_rect(), lit)
		return
	var hw := 0 if _cut() else mini(int(SHADOW_HALF.get(kind, 0)), floori(tex.get_width() * 0.35))
	if hw > 2:
		draw_rect(Rect2(4 - hw, -4, hw * 2 - 4, 4), C_SHADOW)
		draw_rect(Rect2(2 - hw, -3, hw * 2, 2), C_SHADOW)
	var at := _sprite_pos(tex)
	if lit.a > 0.0:
		var ring := outline_for(tex, lit)
		if ring != null:
			_draw_swayed(ring, at - Vector2.ONE)
		else:
			_frame(_local_rect(), lit)
	_draw_swayed(tex, at)


## Draws `tex` at `at`; while swaying in three bands: the top half `_sway` px over, the next quarter half that,
## the foot where it stands (whole pixels, no rotation).
func _draw_swayed(tex: Texture2D, at: Vector2) -> void:
	if _sway == 0:
		draw_texture(tex, at)
		return
	var w := tex.get_width()
	var h := tex.get_height()
	var b1 := floori(h * 0.5)
	var b2 := floori(h * 0.75)
	var mid := int(_sway / 2.0)
	draw_texture_rect_region(tex, Rect2(at + Vector2(_sway, 0), Vector2(w, b1)), Rect2(0, 0, w, b1))
	draw_texture_rect_region(tex, Rect2(at + Vector2(mid, b1), Vector2(w, b2 - b1)), Rect2(0, b1, w, b2 - b1))
	draw_texture_rect_region(tex, Rect2(at + Vector2(0, b2), Vector2(w, h - b2)), Rect2(0, b2, w, h - b2))


## Gold while faced, cream while near with something to take, else none (alpha 0).
func _outline_color() -> Color:
	if highlighted:
		return C_GOLD
	if near and has_take():
		return C_CREAM
	return Color(0, 0, 0, 0)


func _frame(r: Rect2, c: Color) -> void:
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), c)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), c)
	draw_rect(Rect2(r.position, Vector2(1, r.size.y)), c)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), c)


## Sprites hang bottom-centred from the feet.
static func _sprite_pos(tex: Texture2D) -> Vector2:
	return Vector2(-floorf(tex.get_width() * 0.5), -tex.get_height())


## A (w+2)x(h+2) texture holding a 1 px outline (4-neighbour, solid colour `c`) around `tex`'s opaque pixels,
## drawn one pixel up-left of the sprite. Built once per texture and colour; null when the image can't be read.
## (Not the outline shader: the painted trees touch their texture edges, where a shader outline gets clipped.)
static func outline_for(tex: Texture2D, c: Color) -> Texture2D:
	var key := "%s|%s" % [_tex_key(tex), c.to_html()]
	if _outlines.has(key):
		return _outlines[key]
	var out: Texture2D = null
	var img := _image(tex)
	if img != null:
		var w := img.get_width()
		var h := img.get_height()
		var o := Image.create_empty(w + 2, h + 2, false, Image.FORMAT_RGBA8)
		for y in h + 2:
			for x in w + 2:
				if _solid(img, x - 1, y - 1):
					continue
				if _solid(img, x, y - 1) or _solid(img, x - 2, y - 1) or _solid(img, x - 1, y) or _solid(img, x - 1, y - 2):
					o.set_pixel(x, y, c)
		out = ImageTexture.create_from_image(o)
	_outlines[key] = out
	return out


## First opaque row of `tex` (0 when the image can't be read).
static func opaque_top(tex: Texture2D) -> int:
	var key := _tex_key(tex)
	if not _tops.has(key):
		var img := _image(tex)
		_tops[key] = img.get_used_rect().position.y if img != null else 0
	return _tops[key]


static func _tex_key(tex: Texture2D) -> String:
	return tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())


static func _image(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _solid(img: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and img.get_pixel(x, y).a > 0.5


## This object's sprite in its current state, or null (the exit draws itself; so does ground without an icon).
func _texture() -> Texture2D:
	var state := "bare" if done else "ripe"
	match kind:
		"decor":
			if _cut():
				return sprite("prop_stump")
			if _decor_kind() == "vine":
				return sprite("decor_vine")
			return sprite("decor_tree_" + _decor_kind())
		"fruit_tree":
			return sprite("tree_%s_%s" % [String(info.get("type", "")), state])
		"bush":
			if IconLib.is_generated(String(info.get("type", ""))):  # SPECIES-GEN: the bush with species berries
				return IconLib.bush(String(info.type), done)
			return sprite("bush_%s_%s" % [String(info.get("type", "")), state])
		"hive":
			return sprite("bee_hive_" + state)
		"ground":
			return _icon
	return null


## A decor tree the map view drew as a stump (its canopy would hide a path or clearing).
func _cut() -> bool:
	return kind == "decor" and bool(info.get("cut", false)) and sprite("prop_stump") != null


func _update_tag() -> void:
	if _tag == null:
		return
	_tag.visible = has_take()
	_tag.position = Vector2(0, _tag_tip_y())
	_tag.queue_redraw()
	set_process(_tag.visible)


## Local y of the tag's tail tip: a few px into the top of the canopy.
func _tag_tip_y() -> int:
	var tex := _texture()
	if tex == null:
		return int(_local_rect().position.y) + TAG_OVERLAP
	return int(_sprite_pos(tex).y) + opaque_top(tex) + TAG_OVERLAP


## Paper tag (20x20, cut corners) with the fruit icon and a 3 px tail; (0, 0) is the row under the tail tip.
func _draw_tag() -> void:
	var t := _tag
	t.draw_rect(Rect2(-9, -23, 18, 20), C_TAG_EDGE)
	t.draw_rect(Rect2(-10, -22, 20, 18), C_TAG_EDGE)
	t.draw_rect(Rect2(-9, -22, 18, 18), C_CREAM)
	t.draw_rect(Rect2(-2, -4, 5, 1), C_CREAM)
	t.draw_rect(Rect2(-2, -3, 5, 1), C_TAG_EDGE)
	t.draw_rect(Rect2(-1, -3, 3, 1), C_CREAM)
	t.draw_rect(Rect2(-1, -2, 3, 1), C_TAG_EDGE)
	t.draw_rect(Rect2(0, -2, 1, 1), C_CREAM)
	t.draw_rect(Rect2(0, -1, 1, 1), C_TAG_EDGE)
	if _icon != null:
		t.draw_texture(_icon, Vector2(-8, -21))
	else:
		t.draw_rect(Rect2(-4, -17, 8, 8), C_INK)
		t.draw_rect(Rect2(-4, -17, 7, 7), color)


## WildGen's decor kind ("maple" | "birch" | "oak" | "vine"); anything else maps onto one of the trees.
func _decor_kind() -> String:
	var k := String(info.get("kind", ""))
	return k if CANOPY.has(k) or k == "vine" else CANOPY_KINDS[absi(hash(k)) % CANOPY_KINDS.size()]


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
		"hive":
			_draw_hive()
		"exit":
			_draw_exit()


func _draw_decor() -> void:
	var k := _decor_kind()
	if k == "vine":
		draw_rect(Rect2(-1, -8, 2, 8), C_BARK)
		_blob(Rect2(-8, -22, 16, 15), C_OLIVE_DARK, C_OLIVE, C_OLIVE_MID)
		return
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


func _draw_hive() -> void:
	draw_rect(Rect2(-6, -14, 12, 14), C_INK)
	draw_rect(Rect2(-5, -13, 10, 13), C_BARK_MID)
	draw_rect(Rect2(-2, -10, 4, 5), C_INK)
	if not done:
		draw_rect(Rect2(-2, -10, 4, 4), C_GOLD)


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
