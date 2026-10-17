class_name GameSettings
extends RefCounted
## Player settings in user://settings.cfg (spec §10): volumes, fullscreen, show seed, Granny's To-Do, language,
## show the forest grow (FIRST-60), and whether the intro was seen once (it can be skipped after that).
## Read anywhere with GameSettings.get_value("game", "show_seed"); `apply()` pushes volumes, window mode and language.

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"audio": {"music": 0.8, "sfx": 0.8, "ambient": 0.8},
	"display": {"fullscreen": false},
	"game": {"show_seed_corner": false, "tutorial": true, "language": "en", "show_grow": true, "intro_seen": false, "lang_chosen": false},
}
## L10N-TR · Languages of the settings picker: locale -> its own name (shown untranslated). English stays the default,
## whatever the OS locale is.
const LANGUAGES := {"en": "English", "tr": "Türkçe"}
## Loaded by hand when project.godot does not list it yet (and in tests): locale -> translation file.
const TRANSLATIONS := {"tr": "res://i18n/strings_tr.tr.translation"}
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


## The seed box in the wild's corner (off by default: the seed shows on the gate sign and in the forest-grow overlay).
static func show_seed() -> bool:
	return bool(get_value("game", "show_seed_corner"))


## FIRST-60: replay the map's generation the first time a wild opens each day (the first visit of a save always does).
static func show_grow() -> bool:
	return bool(get_value("game", "show_grow"))


static func tutorial_enabled() -> bool:
	return bool(get_value("game", "tutorial"))


## ONBOARD-TITLE: true once the player picked a language (first-launch card or Settings). `--skip-lang` pretends so.
static func lang_chosen() -> bool:
	var args := OS.get_cmdline_user_args()  # scripted demos and recordings (--demo) never stop at the picker
	return bool(get_value("game", "lang_chosen")) or args.has("--skip-lang") or args.has("--demo")


## Stores `lang` as the language (and that one was chosen), then applies the locale.
static func set_language(lang: String) -> void:
	set_value("game", "language", lang)
	set_value("game", "lang_chosen", true)
	apply_language(lang)


static func language() -> String:
	var l := String(get_value("game", "language"))
	return l if LANGUAGES.has(l) else "en"


## Sets the locale (TranslationServer) to `lang` ("" = the saved setting). A `--locale=xx` user argument wins, so
## smoke runs can shoot one language without touching the player's settings.
static func apply_language(lang: String = "") -> void:
	if lang == "":
		lang = language()
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--locale="):
				lang = a.substr(9)
	if not LANGUAGES.has(lang):
		lang = "en"
	ensure_translation(lang)
	if TranslationServer.get_locale().left(2) != lang:  # unchanged: no retranslation pass over the tree
		TranslationServer.set_locale(lang)


## Adds the language's translation when the project list does not have it.
static func ensure_translation(lang: String) -> void:
	if not TRANSLATIONS.has(lang) or TranslationServer.get_loaded_locales().has(lang):
		return
	if ResourceLoader.exists(TRANSLATIONS[lang]):
		var t: Translation = load(TRANSLATIONS[lang])
		if t != null:
			TranslationServer.add_translation(t)


## Volumes through the Audio autoload, plus the window mode and the language. Safe to call before Audio exists.
static func apply() -> void:
	apply_language()
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
