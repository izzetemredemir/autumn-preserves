extends SceneTree
## Smoke shot (P1-SEEDLAB): three moments of the Seed Lab's "Watch it grow" replay and the recipe book's
## "How it was made" card -> user://shots/seedlab_1.png (value noise), seedlab_2.png (Poisson-disk trees over the
## stream), seedlab_3.png (A | B, flood-fill check), howmade.png.
## godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/seedlab_shot.gd

const SEED := 20261016
const HOW_KEY := "jam|crabapple_4|cinnamon"

var _extra := OS.get_cmdline_user_args().has("--all")  ## also save the other steps (seedlab_x_*.png)


func _initialize() -> void:
	root.get_node("Router").params = {"seed": SEED}
	var scene := (load("res://scenes/seed_lab/seed_lab.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_run(scene)


func _run(lab: Node) -> void:
	await _frames(10)
	await _at(lab, 1.0, "seedlab_1")
	await _at(lab, GrowView.start(2) + 1.0, "seedlab_2")
	if _extra:
		await _at(lab, GrowView.start(1) + 0.8, "seedlab_x_stream")
		await _at(lab, GrowView.start(3) + 1.0, "seedlab_x_paths")
		await _at(lab, GrowView.start(4) + 1.2, "seedlab_x_pickups")
		await _at(lab, GrowView.start(5) + 1.6, "seedlab_x_slide")
		await _at(lab, GrowView.total(), "seedlab_x_done")
	lab.compare_btn.button_pressed = true
	await _at(lab, GrowView.start(5) + 0.7, "seedlab_3")
	if _extra:
		await _at(lab, GrowView.total(), "seedlab_x_compare")
	lab.queue_free()
	await _frames(2)

	var gs := root.get_node("GameState")
	gs.start_new(7)
	gs.data.found_varieties = ["crabapple_4"]
	gs.data.book.variants[HOW_KEY] = {"best_q": 3, "best_stars": 5, "count": 2, "first_day": 1}
	var book := Book.open()
	await _frames(4)
	book.open_how(HOW_KEY)
	await _frames(6)
	_save("howmade")
	if _extra:
		book.close_how()
		var more := ["chutney|pear_2|pepper_4|ginger", "pickle|cucumber_1|-", "fruit_butter|quince_2|-"]
		for k in more.size():
			book.open_how(more[k])
			await _frames(4)
			_save("howmade_x_%d" % k)
			book.close_how()
	quit()


func _at(lab: Node, at: float, nm: String) -> void:
	lab.seek_grow(at)
	await _frames(3)
	_save(nm)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	var p := "user://shots/%s.png" % nm
	root.get_texture().get_image().save_png(p)
	print("saved ", ProjectSettings.globalize_path(p))
