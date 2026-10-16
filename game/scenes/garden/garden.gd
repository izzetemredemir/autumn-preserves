extends Node2D
## Garden scene (GD-GARDEN, spec §5, §7.5, §8.1): the hub between the house, the wild and town. A fixed,
## hand-placed one-screen map (garden_layout.gd) that Granny walks. Rules live in Garden/Forage; this scene
## draws, walks Granny and answers every action (motion, sound, bubble or toast).
## Router.params: "from" ("wild" | "town" | else the house door) picks where Granny appears (the scene also
## remembers which exit she left by); "seed" only when no game is running (scene run alone -> start_temp).

const Fx := preload("res://scenes/wild/wild_fx.gd")
const Layout := preload("res://scenes/garden/garden_layout.gd")
const PlantMenu := preload("res://scenes/garden/plant_menu.gd")
const GRANNY := preload("res://player/granny.tscn")
const RETURN_META := &"garden_return"  ## on the root window: the exit Granny left by, for her way back
const BIOME := "forest"  ## the gate goes straight here until a second wild opens (vineyard key, rubber boots)
const C_HUSK := Color("b7b768")  ## olive_300
const FOREST_DB := -8.0  ## forest ambience in the background here; the wild plays it full

var granny: Granny
var spots: Array[GardenSpot] = []
var menu: Node  ## the open plant menu, or null
var cat: Cat  ## Granny's cat (P2-CAT): naps at today's spot, wanders a little, purrs when petted
var _last_pet_line := 0
var _blocked := {}
var _leaving := false

@onready var ground: TileMapLayer = $Ground
@onready var objects: Node2D = $Objects
@onready var fx: Node2D = $Fx
@onready var camera: FollowCamera = $Camera


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_temp(int(Router.params.get("seed", 1)))
	Garden.ensure_beds(GameState.data)  # saves that bought the beds before they existed in the list
	_paint_ground()
	_build_spots()
	granny = GRANNY.instantiate()
	objects.add_child(granny)
	var spawn: Array = Layout.spawn(_came_from())
	granny.setup(Layout.size(), _walkable, spawn[0], spawn[1])
	granny.stepped.connect(_on_stepped)
	granny.interact_requested.connect(_on_interact)
	_build_cat()
	camera.target = granny
	camera.bounds = Rect2i(0, 0, Layout.W * Layout.TILE, Layout.VIEW_H)
	camera.snap()
	GameState.changed.connect(_on_state_changed)
	_refresh()
	Audio.play_music("mus_garden")
	Audio.play_ambient("amb_forest", 2.0, FOREST_DB)
	_update_rain_sound()


func _process(_delta: float) -> void:
	if granny == null:
		return
	cat.near_granny = CatRules.near(cat.cell, granny.current_cell())
	var facing: GardenSpot = null
	if not granny.is_moving() and menu == null and not _leaving:
		facing = spot_at_cell(granny.facing_cell())
	var todo := _todo_spot()
	var near_gate := _near_gate()
	for s in spots:
		s.highlighted = s == facing
		s.glow = s == todo
		if s.kind == "gate":
			s.set_open(near_gate)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse arrives as emulated touch (project: emulate_touch_from_mouse), so one handler serves both.
	if event is InputEventScreenTouch and event.pressed and granny != null and not _leaving and menu == null:
		get_viewport().set_input_as_handled()
		tap_world(get_canvas_transform().affine_inverse() * event.position)


## A tap/click at a world point: walk there, or go and use the thing under it.
func tap_world(p: Vector2) -> void:
	if cat.hit_rect().has_point(p):
		if not granny.approach(cat_cell(), _pet_cat):
			Fx.bubble(fx, cat.top(), tr("WILD_CANT_REACH"))
		return
	var s := spot_at_point(p)
	if s == null and Layout.HOUSE.has_point(Granny.point_to_cell(p)):
		s = find_spot("door")  # the whole cottage front leads to its door
	if s == null:
		granny.walk_to(Granny.point_to_cell(p))
		return
	if s.kind == "gate" or s.kind == "gate_sign":
		_walk_out(Layout.GATE)
	elif not granny.approach(_nearest_cell(s), _use.bind(s)):
		Fx.bubble(fx, s.top(), tr("WILD_CANT_REACH"))


