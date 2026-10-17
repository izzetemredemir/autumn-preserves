extends Node2D
## Wild scene (GD-WILD, spec §7.1): today's procedural forest, vineyard or creek. Rules live in WildGen/Forage; this
## scene only draws the map, walks Granny and shows feedback.
## Router.params: "biome" (default "forest"; BiomePicker sends the others); "seed" is used only when no game is
## running (test start). Before the map is made, the save gets its P1 varieties (VarietyGen.ensure_types: old saves).

const Fx := preload("res://scenes/wild/wild_fx.gd")
const GRANNY := preload("res://player/granny.tscn")
## Ambient loops per biome; ids without a file yet are skipped.
const AMBIENT := {"forest": ["amb_forest"], "vineyard": ["amb_forest"], "creek": ["amb_forest", "amb_creek"]}

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
		GameState.start_temp(int(Router.params.get("seed", Seeds.random_save_seed())))
	var s: Dictionary = GameState.data
	if not VarietyGen.ensure_types(s.varieties, int(s.save_seed)).is_empty():
		GameState.notify(PackedStringArray(["varieties"]))
	if not SpeciesGen.sync(s).is_empty():  # SPECIES-GEN: demo, festival and temp games too
		GameState.notify(PackedStringArray(["varieties"]))
	map = WildGen.generate(int(s.save_seed), int(s.day), biome, String(s.weather), s.varieties)
	SpeciesGen.add_pickups(map, int(s.save_seed), int(s.day))  # SPECIES-GEN: today's species, after every other item
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
	GuideArrow.attach(self, _guide_at)  # ONBOARD-GUIDE: arrow, Granny's hint, first-time key caps
	add_child(WildWeather.make(String(s.weather), granny))  # windy leaves / fog around Granny (P1 weather)
	CritterLayer.attach(view.objects, CritterRules.wild(map, int(s.save_seed), int(s.day), String(s.weather)), granny,
		String(s.weather), map)  # WILD-LIFE: ambient critters
	seed_label.text = "%s %d" % [tr("UI_SEED"), int(map.seed)]
	(seed_label.get_parent() as Control).visible = GameSettings.show_seed()  # off by default: the grow overlay names it
	var grow := WorldGrow.open_if_due(self, map, biome)  # FIRST-60: today's map grows from the seed first
	if grow != null:
		granny.input_enabled = false
		grow.done.connect(func() -> void: granny.input_enabled = not _leaving)
	Audio.play_music("mus_forest")
	for id in _ambient():
		Audio.play_ambient(id)


func _process(_delta: float) -> void:
	if granny != null:
		view.set_highlight(view.object_at_cell(granny.facing_cell()) if not granny.is_moving() else null)
		view.set_near(granny.current_cell())


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
			Fx.bubble(view.fx, o.top(), tr("WILD_CANT_REACH"))
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
	if t == WildGen.T_LEAVES and Juice.rng().randf() < 0.45:  # FEEL: now and then a leaf kicks up
		Fx.kick_leaf(view.fx, granny.position, granny.facing)


