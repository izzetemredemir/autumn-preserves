extends SceneTree
## Smoke shot (MG-ARRANGE): drives the pantry with synthetic mouse/key events and checks GameState after each step
## (inbox -> shelf drag, right click while holding and on a shelf item, R on hover, shelf -> shelf, shelf -> inbox,
## tap-tap pick and place, Esc, Auto-arrange, live stars). Then a 2-star pantry gets its third star by one drag
## ("Ohh, lovely") and a jar is held over the cool shelf for user://shots/pantry.png. In-memory seed-1 game, no save.
## POLISH-PANTRY: with 1 and 3 bought shelves the room stays painted (labels on plates, no off-palette pixel in any
## shot) and scrolls: wheel, drag on empty space, W/S + Up/Down, and a held item reaches the lowest shelf by mouse
## (edge auto-scroll) and by keyboard (tap, S/Down, tap) -> user://shots/pantry_rows1.png, pantry_rows3.png.
##   godot --audio-driver Dummy --path game -s res://tests/smoke/pantry_shot.gd   (needs a display; exit 1 on a fail)

const PAL := ["111010", "a22512", "c94d2e", "e19064", "49423d", "81746a", "b9a697", "f2d9c5", "50361e", "b66813",
	"c58845", "83571e", "e5bd7f", "9b8039", "dbcc83", "b1a13d", "c5bf3f", "b4b3a0", "b7b768", "747c37", "53612e",
	"314524", "738c7a", "4e7664", "275e4c", "2e3f3f", "415c5d", "567c7d", "23282a", "3d1f29", "62272c"]

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
	await _frames(20)
	_painted_checks(0)
	_shot("pantry.png")
	_board.cancel_hold()
	_scene.queue_free()
	await process_frame

	await _open(_bought_state(1))
	_painted_checks(1)
	await _wheel_checks()
	_shot("pantry_rows1.png")
	_scene.queue_free()
	await process_frame

	await _open(_bought_state(3))
	_painted_checks(3)
	_pan_checks()
	await _lowest_shelf_checks()
	_shot("pantry_rows3.png")
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


# --- bought shelves (POLISH-PANTRY) ------------------------------------------------------------------------------

## A few items on every shelf (bought ones too) and a pear basket on the floor.
func _bought_state(n: int) -> Dictionary:
	var s := State.new_game(1)
	for i in n:
		PantryRules.add_shelf(s.pantry)
	var items: Array = s.pantry.items
	items.append(_e(State.nut("walnut", 8), 0, 0))
	items.append(_e(State.product("bread|-", 1, 0, 3), 1, 0))
	for i in 4:
		items.append(_e(State.product(["jam|quince_1|-", "jam|pear_2|-", "jam|apple_1|-", "jam|crabapple_1|-"][i], 2, 0), i, 2))
	items.append(_e(State.product("pickle|cucumber_1|-", 2, 2), 0, 4))
	items.append(_e(State.fresh("apple_1", 5, 6), 1, 5))
	var bought: Array = [
		[State.product("chutney|pear_1|pepper_1|-", 2, 0), State.product("juice|apple_2|-", 2, 0), State.product("pie|apple_1|-", 3, 0, 3)],
		[State.product("pickle|cucumber_2|-", 1, 2), State.product("brined_mushroom|chanterelle_1|-", 2, 1), State.fresh("blackberry_2", 3, 2)],
		[State.nut("hazelnut", 6), State.product("bread|-", 2, 0, 3), State.nut("walnut", 4)],
	]
	var cells: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 1)]
	var cells_dry: Array = [Vector2i(5, 0), Vector2i(4, 1), Vector2i(1, 1)]
	for k in n:
		for j in 3:
			var c: Vector2i = (cells_dry if k == 2 else cells)[j]
			items.append(_e(bought[k][j], c.x, 6 + 2 * k + c.y))
	items.append(_e(State.fresh("pear_2", 3, 5), 0, 6 + 2 * n))
	s.inbox = [State.product("jam|pear_1|-", 2, 0), State.product("pickle|cucumber_3|-", 3, 2),
		State.fresh("chanterelle_1", 2, 2), State.fresh("pear_3", 4, 4)]
	return s


## Painted look for any shelf count: art on, scroll range = one band per bought shelf, every shelf label on its plate.
func _painted_checks(n: int) -> void:
	var shelves: Array = _board.board.get("shelves", [])
	_check("%d bought: painted look" % n, bool(_scene.call("on_art")))
	_check("%d bought: scroll range %d" % [n, 60 * n], int(_scene.call("scroll_max")) == 60 * n)
	var labels: Array = _scene.get("_zone_labels")
	var off := int(_scene.call("scroll_offset"))
	var on_plates := labels.size() == shelves.size() + 1
	for i in shelves.size():
		var plate: Rect2i = _scene.call("plate_rect", i)
		var l: Label = labels[i]
		on_plates = on_plates and Vector2i(l.position) == plate.position - Vector2i(0, off) and Vector2i(l.size) == plate.size
	_check("%d bought: %d shelf labels on name plates" % [n, shelves.size()], on_plates)


