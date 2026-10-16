extends SceneTree
## Smoke drive (GD-GARDEN): the garden run alone on a throwaway game (GameState.start_temp), Granny's To-Do on.
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/garden_shot.gd
## Taps the apple tree (energy -3, bag +2..3), buys a cucumber seed and plants it in an empty bed through the
## plant menu, makes a letter arrive (mailbox flag up), opens and closes the letters overlay from the mailbox,
## then taps the door and checks the bag went to the inbox and the kitchen opened.
## Saves user://shots/garden_start.png, garden_menu.png, garden.png, garden_letters.png.
## Exit code 1 on a failed check or timeout.
## Autoloads are reached through the root and scene scripts by path (SceneTree scripts can't name autoloads).

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
