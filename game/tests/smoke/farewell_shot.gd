extends SceneTree
## Smoke drive (P2-FAREWELL): the hidden day-100 ending end to end, with the demo save on day 99.
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/farewell_shot.gd
## Bed on day 99 -> night card -> the farewell under it (save closed, day-99 backup written), the first viewing ignores
## a held key, shots of each part, the end goes to the title (Completed card, Memory button), Memory mode (day never
## moves on, pantry browsed by keys and drag), replays skipped by holding a key, the mouse and a finger.
## Saves user://shots/farewell_<part>.png. The player's own save files are put back afterwards. Exit 1 on a failure.

const NIGHT := "res://ui/transition/night.gd"
const DEV_TOOLS := "res://ui/dev_panel/dev_tools.gd"
const TRANSITION := "res://ui/transition/transition.gd"
const DIR := "user://shots"
const LIMIT_MS := 20000

var _gs: Node
var _save: Node
var _router: Node
var _fails: Array[String] = []
var _backup := {}


func _initialize() -> void:
	_gs = root.get_node("GameState")
	_save = root.get_node("Save")
	_router = root.get_node("Router")
	_run()


func _run() -> void:
	await process_frame
	for p in [_save.PATH, _save.DAY99_PATH]:
		_backup[p] = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else null
	await _drive()
	for p in _backup:
		if _backup[p] == null:
			_save.delete(p)
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_string(_backup[p])
			f.close()
	Engine.time_scale = 1.0
	print("FAREWELL SMOKE OK" if _fails.is_empty() else "FAREWELL SMOKE FAILED: %s" % ", ".join(_fails))
	quit(1 if not _fails.is_empty() else 0)


