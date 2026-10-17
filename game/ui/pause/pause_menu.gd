class_name PauseMenu
extends CanvasLayer
## PAUSE-MENU · The in-game menu: Resume, Settings (the title's SettingsPanel), Recipe book, How to Play, Save and back to title
## (a temporary game - festival, demo day, market day, Forest Lab walk, Memory - says "Back to title" and is never
## saved) and Quit game (desktop builds only) with a confirm line. A paper panel over a dithered dim; the tree is
## paused while it shows (this node runs with PROCESS_MODE_ALWAYS, the Audio node too so music and the menu's clicks
## go on; looping effects hold still). Mini-games with a real-time beat clock shift it on NOTIFICATION_UNPAUSED.
## One node under the tree root, made by ensure() and kept first among the root's children: _unhandled_input runs
## last-in-tree first, so every scene, overlay, panel, picker, card or mini-game takes Esc before the menu does.
##   PauseMenu.button()           -> the gear for the HUD's status bar (ensures the menu)
##   PauseMenu.corner_button(at)  -> the gear in a small dark frame, for scenes without the HUD (market, pantry)
##   PauseMenu.open() / is_open() -> what the gear and Esc do; only in PLAY_SCENES with a game, never over a
##                                   transition or the night (the title, intro and farewell have no menu)

signal opened
signal closed

const PLAY_SCENES := ["garden", "wild", "kitchen", "pantry", "town", "market"]
const LAYER := 80  ## over the HUD (10), the To-Do note (11) and the popups (12-60), under Transition (90) and Night (95)
const THEME := "res://ui/theme/theme.tres"
## Loaded by path, like the autoloads below (/root/Audio, /root/GameState): this script also compiles where the
## autoloads are not registered (the unit tests).
const TRANSITION := "res://ui/transition/transition.gd"
const NIGHT := "res://ui/transition/night.gd"
const BOOK := "res://ui/book/book.gd"
const SETTINGS := "res://scenes/title/settings_panel.gd"
const HOWTO := "res://ui/howto/how_to_play.gd"
const BUTTON_W := 188  ## the longest Turkish label ("Kaydet ve ana menüye dön") with room on both sides
const C_INK := Color("111010")
const C_TITLE := Color("a22512")
const C_SOFT := Color("83571e")
## 16 x 16 gear: a = ink outline, c = light, s = body, m = shade (palette colours per state in GEAR_COLORS).
const GEAR := [
	".......aa.......",
	"......acca......",
	"...aa.acca.aa...",
	"..accaaccaassa..",
	"..acccccsssssa..",
	"...acccsssssa...",
	".aaaccsaasssaaa.",
	"accccsaaaassmmma",
	"acccssaaaasmmmma",
	".aaasssaasmmaaa.",
	"...asssssmmma...",
	"..asssssmmmmma..",
	"..assaammaamma..",
	"...aa.amma.aa...",
	"......amma......",
	".......aa.......",
]
const GEAR_COLORS := {
	"normal": {"a": "111010", "c": "f2d9c5", "s": "b9a697", "m": "81746a"},
	"hover": {"a": "111010", "c": "f2d9c5", "s": "f2d9c5", "m": "b9a697"},
	"pressed": {"a": "111010", "c": "b9a697", "s": "81746a", "m": "49423d"},
}

## Tests: 1 acts as a web build (no Quit), 0 as a desktop build, -1 asks the OS.
static var web_override := -1
static var _instance: PauseMenu
static var _gears := {}

var _ui: Control
var _center: CenterContainer
var _panel: PanelContainer
var _resume: Button
var _settings_btn: Button
var _title_btn: Button
var _quit: Button
var _confirm: VBoxContainer
var _stay: Button
var _settings: PanelContainer  ## the title's SettingsPanel while Settings is open
var _open := false
var _leaving := false
var _audio_mode := Node.PROCESS_MODE_INHERIT
var _prev_focus: Control


