extends RefCounted
## P2-FAREWELL · The farewell's shots (spec §7.12). Each is a full-screen Control in the 480x270 design space, drawn
## with Vintage Autumn colours on whole pixels, no alpha blending. The director (farewell.gd) shows one at a time and
## calls at(t) every frame with the seconds since the shot began, so any moment can be drawn again (seek, smoke shots).
##   KitchenShot  morning kitchen: the empty rocking chair with her shawl, the cold kettle, the cat asleep
##   LetterShot   Tonty's last letter typed onto paper over the dimmed kitchen
##   PantryShot   a slow pan along a shelf of the player's own jars (JarIcon), the passing jar's name below;
##                Memory mode browses the same shelf by hand
##   SnowShot     the garden under the first snow: settling snow in 2x2 cells, falling one- and two-pixel flakes
##   CreditsShot  credits on the right page, the discovered recipe-book variants on the left, both scrolling up
##   LastShot     "Thank you for playing." / "For Tonty."

const W := 480
const H := 270
const INK := Color("111010")
const CREAM := Color("f2d9c5")
const CREAM_LO := Color("b9a697")
const GLASS := Color("b4b3a0")
const STONE := Color("49423d")
const GOLD := Color("e5bd7f")
const GOLD_DK := Color("b66813")
const TAN := Color("c58845")
const BROWN := Color("83571e")
const BARK := Color("50361e")
const PLUM := Color("3d1f29")
const WINE := Color("62272c")
const RED := Color("a22512")
const RED_HI := Color("c94d2e")
const PEACH := Color("e19064")
const IRON := Color("2e3f3f")
const IRON_HI := Color("415c5d")
const NIGHT := Color("23282a")
const KITCHEN_BG := "res://assets/sprites/scenes/bg_kitchen.png"
const CAT_SLEEP := "res://assets/sprites/cat/cat_sleep.png"
const COTTAGE := "res://assets/sprites/garden/garden_cottage.png"
const BACKDROP := "res://scenes/garden/garden_backdrop.gd"
const TREE_ART := "res://assets/sprites/forest/tree_%s_bare.png"
## Garden sprites as the garden scene places them (GardenSpot feet + sheet offsets): [path, top-left].
const GARDEN_SPRITES := [
	[COTTAGE, Vector2i(153, -4)],
	["apple", Vector2i(24, 48)],
	["quince", Vector2i(24, 144)],
	["walnut", Vector2i(360, 176)],
]


## Base: full-screen, ignores the mouse (the director reads input), helpers for labels and pixel rects.
class Shot:
	extends Control
	## While true, px() draws each rect one pixel larger in INK: an outline pass under the real drawing.
	var ink := false

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Seconds the shot wants on screen (fades included).
	func duration() -> float:
		return 8.0

	func at(_t: float) -> void:
		pass

	func px(x: int, y: int, w: int, h: int, c: Color) -> void:
		if ink:
			draw_rect(Rect2(x - 1, y - 1, w + 2, h + 2), INK)
		else:
			draw_rect(Rect2(x, y, w, h), c)

	static func tex(path: String) -> Texture2D:
		return load(path) as Texture2D if ResourceLoader.exists(path) else null

	static func make_label(text: String, variation: StringName = &"", width := 0) -> Label:
		var l := Label.new()
		l.text = text
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # callers pass translated, formatted text
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if variation != &"":
			l.theme_type_variation = variation
		if width > 0:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(width, 0)
		return l

	## Label text typed in from `start` at `cps` characters a second; the layout never moves while it types.
	static func type_in(l: Label, t: float, start: float, cps: float) -> void:
		var n := int((t - start) * cps)
		l.visible_characters = -1 if n >= l.text.length() else maxi(n, 0)


# ---------------------------------------------------------------- 1. kitchen

