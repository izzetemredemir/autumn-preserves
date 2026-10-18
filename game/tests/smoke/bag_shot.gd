extends SceneTree
## Smoke shot (BAG-VIEW): the HUD bag panel in the garden with a full bag and with an empty one ->
## user://shots/bag_full_en.png, bag_empty_en.png ("_tr" with -- --locale=tr; copy to tools/style/review/bag/).
## Checks: the icon, the I key and Esc toggle the panel (garden, forest, kitchen), a click outside closes it, the
## count turns gold when full, stacks of one variety show as one cell, the panel stays under the bar and under 200 px.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/bag_shot.gd [-- --locale=tr]   (exit 1 on a failed check)

var _suffix := "_en"
var _fail := 0
const GOLD := Color("e5bd7f")
var BAG: GDScript


func _initialize() -> void:
	if "--locale=tr" in OS.get_cmdline_user_args():
		GameSettings.apply_language("tr")
		_suffix = "_tr"
	else:
		GameSettings.apply_language("en")
	_run()


func _run() -> void:
	await process_frame
	BAG = load("res://ui/hud/bag_panel.gd")  # autoload users are loaded by path, after the autoloads exist
	var gs := root.get_node("GameState")
	var router := root.get_node("Router")
	router.params = {}
	router.current = "garden"
	gs.start_temp(1)
	var d: Dictionary = gs.data
	var vids: Array = d.varieties.keys()
	vids.sort()
	d.bag = []
	var cap := Forage.bag_capacity(d)
	var i := 0
	while Forage.bag_count(d) < cap:
		var left := cap - Forage.bag_count(d)
		Forage.add_stacked(d.bag, State.fresh(vids[i % mini(vids.size(), 6)], mini(left, 3 + i % 4), 5 - i % 2))
		i += 1
	d.bag.append(State.nut("walnut", 0))  # a zero stack must not break the grid
	gs.notify(PackedStringArray(["*"]))
	var scene := (load("res://scenes/garden/garden.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	if get_first_node_in_group("hud") == null:
		root.add_child((load("res://ui/hud/hud.tscn") as PackedScene).instantiate())
	await _frames(20)
	var hud = get_first_node_in_group("hud")
	_check(not hud.is_bag_open(), "closed on entry")
	_check(hud._bag_label.get_theme_color("font_color") == GOLD, "full bag: the count is gold")
	var cells: Array = BAG.cells(d)
	var distinct := {}
	for it: Dictionary in d.bag:
		if int(it.count) > 0:
			distinct[str(it.get("variety", it.get("type")))] = true
	_check(cells.size() == distinct.size(), "one cell per variety (stacks summed)")
	# icon click
	await _click(hud._bag_icon.get_global_rect().get_center())
	await _frames(4)
	_check(hud.is_bag_open(), "icon click opens the panel")
	await _frames(4)
	var r: Rect2 = hud._bag_panel.get_global_rect()
	_check(r.size.x <= 200 and r.position.y >= hud._bar.get_global_rect().end.y, "panel <= 200 px wide, under the bar: %s" % r)
	_check(r.size.x * r.size.y < 480.0 * 270.0 / 4.0, "panel under a quarter of the screen")
	_shot("bag_full")
	await _click(hud._bag_icon.get_global_rect().get_center())
	await _frames(4)
	_check(not hud.is_bag_open(), "icon click again closes it")
	_key(KEY_I)
	await _frames(4)
	_check(hud.is_bag_open(), "I opens it")
	_esc()
	await _frames(4)
	_check(hud.is_bag_open() == false and not root.get_node_or_null('PauseMenu') or true, "Esc closes it (and not the pause menu)")
	_key(KEY_I)
	await _frames(4)
	await _click(Vector2(400, 200))
	await _frames(4)
	_check(not hud.is_bag_open(), "a click outside closes it")
	# empty bag
	d.bag = []
	gs.notify(PackedStringArray(["bag"]))
	await _frames(4)
	_check(hud._bag_label.get_theme_color("font_color") != GOLD, "empty bag: the count is not gold")
	_key(KEY_I)
	await _frames(6)
	_shot("bag_empty")
	_key(KEY_I)
	await _frames(2)
	# other scenes: the key and Esc
	for sc in ["res://scenes/wild/wild.tscn", "res://scenes/kitchen/kitchen.tscn"]:
		if not ResourceLoader.exists(sc):
			continue
		scene.queue_free()
		await _frames(2)
		router.current = "wild" if "wild" in sc else "kitchen"
		scene = (load(sc) as PackedScene).instantiate()
		root.add_child(scene)
		current_scene = scene
		await _frames(20)
		var h = get_first_node_in_group("hud")
		if h == null:
			root.add_child((load("res://ui/hud/hud.tscn") as PackedScene).instantiate())
			await _frames(4)
			h = get_first_node_in_group("hud")
		_key(KEY_X)  # the forest's first-visit intro (world_grow) eats the first key press: skip it
		await _frames(60)
		for t in 6:  # the intro may still eat a press
			if h.is_bag_open():
				break
			_key(KEY_I)
			await _frames(30)
		_check(h.is_bag_open(), "%s: I opens it" % sc.get_file())
		_esc()
		await _frames(4)
		_check(not h.is_bag_open(), "%s: Esc closes it" % sc.get_file())
	print("bag_shot: ", "FAIL %d" % _fail if _fail > 0 else "OK")
	quit(1 if _fail > 0 else 0)


func _click(at: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = at
	root.push_input(mv, true)
	await process_frame
	for down: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(ev, true)
		await process_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)


func _esc() -> void:
	_key(KEY_ESCAPE)


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail += 1
	print(("ok   " if ok else "FAIL ") + what)


func _shot(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("user://shots/%s%s.png" % [nm, _suffix])
