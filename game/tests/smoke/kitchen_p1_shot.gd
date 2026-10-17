extends SceneTree
## Smoke shot (P1-RECIPES): the kitchen alone (throwaway game, debug inventory + DevTools.unlock_p1) with the fruit
## press and the dough board.
##   1. Mouse: click the press, click a fruit row, click Cook; the press mini-game is played to the end with Space
##      and mouse clicks on the beat -> juice in the inbox.
##   2. Keyboard: focus the dough board, E opens it, arrow to the bread tab, E, walk focus to Cook, E; knead plays
##      itself (short ctx times) -> bread in the inbox.
##   3. A second juice of the same fruit -> syrup at the stove (four tabs, juice rows) with gifted mint (a P1
##      add-in held only in the cupboard) -> syrup in the inbox.
##   4. The recipe book lists the P1 recipes.
## Saves user://shots/kitchen_p1.png (room), kitchen_p1_press.png, kitchen_p1_mg_press.png, kitchen_p1_board.png,
## kitchen_p1_stove.png, kitchen_p1_book.png.
## godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/kitchen_p1_shot.gd
## (not headless; wrap it in a timeout, about 60 s).

## Press.Phase values (the class is not named here: autoload-using classes load by path in smoke scripts).
const PRESS_PLAY := 1
const PRESS_DONE := 2

var _k: Control
var _fail := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_k = (load("res://scenes/kitchen/kitchen.tscn") as PackedScene).instantiate()
	root.get_node("Router").current = "kitchen"
	root.add_child(_k)
	await _frames(12)
	var gs: Node = root.get_node("GameState")
	var d: Dictionary = gs.data
	_check(_k._spots.press.visible and _k._spots.board.visible, "press and dough board shown once unlocked")
	_shot("kitchen_p1")
	var panel: Control = _k._panel

	# --- 1. press with the mouse, played with Space and clicks
	await _click(_k._spots.press.get_global_rect().get_center())
	await _frames(4)
	_check(panel.visible and panel.station == "press", "click on the press opens it")
	_check(panel._recipes == ["juice", "fruit_vinegar"], "press recipes: %s" % [panel._recipes])
	var fruit := _first_fitting(panel, "main", 4)
	if fruit != "":
		panel._scroll.ensure_control_visible(panel._rows[fruit])
		await _frames(2)
		await _click(panel._rows[fruit].get_global_rect().get_center())
	_check(panel.picks.main == fruit and fruit != "", "click on a fruit row fills the slot (%s)" % fruit)
	await _frames(14)
	_shot("kitchen_p1_press")
	await _click(panel._cook.get_global_rect().get_center())
	await _frames(2)
	_check(_k._mg != null and String(_k._mg.get_script().resource_path).ends_with("press.gd"), "press mini-game launched")
	if _k._mg == null:
		_finish()
		return
	await _play_press(_k._mg)
	if not await _wait_card(10000, "result card after juice"):
		_finish()
		return
	_check(_has(gs.data, "juice|" + fruit + "|"), "juice in the inbox")
	_k._card._on_close()
	await _frames(4)

	# --- 2. dough board with the keyboard, bread
	_k._spots.board.grab_focus()
	_action("interact")
	await _frames(4)
	_check(panel.visible and panel.station == "knead", "E on the focused board opens it")
	_check(panel._recipes == ["pie", "bread"], "board recipes: %s" % [panel._recipes])
	print("focus before: ", _focus_name(panel))
	_action("move_right")
	await _frames(2)
	print("focus after right: ", _focus_name(panel))
	_action("interact")
	await _frames(4)
	_check(panel.recipe == "bread", "arrow + E picks the bread tab")
	var steps := 0
	while root.gui_get_focus_owner() != panel._cook and steps < 12:
		_action("move_down" if steps < 6 else "move_right")
		await _frames(2)
		steps += 1
	_check(root.gui_get_focus_owner() == panel._cook, "arrows reach Cook (%d steps)" % steps)
	await _frames(10)
	_shot("kitchen_p1_board")
	_k.debug_ctx = {"autoplay": true, "knead_time": 3.0, "trace_time": 2.0}
	_action("interact")
	await _frames(2)
	_check(_k._mg != null and String(_k._mg.get_script().resource_path).ends_with("knead.gd"), "knead mini-game launched")
	if not await _wait_card(25000, "result card after bread"):
		_finish()
		return
	_check(_has(gs.data, "bread|-"), "bread in the inbox")
	_k._card._on_close()
	await _frames(4)

	# --- 3. syrup from two juices of one fruit at the stove
	d = gs.data
	d.inbox.append(State.product(ProductGen.make_key("juice", [fruit], ""), 2, 0))
	d.cupboard["mint"] = 3  # Edith's 3-heart gift: a P1 add-in that only the cupboard holds
	await _click(_k._spots.stove.get_global_rect().get_center())
	await _frames(4)
	_check(panel._recipes.has("syrup"), "syrup at the stove once the press is there")
	panel._select_recipe("syrup")
	await _frames(4)
	_check(panel._rows.has(fruit) and panel._rows.size() == Kitchen.product_stock(d, "juice").size(), "juice rows for syrup")
	if panel._rows.has(fruit):
		await _click(panel._rows[fruit].get_global_rect().get_center())
	_check(panel.picks.main == fruit and panel._ok, "two juices fill the syrup slot")
	_check(panel._addin_buttons.has("mint"), "gifted mint in the add-in row")
	panel._select_addin("mint")
	await _frames(2)
	_check(panel._ok, "syrup with mint is ready")
	await _frames(14)
	_shot("kitchen_p1_stove")
	_k.debug_ctx = {"autoplay": true, "duration": 3.0}
	panel._on_cook()
	await _frames(2)
	if not await _wait_card(20000, "result card after syrup"):
		_finish()
		return
	_check(_has(gs.data, "syrup|" + fruit + "|"), "syrup in the inbox")
	_check(Kitchen.product_stock(gs.data, "juice").get(fruit, 0) == 0, "both juices used")
	_check(_has(gs.data, "syrup|%s|mint" % fruit) and int(gs.data.cupboard.mint) == 2, "mint went into the syrup")
	_k._card._on_close()
	await _frames(4)

	# --- 4. the recipe book shows the new recipes
	var book: Node = load("res://ui/book/book.gd").open()
	await _frames(6)
	var ids: Array = book._recipe_ids()
	_check(ids.size() == 11 and ids.has("syrup") and ids.has("bread"), "book lists %d recipes" % ids.size())
	book._flip(1)
	await _frames(6)
	_shot("kitchen_p1_book")
	book.close_book()
	await _frames(2)
	_finish()