class KitchenShot:
	extends Shot
	const CHAIR := Vector2i(92, 214)  ## bottom-left of the rockers, on the floor by the hearth
	const KETTLE := Vector2i(42, 101)  ## bottom-left of the kettle, on the stove top
	const CAT_AT := Vector2i(164, 218)  ## bottom-left of the sleeping cat, at the chair's feet
	var _bg: Texture2D
	var _cat: Texture2D
	var _cat_frame := 0

	func _ready() -> void:
		_bg = tex(KITCHEN_BG)
		_cat = tex(CAT_SLEEP)

	func at(t: float) -> void:
		var f := int(t * 0.8) % 2  # slow breathing
		if f != _cat_frame:
			_cat_frame = f
			queue_redraw()

	func _draw() -> void:
		if _bg != null:
			draw_texture(_bg, Vector2.ZERO)
		else:
			px(0, 0, W, H, BARK)
		ink = true
		_kettle(KETTLE.x, KETTLE.y)
		ink = false
		_kettle(KETTLE.x, KETTLE.y)
		_chair(CHAIR.x, CHAIR.y)
		if _cat != null:
			draw_texture_rect_region(_cat, Rect2(CAT_AT.x, CAT_AT.y - 24, 24, 24), Rect2(_cat_frame * 24, 0, 24, 24))

	## Cold kettle: iron body, lid knob, handle, spout. No steam.
	func _kettle(x: int, y: int) -> void:
		px(x + 3, y - 16, 10, 1, NIGHT)
		px(x + 3, y - 16, 1, 6, NIGHT)
		px(x + 12, y - 16, 1, 6, NIGHT)
		px(x + 4, y - 11, 8, 2, IRON)
		px(x + 7, y - 13, 2, 2, IRON_HI)
		px(x + 2, y - 9, 12, 8, IRON)
		px(x + 3, y - 9, 10, 1, IRON_HI)
		px(x + 11, y - 8, 1, 4, GLASS)
		px(x + 3, y - 1, 10, 1, NIGHT)
		px(x, y - 7, 2, 2, IRON)
		px(x - 2, y - 9, 2, 2, IRON)
		px(x - 2, y - 9, 2, 1, IRON_HI)

	## Rocker runner as [dx, dy, length] steps (3 px thick), tip to tip; its lowest step touches the floor.
	const RUNNER := [[0, -11, 3], [3, -9, 4], [7, -7, 6], [13, -5, 9], [22, -3, 22], [44, -5, 9], [53, -7, 6],
		[59, -9, 4], [63, -11, 3]]
	## The far side of the chair sits this far right and up (the chair stands at an angle to the room).
	const FAR := Vector2i(9, -6)

	## The empty ladder-back rocking chair by the hearth, seen from its side: two runners, legs, seat and cushion,
	## a back of slats leaning away, arms, and her red shawl over the top.
	func _chair(x: int, y: int) -> void:
		for i in range(2, 74, 2):  # dithered shadow on the floor
			px(x + i, y + 1, 1, 1, BARK)
			px(x + i + 1, y + 2, 1, 1, BARK)
		ink = true  # a dark outline around the whole chair first, like the painted furniture
		_chair_body(x, y)
		ink = false
		_chair_body(x, y)

	func _chair_body(x: int, y: int) -> void:
		_chair_side(x + FAR.x, y + FAR.y, true)
		# seat: top surface, cushion, then the near side apron
		for r in 6:
			px(x + 16 + floori(r * 1.5), y - 52 + r, 42, 1, GOLD if r == 0 else TAN)
		px(x + 25, y - 57, 30, 5, GOLD)
		px(x + 25, y - 53, 30, 1, GOLD_DK)
		for k in 3:
			px(x + 31 + k * 9, y - 55, 1, 1, RED_HI)
		# back slats between the posts, running away from us
		for h in [-62, -71, -80, -89]:
			var nx: int = x + 18 - _lean(-h - 48)
			for k in FAR.x:
				px(nx + 3 + k, y + h + floori(k * FAR.y / float(FAR.x)), 1, 3, BROWN)
				px(nx + 3 + k, y + h + floori(k * FAR.y / float(FAR.x)), 1, 1, TAN)
		_chair_side(x, y, false)
		# her shawl folded over the top rail: red wool, peach stripes, a fringe
		var sx: int = x + 18 - _lean(46) - 5
		px(sx, y - 99, 17, 15, RED)
		px(sx, y - 99, 1, 15, WINE)
		px(sx + 16, y - 99, 1, 15, WINE)
		px(sx + 1, y - 99, 15, 1, RED_HI)
		for s in [-95, -90]:
			px(sx + 1, y + s, 15, 2, PEACH)
		for k in 8:
			px(sx + 1 + k * 2, y - 84, 1, 3, RED_HI)

	## Horizontal lean of the back post `up` px above the seat (one px every 7).
	func _lean(up: int) -> int:
		return floori(clampi(up, 0, 56) / 7.0)

	## One side of the chair: runner, legs, apron, back post, arm. The far side is darker and drawn first.
	func _chair_side(x: int, y: int, far: bool) -> void:
		var body := BARK if far else BROWN
		var hi := BROWN if far else TAN
		var lo := NIGHT if far else BARK
		for s in RUNNER:
			px(x + s[0], y + s[1] - 1, s[2], 4, body)
			px(x + s[0], y + s[1] - 1, s[2], 1, hi)
			px(x + s[0], y + s[1] + 2, s[2], 1, lo)
		for lx in [20, 48]:  # back and front legs
			px(x + lx, y - 46, 4, 40, body)
			px(x + lx + 3, y - 46, 1, 40, hi)
		px(x + 16, y - 46, 40, 5, body)  # seat apron
		px(x + 16, y - 46, 40, 1, hi)
		px(x + 16, y - 42, 40, 1, lo)
		for i in 7:  # back post leaning back
			px(x + 17 - i, y - 46 - (i + 1) * 7, 4, 7, body)
			px(x + 20 - i, y - 46 - (i + 1) * 7, 1, 7, hi)
		px(x + 9, y - 98, 5, 3, hi)  # finial
		px(x + 16, y - 66, 42, 3, body)  # arm, its front post and curled end
		px(x + 16, y - 66, 42, 1, hi)
		px(x + 50, y - 63, 3, 17, body)
		px(x + 56, y - 68, 3, 4, body)
		px(x + 56, y - 68, 3, 1, hi)


