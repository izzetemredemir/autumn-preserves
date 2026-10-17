extends SceneTree
## Smoke drive (ENDING): the visit on day 30 end to end, with the demo save moved to day 29.
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/finale_shots.gd [-- --locale=tr]
## Bed on day 29 -> night card -> the finale under it, the first viewing ignores a held key, a shot of each beat,
## the end runs the visit day's night (day 31, saved, seen) and goes to the title (Visited card, Continue stays),
## Continue on day 31 does not replay it, the Visited card replays it and holding a key skips it. Saves the beats to
## tools/style/review/finale/<beat>_<locale>.png. The player's own save files are put back afterwards. Exit 1 on a failure.

const NIGHT := "res://ui/transition/night.gd"
const DEV_TOOLS := "res://ui/dev_panel/dev_tools.gd"
const TRANSITION := "res://ui/transition/transition.gd"
const LIMIT_MS := 30000
## Beat -> seconds into it for its shot.
const BEATS := {"kitchen": 3.6, "garden": 7.6, "snow": 8.0, "pantry": 5.0, "note": -1.0, "credits": 6.0, "last": 3.0}

var _gs: Node
var _save: Node
var _router: Node
var _fails: Array[String] = []
var _backup := {}
var _locale := "en"
var _dir := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--locale="):
			_locale = a.substr(9)
	GameSettings.apply_language(_locale)
	_dir = ProjectSettings.globalize_path("res://").path_join("../tools/style/review/finale").simplify_path()
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
	print("FINALE SMOKE OK" if _fails.is_empty() else "FINALE SMOKE FAILED: %s" % ", ".join(_fails))
	quit(1 if not _fails.is_empty() else 0)


func _drive() -> void:
	# --- day 29 in the kitchen: a real (saved) game from the demo save
	var d: Dictionary = load(DEV_TOOLS).load_demo()
	d.day = 29
	d.stats["jars_made"] = 14
	for id in d.varieties:
		if String(d.varieties[id].get("rarity", "")) != "common" and not id in d.found_varieties:
			d.found_varieties.append(id)
			break
	_gs.data = d
	_save.save_game(d)
	_router.goto("kitchen")
	await _frames(8)
	var night: Node = load(NIGHT).start()
	_check(night != null, "the night starts on day 29")
	await _until(func() -> bool: return night.get("_accepting") == true)
	await _frames(2)
	var fin := current_scene
	_check(_router.current == "finale" and fin != null and fin.name == "Finale", "the finale loads under the morning card")
	_check(int(_gs.data.day) == 30, "the morning of day 30")
	_check(fin.get("_waiting_night") == true, "the finale waits for the morning card")
	night._confirm()
	await _until(func() -> bool: return fin.get("_waiting_night") == false)
	_check(fin.playing and not fin.skippable, "the first viewing plays and cannot be skipped")

	# --- the first viewing ignores a held key
	Input.action_press("interact")
	await create_timer(1.8).timeout
	Input.action_release("interact")
	_check(fin.playing and fin.section == "kitchen", "holding E does not skip the first viewing")

	# --- a shot of each beat (seek into the timeline)
	var tl: Array = fin.get("_timeline")
	_check(tl.size() == 7, "seven parts")
	_check(fin.total_time() > 60.0 and fin.total_time() < 100.0, "about 75 s (%d s)" % int(fin.total_time()))
	for id in BEATS:
		var into := float(BEATS[id])
		if id == "note":
			into = fin.shot("note").typed_by() + 1.0
		await _seek(fin, String(id), into)
		_shot(String(id))
	_check(fin.shot("pantry").pantry.jar_count() > 0, "the pantry pan shows the player's jars")

	# --- the end: seen, the visit day's night, the title
	Engine.time_scale = 8.0
	await _until(func() -> bool: return _router.current == "title" and current_scene != null and current_scene.name == "Title")
	Engine.time_scale = 1.0
	await _until(func() -> bool: return not load(TRANSITION).is_busy())
	await _frames(4)
	var disk: Dictionary = _save.load_game()
	_check(bool(disk.get("flags", {}).get("story", {}).get("finale_seen", false)), "watched once: saved")
	_check(int(disk.get("day", 0)) == 31, "the save goes on from day 31 (%d)" % int(disk.get("day", 0)))
	_check(not bool(disk.get("flags", {}).get("completed", false)), "the save is not closed")
	var title := current_scene
	_check(title.get_node("%Continue").text != tr("UI_MEMORY_OPEN"), "Continue stays Continue")
	_check(title.get("_completed_card") != null, "the title shows the Visited card")

	# --- the Visited card replays it, skippable; the save does not change
	title._replay_visit()
	await _until(func() -> bool: return current_scene != null and current_scene.name == "Finale")
	await _until(func() -> bool: return not load(TRANSITION).is_busy())
	var rep := current_scene
	await _frames(10)
	_check(rep.playing and rep.skippable and rep.mode == "replay", "the replay can be skipped")
	Input.action_press("interact")
	var t0 := Time.get_ticks_msec()
	await _until(func() -> bool: return not rep.playing)
	Input.action_release("interact")
	_check(Time.get_ticks_msec() - t0 < 4000, "holding E skips the replay")
	await _until(func() -> bool: return current_scene != null and current_scene.name == "Title")
	await _until(func() -> bool: return not load(TRANSITION).is_busy())
	_check(int(_save.load_game().get("day", 0)) == 31, "the replay leaves the save on day 31")

	# --- Continue on day 31: the garden, no finale, the grandchildren are there
	current_scene._on_continue()
	await _until(func() -> bool: return current_scene != null and current_scene.name != "Title")
	await _until(func() -> bool: return not load(TRANSITION).is_busy())
	await _frames(6)
	_check(_router.current != "finale", "day 31 does not replay the visit (%s)" % _router.current)
	if _router.current == "garden":
		_check(current_scene.find_child("Grandkids", true, false) != null, "Mia and Leo play in the garden")


func _seek(fin: Node, id: String, into: float) -> void:
	for s in fin.get("_timeline"):
		if s.id == id:
			fin.seek(float(s.start) + into)
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
	DirAccess.make_dir_recursive_absolute(_dir)
	var path := "%s/%s_%s.png" % [_dir, shot_name, _locale]
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails.append(what)
