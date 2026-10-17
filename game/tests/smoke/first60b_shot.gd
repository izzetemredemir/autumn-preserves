extends SceneTree
## FIRST-60B smoke shots -> user://shots/first60b_*<suffix>.png: premise beats 1-3, the day-1 To-Do expanded over
## the garden, the result card mid-celebration. Prints FIRST60B OK / FIRST60B FAIL.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/first60b_shot.gd [-- --locale=tr]

var _suffix := ""
var _fails: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--locale="):
			_suffix = "_" + a.substr(9)
	GameSettings.apply_language("tr" if _suffix == "_tr" else "en")
	_run()


func _run() -> void:
	var gs := root.get_node("GameState")
	gs.start_temp(42)
	var beats: GDScript = load("res://ui/premise/intro_beats.gd")
	if beats.count() != 3:
		_fails.append("three premise beats")
	var premise: Node = (load("res://ui/premise/premise.tscn") as PackedScene).instantiate()
	root.add_child(premise)
	premise.set_process(false)
	await _frames(3)
	for i in beats.count():
		premise.seek(beats.start(i) + float(beats.BEATS[i][2]) * 0.8)
		await _frames(2)
		_shot("first60b_beat%d" % (i + 1))
	premise.queue_free()
	await _frames(2)
	var steps := TodoRules.steps_for(gs.data)
	if steps.find("d1_pick") < 0 or steps.find("d1_pick") > 2:
		_fails.append("forest within the first 3 steps")
	var scene := (load("res://scenes/garden/garden.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(8)
	var todo = load("res://ui/tutorial/granny_todo.gd").ensure()
	root.get_node("Router").set("current", "garden")
	await _frames(3)
	todo.pin_open()
	await _frames(10)
	_shot("first60b_todo")
	scene.queue_free()
	await _frames(2)
	var vars: Dictionary = VarietyGen.generate_all(1016, 0)
	var ids := vars.keys()
	ids.sort()
	var key := ""
	for id in ids:
		if String((vars[id] as Dictionary).get("type", "")) == "apple":
			key = "jam|%s|-" % id
			break
	var card: ResultCard = (load("res://ui/result_card/result_card.tscn") as PackedScene).instantiate()
	root.add_child(card)
	await process_frame
	card.show_result(ProductGen.describe(key, vars), 3, true)
	await create_timer(0.95).timeout
	_shot("first60b_card")
	print("FIRST60B OK" if _fails.is_empty() else "FIRST60B FAIL: %s" % ", ".join(_fails))
	quit(1 if not _fails.is_empty() else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	var p := "user://shots/%s%s.png" % [nm, _suffix]
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(p)
	print("saved ", ProjectSettings.globalize_path(p))
