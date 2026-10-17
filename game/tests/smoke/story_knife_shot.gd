extends SceneTree
## Smoke shot (STORY-04): Teo's knife in the forest. Day 2 of a temporary game: the sparkle waits at a tree foot, picking
## it gives Granny's bubble, a heart, nothing in the bag, no coins; once per save. Saves user://shots/story04_find_<locale>.png.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/story_knife_shot.gd [-- --locale=tr]   (windowed)
## Exit code 1 on a failed check.

var _gs: Node
var _fail := 0
var _locale := "en"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--locale="):
			_locale = a.substr(9)
	_gs = root.get_node("GameState")
	root.get_node("Router").params = {"biome": "forest", "grow": false}
	_run()


func _run() -> void:
	await process_frame
	GameSettings.apply_language(_locale)
	_gs.start_temp(7)
	var d: Dictionary = _gs.data
	d.day = 2
	d.weather = "sunny"
	var scene: Node = (load("res://scenes/wild/wild.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(8)
	var layer = scene.surprises
	var knife = null
	for n in layer.nodes:
		if n.kind == "knife":
			knife = n
	_check(knife != null, "the knife waits on day 2")
	var coins0 := int(d.coins)
	var bag0 := Forage.bag_count(d)
	var energy0 := int(d.get("energy", 0))
	if knife != null:
		for dir: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			if scene._walkable(knife.cell + dir):
				scene.granny.teleport(knife.cell + dir, -dir)
				break
		scene.camera.snap()
		await _frames(4)
		layer.use(knife)
		await create_timer(0.5).timeout
		_check(knife.gone and Story.knife_found(d), "picked up, recorded")
		_check(Forage.bag_count(d) == bag0 and int(d.coins) == coins0 and int(d.get("energy", 0)) == energy0, "nothing in the bag, no coins, no energy")
		_shot("story04_find_" + _locale)
		await create_timer(2.6).timeout
		_shot("story04_find2_" + _locale)
	scene.queue_free()
	await _frames(3)
	var again: Node = (load("res://scenes/wild/wild.tscn") as PackedScene).instantiate()
	root.add_child(again)
	await _frames(6)
	var left := false
	for n in again.surprises.nodes:
		left = left or n.kind == "knife"
	_check(not left, "once per save: no second knife")
	again.queue_free()
	await _frames(2)
	print("STORY KNIFE SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("user://shots/%s.png" % name)
	print("saved ", ProjectSettings.globalize_path("user://shots/%s.png" % name))
