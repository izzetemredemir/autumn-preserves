extends SceneTree
## Smoke shot (GD-KITCHEN): runs the kitchen alone (throwaway game + debug inventory), cooks jam on the stove
## (stir_pot plays itself through the ctx autoplay hook) and pickles at the jar counter (pack_jar result is
## emitted by this script), checks both jars reached the inbox, then keyboard open/close, the chutney vegetable
## slot's Change picker with real mouse clicks (JURY-STOVE; Esc closes the picker first) and a night in bed. ART-GRANNY: Granny stands at the painting's scale (44x88, feet at
## y 175-185), her doze chair sits under the hotspots, and a click on her skirt reaches the stove. Saves:
##   user://shots/kitchen.png        room after both cooks (waiting jar on the sill, To-Do glow, captions)
##   user://shots/kitchen_panel.png  stove panel with a filled slot and an add-in
##   user://shots/kitchen_card.png   result card after the jam
##   user://shots/kitchen_mg.png     the jar packing mini-game running inside the kitchen
## godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/kitchen_shot.gd
## (not headless; wrap it in a timeout). Autoload-using classes (GrannyTodo) are loaded by path.

var _k: Control
var _fail := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var todo_script: GDScript = load("res://ui/tutorial/granny_todo.gd")
	_k = (load("res://scenes/kitchen/kitchen.tscn") as PackedScene).instantiate()
	_k.debug_ctx = {"autoplay": true, "duration": 3.0}
	root.get_node("Router").current = "kitchen"  # the To-Do note hides outside game scenes
	root.add_child(_k)
	todo_script.ensure()
	await _frames(12)
	# --- ART-GRANNY: Granny at the painting's scale, feet on the floor between the stove and the bench
	var g: TextureRect = _k._granny
	_check(g != null and g.size == Vector2(44, 88) and g.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Granny at kitchen scale (44x88), the mouse passes through her")
	_check(g != null and int(g.position.y) + 86 >= 175 and int(g.position.y) + 86 <= 185, "her feet stand at y 175-185")
	_check(_k._doze.size == Vector2(58, 85) and _k._doze.get_index() < _k._spots.stove.get_index(),
		"doze chair at her scale, under the hotspots and captions")
	var gs: Node = root.get_node("GameState")
	var d: Dictionary = gs.data
	var inbox_before: int = d.inbox.size()

	# --- jam at the stove: pick the first fruit variety with 4+, add cinnamon, cook
	_k._on_spot("stove")
	await _frames(4)
	var panel: Control = _k._panel
	var fruit := _first_fitting(panel, "main")
	panel._pick(fruit, panel)
	panel._select_addin("cinnamon")
	await _frames(14)
	_shot("kitchen_panel")
	panel._on_cook()
	await _frames(2)
	_check(_k._mg != null, "stir_pot launched")
	var t0 := Time.get_ticks_msec()
	while _k._card == null and Time.get_ticks_msec() - t0 < 20000:  # 3 s ready + 3 s play + 2.5 s hold
		await process_frame
	if not _check(_k._card != null, "result card after jam"):
		quit(1)
		return
	await _frames(30)
	_shot("kitchen_card")
	_check(_has_product(gs.data, "jam|"), "jam jar in the inbox")
	_k._card._on_close()
	await _frames(4)

	# --- pickles at the jar counter: mini-game runs, this script ends it with 2 stars
	_k._on_spot("counter")
	await _frames(4)
	var veg := _first_fitting(panel, "main")
	panel._pick(veg, panel)
	await _frames(2)
	panel._on_cook()
	await _frames(30)
	_check(_k._mg != null, "pack_jar launched")
	_shot("kitchen_mg")
	_k._mg.finished.emit({"stars": 2, "fill": 0.8})
	await _frames(6)
	if not _check(_k._card != null, "result card after pickles"):
		quit(1)
		return
	_check(_has_product(gs.data, "pickle|"), "pickle jar in the inbox")
	_k._card._on_close()
	await _frames(20)
	_check(_waiting_jars(gs.data) >= 1, "waiting pickle jar listed for the sill")
	_shot("kitchen")

	# --- keyboard: focus + interact opens the stove, cancel closes it
	_k._spots.stove.grab_focus()
	_action("interact")
	await _frames(4)
	_check(panel.visible and panel.station == "stir_pot", "E on the focused stove opens the panel")
	_check(root.gui_get_focus_owner() == panel._cook, "focus starts on Cook (Enter cooks)")
	# chutney (JURY-STOVE): a click on the vegetable slot opens its Change picker, a click on a row fills the slot
	panel._select_recipe("chutney")
	await _frames(4)
	var veg2 := _first_fitting(panel, "second", 2, String(panel.picks.second))
	await _click(panel._slots.second.button.get_global_rect().get_center())
	_check(panel._picker.visible, "a click on the slot opens the picker")
	if veg2 != "" and panel._rows.has(veg2):
		panel._scroll.ensure_control_visible(panel._rows[veg2])
		await _frames(2)
		await _click(panel._rows[veg2].get_global_rect().get_center())
	_check(panel.picks.second == veg2 and veg2 != "" and not panel._picker.visible, "a picker row fills the chutney vegetable slot")
	await _click(panel._slots.second.button.get_global_rect().get_center())
	_action("cancel")
	await _frames(4)
	_check(panel.visible and not panel._picker.visible, "Esc closes the picker first")
	_action("cancel")
	await _frames(4)
	_check(not panel.visible and _k._room_active, "Esc closes the panel")
	# a click on Granny's skirt reaches the stove behind her
	await _click(Vector2(78, 160))
	_check(panel.visible and panel.station == "stir_pot", "a click through Granny opens the stove")
	_action("cancel")
	await _frames(4)

	# --- bed: confirm, Night runs end_day, back in the kitchen on day 2
	var day0: int = int(gs.data.day)
	_k._on_spot("bed")
	await _frames(2)
	_check(_k._dialog.visible, "bed asks first")
	_k._on_sleep()
	await _frames(2)
	var night: Node = null
	for n in root.get_children():
		if n.has_signal("finished") and n.get("after_scene") != null:
			night = n
	_check(night != null, "Night started")
	t0 = Time.get_ticks_msec()
	while night != null and not night.get("_accepting") and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	if night != null:
		night._button.pressed.emit()
	t0 = Time.get_ticks_msec()
	while not _k._room_active and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_check(int(gs.data.day) == day0 + 1 and _k._room_active, "slept: day %d -> %d" % [day0, int(gs.data.day)])
	print("KITCHEN SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)


func _waiting_jars(d: Dictionary) -> int:
	return _k._waiting(d).size()


func _action(name: String) -> void:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	Input.parse_input_event(ev)


## Hover, press and release the left button at one point (viewport coordinates).
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
	await _frames(3)


## The first variety (by id) that fits the slot with `need` units, other than `but` when another one does.
func _first_fitting(panel: Control, which: String, need := 4, but := "") -> String:
	var stock: Dictionary = panel.fresh_stock(root.get_node("GameState").data)
	var ids: Array = stock.keys()
	ids.sort()
	var found := ""
	for vid in ids:
		if panel._fits(which, vid) and int(stock[vid]) >= need:
			if vid != but:
				return vid
			found = vid
	return found


func _has_product(d: Dictionary, prefix: String) -> bool:
	for item in d.inbox:
		if item.kind == "product" and String(item.key).begins_with(prefix):
			return true
	return false


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
