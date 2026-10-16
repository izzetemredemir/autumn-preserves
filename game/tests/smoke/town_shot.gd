extends SceneTree
## Smoke shot: town square, one shot per tab -> user://shots/town_<tab>.png
## godot --path game -s res://tests/smoke/town_shot.gd


func _initialize() -> void:
	var scene := (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node) -> void:
	for i in 3:
		await process_frame
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	for tab in ["grocer", "orders", "neighbours"]:
		scene._on_tab(tab)
		for i in 12:
			await process_frame
		RenderingServer.force_draw(false)  # macOS skips drawing a covered window
		root.get_texture().get_image().save_png("%s/town_%s.png" % [dir, tab])
		print("saved town_", tab)
	root.get_node("GameState").data.friendship.librarian = 4
	for id in ["vintner", "librarian"]:
		scene._select_npc(id)
		scene._on_tab("neighbours")
		for i in 12:
			await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("%s/town_npc_%s.png" % [dir, id])
	quit()