func find_spot(kind: String, index := -1) -> GardenSpot:
	for s in spots:
		if s.kind == kind and (index < 0 or s.index == index):
			return s
	return null


func spot_at_cell(cell: Vector2i) -> GardenSpot:
	for s in spots:
		if s.usable() and cell in s.cells:
			return s
	return null


## The usable thing drawn front-most under a world point, or null.
func spot_at_point(p: Vector2) -> GardenSpot:
	var best: GardenSpot = null
	for s in spots:
		if s.usable() and s.hit_rect().has_point(p) and (best == null or s.position.y > best.position.y):
			best = s
	return best


func _on_interact(cell: Vector2i) -> void:
	if _leaving or menu != null:
		return
	if cell == cat_cell():
		_pet_cat()
		return
	var s := spot_at_cell(cell)
	if s != null:
		_use(s)


func _on_stepped(cell: Vector2i) -> void:
	if Layout.is_gate(cell):
		_go_wild()
	elif Layout.is_road_exit(cell):
		_go_town()
	else:
		Audio.play_sfx("sfx_step_leaves" if Layout.ground(cell) == Layout.T_LEAVES else "sfx_step_grass")


func _use(s: GardenSpot) -> void:
	if not is_instance_valid(s) or _leaving or menu != null:
		return
	match s.kind:
		"tree":
			_shake(s)
		"bed":
			_bed(s)
		"compost":
			var g: Dictionary = GameState.data.garden
			Audio.play_sfx("sfx_bush_rustle")
			s.pop()
			Fx.bubble(fx, s.top(), tr("GARDEN_COMPOST") % [int(g.compost), _compost_per(), int(g.fertilizer)], 2.0)
		"mailbox":
			_mailbox(s)
		"door":
			_enter_house()
		"gate", "gate_sign":
			_go_wild()
		"town_sign":
			_go_town()


func _shake(s: GardenSpot) -> void:
	var r := Garden.shake_tree(GameState.data, s.index)
	if not bool(r.get("ok", false)):
		_fail(s, String(r.get("reason", "")))
		if r.get("reason", "") == "UI_TREE_EMPTY":
			Fx.bubble(fx, s.top(), _refill_text(s.refill_in), 1.6)
		return
	var n := _count(r.get("items", []))
	s.pop()
	granny.act("shake")
	camera.shake(2, 0.25)
	Fx.leaf_burst(fx, s.canopy(), 14)
	Fx.fruit_to_bag(fx, s.canopy(), s.position.y, granny, s.color, n)
	Audio.play_sfx("sfx_tree_shake")
	Audio.play_sfx("sfx_fruit_drop")
	Audio.play_sfx("sfx_bag_add")
	Fx.bubble(fx, s.top(), "+%d" % n, 0.6)
	GameState.notify(PackedStringArray(["energy", "bag", "garden"]))


func _bed(s: GardenSpot) -> void:
	var bed: Dictionary = GameState.data.garden.beds[s.index]
	if String(bed.crop) == "":
		_open_menu(s)
	elif int(bed.days_left) > 0:
		Audio.play_ui("ui_click")
		s.pop()
		var days := int(bed.days_left)
		Fx.bubble(fx, s.top(), tr("GARDEN_BED_TOMORROW") if days == 1 else tr("GARDEN_BED_DAYS") % days)
	else:
		_harvest(s)


func _open_menu(s: GardenSpot) -> void:
	var options := _seed_options()
	if options.is_empty():
		s.nudge()
		Audio.play_sfx("ui_error")
		Fx.bubble(fx, s.top(), tr("GARDEN_NO_SEEDS"), 1.8)
		return
	Audio.play_ui("ui_click")
	granny.input_enabled = false
	var m := PlantMenu.new()
	menu = m
	add_child(m)
	m.chosen.connect(_plant.bind(s))
	m.closed.connect(_on_menu_closed)
	m.open(options, int(GameState.data.garden.fertilizer))


