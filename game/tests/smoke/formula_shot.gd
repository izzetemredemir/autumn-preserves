extends SceneTree
## Smoke shot (FORMULA-KITCHEN): the kitchen alone (throwaway game, debug inventory + a jam in the pantry and honey).
##   1. English: stove -> Invent -> apple, pear, the jam, a walnut and honey picked from the grid -> live preview
##      (name, notes, New!, taste bars, stars, value) -> Cook -> stir mini-game -> result card "New creation!" ->
##      the invention in the inbox and state.formulas -> the book's Creations tab.
##   2. Turkish: the kitchen built again, the Invent panel with another mix (preview, "Yeni!"), Esc closes the Invent
##      panel first (the cook panel comes back, the pause menu stays shut), the Creations tab.
## Saves user://shots/formula_panel_en.png, formula_card_en.png, formula_book_en.png, formula_panel_tr.png,
## formula_book_tr.png.
## godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/formula_shot.gd
## (not headless; wrap it in a timeout, about 30 s).

var _k: Control
var _fail := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	GameSettings.apply_language("en")
	root.get_node("Router").current = "kitchen"
	await _kitchen()
	var gs: Node = root.get_node("GameState")
	var d: Dictionary = gs.data
	d.day = 5
	d.energy = 80
	var apple := DevTools.first_variety(d, "apple")
	var pear := DevTools.first_variety(d, "pear")
	var crab := DevTools.first_variety(d, "crabapple")
	var jam := ProductGen.make_key("jam", [apple], "")
	d.pantry.items.append({"item": State.product(jam, 2, 0), "x": 0, "y": 4, "rot": 0})
	d.cupboard["honey"] = 2
	gs.notify(PackedStringArray(["inbox", "pantry", "cupboard"]))
	await _frames(4)

	# --- 1. English: invent, cook, card, book
	var fx: Control = await _open_invent()
	if fx == null:
		_finish()
		return
	_check(fx._tabs.keys() == Kitchen.formula_methods(d), "method tabs = unlocked stations: %s" % [fx._tabs.keys()])
	_check(fx.method == "stir_pot", "opens on the stove's method")
	await _pick(fx, [apple, pear, jam, "walnut", "honey"])
	_check(fx.components == [apple, pear, jam, "walnut"] and fx.addins == ["honey"], "picked %s + %s" % [fx.components, fx.addins])
	var key := FormulaGen.make_key("stir_pot", [apple, pear, jam, "walnut"], ["honey"])
	var desc := ProductGen.describe(key, d.varieties)
	_check(fx._ok and fx._feedback.text == tr("KITCHEN_READY"), "ready: %s" % fx._feedback.text)
	_check(fx._name.visible and fx._name.text == String(desc.name), "preview name: %s" % fx._name.text)
	_check(fx._new_tag.visible and fx._jar.visible and fx._chart.visible, "New!, jar and taste bars")
	_check(fx._value.text == tr("UI_FORMULA_VALUE") % [ProductGen.value(key, d.varieties, 1), ProductGen.value(key, d.varieties, 3)],
		"value range: %s" % fx._value.text)
	await _frames(14)
	var over := _overflows(fx)
	_check(over.is_empty(), "Invent panel text fits %s" % [over])
	_shot("formula_panel_en")
	print("preview: %s | %s | %s" % [desc.name, desc.taste, fx._notes.text])
	# a click on a filled slot takes it out again; the cell puts it back
	await _click(fx._slots[1].button.get_global_rect().get_center())
	_check(fx.components == [apple, jam, "walnut"], "slot click takes the pear out: %s" % [fx.components])
	await _pick(fx, [pear])
	_check(FormulaGen.make_key(fx.method, fx.components, fx.addins) == key, "same key in any pick order")
	var energy := int(d.energy)
	await _click(fx._cook.get_global_rect().get_center())
	await _frames(2)
	_check(_k._mg != null, "stir mini-game launched")
	if _k._mg == null:
		_finish()
		return
	_k._mg.finished.emit({"stars": 3})
	var t0 := Time.get_ticks_msec()
	while _k._card == null and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	await _frames(30)
	d = gs.data
	_check(_k._card != null, "result card")
	if _k._card != null:
		_check(_k._card._banner.visible and _k._card._banner.text == tr("UI_FORMULA_NEW"), "banner: %s" % _k._card._banner.text)
		_check(_k._card._name.text == String(desc.name), "card name")
	_check(d.formulas.has(key) and int(d.formulas[key].made) == 1, "state.formulas counts it")
	_check(d.inbox.any(func(it: Dictionary) -> bool: return String(it.get("key", "")) == key), "the invention went to the inbox")
	_check(int(d.energy) == energy - Kitchen.energy_cost("stir_pot"), "a stove cook's energy")
	_check(not d.pantry.items.any(func(e: Dictionary) -> bool: return String(e.item.get("key", "")) == jam), "the jam was used")
	_shot("formula_card_en")
	if _k._card != null:
		_k._card._on_close()
	await _frames(6)
	await _book("formula_book_en", String(desc.name))

	# --- 2. Turkish: the panel again with another mix, Esc, the book
	_k.queue_free()
	await _frames(4)
	GameSettings.apply_language("tr")
	await _kitchen()
	fx = await _open_invent()
	if fx == null:
		_finish()
		return
	_check(_k._panel._title.text == tr("KITCHEN_STOVE"), "Turkish kitchen")
	await _pick(fx, [crab, pear, "walnut", "cinnamon"])
	var key_tr := FormulaGen.make_key("stir_pot", [crab, pear, "walnut"], ["cinnamon"])
	var name_tr := ProductGen.product_name(key_tr, gs.data.varieties, "tr")
	_check(fx._ok and fx._name.text == name_tr and fx._new_tag.visible, "Turkish preview: %s (%s)" % [fx._name.text, fx._feedback.text])
	await _frames(14)
	over = _overflows(fx)
	_check(over.is_empty(), "Turkish Invent panel text fits %s" % [over])
	_shot("formula_panel_tr")
	print("preview tr: %s | %s" % [name_tr, fx._notes.text])
	_key(KEY_ESCAPE)
	await _frames(6)
	_check(not fx.visible and _k._panel.visible, "Esc closes the Invent panel, the cook panel is back")
	_check(not PauseMenu.is_open(), "the pause menu stays shut")
	_key(KEY_ESCAPE)
	await _frames(6)
	_check(not _k._panel.visible and not PauseMenu.is_open(), "the next Esc closes the cook panel")
	await _book("formula_book_tr", ProductGen.product_name(key, gs.data.varieties, "tr"))
	GameSettings.apply_language("en")
	_finish()


