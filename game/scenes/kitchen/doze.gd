extends Control
## KITCHEN-P1C · Granny dozing in her rocking chair by the stove (spec §7.12 hint, days 90-99), drawn at the kitchen
## painting's own scale (ART-GRANNY: granny_kitchen_doze.png, 2 frames 58x85 breathing, eyes closed) with a "z"
## bubble that bobs above her head. Looks only: the kitchen shows it after DOZE_AFTER idle seconds and hides it
## again on any input. Whole pixels, palette colours, no alpha.

const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const SHEET := "res://assets/sprites/granny/granny_kitchen_doze.png"
const W := 58
const H := 85
const BEAT := 0.8
## The bubble's top-left corner (its tail points down-left at her bun).
const BUBBLE := Vector2i(28, -11)
const Z_BIG := ["XXXXX", "...X.", "..X..", ".X...", "XXXXX"]
const Z_SMALL := ["XXXX", "..X.", ".X..", "XXXX"]

var _sheet: Texture2D
var _t := 0.0
var _beat := 0


func _ready() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(SHEET):
		_sheet = load(SHEET)


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
	if _sheet != null:  # breathing: inhale on beats 1-2, out on 3-0 (slow, sleepy)
		var f := 1 if _beat == 1 or _beat == 2 else 0
		draw_texture_rect_region(_sheet, Rect2(0, 0, W, H), Rect2(f * W, 0, W, H))
	_bubble()


## The "z" bubble over her head: it bobs one pixel every beat, a small z floats off it on every other beat.
func _bubble() -> void:
	var bx := BUBBLE.x
	var by := BUBBLE.y - (1 if _beat % 2 == 1 else 0)
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
