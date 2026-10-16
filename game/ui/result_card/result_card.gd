class_name ResultCard
extends Control
## Result card shown after cooking (spec §7.3): jar at x2, name, taste chart, profile, stars, value.
## show_result(desc, quality, is_new). `desc` is a ProductGen.describe() dict; an optional "value" int is shown.
## Emits `closed` when the player confirms.

signal closed

const PAPER := Color("f2d9c5")
const FRAME := Color("83571e")
const TEXT := Color("50361e")
const GOLD := Color("e5bd7f")
const GOLD_DK := Color("b66813")
const RED := Color("c94d2e")
const EMPTY := Color("b9a697")
const INK := Color("111010")
const AXES := ["sweet", "sour", "spicy", "salty", "earthy"]
const AXIS_COLORS := [Color("e19064"), Color("c5bf3f"), Color("c94d2e"), Color("4e7664"), Color("c58845")]
const STAR := [
	"...#...",
	"...#...",
	"#######",
	".#####.",
	"..###..",
	".##.##.",
	".#...#.",
]
const FONT_BODY := preload("res://assets/fonts/m6x11plus.ttf")
const FONT_TITLE := preload("res://assets/fonts/m6x11plus.ttf")

var _built := false
var _dim: TextureRect
var _panel: PanelContainer
var _banner: Label
var _name: Label
var _profile: Label
var _jar: JarIcon
var _chart: TasteChart
var _stars: StarRow
var _value: Label
var _button: Button
var _sparkles: Sparkles
var _tween: Tween


func _ready() -> void:
	_build()


func show_result(desc: Dictionary, quality: int, is_new: bool) -> void:
	_build()
	_jar.show_product(desc)
	_name.text = str(desc.get("name", "?"))
	_profile.text = str(desc.get("profile_label", ""))
	_chart.set_taste(desc.get("taste", [0, 0, 0, 0, 0]))
	_stars.set_stars(clampi(quality, 0, 3), clampi(int(desc.get("harmony", 0)), 0, 2))
	var has_value := desc.has("value")
	_value.visible = has_value
	if has_value:
		_value.text = "%s: %d" % [tr("UI_VALUE"), int(desc["value"])]
	_banner.visible = is_new
	_button.grab_focus()
	if _tween:
		_tween.kill()
	if is_new:
		var audio := get_node_or_null("/root/Audio")
		if audio:
			audio.play_jingle("jgl_new_recipe")
		_pop_in()
	else:
		_panel.modulate.a = 1.0


func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 50% checker dither instead of a translucent fill: stays on palette.
	var di := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	di.fill(Color(0, 0, 0, 0))
	di.set_pixel(0, 0, INK)
	di.set_pixel(1, 1, INK)
	_dim = TextureRect.new()
	_dim.texture = ImageTexture.create_from_image(di)
	_dim.stretch_mode = TextureRect.STRETCH_TILE
	_dim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(190, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = FRAME
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	sb.anti_aliasing = false
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_panel.add_child(vb)

	_banner = _label(FONT_TITLE, 18, GOLD_DK)
	_banner.text = tr("UI_NEW_RECIPE")
	_banner.visible = false
	vb.add_child(_banner)

	_name = _label(FONT_TITLE, 18, TEXT)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.custom_minimum_size.x = 170
	vb.add_child(_name)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)

	var jar_box := CenterContainer.new()
	jar_box.custom_minimum_size = Vector2(52, 0)
	hb.add_child(jar_box)
	_jar = JarIcon.new()
	_jar.zoom = 2
	jar_box.add_child(_jar)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	hb.add_child(right)
	_profile = _label(FONT_BODY, 18, TEXT)
	_profile.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(_profile)
	_chart = TasteChart.new()
	right.add_child(_chart)

	_stars = StarRow.new()
	_stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(_stars)

	_value = _label(FONT_BODY, 18, TEXT)
	vb.add_child(_value)

	_button = Button.new()
	_button.text = tr("UI_CONTINUE")
	_button.add_theme_font_override("font", FONT_BODY)
	_button.add_theme_font_size_override("font_size", 18)
	_button.add_theme_color_override("font_color", PAPER)
	_button.add_theme_color_override("font_hover_color", Color("dbcc83"))
	_button.add_theme_color_override("font_focus_color", PAPER)
	_button.add_theme_color_override("font_pressed_color", Color("dbcc83"))
	for st in ["normal", "hover", "pressed", "focus"]:
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color("83571e") if st != "pressed" else Color("50361e")
		bs.border_color = Color("50361e") if st != "focus" else GOLD
		bs.set_border_width_all(2 if st == "focus" else 1)
		bs.set_content_margin_all(4)
		bs.anti_aliasing = false
		_button.add_theme_stylebox_override(st, bs)
	_button.pressed.connect(_on_close)
	vb.add_child(_button)

	_sparkles = Sparkles.new()
	_sparkles.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sparkles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sparkles)