func _wheel_checks() -> void:
	var p := _board.get_global_rect().get_center()
	_wheel(p, MOUSE_BUTTON_WHEEL_DOWN, 2)
	await _settle()
	_check("wheel down scrolls (%d)" % _offset(), _offset() == 48)
	_wheel(p, MOUSE_BUTTON_WHEEL_DOWN, 3)
	await _settle()
	_check("wheel stops at the bottom (%d)" % _offset(), _offset() == 60)
	_wheel(p, MOUSE_BUTTON_WHEEL_UP, 4)
	await _settle()
	_check("wheel up back to the top (%d)" % _offset(), _offset() == 0)


func _pan_checks() -> void:
	var d: Dictionary = _gs.get("data")
	var empty := _cell(Vector2i(5, 1))
	_check("pan starts on an empty cell", _at(d.pantry.items, Vector2i(5, 1)) == "")
	_move(empty)
	_press(empty)
	_move(empty + Vector2(0, -50))
	_move(empty + Vector2(0, -100))
	_check("drag on empty space scrolls (%d)" % _offset(), _offset() == 100)
	_move(empty + Vector2(0, -40))
	_release(empty + Vector2(0, -40))
	_check("dragging back scrolls back (%d)" % _offset(), _offset() == 40)
	var jar := _cell(Vector2i(0, 4))
	_move(jar)
	_press(jar)
	_move(jar + Vector2(0, -30))
	_check("dragging an item does not scroll", _offset() == 40 and _board.is_holding())
	_key(KEY_ESCAPE)
	_release(jar + Vector2(0, -30))
	_scene.call("scroll_to", 0.0, true)


## Mouse: inbox jar dragged to the bottom edge auto-scrolls to the lowest shelf and drops there. Keyboard: W x3 to
## the top, tap a pickle, Down x3, tap on the lowest shelf. Last: a chanterelle held over the lowest shelf for the shot.
func _lowest_shelf_checks() -> void:
	var d: Dictionary = _gs.get("data")
	var items: Array = d.pantry.items
	var low := int(_board.board.rows) - 3
	_check("lowest shelf is row %d (dry)" % low, _board.zone_at(Vector2i(0, low)) == "dry" and int(_board.board.floor_y) == low + 1)
	var max_off := int(_scene.call("scroll_max"))

	var start := _slot(_find(d.inbox, "jam|pear_1|-"))
	_press(start)
	_move(start + Vector2(30, 0))
	_move(Vector2(384, 266))
	for i in 240:
		if _offset() >= max_off:
			break
		await process_frame
	_check("held at the bottom edge auto-scrolls to the end (%d)" % _offset(), _offset() == max_off)
	_move(_cell(Vector2i(2, low)))
	await _frames(5)
	_release(_cell(Vector2i(2, low)))
	var jam := _entry(items, "jam|pear_1|-")
	_check("mouse: jar dropped on the lowest shelf", not jam.is_empty() and int(jam.y) == low and int(jam.x) == 2)

	for i in 3:
		_key(KEY_W)
	await _settle()
	_check("W scrolls back to the top (%d)" % _offset(), _offset() == 0)
	var pk := _slot(_find(d.inbox, "pickle|cucumber_3|-"))
	_move(pk)
	_press(pk)
	_release(pk)
	_check("keyboard: tap holds the pickle", _board.is_holding())
	for i in 3:
		_key(KEY_DOWN)
	await _settle()
	_check("Down scrolls to the lowest shelf while holding (%d)" % _offset(), _offset() == max_off and _board.is_holding())
	_move(_cell(Vector2i(3, low)))
	_press(_cell(Vector2i(3, low)))
	_release(_cell(Vector2i(3, low)))
	var pickle := _entry(items, "pickle|cucumber_3|-")
	_check("keyboard: pickle placed on the lowest shelf", not pickle.is_empty() and int(pickle.y) == low and int(pickle.x) == 3)

	var ch := _slot(_find_type(d.inbox, "chanterelle"))
	_press(ch)
	_move(ch + Vector2(40, 0))
	_move(_cell(Vector2i(0, low)) + Vector2(2, 1))
	await _frames(20)


# --- helpers -----------------------------------------------------------------------------------------------------

func _offset() -> int:
	return int(_scene.call("scroll_offset"))


## Waits until the eased scroll has arrived (at most 240 frames).
func _settle() -> void:
	for i in 240:
		if float(_scene.get("_scroll")) == float(_scene.get("_scroll_to")):
			return
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(file: String) -> void:
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)
	var img := root.get_texture().get_image()
	img.save_png(dir + "/" + file)
	print("saved ", ProjectSettings.globalize_path(dir + "/" + file))
	var pal := {}
	for h in PAL:
		pal[h] = true
	var off := 0
	for y in img.get_height():
		for x in img.get_width():
			if not pal.has(img.get_pixel(x, y).to_html(false)):
				off += 1
	_check("%s: no off-palette pixels (%d)" % [file, off], off == 0)


func _wheel(p: Vector2, button: MouseButton, notches: int) -> void:
	for i in notches:
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			ev.pressed = pressed
			ev.factor = 1.0
			ev.position = p
			ev.global_position = p
			root.push_input(ev, true)

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
