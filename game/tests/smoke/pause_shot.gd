extends SceneTree
## Smoke shot (PAUSE-MENU): the in-game menu, by the gear and by Esc, through real input events.
##   1. a normal game (the demo save): garden (gear, Esc, Settings: the music slider moves and is
##      stored, Esc back, Recipe book: Esc closes the book first, the next Esc opens the menu), wild, town, pantry;
##      kitchen: the cook panel takes Esc first, a stir mini-game pauses under the menu and runs on after Resume,
##      then Save and back to title from inside it: the save is written, the ingredients are still there, no jam;
##   2. market day (a temporary game): the gear above the sign card, Esc, Quit with its confirm line, Quit hidden on
##      web, Back to title: the save file is untouched;
##   3. the Harvest Festival: Esc closes the start card, the next Esc opens the menu (festival line), Back to title:
##      the save file is untouched.
## user://save.json is shared with the player and other windowed runs: the normal game travels as a temporary game
## (scene changes never write it) and is only real while its menu is open, and for the one Save and back to title,
## with the save file backed up just before and put back right after. The music setting is set back at once;
## settings.cfg is checked byte for byte at the end.
## Shots: user://shots/pause_gear.png (the HUD bar's end at x4), pause_garden, pause_settings, pause_wild,
## pause_minigame, pause_market, pause_quit, pause_festival (+ "_tr" with -- --locale=tr).
##   godot --path game --audio-driver Dummy -s res://tests/smoke/pause_shot.gd   (about 40 s; exit 1 on a failed check)

const SAVE := "user://save.json"
const SETTINGS := "user://settings.cfg"
const TRANSITION := "res://ui/transition/transition.gd"

var _gs: Node
var _fail := 0
var _suffix := ""
var _backup := {}  ## path -> file bytes (missing files: null)
var _save_out := false  ## the save file holds the smoke's game until _put_save_back()


func _initialize() -> void:
	_gs = root.get_node("GameState")
	if "--locale=tr" in OS.get_cmdline_user_args():
		GameSettings.apply_language("tr")
		_suffix = "_tr"
	_backup[SETTINGS] = _bytes(SETTINGS)
	_run()


func _run() -> void:
	await process_frame
	PauseMenu.web_override = 0  # act as a desktop build until the web check
	await _normal_game()
	await _market_day()
	await _festival()
	_finish()


# ---------------------------------------------------------------- 1. a normal game

