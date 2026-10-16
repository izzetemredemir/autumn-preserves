extends SceneTree
## Smoke shot (GD-WILD): the wild scene with a fixed test seed -> user://shots/wild.png
## godot --path game -s res://tests/smoke/wild_shot.gd
## Shows Granny at the forest entrance, trees, pickups and the seed in the corner. Starts a test game
## (GameState.start_new) when none is running, like opening the scene on its own.

const SEED := 20261016


func _initialize() -> void:
	root.get_node("Router").params = {"biome": "forest", "seed": SEED}
	var scene := (load("res://scenes/wild/wild.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_run()


func _run() -> void:
	for i in 10:
		await process_frame
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(dir + "/wild.png")
	print("saved ", ProjectSettings.globalize_path(dir + "/wild.png"))
	quit()
