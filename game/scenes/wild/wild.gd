extends Node2D
## Wild scene (GD-WILD, spec §7.1): today's procedural forest. Rules live in WildGen/Forage; this scene only
## draws the map, walks Granny and shows feedback.
## Router.params: "biome" (default "forest"); "seed" is used only when no game is running (test start).

const Fx := preload("res://scenes/wild/wild_fx.gd")
const GRANNY := preload("res://player/granny.tscn")

var biome := "forest"
var map: Dictionary = {}
var granny: Granny
var _leaving := false

@onready var view: WildMapView = $Map
@onready var camera: FollowCamera = $Camera
@onready var seed_label: Label = %Seed


func _ready() -> void:
	biome = String(Router.params.get("biome", "forest"))
	if not GameState.has_game():
		GameState.start_new(int(Router.params.get("seed", Seeds.random_save_seed())))
	var s: Dictionary = GameState.data
	map = WildGen.generate(int(s.save_seed), int(s.day), biome, String(s.weather), s.varieties)
	if map.is_empty():
		push_warning("Wild: no map for biome '%s'" % biome)
		_exit.call_deferred()
		return
	view.show_map(map, s.varieties)

	granny = GRANNY.instantiate()
	view.objects.add_child(granny)
	var entrance: Vector2i = map.entrance
	granny.setup(Vector2i(int(map.w), int(map.h)), _walkable, _spawn_cell(entrance), Vector2i.UP)
	granny.stepped.connect(_on_stepped)
	granny.interact_requested.connect(_on_interact)
	_refresh()

	camera.target = granny
	camera.bounds = Rect2i(Vector2i.ZERO, view.size_px())
	camera.snap()
	seed_label.text = "%s %d" % [tr("UI_SEED"), int(map.seed)]
	Audio.play_music("mus_forest")
	Audio.play_ambient("amb_forest")


func _process(_delta: float) -> void:
	if granny != null:
		view.set_highlight(view.object_at_cell(granny.facing_cell()) if not granny.is_moving() else null)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse arrives as emulated touch (project: emulate_touch_from_mouse), so one handler serves both.
	if event is InputEventScreenTouch and event.pressed and granny != null and not _leaving:
		get_viewport().set_input_as_handled()
		_tap(get_canvas_transform().affine_inverse() * event.position)


func _tap(p: Vector2) -> void:
	var o := view.object_at_point(p)
	if o != null:
		if o.kind == "exit":
			granny.walk_to(o.cell)
		elif not granny.approach(o.cell, _use.bind(o)):
			Fx.bubble(view.fx, _top(o), tr("WILD_CANT_REACH"))
		return
	granny.walk_to(Granny.point_to_cell(p))


func _on_interact(cell: Vector2i) -> void:
	var o := view.object_at_cell(cell)
	if o == null:
		o = view.object_at_cell(granny.current_cell())  # standing on a ground pickup
	if o != null:
		_use(o)


func _on_stepped(cell: Vector2i) -> void:
	if cell == map.entrance:
		_exit()
		return
	var t := int(map.ground[cell.y * int(map.w) + cell.x])
	Audio.play_sfx("sfx_step_leaves" if t == WildGen.T_LEAVES else "sfx_step_grass")


func _use(o: WildObject) -> void:
	if not is_instance_valid(o) or _leaving:
		return
	var r: Dictionary
	match o.kind:
		"fruit_tree":
			r = Forage.shake_tree(GameState.data, map, o.id)
		"bush", "ground":
			r = Forage.pick(GameState.data, map, o.id)
		"exit":
			_exit()
			return
		_:
			return
	if not bool(r.get("ok", false)):
		o.nudge()
		var reason := String(r.get("reason", ""))
		Audio.play_sfx("sfx_bag_full" if reason == "UI_BAG_FULL" else "ui_error")
		if reason != "":
			Fx.bubble(view.fx, _top(o), tr(reason))
		return
	o.pop()
	var n := _count(r.get("items", []))
	if o.kind == "fruit_tree":
		granny.act("shake")
		camera.shake(2, 0.25)
		Fx.leaf_burst(view.fx, o.position + Vector2(0, -28))
		Fx.fruit_to_bag(view.fx, o.position + Vector2(0, -28), o.position.y, granny, o.color, n)
		Audio.play_sfx("sfx_tree_shake")
	else:
		granny.act("pick")
		Audio.play_sfx("sfx_bush_rustle" if o.kind == "bush" else "sfx_pick")
	Audio.play_sfx("sfx_bag_add")
	if n > 0:
		Fx.bubble(view.fx, _top(o), "+%d" % n, 0.6)
	var found: Array = r.get("new", [])
	if not found.is_empty():
		var v: Dictionary = GameState.data.varieties.get(String(found[0]), {})
		Hud.toast("WILD_NEW_VARIETY", [String(v.get("name", found[0]))])
		Audio.play_sfx("sfx_sparkle")
	GameState.notify(PackedStringArray(["energy", "bag", "wild_today", "found_varieties", "stats"]))
	_refresh()


## Pulls today's progress (shaken trees, collected pickups) from Forage into the view.
func _refresh() -> void:
	view.apply_visible(Forage.visible_map(GameState.data, map))


func _walkable(cell: Vector2i) -> bool:
	return not view.blocks(cell) and WildGen.is_walkable(map, cell)


## One tile into the forest from the entrance, or the nearest free tile.
func _spawn_cell(entrance: Vector2i) -> Vector2i:
	var size := Vector2i(int(map.w), int(map.h))
	var seen := {entrance: true}
	var queue: Array[Vector2i] = [entrance + Vector2i.UP, entrance]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if not Rect2i(Vector2i.ZERO, size).has_point(c):
			continue
		if _walkable(c):
			return c
		for d in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return entrance


func _exit() -> void:
	if _leaving:
		return
	_leaving = true
	if granny != null:
		granny.input_enabled = false
		granny.stop()
	Audio.stop_ambient("amb_forest")
	Router.goto("garden" if Router.exists("garden") else "title")


static func _top(o: WildObject) -> Vector2:
	var r := o.hit_rect()
	return r.position + Vector2(r.size.x * 0.5, 0)


static func _count(items: Variant) -> int:
	if typeof(items) != TYPE_ARRAY:
		return 0
	var n := 0
	for it in items:
		n += int(it.get("count", 1)) if typeof(it) == TYPE_DICTIONARY else 1
	return n
