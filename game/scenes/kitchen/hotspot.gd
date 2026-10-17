extends Button
## GD-KITCHEN · One clickable room object (stove, jar counter, cupboard, book, doors, bed).
## Draws its placeholder art through KitchenArt, a 1-px gold outline on hover/focus, a caption under it and,
## when `glow` is on (Granny's To-Do step), a blinking frame (Granny's guide draws the arrow over it, ONBOARD-GUIDE).
## It is a Button, so mouse, touch (emulated mouse) and keyboard (focus + ui_accept) all press it.
## HOUSE-DOORS: a door carries a fixed wooden sign instead (add_sign, DoorSign): always shown, ringed in gold
## whenever a caption would show; it is then the hotspot's `caption` (Granny's guide points just above it).

const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const ANIMATED := ["stove"]
## Last input device (KITCHEN-FOCUS): a frame shows only under a really moving mouse or on a key-given focus.
## is_hovered() can be stale after a scene change and focus is grabbed on entry, so neither lights on its own.
static var kb_mode := false
static var mouse_moved := false

var kind := ""
## Live numbers the art shows: {"cupboard": {...}} or {"inbox": int}.
var info: Dictionary = {}
var glow := false
## The kitchen shows every caption for a moment on entry and while Tab is held (touch players cannot hover).
var reveal := false:
	set(v):
		reveal = v
		_on_state()
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
	if caption_text != "":  # a small tag, shown only on hover / focus / glow so captions never collide
		caption = Label.new()
		caption.text = caption_text
		caption.visible = false
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tag := StyleBoxFlat.new()
		tag.bg_color = Art.PLUM
		tag.border_color = Art.GOLD
		tag.set_border_width_all(1)
		tag.set_content_margin_all(2)
		tag.content_margin_left = 5
		tag.content_margin_right = 5
		tag.anti_aliasing = false
		caption.add_theme_stylebox_override("normal", tag)
		add_child(caption)
		var cs := caption.get_minimum_size()
		caption.size = cs
		var cx := clampi(int(rect.position.x + (size.x - cs.x) / 2.0), 2, 478 - int(cs.x)) - int(rect.position.x)
		var below := rect.end.y + cs.y + 4 <= 238
		caption.position = Vector2(cx, size.y + 2 if below else -cs.y - 2)
	for sig: Signal in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
		sig.connect(_on_state)
	set_process(kind in ANIMATED)


## Replaces the hover caption with a door sign whose top-middle sits at `top_mid` (local space).
func add_sign(text: String, top_mid: Vector2i) -> DoorSign:
	if caption != null:
		remove_child(caption)
		caption.queue_free()
	var s := DoorSign.new()
	add_child(s)
	s.set_name_text(text)
	s.place_at(top_mid)
	caption = s
	_on_state()
	return s


func is_sign() -> bool:
	return caption is DoorSign


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
	var lit := reveal or picked() or (glow and int(_t * 3.0) % 2 == 0)
	if caption is DoorSign:
		(caption as DoorSign).lit = lit
	elif caption != null:
		caption.visible = lit
		caption.add_theme_color_override("font_color", Art.GOLD)
	queue_redraw()


## True while the mouse is really over the object or a key gave it the focus.
func picked() -> bool:
	if kb_mode:
		return has_focus()
	return mouse_moved and is_hovered()


static func set_device(keyboard: bool) -> bool:
	## Returns true when the mode changed.
	var changed := keyboard != kb_mode or (not keyboard and not mouse_moved)
	kb_mode = keyboard
	if not keyboard:
		mouse_moved = true
	return changed


func _draw() -> void:
	Art.draw_object(self, kind, _t, info)
	# No frames (human, 17 Oct 23:40: "kutu kutu duruyor"): the caption tag and the hint line mark the picked
	# object; the glow step blinks the tag and Granny's guide draws its arrow.
