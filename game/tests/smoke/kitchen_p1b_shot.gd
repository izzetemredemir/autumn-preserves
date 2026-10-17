extends SceneTree
## Smoke shot (KITCHEN-P1B): the kitchen alone (throwaway game, debug inventory) with the big pot and a jam variant
## two good cooks away from Mastered.
##   1. Mouse: stove -> fruit slot -> apple row in its picker -> x2 -> Cook; the stir mini-game ends with 3 stars ->
##      two jars, "Mastered!" on the result card, the mastery line on the message bar.
##   2. Stove again (the apple picked by hand is kept): Batch cook beside x2 under Cook (the card's smoke shot);
##      Batch cook -> no mini-game, two more jars at the best quality for one cook's energy.
##   3. The recipe book shows the Mastered badge.
##   4. Knead alone: bread shapes a loaf (part 2), pie fills in the fruit's tones; the press bottle in three tones.
## Saves user://shots/kitchen_p1b_panel.png (cook panel with Batch cook and x2), kitchen_p1b_x2.png,
## kitchen_p1b_mastered.png, kitchen_p1b_book.png, kitchen_p1b_mg_bread.png, kitchen_p1b_mg_bread_done.png,
## kitchen_p1b_mg_pie.png, kitchen_p1b_mg_press.png.
## godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/kitchen_p1b_shot.gd
## (not headless; wrap it in a timeout, about 40 s).

## Knead.Phase values (smoke scripts load autoload-using classes by path).
const KNEAD_TRACE := 3
const KNEAD_DONE := 4

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
	Economy.unlock(d, "big_pot")
	var apple := DevTools.first_variety(d, "apple")
	d.inbox.append(State.fresh(apple, 12, 6))
	d.cupboard["sugar"] = int(d.cupboard.get("sugar", 0)) + 6
	d.cupboard["jar"] = int(d.cupboard.get("jar", 0)) + 6
	var key := Kitchen.product_key("jam", apple, "", "")
	d.book.variants[key] = {"best_q": 3, "best_stars": 3, "count": 2, "first_day": 1, "good": 2}
	d.energy = 80
	var panel: Control = _k._panel

	# --- 1. x2 jam with the mouse; the third good cook masters it
	await _click(_k._spots.stove.get_global_rect().get_center())
	await _frames(4)
	_check(panel.visible and panel.recipe == "jam", "stove opens on jam")
	_check(panel._extras.visible and panel._mult_buttons[2].visible, "x1/x2 shown with the big pot")
	_check(not panel._batch.visible, "no Batch cook before a jam is Mastered")
	await _click(panel._slots.main.button.get_global_rect().get_center())
	if panel._rows.has(apple):
		panel._scroll.ensure_control_visible(panel._rows[apple])
		await _frames(2)
		await _click(panel._rows[apple].get_global_rect().get_center())
	_check(panel.picks.main == apple, "click on the apple row fills the slot")
	await _click(panel._mult_buttons[2].get_global_rect().get_center())
	await _frames(2)
	_check(panel.mult == 2 and panel._ok, "x2 picked and ready")
	_check(String(panel._slots.main.caption.text).ends_with("6"), "slot asks for 6 (%s)" % panel._slots.main.caption.text)
	_check(panel._cook.tooltip_text == tr("UI_BATCH_COOK_TWO") % Kitchen.energy_cost("stir_pot"), "Cook says two jars")
	await _frames(14)
	_shot("kitchen_p1b_x2")
	var jars0 := _count(gs.data, key)
	await _click(panel._cook.get_global_rect().get_center())
	await _frames(2)
	_check(_k._mg != null, "stir mini-game launched")
	if _k._mg == null:
		_finish()
		return
	_k._mg.finished.emit({"stars": 3})
	if not await _wait_card(5000, "result card after the x2 jam"):
		_finish()
		return
	_check(_count(gs.data, key) == jars0 + 2, "two jars from the big pot")
	_check(Kitchen.is_mastered(gs.data, key), "jam variant Mastered")
	var banner: Variant = _k._card.get("_banner")
	_check(banner is Label and banner.visible and banner.text == tr("UI_MASTERY_BANNER"), "card says Mastered!")
	_shot("kitchen_p1b_mastered")
	_k._card._on_close()
	await _frames(4)
	_check(_k._message.text == tr("UI_MASTERY_NEW"), "message bar: %s" % _k._message.text)

	# --- 2. Batch cook next to x2 (the card's smoke shot), then a batch without the mini-game
	await _click(_k._spots.stove.get_global_rect().get_center())
	await _frames(4)
	_check(panel.picks.main == apple and panel.mult == 2, "picks and x2 kept")
	_check(panel._batch.visible and panel._batch_ok, "Batch cook ready for the Mastered jam")
	_check(panel._feedback.text == tr("UI_MASTERY_READY"), "feedback: %s" % panel._feedback.text)
	panel._batch.grab_focus()
	await _frames(14)
	_shot("kitchen_p1b_panel")
	var energy := int(gs.data.energy)
	var jars1 := _count(gs.data, key)
	await _click(panel._batch.get_global_rect().get_center())
	await _frames(2)
	_check(_k._mg == null, "no mini-game for a batch")
	if not await _wait_card(3000, "result card after the batch"):
		_finish()
		return
	_check(_count(gs.data, key) == jars1 + 2, "batch x2 makes two jars")
	_check(energy - int(gs.data.energy) == Kitchen.energy_cost("stir_pot"), "batch costs one cook's energy")
	var best := true
	for item in gs.data.inbox:
		if item.kind == "product" and item.key == key and int(item.q) != 3:
			best = false
	_check(best, "every jar at the best quality (3)")
	_k._card._on_close()
	await _frames(4)

	# --- 3. Mastered badge in the book
	var book: Node = load("res://ui/book/book.gd").open()
	await _frames(6)
	var keys: Array = book._variant_keys()
	var at := keys.find(key)
	for i in floori(at / float(Book.VARIANTS_PER_PAGE)):
		book._flip(1)
	await _frames(6)
	_check(_has_badge(book), "book shows the Mastered badge")
	_shot("kitchen_p1b_book")
	book.close_book()
	await _frames(4)

	# --- 4. knead (bread loaf, pie in fruit tones) and the press bottle, each alone (no kitchen HUD over them)
	_k.queue_free()
	await _frames(4)
	await _knead("bread", ["83571e", "c58845", "e5bd7f"], "kitchen_p1b_mg_bread")
	await _knead("pie", ProductGen.describe(ProductGen.make_key("pie", [apple], ""), gs.data.varieties).appearance.fill, "kitchen_p1b_mg_pie")
	var press: Node = (load("res://minigames/press/press.tscn") as PackedScene).instantiate()
	root.add_child(press)
	var jdesc := ProductGen.describe(ProductGen.make_key("juice", [apple], ""), gs.data.varieties)
	press.start({"seed": 7, "recipe": "juice", "desc": jdesc, "autoplay": true})
	await create_timer(9.0).timeout
	_check(press.fill_tones[1] == Color.html(String(jdesc.appearance.fill[1])), "press reads the three fill tones")
	_shot("kitchen_p1b_mg_press")
	press.queue_free()
	await _frames(2)
	_finish()


