class_name JarIcon
extends Control
## Procedural preserve icon (spec §7.3, tech-spec §10). Draws vessel, fill, chunks, label and lid
## from a ProductGen.describe() dict, using only Vintage Autumn 31 colours.
## view "shelf": 24x24 (bottle 24x48). view "icon": 16x16. `zoom` multiplies by whole numbers only.
## All pixel work lives in render(); _draw() just blits the cached image (nearest, integer scale).
## QA-FIX: the composed texture is cached per look and view (a jar's look is fixed by its description), so the
## pantry, parcel and market views that are rebuilt on every change don't compose an Image each time (~1.5 ms a jar).

const PALETTE := [
	"111010", "a22512", "c94d2e", "e19064", "49423d", "81746a", "b9a697", "f2d9c5", "50361e", "b66813",
	"c58845", "83571e", "e5bd7f", "9b8039", "dbcc83", "b1a13d", "c5bf3f", "b4b3a0", "b7b768", "747c37",
	"53612e", "314524", "738c7a", "4e7664", "275e4c", "2e3f3f", "415c5d", "567c7d", "23282a", "3d1f29", "62272c",
]
const INK := "111010"
const GLASS := "b4b3a0"
const CREAM_HI := "f2d9c5"
const CREAM_LO := "b9a697"
const GOLD_HI := "dbcc83"
const GOLD_MID := "e5bd7f"
const GOLD_LO := "b66813"
const BARK_MID := "c58845"
const BARK_DK := "83571e"
const LEAF_RED := "a22512"
const PEACH := "e19064"

## Switch for hand-drawn layers (res://assets/sprites/jars/layer_<shape>_<kap|dolgu|parça|etiket|kapak>.png).
## While false, or when the files are missing, the procedural renderer below is used.
@export var use_textures := false
@export var view := "shelf":
	set(v):
		view = v
		_refresh()
@export_range(1, 4) var zoom := 1:
	set(v):
		zoom = maxi(v, 1)
		_refresh()

const TEX_CACHE_MAX := 512  ## looks kept (a full save shows far fewer); the cache starts over past this

static var _snap_cache := {}
static var _supply_cache := {}
static var _tex_cache := {}  ## look key (look_key) -> ImageTexture

var _desc: Dictionary = {}
var _tex: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()


func show_product(desc: Dictionary) -> void:
	_desc = desc
	_refresh()


func _refresh() -> void:
	var sz := pixel_size(_desc, view)
	custom_minimum_size = Vector2(sz * zoom)
	size = custom_minimum_size
	_tex = null
	if not _desc.is_empty():
		var key := look_key(_desc, view, use_textures)
		_tex = _tex_cache.get(key)
		if _tex == null:
			var img: Image = null
			if use_textures:
				img = _compose_textures(_desc, view)
			if img == null:
				img = render(_desc, view)
			_tex = ImageTexture.create_from_image(img)
			if _tex_cache.size() >= TEX_CACHE_MAX:
				_tex_cache.clear()
			_tex_cache[key] = _tex
	queue_redraw()


## What fixes a product's picture: the view, its key and vessel, and every appearance value render() reads.
static func look_key(desc: Dictionary, v: String, textures := false) -> String:
	var a: Variant = desc.get("appearance", {})
	return "%s|%s|%s|%d|%d" % [v, str(desc.get("key", "")), _vessel(desc), (a as Dictionary).hash() if a is Dictionary else 0, int(textures)]


## The texture a view of `desc` shows (shared by every view of the same look; never edit it).
func texture() -> Texture2D:
	return _tex


func _draw() -> void:
	if _tex:
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(pixel_size(_desc, view) * zoom)), false)


# ---------------------------------------------------------------- public helpers

static func pixel_size(desc: Dictionary, v: String) -> Vector2i:
	if v == "icon":
		return Vector2i(16, 16)
	if _vessel(desc) == "bottle":
		return Vector2i(24, 48)
	return Vector2i(24, 24)