func _label(font: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (event.is_action("ui_cancel") or event.is_action("ui_accept")):
		get_viewport().set_input_as_handled()
		_on_close()


func _on_close() -> void:
	closed.emit()


func _pop_in() -> void:
	_panel.modulate.a = 0.0
	await get_tree().process_frame
	var base := _panel.position
	var banner_c := GOLD_DK
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.08)
	_tween.tween_method(func(t: float) -> void: _panel.position = base + Vector2(0, roundf(t)), 24.0, 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_callback(func() -> void: _panel.position = base)
	var blink := create_tween().set_loops(6)
	blink.tween_callback(_banner.add_theme_color_override.bind("font_color", RED)).set_delay(0.12)
	blink.tween_callback(_banner.add_theme_color_override.bind("font_color", banner_c)).set_delay(0.12)
	_sparkles.burst(Rect2(_panel.global_position - global_position, _panel.size))


## 5 rows: axis name + 9 cells (value 0..9).
class TasteChart extends Control:
	var taste: Array = [0, 0, 0, 0, 0]

	func _init() -> void:
		custom_minimum_size = Vector2(112, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_taste(t: Array) -> void:
		taste = t
		queue_redraw()

	func _draw() -> void:
		for i in 5:
			var y := i * 11
			draw_string(FONT_BODY, Vector2(0, y + 8), tr("UI_TASTE_" + AXES[i].to_upper()), HORIZONTAL_ALIGNMENT_LEFT, 40, 18, TEXT)
			var v := clampi(int(taste[i]) if i < taste.size() else 0, 0, 9)
			for c in 9:
				draw_rect(Rect2(42 + c * 7, y + 1, 6, 7), AXIS_COLORS[i] if c < v else EMPTY)


## Quality stars (gold, max 3) then harmony stars (red, max 2), drawn 2x from a 7x7 bitmap.
class StarRow extends Control:
	var quality := 0
	var harmony := 0

	func _init() -> void:
		custom_minimum_size = Vector2(5 * 16, 14)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_stars(q: int, h: int) -> void:
		quality = q
		harmony = h
		tooltip_text = "%s %d/3  %s %d/2" % [tr("UI_STARS_QUALITY"), q, tr("UI_STARS_HARMONY"), h]
		queue_redraw()

	func _draw() -> void:
		for i in 5:
			var on := (i < quality) if i < 3 else ((i - 3) < harmony)
			var c: Color = EMPTY
			if on:
				c = GOLD if i < 3 else RED
			for y in 7:
				for x in 7:
					if STAR[y][x] == "#":
						draw_rect(Rect2(i * 16 + x * 2, y * 2, 2, 2), c)
			if i == 2:
				draw_rect(Rect2(i * 16 + 15, 2, 1, 10), FRAME)


## Pixel sparkles (plus shapes), integer positions, flicker by frame.
class Sparkles extends Control:
	var _p: Array = []

	func burst(r: Rect2) -> void:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_p.clear()
		for i in 22:
			var pos := Vector2(r.position.x + rng.randf() * r.size.x, r.position.y + rng.randf() * r.size.y)
			if rng.randf() < 0.5:  # many on the border
				pos.x = r.position.x + (0.0 if rng.randf() < 0.5 else r.size.x)
			_p.append({"pos": pos, "life": 0.5 + rng.randf() * 0.9, "age": -rng.randf() * 0.5, "big": rng.randf() < 0.4, "vy": -6.0 - rng.randf() * 10.0})
		set_process(true)

	func _ready() -> void:
		set_process(false)

	func _process(dt: float) -> void:
		var alive := false
		for s in _p:
			s["age"] += dt
			s["pos"].y += s["vy"] * dt
			if s["age"] < s["life"]:
				alive = true
		queue_redraw()
		if not alive:
			set_process(false)
			_p.clear()

	func _draw() -> void:
		for s in _p:
			if s["age"] < 0.0 or s["age"] >= s["life"]:
				continue
			var t: float = s["age"] / s["life"]
			var c := Color("f2d9c5") if t < 0.35 else (Color("dbcc83") if t < 0.7 else Color("e5bd7f"))
			if int(s["age"] * 20.0) % 3 == 2:
				continue
			var p := Vector2(roundf(s["pos"].x), roundf(s["pos"].y))
			var arm := 2 if (s["big"] and t < 0.6) else 1
			draw_rect(Rect2(p.x - arm, p.y, arm * 2 + 1, 1), c)
			draw_rect(Rect2(p.x, p.y - arm, 1, arm * 2 + 1), c)
