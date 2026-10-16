extends RefCounted
## GD-KITCHEN · Placeholder art for the kitchen, drawn from Vintage Autumn 31 palette rects only.
## background(): the room shell (wall, window, wainscot, floor) as one 480x270 image; ART-05's bg_kitchen.png
## replaces it. draw_object(): the clickable objects (art-bible §3.7: objects sit on top of the background).
## icon(): 16x16 ingredient and cupboard icons from res://assets/sprites/icons/icons.json + icons.png.

const INK := Color("111010")
const CREAM := Color("f2d9c5")
const CREAM_LO := Color("b9a697")
const GOLD := Color("e5bd7f")
const GOLD_PALE := Color("dbcc83")
const AMBER := Color("b66813")
const TAN := Color("c58845")
const BROWN := Color("83571e")
const BARK := Color("50361e")
const PLUM := Color("3d1f29")
const WINE := Color("62272c")
const RED := Color("a22512")
const RED_HI := Color("c94d2e")
const PEACH := Color("e19064")
const IRON := Color("2e3f3f")
const IRON_DK := Color("23282a")
const STONE := Color("49423d")
const MUTED := Color("81746a")
const GLASS := Color("b4b3a0")
const SLATE := Color("567c7d")
const SLATE_DK := Color("415c5d")
const TEAL := Color("4e7664")
const TEAL_DK := Color("275e4c")
const OLIVE := Color("747c37")
const OLIVE_DK := Color("53612e")
const FOREST := Color("314524")

## Hit rects of the room objects (480x270 design space, >=16 px each). Granny's To-Do note covers the top right
## (x >= 250, y < 150) on days 1-2, so everything with numbers on it sits left of x=250; the doors and the bed
## on the right are tall enough to stay visible and clickable under the note.
const OBJECTS := {
	"stove": Rect2i(4, 64, 76, 136),
	"pantry": Rect2i(88, 100, 78, 56),
	"counter": Rect2i(170, 100, 78, 56),
	"book": Rect2i(254, 80, 26, 20),
	"cupboard": Rect2i(288, 40, 72, 52),
	"garden": Rect2i(430, 70, 48, 134),
	"bed": Rect2i(392, 204, 70, 32),
}
## Hotspots sit on the painted bg_kitchen.png: stove (left), bench drawers (pantry, jar counter), recipe book on
## the bench end, tall cupboard, front door (garden), rug by the door (bed). Their art is the painting; only the
## book and the pantry's inbox tag are drawn. When no painting loads, Kitchen sets `painted = false` and the
## placeholder objects below draw instead.
static var painted := true
## P1 stations (spec §8.3), drawn on top of the painting once unlocked (Economy.unlocked): the fruit press on the
## floor right of the stove, the dough board on a little table in the window light. Kitchen shows each when its
## unlock id (UNLOCK_OF) is set.
const P1_OBJECTS := {
	"press": Rect2i(112, 158, 44, 60),
	"board": Rect2i(322, 150, 56, 46),
}
const UNLOCK_OF := {"press": "press", "board": "knead"}
## Window sill over the bench where the waiting jars stand (WaitingShelf).
const SILL := Rect2i(124, 66, 76, 38)
const ICONS_JSON := "res://assets/sprites/icons/icons.json"
const ICONS_PNG := "res://assets/sprites/icons/icons.png"
## The theme font at its native size (the only size besides 36 that stays crisp).
const FONT := preload("res://assets/fonts/m6x11plus.ttf")
const FONT_SIZE := 18

static var _icons: Dictionary = {}
static var _icon_cells: Dictionary = {}


# ---------------------------------------------------------------- icons

## 16x16 icon for an ingredient type, nut, cupboard item or add-in id; null when the atlas has none.
static func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	if _icon_cells.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ICONS_JSON))
		if typeof(parsed) == TYPE_DICTIONARY:
			_icon_cells = parsed
	var tex: Texture2D = null
	var cells: Dictionary = _icon_cells.get("icons", {})
	if cells.has(id) and ResourceLoader.exists(ICONS_PNG):
		var cell: Array = _icon_cells.get("cell", [16, 16])
		var at := AtlasTexture.new()
		at.atlas = load(ICONS_PNG)
		at.region = Rect2(int(cells[id][0]) * int(cell[0]), int(cells[id][1]) * int(cell[1]), int(cell[0]), int(cell[1]))
		tex = at
	if tex == null:
		tex = JarIcon.supply_icon(id)  # P1 supplies (bottle, flour, cabbage) until the atlas has them
	_icons[id] = tex
	return tex


