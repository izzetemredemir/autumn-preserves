extends SceneTree
## Smoke shot (JURY-STOVE): the cook panel as a newcomer first meets it, nothing picked by hand.
##   1. Day 1 of a new game (temporary, never saved): the garden apple tree shaken, the stove opened.
##   2. The Harvest Festival save (temporary): the rare tree shaken, the stove opened.
## Each time the panel must already hold a cookable recipe and a variant that is not in the book yet, so the first
## press of Cook just works. Festival only: the slot's Change picker (rare fruit first, Esc closes just the picker),
## left / right switch recipes, then Enter starts the jam and the run ends.
## Shots: user://shots/cook_panel_day1.png, cook_panel_festival.png, cook_panel_picker.png (+ "_tr" with
## -- --locale=tr).
##   godot --path game --audio-driver Dummy -s res://tests/smoke/cook_panel_shot.gd [-- --locale=tr]
## The player's save is not touched: both games carry flags.temp.

const KITCHEN := "res://scenes/kitchen/kitchen.tscn"

var _gs: Node
var _fail := 0
var _suffix := ""


func _initialize() -> void:
	_gs = root.get_node("GameState")
	if "--locale=tr" in OS.get_cmdline_user_args():
		GameSettings.apply_language("tr")
		_suffix = "_tr"
	_run()


func _run() -> void:
	await process_frame
	root.get_node("Router").current = "kitchen"
	# --- 1. day 1: shake the garden tree (Granny's first step), then the stove
	_gs.start_temp(452)
	var d: Dictionary = _gs.data
	_check(bool(Garden.shake_tree(d, 0).get("ok", false)), "day 1: the garden tree gives apples")
	await _stove("cook_panel_day1", "jam")

	# --- 2. the festival: the rare tree shaken, then the stove
	d = FestivalFacts.load_save()
	if not _check(not d.is_empty(), "festival save loads"):
		_finish()
		return
	_gs.data = d
	var f: Dictionary = TodoRules.festival(d)
	var map := WildGen.generate(int(d.save_seed), int(d.day), "forest", String(d.weather), d.varieties, true)
	_check(bool(Forage.shake_tree(d, map, int(f.tree)).get("ok", false)), "festival: the rare tree shaken")
	var k: Node = await _stove("cook_panel_festival", "jam")
	var panel: Node = k._panel if k != null else null
	if panel != null:
		_check(String(panel.picks.main) == String(f.rare), "festival: the rare fruit is picked (%s)" % panel.picks.main)
		_check(root.gui_get_focus_owner() == panel._cook, "festival: focus waits on Cook")
		# the Change picker: a click on the slot, the rare fruit first (new and rare), Esc closes only the picker
		await _click(panel._slots.main.button.get_global_rect().get_center())
		_check(panel._picker.visible and panel._rows.size() > 1, "festival: the slot opens the picker (%d rows)" % panel._rows.size())
		_check(panel._rows.keys()[0] == String(f.rare), "festival: the rare fruit tops the picker")
		await _frames(6)
		_shot("cook_panel_picker")
		_action("cancel")
		await _frames(3)
		_check(not panel._picker.visible and panel.visible, "festival: Esc closes the picker, the panel stays")
		_action("ui_right")
		await _frames(3)
		_check(String(panel.recipe) == "fruit_butter", "festival: right arrow switches to the next recipe (%s)" % panel.recipe)
		_action("ui_left")
		await _frames(3)
		_check(String(panel.recipe) == "jam" and String(panel.picks.main) == String(f.rare), "festival: left arrow is back on the rare jam")
		panel._cook.grab_focus()
		k.debug_ctx = {"autoplay": true, "duration": 2.0}
		_action("interact")
		await _frames(4)
		_check(k._mg != null, "festival: Enter on the opened stove starts the jam")
	_finish()


func _action(action_name: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action_name
	ev.pressed = true
	Input.parse_input_event(ev)


## Hover, press and release the left button at one point (viewport coordinates).
func _click(at: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = at
	root.push_input(mv, true)
	await process_frame
	for down: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(ev, true)
		await process_frame
	await _frames(3)


## Opens the stove in a fresh kitchen and checks what the panel picked on its own; returns the kitchen.
func _stove(shot: String, want_recipe: String) -> Node:
	var k := (load(KITCHEN) as PackedScene).instantiate()
	for c in root.get_children():
		if c.scene_file_path == KITCHEN:
			c.queue_free()
	root.add_child(k)
	current_scene = k
	await _frames(12)
	k._on_spot("stove")
	await _frames(16)
	var panel: Node = k._panel
	var d: Dictionary = _gs.data
	_check(panel.visible, "%s: the stove opens the panel" % shot)
	_check(String(panel.recipe) == want_recipe, "%s: opens on %s (%s)" % [shot, want_recipe, panel.recipe])
	_check(bool(panel._ok), "%s: ready to cook without a single pick" % shot)
	var key := Kitchen.product_key(String(panel.recipe), String(panel.picks.main), String(panel.picks.second), String(panel.addin))
	_check(not d.book.variants.has(key), "%s: a variant not in the book yet (%s)" % [shot, key])
	_shot(shot)
	return k


func _check(ok: bool, what: String) -> bool:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fail += 1
	return ok


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("%s/%s%s.png" % [dir, shot_name, _suffix])
	print("saved ", ProjectSettings.globalize_path("%s/%s%s.png" % [dir, shot_name, _suffix]))


func _finish() -> void:
	print("COOK PANEL SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)