## 16x16 icon for a P1 supply the icon atlas does not have yet: "bottle" (empty, corked), "flour" (sack),
## "cabbage" and "mint". null for anything else. Palette colours only, cached.
static func supply_icon(id: String) -> Texture2D:
	if _supply_cache.has(id):
		return _supply_cache[id]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var ink := col(INK)
	match id:
		"bottle":
			_paint_silhouette(img, [Rect2i(6, 3, 4, 5), Rect2i(4, 8, 8, 7), Rect2i(3, 9, 10, 5)], 99, _tones({}))
			_rect(img, Rect2i(6, 0, 4, 4), ink)
			_rect(img, Rect2i(7, 1, 2, 2), col(BARK_MID))
			_px(img, 5, 10, col(CREAM_HI))
			_px(img, 5, 11, col(CREAM_HI))
		"flour":
			_paint_silhouette(img, [Rect2i(3, 5, 10, 10), Rect2i(2, 7, 12, 7)], 5, [col(CREAM_HI), col(CREAM_HI), col(CREAM_LO)])
			for p in [Rect2i(5, 1, 2, 3), Rect2i(9, 1, 2, 3)]:
				_rect(img, p, ink)
				_px(img, p.position.x, p.position.y + 1, col(CREAM_HI))
			_rect(img, Rect2i(5, 4, 6, 1), col(BARK_DK))
			for p in [Vector2i(7, 9), Vector2i(8, 8), Vector2i(8, 10), Vector2i(9, 9), Vector2i(8, 11), Vector2i(8, 12)]:
				_px(img, p.x, p.y, col(GOLD_LO))
		"cabbage":
			_paint_silhouette(img, [Rect2i(4, 3, 8, 11), Rect2i(3, 4, 10, 9), Rect2i(2, 6, 12, 5)], 3, [col("b7b768"), col("747c37"), col("53612e")])
			for y in range(5, 13):
				_px(img, 8, y, col("53612e"))
			for p in [Vector2i(6, 6), Vector2i(5, 8), Vector2i(10, 6), Vector2i(11, 8), Vector2i(6, 11), Vector2i(10, 11)]:
				_px(img, p.x, p.y, col("53612e"))
			_px(img, 5, 5, col("dbcc83"))
		"mint":  # a sprig: stem and three leaf pairs
			_rect(img, Rect2i(7, 1, 2, 15), ink)
			_rect(img, Rect2i(8, 2, 1, 13), col("275e4c"))
			for i in 3:
				var y := 2 + i * 4
				var w := 5 - i
				for leaf in [Rect2i(7 - w, y, w, 4), Rect2i(9, y + 1, w, 4)]:
					_rect(img, leaf, ink)
					_rect(img, Rect2i(leaf.position.x + 1, leaf.position.y + 1, leaf.size.x - 2, 1), col("738c7a"))
					_rect(img, Rect2i(leaf.position.x + 1, leaf.position.y + 2, leaf.size.x - 2, 1), col("4e7664"))
					_px(img, leaf.end.x - 2 if leaf.position.x > 8 else leaf.position.x + 1, leaf.position.y + 1, col("b7b768"))
		_:
			_supply_cache[id] = null
			return null
	var tex := ImageTexture.create_from_image(img)
	_supply_cache[id] = tex
	return tex


## Pixel-exact image of the product (transparent background, palette colours only).
static func render(desc: Dictionary, v: String) -> Image:
	var sz := pixel_size(desc, v)
	var img := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	var a: Dictionary = desc.get("appearance", {})
	var vessel := _vessel(desc)
	var icon := v == "icon"
	var g := _geometry(vessel, icon)
	var tones := _tones(a)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a.get("chunk_seed", 1))
	match vessel:
		"pie":
			_draw_pie(img, g, tones, icon)
		"bread":
			_draw_bread(img, g, tones, a, rng, icon)
		_:
			_draw_jar(img, g, tones, a, rng, icon, vessel)
	return img


# ---------------------------------------------------------------- texture switch