# ---------------------------------------------------------------- 2. letter

class LetterShot:
	extends Shot
	const PAPER_W := 448
	const CPS := 32.0
	const PAUSE := 0.6
	const START := 1.4
	const HOLD := 6.0
	var _bg: Texture2D
	var _labels: Array[Label] = []
	var _starts: Array[float] = []
	var _end := START

	func _ready() -> void:
		_bg = tex(KITCHEN_BG)

	## `lines`: the translated letter, one paragraph each; the last one (the signature) sits on the right.
	func setup(lines: Array) -> void:
		var dim := DitherCover.new()
		dim.color = NIGHT
		dim.level = 11
		add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		var paper := PanelContainer.new()
		paper.theme_type_variation = &"PaperPanel"
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(paper)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		paper.add_child(box)
		var t := START
		for i in lines.size():
			var l := make_label(String(lines[i]), &"PaperLabel", PAPER_W - 14)
			l.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
			l.visible_characters = 0
			if i == lines.size() - 1:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			box.add_child(l)
			_labels.append(l)
			_starts.append(t)
			t += l.text.length() / CPS + PAUSE
		_end = t

	func duration() -> float:
		return _end + HOLD

	func typed_by() -> float:
		return _end

	func at(t: float) -> void:
		for i in _labels.size():
			type_in(_labels[i], t, _starts[i], CPS)

	func _draw() -> void:
		if _bg != null:
			draw_texture(_bg, Vector2.ZERO)
		else:
			px(0, 0, W, H, BARK)


# ---------------------------------------------------------------- 3. pantry

