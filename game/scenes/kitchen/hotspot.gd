extends Button
## GD-KITCHEN · One clickable room object (stove, jar counter, cupboard, book, doors, bed).
## Draws its placeholder art through KitchenArt, a 1-px gold outline on hover/focus, a caption under it and,
## when `glow` is on (Granny's To-Do step), a blinking frame with a bobbing arrow.
## It is a Button, so mouse, touch (emulated mouse) and keyboard (focus + ui_accept) all press it.

const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const ANIMATED := ["stove"]
const FLOOR_Y := 198

var kind := ""
## Live numbers the art shows: {"cupboard": {...}} or {"inbox": int}.
var info: Dictionary = {}
var glow := false
var caption: Label
var _t := 0.0
var _frame := -1


func setup(kind_id: String, rect: Rect2i, caption_text: String) -> void:
	kind = kind_id
	position = Vector2(rect.position)
	size = Vector2(rect.size)
	custom_minimum_size = size
	focus_mode = Control.FOCUS_ALL
	flat = true
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	if caption_text != "":
		caption = Label.new()
		caption.text = caption_text
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size = Vector2(maxi(int(size.x), 70), 18)
		caption.position = Vector2(int((size.x - caption.size.x) / 2.0), FLOOR_Y - rect.position.y + 2)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(caption)
	for sig: Signal in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
		sig.connect(_on_state)
	set_process(kind in ANIMATED)


func set_info(d: Dictionary) -> void:
	info = d
	queue_redraw()


func set_glow(on: bool) -> void:
	glow = on
	set_process(on or kind in ANIMATED)
	_on_state()


func _process(delta: float) -> void:
	_t += delta
	var f := int(_t * 8.0)
	if f != _frame:
		_frame = f
		if glow and caption != null:
			_on_state()
		queue_redraw()


func _on_state() -> void:
	var lit := has_focus() or is_hovered() or (glow and int(_t * 3.0) % 2 == 0)
	if caption != null:
		caption.add_theme_color_override("font_color", Art.GOLD if lit else Art.CREAM)
	queue_redraw()


func _draw() -> void:
	var w := int(size.x)
	var h := int(size.y)
	Art.draw_object(self, kind, _t, info)
	if glow:
		var on := int(_t * 3.0) % 2 == 0
		Art.frame(self, Rect2i(-4, -4, w + 8, h + 8), Art.GOLD if on else Art.AMBER)
		Art.arrow(self, w >> 1, -12 + int(_t * 4.0) % 2, Art.GOLD)
	if has_focus() or is_hovered():
		Art.frame(self, Rect2i(-2, -2, w + 4, h + 4), Art.GOLD)
		Art.frame(self, Rect2i(-1, -1, w + 2, h + 2), Art.INK)
