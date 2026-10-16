class_name Hud
extends CanvasLayer
## Always-on HUD (GD-HUD): energy, bag, coins, day, weather, seed toggle, toasts.
## Any scene can call `Hud.toast("UI_KEY")`; the HUD node joins group "hud".

const TOAST_SECONDS := 2.0

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
var _coins_label: Label
var _day_label: Label
var _weather: TextureRect
var _seed_btn: Button
var _seed_label: Label
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
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	row.add_child(_icon("icon_energy"))
	_energy_label = Label.new()
	row.add_child(_energy_label)
	_energy_bar = ProgressBar.new()
	_energy_bar.custom_minimum_size = Vector2(64, 8)
	_energy_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_energy_bar.show_percentage = false
	row.add_child(_energy_bar)
	row.add_child(_icon("icon_bag"))
	_bag_label = Label.new()
	row.add_child(_bag_label)
	row.add_child(_icon("icon_coin"))
	_coins_label = Label.new()
	row.add_child(_coins_label)
	_day_label = Label.new()
	row.add_child(_day_label)
	_weather = _icon("icon_weather_sun")
	row.add_child(_weather)

	_seed_btn = Button.new()
	_seed_btn.text = "UI_SEED"
	_seed_btn.toggle_mode = true
	_seed_btn.focus_mode = Control.FOCUS_NONE
	_seed_btn.position = Vector2(4, 28)
	_seed_btn.toggled.connect(func(_on: bool) -> void: _refresh())
	root.add_child(_seed_btn)
	_seed_label = Label.new()
	_seed_label.position = Vector2(4, 52)
	_seed_label.visible = false
	root.add_child(_seed_label)

	var cursor := load(ICON_DIR + "ui_cursor.png") as Texture2D
	if cursor != null:
		Input.set_custom_mouse_cursor(cursor, Input.CURSOR_ARROW, CURSOR_HOTSPOT)

	_toast_holder = Control.new()
	_toast_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_toast_holder)


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
	_weather.texture = load(ICON_DIR + WEATHER_ICONS.get(String(d.get("weather", "sunny")), "icon_weather_sun") + ".png")
	_seed_label.visible = _seed_btn.button_pressed
	_seed_label.text = "%s %d" % [tr("UI_SEED"), int(d.get("save_seed", 0))]


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


func _icon(icon_name: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(ICON_DIR + icon_name + ".png")
	t.custom_minimum_size = Vector2(16, 16)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