class PantryShot:
	extends Shot
	const SPACING := 72
	const ZOOM := 2
	const SHELF_Y := 186  ## shelf top: the jars stand on it
	const PAN_DELAY := 2.0
	const PAN_SEC := 13.0
	const MIN_SPEED := 36.0
	const HOLD := 3.0
	var offset := 0.0  ## px the camera has moved along the shelf; jar i is centred at offset i * SPACING
	var _strip: ShelfStrip
	var _names: Array = []
	var _caption: Label
	var _empty := ""
	var _speed := MIN_SPEED

	## `jars`: [{"key", "name", ...}] in shelf order; `empty_text` shows when there are none.
	func setup(jars: Array, varieties: Dictionary, empty_text: String) -> void:
		clip_contents = true
		_empty = empty_text
		_strip = ShelfStrip.new()
		_strip.size = Vector2(W + maxi(jars.size() - 1, 0) * SPACING, H)
		add_child(_strip)
		for i in jars.size():
			var j: Dictionary = jars[i]
			var desc := ProductGen.describe(String(j.key), varieties)
			var icon := JarIcon.new()
			icon.zoom = ZOOM
			icon.show_product(desc)
			var sz := JarIcon.pixel_size(desc, "shelf") * ZOOM
			icon.position = Vector2(floori(W * 0.5 - sz.x * 0.5) + i * SPACING, SHELF_Y - sz.y)
			_strip.add_child(icon)
			_names.append(String(j.name))
		_speed = maxf(MIN_SPEED, max_offset() / PAN_SEC)
		var bottom := CenterContainer.new()
		bottom.anchor_left = 0.0
		bottom.anchor_right = 1.0
		bottom.anchor_top = 1.0
		bottom.anchor_bottom = 1.0
		bottom.offset_top = -40
		bottom.offset_bottom = -8
		bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bottom)
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom.add_child(panel)
		_caption = make_label(_empty if jars.is_empty() else "")
		_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(_caption)
		scroll_to(0.0)

	func jar_count() -> int:
		return _names.size()

	func max_offset() -> float:
		return float(maxi(_names.size() - 1, 0) * SPACING)

	func duration() -> float:
		return PAN_DELAY + max_offset() / _speed + HOLD

	## The jar nearest the middle of the screen.
	func current() -> int:
		return clampi(roundi(offset / SPACING), 0, maxi(_names.size() - 1, 0))

	func scroll_to(px_along: float) -> void:
		offset = clampf(px_along, 0.0, max_offset())
		_strip.position = Vector2(-floorf(offset), 0)
		if not _names.is_empty():
			_caption.text = String(_names[current()])

	func at(t: float) -> void:
		scroll_to((t - PAN_DELAY) * _speed)


## The pantry wall and one long shelf, as wide as the jars need.
class ShelfStrip:
	extends Control
	const SEAM := 22
	const BRACKET := 144

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := int(size.x)
		var sy: int = PantryShot.SHELF_Y
		draw_rect(Rect2(0, 0, w, H), PLUM)
		for x in range(0, w, SEAM):
			draw_rect(Rect2(x, 0, 1, H), NIGHT)
			draw_rect(Rect2(x + 1, 0, 1, H), WINE)
		draw_rect(Rect2(0, 60, w, 1), NIGHT)  # a rail high on the wall
		draw_rect(Rect2(0, 61, w, 2), WINE)
		draw_rect(Rect2(0, sy, w, 1), GOLD)
		draw_rect(Rect2(0, sy + 1, w, 5), TAN)
		draw_rect(Rect2(0, sy + 6, w, 2), BROWN)
		draw_rect(Rect2(0, sy + 8, w, 1), BARK)
		draw_rect(Rect2(0, sy + 9, w, 3), NIGHT)
		for bx in range(BRACKET >> 1, w, BRACKET):
			for k in 5:
				draw_rect(Rect2(bx, sy + 12 + k * 3, 12 - k * 2, 3), BROWN)
				draw_rect(Rect2(bx, sy + 12 + k * 3, 1, 3), TAN)


# ---------------------------------------------------------------- 4. first snow

