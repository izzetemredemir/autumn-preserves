extends SceneTree
## Smoke shot (WILD-LIFE): ambient critters in the forest, vineyard, creek and garden -> user://shots/
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/critters_shot.gd
## critters_forest.png / critters_vineyard.png / critters_creek.png / critters_garden.png: Granny stopped a few tiles from
## a critter of the biome. Checks on the way (exit code 1 on a failed check): the node budget, a squirrel runs up its
## tree and a hedgehog curls when Granny comes close, sparrows sit on the vine posts, a frog dives, the robin sits on the
## fence, windy birds sit still, fog hides what is far from Granny. Throwaway games only (GameState.start_temp).

const SEED := 20261017
const DIR := "user://shots"

var _gs: Node
var _router: Node
var _failed := false


func _initialize() -> void:
	_gs = root.get_node("GameState")
	_router = root.get_node("Router")
	_run()


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(DIR)
	await _forest()
	await _vineyard()
	await _creek()
	await _garden()
	await _weather()
	print("critters_shot: ", "FAILED" if _failed else "ok")
	quit(1 if _failed else 0)


func _wild(biome: String, weather := "sunny", day := 3) -> Node:
	_gs.start_temp(SEED)
	_gs.data.day = day
	_gs.data.weather = weather
	_router.params = {"biome": biome}
	var scene := (load("res://scenes/wild/wild.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(5)
	return scene


func _critters(scene: Node) -> Array:
	var layer: Node = scene.view.objects.get_node_or_null("Critters")
	return layer.critters if layer != null else []


func _of(list: Array, kind: String) -> Array:
	return list.filter(func(c: Node) -> bool: return c.kind == kind)


## Puts Granny on an open cell `tiles` away (straight line, 5..tiles+1) from `c`, camera on her.
func _stand_near(scene: Node, c: Node2D, tiles: int) -> void:
	var at := Vector2i(floori(c.home.x / 16.0), floori((c.home.y - 1.0) / 16.0))
	for d in range(tiles, tiles + 4):
		for off in [Vector2i(d, 0), Vector2i(-d, 0), Vector2i(0, d), Vector2i(0, -d), Vector2i(d, d), Vector2i(-d, d)]:
			var cell: Vector2i = at + off
			if WildGen.is_walkable(scene.map, cell) and cell != scene.map.entrance:
				scene.granny.teleport(cell, Vector2i.UP)
				scene.camera.snap()
				return


func _forest() -> void:
	var scene := await _wild("forest")
	var list := _critters(scene)
	_check(list.size() >= 6 and list.size() <= CritterRules.MAX_NODES, "forest: %d critters within the budget" % list.size())
	var sq: Node2D = _of(list, "squirrel")[0]
	var hog: Node2D = _of(list, "hedgehog")[0]
	_stand_near(scene, sq, 6)
	await _frames(10)
	_check(sq.state == "idle", "the squirrel sits while Granny is away")
	_shot("critters_forest")
	_stand_near(scene, sq, 2)
	await _frames(150)
	_check(sq.state == "climb" or sq.state == "gone", "the squirrel runs up its tree when Granny comes close (%s)" % sq.state)
	_stand_near(scene, hog, 1)
	await _frames(6)
	_check(hog.state == "curl", "the hedgehog curls up when Granny is close")
	scene.queue_free()
	await process_frame


func _vineyard() -> void:
	var scene := await _wild("vineyard")
	var list := _critters(scene)
	var perched := _of(list, "bird").filter(func(c: Node) -> bool: return c.perch)
	_check(perched.size() >= 3 and list.size() <= CritterRules.MAX_NODES, "vineyard: %d sparrows on the posts" % perched.size())
	_stand_near(scene, perched[0], 6)
	await _frames(10)
	_shot("critters_vineyard")
	_stand_near(scene, perched[0], 2)
	await _frames(120)
	_check(perched[0].state == "fly" or perched[0].state == "gone", "a sparrow flies off the post")
	scene.queue_free()
	await process_frame


func _creek() -> void:
	var scene := await _wild("creek")
	var list := _critters(scene)
	_check(_of(list, "frog").size() >= 3 and _of(list, "ring").size() >= 3, "creek: frogs and fish rings")
	var frog: Node2D = _of(list, "frog")[0]
	_stand_near(scene, frog, 6)
	await _frames(200)
	var ring_seen := _of(list, "ring").any(func(c: Node) -> bool: return c.visible)
	_check(ring_seen, "a fish ring shows on the water")
	_shot("critters_creek")
	_stand_near(scene, frog, 2)
	await _frames(90)
	_check(frog.state == "dive" or frog.state == "gone", "the frog dives into the creek (%s)" % frog.state)
	scene.queue_free()
	await process_frame


func _garden() -> void:
	_gs.start_temp(SEED)
	_gs.data.day = 3
	_gs.data.weather = "sunny"
	_router.params = {}
	var scene := (load("res://scenes/garden/garden.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(10)
	var layer: Node = scene.objects.get_node_or_null("Critters")
	var list: Array = layer.critters if layer != null else []
	var robin: Node2D = _of(list, "bird")[0] if not _of(list, "bird").is_empty() else null
	_check(robin != null and robin.species == "robin" and robin.perch, "garden: the robin sits on the fence")
	if robin != null:
		scene.granny.teleport(Vector2i(13, 11), Vector2i.DOWN)
		await _frames(40)
		_check(robin.visible and robin.state != "gone", "the robin stays on the fence while Granny is a few tiles off")
		_shot("critters_garden")
	scene.queue_free()
	await process_frame


func _weather() -> void:
	var scene := await _wild("forest", "windy")
	var birds := _of(_critters(scene), "bird")
	_stand_near(scene, birds[0], 12)
	await _frames(400)
	_check(birds.all(func(b: Node) -> bool: return b.state == "idle"), "windy: birds sit still")
	scene.queue_free()
	await process_frame
	scene = await _wild("forest", "foggy")
	var list := _critters(scene)
	scene.granny.teleport(scene.map.entrance + Vector2i.UP, Vector2i.UP)
	await _frames(10)
	var far := list.filter(func(c: Node) -> bool: return c.home.distance_to(scene.granny.position) > Critter.FOG_SEE + 4.0)
	_check(not far.is_empty() and far.all(func(c: Node) -> bool: return not c.visible), "foggy: far critters are hidden")
	scene.queue_free()
	await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	RenderingServer.force_draw(false)
	var path := "%s/%s.png" % [DIR, shot_name]
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		print("FAIL ", what)
		_failed = true