## Icon ids for a recipe slot spec ({"groups"} or {"types"}): its types, or the first P0 types of each group.
static func slot_icon_ids(spec: Variant, max_n: int) -> Array:
	var out: Array = []
	if typeof(spec) != TYPE_DICTIONARY:
		return out
	if spec.has("types"):
		for t in spec.types:
			if icon(String(t)) != null:  # P1 types without an icon yet (grape) are left out
				out.append(String(t))
	elif spec.has("groups"):
		var ings := Data.ingredients()
		for t in Data.ids_up_to("ingredients", 0):
			if ings[t].group in spec.groups:
				out.append(t)
	return out.slice(0, max_n)


## Cupboard contents: base items the grocer sells (Economy.on_sale: P0 + live P1 rows such as bottle and flour),
## then shop add-ins (P0), in data order.
static func cupboard_ids() -> Array:
	var out: Array = []
	var addins := Data.addins()
	var buy: Dictionary = Data.shop().get("buy", {})
	for id in buy:
		var row: Variant = buy[id]
		var live := Economy.on_sale(id, row) if typeof(row) == TYPE_DICTIONARY else true
		if live and not addins.has(id):
			out.append(id)
	for id in addins:
		if addins[id].source == "shop" and int(addins[id].priority) == 0:
			out.append(id)
	return out


# ---------------------------------------------------------------- background

## Room shell, palette only, no alpha. Interaction spots are left plain (objects are drawn on top).
static func background() -> ImageTexture:
	var img := Image.create(480, 270, false, Image.FORMAT_RGBA8)
	img.fill(BROWN)
	_r(img, 0, 0, 480, 8, BARK)
	_r(img, 0, 8, 480, 1, PLUM)
	for x in range(12, 480, 24):  # wallpaper: thin stripes with small amber flowers between
		_r(img, x, 9, 1, 139, BARK)
		for y in range(21, 146, 24):
			_r(img, x + 12, y, 1, 1, AMBER)
			_r(img, x + 11, y + 1, 3, 1, AMBER)
			_r(img, x + 12, y + 2, 1, 1, AMBER)
	_window(img)
	_herbs(img)
	_r(img, 92, 40, 30, 24, BARK)  # little framed picture over the stove: hills and a sun
	_r(img, 94, 42, 26, 20, SLATE)
	_r(img, 94, 54, 26, 8, OLIVE)
	_r(img, 98, 52, 10, 2, OLIVE)
	_r(img, 112, 45, 4, 4, GOLD)
	_r(img, 106, 36, 2, 4, BARK)
	_r(img, 0, 148, 480, 3, TAN)  # wainscot rail + boards
	_r(img, 0, 148, 480, 1, GOLD)
	_r(img, 0, 151, 480, 45, BARK)
	for x in range(8, 480, 16):
		_r(img, x, 151, 1, 45, PLUM)
	_r(img, 0, 196, 480, 2, PLUM)
	_r(img, 0, 198, 480, 72, WINE)  # floor planks
	for row in 8:
		var y0 := 198 + row * 9
		_r(img, 0, y0 + 8, 480, 1, PLUM)
		for x in range((row * 37) % 111, 480, 111):
			_r(img, x, y0, 1, 8, PLUM)
	_rug(img, 96, 216, 148, 20)
	return ImageTexture.create_from_image(img)