class SnowShot:
	extends Shot
	const LINE_AT := 3.5
	const CPS := 22.0
	const DURATION := 15.0
	## Memory mode: the snow already lies and keeps falling, no line.
	var looping := false
	var _fx: SnowFx
	var _line: Label
	var _line_box: Control

	func setup(line_text: String) -> void:
		var garden := Node2D.new()
		add_child(garden)
		var backdrop: Node2D = (load(BACKDROP) as GDScript).new()
		garden.add_child(backdrop)
		var ledge_src := []
		for s in GARDEN_SPRITES:
			var path := String(s[0])
			var t := tex(path if path.begins_with("res://") else TREE_ART % path)
			if t == null:
				continue
			ledge_src.append([t, s[1]])
			var sp := Sprite2D.new()
			sp.texture = t
			sp.centered = false
			sp.position = Vector2(s[1])
			garden.add_child(sp)
		_fx = SnowFx.new()
		_fx.add_sprites(ledge_src)
		add_child(_fx)
		_line_box = CenterContainer.new()
		_line_box.anchor_left = 0.0
		_line_box.anchor_right = 1.0
		_line_box.anchor_top = 1.0
		_line_box.anchor_bottom = 1.0
		_line_box.offset_top = -44
		_line_box.offset_bottom = -10
		_line_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_line_box)
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_line_box.add_child(panel)
		_line = make_label(line_text)
		_line.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
		panel.add_child(_line)

	func duration() -> float:
		return DURATION

	func at(t: float) -> void:
		_fx.at(t, looping)
		_line_box.visible = not looping and t >= LINE_AT
		type_in(_line, t, LINE_AT + 0.4, CPS)


