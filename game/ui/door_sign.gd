class_name DoorSign
extends Label
## HOUSE-DOORS · A small fixed wooden tag on a door of the house ("Pantry", "Parlour", "Kitchen", "Garden"): the plank
## board of the garden's signposts (garden_sign.png 9-slice, 1 px ink edge) with the room's name in the body font
## (m5x7 at 16, theme BodyPaper). Always visible; `lit` (hover, key focus, Granny's To-Do glow) rings it in gold,
## like the town sign's focus frame. Its width follows the text, so EN and TR both fit; place it with place_at().

const SIGN := preload("res://assets/sprites/garden/garden_sign.png")
const BOARD_SRC := Rect2(12, 0, 12, 12)
const GOLD := Color("e5bd7f")
## Text margins inside the board: m5x7's caps sit 4 rows down its 13 px line, so no top margin; the bottom margin
## keeps descenders (y, ç) on the light middle, clear of the board's dark lower edge. 16 px tall in all.
const PAD_X := 4
const PAD_BOTTOM := 3

var lit := false:
	set(v):
		if v != lit:
			lit = v
			if _ring != null:
				_ring.visible = v

var _ring: Control


func _init() -> void:
	theme_type_variation = &"BodyPaper"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sb := StyleBoxTexture.new()
	sb.texture = SIGN
	sb.region_rect = BOARD_SRC
	sb.set_texture_margin_all(3)
	sb.content_margin_left = PAD_X
	sb.content_margin_right = PAD_X
	sb.content_margin_top = 0
	sb.content_margin_bottom = PAD_BOTTOM
	add_theme_stylebox_override("normal", sb)
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.draw.connect(_draw_ring)
	add_child(_ring)


## Sets the name and sizes the board to it.
func set_name_text(t: String) -> void:
	text = t
	custom_minimum_size = Vector2.ZERO
	reset_size()
	size = Vector2(ceilf(size.x), ceilf(size.y))


## Puts the board's top-middle at `top_mid` (parent space), on whole pixels.
func place_at(top_mid: Vector2i) -> void:
	position = Vector2(top_mid.x - floori(size.x / 2.0), top_mid.y)


func _draw_ring() -> void:
	var w := _ring.size.x
	var h := _ring.size.y
	_ring.draw_rect(Rect2(0, 0, w, 1), GOLD)
	_ring.draw_rect(Rect2(0, h - 1, w, 1), GOLD)
	_ring.draw_rect(Rect2(0, 0, 1, h), GOLD)
	_ring.draw_rect(Rect2(w - 1, 0, 1, h), GOLD)
