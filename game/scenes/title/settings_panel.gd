class_name SettingsPanel
extends PanelContainer
## Settings (spec §10): music / effects / ambience volume steps, fullscreen, show seed, Granny's To-Do, language.
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
			_first = slider.get_child(1)
	left.append([_label(tr("TITLE_SET_LANGUAGE")), _language_button()])
	var right: Array = []
	for t in TOGGLES:
		if t[2] == "show_seed_corner" and not Dev.enabled():
			continue  # RELEASE-CLEAN: the seed overlay is a dev aid; its value stays false
		right.append([_label(tr(t[0])), _toggle(String(t[1]), String(t[2]))])
	for r in maxi(left.size(), right.size()):
		for side: Array in [left, right]:
			grid.add_child(side[r][0] if r < side.size() else Control.new())
			grid.add_child(side[r][1] if r < side.size() else Control.new())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	if not in_game and Dev.enabled():
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


## SETTINGS-STEPS · A volume row: "-", a 10-segment bar, "+". One press = one step (10 %); Left / Right on the
## focused bar do the same. Stored as 0.0-1.0 (an old file's value is rounded to the nearest step on display).
func _slider(key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var bar := StepBar.new()
	bar.name = "Bar_" + key
	bar.steps = roundi(clampf(float(GameSettings.get_value("audio", key)), 0.0, 1.0) * StepBar.COUNT)
	bar.changed_to.connect(func(n: int) -> void:
		GameSettings.set_value("audio", key, snappedf(n / float(StepBar.COUNT), 0.1))
		GameSettings.apply()
		Audio.play_ui("ui_click"))
	row.add_child(_step_button("-", bar, -1))
	row.add_child(bar)
	row.add_child(_step_button("+", bar, 1))
	return row


func _step_button(text: String, bar: StepBar, dir: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(16, 16)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: bar.step(dir))
	return b


## The bar: ten 6x8 segments with 1 px ink edges (gold when filled, stone when empty), drawn in whole pixels.
class StepBar extends Control:
	signal changed_to(steps: int)
	const COUNT := 10
	const SEG := 6
	const GOLD := Color("e5bd7f")
	const STONE := Color("b4b3a0")
	const INK := Color("111010")
	var steps := 0:
		set(v):
			steps = clampi(v, 0, COUNT)
			queue_redraw()

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(COUNT * (SEG + 1) + 1, 16)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func step(dir: int) -> void:
		var n := clampi(steps + dir, 0, COUNT)
		if n != steps:
			steps = n
			changed_to.emit(n)

	func _gui_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left"):
			accept_event()
			step(-1)
		elif event.is_action_pressed("ui_right"):
			accept_event()
			step(1)

	func _draw() -> void:
		var w := COUNT * (SEG + 1) + 1
		draw_rect(Rect2(0, 4, w, 10), INK)
		for i in COUNT:
			draw_rect(Rect2(1 + i * (SEG + 1), 5, SEG, 8), GOLD if i < steps else STONE)
		if has_focus():
			draw_rect(Rect2(-1, 3, w + 2, 12), GOLD, false, 1.0)


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