## A gentle first snow: whole-pixel flakes (1-2 px, cream and pale grey) drifting down at a few speeds, and a thin
## cover that builds up over the seconds on the top edges of shapes (roofs, branches, the fence, the path edges),
## one to three pixels deep, never a full-screen pattern.
class SnowFx:
	extends Control
	const LAYOUT := preload("res://scenes/garden/garden_layout.gd")
	const FENCE := "res://assets/sprites/garden/garden_fence_h.png"
	const COVER_FROM := 1.0
	const COVER_SEC := 11.0
	const BUCKETS := 20
	const DEPTH := 3  ## pixels of cover under a ledge at the end
	const SPEEDS := [7.0, 11.0, 16.0]
	const FLAKES := 90
	var _img: Image
	var _tex: ImageTexture
	var _buckets: Array = []  ## per step: PackedInt32Array of (y << 12 | x << 2 | colour)
	var _painted := 0
	var _flakes: Array = []  ## [x0, y0, speed, amp, phase, size, colour]
	var _t := 0.0

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
		_tex = ImageTexture.create_from_image(_img)
		for b in BUCKETS:
			_buckets.append(PackedInt32Array())
		var r := RandomNumberGenerator.new()
		r.seed = 1017
		for i in FLAKES:
			_flakes.append([r.randf_range(0, W), r.randf_range(0, H), SPEEDS[r.randi() % SPEEDS.size()], r.randf_range(0.0, 3.0),
				r.randf_range(0.0, TAU), 2 if r.randf() < 0.25 else 1, CREAM if r.randf() < 0.7 else GLASS])

	## Ledges from the garden sprites: the top opaque pixel of every run in each column, plus the fence and path edges.
	func add_sprites(sprites: Array) -> void:
		for s in sprites:
			var t: Texture2D = s[0]
			if t == null:
				continue
			_ledges_of(t.get_image(), Vector2i(s[1]))
		var fence: Texture2D = load(FENCE) if ResourceLoader.exists(FENCE) else null
		if fence != null:
			var img: Image = fence.get_image()
			var gy := (LAYOUT.H - 1) * LAYOUT.TILE
			for x in range(1, LAYOUT.W - 1):
				var c := Vector2i(x, LAYOUT.H - 1)
				if LAYOUT.is_gate(c):
					continue
				_ledges_of(img.get_region(Rect2i(0, 0, LAYOUT.TILE, LAYOUT.TILE)), Vector2i(x * LAYOUT.TILE, gy))
		# path and road edges: a thin line on the lawn side
		var tile: int = LAYOUT.TILE
		var px0: int = int(LAYOUT.PATH_COLS[0]) * tile
		var px1: int = (int(LAYOUT.PATH_COLS[-1]) + 1) * tile
		var ry0: int = int(LAYOUT.ROAD_ROWS[0]) * tile
		var ry1: int = (int(LAYOUT.ROAD_ROWS[-1]) + 1) * tile
		var top: int = (LAYOUT.HOUSE.end.y) * tile
		for y in range(top, (LAYOUT.H - 1) * tile):
			if y >= ry0 and y < ry1:
				continue
			if (y * 7 + 3) % 5 != 0:
				_put(px0 - 1, y, 0)
			if (y * 11 + 1) % 5 != 0:
				_put(px1, y, 0)
		for x in range(0, W - tile):
			if x >= px0 and x < px1:
				continue
			if (x * 7 + 3) % 5 != 0:
				_put(x, ry0 - 1, 0)
			if (x * 11 + 1) % 5 != 0:
				_put(x, ry1, 1)

	func _ledges_of(img: Image, at: Vector2i) -> void:
		for x in img.get_width():
			var open := true
			for y in img.get_height():
				var solid := img.get_pixel(x, y).a > 0.5
				if solid and open:
					for k in DEPTH:
						if y + k < img.get_height() and img.get_pixel(x, y + k).a > 0.5:
							_put(at.x + x, at.y + y + k, k)
				open = not solid

	## `depth` 0 is the top pixel (appears first, cream); deeper ones follow and the thin ones are pale grey.
	func _put(x: int, y: int, depth: int) -> void:
		if x < 0 or y < 0 or x >= W or y >= H:
			return
		var h := (x * 374761393 + y * 668265263) & 0x7FFFFFFF
		h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
		h = (h ^ (h >> 16)) & 0xFFFF
		if depth >= 2 and (h & 3) != 0:
			return  # the third row is patchy
		var th := (0.55 * float(h) / 65535.0 + 0.2 * depth) / 1.0
		var col := 1 if depth == 0 and (h & 7) == 0 else (0 if depth < 2 else 1 + ((h >> 3) & 1))
		_buckets[clampi(int(th * BUCKETS), 0, BUCKETS - 1)].append((((y << 10) | x) << 2) | col)

	func at(t: float, full: bool) -> void:
		_t = t
		var k := BUCKETS if full else clampi(int((t - COVER_FROM) / COVER_SEC * BUCKETS), 0, BUCKETS)
		if k < _painted:
			_img.fill(Color(0, 0, 0, 0))
			_painted = 0
		if k > _painted:
			var cols := [CREAM, GLASS, CREAM_LO]
			while _painted < k:
				for v in _buckets[_painted]:
					_img.set_pixel((v >> 2) & 0x3FF, v >> 12, cols[v & 3])
				_painted += 1
			_tex.update(_img)
		queue_redraw()

	func _draw() -> void:
		draw_texture(_tex, Vector2.ZERO)
		for f in _flakes:
			var y := fposmod(float(f[1]) + _t * float(f[2]), H + 4.0) - 2.0
			var x := fposmod(float(f[0]) + sin(_t * 0.5 + float(f[4])) * float(f[3]) - _t * 2.0, float(W))
			draw_rect(Rect2(floorf(x), floorf(y), f[5], f[5]), f[6])


# ---------------------------------------------------------------- 5. credits

