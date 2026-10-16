class_name GameSettings
extends RefCounted
## Player settings in user://settings.cfg (spec §10): volumes, fullscreen, show seed, Granny's To-Do.
## Read anywhere with GameSettings.get_value("game", "show_seed"); `apply()` pushes volumes and window mode.

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"audio": {"music": 0.8, "sfx": 0.8, "ambient": 0.8},
	"display": {"fullscreen": false},
	"game": {"show_seed": true, "tutorial": true},
}
## settings.cfg audio key -> buses it drives (UI clicks follow the effects slider).
const BUSES := {"music": ["Music"], "sfx": ["SFX", "UI"], "ambient": ["Ambient"]}

static var _cfg: ConfigFile = null


static func _file() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg


static func get_value(section: String, key: String) -> Variant:
	var fallback: Variant = DEFAULTS.get(section, {}).get(key)
	var v: Variant = _file().get_value(section, key, fallback)
	if fallback != null and typeof(v) != typeof(fallback):
		return fallback
	return v


static func set_value(section: String, key: String, value: Variant) -> void:
	_file().set_value(section, key, value)
	_file().save(PATH)


static func show_seed() -> bool:
	return bool(get_value("game", "show_seed"))


static func tutorial_enabled() -> bool:
	return bool(get_value("game", "tutorial"))


## Volumes through the Audio autoload, plus the window mode. Safe to call before Audio exists.
static func apply() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var audio: Node = tree.root.get_node_or_null("Audio") if tree != null else null
	if audio != null:
		for key in BUSES:
			for bus in BUSES[key]:
				audio.set_bus_volume(bus, float(get_value("audio", key)))
	apply_window()


static func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var full := bool(get_value("display", "fullscreen"))
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if full and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not full and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
