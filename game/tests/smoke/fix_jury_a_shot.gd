extends SceneTree
## FIX-JURY-A smoke shots -> user://shots/fix_jury_a_<view><suffix>.png: title, premise hint, day-1 result card with
## the To-Do note hidden, press result strip. `-- --locale=tr` for Turkish.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/fix_jury_a_shot.gd [-- --locale=tr]

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
	var title := (load("res://scenes/title/title.tscn") as PackedScene).instantiate()
	root.add_child(title)
	await _frames(8)
	_shot("title")
	title.queue_free()
	await _frames(2)
	var beats: GDScript = load("res://ui/premise/intro_beats.gd")
	var premise: Node = (load("res://ui/premise/premise.tscn") as PackedScene).instantiate()
	root.add_child(premise)
	premise.set_process(false)
	await _frames(3)
	premise.seek(beats.start(2) + float(beats.BEATS[2][2]) * 0.8)
	await _frames(3)
	premise._hint.visible = true
	_shot("premise_hint")
	premise.queue_free()
	await _frames(2)
	# the note on the kitchen, then a card over it
	var kitchen := (load("res://scenes/kitchen/kitchen.tscn") as PackedScene).instantiate()
	root.add_child(kitchen)
	root.get_node("Router").set("current", "kitchen")
	await _frames(8)
	var todo = load("res://ui/tutorial/granny_todo.gd").ensure()
	await _frames(4)
	todo.pin_open()
	await _frames(6)
	var visible_before: bool = todo._root.visible
	_shot("todo")
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
	if not visible_before:
		_fails.append("note should show before the card")
	if todo._root.visible:
		_fails.append("note must hide under the card")
	_shot("card")
	card.queue_free()
	kitchen.queue_free()
	await _frames(4)
	var press := (load("res://minigames/press/press.tscn") as PackedScene).instantiate()
	root.add_child(press)
	await create_timer(0.5).timeout  # the scene starts itself (run with -- --autoplay)
	var t := 0.0
	while press.phase != press.Phase.DONE and t < 40.0:
		await create_timer(0.25).timeout
		t += 0.25
	await _frames(4)
	_shot("press_result")
	print("FIXJURYA OK" if _fails.is_empty() else "FIXJURYA FAIL: %s" % ", ".join(_fails))
	quit(1 if not _fails.is_empty() else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	var p := "user://shots/fix_jury_a_%s%s.png" % [nm, _suffix]
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(p)
	print("saved ", ProjectSettings.globalize_path(p))
