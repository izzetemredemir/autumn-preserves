extends SceneTree
## Smoke shot (MG-ARRANGE): drives the pantry with synthetic mouse/key events and checks GameState after each step
## (inbox -> shelf drag, right click while holding and on a shelf item, R on hover, shelf -> shelf, shelf -> inbox,
## tap-tap pick and place, Esc, Auto-arrange, live stars). Then a 2-star pantry gets its third star by one drag
## ("Ohh, lovely") and a jar is held over the cool shelf for user://shots/pantry.png. In-memory seed-1 game, no save.
##   godot --path game -s res://tests/smoke/pantry_shot.gd      (needs a display; exit 1 when a check fails)

var _gs: Node
var _scene: Control
var _board: ArrangeBoard
var _inbox: Control
var _mask := 0
var _last := Vector2.ZERO
var _checks := 0
var _fails := 0
var _notified := 0


func _initialize() -> void:
	_gs = root.get_node("GameState")
	_gs.connect("changed", func(_keys: PackedStringArray) -> void: _notified += 1)
	_run()


func _run() -> void:
	await process_frame
	await _open(_test_state())
	_interaction_checks()
	_scene.queue_free()
	await process_frame
	await _open(_shot_state())
	_shot_moves()
	for i in 20:
		await process_frame
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(dir + "/pantry.png")
	print("saved ", ProjectSettings.globalize_path(dir + "/pantry.png"))
	print("pantry smoke: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _open(state: Dictionary) -> void:
	_gs.set("data", state)
	_scene = (load("res://scenes/pantry/pantry.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_board = _scene.get_node("%Board")
	_inbox = _scene.get_node("%Inbox")
	await process_frame
	await process_frame


func _interaction_checks() -> void:
	var d: Dictionary = _gs.get("data")
	var items: Array = d.pantry.items
	var inbox: Array = d.inbox
	var n_in := inbox.size()
	var stars0 := int(_board.stars_result().get("stars", -1))

	_drag(_slot(_find(inbox, "jam|apple_1|-")), _cell(Vector2i(0, 2)))
	_check("inbox -> shelf by drag", items.size() == 1 and inbox.size() == n_in - 1 and _at(items, Vector2i(0, 2)) == "jam")
	_check("GameState.notify on a move", _notified > 0)

	var start := _slot(_find(inbox, "pie|apple_1|-"))
	_press(start)
	_move(start + Vector2(30, 0))
	_move(_cell(Vector2i(2, 2)))
	_press(_cell(Vector2i(2, 2)), MOUSE_BUTTON_RIGHT)
	_release(_cell(Vector2i(2, 2)), MOUSE_BUTTON_RIGHT)
	_move(_cell(Vector2i(2, 2)) + Vector2(1, 0))
	_release(_cell(Vector2i(2, 2)) + Vector2(1, 0))
	var pie := _entry(items, "pie|apple_1|-")
	_check("right click turns the held pie", not pie.is_empty() and int(pie.rot) == 1 and int(pie.x) == 2 and int(pie.y) == 2)

	_press(_cell(Vector2i(2, 3)), MOUSE_BUTTON_RIGHT)
	_release(_cell(Vector2i(2, 3)), MOUSE_BUTTON_RIGHT)
	_check("right click turns a shelf item", int(pie.get("rot", -1)) == 0 and _at(items, Vector2i(3, 2)) == "pie")

	_move(_cell(Vector2i(3, 2)))
	_key(KEY_R)
	_check("R turns the hovered item", int(pie.get("rot", -1)) == 1)

	_drag(_cell(Vector2i(0, 2)), _cell(Vector2i(1, 2)))
	_check("shelf -> shelf", _at(items, Vector2i(1, 2)) == "jam" and _at(items, Vector2i(0, 2)) == "")

	var before := inbox.size()
	_drag(_cell(Vector2i(1, 2)), _inbox.get_global_rect().get_center())
	_check("shelf -> inbox", inbox.size() == before + 1 and _entry(items, "jam|apple_1|-").is_empty())

	var nut := _slot(_find_type(inbox, "walnut"))
	_press(nut)
	_release(nut)
	_check("tap keeps the item in hand", _board.is_holding())
	_move(_cell(Vector2i(0, 0)))
	_press(_cell(Vector2i(0, 0)))
	_release(_cell(Vector2i(0, 0)))
	_check("second tap places it", not _board.is_holding() and _at(items, Vector2i(0, 0)) == "walnut")

	before = inbox.size()
	var q := _slot(_find(inbox, "jam|quince_1|-"))
	_press(q)
	_move(_cell(Vector2i(0, 3)))
	_key(KEY_ESCAPE)
	_release(_cell(Vector2i(0, 3)))
	_check("Esc puts the held item back", not _board.is_holding() and inbox.size() == before and _at(items, Vector2i(0, 3)) == "")
	_check("Esc while holding stays in the pantry", is_instance_valid(_scene) and _scene.is_inside_tree())

	var btn: Button = _scene.get_node("%AutoArrange")
	_move(btn.get_global_rect().get_center())
	_press(btn.get_global_rect().get_center())
	_release(btn.get_global_rect().get_center())
	_check("Auto-arrange clicks through", inbox.size() < before)
	var stars1 := int(_board.stars_result().get("stars", -1))
	_check("stars are live (%d -> %d)" % [stars0, stars1], stars1 >= 1 and stars1 != stars0)


func _test_state() -> Dictionary:
	var s := State.new_game(1)
	s.inbox = (load("res://scenes/pantry/pantry.gd") as GDScript).call("sample_items")
	return s


## Room shelf: five jams light to dark + bottle; pickles split on the cool shelf -> 2 stars until one drag.
func _shot_state() -> Dictionary:
	var s := State.new_game(1)
	var v: Dictionary = s.varieties
	var jams := ["jam|quince_1|-", "jam|pear_2|-", "jam|apple_1|-", "jam|crabapple_1|-", "jam|blackberry_1|-"]
	jams.sort_custom(func(a: String, b: String) -> bool: return _lum(a, v) > _lum(b, v))
	var items: Array = s.pantry.items
	for i in jams.size():
		items.append(_e(State.product(jams[i], 2, 0), i, 2))
	items.append(_e(State.product("juice|apple_2|-", 2, 0), 5, 2))
	items.append(_e(State.product("pie|apple_1|-", 3, 0, 3), 0, 3))
	items.append(_e(State.product("chutney|pear_1|pepper_1|-", 2, 0), 2, 3))
	items.append(_e(State.nut("walnut", 8), 0, 0))
	items.append(_e(State.product("bread|-", 1, 0, 3), 1, 0))
	items.append(_e(State.product("pickle|cucumber_1|-", 2, 2), 0, 4))
	items.append(_e(State.product("pickle|cucumber_2|-", 1, 2), 3, 4))
	items.append(_e(State.product("brined_mushroom|chanterelle_1|-", 2, 1), 5, 4))
	items.append(_e(State.fresh("apple_1", 5, 6), 0, 5))
	items.append(_e(State.fresh("blackberry_2", 3, 2), 1, 5))
	s.inbox = [State.product("jam|pear_1|-", 2, 0), State.fresh("chanterelle_1", 2, 2), State.fresh("pear_3", 4, 4),
		State.fresh("porcini_1", 1, 2), State.product("pickle|cucumber_3|-", 3, 2)]
	return s


func _shot_moves() -> void:
	var stars0 := int(_board.stars_result().get("stars", -1))
	_drag(_cell(Vector2i(3, 4)), _cell(Vector2i(1, 4)))
	var stars1 := int(_board.stars_result().get("stars", -1))
	_check("one drag gives the third star (%d -> %d)" % [stars0, stars1], stars0 == 2 and stars1 == 3)
	_check("lovely bubble shows", (_scene.get_node("%Bubble") as Control).visible)
	var d: Dictionary = _gs.get("data")
	var p := _slot(_find_type(d.inbox, "chanterelle"))
	_press(p)
	_move(p + Vector2(40, 0))
	_move(_cell(Vector2i(3, 5)) + Vector2(2, 1))


# --- helpers -----------------------------------------------------------------------------------------------------

func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("ok   " if ok else "FAIL ") + what)


func _e(item: Dictionary, x: int, y: int) -> Dictionary:
	return {"item": item, "x": x, "y": y, "rot": 0}


func _lum(key: String, varieties: Dictionary) -> float:
	return PantryRules.fill_luminance(ProductGen.describe(key, varieties))


func _cell(c: Vector2i) -> Vector2:
	return _board.get_global_rect().position + Vector2(_board.cell_rect(c).position) + Vector2(12, 12)


func _slot(i: int) -> Vector2:
	var r: Rect2i = _inbox.call("slot_rect", i)
	return _inbox.get_global_rect().position + Vector2(r.position) + Vector2(12, 12)


func _find(arr: Array, key: String) -> int:
	for i in arr.size():
		if String(arr[i].get("key", "")) == key:
			return i
	return -1


func _find_type(arr: Array, type: String) -> int:
	for i in arr.size():
		if State.item_type(arr[i]) == type:
			return i
	return -1


func _entry(items: Array, key: String) -> Dictionary:
	for e in items:
		if String(e.item.get("key", "")) == key:
			return e
	return {}


func _at(items: Array, c: Vector2i) -> String:
	for e in items:
		if PantryRules.entry_cells(e).has(c):
			return State.item_type(e.item)
	return ""


func _press(p: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_button(p, button, true)


func _release(p: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_button(p, button, false)


func _button(p: Vector2, button: MouseButton, pressed: bool) -> void:
	var bit := 1 << (int(button) - 1)
	_mask = (_mask | bit) if pressed else (_mask & ~bit)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = _mask
	ev.position = p
	ev.global_position = p
	root.push_input(ev, true)


func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.relative = p - _last
	ev.button_mask = _mask
	_last = p
	root.push_input(ev, true)


func _drag(a: Vector2, b: Vector2) -> void:
	_move(a)
	_press(a)
	_move(a.lerp(b, 0.5))
	_move(b)
	_release(b)


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		root.push_input(ev, true)
