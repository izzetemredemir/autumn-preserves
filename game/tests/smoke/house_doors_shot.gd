extends SceneTree
## Smoke shot (HOUSE-DOORS): the house reads as rooms with doors. Day 1 with Granny's To-Do note: the kitchen's
## painted parlour door, the garden door and the pantry cupboard carry fixed signs (shown without hover, clear of the
## note), the room bar sits bottom-left over the hint line (kitchen pressed, keyboard reachable from the stove,
## hidden under the cook panel); the To-Do pantry step glows on the pantry, the bed step on the parlour door with
## Granny's guide just above its sign. Then the bar walks Kitchen -> Parlour (door sign, bar, hidden under the book)
## -> Pantry (door sign, bar clear of Back / gear / Auto-arrange and the shelves) -> Kitchen -> Garden.
## Saves user://shots/house_doors_{kitchen,parlor,pantry}_<locale>.png.
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/house_doors_shot.gd [-- --locale=tr]

const KITCHEN := "res://scenes/kitchen/kitchen.tscn"
const TODO_GD := "res://ui/tutorial/granny_todo.gd"
const TRANSITION_GD := "res://ui/transition/transition.gd"
## Granny's To-Do note when collapsed (x >= 326, y 36..90): no sign or bar may sit there.
const NOTE := Rect2(326, 36, 150, 55)
const BITS_PANTRY := 99  ## mail, shake, pick and jam done: the pantry step is next
const BITS_BED := 111  ## and the pantry and the order: the bed step

var _fail := 0
var _locale := "en"
var _gs: Node
var _router: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--locale="):
			_locale = a.substr(9)
	_run()


