extends Control
## KITCHEN-P1C · Granny dozing in her rocking chair by the stove (spec §7.12 hint, days 90-99): a little front-view
## chair with Granny sitting in it, eyes closed, and a "z" bubble that bobs above her head. Looks only: the kitchen
## shows it after DOZE_AFTER idle seconds and hides it again on any input. Whole pixels, palette colours, no alpha.

const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const GRANNY_IDLE := "res://assets/sprites/granny/granny_idle.png"
const W := 24
const H := 35
## Granny's sheet rows shown above the seat (head, shoulders, lap) and her boots under it.
const BODY_ROWS := 22
const BOOT_ROW := 29
const SKIN := Color("e5bd7f")
const LID := Color("49423d")
## Her eyes behind the glasses (x of the two pixels per eye, rows 9-11 of the 16x32 frame).
const EYES := [5, 6, 9, 10]
const BEAT := 0.8
const Z_BIG := ["XXXXX", "...X.", "..X..", ".X...", "XXXXX"]
const Z_SMALL := ["XXXX", "..X.", ".X..", "XXXX"]

var _body: Texture2D
var _boots: Texture2D
var _t := 0.0
var _beat := 0


func _ready() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(GRANNY_IDLE):
		var sheet: Image = (load(GRANNY_IDLE) as Texture2D).get_image()
		if sheet.is_compressed():
			sheet.decompress()
		sheet.convert(Image.FORMAT_RGBA8)
		var body := sheet.get_region(Rect2i(0, 0, 16, BODY_ROWS))
		for x: int in EYES:  # eyes closed: one dark lid line, skin above and below
			body.set_pixel(x, 9, SKIN)
			body.set_pixel(x, 10, LID)
			body.set_pixel(x, 11, SKIN)
		_body = ImageTexture.create_from_image(body)
		_boots = ImageTexture.create_from_image(sheet.get_region(Rect2i(0, BOOT_ROW, 16, 32 - BOOT_ROW)))


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var b := int(_t / BEAT) % 4
	if b != _beat:
		_beat = b
		queue_redraw()


## Starts the bubble from its first beat (each time she nods off).
func restart() -> void:
	_t = 0.0
	_beat = 0
	queue_redraw()


func _draw() -> void:
	# floor shadow, every other pixel
	for x in range(2, W - 2, 2):
		_px(x, H - 1, 1, 1, Art.BARK)
	# each chair part twice: a 1 px ink outline first (like the painted furniture), then its wood
	_back(true)
	_back(false)
	if _body != null:  # Granny: head, shawl and lap above the seat
		draw_texture(_body, Vector2(4, 2))
	_front(true)
	_front(false)
	if _boots != null:  # her boots hang between the front legs
		draw_texture(_boots, Vector2(4, 26))
	_bubble()


## Back posts with finials, the top rail and a slat: behind her.
func _back(ink: bool) -> void:
	for x0 in [0, W - 2]:
		_part(x0, 3, 2, 24, Art.BARK, ink)
		_part(x0, 3, 1, 24, Art.BROWN, ink)
		_part(x0, 1, 2, 2, Art.TAN, ink)
	_part(1, 5, W - 2, 2, Art.BROWN, ink)
	_part(1, 5, W - 2, 1, Art.TAN, ink)
	_part(2, 10, W - 4, 1, Art.BARK, ink)


## Arms, seat front, front legs and rockers: in front of her.
func _front(ink: bool) -> void:
	for x0 in [0, W - 5]:
		_part(x0, 15, 5, 2, Art.BROWN, ink)
		_part(x0, 15, 5, 1, Art.TAN, ink)
	_part(0, 23, W, 3, Art.BROWN, ink)
	_part(0, 23, W, 1, Art.TAN, ink)
	_part(0, 25, W, 1, Art.BARK, ink)
	for x0 in [1, W - 3]:
		_part(x0, 26, 2, 6, Art.BROWN, ink)
		_part(x0, 26, 1, 6, Art.TAN, ink)
	for x0 in [0, W - 4]:
		_part(x0, 32, 4, 2, Art.BARK, ink)
		_part(x0 + 1, 32, 2, 1, Art.BROWN, ink)


func _part(x: int, y: int, w: int, h: int, c: Color, ink: bool) -> void:
	if ink:
		_px(x - 1, y - 1, w + 2, h + 2, Art.INK)
	else:
		_px(x, y, w, h, c)


## The "z" bubble over her head: it bobs one pixel every beat, a small z floats off it on every other beat.
func _bubble() -> void:
	var bx := 15
	var by := -14 - (1 if _beat % 2 == 1 else 0)
	_px(bx + 1, by, 9, 1, Art.INK)
	_px(bx + 1, by + 8, 9, 1, Art.INK)
	_px(bx, by + 1, 1, 7, Art.INK)
	_px(bx + 10, by + 1, 1, 7, Art.INK)
	_px(bx + 1, by + 1, 9, 7, Art.CREAM)
	_px(bx + 1, by + 9, 2, 1, Art.INK)  # tail towards her head
	_px(bx, by + 10, 1, 1, Art.INK)
	_glyph(Z_BIG, bx + 3, by + 2, Art.PLUM)
	if _beat >= 2:  # a little bubble with a small z drifts up off the big one
		var sx := bx + 10
		var sy := by - 8 - (_beat - 2)
		_px(sx + 1, sy, 6, 8, Art.INK)
		_px(sx, sy + 1, 8, 6, Art.INK)
		_px(sx + 1, sy + 1, 6, 6, Art.CREAM)
		_glyph(Z_SMALL, sx + 2, sy + 2, Art.PLUM)


func _glyph(rows: Array, x: int, y: int, c: Color) -> void:
	for j in rows.size():
		var row: String = rows[j]
		for i in row.length():
			if row[i] == "X":
				_px(x + i, y + j, 1, 1, c)


func _px(x: int, y: int, w: int, h: int, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)