func _normal_game() -> void:
	var d := DevTools.load_demo()
	if not _check(not d.is_empty(), "demo save loads"):
		return
	if typeof(d.get("flags")) != TYPE_DICTIONARY:
		d["flags"] = {}
	d.flags["temp"] = true  # until a check needs a real game: no scene change writes the player's save
	for v: String in d.varieties:  # fresh fruit for a jam (as the kitchen's debug fill)
		var t := State.type_of_variety(v)
		if Data.ingredients()[t].group != "nut" and v.ends_with("_1"):
			d.inbox.append(State.fresh(v, 5, int(Data.ingredients()[t].shelf_days)))
	_gs.data = d
	_gs.notify(PackedStringArray(["*"]))
	if not await _go("garden"):
		return
	await _seconds(0.5)

	# gear
	var gear := _hud_gear()
	_check(gear != null and gear.is_visible_in_tree(), "garden: a gear at the end of the HUD bar")
	if gear != null:
		var bar := (get_first_node_in_group("hud").get("_bar") as Control).get_global_rect()  # not Hud: it needs the autoloads to compile
		_shot_zoom("pause_gear", Rect2i(int(bar.end.x) - 120, 0, 124, int(bar.end.y) + 4))
		_check(gear.get_global_rect().end.x <= bar.end.x and gear.get_global_rect().end.x > bar.end.x - 16, "garden: the gear is the bar's last item")
		_real(true)  # read when the menu is built; nothing is written while it is open
		await _click(gear)
	_check(PauseMenu.is_open() and paused, "garden: the gear opens the menu and pauses the game")
	var m := PauseMenu.current()
	_check(m != null and get_root().gui_get_focus_owner() == m._resume, "focus starts on Resume")
	_check(m != null and m._title_btn.text == TranslationServer.translate("UI_PAUSE_SAVE_TITLE"), "a normal game says Save and back to title")
	_shot("pause_garden")
	_key(KEY_ESCAPE)
	await _frames(2)
	_real(false)
	_check(not PauseMenu.is_open() and not paused, "Esc in the menu resumes")
	_key(KEY_ESCAPE)
	await _frames(2)
	_check(PauseMenu.is_open() and paused, "garden: Esc opens the menu")

	# Settings: keyboard down + Enter, the music slider moves and is stored, Esc back to the menu
	_key(KEY_DOWN)
	await _frames(1)
	_key(KEY_ENTER)
	await _frames(3)
	m = PauseMenu.current()
	var sp: Control = m._settings if m != null else null
	_check(sp != null and sp.visible and not m._panel.visible, "Settings opens the title's settings panel in the menu")
	if sp != null:
		_check(not _has_text(sp, TranslationServer.translate("TITLE_DEMO_DAY")), "no Demo day button inside a game")
		var before := float(GameSettings.get_value("audio", "music"))
		_key(KEY_LEFT if before > 0.05 else KEY_RIGHT)  # the music slider has the focus
		await _frames(2)
		var after := float(GameSettings.get_value("audio", "music"))
		_check(not is_equal_approx(before, after), "a setting changes and is stored (music %.1f -> %.1f)" % [before, after])
		_shot("pause_settings")
		GameSettings.set_value("audio", "music", before)  # the player's setting, back at once
		GameSettings.apply()
		_key(KEY_ESCAPE)
		await _frames(2)
		_check(PauseMenu.is_open() and m._panel.visible and m._settings == null, "Esc closes Settings, the menu stays")
		_check(get_root().gui_get_focus_owner() == m._settings_btn, "focus back on Settings")
	# Recipe book: the menu closes, the book's own Esc comes first, the next Esc opens the menu
	if m != null:
		m._open_book()
	await _frames(6)
	_check(not PauseMenu.is_open() and not paused and get_first_node_in_group("book") != null, "Recipe book opens the book")
	_key(KEY_ESCAPE)
	await _frames(3)
	_check(get_first_node_in_group("book") == null and not PauseMenu.is_open(), "Esc closes the book first")
	_key(KEY_ESCAPE)
	await _frames(2)
	_check(PauseMenu.is_open(), "the next Esc opens the menu")
	_key(KEY_ESCAPE)
	await _frames(2)

	# wild
	if await _go("wild", {"biome": "forest"}):
		await _until(func() -> bool: return not _growing(), 10000)
		await _frames(10)
		await _gear_and_esc("wild")
		_key(KEY_ESCAPE)
		await _frames(2)
		_check(PauseMenu.is_open(), "wild: Esc opens the menu")
		_shot("pause_wild")
		_key(KEY_ESCAPE)
		await _frames(2)
	# town: Esc no longer leaves the square
	if await _go("town"):
		_key(KEY_ESCAPE)
		await _frames(2)
		_check(PauseMenu.is_open() and _scene_id() == "town", "town: Esc opens the menu (and stays in town)")
		_key(KEY_ESCAPE)
		await _frames(2)
	# pantry: the gear beside Back
	if await _go("pantry"):
		var corner := current_scene.find_child("MenuCorner", true, false) as Control
		_check(corner != null and corner.is_visible_in_tree(), "pantry: a gear beside Back")
		if corner != null:
			await _click(corner)
		_check(PauseMenu.is_open(), "pantry: the gear opens the menu")
		_key(KEY_ESCAPE)
		await _frames(2)
		_key(KEY_ESCAPE)
		await _frames(2)
		_check(PauseMenu.is_open() and _scene_id() == "pantry", "pantry: Esc opens the menu (and stays in the pantry)")
		_key(KEY_ESCAPE)
		await _frames(2)
	await _kitchen()


func _kitchen() -> void:
	if not await _go("kitchen"):
		return
	await _frames(10)
	var k := current_scene
	await _gear_and_esc("kitchen")
	k._on_spot("stove")
	await _frames(4)
	var panel: Node = k._panel
	_check(panel.visible, "kitchen: the stove opens the cook panel")
	_key(KEY_ESCAPE)
	await _frames(3)
	_check(not panel.visible and not PauseMenu.is_open(), "kitchen: Esc closes the cook panel first")
	k._on_spot("stove")
	await _frames(4)
	panel._select_recipe("jam")
	await _frames(2)
	var fruit := ""
	var stock: Dictionary = panel.fresh_stock(_gs.data)
	for v: String in stock:
		if int(stock[v]) >= 3 and panel._fits("main", v):
			fruit = v
			break
	if not _check(fruit != "", "a fruit for the jam"):
		return
	panel._pick(fruit, panel)
	await _frames(2)
	var stock_before := int(stock[fruit])
	var jams_before := _jams()
	panel._on_cook()
	await _until(func() -> bool: return k._mg != null, 3000)
	_check(k._mg != null, "the stir mini-game runs")
	await _seconds(1.0)
	_key(KEY_ESCAPE)
	await _frames(3)
	_check(PauseMenu.is_open() and k._mg != null and not k._mg.can_process(), "the menu opens over the mini-game and pauses it")
	_shot("pause_minigame")
	_key(KEY_ESCAPE)
	await _frames(3)
	_check(not PauseMenu.is_open() and k._mg != null and k._mg.can_process(), "Resume: the mini-game runs on")
	_key(KEY_ESCAPE)
	await _frames(2)
	# Save and back to title from inside the cook: the only time the smoke writes the save file
	var m := PauseMenu.current()
	if m != null:
		_backup[SAVE] = _bytes(SAVE)
		_save_out = true
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
		_real(true)
		await _click(m._title_btn)
	await _until(func() -> bool: return _scene_id() == "title" and not _busy(), 6000)
	_check(_scene_id() == "title" and not PauseMenu.is_open() and not paused, "Save and back to title reaches the title")
	_check(FileAccess.file_exists(SAVE), "a normal game is saved on the way")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE)) if FileAccess.file_exists(SAVE) else {}
	var saved: Dictionary = parsed if parsed is Dictionary else {}
	_check(int(load("res://scenes/kitchen/cook_panel.gd").fresh_stock(saved).get(fruit, 0)) == stock_before, "the abandoned cook kept its fruit (%d)" % stock_before)
	_check(_jams(saved) == jams_before, "no jam was made")
	_put_save_back()
	var loops: Variant = root.get_node("Audio").get("_loops")
	_check(loops is Dictionary and (loops as Dictionary).is_empty(), "no looping effect left playing")


