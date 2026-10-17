extends Node2D
## Garden scene (GD-GARDEN, spec §5, §7.5, §8.1): the hub between the house, the wild and town. A fixed,
## hand-placed one-screen map (garden_layout.gd) that Granny walks. Rules live in Garden/Forage; this scene
## draws, walks Granny and answers every action (motion, sound, bubble or toast).
## Router.params: "from" ("wild" | "town" | else the house door) picks where Granny appears (the scene also
## remembers which exit she left by); "seed" only when no game is running (scene run alone -> start_temp).
## GARDEN-LIFE: the props of garden_props.json (Walter's truck, the hens and their run, hives, clothesline, scarecrow,
## bench) stand y-sorted with Granny and block their cells; clicking one walks her to it and she says a line. Hens,
## bees, crows, butterflies, squirrels, chimney smoke and leaf piles are cosmetic and never saved.

const Fx := preload("res://scenes/wild/wild_fx.gd")
const Layout := preload("res://scenes/garden/garden_layout.gd")
const Props := preload("res://scenes/garden/garden_props.gd")
const Leaves := preload("res://actors/garden_life/garden_leaves.gd")
const PlantMenu := preload("res://scenes/garden/plant_menu.gd")
const GRANNY := preload("res://player/granny.tscn")
const RETURN_META := &"garden_return"  ## on the root window: the exit Granny left by, for her way back
const ROOSTER_META := &"garden_rooster_day"  ## on the root window: the day the rooster last crowed (not saved)
const BIOME := "forest"  ## the gate goes straight here until a second wild opens (vineyard key, rubber boots)
const C_HUSK := Color("b7b768")  ## olive_300
const FOREST_DB := -8.0  ## forest ambience in the background here; the wild plays it full
## Props Granny can use, by kind ("hive_2" -> "hive"; the run and its fence count as "coop"), with their line count.
const USABLE := {"truck": 4, "coop": 3, "hive": 0, "scarecrow": 3, "bench": 3, "clothesline": 3}
const HUD_H := 32  ## px under the screen's top edge that the HUD covers: bubbles stay below it
const HENS_NEAR_PX := 18.0  ## Granny's feet this close to the run: the hens scatter
const HIVE_NEAR := 2  ## cells (Chebyshev) from a hive: the bees buzz
const CLUCK_SEC := Vector2(10.0, 24.0)
const BEES_PER_HIVE := 4
const BEE_FLOWER_PX := 80.0
const LEAF_PILE_MS := 900  ## a pile bursts at most this often

var granny: Granny
var spots: Array[GardenSpot] = []
var menu: Node  ## the open plant menu, or null
var cat: Cat  ## Granny's cat (P2-CAT): naps at today's spot, wanders a little, purrs when petted
var props: Array[GardenProp] = []
var hens: Array[GardenHen] = []
var crows: Array[GardenCrow] = []
var butterflies: Array[GardenButterfly] = []
var _props_data: Dictionary
var _prop_cells := {}  ## cell -> prop id (the run's cells -> "coop")
var _last_pet_line := 0
var _last_line := {}  ## prop kind -> last line number said
var _blocked := {}
var _leaving := false
var _near_run := false
var _near_hive := false
var _cluck_in := 12.0
var _leaf_piles := {}  ## cell -> ticks msec of its last burst
var _rng := RandomNumberGenerator.new()  ## visual randomness only (which line, which hen clucks)

@onready var ground: TileMapLayer = $Ground
@onready var backdrop: Node2D = $Backdrop
@onready var objects: Node2D = $Objects
@onready var fx: Node2D = $Fx
@onready var camera: FollowCamera = $Camera


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_temp(int(Router.params.get("seed", 1)))
	Garden.ensure_beds(GameState.data)  # saves that bought the beds before they existed in the list
	_rng.randomize()
	_paint_ground()
	_build_spots()
	_build_props()
	granny = GRANNY.instantiate()
	objects.add_child(granny)
	var spawn: Array = Layout.spawn(_came_from())
	granny.setup(Layout.size(), _walkable, spawn[0], spawn[1])
	granny.stepped.connect(_on_stepped)
	granny.interact_requested.connect(_on_interact)
	_build_cat()
	_build_critters()
	_build_life()
	camera.target = granny
	camera.bounds = Rect2i(0, 0, Layout.W * Layout.TILE, Layout.VIEW_H)
	camera.snap()
	GameState.changed.connect(_on_state_changed)
	_refresh()
	Audio.play_music("mus_garden")
	Audio.play_ambient("amb_forest", 2.0, FOREST_DB)
	_update_rain_sound()


