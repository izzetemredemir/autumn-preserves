class_name HowToPlay
extends CanvasLayer
## ONBOARD-HOWTO · A short illustrated How to Play: five pages (Your autumn, Forage, Cook, Pantry, Share), each a 1x
## picture of the real game framed on the paper panel (res://assets/howto/<id>.png, made by howto_shot.gd
## -- --pictures), a title and two or three short lines. Page dots (click or tap one), Back / Next buttons, Left /
## Right (or A / D) and a swipe flip pages; Next has the focus, so Enter goes on, and on the last page "Got it!"
## closes; Esc or Close closes on any page.
## Opened by the title after the New Game intro and by its How to Play button, and by the pause menu (over the paused
## game: this layer runs with PROCESS_MODE_ALWAYS). Emits `closed` once and frees itself.
## Reaches Audio by path: the pause menu loads this script where the autoloads are not registered (unit tests).

signal closed

const LAYER := 85  ## over the pause menu (80), under Transition (90) and Night (95)
const THEME := "res://ui/theme/theme.tres"
const PICTURES := "res://assets/howto/%s.png"
## id (the picture), title key, line keys
const PAGES := [
	["autumn", "HOWTO_AUTUMN", ["HOWTO_AUTUMN_1", "HOWTO_AUTUMN_2", "HOWTO_AUTUMN_3"]],
	["forage", "HOWTO_FORAGE", ["HOWTO_FORAGE_1", "HOWTO_FORAGE_2", "HOWTO_FORAGE_3"]],
	["cook", "HOWTO_COOK", ["HOWTO_COOK_1", "HOWTO_COOK_2", "HOWTO_COOK_3"]],
	["pantry", "HOWTO_PANTRY", ["HOWTO_PANTRY_1", "HOWTO_PANTRY_2", "HOWTO_PANTRY_3"]],
	["share", "HOWTO_SHARE", ["HOWTO_SHARE_1", "HOWTO_SHARE_2", "HOWTO_SHARE_3"]],
]
const PICTURE := Vector2i(200, 110)
const BODY_H := 160  ## the longest page (Cook, seven lines) fits; shorter ones centre in it
const PANEL_W := 456
const TEXT_W := 228
const SIDE_W := 140  ## the bottom row's left and right parts, so the dots sit in the middle
const SWIPE := 32
const C_INK := Color("111010")
const C_TITLE := Color("a22512")
const C_TEXT := Color("50361e")
const C_SOFT := Color("83571e")
const C_DOT := Color("b9a697")

var page := 0
var _ui: Control
var _title: Label
var _view: Control  ## clips the sliding picture
var _picture: TextureRect
var _lines: VBoxContainer
var _dots: Dots
var _back: Button
var _next: Button
var _done: Button
var _close: Button
var _touch_from := Vector2.INF
var _slide: Tween
var _closing := false


## Opens the book under `host` (the title, the pause menu; the tree root when null), or returns the one already open.
static func open(host: Node) -> HowToPlay:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group("howto") as HowToPlay
	if found != null and not found._closing:
		return found
	var h := HowToPlay.new()
	h.name = "HowToPlay"
	(host if host != null else tree.root).add_child(h)
	return h


static func page_count() -> int:
	return PAGES.size()


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("howto")
	_build()
	show_page(0)


func show_page(i: int) -> void:
	var from := page
	page = clampi(i, 0, PAGES.size() - 1)
	var p: Array = PAGES[page]
	_title.text = tr(p[1])
	_picture.texture = _texture(p[0])
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	for key: String in p[2]:
		_lines.add_child(_line(tr(key)))
	_dots.current = page
	_dots.queue_redraw()
	var last := page == PAGES.size() - 1
	_back.disabled = page == 0
	_next.visible = not last
	_done.visible = last
	(_done if last else _next).grab_focus()
	if page != from:
		_slide_in(1 if page > from else -1)


## d = -1 / 1: the page before / after (nothing past either end).
func flip(d: int) -> void:
	var np := clampi(page + d, 0, PAGES.size() - 1)
	if np == page:
		return
	_sfx("sfx_page_turn")
	show_page(np)


## Esc, Close and "Got it!": the book goes and `closed` is emitted once.
func close(confirm := false) -> void:
	if _closing:
		return
	_closing = true
	_ui_sound("ui_confirm" if confirm else "ui_back")
	visible = false
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if _closing or not visible:
		return
	if event is InputEventScreenTouch:
		_swipe(event as InputEventScreenTouch)
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif _pressed(event, ["ui_left", "move_left"]):
		get_viewport().set_input_as_handled()
		flip(-1)
	elif _pressed(event, ["ui_right", "move_right"]):
		get_viewport().set_input_as_handled()
		flip(1)


func _pressed(event: InputEvent, actions: Array) -> bool:
	for a: String in actions:
		if InputMap.has_action(a) and event.is_action_pressed(a):
			return true
	return false


