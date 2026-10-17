extends SceneTree
## Smoke shots: the mini-games, each a few seconds in -> user://shots/mg_<id>.png
##   godot --path game -s res://tests/smoke/minigames_shot.gd
## Each game is started on its own with a fixed ctx (no autoplay, so the first-impression screen shows).
## Fills are ProductGen.describe() style: three palette tones, dark -> light. "game" names the folder when the shot
## id is not the game id (knead_bread).

const GAMES := {
	"stir_pot": {"seed": 7, "recipe": "jam", "desc": {"appearance": {"fill": ["a22512", "c94d2e", "e19064"]}}},
	"pack_jar": {"seed": 7, "recipe": "pickle", "ingredient_types": ["cucumber", "carrot", "beet"],
		"desc": {"appearance": {"fill": "7a9a3a"}}},
	"press": {"seed": 7, "recipe": "juice", "desc": {"appearance": {"fill": ["a22512", "c94d2e", "e19064"]}}},
	"knead": {"seed": 7, "recipe": "pie", "desc": {"appearance": {"fill": ["62272c", "a22512", "c94d2e"]}}},
	"knead_bread": {"game": "knead", "seed": 7, "recipe": "bread",
		"desc": {"appearance": {"fill": ["83571e", "c58845", "e5bd7f"]}}},
}


func _initialize() -> void:
	root.get_node("GameState").start_new(1)
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	for id: String in GAMES:
		var game := String(GAMES[id].get("game", id))
		var mg: Node = (load("res://minigames/%s/%s.tscn" % [game, game]) as PackedScene).instantiate()
		root.add_child(mg)
		mg.start(GAMES[id])
		await create_timer(3.0).timeout
		RenderingServer.force_draw(false)  # macOS skips drawing a covered window
		root.get_texture().get_image().save_png("user://shots/mg_%s.png" % id)
		print("saved mg_", id)
		mg.queue_free()
		await process_frame
	await _action_shots()
	quit()


## JURY-MG: the moments the first-impression shots miss: a filled jar (Full!), a press mid-song, a dough squash.
func _action_shots() -> void:
	var jar: Node = (load("res://minigames/pack_jar/pack_jar.tscn") as PackedScene).instantiate()
	root.add_child(jar)
	jar.start(GAMES["pack_jar"])
	var guard := 0
	while jar._fill_label.text != tr("MG_PACK_FILL") % 100 and guard < 120:
		guard += 1
		jar._set_piece_x(guard % 6)
		jar._drop_piece()
		while not jar._fall.is_empty():
			await process_frame
	await create_timer(0.35).timeout
	await _snap("mg_pack_jar_full")
	jar.queue_free()
	await process_frame
	var press: Node = (load("res://minigames/press/press.tscn") as PackedScene).instantiate()
	root.add_child(press)
	var pctx: Dictionary = GAMES["press"].duplicate()
	pctx["autoplay"] = true
	press.start(pctx)
	await create_timer(9.0).timeout
	await _snap("mg_press_play")
	press.queue_free()
	await process_frame
	var knead: Node = (load("res://minigames/knead/knead.tscn") as PackedScene).instantiate()
	root.add_child(knead)
	knead.start(GAMES["knead"])
	await create_timer(1.5 + 0.8 + 0.05).timeout  # READY, then the first beat
	knead._press(KneadRules.beat_side(0), Time.get_ticks_usec())
	await create_timer(0.05).timeout
	await _snap("mg_knead_hit")
	knead.queue_free()
	await process_frame


func _snap(shot: String) -> void:
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("user://shots/%s.png" % shot)
	print("saved ", shot)
