class_name ResultCard
extends Control
## Result card shown after cooking (spec §7.3): jar at x2, name, taste chart, profile, stars, value.
## show_result(desc, quality, is_new). `desc` is a ProductGen.describe() dict; an optional "value" int is shown.
## Emits `closed` when the player confirms.
## FEEL: every card plays in (never blocking the button): the jar drops in with a squash, its label stamps on, the
## earned stars pop in one by one with rising notes, and a "New recipe!" (or Mastered) banner gets a ribbon burst.
## QA-FIX: Continue always closes the card: it hides at once, emits `closed` once, and frees itself when nobody
## listens. A host's banner line (Mastered) comes in through show_result, before the play-in lays the card out.

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
const DROP := 20  ## px the jar falls in from
const STAR_SEMITONES := [0, 3, 7, 10, 12]  ## sfx_star_pop pitch per star, one by one (docs/audio.md)
const FONT_BODY := preload("res://assets/fonts/m6x11plus.ttf")
const FONT_TITLE := preload("res://assets/fonts/m6x11plus.ttf")

var _built := false
var _dim: Control
var _panel: PanelContainer
var _banner: Label
var _name: Label
var _profile: Label
var _jar: JarIcon
var _jar_holder: Control
var _stamp: LabelStamp
var _feel: Tween
var _chart: TasteChart
var _stars: StarRow
var _value: Label
var _button: Button
var _sparkles: Sparkles
var _tween: Tween
var _type: Tween
var _closing := false


func _ready() -> void:
	add_to_group("modal_card")  # the To-Do note hides while this is open
	_build()


## `banner`: a host's own banner line (the kitchen's "Mastered!"); "" shows "New recipe!" when `is_new`.
func show_result(desc: Dictionary, quality: int, is_new: bool, banner := "") -> void:
	_build()
	_closing = false
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_jar.show_product(desc)
	_jar_holder.custom_minimum_size = _jar.custom_minimum_size
	_stamp.setup(desc, _jar.zoom)
	_name.text = str(desc.get("name", "?"))
	_profile.text = str(desc.get("profile_label", ""))
	_chart.set_taste(desc.get("taste", [0, 0, 0, 0, 0]))
	_stars.set_stars(clampi(quality, 0, 3), clampi(int(desc.get("harmony", 0)), 0, 2))
	var has_value := desc.has("value")
	_value.visible = has_value
	if has_value:
		_value.text = "%s: %d" % [tr("UI_VALUE"), int(desc["value"])]
	if _type != null:
		_type.kill()
	_name.visible_characters = -1
	_name.custom_minimum_size.y = 0.0
	_banner.text = banner if banner != "" else tr("UI_NEW_RECIPE")
	_banner.visible = is_new or banner != ""
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
	_play_in(is_new)


func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# UI-COMPACT: a light 25% ink dither (DitherCover.dim) instead of a translucent fill: on palette, scene visible.
	_dim = DitherCover.dim()
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
	_jar_holder = Control.new()  # FEEL: the jar drops and squashes in here; the container never moves it
	_jar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jar_box.add_child(_jar_holder)
	_jar = JarIcon.new()
	_jar.zoom = 2
	_jar_holder.add_child(_jar)
	_stamp = LabelStamp.new()
	_jar.add_child(_stamp)

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


## Continue, Enter or Esc (hosts and bots call it too). Once only; the card is gone from sight and input at once,
## whatever the host does with the signal, and frees itself when nobody listens.
func _on_close() -> void:
	if _closing:
		return
	_closing = true
	for t: Tween in [_tween, _feel, _type]:
		if t != null:
			t.kill()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heard := not closed.get_connections().is_empty()
	closed.emit()
	if not heard and is_inside_tree():
		queue_free()


func _pop_in() -> void:
	_panel.modulate.a = 0.0
	await get_tree().process_frame
	if _closing or not is_inside_tree():
		return
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


## FEEL: jar drop and squash, label stamp, stars one by one, ribbons for a banner. Purely visual.
func _play_in(is_new: bool) -> void:
	if _feel != null:
		_feel.kill()
	var earned := _stars.quality + _stars.harmony
	_stars.reveal = 0
	_jar.position = Vector2(0, -DROP)
	_stamp.covered = _stamp.has_label()
	_stamp.queue_redraw()
	_feel = create_tween()
	_feel.tween_interval(0.14 if is_new else 0.05)
	_feel.tween_method(func(y: float) -> void: _jar.position.y = roundf(y), float(-DROP), 0.0, 0.2) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_feel.tween_callback(_on_jar_landed)
	_feel.tween_callback(_burst_ribbons)  # checks the banner then: kitchen shows its Mastered line after show_result
	_feel.tween_interval(0.16)
	if _stamp.has_label():
		_feel.tween_callback(_stamp_label)
		_feel.tween_interval(0.05)
		_feel.tween_callback(_stamp.set_big.bind(3))
		_feel.tween_interval(0.05)
		_feel.tween_callback(_stamp.set_big.bind(0))
		_feel.tween_interval(0.1)
	for k in earned:
		_feel.tween_callback(_pop_star.bind(k))
		_feel.tween_interval(0.13)
	if is_new:
		_celebrate()


## FIRST-60B: a new jar's name types in letter by letter with a soft tick, leaves burst from the card, the jar
## glints, and the banner pops. Purely visual.
func _celebrate() -> void:
	var n := _name.text.length()
	# Reserve the full name's height so the card does not grow line by line while it types.
	_name.custom_minimum_size.y = FONT_TITLE.get_multiline_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, 170.0, 18).y
	_name.visible_characters = 0
	_type = create_tween()
	_type.set_parallel(true)
	for k in n:
		_type.tween_callback(_type_letter.bind(k + 1)).set_delay(0.4 + 0.045 * k)
	_type.tween_callback(_leaf_confetti).set_delay(0.38)
	_type.tween_callback(_glint).set_delay(0.5)
	_type.tween_callback(_pop_banner).set_delay(0.12)


