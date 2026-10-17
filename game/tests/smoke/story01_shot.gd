extends SceneTree
## STORY-01 smoke shots -> user://shots/story01_letter<suffix>.png (Nora's letter open over the garden),
## story01_premise3<suffix>.png (premise beat 3). Prints STORY01 OK / STORY01 FAIL.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/story01_shot.gd [-- --locale=tr]

var _suffix := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--locale="):
			_suffix = "_" + a.substr(9)
	GameSettings.apply_language("tr" if _suffix == "_tr" else "en")
	_run()


func _run() -> void:
	var fails: Array[String] = []
	var gs := root.get_node("GameState")
	gs.start_temp(42)
	var d: Dictionary = gs.data
	if Letters.unread_count(d) != 1:
		fails.append("day 1 mailbox should hold one unread letter")
	var beats: GDScript = load("res://ui/premise/intro_beats.gd")
	var premise: Node = (load("res://ui/premise/premise.tscn") as PackedScene).instantiate()
	root.add_child(premise)
	premise.set_process(false)
	await _frames(3)
	premise.seek(beats.start(1) + float(beats.BEATS[1][2]) * 0.8)
	await _frames(2)
	_shot("story01_premise3")
	premise.queue_free()
	await _frames(2)
	var scene := (load("res://scenes/garden/garden.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(6)
	var ui := LettersUI.open()
	await _frames(10)
	_shot("story01_letter")
	if ui._pack_btn.visible:
		fails.append("story letter must not show the Pack button")
	if not Letters.find_letter(d, Letters.STORY_ID).read:
		fails.append("opening the letter marks it read")
	print("STORY01 OK" if fails.is_empty() else "STORY01 FAIL: %s" % ", ".join(fails))
	quit(1 if not fails.is_empty() else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	var p := "user://shots/%s%s.png" % [nm, _suffix]
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(p)
	print("saved ", ProjectSettings.globalize_path(p))
