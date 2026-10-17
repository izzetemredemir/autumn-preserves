extends SceneTree
## Smoke shot (GD-WILD, INT-WILD): the wild scene -> user://shots/
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/wild_shot.gd
## wild.png: a fixed test seed, Granny at the forest entrance, trees, pickups and the seed in the corner.
## wild_demo.png: the demo save (res://dev/demo_save.json: seed 452, day 3, rainy, mushroom ring), Granny walked
## up to the nearest fruit tree (outlined, fruit tag above it). wild_shake.png: a moment after shaking it.
## wild_map.png / wild_demo_map.png: the same two forests whole (the scene in a map-sized SubViewport).
## Starts a throwaway game (GameState.start_temp) for the test seed, like opening the scene on its own.
## Checks the INT-WILD readability rules on the way; exit code 1 on a failed check.

const SEED := 20261016
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
	# 1. test seed, at the entrance
	_router.params = {"biome": "forest", "seed": SEED}
	_gs.data = {}
	var scene := _open(root)
	await _frames(10)
	_shot(root, "wild")
	_check_map(scene)
	await _whole_map("wild_map", scene)
	scene.queue_free()

	# 2. demo save, Granny next to the nearest fruit tree, then she shakes it
	var demo: Dictionary = load("res://ui/dev_panel/dev_tools.gd").load_demo()
	_check(not demo.is_empty(), "demo save loads")
	if not demo.is_empty():
		_gs.data = demo
		_router.params = {"biome": "forest"}
		scene = _open(root)
		await _frames(5)
		_check(String(scene.map.special.get("kind", "")) == "mushroom_ring", "demo forest has the mushroom ring")
		_check_map(scene)
		var tree: Node2D = _nearest_tree(scene)
		_check(tree != null and scene.granny.approach(tree.cell), "Granny can walk up to a fruit tree")
		for i in 1200:  # walking takes time, not frames (headless frames are short)
			await process_frame
			if tree.highlighted:
				break
		await _frames(5)
		_check(tree.highlighted, "the faced fruit tree is highlighted")
		_shot(root, "wild_demo")
		await _whole_map("wild_demo_map", scene)
		scene._use(tree)
		_check_burst(scene, tree)
		await _frames(5)
		_shot(root, "wild_shake")
		_check(tree.done and not _tag_shown(tree), "a shaken tree turns bare and drops its fruit tag")
		scene.queue_free()
	await process_frame
	print("wild_shot: ", "FAILED" if _failed else "ok")
	quit(1 if _failed else 0)


func _open(parent: Node) -> Node:
	var scene := (load("res://scenes/wild/wild.tscn") as PackedScene).instantiate()
	parent.add_child(scene)
	return scene


## INT-WILD: fruit trees with fruit carry their tag; no decor canopy hides a path or clearing tile (those trees are
## stumps); the mossy rocks are the same every time and lie on free grass.
func _check_map(scene: Node) -> void:
	var m: Dictionary = scene.map
	_check(not m.is_empty(), "the scene built a map")
	var tags := 0
	for t in m.fruit_trees:
		var o: Node2D = scene.view.find("fruit_tree", int(t.id))
		tags += 1 if o != null and _tag_shown(o) else 0
	_check(tags == m.fruit_trees.size(), "every fruit tree shows its tag (%d / %d)" % [tags, m.fruit_trees.size()])
	var open: Dictionary = WildMapView.open_cells(m)
	var hiding := 0
	var stumps := 0
	for o in scene.view.objects.get_children():
		if o is WildObject and o.kind == "decor":
			var cut := bool(o.info.get("cut", false))
			stumps += 1 if cut else 0
			hiding += 1 if not cut and WildMapView.canopy_covers(o.cell, open) else 0
	_check(hiding == 0, "no decor canopy hides a path or clearing tile (%d stumps instead)" % stumps)
	var rocks: Array[Vector2i] = WildMapView.scatter_rocks(m)
	_check(rocks == WildMapView.scatter_rocks(m), "mossy rocks are deterministic")
	_check(rocks.size() >= 3, "a few mossy rocks on the map (%d)" % rocks.size())
	var w := int(m.w)
	for c in rocks:
		var free: bool = int(m.ground[c.y * w + c.x]) == WildGen.T_GRASS and WildGen.is_walkable(m, c)
		_check(free, "rock at %s lies on free grass" % c)


## Right after a shake the leaves start inside the painted canopy (not at the old placeholder height) and the
## "+n" bubble sits above the tree.
func _check_burst(scene: Node, tree: Node2D) -> void:
	var feet := tree.position.y
	var leaves := 0
	var inside := 0
	var bubble_y := INF
	for c in scene.view.fx.get_children():
		if c is ColorRect and (c.size == Vector2(4, 3) or c.size == Vector2(3, 4)):  # FEEL leaves: 4x3 or 3x4 with an ink edge
			leaves += 1
			inside += 1 if c.position.y < feet - 24 and c.position.y > feet - 72 else 0
		elif c is PanelContainer:
			bubble_y = minf(bubble_y, c.position.y + c.size.y)
	_check(leaves > 0 and inside == leaves, "leaf burst starts in the canopy (%d / %d leaves)" % [inside, leaves])
	_check(bubble_y <= feet - 64, "the +n bubble sits above the tree (bubble bottom %d, feet %d)" % [bubble_y, feet])


## The same forest drawn whole: a second scene in a SubViewport the size of the map, so the camera shows it all.
func _whole_map(shot_name: String, scene: Node) -> void:
	var sv := SubViewport.new()
	sv.size = scene.view.size_px()
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	var whole := _open(sv)
	await _frames(5)
	RenderingServer.force_draw(false)
	_save(sv.get_texture().get_image(), shot_name)
	whole.queue_free()
	sv.queue_free()
	await process_frame


func _nearest_tree(scene: Node) -> Node2D:
	var from: Vector2 = scene.granny.position
	var best: Node2D = null
	for t in scene.map.fruit_trees:
		var o: Node2D = scene.view.find("fruit_tree", int(t.id))
		if o != null and (best == null or o.position.distance_to(from) < best.position.distance_to(from)):
			best = o
	return best


func _tag_shown(o: Node2D) -> bool:
	var tag: Node2D = o.get("_tag")
	return tag != null and tag.visible


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(vp: Viewport, shot_name: String) -> void:
	RenderingServer.force_draw(false)  # macOS skips drawing a covered window; the shot must show this frame
	_save(vp.get_texture().get_image(), shot_name)


func _save(img: Image, shot_name: String) -> void:
	var path := "%s/%s.png" % [DIR, shot_name]
	if img == null:
		print("no image for ", shot_name, " (headless: run windowed for the shots)")
		return
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		_failed = true
		printerr("FAIL ", what)
