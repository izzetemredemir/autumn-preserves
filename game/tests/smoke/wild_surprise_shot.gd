extends SceneTree
## Smoke shot (FUN-FOREST) -> user://shots/: surprise_bush_before / surprise_bush_after (the shrub mid-shiver, then
## the moment after it was used), surprise_pile_burst (a leaf pile bursting), surprise_sparkle (the twinkle) and
## surprise_sparkle_find (the celebration). Uses a temporary game, so no save is touched.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/wild_surprise_shot.gd     (windowed: shots need a GPU)
## (The layer and node classes stay untyped here: they pull in the autoloads, which -s scripts compile before.)
## Exit code 1 on a failed check.

const DAY := 14
const DIR := "user://shots"

var _gs: Node
var _failed := false


func _initialize() -> void:
	_gs = root.get_node("GameState")
	root.get_node("Router").params = {"biome": "forest", "grow": false}
	_run()


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(DIR)
	GameSettings.apply_language("en")
	var sd := _pick_seed()
	_check(sd > 0, "a seed with a bush, a pile and a sparkle")
	_gs.start_temp(sd)
	var d: Dictionary = _gs.data
	d.day = DAY
	d.weather = "sunny"
	var scene: Node = (load("res://scenes/wild/wild.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(8)
	var layer = scene.surprises
	_check(layer != null and not layer.nodes.is_empty(), "the layer has surprises")

	var bush = _node(layer, "bush", "critter")
	if bush == null:
		bush = _node(layer, "bush")
	_stand_beside(scene, bush)
	bush.shiver_now()
	await _frames(4)
	_shot("surprise_bush_before")
	layer.use(bush)
	await create_timer(0.3).timeout
	_shot("surprise_bush_after")
	_check(ForestSurprises.is_consumed(d, bush.id) and bush.gone, "the bush is used up")
	await create_timer(1.2).timeout

	var pile = _node(layer, "pile")
	_stand_beside(scene, pile)
	await _frames(4)
	layer.use(pile)
	await create_timer(0.12).timeout
	_shot("surprise_pile_burst")
	_check(pile.gone, "the pile burst")
	await create_timer(1.0).timeout

	var spark = _node(layer, "sparkle")
	_stand_beside(scene, spark)
	await _frames(4)
	_shot("surprise_sparkle")
	layer.use(spark)
	await create_timer(0.35).timeout
	_shot("surprise_sparkle_find")
	_check(spark.gone, "the sparkle was picked up")
	for c in scene.get_children():
		if c is SpeciesCard and not c.is_queued_for_deletion():
			c.close()
	await _frames(3)
	scene.queue_free()
	await _frames(3)
	print("wild_surprise_shot: %s (seed %d)" % ["FAILED" if _failed else "ok", sd])
	quit(1 if _failed else 0)


## A seed whose day-14 forest has a bush that releases a critter, a pile with a find and a sparkle.
func _pick_seed() -> int:
	for sd in range(1, 400):
		var s := State.new_game(sd)
		VarietyGen.ensure_types(s.varieties, sd)
		s.day = DAY
		SpeciesGen.sync(s)
		var m := WildGen.generate(sd, DAY, "forest", "sunny", s.varieties)
		SpeciesGen.add_pickups(m, sd, DAY)
		var kinds := {}
		for e: Dictionary in ForestSurprises.plan(m, sd, DAY, s.varieties):
			kinds[e.kind] = true
			if e.kind == "bush" and e.reward.t == "critter":
				kinds["critter"] = true
			if e.kind == "pile" and e.reward.t != "none":
				kinds["find"] = true
		if kinds.has("bush") and kinds.has("critter") and kinds.has("find") and kinds.has("sparkle"):
			return sd
	return 0


func _node(layer, kind: String, reward := ""):
	for n in layer.nodes:
		if n.kind == kind and not n.gone and (reward == "" or String(n.entry.reward.t) == reward):
			return n
	return null


func _stand_beside(scene: Node, n) -> void:
	if n == null:
		return
	for dir: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		if scene._walkable(n.cell + dir):
			scene.granny.teleport(n.cell + dir, -dir)
			break
	scene.camera.snap()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	RenderingServer.force_draw(false)  # macOS skips drawing a covered window; the shot must show this frame
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		print("no image for ", shot_name, " (headless: run windowed for the shots)")
		return
	img.save_png("%s/%s.png" % [DIR, shot_name])
	print("saved ", ProjectSettings.globalize_path("%s/%s.png" % [DIR, shot_name]))


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("CHECK FAILED: ", what)