## The one menu under the tree root, made on first use (added deferred: callers may be inside a scene's _ready).
static func ensure() -> PauseMenu:
	if is_instance_valid(_instance):
		return _instance
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_instance = PauseMenu.new()
	_instance.name = "PauseMenu"
	tree.root.add_child.call_deferred(_instance)
	return _instance


## Opens the menu when it may (see can_open). True when it opened.
static func open() -> bool:
	var m := ensure()
	if m == null or not m.is_inside_tree() or m._open or not can_open():
		return false
	m._show()
	return true


static func is_open() -> bool:
	return is_instance_valid(_instance) and _instance._open


## The open menu node, or null (tests drive its buttons).
static func current() -> PauseMenu:
	return _instance if is_open() else null


## A play scene with a game loaded, nothing paused, no scene transition and no night running.
static func can_open() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.paused:
		return false
	var router: Node = tree.root.get_node_or_null("Router")
	var gs: Node = tree.root.get_node_or_null("GameState")
	if router == null or gs == null or not gs.has_game() or String(router.get("current")) not in PLAY_SCENES:
		return false
	return not bool(load(TRANSITION).call("is_busy")) and not bool(load(NIGHT).call("is_running"))


## A game that is never written to disk (flags.temp): the festival, demo day, market day, Forest Lab walks, Memory.
static func is_temp() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("GameState") if tree != null else null
	if gs == null:
		return true
	var d: Dictionary = gs.get("data")
	var flags: Variant = d.get("flags", {})
	return flags is Dictionary and bool((flags as Dictionary).get("temp", false))


## Quit shows in desktop builds only (a web page has no window to close).
static func quit_allowed() -> bool:
	if web_override >= 0:
		return web_override == 0
	return OS.has_feature("pc") and not OS.has_feature("web")


## The gear: mouse and touch only (keyboard players press Esc), so arrow keys never land on it.
static func button() -> TextureButton:
	ensure()
	var b := TextureButton.new()
	b.name = "MenuButton"
	b.texture_normal = gear("normal")
	b.texture_hover = gear("hover")
	b.texture_pressed = gear("pressed")
	b.custom_minimum_size = Vector2(16, 16)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = b.tr("UI_PAUSE_TIP")
	b.pressed.connect(func() -> void: PauseMenu.open())
	return b


