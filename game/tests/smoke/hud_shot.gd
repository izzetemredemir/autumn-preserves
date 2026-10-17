extends SceneTree
## Smoke shot (HUD-BAR): the garden with the full-width HUD bar, the collapsed To-Do note, the note expanded, the
## sound icon on and off -> tools/style/review/hud_bar/*.png ("_tr" suffix with `-- --locale=tr`).
##   godot --path game --audio-driver Dummy -s res://tests/smoke/hud_shot.gd [-- --locale=tr]
## Checks: bar spans x 4..476, the note sits right under it with its right edge at 476 and stays on screen, the
## speaker button flips the Master mute and its icon follows an M key press. Exit 1 on a failed check.

var _suffix := ""
var _fail := false


func _initialize() -> void:
	if "--locale=tr" in OS.get_cmdline_user_args():
		GameSettings.apply_language("tr")
		_suffix = "_tr"
	else:
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
	for i in 20:
		await process_frame
	var todo := get_first_node_in_group("granny_todo")
	var hud := get_first_node_in_group("hud")
	var audio := root.get_node("Audio")

	var bar: Rect2 = hud.bar_rect()
	_check(int(bar.position.x) == 4 and int(bar.end.x) == 476, "the bar spans x 4..476 (%s)" % bar)
	var note: Rect2 = todo._panel.get_global_rect()
	_check(int(note.end.x) == 476, "the note's right edge is x 476 (%s)" % note)
	_check(int(note.position.y) == int(bar.end.y) + 2, "the note sits right under the bar")
	_check(note.position.x >= 276, "the folded note stays in its zone")
	audio.set_muted(false)
	await process_frame
	var btn: TextureButton = hud.find_child("SoundButton", true, false)
	_check(btn != null, "the sound button exists")
	var on_tex: Texture2D = btn.texture_normal
	_shot("hud_bar_collapsed")
	_shot("hud_sound_on")

	todo.pin_open()
	for i in 4:
		await process_frame
	var open_rect: Rect2 = todo._panel.get_global_rect()
	_check(Rect2(0, 0, 480, 270).encloses(open_rect), "the expanded note stays on screen (%s)" % open_rect)
	_check(open_rect.end.y <= 215, "the expanded note ends by y 215 (%s)" % open_rect.end.y)
	_shot("hud_note_expanded")
	todo._collapsed = true
	todo._auto_pinned = false
	todo._apply_fold()
	await process_frame

	btn.pressed.emit()
	await process_frame
	_check(audio.is_muted(), "the speaker button mutes Master")
	_check(btn.texture_normal != on_tex, "the icon shows the muted state")
	_shot("hud_sound_off")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_M
	key.pressed = true
	audio._unhandled_input(key)
	await process_frame
	_check(not audio.is_muted() and btn.texture_normal == on_tex, "M unmutes and the icon follows")
	gs.data.day = 9
	gs.notify(PackedStringArray(["*"]))
	for i in 4:
		await process_frame
	_shot("hud_bar_week")
	audio.set_muted(true)  # dev runs start muted
	quit(1 if _fail else 0)


func _shot(shot_name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../tools/style/review/hud_bar").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s%s.png" % [dir, shot_name, _suffix]
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fail = true