func _kitchen() -> void:
	_k = (load("res://scenes/kitchen/kitchen.tscn") as PackedScene).instantiate()
	root.add_child(_k)
	await _frames(12)


## Stove -> the cook panel's Invent button -> the Invent panel (null when something is missing).
func _open_invent() -> Control:
	await _click(_k._spots.stove.get_global_rect().get_center())
	await _frames(4)
	var panel: Control = _k._panel
	var invent: Button = null
	for c in panel.get_children():
		if c is Button and (c as Button).text == tr("UI_FORMULA_INVENT"):
			invent = c
	_check(panel.visible and invent != null and invent.is_visible_in_tree(), "Invent button on the cook panel")
	if invent == null:
		return null
	await _click(invent.get_global_rect().get_center())
	await _frames(6)
	var fx: Control = _k._fx_panel
	_check(fx.visible and not panel.visible, "the Invent panel takes the cook panel's place")
	return fx if fx.visible else null


func _pick(fx: Control, ids: Array) -> void:
	for id: String in ids:
		if not fx._cells.has(id):
			_check(false, "grid offers %s" % id)
			continue
		fx._scroll.ensure_control_visible(fx._cells[id])
		await _frames(2)
		await _click(fx._cells[id].get_global_rect().get_center())
		await _frames(2)


## The book's Creations tab with the invention `title` on it.
func _book(shot: String, title: String) -> void:
	var book: Node = load("res://ui/book/book.gd").open()
	await _frames(6)
	book._set_tab(2)
	await _frames(8)
	_check(book._tab_btns[2].text == tr("UI_FORMULA_TAB"), "Creations tab: %s" % book._tab_btns[2].text)
	_check(_has_text(book, title), "the book lists %s" % title)
	var over := _overflows(book)
	_check(over.is_empty(), "Creations page text fits %s" % [over])
	_shot(shot)
	book.close_book()
	await _frames(4)


## Labels and buttons under `n` whose text needs more room than they have (the UI audit's rule).
func _overflows(n: Node, out: Array = []) -> Array:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return out
	if (n is Label or n is Button) and String(n.get("text")) != "" and not _in_scroll(n):
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
		if c is Label and (c as Label).max_lines_visible > 0:
			need.y = minf(need.y, font.get_height(fs) * (c as Label).max_lines_visible)
		if need.x > avail.x + 0.5 or need.y > avail.y + 0.5:
			out.append("%s needs %s has %s" % [n.get("text"), need, avail])
	for ch in n.get_children():
		_overflows(ch, out)
	return out


func _in_scroll(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _has_text(n: Node, t: String) -> bool:
	if n is Label and (n as Label).text == t and (n as Label).is_visible_in_tree():
		return true
	for c in n.get_children():
		if _has_text(c, t):
			return true
	return false


func _finish() -> void:
	print("FORMULA SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		root.push_input(ev, true)


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
