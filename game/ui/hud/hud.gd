class_name Hud
extends CanvasLayer
## Always-on HUD (GD-HUD): energy, bag, coins, day, weather, toasts (the seed label is drawn by the garden/wild scenes).
## CALENDAR-WEATHER: the harvest week's name after the weather icon from day 8 (MorningText.week_name; hidden before;
## "Autumn N" only in its tooltip), the weather's name as the icon's tooltip (UI_WEATHER_*).
## Any scene can call `Hud.toast("UI_KEY")`; the HUD node joins group "hud".
## PAUSE-MENU: a gear at the status bar's right end opens the in-game menu (ui/pause); Esc opens it too.

const TOAST_SECONDS := 2.0
const BAR_W := 472  ## HUD-BAR: x 4..476 on the 480 px screen

const ICON_DIR := "res://assets/sprites/ui/"
const CURSOR_HOTSPOT := Vector2(1, 1)

const WEATHER_ICONS := {
	"sunny": "icon_weather_sun", "rainy": "icon_weather_rain",
	"windy": "icon_weather_wind", "foggy": "icon_weather_fog",
}

const C_INK := Color("111010")
const C_GOLD := Color("e5bd7f")
const C_AMBER := Color("b66813")
const C_CREAM := Color("f2d9c5")
const C_WATER := Color("567c7d")
const C_SAGE := Color("738c7a")
const C_STONE := Color("b4b3a0")

var _energy_bar: ProgressBar
var _energy_label: Label
var _bag_label: Label
var _bag_icon: TextureRect
var _coins_label: Label
var _day_label: Label
var _weather: TextureRect
var _week_label: Label
var _bar: PanelContainer  ## the full-width status bar (Granny's To-Do note sits right under it)
var _sound_btn: TextureButton
var _toast_holder: Control
var _toast_tween: Tween


## Static helper: shows tr(key) (formatted with args if given) for 2 s on the active HUD.
static func toast(key: String, args := []) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Hud
	if hud != null:
		hud.show_toast(key, args)


func _ready() -> void:
	layer = 10
	add_to_group("hud")
	_build()
	GameState.changed.connect(_on_changed)
	_refresh()


func _build() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = load("res://ui/theme/theme.tres")
	add_child(root)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DarkPanel"
	panel.position = Vector2(4, 4)
	panel.custom_minimum_size = Vector2(BAR_W, 0)  # HUD-BAR: the bar spans x 4..476
	root.add_child(panel)
	_bar = panel
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	row.add_child(_icon("icon_energy", "UI_TIP_ENERGY"))
	_energy_label = Label.new()
	row.add_child(_energy_label)
	_energy_bar = ProgressBar.new()
	_energy_bar.custom_minimum_size = Vector2(64, 8)
	_energy_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_energy_bar.show_percentage = false
	row.add_child(_energy_bar)
	_bag_icon = _icon("icon_bag", "UI_TIP_BAG")
	row.add_child(_bag_icon)
	_bag_label = Label.new()
	row.add_child(_bag_label)
	row.add_child(_icon("icon_coin", "UI_TIP_COINS"))
	_coins_label = Label.new()
	row.add_child(_coins_label)
	_day_label = Label.new()
	_day_label.add_theme_color_override("font_color", C_GOLD)  # JURY-MG: the day reads apart from the counters
	row.add_child(_day_label)
	_weather = _icon("icon_weather_sun")
	_weather.mouse_filter = Control.MOUSE_FILTER_PASS  # tooltip: the weather's name
	row.add_child(_weather)
	_week_label = Label.new()
	_week_label.visible = false
	_week_label.mouse_filter = Control.MOUSE_FILTER_PASS  # tooltip: the week with its "Autumn N"
	row.add_child(_week_label)
	var spacer := Control.new()  # HUD-BAR: pushes the sound toggle and the gear to the bar's right end
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_sound_btn = TextureButton.new()
	_sound_btn.name = "SoundButton"
	_sound_btn.custom_minimum_size = Vector2(16, 16)
	_sound_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sound_btn.focus_mode = Control.FOCUS_NONE
	_sound_btn.pressed.connect(func() -> void: Audio.set_muted(not Audio.is_muted()))
	row.add_child(_sound_btn)
	Audio.muted_changed.connect(func(_m: bool) -> void: _refresh_sound())
	_refresh_sound()
	row.add_child(PauseMenu.button())  # PAUSE-MENU: the gear at the bar's right end (Esc opens the same menu)

	var cursor := load(ICON_DIR + "ui_cursor.png") as Texture2D
	if cursor != null:
		Input.set_custom_mouse_cursor(cursor, Input.CURSOR_ARROW, CURSOR_HOTSPOT)

	_toast_holder = Control.new()
	_toast_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_toast_holder)


