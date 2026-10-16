extends SceneTree
## Smoke shot (BIOMES): vineyard and creek in the wild scene, and the garden gate's biome picker -> user://shots/
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/wild_biomes_shot.gd
## wild_vineyard.png / wild_creek.png: Granny walked up to the nearest vine or elder (highlighted, fruit tag above it);
## wild_vineyard_map.png / wild_creek_map.png: the whole map; wild_picker.png: the picker with the vineyard open and
## the creek locked. Checks on the way (exit code 1 on a failed check): the biome's own tileset is used, every fruit
## tree shows its tag, a vine/elder can be reached and shaken into the bag, a bee hive gives honey, the picker's locks.

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
	for biome in ["vineyard", "creek"]:
		_router.params = {"biome": biome, "seed": SEED}
		_gs.data = {}
		var scene := _open(root)
		await _frames(10)
		var m: Dictionary = scene.map
		_check(not m.is_empty() and m.biome == biome, "%s: the scene built a %s map" % [biome, biome])
		_check(scene.view.ground.tile_set == WildMapView.tileset_for(biome) and
			WildMapView.tileset_for(biome) != WildMapView.tileset(), "%s: own ground tiles" % biome)
		_check(_gs.data.varieties.has("grape_1") and _gs.data.varieties.has("elderberry_6"), "%s: P1 varieties ensured" % biome)
		var tags := 0
		for t in m.fruit_trees:
			var o: Node2D = scene.view.find("fruit_tree", int(t.id))
			tags += 1 if o != null and _tag_shown(o) else 0
		_check(tags == m.fruit_trees.size() and tags >= 4, "%s: every fruit tree shows its tag (%d)" % [biome, tags])
		var tree: Node2D = _nearest_tree(scene)
		_check(tree != null and scene.granny.approach(tree.cell), "%s: Granny can walk up to a fruit tree" % biome)
		for i in 1500:
			await process_frame
			if tree.highlighted:
				break
		await _frames(5)
		_check(tree.highlighted, "%s: the faced tree is highlighted" % biome)
		_shot(root, "wild_" + biome)
		var bag0 := Forage.bag_count(_gs.data)
		scene._use(tree)
		await _frames(3)
		_check(Forage.bag_count(_gs.data) > bag0, "%s: shaking puts %s in the bag" % [biome, tree.info.type])
		await _whole_map("wild_%s_map" % biome, scene)
		scene.queue_free()
		await process_frame
	await _hive()
	await _picker()
	await process_frame
	print("wild_biomes_shot: ", "FAILED" if _failed else "ok")
	quit(1 if _failed else 0)


## A vineyard seed with a bee hive: Granny takes the honey.
func _hive() -> void:
	var sd := -1
	var v := VarietyGen.generate_all(1, 0)
	for k in 200:
		var m := WildGen.generate(SEED + k, 1, "vineyard", "sunny", v)
		if String(m.special.get("kind", "")) == "bee_hive":
			sd = SEED + k
			break
	_check(sd > 0, "a vineyard with a bee hive")
	if sd < 0:
		return
	_router.params = {"biome": "vineyard", "seed": sd}
	_gs.data = {}
	var scene := _open(root)
	await _frames(5)
	var hive: Node2D = null
	for o in scene.view.objects.get_children():
		if o is WildObject and o.kind == "hive":
			hive = o
	_check(hive != null and hive.has_take(), "the hive is on the map")
	if hive != null:
		var honey := int(_gs.data.cupboard.get("honey", 0))
		scene._use(hive)
		await _frames(3)
		_check(int(_gs.data.cupboard.get("honey", 0)) > honey, "the hive gives honey to the cupboard")
		_check(hive.done and not hive.has_take(), "the hive is empty afterwards")
	scene.queue_free()
	await process_frame


func _picker() -> void:
	_gs.data = State.new_game(SEED)
	Economy.unlock(_gs.data, "vineyard")
	var bg := ColorRect.new()
	bg.color = Color("53612e")
	bg.size = Vector2(480, 270)
	root.add_child(bg)
	# loaded at run time: the picker uses autoloads, which a SceneTree script cannot name at compile time
	var p: CanvasLayer = load("res://scenes/wild/biome_picker.gd").new()
	root.add_child(p)
	p.open(_gs.data)
	await _frames(5)
	_check(not p.row("forest").disabled and not p.row("vineyard").disabled, "forest and vineyard are open")
	_check(p.row("creek").disabled, "the creek waits for the boots")
	var picked := [""]
	p.chosen.connect(func(b: String) -> void: picked[0] = b)
	_shot(root, "wild_picker")
	p.row("vineyard").pressed.emit()
	_check(picked[0] == "vineyard" and not p.is_open(), "picking the vineyard reports it and closes")
	bg.queue_free()
	await process_frame


func _open(parent: Node) -> Node:
	var scene := (load("res://scenes/wild/wild.tscn") as PackedScene).instantiate()
	parent.add_child(scene)
	return scene


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