func _process(delta: float) -> void:
	if granny == null:
		return
	cat.near_granny = CatRules.near(cat.cell, granny.current_cell())
	var facing: GardenSpot = null
	var facing_prop: GardenProp = null
	if not granny.is_moving() and menu == null and not _leaving:
		facing = spot_at_cell(granny.facing_cell())
		if facing == null and granny.facing_cell() != cat_cell():  # the cat on the hood or bench comes first
			facing_prop = prop_at_cell(granny.facing_cell())
	var todo := _todo_spot()
	var near_gate := _near_gate()
	for s in spots:
		s.highlighted = s == facing
		s.glow = s == todo
		if s.kind == "gate":
			s.set_open(near_gate)
	for p in props:
		p.highlighted = facing_prop != null and use_kind(p) == use_kind(facing_prop)
	_tick_life(delta)


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
	var pr := prop_at_point(p)
	if pr != null and (s == null or pr.position.y > s.position.y):
		approach_prop(pr)
		return
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
		return
	var p := prop_at_cell(cell)
	if p != null:
		use_prop(p)


func _on_stepped(cell: Vector2i) -> void:
	if Layout.is_gate(cell):
		_go_wild()
	elif Layout.is_road_exit(cell):
		_go_town()
	else:
		Audio.play_sfx("sfx_step_leaves" if Layout.ground(cell) == Layout.T_LEAVES else "sfx_step_grass")
		_leaf_pile(cell)


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
## GARDEN-LIFE: on a prop (the truck hood, the bench) it sits at the json's feet point, drawn over the prop (its feet
## are above the prop's sort line), and stays put.
func _build_cat() -> void:
	var spot := CatRules.spot_for(int(GameState.data.save_seed), int(GameState.data.day))
	var cell: Vector2i = spot.cell
	var seat := Props.cat_spot(_props_data, String(spot.id)) if spot.has("prop") else {}
	if not seat.is_empty():
		cell = seat.cell
	cat = Cat.new()
	objects.add_child(cat)
	cat.setup(Seeds.seed_for(int(GameState.data.save_seed), "cat_walk", int(GameState.data.day)), cell)
	if not seat.is_empty():
		cat.position = Vector2(seat.px)
		cat.z_index = 1
	else:
		cat.wander_walkable = _cat_may_walk


## WILD-LIFE: a robin on the fence and a sparrow or two on the lawn; GARDEN-LIFE: squirrels at the apple and walnut
## trees, late butterflies over the flowers (cosmetic, not saved). Butterflies are GardenButterfly, the rest Critter.
func _build_critters() -> void:
	var s: Dictionary = GameState.data
	var weather := String(s.get("weather", "sunny"))
	var lawn := func(c: Vector2i) -> bool: return _walkable(c) and not spot_blocks(c)
	var list: Array = []
	for p: Dictionary in CritterRules.garden(int(s.save_seed), int(s.day), weather, lawn):
		if p.kind == "butterfly":
			var b := GardenButterfly.new()
			fx.add_child(b)
			b.setup(p, hash([butterflies.size(), int(s.day)]))
			butterflies.append(b)
		else:
			list.append(p)
	CritterLayer.attach(objects, list, granny, weather)


## GARDEN-LIFE: the props, y-sorted with Granny (or under everything with "z": "back": the truck's gravel, the run's
## back fence); their cells block her. The truck bed carries the calendar week's load.
func _build_props() -> void:
	_props_data = Props.data()
	var d: Dictionary = GameState.data
	var weather := String(d.get("weather", "sunny"))
	for p: Dictionary in _props_data.props:
		var n := GardenProp.new()
		(backdrop if p.z == "back" else objects).add_child(n)
		n.setup(p, weather)
		props.append(n)
		if n.kind == "truck" and _props_data.truck_bed.x >= 0:
			n.set_load(GardenLifeRules.truck_load(int(d.day)), _props_data.truck_bed)
	_prop_cells = Props.blocked(_props_data)
	for c in _prop_cells:
		_blocked[c] = true
	for dec in Layout.DECOR:
		if dec[1] == Layout.D_LEAVES and not _prop_cells.has(dec[0]):
			_leaf_piles[dec[0]] = -LEAF_PILE_MS