## Starts knead alone for `recipe`, skips to part 2, hits half the dots, shoots, then lets it finish.
func _knead(recipe: String, fill: Array, shot: String) -> void:
	var mg: Node = (load("res://minigames/knead/knead.tscn") as PackedScene).instantiate()
	root.add_child(mg)
	var result := {}
	mg.finished.connect(func(r: Dictionary) -> void: result.merge(r))
	mg.start({"seed": 7, "recipe": recipe, "desc": {"appearance": {"fill": fill}}, "knead_time": 1.0, "trace_time": 3.0})
	var t0 := Time.get_ticks_msec()
	while int(mg.phase) != KNEAD_TRACE and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_check(int(mg.phase) == KNEAD_TRACE, "%s reaches part 2" % recipe)
	_check(mg.bread == (recipe == "bread"), "%s variant" % recipe)
	for i in 6:
		mg._check_hits(mg.points[i], mg.points[i])
	await _frames(10)
	_shot(shot)
	if recipe == "bread":  # trace the rest: the loaf gets its full length and all three score marks
		for i in mg.points.size():
			mg._check_hits(mg.points[i], mg.points[i])
		await _frames(10)
		_check(int(mg.phase) == KNEAD_DONE and int(mg.trace_stars) == 3, "every dot hit ends part 2 with 3 stars")
		_shot(shot + "_done")
	var t1 := Time.get_ticks_msec()
	while result.is_empty() and Time.get_ticks_msec() - t1 < 9000:
		await process_frame
	_check(int(result.get("stars", 0)) >= 1, "%s knead finished: %s" % [recipe, result])
	if is_instance_valid(mg):
		mg.queue_free()
	await _frames(2)


func _has_badge(n: Node) -> bool:
	if n.get_class() == "Control" and n.get("text") == tr("UI_MASTERY_BADGE"):
		return (n as Control).is_visible_in_tree()
	for c in n.get_children():
		if _has_badge(c):
			return true
	return false


func _count(d: Dictionary, key: String) -> int:
	var n := 0
	for item in d.inbox:
		if item.kind == "product" and item.key == key:
			n += 1
	return n


func _wait_card(ms: int, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while _k._card == null and Time.get_ticks_msec() - t0 < ms:
		await process_frame
	await _frames(20)
	return _check(_k._card != null, what)


func _finish() -> void:
	print("KITCHEN P1B SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)


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
