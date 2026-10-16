class_name Transition
extends CanvasLayer
## Full-screen scene change (tech-spec §7): dither to dark, autosave, Router.goto, dither back.
## Any scene may call `Transition.go("kitchen")` instead of `Router.goto("kitchen")`.

const OUT_SEC := 0.32
const IN_SEC := 0.32
const COLOR := Color("3d1f29")

static var _busy := false


## Fades out, autosaves (spec §9: every scene change saves), changes scene, fades in.
## Ignored while another transition runs.
static func go(id: String, params := {}) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or _busy:
		return
	_busy = true
	var t := Transition.new()
	tree.root.add_child(t)
	t._run(id, params)


static func is_busy() -> bool:
	return _busy


## Where a game starts or resumes: the garden, or the kitchen until the garden scene exists.
static func home_scene() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var router: Node = tree.root.get_node_or_null("Router") if tree != null else null
	if router != null and router.exists("garden"):
		return "garden"
	return "kitchen"


func _run(id: String, params: Dictionary) -> void:
	layer = 90
	var cover := DitherCover.new()
	cover.color = COLOR
	add_child(cover)
	await cover.fade(DitherCover.LEVELS, OUT_SEC)
	if GameState.has_game():
		Save.save_game(GameState.data)
	Router.goto(id, params)
	await get_tree().process_frame
	await get_tree().process_frame
	await cover.fade(0, IN_SEC)
	_busy = false
	queue_free()
