extends Button
## "Market today!" hotspot for the town square (MARKET): a striped cloth banner with bunting, pinned over the notice
## board on market days until the stall has opened (Market.can_open). A Button, so mouse, touch and keyboard focus
## (Tab + Enter) all open the market scene.

const C_INK := Color("111010")
const C_RED := Color("c94d2e")
const C_RED_DK := Color("a22512")
const C_CREAM := Color("f2d9c5")
const C_GOLD := Color("e5bd7f")
const C_OLIVE := Color("747c37")
const C_WOOD_DK := Color("50361e")
const C_HOVER := Color("dbcc83")
const RECT := Rect2i(184, 64, 112, 40)

var _bob: Tween
var _label: Label


func _ready() -> void:
	name = "MarketToday"
	flat = true
	focus_mode = Control.FOCUS_ALL
	position = Vector2(RECT.position)
	size = Vector2(RECT.size)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(s, empty)
	_label = Label.new()
	_label.text = tr("UI_MARKET_TODAY")
	_label.theme_type_variation = &"PaperLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(3, 14)
	_label.size = Vector2(RECT.size.x - 6, RECT.size.y - 15)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	pressed.connect(_on_pressed)
	for sig: Signal in [mouse_entered, mouse_exited, focus_entered, focus_exited]:
		sig.connect(_on_hot)
	_bob = create_tween().set_loops()
	_bob.tween_interval(0.7)
	_bob.tween_callback(func() -> void: position.y = RECT.position.y - 1)
	_bob.tween_interval(0.7)
	_bob.tween_callback(func() -> void: position.y = RECT.position.y)


func _on_hot() -> void:
	_label.add_theme_color_override("font_color", C_RED_DK if is_hovered() or has_focus() else C_WOOD_DK)
	queue_redraw()


func _on_pressed() -> void:
	var router := get_node_or_null("/root/Router")
	if router != null:
		router.goto("market")


func _draw() -> void:
	var w := int(size.x)
	var h := int(size.y)
	var hot := is_hovered() or has_focus()
	# string of bunting above the cloth
	_r(0, 1, w, 1, C_WOOD_DK)
	var cols := [C_RED, C_GOLD, C_OLIVE]
	var i := 0
	for x in range(3, w - 6, 10):
		for row in 4:
			_r(x + row, 2 + row, 7 - row * 2, 1, cols[i % cols.size()])
		i += 1
	# cloth: border, cream body, red and cream stripe hem on top
	var top := 8
	_r(2, top, w - 4, h - top, C_HOVER if hot else C_WOOD_DK)
	_r(3, top + 1, w - 6, h - top - 2, C_CREAM)
	var n := 0
	for x in range(3, w - 3, 6):
		_r(x, top + 1, mini(6, w - 3 - x), 4, C_RED if n % 2 == 0 else C_CREAM)
		n += 1
	_r(3, top + 5, w - 6, 1, C_RED_DK)
	_r(5, h - 1, w - 8, 1, C_INK)


func _r(x: int, y: int, w: int, h: int, c: Color) -> void:
	if w > 0 and h > 0:
		draw_rect(Rect2(x, y, w, h), c)