func _on_menu_closed() -> void:
	menu = null
	if granny != null and not _leaving:
		granny.input_enabled = true
	_refresh()


## The letters overlay (P1-LETTERS) when any letter has come; a bubble while the box has never had one.
func _mailbox(s: GardenSpot) -> void:
	s.pop()
	var letters: Variant = GameState.data.get("letters")
	if typeof(letters) != TYPE_DICTIONARY or letters.get("inbox", []).is_empty():
		Audio.play_ui("ui_click")
		Fx.bubble(fx, s.top(), tr("GARDEN_NO_MAIL"))
		return
	var ui := LettersUI.open()
	if ui == null:
		return
	granny.input_enabled = false
	granny.stop()
	menu = ui
	ui.closed.connect(_on_menu_closed)


func _plant(crop: String, use_fertilizer: bool, s: GardenSpot) -> void:
	var r := Garden.plant(GameState.data, s.index, crop, use_fertilizer)
	if not bool(r.get("ok", false)):
		_fail(s, String(r.get("reason", "")))
		return
	s.pop()
	granny.act("pick")
	Audio.play_sfx("sfx_pick")
	Fx.bubble(fx, s.top(), tr("GARDEN_PLANTED") % int(r.get("days_left", 0)), 1.4)
	GameState.notify(PackedStringArray(["energy", "garden", "cupboard"]))


func _harvest(s: GardenSpot) -> void:
	var color := s.color
	var r := Garden.harvest(GameState.data, s.index)
	if not bool(r.get("ok", false)):
		_fail(s, String(r.get("reason", "")))
		return
	var n := _count(r.get("items", []))
	s.pop()
	granny.act("pick")
	Fx.fruit_to_bag(fx, s.position + Vector2(0, -12), s.position.y, granny, color, n)
	Audio.play_sfx("sfx_pick")
	Audio.play_sfx("sfx_bag_add")
	Fx.bubble(fx, s.top(), "+%d" % n, 0.6)
	GameState.notify(PackedStringArray(["energy", "bag", "garden"]))


## Rule said no: wiggle, a sound, and the reason as a toast.
func _fail(s: GardenSpot, reason: String) -> void:
	s.nudge()
	Audio.play_sfx("sfx_bag_full" if reason == "UI_BAG_FULL" else "ui_error")
	if reason != "":
		Hud.toast(reason)


func _enter_house() -> void:
	if not _can_leave():
		return
	Forage.empty_bag_to_inbox(GameState.data)
	GameState.notify(PackedStringArray(["bag", "inbox"]))
	Audio.play_sfx("sfx_door_open")
	_stop_ambient()
	_leave("kitchen", {}, "door")


## The gate: straight to the forest while it is the only open wild, else the "where to today?" card (BIOMES).
func _go_wild() -> void:
	if not _can_leave() or menu != null:
		return
	var open_count := 0
	for c in WildGen.biome_choices(GameState.data):
		if bool(c.open):
			open_count += 1
	if open_count <= 1:
		_go_biome(BIOME)
		return
	Audio.play_ui("ui_click")
	granny.input_enabled = false
	var p := BiomePicker.new()
	menu = p
	add_child(p)
	p.chosen.connect(_go_biome)
	p.closed.connect(_on_menu_closed)
	p.open(GameState.data)


func _go_biome(biome: String) -> void:
	_stop_ambient()
	_leave("wild", {"biome": biome, "seed": int(GameState.data.save_seed)}, "wild")


func _go_town() -> void:
	if not _can_leave():
		return
	_stop_ambient()
	_leave("town", {}, "town")


func _can_leave() -> bool:
	return not _leaving and not Transition.is_busy()


func _leave(id: String, params: Dictionary, back_at: String) -> void:
	_leaving = true
	granny.input_enabled = false
	granny.stop()
	get_tree().root.set_meta(RETURN_META, back_at)
	Transition.go(id, params)