## Hand-drawn layer compositing. Returns null (-> procedural) until the ART-04 layers exist.
func _compose_textures(desc: Dictionary, v: String) -> Image:
	if v == "icon":
		return null  # icon layers are not defined yet
	var shapes := {"jam_jar": "jam", "pickle_jar": "tall", "bottle": "bottle", "pie": "pie", "bread": "bread"}
	var shape: String = shapes.get(_vessel(desc), "jam")
	var out: Image = null
	for layer in ["kap", "dolgu", "parça", "etiket", "kapak"]:
		var path := "res://assets/sprites/jars/layer_%s_%s.png" % [shape, layer]
		if not ResourceLoader.exists(path):
			return null
		var t := load(path) as Texture2D
		if t == null:
			return null
		var li := t.get_image()
		if out == null:
			out = Image.create(li.get_width(), li.get_height(), false, Image.FORMAT_RGBA8)
		out.blend_rect(li, Rect2i(Vector2i.ZERO, li.get_size()), Vector2i.ZERO)
	return out


# ---------------------------------------------------------------- colour helpers

static func _vessel(desc: Dictionary) -> String:
	var a: Dictionary = desc.get("appearance", {})
	return str(a.get("vessel", desc.get("vessel", "jam_jar")))


static func col(hex: String) -> Color:
	return Color.html("#" + hex.trim_prefix("#"))


## Snaps any hex to the nearest palette colour (render is palette-safe even for odd input).
static func snap(hex: String) -> Color:
	var key := hex.trim_prefix("#").to_lower()
	if _snap_cache.has(key):
		return _snap_cache[key]
	var c := col(key)
	var best := c
	var best_d := 1e9
	for p in PALETTE:
		var pc := col(p)
		var d := pow(pc.r - c.r, 2) + pow(pc.g - c.g, 2) + pow(pc.b - c.b, 2)
		if d < best_d:
			best_d = d
			best = pc
	_snap_cache[key] = best
	return best


static func _tones(a: Dictionary) -> Array:
	var f: Array = a.get("fill", [])
	var defaults := [GOLD_MID, BARK_MID, BARK_DK]
	var out: Array = []
	for i in 3:
		out.append(snap(str(f[i])) if i < f.size() else snap(defaults[i]))
	return out


static func _is_light(c: Color) -> bool:
	return c.get_luminance() > 0.45


# ---------------------------------------------------------------- pixel primitives

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, r: Rect2i, c: Color) -> void:
	img.fill_rect(r.intersection(Rect2i(0, 0, img.get_width(), img.get_height())), c)


static func _geometry(vessel: String, icon: bool) -> Dictionary:
	# Rect arrays are unioned into the silhouette; chamfered corners come from overlapping rects.
	match vessel:
		"pickle_jar":
			if icon:
				return {"lid": Rect2i(3, 1, 10, 3), "shape": [Rect2i(4, 4, 8, 12), Rect2i(3, 5, 10, 10)], "label": Rect2i(5, 7, 6, 6), "fill_top": 7}
			return {"lid": Rect2i(5, 1, 14, 4), "shape": [Rect2i(5, 5, 14, 19), Rect2i(4, 6, 16, 17)], "label": Rect2i(7, 10, 10, 9), "fill_top": 8}
		"bottle":
			if icon:
				return {"lid": Rect2i(6, 0, 4, 3), "shape": [Rect2i(6, 3, 4, 5), Rect2i(4, 8, 8, 8), Rect2i(3, 9, 10, 6)], "label": Rect2i(5, 9, 6, 5), "fill_top": 5}
			return {"lid": Rect2i(9, 2, 6, 5), "shape": [Rect2i(9, 7, 6, 11), Rect2i(7, 17, 10, 2), Rect2i(6, 19, 12, 28), Rect2i(5, 21, 14, 24)], "label": Rect2i(8, 26, 8, 14), "fill_top": 14}
		"pie":
			if icon:
				return {"dish": Rect2i(1, 10, 14, 5), "dome": [Rect2i(4, 6, 8, 1), Rect2i(3, 7, 10, 1), Rect2i(2, 8, 12, 2)]}
			return {"dish": Rect2i(1, 15, 22, 7), "dome": [Rect2i(7, 9, 10, 1), Rect2i(5, 10, 14, 1), Rect2i(3, 11, 18, 1), Rect2i(2, 12, 20, 3)]}
		"bread":
			if icon:
				return {"shape": [Rect2i(4, 4, 8, 1), Rect2i(2, 5, 12, 1), Rect2i(1, 6, 14, 5), Rect2i(2, 11, 12, 1), Rect2i(4, 12, 8, 1)]}
			return {"shape": [Rect2i(7, 6, 10, 1), Rect2i(4, 7, 16, 1), Rect2i(3, 8, 18, 1), Rect2i(2, 9, 20, 8), Rect2i(3, 17, 18, 1), Rect2i(4, 18, 16, 1), Rect2i(6, 19, 12, 1)]}
		_:
			if icon:
				return {"lid": Rect2i(2, 2, 12, 4), "shape": [Rect2i(2, 6, 12, 10), Rect2i(1, 7, 14, 8)], "label": Rect2i(4, 9, 8, 5), "fill_top": 8}
			return {"lid": Rect2i(3, 3, 18, 5), "shape": [Rect2i(3, 8, 18, 16), Rect2i(2, 9, 20, 14)], "label": Rect2i(5, 12, 14, 8), "fill_top": 11}