## A sideways swipe flips a page (touch screens); taps still reach the buttons and dots.
func _swipe(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_touch_from = t.position
		return
	if _touch_from == Vector2.INF:
		return
	var d := t.position - _touch_from
	_touch_from = Vector2.INF
	if absf(d.x) >= SWIPE and absf(d.x) > absf(d.y) * 1.5:
		flip(-1 if d.x > 0 else 1)


# ---------------------------------------------------------------- view

func _build() -> void:
	_ui = Control.new()
	_ui.name = "HowTo"
	_ui.theme = load(THEME)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing under the book takes a click or a tap
	add_child(_ui)
	_ui.add_child(_dim())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = &"PaperPanel"
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	_title = _label("", C_TITLE)
	_title.name = "Title"
	_title.add_theme_font_size_override("font_size", 36)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 8)
	body.custom_minimum_size = Vector2(0, BODY_H)  # one panel size for every page
	box.add_child(body)
	body.add_child(_frame())
	_lines = VBoxContainer.new()
	_lines.name = "Lines"
	_lines.custom_minimum_size = Vector2(TEXT_W, 0)
	_lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lines.add_theme_constant_override("separation", 5)
	body.add_child(_lines)

	var bottom := HBoxContainer.new()
	bottom.name = "Bottom"
	bottom.add_theme_constant_override("separation", 0)
	box.add_child(bottom)
	var left := HBoxContainer.new()
	left.custom_minimum_size = Vector2(SIDE_W, 0)
	bottom.add_child(left)
	_close = _button(left, "Close", tr("HOWTO_CLOSE"), close)
	_dots = Dots.new()
	_dots.name = "Dots"
	_dots.count = PAGES.size()
	_dots.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dots.picked.connect(func(i: int) -> void:
		if i != page:
			_sfx("sfx_page_turn")
			show_page(i))
	bottom.add_child(_dots)
	var right := HBoxContainer.new()
	right.custom_minimum_size = Vector2(SIDE_W, 0)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 4)
	bottom.add_child(right)
	_back = _button(right, "Back", tr("HOWTO_BACK"), flip.bind(-1))
	_next = _button(right, "Next", tr("HOWTO_NEXT"), flip.bind(1))
	_done = _button(right, "Done", tr("HOWTO_DONE"), close.bind(true))


## The picture at 1x in a 2 px frame; the inner view clips it while it slides in.
func _frame() -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_INK
	sb.border_color = C_SOFT
	sb.set_border_width_all(2)
	sb.set_content_margin_all(2)
	sb.anti_aliasing = false
	frame.add_theme_stylebox_override("panel", sb)
	_view = Control.new()
	_view.custom_minimum_size = Vector2(PICTURE)
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_view)
	_picture = TextureRect.new()
	_picture.name = "Picture"
	_picture.size = Vector2(PICTURE)
	_picture.stretch_mode = TextureRect.STRETCH_KEEP
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_picture)
	return frame


## One short line with a square bullet; wraps inside the text column.
func _line(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var bullet := Control.new()
	bullet.custom_minimum_size = Vector2(4, 4)
	var dot := ColorRect.new()
	dot.color = C_SOFT
	dot.position = Vector2(0, 7)
	dot.size = Vector2(4, 4)
	bullet.add_child(dot)
	row.add_child(bullet)
	var l := _label(text, C_TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(TEXT_W - 10, 0)
	row.add_child(l)
	return row


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"PaperLabel"
	l.add_theme_color_override("font_color", color)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # set already translated
	return l


func _button(parent: Control, node_name: String, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(64, 22)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## Every other pixel ink (no alpha): what is underneath shows through, dimmed.
func _dim() -> TextureRect:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixel(0, 0, C_INK)
	img.set_pixel(1, 1, C_INK)
	var dim := TextureRect.new()
	dim.texture = ImageTexture.create_from_image(img)
	dim.stretch_mode = TextureRect.STRETCH_TILE
	dim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dim


func _texture(id: String) -> Texture2D:
	var path := PICTURES % id
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.create(PICTURE.x, PICTURE.y, false, Image.FORMAT_RGBA8)  # no picture yet: plain paper shade
	img.fill(C_DOT)
	return ImageTexture.create_from_image(img)


## The new picture slides in from the side it comes from, in whole pixels.
func _slide_in(dir: int) -> void:
	if _slide != null:
		_slide.kill()
	_picture.position = Vector2(dir * 16, 0)
	_slide = create_tween()
	_slide.tween_method(func(x: float) -> void: _picture.position.x = roundf(x), float(dir * 16), 0.0, 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _ui_sound(id: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.call("play_ui", id)


func _sfx(id: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.call("play_sfx", id)


## Five page dots: the current one larger and red. A click or tap on one opens its page (16 px tall hit area).
class Dots:
	extends Control

	signal picked(i: int)

	const STEP := 14
	var count := 5
	var current := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_minimum_size() -> Vector2:
		return Vector2(count * STEP, 16)

	func _draw() -> void:
		for i in count:
			var s := 6 if i == current else 4
			var x := i * STEP + int((STEP - s) / 2.0)
			var y := int((16 - s) / 2.0)
			draw_rect(Rect2(x, y, s, s), HowToPlay.C_TITLE if i == current else HowToPlay.C_DOT)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			picked.emit(clampi(int(event.position.x / STEP), 0, count - 1))
