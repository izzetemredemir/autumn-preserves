class_name Festival
extends CanvasLayer
## FESTIVAL · The Harvest Festival showcase day (title menu, any build). Festival.start() loads the crafted festival
## save (res://dev/festival_save.json, made by tools/scripts/make_festival.gd) as a temporary game that is never
## written to disk, opens Granny's note with the six-step checklist and walks into the garden.
## This director lives under the tree root while a festival save is loaded: the start card when the garden first
## shows, a bobbing marker over the rare tree in today's forest, and the end card once all six steps are ticked and
## nothing else is on screen (Keep playing / Back to title). It frees itself when the festival ends or another game
## is loaded. Progress marks live in the temporary state: flags.festival.started / ended.

const LAYER := 30  ## inside GrannyTodo's popup range: the note hides while a card shows
const QUIET_IN := ["garden", "kitchen", "pantry", "parlor", "town"]
const POPUP_LAYERS := Vector2i(12, 60)
const START_DELAY := 0.5
const END_DELAY := 1.2  ## after the last tick, so the note's celebration shows first
const TODO := "res://ui/tutorial/granny_todo.gd"
const TRANSITION := "res://ui/transition/transition.gd"

var _card: FestivalCard
var _wait := 0.0
var _marker: Node2D
var _marked_scene: Node
var _away := false  ## has left the title (the director is made while the title still shows)


## Loads the festival save as a temporary game and goes to the garden. False when the save is missing.
static func start() -> bool:
	var d := FestivalFacts.load_save()
	if d.is_empty():
		return false
	var tree := Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("GameState")
	if gs == null:
		return false
	gs.data = d
	gs.notify(PackedStringArray(["*"]))
	load(TODO).ensure()
	ensure()
	load(TRANSITION).go("garden")
	return true


static func ensure() -> Festival:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group("festival") as Festival
	if found != null:
		return found
	var f := Festival.new()
	tree.root.add_child.call_deferred(f)
	return f


func _ready() -> void:
	layer = LAYER
	add_to_group("festival")


func _data() -> Dictionary:
	var gs := get_node_or_null("/root/GameState")
	return gs.data if gs != null else {}


func _scene_id() -> String:
	var r := get_node_or_null("/root/Router")
	return String(r.current) if r != null else ""


func _process(delta: float) -> void:
	var d := _data()
	var id := _scene_id()
	if id not in ["", "title"]:
		_away = true
	if not TodoRules.is_festival(d) or (_away and id == "title"):
		queue_free()
		return
	var f := TodoRules.festival(d)
	if _card != null:
		return
	_update_marker(d, f)
	if _busy():
		_wait = 0.0
		return
	if not bool(f.get("started", false)):
		if _scene_id() == "garden":
			_wait += delta
			if _wait >= START_DELAY:
				f["started"] = true
				_show("start")
		return
	if not bool(f.get("ended", false)) and TodoRules.festival_today(d) and _all_done(d) and _scene_id() in QUIET_IN:
		_wait += delta
		if _wait >= END_DELAY:
			f["ended"] = true
			_show("end")
	else:
		_wait = 0.0


## Taps never reach the scene under a card (the garden turns a tap into a walk); its buttons take mouse events.
func _input(event: InputEvent) -> void:
	if _card != null and event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()


func _all_done(d: Dictionary) -> bool:
	var bits := TodoRules.bits_of(d)
	for step in TodoRules.FESTIVAL:
		if not TodoRules.is_done(bits, step):
			return false
	return true


func _show(which: String) -> void:
	_wait = 0.0
	_card = FestivalCard.new()
	add_child(_card)
	_card.chosen.connect(_on_chosen)
	if which == "start":
		_card.show_start()
	else:
		_card.show_end(FestivalFacts.summary(_data()))
	_set_granny(false)


func _on_chosen(id: String) -> void:
	if _card != null:
		_card.queue_free()
	_card = null
	_set_granny(true)
	if id == "title":
		load(TRANSITION).go("title")
	elif id == "go":
		var todo := get_tree().get_first_node_in_group("granny_todo")
		if todo != null and todo.has_method("pin_open"):
			todo.pin_open()  # the six steps at a glance; a click folds the note


## Granny stands still while a card is up (arrow keys move the focus, not her).
func _set_granny(on: bool) -> void:
	var scene := get_tree().current_scene
	var granny: Node = scene.get("granny") if scene != null else null
	if granny != null and "input_enabled" in granny:
		granny.input_enabled = on


## A transition, a mini-game, a result card, letters, the book or a menu is on screen.
func _busy() -> bool:
	var tr_script: GDScript = load(TRANSITION)
	if tr_script.is_busy():
		return true
	var tree := get_tree()
	var nodes: Array[Node] = tree.root.get_children()
	var scene := tree.current_scene
	if scene == null:
		return true
	nodes.append_array(scene.get_children())
	for n in nodes:
		var cl := n as CanvasLayer
		if cl == null or cl == self or cl.is_in_group("granny_todo") or not cl.visible:
			continue
		if cl.layer < POPUP_LAYERS.x or cl.layer > POPUP_LAYERS.y:
			continue
		for c in cl.get_children():
			if c is CanvasItem and c.visible:
				return true
	for key in ["menu", "_mg", "_card"]:
		var v: Variant = scene.get(key)
		if v is Object and is_instance_valid(v):
			return true
	return false


