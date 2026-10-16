extends SceneTree
## Smoke drive (P2-CAT): the garden with Granny's cat.
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/cat_shot.gd
## Checks the cat sits on today's spot, petting by tap (walk up, purr, heart) and by the interact key (Granny
## facing it), and that petting changes nothing in the save. Saves user://shots/cat_garden.png, cat_petted.png.
## Exit code 1 on a failed check or timeout.

const SEED := 1
const TIMEOUT_FRAMES := 3600
const DIR := "user://shots"

var _frames := 0
var _scene: Node
var _gs: Node
var _router: Node


func _initialize() -> void:
	_gs = root.get_node("GameState")
	_router = root.get_node("Router")
	_run()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames > TIMEOUT_FRAMES:
		_fail("timeout after %d frames" % TIMEOUT_FRAMES)
	return false


func _run() -> void:
	await process_frame
	_router.params = {}
	_router.current = "garden"
	_gs.start_temp(SEED)
	_scene = (load("res://scenes/garden/garden.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	current_scene = _scene
	await _frames_wait(10)
	var cat: Node = _scene.get("cat")
	var spot: Dictionary = load("res://actors/cat/cat_rules.gd").spot_for(int(_gs.data.save_seed), int(_gs.data.day))
	_check(cat != null and cat.get("cell") == spot.cell, "cat sits on today's spot (%s)" % spot.id)
	var granny: Node = _scene.get("granny")
	granny.call("teleport", Vector2i(26, 10), Vector2i.LEFT)
	await _frames_wait(20)
	_check(cat.get("pose") == "sleep", "cat naps while Granny is away")
	# put Granny a few steps from the cat for the shot, so it wakes and looks
	var side: Vector2i = spot.cell + Vector2i(2, 1)
	granny.call("teleport", side, Vector2i.LEFT)
	await _frames_wait(20)
	_check(cat.get("pose") == "look", "cat looks at Granny when she is near")
	_shot("cat_garden")
	var before: String = JSON.stringify(_gs.data)

	# 1. mouse / tap: walk up to the cat and pet it
	_scene.tap_world(cat.hit_rect().get_center())
	await _until(func() -> bool: return cat.call("is_purring"))
	await _frames_wait(10)
	_check(cat.get("pose") == "purr", "tapping the cat purrs")
	_shot("cat_petted")
	await _until(func() -> bool: return not cat.call("is_purring"))
	_check(JSON.stringify(_gs.data) == before, "petting changes nothing in the save")

	# 2. keyboard: Granny faces the cat and presses interact
	var facing: Vector2i = granny.call("facing_cell")
	_check(facing == cat.get("cell"), "Granny faces the cat after walking up")
	granny.emit_signal("interact_requested", facing)
	await _frames_wait(2)
	_check(cat.call("is_purring"), "the interact key purrs too")
	print("CAT SMOKE OK")
	quit(0)


func _until(cond: Callable) -> void:
	while not bool(cond.call()):
		await process_frame


func _frames_wait(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := "%s/%s.png" % [DIR, shot_name]
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		_fail(what)


func _fail(what: String) -> void:
	print("FAIL ", what)
	quit(1)