## GARDEN-LIFE: hens and the rooster in the run, crows on their perches (scarecrow, truck roof, hen house ridge), bees
## at the hives (not in rain), chimney smoke where it shows.
func _build_life() -> void:
	var d: Dictionary = GameState.data
	var day := int(d.day)
	var weather := String(d.get("weather", "sunny"))
	var run := Props.run_px(_props_data)
	if run.has_area():
		var coop := _footprint(Props.prop(_props_data, "coop"))
		var area := GardenLifeRules.area(run, coop, weather == "rainy")
		var avoid: Array = [coop] if coop.has_area() else []
		var i := 0
		for h: Dictionary in GardenLifeRules.flock():
			var hen := GardenHen.new()
			objects.add_child(hen)
			hen.setup(String(h.kind), int(h.variant), GardenLifeRules.route(int(d.save_seed), day, i, area, avoid), area,
				avoid, hash([i, day]))
			hens.append(hen)
			i += 1
	var i := 0
	for on in _props_data.perches:  # crows on the scarecrow, the truck roof, the hen house ridge
		var under := find_prop(String(on))
		if under == null:
			continue
		for perch: Vector2i in _props_data.perches[on]:
			var c := GardenCrow.new()
			objects.add_child(c)
			c.setup(perch, int(under.position.y), hash([i, day, "crow"]))
			crows.append(c)
			i += 1
	if weather != "rainy":
		for p in props:
			if p.kind == "hive":
				var r := p.hit_rect()
				var door := Vector2(roundf(r.get_center().x), r.end.y + 3)  # bees hover in front of the hive
				var bees := GardenBees.new()
				fx.add_child(bees)
				bees.setup(door, _flowers_near(door), BEES_PER_HIVE, hash([p.id, day]))
	# chimney smoke only where it can be seen: in the 480x270 view the chimney sits under the HUD bar (taller windows
	# show it)
	var view_top := minf(0.0, (Layout.VIEW_H - get_viewport_rect().size.y) * 0.5)  # FollowCamera centres a taller view
	if _props_data.chimney.x >= 0 and _props_data.chimney.y - GardenSmoke.RISE * 0.5 > view_top + HUD_H:
		var smoke := GardenSmoke.new()
		fx.add_child(smoke)
		smoke.setup(_props_data.chimney, weather == "windy")
	var root := get_tree().root
	if int(root.get_meta(ROOSTER_META, -1)) != day and not hens.is_empty():
		root.set_meta(ROOSTER_META, day)
		get_tree().create_timer(1.0).timeout.connect(_rooster_crow)


## The rooster's morning call, once a day when Granny first steps out.
func _rooster_crow() -> void:
	if not is_instance_valid(self) or hens.is_empty() or _leaving:
		return
	for h in hens:
		if h.kind == "rooster":
			h.crow()
	Audio.play_sfx("sfx_rooster", false)


## Per frame: hens scatter as Granny comes to the run, clucks now and then, crows take off, the hives buzz as she
## passes, butterflies keep their distance.
func _tick_life(delta: float) -> void:
	var feet := granny.position
	if not hens.is_empty():
		var near := Rect2(Props.run_px(_props_data)).grow(HENS_NEAR_PX).has_point(feet)
		if near and not _near_run:
			scatter_hens()
		_near_run = near
		_cluck_in -= delta
		if _cluck_in <= 0.0:
			_cluck_in = _rng.randf_range(CLUCK_SEC.x, CLUCK_SEC.y)
			hens[_rng.randi_range(0, hens.size() - 1)].cluck()
			Audio.play_sfx("sfx_hen_cluck")
	var took_off := false
	for c in crows:
		took_off = c.tick(delta, feet) or took_off
	if took_off:
		Audio.play_sfx("sfx_crow_caw")
	for b in butterflies:
		b.tick(delta, feet)
	var near_hive := false
	if String(GameState.data.get("weather", "sunny")) != "rainy":
		var g := granny.current_cell()
		for p in props:
			if p.kind == "hive":
				for c: Vector2i in p.info.blocked:
					near_hive = near_hive or maxi(absi(c.x - g.x), absi(c.y - g.y)) <= HIVE_NEAR
	if near_hive and not _near_hive:
		Audio.play_sfx("sfx_bees_buzz", false)
	_near_hive = near_hive