## Walks onto the nearest exit cell; stepping on it leaves (_on_stepped).
func _walk_out(exits: Array) -> void:
	var best := Vector2i(-1, -1)
	var best_len := 1 << 30
	for c in exits:
		var p := granny.find_path(granny.dest_cell(), c)
		if not p.is_empty() and p.size() < best_len:
			best = c
			best_len = p.size()
	if best.x >= 0:
		granny.walk_to(best)


## Every exit fades the garden's ambience (the wild starts its own forest sound at full level).
func _stop_ambient() -> void:
	Audio.stop_ambient("amb_rain")
	Audio.stop_ambient("amb_forest")


func _update_rain_sound() -> void:
	if String(GameState.data.get("weather", "sunny")) == "rainy":
		Audio.play_ambient("amb_rain")
	else:
		Audio.stop_ambient("amb_rain")


func _came_from() -> String:
	var root := get_tree().root
	var from := String(Router.params.get("from", ""))
	if root.has_meta(RETURN_META):
		if from == "":
			from = String(root.get_meta(RETURN_META))
		root.remove_meta(RETURN_META)
	return from


func _paint_ground() -> void:
	ground.tile_set = WildMapView.tileset()
	for y in range(-Layout.MARGIN.y, Layout.H + Layout.MARGIN.y):
		for x in range(-Layout.MARGIN.x, Layout.W + Layout.MARGIN.x):
			var c := Vector2i(x, y)
			ground.set_cell(c, 0, WildMapView._atlas_for(Layout.ground(c), x, y))


func _build_spots() -> void:
	var g: Dictionary = GameState.data.garden
	var house: Array = []
	for y in range(Layout.HOUSE.position.y, Layout.HOUSE.end.y):
		for x in range(Layout.HOUSE.position.x, Layout.HOUSE.end.x):
			house.append(Vector2i(x, y))
	_add("house", -1, house)
	_add("door", -1, Layout.DOOR)
	_add("mailbox", -1, [Layout.MAILBOX])
	_add("compost", -1, [Layout.COMPOST])
	for i in g.trees.size():
		_add("tree", i, [Layout.tree_cell(String(g.trees[i].type), i)])
	for i in mini(g.beds.size(), Layout.BEDS.size()):
		_add("bed", i, Layout.bed_cells(i))
	_add("gate", -1, Layout.GATE)
	_add("gate_sign", -1, [Layout.GATE_SIGN])
	_add("town_sign", -1, [Layout.TOWN_SIGN])


## The cat naps at today's spot (CatRules). Its cell is not walkable, so Granny can face it and pet it.
func _build_cat() -> void:
	var spot := CatRules.spot_for(int(GameState.data.save_seed), int(GameState.data.day))
	cat = Cat.new()
	objects.add_child(cat)
	cat.setup(Seeds.seed_for(int(GameState.data.save_seed), "cat_walk", int(GameState.data.day)), spot.cell)
	cat.wander_walkable = _cat_may_walk


func cat_cell() -> Vector2i:
	return cat.cell if cat != null else Vector2i(-1, -1)


func _cat_may_walk(c: Vector2i) -> bool:
	return _walkable(c) and c != granny.current_cell() and c != granny.dest_cell()


## Pets the cat: purr, a heart and a short line. Nothing else happens (no needs, no reward).
func _pet_cat() -> void:
	if _leaving or menu != null or cat.is_purring():
		return
	cat.pet()
	Audio.play_sfx("sfx_cat_purr", false)
	var n := CatRules.pet_line(RandomNumberGenerator.new(), _last_pet_line)
	_last_pet_line = n
	var line := ""
	match n:
		1:
			line = tr("CAT_PET_1")
		2:
			line = tr("CAT_PET_2")
		3:
			line = tr("CAT_PET_3")
		_:
			line = tr("CAT_PET_4")
	Fx.bubble(fx, cat.top(), line, 1.8)


func _add(kind: String, index: int, cells: Array) -> void:
	var s := GardenSpot.new()
	s.setup(kind, index, cells)
	objects.add_child(s)
	spots.append(s)
	if s.blocks():
		for c in s.cells:
			_blocked[c] = true


