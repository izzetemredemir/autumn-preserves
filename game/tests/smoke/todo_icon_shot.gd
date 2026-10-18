extends SceneTree
## Smoke shot (TODO-ICON): Granny's To-Do note folds to an envelope icon. Day-1 tutorial: peek at scene entry, folds
## by itself after 3 s into the icon (<= 44x16, right edge x 476), a click opens it, Esc / outside click fold it.
## Festival save: the same, icon "0/7". -> tools/style/review/todo_icon/{icon,peek,open,festival_icon}_en.png
##   godot --path game --audio-driver Dummy -s res://tests/smoke/todo_icon_shot.gd   (about 15 s; exit 1 on a failed check)
## The games are temporary (never written to user://save.json).

var _fail := false
var _todo: Node


func _initialize() -> void:
	GameSettings.apply_language("en")
	_run()


func _run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	var router := root.get_node("Router")
	router.params = {}
	router.current = "garden"
	gs.start_temp(1)
	gs.data.weather = "rainy"
	gs.data.day = 1
	gs.notify(PackedStringArray(["*"]))
	load("res://ui/tutorial/granny_todo.gd").ensure()
	var scene := (load("res://scenes/garden/garden.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	if get_first_node_in_group("hud") == null:
		root.add_child((load("res://ui/hud/hud.tscn") as PackedScene).instantiate())
	await _frames(20)
	_todo = get_first_node_in_group("granny_todo")
	_check(_todo.fold_name() == "peek", "the step peeks at scene entry (%s)" % _todo.fold_name())
	_shot("peek")
	var t0 := Time.get_ticks_msec()
	while _todo.fold_name() == "peek" and Time.get_ticks_msec() - t0 < 6000:
		await process_frame
	var peek_ms := Time.get_ticks_msec() - t0
	_check(_todo.fold_name() == "icon" and peek_ms >= 2000 and peek_ms <= 3600, "peek folds to the icon by itself (%d ms left)" % peek_ms)
	await _frames(4)
	var r: Rect2 = _todo._panel.get_global_rect()
	_check(r.size.x <= 44 and r.size.y <= 16, "icon fold is <= 44x16 (%s)" % r.size)
	_check(int(r.end.x) == 476, "icon right edge is x 476 (%s)" % r.end.x)
	var bar: Rect2 = get_first_node_in_group("hud").bar_rect()
	_check(int(r.position.y) >= int(bar.end.y), "icon sits under the HUD bar")
	_shot("icon")
	_todo._on_icon_pressed()
	await _frames(4)
	_check(_todo.is_open(), "a click on the icon opens the note")
	_shot("open")
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	_todo._input(key)
	await _frames(2)
	_check(_todo.fold_name() == "icon", "Esc folds to the icon")
	_todo._on_icon_pressed()
	await _frames(4)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(20, 200)
	_todo._input(click)
	await _frames(2)
	_check(_todo.fold_name() == "icon", "a click outside folds to the icon")
	# festival save
	var fd: Dictionary = FestivalFacts.load_save()
	if fd.is_empty():
		_check(false, "festival save loads")
		quit(1)
		return
	gs.data = fd
	gs.notify(PackedStringArray(["*"]))
	await _frames(4)
	t0 = Time.get_ticks_msec()
	while _todo.fold_name() == "peek" and Time.get_ticks_msec() - t0 < 6000:
		await process_frame
	await _frames(4)
	_check(_todo.fold_name() == "icon" and _todo.visible, "festival: icon fold")
	r = _todo._panel.get_global_rect()
	_check(r.size.x <= 44 and r.size.y <= 16 and int(r.end.x) == 476, "festival icon <= 44x16 at x 476 (%s)" % r)
	_shot("festival_icon")
	quit(1 if _fail else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../tools/style/review/todo_icon").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s_en.png" % [dir, shot_name]
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fail = true
