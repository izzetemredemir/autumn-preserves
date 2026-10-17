extends SceneTree
## Smoke shot (SETTINGS-STEPS): the settings panel's +/- volume bars from the title and from the pause menu, EN + TR.
## Also presses "+" / "-" and Right on the bar and checks the stored value. settings.cfg is put back afterwards.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/settings_shot.gd -- --out=/abs/dir
const CFG := "user://settings.cfg"
var _fail := 0
var _out := "user://shots"
var _backup := PackedByteArray()


func _initialize() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	if FileAccess.file_exists(CFG):
		_backup = FileAccess.get_file_as_bytes(CFG)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(2)
	var lang := GameSettings.language()
	GameSettings.set_value("audio", "music", 0.43)  # an old file's off-step value rounds to 0.4
	GameSettings.set_value("audio", "sfx", 0.8)
	GameSettings.set_value("audio", "ambient", 0.2)
	for loc in ["en", "tr"]:
		GameSettings.set_language(loc)
		var title: Node = load("res://scenes/title/title.tscn").instantiate()
		root.add_child(title)
		await _frames(4)
		title._on_settings()
		await _frames(4)
		var panel := _find(title)
		_check_buttons(panel, loc)
		await _shot("settings_title_" + loc)
		if loc == "en":
			_exercise(panel)
		panel.visible = false
		var m := PauseMenu.ensure()
		await _frames(2)
		PauseMenu.web_override = 0
		m._show()  # over the title as the backdrop
		await _frames(3)
		m._open_settings(false)
		await _frames(4)
		await _shot("settings_pause_" + loc)
		m._close()
		paused = false
		PauseMenu.web_override = -1
		title.queue_free()
		await _frames(2)
	GameSettings.apply_language(lang)
	if _backup.size() > 0:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	else:
		DirAccess.remove_absolute(CFG)
	print("settings_shot: ", "OK" if _fail == 0 else "FAILED")
	quit(_fail)


func _find(n: Node) -> Node:
	if n.get_script() != null and String(n.get_script().resource_path).ends_with("settings_panel.gd"):
		return n
	for c in n.get_children():
		var r := _find(c)
		if r != null:
			return r
	return null


func _bars(n: Node, out: Array) -> void:
	if n.name.begins_with("Bar_"):
		out.append(n)
	for c in n.get_children():
		_bars(c, out)


func _check_buttons(panel: Node, loc: String) -> void:
	var bars := []
	_bars(panel, bars)
	if bars.size() != 3 or bars[0].steps != (4 if loc == "en" else 6):
		_fail += 1
		printerr("expected 3 bars, music at 4 steps; got ", bars.size())
	for b: Control in bars:
		for c: Control in b.get_parent().get_children():
			if c.size.x < 16 or c.size.y < 16:
				_fail += 1
				printerr("touch target under 16 px: ", c.name, c.size)


func _exercise(panel: Node) -> void:
	var bars := []
	_bars(panel, bars)
	var bar: Control = bars[0]
	var plus: Button = bar.get_parent().get_child(2)
	var minus: Button = bar.get_parent().get_child(0)
	plus.pressed.emit()
	plus.pressed.emit()
	var ev := InputEventAction.new()
	ev.action = "ui_right"
	ev.pressed = true
	bar._gui_input(ev)
	minus.pressed.emit()
	var v := float(GameSettings.get_value("audio", "music"))
	if not is_equal_approx(v, 0.6):
		_fail += 1
		printerr("music expected 0.6, got ", v)


func _shot(shot_name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.save_png(_out.path_join(shot_name + ".png"))
	print("saved ", shot_name)