# ---------------------------------------------------------------- 2. market day (temporary)

func _market_day() -> void:
	var d := DevTools.load_demo()
	if d.is_empty():
		return
	if typeof(d.get("flags")) != TYPE_DICTIONARY:
		d["flags"] = {}
	d.flags["temp"] = true
	d.day = Market.EVERY
	d.weather = "sunny"
	_gs.data = d
	_gs.notify(PackedStringArray(["*"]))
	var disk: Variant = _bytes(SAVE)
	if not await _go("market"):
		return
	await _frames(20)
	var corner := current_scene.find_child("MenuCorner", true, false) as Control
	_check(corner != null and corner.is_visible_in_tree(), "market: a gear above the sign card")
	if corner != null:
		await _click(corner)
	_check(PauseMenu.is_open() and paused, "market: the gear opens the menu")
	var m := PauseMenu.current()
	_check(m != null and m._title_btn.text == TranslationServer.translate("UI_PAUSE_TO_TITLE"), "a temporary game says Back to title")
	_shot("pause_market")
	_key(KEY_ESCAPE)
	await _frames(2)
	_key(KEY_ESCAPE)
	await _frames(2)
	_check(PauseMenu.is_open() and _scene_id() == "market", "market: Esc opens the menu (and stays at the stall)")
	m = PauseMenu.current()
	# Quit: a confirm line inside the panel; Esc takes it back
	if m != null:
		_check(m._quit.visible, "desktop: Quit game shows")
		await _click(m._quit)
		_check(m._confirm.visible and not m._quit.visible, "Quit asks first")
		var line := m._confirm.get_node("Line") as Label
		_check(line.text == TranslationServer.translate("UI_PAUSE_QUIT_TEMP"), "the line says the day is not saved")
		_shot("pause_quit")
		_key(KEY_ESCAPE)
		await _frames(2)
		_check(PauseMenu.is_open() and not m._confirm.visible and m._quit.visible, "Esc takes the confirm back")
		_key(KEY_ESCAPE)
		await _frames(2)
	PauseMenu.web_override = 1
	_key(KEY_ESCAPE)
	await _frames(2)
	m = PauseMenu.current()
	_check(m != null and not m._quit.visible, "web: Quit game is hidden")
	PauseMenu.web_override = 0
	if m != null:
		await _click(m._title_btn)
	await _until(func() -> bool: return _scene_id() == "title" and not _busy(), 6000)
	_check(_scene_id() == "title", "market day: Back to title")
	_check(_bytes(SAVE) == disk, "market day: the save file is untouched")


# ---------------------------------------------------------------- 3. the festival

func _festival() -> void:
	var disk: Variant = _bytes(SAVE)
	if not _check(Festival.start(), "the festival starts"):
		return
	await _until(func() -> bool: return _scene_id() == "garden" and _festival_card() != null, 8000)
	await _seconds(0.5)
	_check(_festival_card() != null, "festival: the start card shows")
	_key(KEY_ESCAPE)
	await _frames(3)
	_check(_festival_card() == null and not PauseMenu.is_open(), "festival: Esc closes the start card first")
	_key(KEY_ESCAPE)
	await _frames(3)
	var m := PauseMenu.current()
	_check(m != null, "festival: the next Esc opens the menu")
	if m == null:
		return
	_check(m._title_btn.text == TranslationServer.translate("UI_PAUSE_TO_TITLE"), "festival: Back to title (never saved)")
	_check((m._confirm.get_node("Line") as Label).text == TranslationServer.translate("UI_PAUSE_QUIT_FESTIVAL"), "festival: the quit line says the festival ends")
	_shot("pause_festival")
	await _click(m._title_btn)
	await _until(func() -> bool: return _scene_id() == "title" and not _busy(), 6000)
	await _frames(4)
	_check(_scene_id() == "title" and get_first_node_in_group("festival") == null, "festival: Back to title ends it")
	_check(_bytes(SAVE) == disk, "festival: the save file is untouched")