## The gear in a small dark frame (24 x 24) at `at`, for scenes without the HUD.
static func corner_button(at: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "MenuCorner"
	p.theme_type_variation = &"DarkPanel"
	p.position = at
	p.add_child(button())
	return p


static func gear(state: String) -> ImageTexture:
	if _gears.has(state):
		return _gears[state]
	var colors: Dictionary = GEAR_COLORS.get(state, GEAR_COLORS.normal)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in GEAR.size():
		var row: String = GEAR[y]
		for x in row.length():
			if colors.has(row[x]):
				img.set_pixel(x, y, Color(String(colors[row[x]])))
	var tex := ImageTexture.create_from_image(img)
	_gears[state] = tex
	return tex


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("pause_menu")
	get_parent().move_child.call_deferred(self, 0)  # first under the root: the last to be offered Esc
	var router: Node = get_node_or_null("/root/Router")
	if router != null and router.has_signal("scene_changed"):
		router.connect("scene_changed", _on_scene_changed)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("cancel"):
		return
	if _open:
		get_viewport().set_input_as_handled()
		if _leaving:
			return
		if _confirm != null and _confirm.visible:
			_hide_confirm()
		else:
			resume()
	elif can_open():
		get_viewport().set_input_as_handled()
		_show()


func _show() -> void:
	_prev_focus = get_viewport().gui_get_focus_owner()
	_open = true
	_leaving = false
	get_tree().paused = true
	_hold_audio(true)
	_build()
	visible = true
	_sound("ui_click")
	_resume.grab_focus()
	opened.emit()


## Back to the game where it was.
func resume() -> void:
	if not _open or _leaving:
		return
	_sound("ui_back")
	_close()
	if _prev_focus != null and is_instance_valid(_prev_focus) and _prev_focus.is_visible_in_tree():
		_prev_focus.grab_focus()
	_prev_focus = null


func _close() -> void:
	if not _open:
		return
	_open = false
	_leaving = false
	visible = false
	if _ui != null:
		_ui.queue_free()
	_ui = null
	_settings = null
	_confirm = null
	get_tree().paused = false
	_hold_audio(false)
	closed.emit()


func _on_scene_changed(_id: String) -> void:
	_close()


# ---------------------------------------------------------------- view

func _build() -> void:
	if _ui != null:
		remove_child(_ui)  # the rebuilt menu takes its name at once
		_ui.queue_free()
	_ui = Control.new()
	_ui.name = "Menu"
	_ui.theme = load(THEME)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing under the menu takes a click or a tap
	add_child(_ui)
	_ui.add_child(_dim())
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme_type_variation = &"PaperPanel"
	_center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_panel.add_child(box)
	var head := _label(tr("UI_PAUSE_TITLE"), C_TITLE)
	box.add_child(head)
	_resume = _button(box, "Resume", tr("UI_PAUSE_RESUME"), resume)
	_settings_btn = _button(box, "Settings", tr("UI_PAUSE_SETTINGS"), _open_settings)
	_button(box, "Book", tr("UI_PAUSE_BOOK"), _open_book)
	_button(box, "HowTo", tr("HOWTO_TITLE"), _open_how_to)
	var title_text := tr("UI_PAUSE_TO_TITLE") if is_temp() else tr("UI_PAUSE_SAVE_TITLE")
	_title_btn = _button(box, "ToTitle", title_text, _leave_to_title)
	_quit = _button(box, "Quit", tr("UI_PAUSE_QUIT"), _ask_quit)
	_quit.visible = quit_allowed()
	_confirm = VBoxContainer.new()
	_confirm.name = "Confirm"
	_confirm.visible = false
	_confirm.add_theme_constant_override("separation", 3)
	box.add_child(_confirm)
	var line := _label(_quit_line(), C_SOFT)
	line.name = "Line"
	_confirm.add_child(line)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	_confirm.add_child(row)
	var yes := Button.new()
	yes.name = "QuitNow"
	yes.text = tr("UI_PAUSE_QUIT_YES")
	yes.custom_minimum_size = Vector2(72, 22)
	yes.pressed.connect(_quit_now)
	row.add_child(yes)
	_stay = Button.new()
	_stay.name = "Stay"
	_stay.text = tr("UI_PAUSE_QUIT_NO")
	_stay.custom_minimum_size = Vector2(72, 22)
	_stay.pressed.connect(_hide_confirm)
	row.add_child(_stay)


## The quit confirm line: what happens to the day.
func _quit_line() -> String:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and TodoRules.is_festival(gs.get("data")):
		return tr("UI_PAUSE_QUIT_FESTIVAL")
	return tr("UI_PAUSE_QUIT_TEMP") if is_temp() else tr("UI_PAUSE_QUIT_SAVED")


func _button(box: VBoxContainer, node_name: String, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(BUTTON_W, 22)
	b.pressed.connect(on_press)
	box.add_child(b)
	return b


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"PaperLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	return l


## Every other pixel ink (no alpha): the game shows through, dimmed.
func _dim() -> TextureRect:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixel(0, 0, C_INK)
	img.set_pixel(1, 1, C_INK)
	var dim := TextureRect.new()
	dim.texture = ImageTexture.create_from_image(img)
	dim.stretch_mode = TextureRect.STRETCH_TILE
	dim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dim


# ---------------------------------------------------------------- actions

func _open_settings(sound := true) -> void:
	if sound:
		_sound("ui_click")
	_panel.visible = false
	_settings = (load(SETTINGS) as GDScript).new()
	_settings.set("in_game", true)
	_settings.connect("closed", _on_settings_closed)
	_settings.connect("language_changed", _on_language_changed, CONNECT_DEFERRED)  # rebuilt after the press
	_center.add_child(_settings)
	_settings.call("open")


func _on_settings_closed() -> void:
	if _settings != null:
		_settings.queue_free()
	_settings = null
	_panel.visible = true
	_settings_btn.grab_focus()


## The menu is built again in the new language (Settings stays open); the HUD's texts follow at once, the scene's
## own texts on its next change.
func _on_language_changed() -> void:
	if not _open:
		return
	_build()
	_open_settings(false)
	var lang := _settings.find_child("Language", true, false) as Button
	if lang != null:
		lang.grab_focus()
	get_tree().call_group("hud", "_refresh")


func _open_book() -> void:
	resume()
	load(BOOK).call("open")


## ONBOARD-HOWTO: the How to Play book over the paused game (inside the menu's view, so it goes with the menu); the
## menu comes back when it closes.
func _open_how_to() -> void:
	_sound("ui_click")
	_panel.visible = false
	var h: Node = load(HOWTO).call("open", _ui)
	h.connect("closed", _on_how_to_closed, CONNECT_ONE_SHOT)


func _on_how_to_closed() -> void:
	if not _open or _panel == null or not is_instance_valid(_panel):
		return
	_panel.visible = true
	(_panel.find_child("HowTo", true, false) as Button).grab_focus()


## Normal games save first; a temporary game is left as it is. The scene stops at once (a running mini-game is
## abandoned before its result, so its ingredients stay where they were) and the transition fades to the title.
func _leave_to_title() -> void:
	if _leaving:
		return
	_leaving = true
	_sound("ui_confirm")
	_save_now()
	_stop_loops()
	var scene := get_tree().current_scene
	if scene != null:
		scene.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	load(TRANSITION).call("go", "title")


func _ask_quit() -> void:
	_sound("ui_click")
	_quit.visible = false
	_confirm.visible = true
	_stay.grab_focus()


func _hide_confirm() -> void:
	_sound("ui_back")
	_confirm.visible = false
	_quit.visible = quit_allowed()
	_quit.grab_focus()


func _quit_now() -> void:
	if _leaving:
		return
	_leaving = true
	_save_now()
	_stop_loops()
	get_tree().quit()


# ---------------------------------------------------------------- sound and save

func _sound(id: String) -> void:
	var audio: Node = get_node_or_null("/root/Audio")
	if audio != null:
		audio.call("play_ui", id)


## Normal games only: Save.save_game skips temporary ones anyway, GameState.save_now says so too.
func _save_now() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and not is_temp():
		gs.call("save_now")


## While the menu shows, the Audio node runs (music, ambience and the menu's clicks; volume changes are heard) and
## looping effects (the stir pot, the brine) hold still; both go back as they were on resume.
func _hold_audio(on: bool) -> void:
	var audio: Node = get_node_or_null("/root/Audio")
	if audio == null:
		return
	if on:
		_audio_mode = audio.process_mode
		audio.process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		audio.process_mode = _audio_mode
	for p in _loop_players(audio):
		p.stream_paused = on


func _stop_loops() -> void:
	var audio: Node = get_node_or_null("/root/Audio")
	if audio == null:
		return
	var loops: Variant = audio.get("_loops")
	if loops is Dictionary:
		for id: String in (loops as Dictionary).keys():
			audio.call("set_loop_sfx", id, false)


func _loop_players(audio: Node) -> Array:
	var out: Array = []
	var loops: Variant = audio.get("_loops")
	if loops is Dictionary:
		for p: Variant in (loops as Dictionary).values():
			if p is AudioStreamPlayer and is_instance_valid(p):
				out.append(p)
	return out
