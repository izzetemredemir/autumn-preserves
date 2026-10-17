class_name SettingsPanel
extends PanelContainer
## Settings (spec §10): music / effects / ambience sliders, fullscreen, show seed, Granny's To-Do, language.
## Every change is applied at once and written to user://settings.cfg (GameSettings). Emits `closed`, and
## `language_changed` after the locale switched (the title rebuilds itself in the new language).
## PAUSE-MENU: the in-game menu reuses it with `in_game = true` (set before adding it): no Demo day / Market day
## buttons there, since they would replace the game being played.

signal closed
signal language_changed

const SLIDERS := [["TITLE_SET_MUSIC", "music"], ["TITLE_SET_SFX", "sfx"], ["TITLE_SET_AMBIENT", "ambient"]]
const TOGGLES := [
	["TITLE_SET_FULLSCREEN", "display", "fullscreen"],
	["TITLE_SET_SHOW_SEED", "game", "show_seed_corner"],
	["TITLE_SET_TUTORIAL", "game", "tutorial"],
	["WORLD_GROW_SETTING", "game", "show_grow"],
]

var in_game := false
var _first: Control


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	var head := Label.new()
	head.text = tr("TITLE_SETTINGS")
	head.theme_type_variation = &"Heading"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	# Two label/control pairs per row (FIRST-60: eight rows in one column no longer fit under the logo):
	# the sliders and the language on the left, the toggles on the right.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	var left: Array = []
	for s in SLIDERS:
		var slider := _slider(String(s[1]))
		left.append([_label(tr(s[0])), slider])
		if _first == null:
			_first = slider
	left.append([_label(tr("TITLE_SET_LANGUAGE")), _language_button()])
	var right: Array = []
	for t in TOGGLES:
		right.append([_label(tr(t[0])), _toggle(String(t[1]), String(t[2]))])
	for r in maxi(left.size(), right.size()):
		for side: Array in [left, right]:
			grid.add_child(side[r][0] if r < side.size() else Control.new())
			grid.add_child(side[r][1] if r < side.size() else Control.new())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	if not in_game:
		var demo := Button.new()  # the jury demo day, in every build (it never touches the player's save)
		demo.text = tr("TITLE_DEMO_DAY")
		demo.tooltip_text = tr("TITLE_DEMO_DAY_TIP")
		demo.pressed.connect(_play_demo_day)
		row.add_child(demo)
		var market := Button.new()  # the same save on its first market day (day 7), straight to the stall
		market.text = tr("TITLE_MARKET_DAY")
		market.tooltip_text = tr("TITLE_MARKET_DAY_TIP")
		market.pressed.connect(_play_market_day)
		row.add_child(market)
	var back := Button.new()
	back.text = tr("UI_BACK")
	back.pressed.connect(_close)
	row.add_child(back)


func open() -> void:
	visible = true
	if _first != null:
		_first.grab_focus()


func _close() -> void:
	Audio.play_ui("ui_back")
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _slider(key: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.1
	s.custom_minimum_size = Vector2(100, 16)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value = float(GameSettings.get_value("audio", key))
	_style_slider(s)
	s.value_changed.connect(func(v: float) -> void:
		GameSettings.set_value("audio", key, snappedf(v, 0.1))
		GameSettings.apply()
		Audio.play_ui("ui_click"))
	return s


## A plain button whose label shows the state (a pressed-looking "On" would read as disabled).
func _toggle(section: String, key: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(48, 0)
	b.text = tr("TITLE_ON") if bool(GameSettings.get_value(section, key)) else tr("TITLE_OFF")
	b.pressed.connect(func() -> void:
		var on := not bool(GameSettings.get_value(section, key))
		b.text = tr("TITLE_ON") if on else tr("TITLE_OFF")
		GameSettings.set_value(section, key, on)
		GameSettings.apply()
		Audio.play_ui("ui_click"))
	return b


## L10N-TR · Language: English / Türkçe, each name in its own language. A press moves to the next one, stores it
## and applies the locale.
func _language_button() -> Button:
	var b := Button.new()
	b.name = "Language"
	b.custom_minimum_size = Vector2(48, 0)
	b.text = String(GameSettings.LANGUAGES[GameSettings.language()])
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.pressed.connect(func() -> void:
		var codes: Array = GameSettings.LANGUAGES.keys()
		var next := String(codes[(codes.find(GameSettings.language()) + 1) % codes.size()])
		GameSettings.set_language(next)
		b.text = String(GameSettings.LANGUAGES[next])
		Audio.play_ui("ui_click")
		language_changed.emit())
	return b


## Pixel slider look: flat 6 px track, amber fill, 6x10 grabber, no anti-aliasing.
func _style_slider(s: HSlider) -> void:
	var track := _box(Color("3d1f29"), Color("111010"))
	var fill := _box(Color("b66813"), Color("111010"))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.anti_aliasing = false
	focus.set_border_width_all(1)
	focus.border_color = Color("e5bd7f")
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_stylebox_override("focus", focus)
	s.add_theme_icon_override("grabber", _grabber(Color("e5bd7f")))
	s.add_theme_icon_override("grabber_highlight", _grabber(Color("f2d9c5")))
	s.add_theme_icon_override("grabber_disabled", _grabber(Color("81746a")))


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(1)
	b.anti_aliasing = false
	b.content_margin_top = 3
	b.content_margin_bottom = 3
	return b


func _grabber(c: Color) -> ImageTexture:
	var img := Image.create(6, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color("111010"))
	img.fill_rect(Rect2i(1, 1, 4, 8), c)
	img.fill_rect(Rect2i(1, 8, 4, 1), Color("b66813"))
	return ImageTexture.create_from_image(img)


## The jury demo save (seed 452, day 3, rainy, the rare crabapple) as a temporary game: it is never written to disk,
## so it cannot overwrite the player's own save. Works in release builds (the F1 dev panel is debug only).
func _play_demo_day() -> void:
	if _load_demo_temp():
		_leave_to("garden")


## The demo save moved to its first market day (day 7, sunny) and straight to the market stall: the weekly market
## can be shown live without playing four days first. Same temporary game, the player's save stays untouched.
func _play_market_day() -> void:
	if not _load_demo_temp():
		return
	var d: Dictionary = GameState.data
	d.day = Market.EVERY
	d.weather = "sunny"
	GameState.notify(PackedStringArray(["day", "weather"]))
	_leave_to("market")


func _load_demo_temp() -> bool:
	var d := DevTools.load_demo()
	if d.is_empty():
		return false
	if typeof(d.get("flags")) != TYPE_DICTIONARY:
		d["flags"] = {}
	d.flags["temp"] = true
	GameState.data = d
	GameState.notify(PackedStringArray(["*"]))
	load("res://ui/tutorial/granny_todo.gd").ensure()
	return true


func _leave_to(scene_id: String) -> void:
	Audio.play_ui("ui_confirm")
	visible = false
	Transition.go(scene_id)
