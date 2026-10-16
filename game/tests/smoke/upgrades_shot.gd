extends SceneTree
## Smoke shot (UPGRADES): the grocer's three groups and the garden after buying the extra beds.
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/upgrades_shot.gd
## Saves user://shots/upgrades_<group>.png and upgrades_garden.png.

const DIR := "user://shots"


func _initialize() -> void:
	_run()


func _shot(name: String) -> void:
	for i in 12:
		await process_frame
	RenderingServer.force_draw(false)  # macOS skips drawing a covered window
	root.get_texture().get_image().save_png("%s/%s.png" % [DIR, name])
	print("saved ", name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	await process_frame
	var gs := root.get_node("GameState")
	gs.start_temp(1)
	gs.data.coins = 900
	var town := (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(town)
	await process_frame
	for g in ["supplies", "seeds", "upgrades"]:
		town._set_group(g)
		await _shot("upgrades_" + g)
	town._on_buy("beds")
	town._on_buy("bag")
	town.queue_free()
	await process_frame
	var garden := (load("res://scenes/garden/garden.tscn") as PackedScene).instantiate()
	root.add_child(garden)
	await _shot("upgrades_garden")
	if gs.data.garden.beds.size() != 6:
		push_error("upgrades_shot: expected 6 beds")
		quit(1)
		return
	quit()
