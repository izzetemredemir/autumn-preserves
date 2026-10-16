extends SceneTree
## Smoke shots: the four mini-games, each a few seconds in -> user://shots/mg_<id>.png
##   godot --path game -s res://tests/smoke/minigames_shot.gd
## Each game is started on its own with a fixed ctx (no autoplay, so the first-impression screen shows).

const GAMES := {
	"stir_pot": {"seed": 7, "recipe": "jam", "desc": {"appearance": {"fill": "c94d2e"}}},
	"pack_jar": {"seed": 7, "recipe": "pickle", "ingredient_types": ["cucumber", "carrot", "beet"],
		"desc": {"appearance": {"fill": "7a9a3a"}}},
	"press": {"seed": 7, "recipe": "juice", "desc": {"appearance": {"fill": "c94d2e"}}},
	"knead": {"seed": 7, "recipe": "pie", "desc": {"appearance": {"fill": "c58845"}}},
}


func _initialize() -> void:
	root.get_node("GameState").start_new(1)
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	for id: String in GAMES:
		var mg: Node = (load("res://minigames/%s/%s.tscn" % [id, id]) as PackedScene).instantiate()
		root.add_child(mg)
		mg.start(GAMES[id])
		await create_timer(3.0).timeout
		RenderingServer.force_draw(false)  # macOS skips drawing a covered window
		root.get_texture().get_image().save_png("user://shots/mg_%s.png" % id)
		print("saved mg_", id)
		mg.queue_free()
		await process_frame
	quit()