class CreditsShot:
	extends Shot
	const PAGE := Vector2i(206, 212)
	const LEFT := Vector2i(30, 29)
	const RIGHT := Vector2i(244, 29)
	const START := 1.0
	const SCROLL_SEC := 18.0
	const HOLD := 1.0
	const COL_PAD := 8
	var _left_col: VBoxContainer
	var _right_col: VBoxContainer

	## `variants`: product keys; `lines`: translated credits ("" = gap); `heads`: indexes of lines drawn as headings.
	func setup(variants: Array, varieties: Dictionary, lines: Array, heads: Array, book_head: String, book_empty: String) -> void:
		var spine := Spine.new()
		add_child(spine)
		var lp := Page.new()
		lp.position = Vector2(LEFT)
		lp.size = Vector2(PAGE)
		add_child(lp)
		var rp := Page.new()
		rp.position = Vector2(RIGHT)
		rp.size = Vector2(PAGE)
		add_child(rp)
		var cw := PAGE.x - COL_PAD * 2
		_left_col = VBoxContainer.new()
		_left_col.add_theme_constant_override("separation", 4)
		_left_col.position = Vector2(COL_PAD, PAGE.y)
		_left_col.custom_minimum_size = Vector2(cw, 0)
		lp.add_child(_left_col)
		var head := make_label(book_head, &"PaperLabel", cw)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_color_override("font_color", RED)
		_left_col.add_child(head)
		if variants.is_empty():
			var none := make_label(book_empty, &"PaperLabel", cw)
			none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_left_col.add_child(none)
		for key in variants:
			var desc := ProductGen.describe(String(key), varieties)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon := JarIcon.new()
			icon.show_product(desc)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(icon)
			var title := make_label(String(desc.get("name", "?")), &"PaperLabel", cw - 30)
			title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(title)
			_left_col.add_child(row)
		_right_col = VBoxContainer.new()
		_right_col.add_theme_constant_override("separation", 0)
		_right_col.position = Vector2(COL_PAD, PAGE.y)
		_right_col.custom_minimum_size = Vector2(cw, 0)
		rp.add_child(_right_col)
		for i in lines.size():
			var l := make_label(String(lines[i]), &"PaperLabel", cw)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if i in heads:
				l.add_theme_color_override("font_color", RED)
			if String(lines[i]) == "":
				l.custom_minimum_size.y = 12
			_right_col.add_child(l)

	func duration() -> float:
		return START + SCROLL_SEC + HOLD

	## Both columns rise from below the page to past its top in SCROLL_SEC, so they end together.
	func at(t: float) -> void:
		var k := clampf((t - START) / SCROLL_SEC, 0.0, 1.0)
		for col in [_left_col, _right_col]:
			var c := col as VBoxContainer
			var h := c.get_combined_minimum_size().y
			c.position.y = floorf(PAGE.y - k * (PAGE.y + h))


## One recipe-book page: paper, a frame, a darker edge by the spine; clips the scrolling column.
class Page:
	extends Control

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := int(size.x)
		var h := int(size.y)
		draw_rect(Rect2(0, 0, w, h), CREAM)
		for e in [Rect2(0, 0, w, 1), Rect2(0, h - 1, w, 1), Rect2(0, 0, 1, h), Rect2(w - 1, 0, 1, h)]:
			draw_rect(e, BROWN)
		var by_spine := w - 3 if position.x < W * 0.5 else 1
		draw_rect(Rect2(by_spine, 1, 2, h - 2), CREAM_LO)


## The open book behind the pages: leather cover and spine on the dark table.
class Spine:
	extends Control

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(0, 0, W, H), PLUM)
		var l: Vector2i = CreditsShot.LEFT
		var p: Vector2i = CreditsShot.PAGE
		draw_rect(Rect2(l.x - 6, l.y - 6, CreditsShot.RIGHT.x + p.x - l.x + 12, p.y + 12), WINE)
		draw_rect(Rect2(l.x - 6, l.y + p.y + 4, CreditsShot.RIGHT.x + p.x - l.x + 12, 2), NIGHT)
		draw_rect(Rect2(l.x + p.x, l.y - 2, CreditsShot.RIGHT.x - l.x - p.x, p.y + 4), BARK)


# ---------------------------------------------------------------- 6. last card

class LastShot:
	extends Shot
	const FIRST_AT := 0.8
	const SECOND_AT := 2.6
	const DURATION := 8.0
	var _thanks: Label
	var _for: Label

	func setup(thanks: String, for_tonty: String) -> void:
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		center.add_child(box)
		_thanks = make_label(thanks, &"Heading")
		_thanks.add_theme_font_size_override("font_size", 36)
		_thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_thanks)
		_for = make_label(for_tonty)
		_for.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_for)

	func duration() -> float:
		return DURATION

	func at(t: float) -> void:
		_thanks.self_modulate = Color.WHITE if t >= FIRST_AT else Color(1, 1, 1, 0)
		_for.self_modulate = Color.WHITE if t >= SECOND_AT else Color(1, 1, 1, 0)

	func _draw() -> void:
		draw_rect(Rect2(0, 0, W, H), PLUM)