func _drive() -> void:
	# --- day 99 in the kitchen: a real (saved) game from the demo save
	var d: Dictionary = load(DEV_TOOLS).load_demo()
	d.day = 99
	d.friendship["baker"] = 25
	for id in d.varieties:
		if String(d.varieties[id].get("rarity", "")) != "common" and not id in d.found_varieties:
			d.found_varieties.append(id)
			break
	_gs.data = d
	for day in [50, 95]:  # days 90-99: Granny walks and steps slower (looks only)
		d.day = day
		var g: Node = (load("res://player/granny.tscn") as PackedScene).instantiate()
		root.add_child(g)
		_check(is_equal_approx(float(g.speed), 72.0 * load("res://sim/farewell.gd").walk_scale(day)), "walk speed on day %d" % day)
		g.free()
	d.day = 99
	_save.save_game(d)
	_save.delete(_save.DAY99_PATH)
	_router.goto("kitchen")
	await _frames(8)
	var night: Node = load(NIGHT).start()
	_check(night != null, "the night starts on day 99")
	await _until(func() -> bool: return night.get("_accepting") == true)
	var fw := current_scene
	_check(_router.current == "farewell" and fw != null and fw.name == "Farewell", "the farewell loads under the night")
	_check(int(_gs.data.day) == 100 and bool(_gs.data.flags.get("completed", false)), "day 100, the save is closed")
	var disk: Dictionary = _save.load_game()
	_check(bool(disk.get("flags", {}).get("completed", false)), "the closed save is on disk")
	var day99: Dictionary = _save.load_game(_save.DAY99_PATH)
	_check(int(day99.get("day", 0)) == 99 and not bool(day99.flags.get("completed", false)), "save_day99.json holds day 99")
	_check(fw.get("_waiting_night") == true, "the farewell waits for the morning card")
	night._confirm()
	await _until(func() -> bool: return fw.get("_waiting_night") == false)
	_check(fw.playing and not fw.skippable, "the first viewing plays and cannot be skipped")

	# --- the first viewing ignores a held key
	Input.action_press("interact")
	await create_timer(1.8).timeout
	Input.action_release("interact")
	_check(fw.playing and fw.section == "kitchen", "holding E does not skip the first viewing")
	_shot("farewell_kitchen")

	# --- shots of each part (seek into the timeline)
	var tl: Array = fw.get("_timeline")
	_check(fw.total_time() > 75.0 and fw.total_time() < 110.0, "about 90 s (%d s)" % int(fw.total_time()))
	var letter: Node = fw.shot("letter")
	await _seek(fw, "letter", letter.typed_by() + 1.0)
	_shot("farewell_letter")
	await _seek(fw, "pantry", 6.0)
	_check(fw.shot("pantry").jar_count() > 0, "the pantry pan shows the player's jars")
	_shot("farewell_pantry")
	await _seek(fw, "snow", 13.0)
	_shot("farewell_snow")
	await _seek(fw, "credits", 9.0)
	_shot("farewell_credits")
	await _seek(fw, "last", 5.0)
	_shot("farewell_last")
	_check(tl.size() == 6, "six parts")

	# --- the end goes to the title, the save says it was watched
	Engine.time_scale = 8.0
	await _until(func() -> bool: return _router.current == "title" and current_scene != null and current_scene.name == "Title")
	Engine.time_scale = 1.0
	await _until(func() -> bool: return not load(TRANSITION).is_busy())
	await _frames(4)
	_check(bool(_save.load_game().get("flags", {}).get("farewell_seen", false)), "watched once: saved")
	var title := current_scene
	_check(title.get_node("%Continue").text == tr("UI_MEMORY_OPEN"), "Continue became Memory")
	_check(title.get("_completed_card") != null, "the title shows the Completed card")
	_shot("farewell_title")

	# --- Memory mode
	title._on_continue()
	await _until(func() -> bool: return current_scene != null and current_scene.name == "Farewell")
	await _until(func() -> bool: return not load(TRANSITION).is_busy())
	await _frames(4)
	var mem := current_scene
	_check(mem.mode == "memory" and _gs.is_memory(), "Memory mode opens")
	_check(_gs.end_day() == [] and int(_gs.data.day) == 100, "Memory mode never advances the day")
	_shot("farewell_memory")
	mem._open_browse()
	await _frames(4)
	_key("move_right")
	_key("move_right")
	await create_timer(0.6).timeout
	_check(mem.get("_shelf").current() == 2, "arrow keys walk the shelf")
	var drag := InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_LEFT
	drag.pressed = true
	mem._on_browse_input(drag)
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(-72, 0)
	mem._on_browse_input(move)
	drag = drag.duplicate()
	drag.pressed = false
	mem._on_browse_input(drag)
	await create_timer(0.5).timeout
	_check(mem.get("_shelf").current() == 3, "dragging moves along the shelf")
	_shot("farewell_memory_pantry")
	_key("cancel")
	await _frames(4)
	_check(mem.get("_menu").visible, "Esc goes back to the Memory menu")

	# --- replays: hold to skip with the mouse, a finger and a key
	for how in ["mouse", "touch", "key"]:
		mem.start_play(true)
		await _frames(10)
		_check(mem.playing and mem.skippable, "replay (%s) can be skipped" % how)
		_hold(how, true)
		var t0 := Time.get_ticks_msec()
		await _until(func() -> bool: return not mem.playing)
		_hold(how, false)
		var held := Time.get_ticks_msec() - t0
		_check(mem.mode == "memory" and held < 4000, "holding (%s) skips back to Memory (%d ms)" % [how, held])
		await _frames(4)
	_check(int(_gs.data.day) == 100 and bool(_save.load_game().flags.get("completed", false)), "the save stays closed")


func _hold(how: String, down: bool) -> void:
	match how:
		"mouse":
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.position = Vector2(240, 135)
			e.pressed = down
			Input.parse_input_event(e)
		"touch":
			var e := InputEventScreenTouch.new()
			e.position = Vector2(240, 135)
			e.pressed = down
			Input.parse_input_event(e)
		"key":
			if down:
				Input.action_press("interact")
			else:
				Input.action_release("interact")


func _key(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _seek(fw: Node, id: String, into: float) -> void:
	for s in fw.get("_timeline"):
		if s.id == id:
			fw.seek(float(s.start) + into)
	await _frames(3)


func _until(cond: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()):
		if Time.get_ticks_msec() - t0 > LIMIT_MS:
			_check(false, "timed out waiting")
			return
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := "%s/%s.png" % [DIR, shot_name]
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails.append(what)