static func _window(img: Image) -> void:
	_r(img, 158, 30, 100, 2, BARK)  # curtain rod
	_r(img, 172, 34, 72, 66, BARK)
	_r(img, 175, 37, 66, 63, SLATE)
	_r(img, 175, 37, 66, 6, SLATE_DK)
	_r(img, 175, 55, 66, 3, GOLD_PALE)
	_r(img, 175, 58, 66, 8, PEACH)
	_r(img, 175, 66, 66, 34, OLIVE_DK)
	for i in 5:  # hills and autumn trees
		var x := 176 + i * 13
		_r(img, x, 62 + (i * 5) % 6, 11, 6, OLIVE_DK)
		_r(img, x + 2, 70 + (i * 3) % 5, 8, 7, RED_HI if i % 2 == 0 else AMBER)
		_r(img, x + 3, 68 + (i * 3) % 5, 6, 2, PEACH if i % 2 == 0 else GOLD)
		_r(img, x + 5, 77 + (i * 3) % 5, 1, 4, BARK)
	_r(img, 175, 86, 66, 14, FOREST)
	_r(img, 207, 37, 2, 63, BARK)  # mullions
	_r(img, 175, 64, 66, 2, BARK)
	_r(img, 178, 40, 2, 6, CREAM_LO)  # glass glint
	_r(img, 212, 40, 2, 4, CREAM_LO)
	for side in [164, 242]:  # curtains
		_r(img, side, 32, 10, 54, RED)
		_r(img, side + 3, 32, 1, 54, RED_HI)
		_r(img, side + 7, 32, 1, 54, WINE)
		_r(img, side + 1, 86, 8, 2, RED_HI)


static func _herbs(img: Image) -> void:
	_r(img, 8, 76, 54, 2, BARK)
	for i in 3:
		var x := 12 + i * 12
		_r(img, x + 2, 78, 1, 3, BARK)
		_r(img, x, 81, 5, 3, OLIVE)
		_r(img, x + 1, 84, 3, 4, OLIVE_DK)
		_r(img, x + 2, 88, 1, 2, OLIVE_DK)
	_r(img, 52, 78, 2, 6, BARK)  # little copper pan
	_r(img, 48, 84, 10, 8, AMBER)
	_r(img, 49, 85, 2, 5, PEACH)
	_r(img, 48, 91, 10, 1, BROWN)


static func _rug(img: Image, x: int, y: int, w: int, h: int) -> void:
	_r(img, x, y, w, h, RED)
	_r(img, x + 2, y + 2, w - 4, 1, PEACH)
	_r(img, x + 2, y + h - 3, w - 4, 1, PEACH)
	for i in range(8, w - 8, 12):
		_r(img, x + i, y + 6, 4, h - 12, RED_HI)
	for i in range(1, h, 2):
		_r(img, x - 2, y + i, 2, 1, CREAM_LO)
		_r(img, x + w, y + i, 2, 1, CREAM_LO)


static func _r(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)


# ---------------------------------------------------------------- objects

## Draws object `kind` into `ci` in its local space. `t` = seconds (animation), `info` = live numbers.
static func draw_object(ci: CanvasItem, kind: String, t: float, info: Dictionary) -> void:
	if kind == "press":  # P1 stations are not in the painting: always drawn
		_press(ci)
		return
	if kind == "board":
		_board(ci)
		return
	if painted:
		if kind == "book":
			_book(ci)
		elif kind == "pantry" and int(info.get("inbox", 0)) > 0:
			_tag(ci, 28, 8, int(info.inbox))
		return
	match kind:
		"garden":
			_door_garden(ci)
		"stove":
			_stove(ci, t)
		"counter":
			_counter(ci)
		"book":
			_book(ci)
		"cupboard":
			_cupboard(ci, info.get("cupboard", {}))
		"pantry":
			_door_pantry(ci, int(info.get("inbox", 0)))
		"bed":
			_bed(ci, OBJECTS.bed.size.x)


static func _d(ci: CanvasItem, x: int, y: int, w: int, h: int, c: Color) -> void:
	ci.draw_rect(Rect2(x, y, w, h), c)


## 1-px frame (filled rects, so it stays on whole pixels).
static func frame(ci: CanvasItem, rect: Rect2i, c: Color) -> void:
	_d(ci, rect.position.x, rect.position.y, rect.size.x, 1, c)
	_d(ci, rect.position.x, rect.end.y - 1, rect.size.x, 1, c)
	_d(ci, rect.position.x, rect.position.y, 1, rect.size.y, c)
	_d(ci, rect.end.x - 1, rect.position.y, 1, rect.size.y, c)