## Every hen flaps away from Granny inside the run (and one clucks).
func scatter_hens() -> void:
	for h in hens:
		h.scatter(granny.position)
	if not hens.is_empty():
		Audio.play_sfx("sfx_hen_cluck")


## Granny walks through a leaf pile: a few leaves fly up.
func _leaf_pile(cell: Vector2i) -> void:
	if not _leaf_piles.has(cell):
		return
	var now := Time.get_ticks_msec()
	if now - int(_leaf_piles[cell]) < LEAF_PILE_MS:
		return
	_leaf_piles[cell] = now
	Leaves.burst(fx, Vector2(cell.x * Layout.TILE + 8, (cell.y + 1) * Layout.TILE - 3), 6)


func find_prop(id: String) -> GardenProp:
	for p in props:
		if p.id == id:
			return p
	return null


## What using a prop does: "truck" | "coop" | "hive" | "scarecrow" | "bench" | "clothesline", or "" (others).
func use_kind(p: GardenProp) -> String:
	return use_kind_of(p.id)


## The usable prop standing on `cell` (the run's cells are the hens'), or null.
func prop_at_cell(cell: Vector2i) -> GardenProp:
	if not _prop_cells.has(cell):
		return null
	var id := String(_prop_cells[cell])
	for p in props:
		if (p.id == id or (Props.group(id) == "coop" and use_kind(p) == "coop")) and use_kind(p) != "":
			return p
	return null


## The usable prop drawn front-most under a garden point, or null.
func prop_at_point(at: Vector2) -> GardenProp:
	var best: GardenProp = null
	for p in props:
		if use_kind(p) != "" and p.hit_rect().has_point(at) and (best == null or p.position.y > best.position.y):
			best = p
	return best


## Walks Granny to the prop (to the side of one of its cells next to an interact cell, nearest first), then uses it.
func approach_prop(p: GardenProp) -> void:
	var kind := use_kind(p)
	var cells: Array[Vector2i] = []
	var spots_to: Array[Vector2i] = []
	for c in _prop_cells:
		var q := prop_at_cell(c)
		if q != null and use_kind(q) == kind:
			cells.append(c)
	for d: Dictionary in _props_data.props:
		if use_kind_of(String(d.id)) == kind:
			spots_to.append_array(d.interact)
	var from := granny.dest_cell()
	var best := Vector2i(-1, -1)
	var best_len := 1 << 30
	for ic in spots_to:
		var path := granny.find_path(from, ic)
		if path.is_empty() or path.size() >= best_len:
			continue
		for dir: Vector2i in Granny.DIRS:
			if (ic + dir) in cells:
				best = ic + dir
				best_len = path.size()
				break
	if best.x < 0:  # no interact cell: any reachable side of its cells
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - from).length_squared() < (b - from).length_squared())
		for c in cells:
			if granny.approach(c, use_prop.bind(p)):
				return
		_say(tr("WILD_CANT_REACH"))
		return
	if not granny.approach(best, use_prop.bind(p)):
		_say(tr("WILD_CANT_REACH"))


func use_kind_of(id: String) -> String:
	if Props.group(id) == "coop":
		return "coop"
	var k := id.rstrip("0123456789").trim_suffix("_")
	return k if USABLE.has(k) else ""