# ---------------------------------------------------------------- helpers

## The gear opens the menu, Esc closes it (the scene stays).
func _gear_and_esc(where: String) -> void:
	var gear := _hud_gear()
	_check(gear != null and gear.is_visible_in_tree(), "%s: a gear on the HUD bar" % where)
	if gear != null:
		await _click(gear)
	_check(PauseMenu.is_open() and paused, "%s: the gear opens the menu" % where)
	_key(KEY_ESCAPE)
	await _frames(2)
	_check(not PauseMenu.is_open() and not paused and _scene_id() == where, "%s: Esc resumes" % where)


func _hud_gear() -> Control:
	var hud := get_first_node_in_group("hud")
	return hud.find_child("MenuButton", true, false) as Control if hud != null else null


func _go(id: String, params := {}) -> bool:
	load(TRANSITION).go(id, params)
	var ok := await _until(func() -> bool: return _scene_id() == id and current_scene != null and current_scene.is_node_ready() and not _busy(), 8000)
	await _frames(8)
	return _check(ok, "%s opens" % id)


func _busy() -> bool:
	return bool(load(TRANSITION).is_busy())


func _scene_id() -> String:
	return String(root.get_node("Router").current)


func _growing() -> bool:
	if current_scene == null:
		return false
	for c in current_scene.get_children():
		var sc: Variant = c.get_script()
		if sc is Script and String((sc as Script).resource_path).ends_with("world_grow.gd"):
			return true
	return false


func _festival_card() -> Node:
	var f := get_first_node_in_group("festival")
	var c: Variant = f.get("_card") if f != null else null
	return c if c is Node and is_instance_valid(c) else null


func _jams(d: Dictionary = {}) -> int:
	if d.is_empty():
		d = _gs.data
	var n := 0
	for it: Dictionary in d.get("inbox", []):
		if String(it.get("kind", "")) == "product" and String(it.get("key", "")).begins_with("jam|"):
			n += 1
	return n


func _has_text(n: Node, text: String) -> bool:
	if n is Button and (n as Button).text == text:
		return true
	for c in n.get_children():
		if _has_text(c, text):
			return true
	return false


func _click(c: Control) -> void:
	var p := c.get_global_rect().get_center().floor()
	for pressed in [true, false]:
		var mv := InputEventMouseMotion.new()
		mv.position = p
		mv.global_position = p
		root.push_input(mv, true)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.button_mask = 1 if pressed else 0
		ev.position = p
		ev.global_position = p
		root.push_input(ev, true)
		await process_frame
	await _frames(2)


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		root.push_input(ev, true)


func _until(cond: Callable, ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()) and Time.get_ticks_msec() - t0 < ms:
		await process_frame
	return bool(cond.call())


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> bool:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fail += 1
	return ok


func _shot(shot_name: String) -> void:
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("%s/%s%s.png" % [dir, shot_name, _suffix])
	print("saved ", ProjectSettings.globalize_path("%s/%s%s.png" % [dir, shot_name, _suffix]))


## A part of the screen at x4 (nearest), to look at the gear's pixels.
func _shot_zoom(shot_name: String, r: Rect2i) -> void:
	RenderingServer.force_draw(false)
	var img := root.get_texture().get_image().get_region(r)
	img.resize(r.size.x * 4, r.size.y * 4, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/%s%s.png" % [shot_name, _suffix])


## The smoke's game as a real one (menus offer Save and back to title) or as a temporary one (nothing is written).
func _real(on: bool) -> void:
	var flags: Dictionary = _gs.data.flags
	if on:
		flags.erase("temp")
	else:
		flags["temp"] = true


func _bytes(path: String) -> Variant:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null


func _write(path: String, bytes: Variant) -> void:
	if bytes == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


## The player's save as it was just before the smoke's Save and back to title.
func _put_save_back() -> void:
	if _save_out:
		_write(SAVE, _backup[SAVE])
		_save_out = false
		_check(_bytes(SAVE) == _backup[SAVE], "the player's save is back as it was")


func _finish() -> void:
	PauseMenu.web_override = -1
	paused = false
	_put_save_back()
	if _bytes(SETTINGS) != _backup[SETTINGS]:
		_write(SETTINGS, _backup[SETTINGS])
	_check(_bytes(SETTINGS) == _backup[SETTINGS], "the player's settings are back as they were")
	print("PAUSE SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)