## Pulls the garden state into the spots (fruit, beds, compost, today's wild seed on the gate sign).
func _refresh() -> void:
	var d: Dictionary = GameState.data
	var g: Dictionary = d.garden
	var seeds: Dictionary = Data.shop().seeds
	for s in spots:
		match s.kind:
			"tree":
				var t: Dictionary = g.trees[s.index]
				s.set_tree(String(t.type), bool(t.fruit), int(t.refill_in), _tree_color(String(t.type), String(t.variety)))
			"bed":
				var b: Dictionary = g.beds[s.index]
				var crop := String(b.crop)
				s.set_bed(crop, int(b.days_left), int(seeds.get(crop, {}).get("grow_days", 1)), bool(b.fertilized),
					WildMapView.fruit_color(crop, String(b.variety), d.varieties))
			"compost":
				s.set_compost(int(g.compost), _compost_per(), int(g.fertilizer))
			"mailbox":
				s.set_mail(Letters.unread_count(d))
			"gate_sign":
				var wild_seed := Seeds.seed_for(int(d.save_seed), "wild:" + BIOME, int(d.day))
				s.set_label(tr("GARDEN_GATE_SIGN") % [tr("WILD_BIOME_FOREST"), wild_seed])
			"town_sign":
				s.set_label(tr("GARDEN_TO_TOWN"))


func _on_state_changed(_keys: PackedStringArray) -> void:
	if GameState.has_game():
		_refresh()
		_update_rain_sound()


## The thing Granny's To-Do step points at here: the step's own object, or the way to the step's scene.
func _todo_spot() -> GardenSpot:
	var step := GrannyTodo.current_step()
	if step == "":
		return null
	match String(TodoRules.SCENE_OF.get(step, "")):
		"garden":
			if step == "d1_shake":
				for s in spots:
					if s.kind == "tree" and s.tree_type == "apple":
						return s
		"kitchen", "pantry":
			return find_spot("door")
		"wild":
			return find_spot("gate")
		"town":
			return find_spot("town_sign")
	return null


## The gate swings open while Granny is within two steps of it, or walking to it.
func _near_gate() -> bool:
	for c in [granny.current_cell(), granny.dest_cell()]:
		for g in Layout.GATE:
			if maxi(absi(c.x - g.x), absi(c.y - g.y)) <= 2:
				return true
	return false


func _walkable(cell: Vector2i) -> bool:
	return Layout.is_open(cell) and not _blocked.has(cell) and cell != cat_cell()


func _nearest_cell(s: GardenSpot) -> Vector2i:
	var from := granny.dest_cell()
	var best: Vector2i = s.cells[0]
	for c in s.cells:
		if absi(c.x - from.x) + absi(c.y - from.y) < absi(best.x - from.x) + absi(best.y - from.y):
			best = c
	return best


func _seed_options() -> Array:
	var out: Array = []
	var cupboard: Dictionary = GameState.data.cupboard
	for crop in Data.shop().seeds:
		var n := int(cupboard.get("seed_" + String(crop), 0))
		if n > 0:
			out.append({"crop": String(crop), "count": n})
	return out


## Fruit colour on the tree; nuts hang in their green husks.
func _tree_color(type: String, variety: String) -> Color:
	if String(Data.ingredients().get(type, {}).get("group", "")) == "nut":
		return C_HUSK
	return WildMapView.fruit_color(type, variety, GameState.data.varieties)


func _refill_text(days: int) -> String:
	return tr("GARDEN_TREE_TOMORROW") if days <= 1 else tr("GARDEN_TREE_REFILL") % days


static func _compost_per() -> int:
	return int(Data.rules().garden.compost_per_fertilizer)


static func _count(items: Variant) -> int:
	if typeof(items) != TYPE_ARRAY:
		return 0
	var n := 0
	for it in items:
		n += int(it.get("count", 1)) if typeof(it) == TYPE_DICTIONARY else 1
	return n
