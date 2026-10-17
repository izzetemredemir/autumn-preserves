extends SceneTree
## GD-META smoke shots -> user://shots/title.png (default view) or user://shots/title_<view>.png
##   godot --path game -s res://tests/smoke/title_shot.gd [-- --view lang|newgame|settings|premise|todo|night|dev]
## `--view flow` (works --headless) plays New Game -> premise -> home scene -> night -> Continue and prints
## FLOW OK / FLOW FAIL; the player's own save file is restored afterwards.

const TITLE := "res://scenes/title/title.tscn"
const TITLE_SCRIPT := "res://scenes/title/title.gd"
# Scripts are loaded by path: their class names use autoloads, which --check-only of this file cannot see.
const TODO := "res://ui/tutorial/granny_todo.gd"
const NIGHT := "res://ui/transition/night.gd"
const DEV := "res://ui/dev_panel/dev_panel.gd"
const TRANSITION := "res://ui/transition/transition.gd"

var _view := "title"
var _fails: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--view" and i + 1 < args.size():
			_view = args[i + 1]
	_run()


func _run() -> void:
	await process_frame
	match _view:
		"flow":
			await _flow()
			quit(1 if not _fails.is_empty() else 0)
			return
		"title", "newgame", "settings", "lang":
			if _view != "lang":
				load(TITLE_SCRIPT).skip_lang = true
			var title := _title()
			await _frames(4)
			if _view == "lang":
				title._build_lang_picker()
			elif _view == "newgame":
				title._on_new_game()
			elif _view == "settings":
				title._on_settings()
		"premise":
			root.add_child((load("res://ui/premise/premise.tscn") as PackedScene).instantiate())
			await create_timer(4.0).timeout
		"todo":
			var gs := _game()
			_hud()
			gs.data.flags.tutorial = 3
			root.get_node("Router").current = "kitchen"
			load(TODO).ensure()
			await _frames(3)
			gs.notify(PackedStringArray(["*"]))
		"night":
			_game()
			_hud()
			load(NIGHT).start()
			await create_timer(3.2).timeout
		"dev":
			_game()
			_hud()
			load(DEV).ensure()
			await _frames(3)
			var dev := get_first_node_in_group("dev_panel")
			dev._panel.visible = true
			dev._refresh()
	await _frames(14)
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var file := dir + ("/title.png" if _view == "title" else "/title_%s.png" % _view)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(file)
	print("saved ", ProjectSettings.globalize_path(file))
	quit()


func _title() -> Node:
	var title := (load(TITLE) as PackedScene).instantiate()
	root.add_child(title)
	current_scene = title
	return title


func _game() -> Node:
	var gs := root.get_node("GameState")
	gs.start_new(1)
	var bg := ColorRect.new()
	bg.color = Color("747c37")
	bg.size = Vector2(480, 270)
	root.add_child(bg)
	return gs


func _hud() -> void:
	if ResourceLoader.exists("res://ui/hud/hud.tscn"):
		root.add_child((load("res://ui/hud/hud.tscn") as PackedScene).instantiate())


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)


func _flow() -> void:
	var save := root.get_node("Save")
	var gs := root.get_node("GameState")
	var router := root.get_node("Router")
	var backup: String = FileAccess.get_file_as_string(save.PATH) if save.has_save() else ""
	load(TITLE_SCRIPT).skip_lang = true
	var title := _title()
	await _frames(3)
	title._on_new_game()
	title._seed_edit.text = "1234"
	title._start()
	_check(int(gs.data.save_seed) == 1234, "New Game uses the typed seed")
	var premise: Node = null
	for c in title.get_children():
		if c.has_method("_skip_or_leave"):
			premise = c
	_check(premise != null, "premise shows after New Game")
	if premise != null:
		var seen: Variant = GameSettings.get_value("game", "intro_seen")
		premise.skip()  # FIRST-60: the intro has five beats; skip() leaves at once
		GameSettings.set_value("game", "intro_seen", seen)  # the player's first intro stays unwatched
	await process_frame
	var howto := get_first_node_in_group("howto")  # ONBOARD-HOWTO: How to Play after the intro; Got it! goes on
	_check(howto != null, "How to Play opens after the intro")
	if howto != null:
		howto.close(true)
	await create_timer(1.2).timeout
	var home: String = load(TRANSITION).home_scene()
	_check(router.current == home, "premise leads to %s (now '%s')" % [home, router.current])
	_check(save.has_save() and int(save.load_game().get("day", 0)) == 1, "new game is saved")
	_check(get_first_node_in_group("granny_todo") != null, "Granny's To-Do is added")
	var night: Node = load(NIGHT).start()
	_check(night != null, "night starts")
	await create_timer(2.6).timeout
	_check(int(gs.data.day) == 2, "night advances the day")
	_check(int(save.load_game().get("day", 0)) == 2, "night autosaves")
	if night != null:
		night._confirm()
		await create_timer(1.0).timeout
	_check(not load(NIGHT).is_running(), "morning card closes")
	gs.data = {}
	current_scene.queue_free()
	await process_frame
	title = _title()
	await _frames(3)
	_check(not title.get_node("%Continue").disabled, "Continue is enabled with a save")
	title._on_continue()
	_check(int(gs.data.get("day", 0)) == 2, "Continue loads the saved day")
	await create_timer(1.2).timeout
	_check(router.current == home, "Continue goes to %s" % home)
	if backup != "":
		var f := FileAccess.open(save.PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		save.delete()
	print("FLOW OK" if _fails.is_empty() else "FLOW FAIL: %s" % ", ".join(_fails))