## Granny uses a prop: a sound, a little squash and a line in her voice.
func use_prop(p: GardenProp) -> void:
	if not is_instance_valid(p) or _leaving or menu != null:
		return
	var kind := use_kind(p)
	if kind == "":
		return
	if kind != "coop":
		p.pop()
	match kind:
		"truck":
			Audio.play_sfx("sfx_truck_creak", false)
		"coop":
			scatter_hens()
		"hive":
			Audio.play_sfx("sfx_bees_buzz", false)
			_say(_hive_line(), _clear_of(kind))
			return
		"bench":
			Audio.play_ui("ui_click")
		"scarecrow":
			Audio.play_sfx("sfx_bush_rustle")
		"clothesline":
			Audio.play_sfx("sfx_bush_rustle")
	var n := GardenLifeRules.line(_rng, int(USABLE[kind]), int(_last_line.get(kind, 0)))
	_last_line[kind] = n
	_say(tr("GARDEN_%s_%d" % [("HENS" if kind == "coop" else kind.to_upper()), n]), _clear_of(kind))


## The area of every prop of a kind (the run and its hen house together), for the bubble to keep clear of.
func _clear_of(kind: String) -> Rect2:
	var r := Rect2()
	for p in props:
		if use_kind(p) == kind:
			r = p.hit_rect() if not r.has_area() else r.merge(p.hit_rect())
	return r


## The hives' line: when the next honey comes (rules: Garden.honey_day), or that the bees stay in on rainy days.
func _hive_line() -> String:
	var day := int(GameState.data.day)
	if String(GameState.data.get("weather", "sunny")) == "rainy":
		return tr("GARDEN_HIVES_RAIN")
	if Garden.honey_day(day):
		return tr("GARDEN_HIVES_TODAY")
	var n := Garden.days_to_honey(day)
	return tr("GARDEN_HIVES_TOMORROW") if n == 1 else tr("GARDEN_HIVES_DAYS") % n


## A paper bubble over Granny's head with her line (like Fx.bubble), kept on screen: where it would hide under the
## HUD or cover `keep_clear` (the thing she talks about) it goes under her feet instead.
func _say(text: String, keep_clear := Rect2(), seconds := 2.6) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PaperPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 50
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("50361e"))
	panel.add_child(label)
	fx.add_child(panel)
	var size := panel.get_combined_minimum_size()
	panel.size = size
	var view := get_canvas_transform().affine_inverse() * get_viewport_rect()
	var x := clampf(roundf(granny.position.x - size.x * 0.5), view.position.x + 2, view.end.x - 2 - size.x)
	var y := granny.position.y - 34 - size.y
	if y < view.position.y + HUD_H or (keep_clear.has_area() and keep_clear.intersects(Rect2(Vector2(x, y), size))):
		y = minf(granny.position.y + 6, view.end.y - 2 - size.y)
	panel.position = Vector2(x, roundf(y))
	panel.pivot_offset = Vector2(floori(size.x * 0.5), size.y)
	panel.scale = Vector2(0.6, 0.6)
	var t := panel.create_tween()
	t.tween_property(panel, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "position:y", panel.position.y - 4, 0.25)
	t.tween_interval(seconds)
	t.tween_callback(panel.queue_free)


## A prop's blocked cells as one rectangle in garden px (the hen house's footprint), or an empty rect.
func _footprint(p: Dictionary) -> Rect2i:
	var r := Rect2i()
	for c: Vector2i in p.get("blocked", []):
		var cell := Rect2i(c * Layout.TILE, Vector2i(Layout.TILE, Layout.TILE))
		r = cell if not r.has_area() else r.merge(cell)
	return r


## Flower clumps within BEE_FLOWER_PX of a hive door that no prop covers, in garden px.
func _flowers_near(door: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for dec in Layout.DECOR:
		var c: Vector2i = dec[0]
		if dec[1] in [Layout.D_FLOWERS_RED, Layout.D_FLOWERS_GOLD] and not _prop_cells.has(c):
			var at := Vector2(c.x * Layout.TILE + 8, c.y * Layout.TILE + 8)
			if at.distance_to(door) <= BEE_FLOWER_PX:
				out.append(at)
	return out


## A cell a garden thing (bed, sign, tree) stands on or reaches over, for the critters' sake.
func spot_blocks(c: Vector2i) -> bool:
	for sp in spots:
		if c in sp.cells:
			return true
	return false


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