func _use(o: WildObject) -> void:
	if not is_instance_valid(o) or _leaving:
		return
	GuideArrow.used(o.kind)
	var r: Dictionary
	match o.kind:
		"fruit_tree":
			r = Forage.shake_tree(GameState.data, map, o.id)
		"bush", "ground", "hive":
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
			Fx.bubble(view.fx, o.top(), tr(reason))
		return
	if o.kind != "fruit_tree":
		o.pop()  # trees wiggle in Fx.shake_tree
	_refresh()  # the tree turns bare and drops its tag before the bubble is placed over it
	var n := _count(r.get("items", []))
	if o.kind == "hive":  # honey goes straight to the cupboard, not the bag
		granny.act("pick")
		Audio.play_sfx("sfx_bush_rustle")
		Audio.play_sfx("sfx_sparkle")
		Fx.bubble(view.fx, o.top(), "+%d" % n, 0.6)
		Hud.toast("WILD_HONEY", [n])
		GameState.notify(PackedStringArray(["energy", "cupboard", "wild_today", "stats"]))
		return
	if o.kind == "fruit_tree":
		granny.act("shake")
		Fx.shake_tree(view.fx, o, o.canopy(), o.position.y, granny, o.color, n, camera,
			WildObject.icon_for(String(o.info.get("type", ""))))
		Audio.play_sfx("sfx_tree_shake")
	else:
		granny.act("pick")
		var from := o.position if o.kind == "ground" else o.canopy() + Vector2(0, 8)
		Fx.item_to_bag(view.fx, from, WildObject.icon_for(String(o.info.get("type", ""))), o.color)
		Audio.play_sfx("sfx_bush_rustle" if o.kind == "bush" else "sfx_pick")
	Audio.play_sfx("sfx_bag_add")
	if n > 0:
		Fx.bubble(view.fx, o.top(), "+%d" % n, 0.6)
	var found: Array = r.get("new", [])
	if SpeciesGen.mark_seen(GameState.data, String(o.info.get("type", ""))):  # SPECIES-GEN: first meeting
		_species_card(String(o.info.type))
	elif not found.is_empty():
		var v: Dictionary = GameState.data.varieties.get(String(found[0]), {})
		Hud.toast("WILD_NEW_VARIETY", [VarietyGen.display_name(v) if not v.is_empty() else String(found[0])])
		Audio.play_sfx("sfx_sparkle")
	GameState.notify(PackedStringArray(["energy", "bag", "wild_today", "found_varieties", "species_seen", "stats"]))


## SPECIES-GEN: the "New species!" card; Granny waits while it is open.
func _species_card(type: String) -> void:
	granny.input_enabled = false
	SpeciesCard.open(self, type).closed.connect(func() -> void: granny.input_enabled = not _leaving)


## ONBOARD-GUIDE: what Granny's guide asks the wild (GuideArrow header): the festival's rare tree, the nearest
## mushroom on day 2, else the way out; her body; the thing she stands at while it has something to take.
func _guide_at(what: String) -> Variant:
	if granny == null or _leaving:
		return null
	match what:
		"granny":
			return Rect2(granny.global_position + Vector2(-8, -32), Vector2(16, 32))
		"bubble", "d2_forest":
			return null
		"near":
			if granny.is_moving():
				return {}
			var o := view.object_at_cell(granny.facing_cell())
			if o == null:
				o = view.object_at_cell(granny.current_cell())
			return {"kind": o.kind, "at": view.objects.to_global(o.top())} if o != null and o.has_take() else {}
		"d2_mushroom":
			var m := _guide_mushroom()
			return view.objects.to_global(m.top()) if m != null else null
		"f_shake":
			var f := TodoRules.festival(GameState.data)
			if biome == String(f.get("biome", "forest")):
				var t := view.find("fruit_tree", int(f.get("tree", -1)))
				return view.objects.to_global(t.top()) if t != null and t.has_take() else null
	for c in view.objects.get_children():
		if c is WildObject and (c as WildObject).kind == "exit":
			return view.objects.to_global((c as WildObject).top())
	return null


## The mushroom still lying on the ground nearest to Granny, or null.
func _guide_mushroom() -> WildObject:
	var best: WildObject = null
	var at := granny.current_cell()
	var ingredients := Data.ingredients()
	for c in view.objects.get_children():
		var o := c as WildObject
		if o == null or o.kind != "ground" or not o.has_take():
			continue
		if String(ingredients.get(String(o.info.get("type", "")), {}).get("group", "")) != "mushroom":
			continue
		if best == null or (o.cell - at).length_squared() < (best.cell - at).length_squared():
			best = o
	return best


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
	for id in _ambient():
		Audio.stop_ambient(id)
	Router.goto("garden" if Router.exists("garden") else "title")


func _ambient() -> Array:
	return (AMBIENT.get(biome, ["amb_forest"]) as Array).filter(
		func(id: String) -> bool: return ResourceLoader.exists("res://assets/audio/ambient/%s.ogg" % id))


static func _count(items: Variant) -> int:
	if typeof(items) != TYPE_ARRAY:
		return 0
	var n := 0
	for it in items:
		n += int(it.get("count", 1)) if typeof(it) == TYPE_DICTIONARY else 1
	return n