# --- the rare tree in the forest -------------------------------------------------------------------------------------

## Today's rare tree gets a bobbing marker in the forest until it is shaken (ONBOARD-GUIDE: only with Granny's guide
## off; otherwise the guide's arrow points at the tree).
func _update_marker(d: Dictionary, f: Dictionary) -> void:
	var scene := get_tree().current_scene
	var shaken := TodoRules.is_done(TodoRules.bits_of(d), "f_shake") or not TodoRules.festival_today(d)
	if _scene_id() != "wild" or scene == null or shaken or GuideArrow.enabled():
		if _marker != null and is_instance_valid(_marker):
			_marker.queue_free()
		_marker = null
		return
	if _marked_scene == scene and _marker != null and is_instance_valid(_marker):
		return
	var view: Node = scene.get("view")
	if view == null or not view.has_method("find") or String(scene.get("biome")) != String(f.get("biome", "forest")):
		return
	var tree_obj: Node2D = view.find("fruit_tree", int(f.get("tree", -1)))
	var fx: Node = view.get("fx")
	if tree_obj == null or fx == null:
		return
	_marked_scene = scene
	_marker = TreeMarker.new()
	_marker.name = "FestivalMarker"
	_marker.position = (tree_obj.call("top") as Vector2).round() + Vector2(0, -4)
	fx.add_child(_marker)


## A gold arrow pointing down at the tree, bobbing a pixel or two (palette colours, whole pixels). While the tree is
## off screen the arrow waits at the screen edge (under the HUD bar) with a paper tag "Rare tree" and points the way.
## Four drawn directions, never a rotated sprite.
class TreeMarker:
	extends Node2D
	const GOLD := Color("e5bd7f")
	const AMBER := Color("b66813")
	const INK := Color("111010")
	const TEXT := Color("50361e")
	const DOWN := ["#########", ".#ooooo#.", "..#ooo#..", "...#o#...", "....#...."]
	const EDGE := 6  ## px from the screen sides and bottom
	const TOP := 34  ## px from the screen top: under the HUD bar
	const STEP := {"up": Vector2(0, -1), "down": Vector2(0, 1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}
	var _t := 0.0
	var _dir := "down"
	var _tip := Vector2.ZERO
	var _plate: PanelContainer

	func _ready() -> void:
		z_index = 45
		_plate = PanelContainer.new()
		_plate.theme_type_variation = &"PaperPanel"
		_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_plate.visible = false
		var l := Label.new()
		l.text = tr("FESTIVAL_RARE_TREE")
		l.add_theme_color_override("font_color", TEXT)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		_plate.add_child(l)
		add_child(_plate)

	func _process(delta: float) -> void:
		_t += delta
		var bob := int(_t * 3.0) % 2 * 2
		var xf := get_global_transform_with_canvas()
		var at := xf.origin
		var vp := get_viewport_rect().size
		var plate := _plate.get_combined_minimum_size()
		var r := Rect2(EDGE, TOP, vp.x - 2 * EDGE, vp.y - TOP - EDGE)
		if r.grow(-2).has_point(at):
			_dir = "down"
			_tip = Vector2(0, -bob)
			_plate.visible = false
		else:
			var c := Vector2(clampf(at.x, r.position.x, r.end.x), clampf(at.y, r.position.y, r.end.y))
			var d := at - c
			_dir = ("up" if d.y < 0 else "down") if absf(d.y) >= absf(d.x) else ("left" if d.x < 0 else "right")
			# keep the tag on screen beside the arrow
			if _dir in ["up", "down"]:
				c.x = clampf(c.x, r.position.x + ceilf(plate.x / 2.0), r.end.x - ceilf(plate.x / 2.0))
			else:
				c.y = clampf(c.y, r.position.y + ceilf(plate.y / 2.0), r.end.y - ceilf(plate.y / 2.0))
			_tip = (xf.affine_inverse() * c).round() + (STEP[_dir] as Vector2) * bob
			var off: Vector2
			match _dir:
				"up":
					off = Vector2(-floorf(plate.x / 2.0), 7)
				"down":
					off = Vector2(-floorf(plate.x / 2.0), -7 - plate.y)
				"left":
					off = Vector2(7, -floorf(plate.y / 2.0))
				_:
					off = Vector2(-7 - plate.x, -floorf(plate.y / 2.0))
			_plate.size = plate
			_plate.position = _tip + off
			_plate.visible = true
		queue_redraw()

	func _draw() -> void:
		for y in DOWN.size():
			var row: String = DOWN[y]
			for x in row.length():
				var ch := row[x]
				if ch == ".":
					continue
				var col := INK if ch == "#" else (GOLD if y < 2 else AMBER)
				var p := Vector2(x - 4, y - 4)  # DOWN with its tip at (0, 0)
				match _dir:
					"up":
						p = Vector2(p.x, -p.y)
					"right":
						p = Vector2(p.y, p.x)
					"left":
						p = Vector2(-p.y, p.x)
				draw_rect(Rect2(_tip + p, Vector2.ONE), col)
