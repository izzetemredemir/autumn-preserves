extends SceneTree
## Smoke shot (KITCHEN-P1C): the kitchen alone (throwaway game, debug inventory) with four reply letters and all six
## family recipes unlocked.
##   1. The wall: the three newest reply drawings in frames left of the window; a click opens the newest big.
##   2. Stove -> "Family recipes" -> Granny's Quince Butter with its fixed cinnamon -> stir -> result card (gold label).
##   3. The book's family section (heading, gold jars, who sent each) and the family jar's "How it was made" card.
##   4. Day 95: 10 s idle -> Granny dozes in her chair with a "z" bubble; a mouse move wakes her. Day 50: no doze.
## Saves user://shots/kitchen_p1c_wall.png, kitchen_p1c_drawing.png, kitchen_p1c_panel.png, kitchen_p1c_card.png,
## kitchen_p1c_book.png, kitchen_p1c_how.png, kitchen_p1c_doze.png.
## godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/kitchen_p1c_shot.gd
## (not headless; wrap it in a timeout, about 30 s).

var _k: Control
var _fail := 0


func _initialize() -> void:
	GameSettings.apply_language("tr" if "--locale=tr" in OS.get_cmdline_user_args() else "en")  # UI-COMPACT: shots per language
	_run()


func _run() -> void:
	await process_frame
	_k = (load("res://scenes/kitchen/kitchen.tscn") as PackedScene).instantiate()
	root.get_node("Router").current = "kitchen"
	root.add_child(_k)
	await _frames(12)
	var gs: Node = root.get_node("GameState")
	var d: Dictionary = gs.data
	d.day = 12
	d.energy = 80
	var quince := DevTools.first_variety(d, "quince")
	d.inbox.append(State.fresh(quince, 8, 6))
	d.cupboard["cinnamon"] = 2
	d.cupboard["sugar"] = int(d.cupboard.get("sugar", 0)) + 4
	d.cupboard["jar"] = int(d.cupboard.get("jar", 0)) + 4
	var l := Letters.ensure(d)
	for id: String in Kitchen.family_ids():
		l.unlocked_recipes.append(id)
	l.love = {"mia": 10, "leo": 10}
	var apple := DevTools.first_variety(d, "apple")
	var cucumber := DevTools.first_variety(d, "cucumber")
	var parcels := [
		["mia", [ProductGen.make_key("jam", [apple], ""), ProductGen.make_key("fruit_butter", [apple], "cinnamon")], false],
		["leo", [ProductGen.make_key("pickle", [cucumber], "chili")], true],
		["mia", [ProductGen.make_key("grannys_quince_butter", [quince], "cinnamon")], true],
		["leo", [ProductGen.make_key("chili_pickles", [cucumber], "chili"), ProductGen.make_key("pickle", [cucumber], "")], false],
	]
	for p: Array in parcels:
		_reply(d, p[0], p[1], p[2])
	gs.notify(PackedStringArray(["letters"]))
	await _frames(6)

	# --- 1. drawings on the wall
	var wall: Control = _k._wall
	_check(wall.frame_count() == 3, "three drawings on the wall (%d)" % wall.frame_count())
	var newest: Button = wall.newest()
	_check(newest != null and newest.position == Vector2(wall.SPOTS[0]), "the newest hangs in front")
	var on_wall := true
	for f: Control in wall._frames:
		var r := Rect2(f.position, f.size)
		on_wall = on_wall and r.position.y >= 32.0 and r.end.y <= 86.0 and r.position.x >= 88.0 and r.end.x <= 127.0
	_check(on_wall, "frames on the stone wall: below the HUD, above the bench, left of the curtain")
	await _move(newest.get_global_rect().get_center())
	await _frames(6)
	_check(_k._message.text == tr("UI_FAMILY_DRAWING_HINT") % "Leo", "hover names the child: %s" % _k._message.text)
	_shot("kitchen_p1c_wall")
	await _click(newest.get_global_rect().get_center())
	await _frames(6)
	_check(_k._viewer != null, "a click opens the drawing big")
	_shot("kitchen_p1c_drawing")
	await _click(Vector2(20, 20))
	await _frames(4)
	_check(_k._viewer == null and _k._room_active, "a click hangs it back")

	# --- 2. a family recipe at the stove
	await _click(_k._spots.stove.get_global_rect().get_center())
	await _frames(4)
	var panel: Control = _k._panel
	_check(panel.visible and panel._family_btn.visible, "stove shows the Family recipes button")
	_check(not panel.family and not panel._tabs.has("grannys_quince_butter"), "base tabs first")
	await _click(panel._family_btn.get_global_rect().get_center())
	await _frames(4)
	_check(panel.family and panel._tabs.keys() == ["grannys_quince_butter", "blackberry_honey_jam", "crabapple_jelly",
		"pepper_relish"], "four family tabs at the stove: %s" % [panel._tabs.keys()])
	_check(panel.recipe == "grannys_quince_butter", "first family tab picked")
	_check(panel.addin == "cinnamon" and panel._addin_buttons.keys() == ["cinnamon"], "the add-in row holds only cinnamon")
	await _click(panel._slots.main.button.get_global_rect().get_center())  # the quince slot's Change picker
	if panel._rows.has(quince):
		panel._scroll.ensure_control_visible(panel._rows[quince])
		await _frames(2)
		await _click(panel._rows[quince].get_global_rect().get_center())
	_check(panel.picks.main == quince and panel._ok, "quince picked, ready: %s" % panel._feedback.text)
	await _frames(14)
	var over := _overflows(panel)
	_check(over.is_empty(), "family stove panel text fits %s" % [over])
	_shot("kitchen_p1c_panel")
	await _click(panel._cook.get_global_rect().get_center())
	await _frames(2)
	_check(_k._mg != null, "stir mini-game launched")
	if _k._mg == null:
		_finish()
		return
	_k._mg.finished.emit({"stars": 3})
	var t0 := Time.get_ticks_msec()
	while _k._card == null and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	await _frames(24)
	var key := ProductGen.make_key("grannys_quince_butter", [quince], "cinnamon")
	_check(_k._card != null and gs.data.book.variants.has(key), "result card, family variant in the book")
	var desc := ProductGen.describe(key, gs.data.varieties)
	_check(String(desc.name).begins_with("Granny's") and String(desc.name).length() <= 28, "name: %s" % desc.name)
	_check(String(desc.appearance.label_color) == ProductGen.FAMILY_LABEL, "gold label")
	_shot("kitchen_p1c_card")
	if _k._card != null:
		_k._card._on_close()
	await _frames(4)
	# the jar counter's family set: Leo's pickles and porcini
	await _click(_k._spots.counter.get_global_rect().get_center())
	await _frames(4)
	_check(panel._family_btn.visible and not panel.family, "counter opens on its base recipes")
	await _click(panel._family_btn.get_global_rect().get_center())
	await _frames(4)
	_check(panel._tabs.keys() == ["chili_pickles", "salted_porcini"], "counter family tabs: %s" % [panel._tabs.keys()])
	_check(panel.recipe == "chili_pickles" and panel.addin == "chili", "chili pickles takes its chili (%s)" % panel.addin)
	await _click(panel._tabs.salted_porcini.get_global_rect().get_center())
	await _frames(2)
	_check(panel.addin == "" and panel._addin_buttons.keys() == [""], "salted porcini takes no add-in")
	over = _overflows(panel)
	_check(over.is_empty(), "family counter panel text fits %s" % [over])
	_k._close_panel()
	await _frames(4)

	# --- 3. the book's family section and the How it was made card
	var book: Node = load("res://ui/book/book.gd").open()
	await _frames(6)
	while book._page < book._base_pages() and book._page < book._page_count() - 1:
		book._flip(1)
	await _frames(6)
	_check(_has_text(book, tr("UI_FAMILY_HEADING") % [6, 6]), "family heading 6/6")
	_check(_has_text(book, tr("LET_RECIPE_GRANNYS_QUINCE_BUTTER")), "Granny's Quince Butter listed")
	_check(_has_text(book, tr("UI_FAMILY_FROM") % ["Mia", 3]), "who sent it back")
	over = _overflows(book)
	_check(over.is_empty(), "family page text fits %s" % [over])
	_shot("kitchen_p1c_book")
	book._flip(1)
	await _frames(4)
	_check(_has_text(book, tr("LET_RECIPE_SALTED_PORCINI")), "second family page: Leo's recipes")
	over = _overflows(book)
	_check(over.is_empty(), "second family page text fits %s" % [over])
	book.open_how(key)
	await _frames(6)
	_check(_has_text(book._how, tr("UI_FAMILY_HOW_ADJ") % "Granny's"), "How it was made explains the family name")
	over = _overflows(book._how)
	_check(over.is_empty(), "How it was made text fits %s" % [over])
	_shot("kitchen_p1c_how")
	book.close_how()
	book.close_book()
	await _frames(4)

	# --- 4. the doze: only on hint days, after 10 s idle; any input wakes her
	d = gs.data
	d.day = 50
	_k._idle = 30.0
	await _frames(4)
	_check(not _k._doze.visible, "no doze on day 50")
	d.day = 95
	_k._idle = _k.DOZE_AFTER - 0.2
	await create_timer(0.6).timeout
	_check(_k._doze.visible and not _k._granny.visible, "day 95: dozing after 10 s idle")
	await create_timer(1.8).timeout  # the bubble's small z floats off
	_shot("kitchen_p1c_doze")
	await _move(Vector2(240, 200))
	await _frames(2)
	_check(not _k._doze.visible and _k._granny.visible, "a mouse move wakes her")
	_check(int(gs.data.day) == 95 and int(gs.data.energy) == int(d.energy), "looks only")
	_finish()