func _type_letter(count: int) -> void:
	_name.visible_characters = count
	if count % 2 == 1:
		Juice.sfx_pitched(self, "ui_click", 7.0 + float(count % 3), -14.0)


func _leaf_confetti() -> void:
	if not is_inside_tree():
		return
	var r := _panel.get_global_rect()
	Juice.leaf_burst(self, Vector2(r.get_center().x, r.end.y) - global_position, int(r.size.x), 22)
	Juice.leaf_burst(self, Vector2(r.get_center().x, r.position.y + 20.0) - global_position, int(r.size.x), 12)


func _glint() -> void:
	if not is_inside_tree():
		return
	var r := _jar_holder.get_global_rect() if _jar_holder.size.x > 0 else _jar.get_global_rect()
	Juice.sparkle(self, Rect2(r.position - global_position, r.size), 8)
	Juice.sfx_pitched(self, "sfx_sparkle", 5.0, -8.0)


func _pop_banner() -> void:
	if _banner.visible and is_inside_tree():
		Juice.pop(_banner, 2.0, 0.3)


func _on_jar_landed() -> void:
	Juice.squash(_jar, 0.25, 0.16)
	_sfx("sfx_pantry_place")


func _stamp_label() -> void:
	_stamp.covered = false
	_stamp.set_big(4)
	_sfx("sfx_board_pin")
	var t := create_tween()  # the stamp presses the jar 1 px down
	t.tween_callback(func() -> void: _jar.position.y = 1.0)
	t.tween_interval(0.06)
	t.tween_callback(func() -> void: _jar.position.y = 0.0)


func _pop_star(order: int) -> void:
	_stars.pop_star(order)
	Juice.sfx_pitched(self, "sfx_star_pop", STAR_SEMITONES[mini(order, STAR_SEMITONES.size() - 1)])


## Ribbons from the banner line (wherever kitchen's Mastered text or "New recipe!" sits right now).
func _burst_ribbons() -> void:
	if not _banner.visible:
		return
	var r := _banner.get_global_rect()
	var at := r.get_center() - global_position
	Juice.ribbons(self, Vector2(at.x, r.position.y - global_position.y + 2), mini(int(r.size.x), 90), 18)


func _sfx(id: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.play_sfx(id)


## FEEL: hides the jar's label until it stamps on: a cover in the jar's fill colour, then the label drawn 4x, 3x
## and gone (the real one shows underneath at the jar's zoom). Vessels without a label (pie, bread) have none.
class LabelStamp extends Control:
	var zoom := 2
	var rect := Rect2i()  ## label rect in jar pixels (JarIcon geometry); empty = no label
	var fill := Color()
	var tex: Texture2D
	var covered := false
	var big := 0  ## zoom of the stamp drawn over the label while it lands (0 = none)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(desc: Dictionary, z: int) -> void:
		zoom = z
		covered = false
		big = 0
		rect = Rect2i()
		tex = null
		var g := JarIcon._geometry(JarIcon._vessel(desc), false)
		if g.has("label"):
			rect = g["label"]
			tex = ImageTexture.create_from_image(JarIcon.render(desc, "shelf").get_region(rect))
			fill = JarIcon._tones(desc.get("appearance", {}))[1]
		queue_redraw()

	func has_label() -> bool:
		return tex != null

	func set_big(z: int) -> void:
		big = z
		queue_redraw()

	func _draw() -> void:
		if tex == null:
			return
		if covered:
			draw_rect(Rect2(rect.position * zoom, rect.size * zoom), fill)
		if big > 0:
			var c := Vector2(rect.position * zoom) + Vector2(rect.size * zoom) * 0.5
			var s := Vector2(rect.size * big)
			draw_texture_rect(tex, Rect2((c - s * 0.5).floor(), s), false)


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
	var reveal := 5  ## FEEL: earned stars lit so far (quality first, then harmony); the card counts it up
	var popping := -1  ## star drawn 3x for a moment as it lights up

	func _init() -> void:
		custom_minimum_size = Vector2(5 * 16, 14)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_stars(q: int, h: int) -> void:
		quality = q
		harmony = h
		tooltip_text = "%s %d/3  %s %d/2" % [tr("UI_STARS_QUALITY"), q, tr("UI_STARS_HARMONY"), h]
		queue_redraw()

	## Lights the earned star number `order` (0-based, quality then harmony) with a short 3x pop.
	func pop_star(order: int) -> void:
		reveal = order + 1
		popping = order if order < quality else 3 + order - quality
		queue_redraw()
		get_tree().create_timer(0.07).timeout.connect(_unpop)

	func _unpop() -> void:
		popping = -1
		queue_redraw()

	func _draw() -> void:
		for i in 5:
			var on := (i < quality) if i < 3 else ((i - 3) < harmony)
			on = on and (i if i < 3 else quality + i - 3) < reveal
			var c: Color = EMPTY
			if on:
				c = GOLD if i < 3 else RED
			var px := 3 if i == popping else 2
			var o := Vector2(-3, -4) if i == popping else Vector2.ZERO
			for y in 7:
				for x in 7:
					if STAR[y][x] == "#":
						draw_rect(Rect2(o.x + i * 16 + x * px, o.y + y * px, px, px), c)
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
