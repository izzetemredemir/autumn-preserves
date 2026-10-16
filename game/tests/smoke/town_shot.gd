extends SceneTree
## Smoke shot: town square with debug jars -> user://shots/town.png
## godot --path game -s res://tests/smoke/town_shot.gd


func _initialize() -> void:
	var scene := (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node) -> void:
	for i in 3:
		await process_frame
	scene._on_tab("orders")
	for i in 12:
		await process_frame
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir + "/town.png")
	print("saved ", ProjectSettings.globalize_path(dir + "/town.png"))
	quit()