## Plays the whole press song: Space on even beats, a mouse click on odd ones, right on the beat.
func _play_press(mg: Node) -> void:
	var t0 := Time.get_ticks_msec()
	var sent := 0
	var shot := false
	while is_instance_valid(mg) and int(mg.phase) != PRESS_DONE and Time.get_ticks_msec() - t0 < 45000:
		await process_frame
		if not is_instance_valid(mg) or int(mg.phase) != PRESS_PLAY:
			continue
		var next: int = mg.grades.find("")
		if next >= 0 and mg._now_ms() >= mg.beat_ms(next) - 8.0:
			if next % 2 == 0:
				_key(KEY_SPACE, true)
				await process_frame
				_key(KEY_SPACE, false)
			else:
				await _click(Vector2(240, 140))
			sent += 1
			if next == 6 and not shot:
				shot = true
				await _frames(3)
				_shot("kitchen_p1_mg_press")
	if not is_instance_valid(mg):
		return
	var c: Dictionary = mg.counts
	print("press: sent %d, perfect %d good %d miss %d" % [sent, c.perfect, c.good, c.miss])
	_check(int(c.perfect) + int(c.good) >= 6, "Space and clicks land on the beat (%d hits)" % (int(c.perfect) + int(c.good)))


func _wait_card(ms: int, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while _k._card == null and Time.get_ticks_msec() - t0 < ms:
		await process_frame
	await _frames(20)
	return _check(_k._card != null, what)


func _finish() -> void:
	print("KITCHEN P1 SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)


func _first_fitting(panel: Control, which: String, need: int) -> String:
	var stock: Dictionary = panel._slot_stock(which)
	var ids: Array = stock.keys()
	ids.sort()
	for vid in ids:
		if panel._fits(which, vid) and int(stock[vid]) >= need:
			return vid
	return ""


func _has(d: Dictionary, prefix: String) -> bool:
	for item in d.inbox:
		if item.kind == "product" and String(item.key).begins_with(prefix):
			return true
	return false


func _action(name: String) -> void:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = name
	up.pressed = false
	Input.parse_input_event(up)


func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _click(at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(down, true)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	root.push_input(up, true)
	await process_frame


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


func _focus_name(panel: Control) -> String:
	var f := root.gui_get_focus_owner()
	if f == null:
		return "none"
	for id in panel._tabs:
		if panel._tabs[id] == f:
			return "tab " + id
	return "%s %s" % [f.get_class(), f.get_global_rect()]