## A sent parcel and its reply letter (as Letters.night writes them).
func _reply(d: Dictionary, kid: String, keys: Array, care: bool) -> void:
	var l: Dictionary = d.letters
	var req_id := int(l.next_id)
	l.next_id = req_id + 1
	l.sent.append({"letter": req_id, "to": kid, "day": 3, "reply_day": 5, "keys": keys, "care": care, "hearts": 2,
		"unlocked": [], "replied": true})
	l.inbox.append({"id": int(l.next_id), "kind": "reply", "from": kid, "day": 5, "note": "LET_REPLY_%s_1" % kid.to_upper(),
		"care_note": "", "re": req_id, "care": care, "hearts": 2, "unlocked": [], "read": true})
	l.next_id = int(l.next_id) + 1


## Labels and buttons under `n` whose text needs more room than they have (the UI audit's rule, for screens the
## demo save never shows).
func _overflows(n: Node, out: Array = []) -> Array:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return out
	if (n is Label or n is Button) and String(n.get("text")) != "":
		var c := n as Control
		var font := c.get_theme_font("font")
		var fs := c.get_theme_font_size("font_size")
		var avail := c.size
		var width := -1.0
		if c is Label and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			width = c.size.x
		if c is Button:
			var sb := c.get_theme_stylebox("normal")
			avail -= Vector2(sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT), sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM))
		var need := font.get_multiline_string_size(String(n.get("text")), HORIZONTAL_ALIGNMENT_LEFT, width, fs)
		if need.x > avail.x + 0.5 or need.y > avail.y + 0.5:
			out.append("%s needs %s has %s" % [n.get("text"), need, avail])
	for ch in n.get_children():
		_overflows(ch, out)
	return out


func _has_text(n: Node, t: String) -> bool:
	if n is Label and (n as Label).text == t and (n as Label).is_visible_in_tree():
		return true
	for c in n.get_children():
		if _has_text(c, t):
			return true
	return false


func _finish() -> void:
	print("KITCHEN P1C SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)


func _move(at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	root.push_input(m, true)
	await process_frame


func _click(at: Vector2) -> void:
	await _move(at)
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