static func _mask(img: Image, rects: Array) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var m := PackedByteArray()
	m.resize(w * h)
	for r: Rect2i in rects:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if x >= 0 and y >= 0 and x < w and y < h:
					m[y * w + x] = 1
	return m


static func _in(m: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h and m[y * w + x] == 1


static func _is_edge(m: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	return not (_in(m, w, h, x - 1, y) and _in(m, w, h, x + 1, y) and _in(m, w, h, x, y - 1) and _in(m, w, h, x, y + 1))


## Outline + glass + 3-tone fill + highlight for a union-of-rects silhouette.
static func _paint_silhouette(img: Image, rects: Array, fill_top: int, tones: Array) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var m := _mask(img, rects)
	var ink := col(INK)
	var glass := col(GLASS)
	for y in h:
		var first := -1
		var last := -1
		for x in w:
			if _in(m, w, h, x, y) and not _is_edge(m, w, h, x, y):
				if first < 0:
					first = x
				last = x
		for x in w:
			if not _in(m, w, h, x, y):
				continue
			if _is_edge(m, w, h, x, y):
				img.set_pixel(x, y, ink)
				continue
			var c := glass
			if y >= fill_top:
				c = tones[1]
				if x == first or (x == first + 1 and last - first > 6):
					c = tones[0]
				elif x >= last - 1 and last - first > 4:
					c = tones[2]
				if y == fill_top:
					c = tones[0]
				elif _is_edge(m, w, h, x, y + 1) or _is_edge(m, w, h, x, y + 2):
					c = tones[2]
			img.set_pixel(x, y, c)
		if first >= 0 and y >= fill_top + 2 and y <= fill_top + 4 and last - first > 4:
			img.set_pixel(first, y, col(CREAM_HI))


static func _paint_lid(img: Image, r: Rect2i, a: Dictionary, vessel: String) -> void:
	var ink := col(INK)
	if str(a.get("lid", "metal")) == "cloth":
		var lc: Array = a.get("lid_colors", [])
		var c0 := snap(str(lc[0])) if lc.size() > 0 else col(CREAM_HI)
		var c1 := snap(str(lc[1])) if lc.size() > 1 else col("c94d2e")
		var cr := Rect2i(r.position.x - 1, r.position.y, r.size.x + 2, r.size.y)
		_rect(img, cr, ink)
		for y in range(cr.position.y + 1, cr.end.y - 1):
			for x in range(cr.position.x + 1, cr.end.x - 1):
				var odd := (((x - cr.position.x - 1) >> 1) + ((y - cr.position.y - 1) >> 1)) % 2 == 1
				img.set_pixel(x, y, c1 if odd else c0)
		var sy := cr.end.y - 1  # string
		for x in range(cr.position.x + 1, cr.end.x - 1):
			_px(img, x, sy, col(BARK_MID))
	else:
		_rect(img, r, ink)
		var base := col(GOLD_MID)
		var hi := col(GOLD_HI)
		var lo := col(GOLD_LO)
		if vessel == "bottle":
			base = col(BARK_MID)
			hi = col(CREAM_HI)
			lo = col(BARK_DK)
		_rect(img, Rect2i(r.position.x + 1, r.position.y + 1, r.size.x - 2, r.size.y - 2), base)
		_rect(img, Rect2i(r.position.x + 1, r.position.y + 1, r.size.x - 2, 1), hi)
		_rect(img, Rect2i(r.position.x + 1, r.end.y - 2, r.size.x - 2, 1), lo)


static func _paint_label(img: Image, r: Rect2i, a: Dictionary, icon: bool) -> void:
	var ink := col(INK)
	var lc := snap(str(a.get("label_color", CREAM_HI)))
	var shape := int(a.get("label_shape", 0))
	_rect(img, r, ink)
	var inner := Rect2i(r.position + Vector2i.ONE, r.size - Vector2i(2, 2))
	_rect(img, inner, lc)
	match shape:
		1:  # rounded: soften the corners
			for p in [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
				_px(img, p.x, p.y, ink)
			_px(img, inner.position.x, inner.position.y, ink)
			_px(img, inner.end.x - 1, inner.position.y, ink)
			_px(img, inner.position.x, inner.end.y - 1, ink)
			_px(img, inner.end.x - 1, inner.end.y - 1, ink)
		2:  # banner: notched short sides
			var my := r.position.y + r.size.y / 2
			_px(img, r.position.x + 1, my, ink)
			_px(img, r.end.x - 2, my, ink)
			if not icon:
				_px(img, r.position.x + 2, my, lc)
				_px(img, r.end.x - 3, my, lc)
	var mc := ink if _is_light(lc) else col(CREAM_HI)
	var cx := inner.position.x + inner.size.x / 2
	var cy := inner.position.y + inner.size.y / 2
	if inner.size.x < 7 or inner.size.y < 5:
		_px(img, cx, cy, mc)
		return
	match str(a.get("motif", "leaf")):
		"star":
			for p in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				_px(img, cx + p.x, cy + p.y, mc)
		"stripe":
			var half := mini(inner.size.x / 2 - 1, 4)
			_rect(img, Rect2i(cx - half, cy - 1, half * 2 + 1, 1), mc)
			_rect(img, Rect2i(cx - half, cy + 1, half * 2 + 1, 1), mc)
		_:  # leaf
			var leaf := col(LEAF_RED) if _is_light(lc) else col(PEACH)
			for p in [Vector2i(-1, 1), Vector2i(0, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(1, 0)]:
				_px(img, cx + p.x, cy + p.y, leaf)


static func _paint_chunks(img: Image, area: Rect2i, avoid: Rect2i, kind: String, tones: Array, rng: RandomNumberGenerator, icon: bool, count: int) -> void:
	var light: Color = tones[0]
	var dark: Color = tones[2]
	var k := kind.to_lower()
	var variant := 0
	if k.contains("ring") or k.contains("slice") or k.contains("cucum"):
		variant = 1
	elif k.contains("seed") or k.contains("speck") or k.contains("dot") or k.contains("crumb"):
		variant = 2
	elif k.contains("mush") or k.contains("cap"):
		variant = 3
	elif k == "none" or k == "smooth":
		variant = 4
	if icon and variant != 4:
		variant = 2
	var hold := avoid.grow(1) if avoid.size.x > 0 else Rect2i()
	for i in count:
		for attempt in 4:
			var x := area.position.x + rng.randi_range(0, maxi(area.size.x - 3, 0))
			var y := area.position.y + rng.randi_range(0, maxi(area.size.y - 3, 0))
			if hold.size.x > 0 and hold.intersects(Rect2i(x, y, 3, 3)):
				continue
			match variant:
				1:
					_rect(img, Rect2i(x, y, 3, 3), light)
					_px(img, x + 1, y + 1, dark)
				2:
					_px(img, x, y, col(CREAM_HI))
					_px(img, x + 1, y + 1, dark)
				3:
					_rect(img, Rect2i(x, y, 3, 2), col(CREAM_LO))
					_px(img, x + 1, y + 2, col(CREAM_HI))
					_px(img, x, y, dark)
				4:
					pass
				_:
					_rect(img, Rect2i(x, y, 2, 2), dark)
					_px(img, x, y, light)
			break


# ---------------------------------------------------------------- vessels

static func _draw_jar(img: Image, g: Dictionary, tones: Array, a: Dictionary, rng: RandomNumberGenerator, icon: bool, vessel: String) -> void:
	var rects: Array = g["shape"]
	var fill_top: int = g["fill_top"]
	_paint_silhouette(img, rects, fill_top, tones)
	var label: Rect2i = g["label"]
	var bb: Rect2i = rects[0]
	for r: Rect2i in rects:
		bb = bb.merge(r)
	var area := Rect2i(bb.position.x + 2, fill_top + 2, bb.size.x - 4, bb.end.y - fill_top - 4)
	var count := 3 if icon else (area.size.x * area.size.y) / 12
	_paint_chunks(img, area, label, str(a.get("chunk", "")), tones, rng, icon, count)
	_paint_label(img, label, a, icon)
	_paint_lid(img, g["lid"], a, vessel)


static func _draw_pie(img: Image, g: Dictionary, tones: Array, icon: bool) -> void:
	var ink := col(INK)
	var dish: Rect2i = g["dish"]
	var dome: Array = g["dome"]
	var rects: Array = [dish, Rect2i(dish.position.x + 1, dish.end.y, dish.size.x - 2, 1)]
	rects.append_array(dome)
	var w := img.get_width()
	var h := img.get_height()
	var m := _mask(img, rects)
	var crust := [col(GOLD_MID), col(BARK_MID), col(GOLD_LO)]
	var dome_top: int = (dome[0] as Rect2i).position.y
	for y in h:
		for x in w:
			if not _in(m, w, h, x, y):
				continue
			if _is_edge(m, w, h, x, y):
				img.set_pixel(x, y, ink)
			elif y >= dish.position.y:
				var idx := 0 if y == dish.position.y + 1 else (1 if y < dish.end.y - 1 else 2)
				img.set_pixel(x, y, crust[idx])
			else:
				var lattice := ((x + y) % 4 == 0) or ((x - y + 40) % 4 == 0)
				img.set_pixel(x, y, crust[1] if lattice else (tones[0] if y == dome_top + 1 else tones[1]))
	if not icon:
		for x in range(dish.position.x + 3, dish.end.x - 2, 4):
			_px(img, x, dish.position.y + 3, col(BARK_DK))
	_px(img, dish.position.x + 2, dish.position.y + 1, col(CREAM_HI))


static func _draw_bread(img: Image, g: Dictionary, tones: Array, a: Dictionary, rng: RandomNumberGenerator, icon: bool) -> void:
	var rects: Array = g["shape"]
	var bb: Rect2i = rects[0]
	for r: Rect2i in rects:
		bb = bb.merge(r)
	_paint_silhouette(img, rects, bb.position.y + 1, tones)
	var hi := col(CREAM_HI)
	for i in (2 if icon else 3):
		var x := bb.position.x + (4 if icon else 5) + i * (3 if icon else 5)
		var y := bb.position.y + (3 if icon else 4)
		_px(img, x, y, hi)
		_px(img, x + 1, y + 1, hi)
		if not icon:
			_px(img, x + 2, y + 2, hi)
	var kind := "seed" if str(a.get("chunk", "")) not in ["none", "smooth"] else "none"
	var area := Rect2i(bb.position.x + 3, bb.position.y + 1, bb.size.x - 6, 2)
	_paint_chunks(img, area, Rect2i(), kind, tones, rng, icon, 1 if icon else 4)