## The speaker icon and its tooltip follow the Master mute (button click or the M key).
func _refresh_sound() -> void:
	var muted: bool = Audio.is_muted()
	_sound_btn.texture_normal = load(ICON_DIR + ("icon_sound_off" if muted else "icon_sound_on") + ".png")
	_sound_btn.tooltip_text = tr("UI_TIP_SOUND_OFF" if muted else "UI_TIP_SOUND_ON")


func _on_changed(_keys: PackedStringArray) -> void:
	_refresh()


func _refresh() -> void:
	if _energy_label == null:
		return
	var d: Dictionary = GameState.data
	if d.is_empty():
		return
	var e := int(d.get("energy", 0))
	var emax := int(d.get("energy_max", 80))
	_energy_label.text = "%d/%d" % [e, emax]
	_energy_bar.max_value = emax
	_energy_bar.value = e
	_bag_label.text = str(Forage.bag_count(d))
	_coins_label.text = str(int(d.get("coins", 0)))
	_day_label.text = "%s %d" % [tr("UI_DAY"), int(d.get("day", 1))]
	var w := String(d.get("weather", "sunny"))
	_weather.texture = load(ICON_DIR + WEATHER_ICONS.get(w, "icon_weather_sun") + ".png")
	_weather.tooltip_text = tr("UI_WEATHER_" + w.to_upper()) if WEATHER_ICONS.has(w) else ""
	_week_label.text = MorningText.week_name(int(d.get("day", 1)), false)  # short: the HUD row must fit 480 px
	_week_label.tooltip_text = MorningText.week_name(int(d.get("day", 1)))
	_week_label.visible = _week_label.text != ""


func show_toast(key: String, args := []) -> void:
	for c in _toast_holder.get_children():
		c.queue_free()
	var text := tr(key)
	if not args.is_empty():
		text = text % args
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DarkPanel"
	var label := Label.new()
	label.text = text
	panel.add_child(label)
	_toast_holder.add_child(panel)
	await get_tree().process_frame
	if not is_instance_valid(panel) or panel.is_queued_for_deletion():
		return  # a newer toast replaced this one within the same frame
	var vp := get_viewport().get_visible_rect().size
	panel.position = Vector2(int((vp.x - panel.size.x) / 2.0), 40)
	panel.pivot_offset = (panel.size / 2.0).floor()
	panel.scale = Vector2(1.5, 1.5)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(panel, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(TOAST_SECONDS)
	_toast_tween.tween_callback(panel.queue_free)


func _icon(icon_name: String, tip_key := "") -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(ICON_DIR + icon_name + ".png")
	t.custom_minimum_size = Vector2(16, 16)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tip_key != "":
		t.mouse_filter = Control.MOUSE_FILTER_PASS  # JURY-MG: hover names the icon for a newcomer
		t.tooltip_text = tr(tip_key)
	return t


## FEEL: screen point (HUD canvas) in the middle of the bag icon, for picked things flying into the bag;
## (-1, -1) when no HUD is showing.
static func bag_point() -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	var hud := tree.get_first_node_in_group("hud") as Hud if tree != null else null
	if hud == null or hud._bag_icon == null or not hud._bag_icon.is_visible_in_tree():
		return Vector2(-1, -1)
	return hud._bag_icon.get_global_rect().get_center().floor()


## The status bar's screen rect (HUD canvas), or an empty rect when no HUD is showing. The To-Do note reads it
## so it never covers the week name on a wide bar.
static func bar_rect() -> Rect2:
	var tree := Engine.get_main_loop() as SceneTree
	var hud := tree.get_first_node_in_group("hud") as Hud if tree != null else null
	if hud == null or hud._bar == null or not hud._bar.is_visible_in_tree():
		return Rect2()
	return hud._bar.get_global_rect()


## FEEL: the bag icon and its counter bump (something just landed in the bag).
static func bump_bag() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var hud := tree.get_first_node_in_group("hud") as Hud if tree != null else null
	if hud == null or hud._bag_icon == null:
		return
	Juice.pop(hud._bag_icon, 1.5, 0.16)
	Juice.pop(hud._bag_label, 1.5, 0.16)