## Small down arrow (7x4) with an ink edge, for "do this next" hints.
static func arrow(ci: CanvasItem, x: int, y: int, c: Color) -> void:
	for i in 4:
		_d(ci, x - 4 + i, y + i - 1, 9 - i * 2, 1, INK)
	for i in 4:
		_d(ci, x - 3 + i, y + i, 7 - i * 2, 1, c)


## Text (baseline at pos) with a 1-px ink shadow, like the theme labels.
static func text(ci: CanvasItem, pos: Vector2i, s: String, width: int, c: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	ci.draw_string(FONT, Vector2(pos + Vector2i(1, 1)), s, align, width, FONT_SIZE, INK)
	ci.draw_string(FONT, Vector2(pos), s, align, width, FONT_SIZE, c)


static func _door_garden(ci: CanvasItem) -> void:
	_d(ci, 0, 0, 36, 102, PLUM)
	_d(ci, 3, 3, 30, 97, TEAL)
	_d(ci, 7, 8, 22, 28, TEAL_DK)
	_d(ci, 8, 9, 20, 26, SLATE)
	_d(ci, 8, 9, 20, 9, PEACH)
	_d(ci, 17, 9, 2, 26, TEAL_DK)
	_d(ci, 8, 21, 20, 2, TEAL_DK)
	_d(ci, 10, 25, 2, 6, CREAM_LO)
	for y in [44, 72]:
		_d(ci, 6, y, 24, 22, TEAL_DK)
		_d(ci, 8, y + 2, 20, 18, TEAL)
	_d(ci, 27, 60, 3, 3, GOLD)
	_d(ci, 0, 100, 36, 2, BARK)


static func _stove(ci: CanvasItem, t: float) -> void:
	_d(ci, 66, -76, 8, 72, IRON_DK)  # stovepipe
	_d(ci, 67, -76, 1, 72, IRON)
	_d(ci, 64, -6, 12, 4, IRON)
	for i in 3:  # steam
		var ph := fmod(t * 0.5 + i / 3.0, 1.0)
		if ph < 0.85:
			var sx := 24 + i * 9 + roundi(sin(ph * 6.0 + i) * 2.0)
			_d(ci, sx, roundi(2.0 - ph * 20.0), 2, 2, CREAM_LO if ph < 0.5 else GLASS)
	_d(ci, 14, 3, 42, 3, GOLD)  # copper pot
	_d(ci, 16, 6, 38, 16, AMBER)
	_d(ci, 16, 18, 38, 4, BROWN)
	_d(ci, 20, 8, 2, 8, PEACH)
	_d(ci, 10, 9, 6, 3, BROWN)
	_d(ci, 54, 9, 6, 3, BROWN)
	_d(ci, 0, 22, 84, 6, STONE)  # top plate and body
	_d(ci, 0, 22, 84, 1, MUTED)
	_d(ci, 3, 28, 78, 80, IRON)
	_d(ci, 3, 28, 1, 80, IRON_DK)
	_d(ci, 80, 28, 1, 80, IRON_DK)
	_d(ci, 10, 38, 36, 30, IRON_DK)  # firebox
	_d(ci, 13, 48, 30, 16, PLUM)
	var f := int(t * 8.0)
	for c in 15:
		var h := 4 + (c * 7 + f * 3) % 7
		_d(ci, 13 + c * 2, 64 - h, 2, h, RED_HI)
		_d(ci, 13 + c * 2, 64 - (h >> 1), 2, h >> 1, PEACH)
	_d(ci, 13, 62, 30, 2, GOLD)
	for i in 4:
		_d(ci, 18 + i * 6, 48, 1, 16, IRON_DK)
	_d(ci, 50, 38, 26, 42, IRON_DK)  # oven door
	_d(ci, 52, 40, 22, 38, IRON)
	_d(ci, 54, 44, 18, 2, GLASS)
	_d(ci, 10, 74, 36, 12, IRON_DK)  # ash drawer
	_d(ci, 22, 79, 12, 2, GLASS)
	_d(ci, 4, 92, 76, 2, GOLD)  # towel bar
	_d(ci, 30, 94, 14, 12, CREAM)
	_d(ci, 30, 100, 14, 2, RED_HI)
	_d(ci, 4, 108, 6, 6, IRON_DK)
	_d(ci, 74, 108, 6, 6, IRON_DK)


static func _counter(ci: CanvasItem) -> void:
	for x in [6, 20, 34]:  # empty jars waiting on top
		_d(ci, x, -13, 10, 2, GOLD)
		_d(ci, x, -11, 10, 11, GLASS)
		_d(ci, x + 1, -10, 8, 9, SLATE_DK)
		_d(ci, x + 2, -9, 1, 5, CREAM)
	_d(ci, 0, 0, 80, 6, TAN)
	_d(ci, 0, 0, 80, 1, GOLD)
	_d(ci, 0, 6, 80, 2, BROWN)
	_d(ci, 2, 8, 76, 50, BROWN)
	for x in [6, 42]:
		_d(ci, x, 12, 32, 42, AMBER)
		_d(ci, x + 3, 15, 26, 36, BROWN)
		_d(ci, x + 4, 16, 24, 34, AMBER)
	_d(ci, 33, 31, 2, 4, GOLD)
	_d(ci, 45, 31, 2, 4, GOLD)
	_d(ci, 0, 58, 80, 4, BARK)


static func _book(ci: CanvasItem) -> void:
	_d(ci, 0, 16, 26, 3, RED)  # cover under open pages
	_d(ci, 0, 16, 26, 1, RED_HI)
	_d(ci, 1, 4, 11, 12, CREAM)
	_d(ci, 14, 4, 11, 12, CREAM)
	_d(ci, 12, 4, 2, 12, CREAM_LO)
	for i in 3:
		_d(ci, 3, 7 + i * 3, 7, 1, MUTED)
		_d(ci, 16, 7 + i * 3, 7, 1, MUTED)
	_d(ci, 18, 13, 3, 3, RED_HI)  # a little jar sketch
	_d(ci, 19, 2, 2, 4, GOLD)  # ribbon
	_d(ci, 10, 19, 6, 1, BROWN)


## Spice-rack sideboard: every cupboard item with its count (0 base items in red: the grocer sells them).
static func _cupboard(ci: CanvasItem, cupboard: Dictionary) -> void:
	_d(ci, 0, 0, 68, 4, TAN)
	_d(ci, 0, 0, 68, 1, GOLD)
	_d(ci, 0, 4, 68, 1, BARK)
	_d(ci, 1, 5, 66, 93, BROWN)
	_d(ci, 4, 5, 60, 93, PLUM)
	var ids := cupboard_ids()
	var addins := Data.addins()
	for i in ids.size():
		var x := 5 + (i % 2) * 30
		var y := 6 + int(i / 2.0) * 16
		if i % 2 == 0:
			_d(ci, 4, y + 15, 60, 1, TAN)
		var tex := icon(ids[i])
		if tex != null:
			ci.draw_texture(tex, Vector2(x, y))
		var n := int(cupboard.get(ids[i], 0))
		var c := CREAM
		if n <= 0:
			c = MUTED if addins.has(ids[i]) else RED_HI
		text(ci, Vector2i(x + 17, y + 13), str(n), 12, c, HORIZONTAL_ALIGNMENT_LEFT)


static func _door_pantry(ci: CanvasItem, inbox: int) -> void:
	_d(ci, 0, 0, 40, 102, PLUM)
	_d(ci, 3, 3, 34, 97, AMBER)
	for x in [11, 19, 27]:
		_d(ci, x, 3, 1, 97, BROWN)
	_d(ci, 3, 18, 34, 4, BROWN)
	_d(ci, 3, 78, 34, 4, BROWN)
	for i in 26:  # diagonal brace
		_d(ci, 6 + i, 76 - i * 2, 3, 2, BROWN)
	_d(ci, 3, 20, 7, 2, IRON_DK)
	_d(ci, 3, 80, 7, 2, IRON_DK)
	_d(ci, 30, 60, 3, 3, GOLD)
	_d(ci, 0, 100, 40, 2, BARK)
	if inbox > 0:  # paper tag: how many things just arrived in the basket (below the To-Do note)
		_d(ci, 20, 56, 1, 4, BARK)
		_d(ci, 10, 60, 22, 16, BARK)
		_d(ci, 11, 61, 20, 14, CREAM)
		ci.draw_string(FONT, Vector2(11, 73), str(inbox) if inbox < 10 else "9+", HORIZONTAL_ALIGNMENT_CENTER, 20, FONT_SIZE, BARK)


## Paper tag with the number of things in the pantry basket.
static func _tag(ci: CanvasItem, x: int, y: int, n: int) -> void:
	_d(ci, x, y, 22, 16, BARK)
	_d(ci, x + 1, y + 1, 20, 14, CREAM)
	ci.draw_string(FONT, Vector2(x + 1, y + 13), str(n) if n < 10 else "9+", HORIZONTAL_ALIGNMENT_CENTER, 20, FONT_SIZE, BARK)


static func _bed(ci: CanvasItem, w: int) -> void:
	_d(ci, 0, 0, w, 86, BARK)
	_d(ci, 3, 3, w - 6, 83, PLUM)
	_d(ci, 3, 3, 3, 2, BARK)
	_d(ci, w - 6, 3, 3, 2, BARK)
	_d(ci, w - 34, 12, 7, 7, GOLD_PALE)  # moon and stars through the bedroom window
	_d(ci, w - 32, 12, 5, 5, PLUM)
	_d(ci, w - 50, 10, 1, 1, CREAM)
	_d(ci, w - 16, 24, 1, 1, CREAM)
	_d(ci, 30, 20, 1, 1, CREAM_LO)
	_d(ci, 3, 3, 6, 42, TEAL)  # tied curtain
	_d(ci, 5, 3, 1, 42, TEAL_DK)
	_d(ci, 3, 45, 4, 8, TEAL_DK)
	_d(ci, 12, 38, 6, 44, BROWN)  # headboard
	_d(ci, 12, 38, 6, 1, TAN)
	_d(ci, 18, 56, w - 30, 18, RED)  # quilt
	for cx in range(0, w - 30, 6):
		for cy in range(0, 18, 6):
			if (int(cx / 6.0) + int(cy / 6.0)) % 2 == 0:
				_d(ci, 18 + cx, 56 + cy, 3, 3, RED_HI)
	_d(ci, 18, 74, w - 30, 3, CREAM_LO)
	_d(ci, 20, 49, 16, 7, CREAM)
	_d(ci, 20, 55, 16, 1, CREAM_LO)
	_d(ci, w - 12, 50, 4, 32, BROWN)
	_d(ci, 14, 82, 3, 4, BARK)
	_d(ci, w - 12, 82, 3, 4, BARK)


## Fruit press (44x60): screw and T-handle through a crossbeam, two posts, a slatted cage full of fruit on a tub
## whose spout drips into a waiting bottle.
static func _press(ci: CanvasItem) -> void:
	_d(ci, 7, 1, 30, 4, INK)  # T-handle with gold knobs
	_d(ci, 8, 2, 28, 2, IRON)
	_d(ci, 5, 1, 3, 4, INK)
	_d(ci, 6, 2, 1, 2, GOLD)
	_d(ci, 36, 1, 3, 4, INK)
	_d(ci, 37, 2, 1, 2, GOLD)
	_d(ci, 19, 0, 6, 24, INK)  # screw
	_d(ci, 20, 4, 4, 19, IRON)
	for y in range(5, 22, 3):
		_d(ci, 20, y, 4, 1, IRON_DK)
	_d(ci, 2, 8, 40, 7, INK)  # crossbeam
	_d(ci, 3, 9, 38, 5, BROWN)
	_d(ci, 3, 9, 38, 1, TAN)
	_d(ci, 3, 13, 38, 1, BARK)
	_d(ci, 19, 9, 6, 5, IRON_DK)
	_d(ci, 20, 10, 4, 3, IRON)
	for x in [4, 34]:  # posts
		_d(ci, x, 15, 6, 34, INK)
		_d(ci, x + 1, 15, 4, 33, BROWN)
		_d(ci, x + 1, 15, 1, 33, TAN)
	_d(ci, 11, 22, 22, 4, INK)  # pressing plate
	_d(ci, 12, 23, 20, 2, TAN)
	_d(ci, 12, 26, 20, 19, INK)  # slatted cage, fruit showing between the slats
	_d(ci, 13, 26, 18, 18, WINE)
	for i in 6:
		var fx := 14 + i * 3
		_d(ci, fx, 28 + (i * 5) % 9, 2, 2, RED_HI if i % 2 == 0 else AMBER)
		_d(ci, fx, 36 + (i * 3) % 6, 2, 2, PEACH if i % 2 == 0 else RED)
	for x in range(13, 31, 3):
		_d(ci, x, 26, 2, 18, BROWN)
		_d(ci, x, 26, 1, 18, TAN)
	for y in [28, 40]:  # iron hoops
		_d(ci, 12, y, 20, 2, IRON_DK)
		_d(ci, 12, y, 20, 1, IRON)
	_d(ci, 4, 44, 36, 9, INK)  # tub with a spout
	_d(ci, 5, 45, 34, 7, AMBER)
	_d(ci, 5, 45, 34, 1, GOLD)
	_d(ci, 5, 49, 34, 3, BROWN)
	_d(ci, 8, 45, 1, 7, BROWN)
	_d(ci, 35, 45, 1, 7, BROWN)
	_d(ci, 39, 46, 5, 3, INK)
	_d(ci, 39, 47, 4, 1, TAN)
	_d(ci, 42, 49, 1, 2, RED_HI)  # drip
	for x in [7, 33]:  # legs
		_d(ci, x, 53, 4, 7, INK)
		_d(ci, x + 1, 53, 2, 6, BARK)
	_d(ci, 39, 52, 5, 8, INK)  # little bottle under the spout
	_d(ci, 40, 53, 3, 6, GLASS)
	_d(ci, 40, 56, 3, 3, RED_HI)
	_d(ci, 41, 53, 1, 2, CREAM)


## Dough board (56x46): a little table with a floured board, a dough ball and a rolling pin.
static func _board(ci: CanvasItem) -> void:
	_d(ci, 4, 13, 46, 7, INK)  # board
	_d(ci, 5, 14, 44, 5, GOLD_PALE)
	_d(ci, 5, 18, 44, 1, TAN)
	for p in [Vector2i(9, 15), Vector2i(13, 17), Vector2i(36, 15), Vector2i(41, 17), Vector2i(26, 17)]:
		_d(ci, p.x, p.y, 1, 1, CREAM)  # flour dust
	_d(ci, 13, 5, 16, 10, INK)  # dough ball
	_d(ci, 15, 4, 12, 1, INK)
	_d(ci, 14, 6, 14, 8, CREAM)
	_d(ci, 16, 5, 10, 1, CREAM)
	_d(ci, 14, 11, 14, 3, CREAM_LO)
	_d(ci, 17, 7, 3, 2, GOLD)
	_d(ci, 29, 8, 24, 5, INK)  # rolling pin
	_d(ci, 30, 9, 16, 3, TAN)
	_d(ci, 30, 9, 16, 1, GOLD)
	_d(ci, 46, 10, 6, 1, BROWN)
	_d(ci, 0, 20, 56, 6, INK)  # table top and apron
	_d(ci, 1, 21, 54, 4, BROWN)
	_d(ci, 1, 21, 54, 1, TAN)
	_d(ci, 3, 25, 50, 4, INK)
	_d(ci, 4, 25, 48, 3, BARK)
	for x in [4, 46]:  # legs and stretcher
		_d(ci, x, 28, 6, 18, INK)
		_d(ci, x + 1, 28, 4, 17, BROWN)
		_d(ci, x + 1, 28, 1, 17, TAN)
	_d(ci, 10, 38, 36, 3, INK)
	_d(ci, 10, 39, 36, 1, BARK)
