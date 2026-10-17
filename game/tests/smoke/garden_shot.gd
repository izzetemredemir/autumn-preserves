extends SceneTree
## Smoke drive (GD-GARDEN): the garden run alone on a throwaway game (GameState.start_temp), Granny's To-Do on.
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/garden_shot.gd
## Taps the apple tree (energy -3, bag +2..3), buys a cucumber seed and plants it in an empty bed through the
## plant menu, makes a letter arrive (mailbox flag up), ripens two beds for the shot, opens and closes the
## letters overlay from the mailbox, then taps the door and checks the bag went to the inbox and the kitchen opened.
## GARDEN-LIFE: checks the props block their cells, walks Granny to the truck (a line) and to the hens (they scatter).
## Saves user://shots/garden_start.png, garden_menu.png, garden.png, garden_letters.png, garden_rest.png,
## garden_truck.png, garden_hens.png.
## Exit code 1 on a failed check or timeout.
## Autoloads are reached through the root and scene scripts by path (SceneTree scripts can't name autoloads).

const SEED := 1
const TIMEOUT_FRAMES := 5400
const _props := preload("res://scenes/garden/garden_props.gd")
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
	_router.current = "garden"  # Granny's To-Do hides on scene "" (scenes run alone)
	_gs.start_temp(SEED)
	load("res://ui/tutorial/granny_todo.gd").ensure()
	_scene = (load("res://scenes/garden/garden.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	current_scene = _scene
	await _frames_wait(10)
	_shot("garden_start")

	# 1. shake the apple tree
	var d: Dictionary = _gs.data
	var energy := int(d.energy)
	var bag := _bag_count(d)
	var apple: Node = _tree("apple")
	_check(apple != null and bool(apple.get("glow")), "apple tree glows for the first To-Do step")
	_scene.tap_world(apple.hit_rect().get_center())
	await _until(func() -> bool: return int(_gs.data.energy) != energy)
	await _frames_wait(30)
	var got := _bag_count(_gs.data) - bag
	_check(int(_gs.data.energy) == energy - 3, "shake costs 3 energy (%d -> %d)" % [energy, int(_gs.data.energy)])
	_check(got >= 2 and got <= 3, "shake puts 2..3 fruit in the bag (got %d)" % got)

	# 2. buy a cucumber seed, plant it in the first empty bed
	var bought: Dictionary = load("res://sim/economy.gd").buy(_gs.data, "seed_cucumber")
	_check(bool(bought.ok), "bought a cucumber seed")
	var bed_i := -1
	for i in _gs.data.garden.beds.size():
		if String(_gs.data.garden.beds[i].crop) == "":
			bed_i = i
			break
	_check(bed_i >= 0, "an empty bed exists")
	energy = int(_gs.data.energy)
	var bed: Node = _scene.find_spot("bed", bed_i)
	_scene.tap_world(bed.hit_rect().get_center())
	await _until(func() -> bool: return _scene.get("menu") != null)
	await _frames_wait(5)
	_shot("garden_menu")
	_scene.get("menu").choose("cucumber")
	await _frames_wait(20)
	var planted: Dictionary = _gs.data.garden.beds[bed_i]
	_check(String(planted.crop) == "cucumber", "bed %d has a cucumber" % bed_i)
	_check(int(_gs.data.cupboard.get("seed_cucumber", 0)) == 0, "the seed left the cupboard")
	_check(int(_gs.data.energy) == energy - 1, "planting costs 1 energy")

	# 3. a letter arrives: the mailbox raises its flag; tapping it opens the letters overlay, reading lowers it
	var letters_rules: GDScript = load("res://sim/letters.gd")
	letters_rules.ensure(_gs.data)
	_gs.data.letters.next_day = int(_gs.data.day)
	letters_rules.night(_gs.data)
	_gs.notify(PackedStringArray(["letters"]))
	var mailbox: Node = _scene.find_spot("mailbox")
	_check(int(letters_rules.unread_count(_gs.data)) == 1, "one unread letter")
	_check(int(mailbox.get("unread")) == 1, "mailbox flag is up")
	# dress the shot (ART-GARDEN): ripe pepper and cucumber beds next to the new seed, a fertilized sprout,
	# a heaped compost bin with a sack of fertilizer
	var beds: Array = _gs.data.garden.beds
	beds[0] = {"crop": "pepper", "variety": "", "days_left": 0, "fertilized": false}
	beds[1] = {"crop": "cucumber", "variety": "", "days_left": 0, "fertilized": false}
	if beds.size() > 3 and bed_i != 3:
		beds[3] = {"crop": "pepper", "variety": "", "days_left": 2, "fertilized": true}
	_gs.data.garden.compost = 4
	_gs.data.garden.fertilizer = 1
	_gs.notify(PackedStringArray(["garden"]))
	await _frames_wait(40)
	_shot("garden")
	_scene.tap_world(mailbox.hit_rect().get_center())
	await _until(func() -> bool: return get_first_node_in_group("letters_ui") != null)
	await _frames_wait(10)
	_shot("garden_letters")
	_check(_scene.get("menu") != null, "the garden waits while the letters are open")
	get_first_node_in_group("letters_ui").close()
	await _frames_wait(5)
	_check(_scene.get("menu") == null, "letters closed, Granny walks again")
	_check(int(mailbox.get("unread")) == 0, "mailbox flag is down after reading")

	# 3b. GARDEN-LIFE: the props block their cells; Granny walks to Walter's truck (a line), then to the hens' run
	# (they scatter, a hen line); the garden at rest first
	for id in ["truck", "coop", "hive_1", "hive_2", "clothesline", "scarecrow", "bench"]:
		var pr: Node = _scene.find_prop(id)
		_check(pr != null, "prop %s stands in the garden" % id)
		for c: Vector2i in pr.get("info").blocked:
			_check(not bool(_scene._walkable(c)), "%s blocks %s" % [id, c])
	_check(_scene.get("hens").size() == 4, "three hens and a rooster")
	_check(_scene.get("crows").size() >= 2, "crows on the scarecrow")
	await _frames_wait(30)
	_shot("garden_rest")
	var truck: Node = _scene.find_prop("truck")
	_scene.tap_world(truck.hit_rect().get_center())
	await _until(func() -> bool: return _bubbles() > 0)
	await _frames_wait(20)
	_check(_scene.granny.current_cell() in _props.prop(_props.data(), "truck").interact or _scene.prop_at_cell(
		_scene.granny.facing_cell()) == truck, "Granny stands at the truck, facing it")
	_shot("garden_truck")
	await _until(func() -> bool: return _bubbles() == 0)
	_scene.tap_world(_scene.find_prop("coop").hit_rect().get_center())
	await _until(func() -> bool: return _scared() > 0)
	await _frames_wait(8)
	_check(_scared() >= 3, "the hens scatter as Granny comes to the run (%d)" % _scared())
	_shot("garden_hens")
	await _until(func() -> bool: return _bubbles() > 0)
	await _until(func() -> bool: return _scared() == 0)
	_check(true, "the hens go back to pecking")

	# 4. walk to the door -> kitchen, the bag empties into the inbox
	bag = _bag_count(_gs.data)
	_scene.tap_world(_scene.find_spot("door").hit_rect().get_center())
	await _until(func() -> bool: return _router.current == "kitchen")
	await _frames_wait(40)
	_check(_bag_count(_gs.data) == 0, "bag emptied at the door")
	_check(_inbox_count(_gs.data) >= bag, "inbox got the bag (%d items)" % _inbox_count(_gs.data))
	_check(String(root.get_meta(&"garden_return", "")) == "door", "the garden remembers she left by the door")
	print("GARDEN SMOKE OK")
	quit(0)


## Bubbles (paper panels) showing in the garden's fx layer.
func _bubbles() -> int:
	var n := 0
	for c in _scene.get("fx").get_children():
		n += 1 if c is PanelContainer else 0
	return n


func _scared() -> int:
	var n := 0
	for h in _scene.get("hens"):
		n += 1 if h.is_scared() else 0
	return n


func _tree(type: String) -> Node:
	for s in _scene.get("spots"):
		if s.kind == "tree" and s.tree_type == type:
			return s
	return null


func _bag_count(d: Dictionary) -> int:
	var n := 0
	for it in d.bag:
		n += int(it.get("count", 1))
	return n


func _inbox_count(d: Dictionary) -> int:
	var n := 0
	for it in d.get("inbox", []):
		n += int(it.get("count", 1))
	return n


func _until(cond: Callable) -> void:
	while not bool(cond.call()):
		await process_frame


func _frames_wait(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := "%s/%s.png" % [DIR, shot_name]
	RenderingServer.force_draw(false)  # macOS skips drawing a covered window; the shot must show this frame
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
