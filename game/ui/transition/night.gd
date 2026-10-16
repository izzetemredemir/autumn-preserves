class_name Night
extends CanvasLayer
## Going to bed (spec §9): dither to night, GameState.end_day() (runs DayEnd and autosaves), a starry pause,
## then a morning card with the night's events in plain words; Continue dithers back to the scene.
##   Night.start()              -> stays in the current scene (it refreshes through GameState.changed)
##   Night.start("garden")      -> wakes up in another scene
## Returns the node (null while another night runs); `finished(events)` fires when the player is back.

signal finished(events: Array)
signal _confirmed

const SCENE := "res://ui/transition/night.tscn"
const NIGHT := Color("23282a")
const TEXT := Color("50361e")
const FRAME := Color("83571e")
const FADE_OUT_SEC := 0.8
const STARS_SEC := 1.2
const FADE_IN_SEC := 0.6
const CARD_WIDTH := 236

static var _running := false

var after_scene := ""
var _cover: DitherCover
var _sky: NightSky
var _card: PanelContainer
var _title: Label
var _lines: VBoxContainer
var _button: Button
var _accepting := false


static func start(wake_scene := "") -> Night:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or _running:
		return null
	_running = true
	var n := (load(SCENE) as PackedScene).instantiate() as Night
	n.after_scene = wake_scene
	tree.root.add_child(n)
	return n


static func is_running() -> bool:
	return _running


func _ready() -> void:
	layer = 95
	_build()
	_run()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/theme.tres")
	add_child(root)
	_cover = DitherCover.new()
	_cover.color = NIGHT
	_cover.gui_input.connect(_on_cover_input)
	root.add_child(_cover)
	_sky = NightSky.new()
	_sky.visible = false
	root.add_child(_sky)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_card = PanelContainer.new()
	_card.theme_type_variation = &"PaperPanel"
	_card.visible = false
	center.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_card.add_child(box)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.add_theme_color_override("font_color", FRAME)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 0)
	box.add_child(_lines)
	_button = Button.new()
	_button.text = "UI_CONTINUE"
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.pressed.connect(_confirm)
	box.add_child(_button)


func _run() -> void:
	Audio.stop_music(1.5)
	Audio.play_sfx("sfx_night_fade", false)
	Audio.play_jingle("jgl_night")
	await _cover.fade(DitherCover.LEVELS, FADE_OUT_SEC)
	_sky.visible = true
	await get_tree().create_timer(STARS_SEC).timeout
	var events: Array = GameState.end_day() if GameState.has_game() else []
	_show_card(events)
	Audio.play_jingle("jgl_morning")
	await get_tree().create_timer(0.3).timeout
	_accepting = true
	await _confirmed
	_accepting = false
	Audio.play_ui("ui_confirm")
	_card.visible = false
	_sky.visible = false
	if after_scene != "" and Router.exists(after_scene):
		Router.goto(after_scene)
		await get_tree().process_frame
		await get_tree().process_frame
	await _cover.fade(0, FADE_IN_SEC)
	_running = false
	finished.emit(events)
	queue_free()


func _show_card(events: Array) -> void:
	var d: Dictionary = GameState.data
	_title.text = tr("UI_NIGHT_MORNING") % int(d.get("day", 1))
	for c in _lines.get_children():
		c.queue_free()
	for l in MorningText.lines(events, d):
		var text := tr(l.key)
		if text == l.key:
			continue
		if not l.args.is_empty():
			text = text % l.args
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(CARD_WIDTH, 0)
		label.add_theme_color_override("font_color", TEXT)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		_lines.add_child(label)
	_card.visible = true
	_card.pivot_offset = Vector2(CARD_WIDTH / 2.0, 40.0).floor()
	_card.scale = Vector2(0.9, 0.9)
	create_tween().tween_property(_card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_button.grab_focus()


func _confirm() -> void:
	if _accepting:
		_confirmed.emit()


func _on_cover_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_confirm()


func _unhandled_input(event: InputEvent) -> void:
	if _accepting and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") or event.is_action_pressed("cancel")):
		get_viewport().set_input_as_handled()
		_confirm()


## Night sky over the cover: a crescent moon and twinkling one-pixel stars (fixed layout, palette colours).
class NightSky:
	extends Control
	const STAR := Color("f2d9c5")
	const DIM := Color("b4b3a0")
	const MOON := Color("e5bd7f")
	const MOON_ROWS := [
		"..###..",
		".##....",
		"##.....",
		"##.....",
		"##.....",
		".##....",
		"..###..",
	]
	var _stars: Array[Vector2i] = []
	var _t := 0.0
	var _tick := -1

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		var r := RandomNumberGenerator.new()
		r.seed = 1017
		for i in 48:
			_stars.append(Vector2i(r.randi_range(0, 1023), r.randi_range(0, 1023)))

	func _process(delta: float) -> void:
		_t += delta
		var tick := int(_t * 4.0)
		if tick != _tick:
			_tick = tick
			queue_redraw()

	func _draw() -> void:
		var w := maxi(int(size.x), 1)
		var h := maxi(int(size.y * 0.55), 1)
		for i in _stars.size():
			var p := Vector2i(_stars[i].x % w, _stars[i].y % h)
			var on := (i + _tick) % 7 != 0
			draw_rect(Rect2(p, Vector2i.ONE), STAR if on else DIM)
			if i % 9 == 0 and on:
				draw_rect(Rect2(p + Vector2i(-1, 0), Vector2i(3, 1)), DIM)
				draw_rect(Rect2(p + Vector2i(0, -1), Vector2i(1, 3)), DIM)
				draw_rect(Rect2(p, Vector2i.ONE), STAR)
		var mx := int(size.x) - 60
		for y in MOON_ROWS.size():
			var row: String = MOON_ROWS[y]
			for x in row.length():
				if row[x] == "#":
					draw_rect(Rect2(mx + x * 2, 24 + y * 2, 2, 2), MOON)