func _run() -> void:
	GameSettings.apply_language(_locale)
	await process_frame
	_gs = root.get_node("GameState")
	_router = root.get_node("Router")
	_gs.start_temp(1)
	_gs.data.flags["tutorial"] = BITS_PANTRY
	_router.current = "kitchen"  # the To-Do note hides outside game scenes
	load(TODO_GD).ensure()
	await _frames(2)
	var k: Control = (load(KITCHEN) as PackedScene).instantiate()
	root.add_child(k)
	current_scene = k  # the bar's scene change frees the kitchen
	await _frames(12)

	# --- kitchen: three signed ways out, always shown
	for kind in ["parlor", "garden", "pantry"]:
		var h: Control = k._spots.get(kind)
		var ok: bool = h != null and h.is_sign() and h.caption.is_visible_in_tree()
		_check(ok and not h.caption.get_global_rect().intersects(NOTE), "kitchen: the %s way has a sign, clear of the To-Do note" % kind)
	_check(k._spots.parlor.caption.text == tr("KITCHEN_TO_PARLOR") and k._spots.garden.caption.text == tr("KITCHEN_TO_GARDEN")
		and k._spots.pantry.caption.text == tr("KITCHEN_TO_PANTRY"), "kitchen: the signs say Parlour, Garden, Pantry")
	var door: Rect2 = k._spots.parlor.get_global_rect()
	_check(door.end.y < 140 and door.end.x <= 136 and door.position.x >= 80, "kitchen: the parlour door is on the back wall, left of the window")
	_check(k._glow == "pantry" and k._spots.pantry.glow, "kitchen: the To-Do pantry step glows on the pantry")
	_bar_checks(k, "kitchen")
	var hint: Rect2 = (k._bar as Control).get_global_rect()
	_check(not k._rooms.get_global_rect().intersects(hint), "kitchen: the room bar stays off the hint line")
	var stove: Control = k._spots.stove
	var below: Control = stove.find_valid_focus_neighbor(SIDE_BOTTOM)
	_check(below != null and below.get_parent() == k._rooms, "kitchen: Down from the stove reaches the room bar")
	k._on_spot("stove")
	await _frames(3)
	_check(not k._rooms.visible, "kitchen: the room bar hides under the cook panel")
	k._close_panel()
	await _frames(3)
	_check(k._rooms.visible, "kitchen: the room bar is back when the panel closes")
	_gs.data.flags["tutorial"] = BITS_BED
	_gs.notify(PackedStringArray(["flags"]))
	await create_timer(2.0).timeout  # the entry reveal is over: the signs stay
	_check(k._glow == "parlor" and k._spots.parlor.glow, "kitchen: the To-Do bed step glows on the parlour door")
	var at: Variant = k._guide_at("")
	var sign_r: Rect2 = k._spots.parlor.caption.get_global_rect()
	_check(at is Vector2 and absf((at as Vector2).x - sign_r.get_center().x) <= 1.0 and (at as Vector2).y <= sign_r.position.y,
		"kitchen: Granny's guide points just above the parlour door's sign")
	_shot("house_doors_kitchen_" + _locale)

	# --- the bar walks to the parlour
	await _press(k._rooms, "parlor")
	var p: Node = current_scene
	_check(String(_router.current) == "parlor" and p != null and "_spots" in p, "bar: Parlour opens the parlour")
	if p != null and "_spots" in p:
		var d: Control = p._spots.door
		_check(d.is_sign() and d.caption.is_visible_in_tree() and d.caption.text == tr("PARLOR_TO_KITCHEN"), "parlour: the door's Kitchen sign")
		var pbar: Control = p.get_node_or_null("RoomBar")
		_bar_checks(p, "parlor")
		if pbar != null:
			_check(not pbar.get_global_rect().intersects((p._bar as Control).get_global_rect()), "parlour: the room bar stays off the hint line")
		_check(p._spots.bed.glow, "parlour: the bed glows for the bed step")
		await create_timer(1.8).timeout
		_shot("house_doors_parlor_" + _locale)
		p._on_spot("shelf")
		await _frames(6)
		var book: Node = get_first_node_in_group("book")
		_check(book != null and pbar != null and not pbar.visible, "parlour: the room bar hides under the recipe book")
		if book != null:
			book.close_book()
		await _frames(20)
		_check(pbar != null and pbar.visible, "parlour: the room bar is back after the book")

		# --- on to the pantry
		await _press(pbar, "pantry")
	var pa: Node = current_scene
	_check(String(_router.current) == "pantry" and pa != null and "rooms" in pa, "bar: Pantry opens the pantry")
	if pa != null and "rooms" in pa:
		var s: Label = pa.get_node_or_null("DoorSign")
		_check(s != null and s.is_visible_in_tree() and s.text == tr("ROOM_KITCHEN"), "pantry: the door's Kitchen sign")
		_bar_checks(pa, "pantry")
		var bar_r: Rect2 = (pa.rooms as Control).get_global_rect()
		for n in ["Back", "AutoArrange"]:
			var b: Control = pa.get_node("%" + n)
			_check(not bar_r.intersects(b.get_global_rect()), "pantry: the room bar is clear of %s" % n)
		_check(not bar_r.intersects(pa._menu_btn.get_global_rect()), "pantry: the room bar is clear of the gear")
		var shelves: Rect2 = Rect2(pa.board.global_position, Vector2(pa.board.size.x, 254 - pa.board.global_position.y))
		_check(not bar_r.intersects(shelves), "pantry: the room bar is under the shelves")
		await create_timer(0.6).timeout
		_shot("house_doors_pantry_" + _locale)
		await _press(pa.rooms, "kitchen")
	_check(String(_router.current) == "kitchen", "bar: Kitchen goes back to the kitchen")
	var k2: Node = current_scene
	if k2 != null and "_rooms" in k2:
		await _press(k2._rooms, "garden")
		_check(String(_router.current) == "garden", "bar: Garden goes out to the garden")
	print("HOUSE-DOORS SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)


## The room's bar: four buttons, this room pressed and only this one, fully on screen, clear of the To-Do note.
func _bar_checks(scene: Node, room: String) -> void:
	var bar: Control = scene.get_node_or_null("RoomBar")
	if not _check(bar != null and bar.is_visible_in_tree(), "%s: the room bar shows" % room):
		return
	_check(bar.buttons.size() == 4, "%s: four room buttons" % room)
	var pressed: Array = []
	for id: String in bar.buttons:
		var b: Button = bar.buttons[id]
		if b.button_pressed:
			pressed.append(id)
		_check(b.focus_mode == Control.FOCUS_ALL and b.text != "", "%s: %s button focusable, named" % [room, id])
	_check(pressed == [room], "%s: only its own button pressed (%s)" % [room, ",".join(pressed)])
	var r := bar.get_global_rect()
	_check(Rect2(2, 2, 476, 266).encloses(r) and not r.intersects(NOTE), "%s: the bar is on screen, clear of the note %s" % [room, r])


## Presses a bar button like a click does and waits until the next room is in and its fade is done.
func _press(bar: Control, room: String) -> void:
	var b: Button = bar.buttons[room]
	var c := b.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = c
	root.push_input(mv, true)
	await _frames(2)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = c
		root.push_input(ev, true)
		await _frames(2)
	var transition: GDScript = load(TRANSITION_GD)
	var target := "wild" if room == "garden" and not _router.exists("garden") else room
	var t0 := Time.get_ticks_msec()
	while (String(_router.current) != target or transition.is_busy()) and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	await _frames(12)


func _check(ok: bool, what: String) -> bool:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fail += 1
	return ok


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)  # macOS skips frames while the window is covered; draw this one anyway
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("saved ", ProjectSettings.globalize_path("%s/%s.png" % [dir, name]))
