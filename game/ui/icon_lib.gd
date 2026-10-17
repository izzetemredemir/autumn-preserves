class_name IconLib
extends RefCounted
## SPECIES-GEN · One resolver for 16x16 ingredient icons: IconLib.ingredient(type) -> Texture2D.
## A base type: its file icon (res://assets/sprites/icons/<type>.png), null when there is none. A generated species
## (SpeciesGen row with "template"): its template (res://assets/masks/species/<template>.png, a 5-gray value map made
## by tools/procedural/species_templates.py) recoloured with the species ramp into an ImageTexture: gray 0 on the
## silhouette edge -> ink 111010, gray 0 inside -> ramp[0], 64 / 128 / 192 / 255 -> ramp[1..4]. Ramps hold palette
## colours only, so the icon is palette-clean by construction. Cached per type (never a miss: a species may register
## later). bush(type, bare): the blackberry bush with its berries recoloured the same way (fruit species in the forest).

const FILE := "res://assets/sprites/icons/%s.png"
const TEMPLATE := "res://assets/masks/species/%s.png"
const BUSH := "res://assets/sprites/forest/bush_blackberry_%s.png"
const INK := "111010"
## Berry tones of the blackberry bush -> species ramp index (the leaves and the ink stay).
const BERRY_TONES := {"23282a": 0, "3d1f29": 1, "62272c": 2, "a22512": 3, "81746a": 3, "b9a697": 4}

static var _icons := {}
static var _bushes := {}
static var _templates := {}


static func ingredient(type: String) -> Texture2D:
	if _icons.has(type):
		return _icons[type]
	var tex: Texture2D = null
	if is_generated(type):
		var img := image(type)
		if img != null:
			tex = ImageTexture.create_from_image(img)
	elif type != "" and ResourceLoader.exists(FILE % type):
		tex = load(FILE % type) as Texture2D
	if tex != null:
		_icons[type] = tex
	return tex


## True for a generated species (its icon is a recoloured template).
static func is_generated(type: String) -> bool:
	return Data.ingredients().get(type, {}).has("template")


## The species icon as a 16x16 RGBA8 image, null for other types.
static func image(type: String) -> Image:
	var row: Dictionary = Data.ingredients().get(type, {})
	if not row.has("template"):
		return null
	return recolor(template(String(row.template)), row.get("ramp", []))


## A template value map as an RGBA8 image (null when missing).
static func template(template_name: String) -> Image:
	if _templates.has(template_name):
		return _templates[template_name]
	var img: Image = null
	var path := TEMPLATE % template_name
	if ResourceLoader.exists(path):
		img = _rgba((load(path) as Texture2D).get_image())
	_templates[template_name] = img
	return img


## Value map x 5-tone ramp -> image (see the header for the mapping).
static func recolor(tpl: Image, ramp: Array) -> Image:
	if tpl == null or ramp.size() < 5:
		return null
	var w := tpl.get_width()
	var h := tpl.get_height()
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var ink := Color.html(INK)
	for y in h:
		for x in w:
			var p := tpl.get_pixel(x, y)
			if p.a < 0.5:
				continue
			var lv := clampi(roundi(p.r * 255.0 / 64.0), 0, 4)
			out.set_pixel(x, y, ink if lv == 0 and _edge(tpl, x, y) else Color.html(String(ramp[lv])))
	return out


## Fruit species bushes: the ripe blackberry bush with species-coloured berries; bare: the plain bare bush.
static func bush(type: String, bare: bool) -> Texture2D:
	if bare:
		return load(BUSH % "bare") as Texture2D if ResourceLoader.exists(BUSH % "bare") else null
	if _bushes.has(type):
		return _bushes[type]
	var ramp: Array = Data.ingredients().get(type, {}).get("ramp", [])
	if ramp.size() < 5 or not ResourceLoader.exists(BUSH % "ripe"):
		return null
	var img := _rgba((load(BUSH % "ripe") as Texture2D).get_image())
	if img == null:
		return null
	var map := {}
	for hex: String in BERRY_TONES:
		map[Color.html(hex).to_html(false)] = Color.html(String(ramp[int(BERRY_TONES[hex])]))
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a < 0.5:
				continue
			var key := p.to_html(false)
			if map.has(key):
				img.set_pixel(x, y, map[key])
	var tex := ImageTexture.create_from_image(img)
	_bushes[type] = tex
	return tex


static func _edge(img: Image, x: int, y: int) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx := x + d.x
		var ny := y + d.y
		if nx < 0 or ny < 0 or nx >= img.get_width() or ny >= img.get_height() or img.get_pixel(nx, ny).a < 0.5:
			return true
	return false


static func _rgba(img: Image) -> Image:
	if img == null or img.is_empty():
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img
