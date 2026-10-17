extends Button
## TOWN-NAV · The way back to the garden as a wooden signpost board with its arrow tip on the left, painted like the
## garden's "Town" sign (same plank board and tip from garden_sign.png). A real Button: keyboard focus (gold frame),
## Enter and a click work; the town puts it at the bottom-left of the picture, always visible.

const SIGN := preload("res://assets/sprites/garden/garden_sign.png")
const BOARD_SRC := Rect2(12, 0, 12, 12)
const TIP_SRC := Rect2(24, 0, 6, 11)
const TIP_W := 6
const C_INK := Color("111010")
const C_GOLD := Color("e5bd7f")
const C_CREAM := Color("f2d9c5")
const H := 20


var _paint: Control  # the board, drawn behind the button's own text


func _ready() -> void:
	_paint = Control.new()
	_paint.show_behind_parent = true
	_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paint.draw.connect(_draw_board)
	add_child(_paint)
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var none := StyleBoxEmpty.new()
	none.content_margin_left = TIP_W + 2  # the text sits on the board, right of the tip
	none.content_margin_right = 3
	for k in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(k, none)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		add_theme_color_override(k, C_INK)
	add_theme_constant_override("outline_size", 0)
	fit()


## Board width follows the text, so EN and TR both fit.
func fit() -> void:
	var w := int(ceil(get_minimum_size().x))
	custom_minimum_size = Vector2(maxi(w, 52), H)
	size = custom_minimum_size


func _draw_board() -> void:
	var x0 := TIP_W - 1
	var board := Rect2(x0, 0, size.x - x0, size.y)
	_nine(board)
	# the arrow tip points left: the garden's tip mirrored by whole pixels
	_paint.draw_set_transform(Vector2(TIP_W, floorf((size.y - TIP_SRC.size.y) * 0.5)), 0.0, Vector2(-1, 1))
	_paint.draw_texture_rect_region(SIGN, Rect2(Vector2.ZERO, TIP_SRC.size), TIP_SRC)
	_paint.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if has_focus():
		_paint.draw_rect(Rect2(0, 0, size.x, 1), C_GOLD)
		_paint.draw_rect(Rect2(0, size.y - 1, size.x, 1), C_GOLD)
		_paint.draw_rect(Rect2(0, 0, 1, size.y), C_GOLD)
		_paint.draw_rect(Rect2(size.x - 1, 0, 1, size.y), C_GOLD)
	elif is_hovered():
		_paint.draw_rect(Rect2(x0 + 1, 1, board.size.x - 2, 1), C_CREAM)


## Draws the board's 9-slice (3 px corners) with whole-pixel patches.
func _nine(r: Rect2) -> void:
	var m := 3.0
	var src := BOARD_SRC
	var xs := [0.0, m, src.size.x - m, src.size.x]
	var dx := [r.position.x, r.position.x + m, r.end.x - m, r.end.x]
	var ys := [0.0, m, src.size.y - m, src.size.y]
	var dy := [r.position.y, r.position.y + m, r.end.y - m, r.end.y]
	for j in 3:
		for i in 3:
			var s := Rect2(src.position + Vector2(xs[i], ys[j]), Vector2(xs[i + 1] - xs[i], ys[j + 1] - ys[j]))
			var d := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
			_paint.draw_texture_rect_region(SIGN, d, s)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()
		if _paint != null:
			_paint.queue_redraw()
