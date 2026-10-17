extends SceneTree
## Smoke shots (STORY-03): a letter with a story P.S., Vito's Teo line in the neighbour panel, Teo's letter in the
## recipe book, the farewell letter with the new line -> tools/style/review/story03/<name>_<lang>.png
## godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/story03_shot.gd [-- --locale=tr]

var _lang := "en"
var _dir := ""


func _initialize() -> void:
	_lang = "tr" if "--locale=tr" in OS.get_cmdline_user_args() else "en"
	GameSettings.apply_language(_lang)
	_dir = ProjectSettings.globalize_path("res://").path_join("../tools/style/review/story03")
	DirAccess.make_dir_recursive_absolute(_dir)
	_run()


func _run() -> void:
	var gs := root.get_node("GameState")
	gs.start_temp(42)
	var s: Dictionary = gs.data
	s.day = 8
	Letters.ensure(s)
	var letter := Letters.make_request(s, "leo", Seeds.rng(42, "letters", 8))
	s.letters.inbox.append(letter)
	s.friendship["vintner"] = int(Data.rules().friendship.points_per_heart) * 2
	var town := (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(town)
	await _frames(4)
	var ui := LettersUI.open()
	await _frames(10)
	_save("letter")
	ui.queue_free()
	await _frames(3)
	town._npc = "vintner"
	town._on_tab("neighbours")
	await _frames(10)
	_save("neighbour")
	town.queue_free()
	await _frames(3)
	Letters.ensure(s).unlocked_recipes.append("pepper_relish")
	Book.open()
	await _frames(12)
	_save("book")
	for b in root.get_children():
		if b is Book:
			b.queue_free()
	await _frames(3)
	s.day = 100
	var f := (load("res://scenes/farewell/farewell.tscn") as PackedScene).instantiate()
	root.add_child(f)
	await _frames(3)
	var t: float = 0.0
	for e in f._timeline:
		if e.id == "letter":
			t = float(e.start) + f.shot("letter").typed_by() + 1.0
	f.seek(t)
	await _frames(4)
	_save("farewell")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(nm: String) -> void:
	RenderingServer.force_draw(false)
	var p := "%s/%s_%s.png" % [_dir, nm, _lang]
	root.get_texture().get_image().save_png(p)
	print("saved ", p)
