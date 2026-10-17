extends SceneTree
## Smoke shot (FESTIVAL): plays the whole Harvest Festival from the title menu, the way a juror would, through the
## scenes' own handlers (what a click calls): the start card, Mia and Leo in the garden, then the six steps:
##   1. the forest: the marker over the rare tree, Granny walks up and shakes it,
##   2. the stove: a jam of the rare fruit (stir mini-game, ended with 3 stars) -> "New recipe!",
##   3. the press: a juice of the inbox apples,
##   4. the pantry: the new jam dragged into the room shelf's gap -> 3 stars,
##   5. the market: fill the stall, open it, the parade, the end card,
##   6. the garden mailbox: Mia's thank-you letter with her drawing,
## then the end card (Keep playing hides it; Back to title returns to the title). The player's own save
## (user://save.json) must be byte for byte the same afterwards.
## Shots: user://shots/festival_00_title.png, _01_start, _02_wave, _02_garden, _03_grow, _03_wild, _04_shake, _05_stir, _06_jam,
## _07_juice, _08_pantry, _09_market, _10_market_end, _11_letter, _12_end (+ "_tr" with -- --locale=tr).
##   godot --path game --audio-driver Dummy -s res://tests/smoke/festival_shot.gd   (about 60 s; exit 1 on a failed check)

const TRANSITION := "res://ui/transition/transition.gd"
const SAVE := "user://save.json"
const GAP := Vector2i(2, 3)

var _gs: Node
var _fail := 0
var _suffix := ""
var _save_before := ""
var _had_save := false


func _initialize() -> void:
	_gs = root.get_node("GameState")
	if "--locale=tr" in OS.get_cmdline_user_args():
		GameSettings.apply_language("tr")
		_suffix = "_tr"
	_had_save = FileAccess.file_exists(SAVE)
	_save_before = FileAccess.get_file_as_string(SAVE) if _had_save else ""
	_run()


func _run() -> void:
	await process_frame
	# --- title: the Harvest Festival button
	var title := (load("res://scenes/title/title.tscn") as PackedScene).instantiate()
	root.add_child(title)
	current_scene = title
	root.get_node("Router").current = "title"
	await _frames(10)
	var btn: Button = title.get_node("%Festival")
	_check(btn != null and btn.visible and not btn.disabled, "Harvest Festival button on the title menu")
	_shot("festival_00_title")
	title._on_festival()
	if not await _until(func() -> bool: return _scene_id() == "garden" and _festival_card() != null, 8000):
		_check(false, "garden with the start card")
		_finish()
		return
	await _frames(20)
	var d: Dictionary = _gs.data
	_check(bool(d.flags.get("temp", false)) and TodoRules.is_festival(d), "festival loaded as a temporary game")
	_check(String(_festival_card().mode) == "start", "start card shows in the garden")
	_shot("festival_01_start")
	_festival_card()._choose("go")
	await _frames(4)
	_check(_festival_card() == null, "Let's go closes the start card")
	var note := get_first_node_in_group("granny_todo")
	_check(note != null and note.is_open(), "the festival note opens with all six steps")
	var garden := current_scene
	var kids := garden.get_node_or_null("Objects/Grandkids")
	_check(kids != null and kids.kids.size() == 2, "Mia and Leo are in the garden")
	await _seconds(0.5)
	_check(kids != null and kids._greeted.values().has(true), "a grandchild waves at Granny once the card is gone")
	_shot("festival_02_wave")
	_check(_todo_step() == "f_shake", "the note starts at: shake the rare tree")
	var glow: Variant = garden.call("_todo_spot")
	_check(glow != null and String(glow.kind) == "gate", "the gate glows for the forest step")
	await _seconds(2.5)
	_shot("festival_02_garden")

	# --- 1. the rare tree
	load(TRANSITION).go("wild", {"biome": "forest"})
	await _until(func() -> bool: return _scene_id() == "wild" and _ready_scene() and current_scene.get("granny") != null, 6000)
	await _frames(10)
	_check(_growing(), "the forest grows from its seed first (FIRST-60)")
	await _seconds(1.2)
	_shot("festival_03_grow")
	await _until(func() -> bool: return not _growing(), 10000)
	await _frames(20)
	var w := current_scene
	var f: Dictionary = TodoRules.festival(_gs.data)
	var tree_obj: Node2D = w.view.find("fruit_tree", int(f.tree))
	_check(tree_obj != null, "the rare tree is on the map")
	var marker: Node2D = w.view.fx.get_node_or_null("FestivalMarker")
	_check(marker != null, "a marker hangs over the rare tree")
	_shot("festival_03_wild")
	if tree_obj != null:
		w.granny.approach(tree_obj.cell, w._use.bind(tree_obj))
	await _seconds(1.6)
	_shot("festival_03_wild_walk")
	await _until(func() -> bool: return _done("f_shake"), 15000)
	_check(_done("f_shake"), "step 1: the rare tree shaken")
	await _seconds(0.6)
	_shot("festival_04_shake")
	w._exit()
	await _until(func() -> bool: return _scene_id() == "garden", 6000)
	await _frames(10)

	# --- 2. jam of the rare fruit at the stove
	load(TRANSITION).go("kitchen")
	await _until(func() -> bool: return _scene_id() == "kitchen" and _ready_scene(), 6000)
	await _frames(20)
	var k := current_scene
	_check(String(k.get("_glow")) == "stove", "the stove glows for the jam step (%s)" % k.get("_glow"))
	k._on_spot("stove")
	await _frames(6)
	var panel: Node = k._panel
	panel._select_recipe("jam")
	await _frames(2)
	var rare := String(f.rare)
	_check(panel._fits("main", rare) and int(panel.fresh_stock(_gs.data).get(rare, 0)) >= 3, "the rare fruit is in the kitchen")
	panel._pick(rare, panel)
	await _frames(4)
	panel._on_cook()
	await _until(func() -> bool: return k._mg != null, 3000)
	await _seconds(1.5)
	_shot("festival_05_stir")
	if k._mg != null:
		k._mg.finished.emit({"stars": 3})
	await _until(func() -> bool: return k._card != null, 3000)
	await _seconds(1.2)
	_check(k._card != null and k._card._banner.visible, "New recipe! on the result card")
	_check(_done("f_jam"), "step 2: a jam never made")
	_shot("festival_06_jam")
	k._card._on_close()
	await _frames(10)

	# --- 3. juice at the press
	_check(String(k.get("_glow")) == "press", "the press glows for the juice step (%s)" % k.get("_glow"))
	k._on_spot("press")
	await _frames(6)
	panel._select_recipe("juice")
	await _frames(2)
	var apple := ""
	var stock: Dictionary = panel.fresh_stock(_gs.data)
	var ids: Array = stock.keys()
	ids.sort()
	for vid in ids:
		if State.type_of_variety(String(vid)) == "apple" and panel._fits("main", vid) and int(stock[vid]) >= 4:
			apple = String(vid)
	panel._pick(apple, panel)
	await _frames(4)
	panel._on_cook()
	await _until(func() -> bool: return k._mg != null, 3000)
	await _seconds(1.0)
	if k._mg != null:
		k._mg.finished.emit({"stars": 2})
	await _until(func() -> bool: return k._card != null, 3000)
	await _seconds(0.8)
	_check(_done("f_juice"), "step 3: a juice pressed")
	_shot("festival_07_juice")
	k._card._on_close()
	await _frames(10)

	# --- 4. the pantry: the new jam into the gap
	load(TRANSITION).go("pantry")
	await _until(func() -> bool: return _scene_id() == "pantry" and _ready_scene(), 6000)
	await _frames(20)
	var p := current_scene
	var board: Control = p.board
	var inbox: Array = _gs.data.inbox
	var index := -1
	for i in inbox.size():
		if String(inbox[i].get("kind", "")) == "product" and String(inbox[i].key).begins_with("jam|" + rare):
			index = i
	_check(index >= 0, "the new jam waits in the pantry inbox")
	if index >= 0:
		var item: Dictionary = inbox[index]
		var start: Vector2 = p.inbox_view.get_global_transform_with_canvas() * Vector2(p.inbox_view.slot_rect(index).get_center())
		board.begin_hold(item, {"where": "inbox", "index": index}, start)
		await _frames(2)
		board.move_hold_to(Vector2(board.cell_rect(GAP).get_center()))
		await _frames(4)
		board.drop_held()
	await _seconds(1.0)
	_check(_done("f_pantry"), "step 4: the pantry at 3 stars (%s)" % [PantryRules.state_stars(_gs.data).rules])
	_shot("festival_08_pantry")

	# --- 5. the market
	load(TRANSITION).go("market")
	await _until(func() -> bool: return _scene_id() == "market" and _ready_scene(), 6000)
	await _frames(20)
	var m := current_scene
	m._on_fill()
	await _frames(6)
	m._on_open()
	await _frames(4)
	_check(_done("f_market"), "step 5: sold at the market")
	await _seconds(4.0)
	_shot("festival_09_market")
	m._finish()
	await _seconds(0.8)
	_shot("festival_10_market_end")
	load(TRANSITION).go("garden")
	await _until(func() -> bool: return _scene_id() == "garden" and _ready_scene(), 6000)
	await _frames(30)

	# --- 6. Mia's letter
	garden = current_scene
	_check(_todo_step() == "f_letter", "the note points at Mia's letter (%s)" % _todo_step())
	var mailbox: Variant = garden.call("find_spot", "mailbox")
	var spot: Variant = garden.call("_todo_spot")
	_check(spot != null and spot == mailbox, "the mailbox glows for the letter step")
	garden._use(mailbox)
	await _seconds(1.0)
	var ui := get_first_node_in_group("letters_ui")
	_check(ui != null and Letters.find_letter(_gs.data, int(f.letter)).get("read", false), "Mia's letter is open")
	_check(_festival_card() == null, "no end card over the letter")
	_shot("festival_11_letter")
	if ui != null:
		ui.close()
	await _frames(4)
	_check(_done("f_letter"), "step 6: Mia's letter read")

	# --- the end card
	await _until(func() -> bool: return _festival_card() != null, 6000)
	await _seconds(0.8)
	var card := _festival_card()
	_check(card != null and String(card.mode) == "end", "the end card after the six steps")
	_shot("festival_12_end")
	if card != null:
		card._choose("keep")
		await _frames(6)
		_check(_festival_card() == null, "Keep playing closes the end card")
	var director := get_first_node_in_group("festival")
	if director != null:
		director._show("end")
		await _frames(4)
		_festival_card()._choose("title")
	await _until(func() -> bool: return _scene_id() == "title", 6000)
	await _frames(10)
	_check(_scene_id() == "title", "Back to title returns to the title")
	_check(get_first_node_in_group("festival") == null, "the festival director is gone on the title")
	var after := FileAccess.get_file_as_string(SAVE) if FileAccess.file_exists(SAVE) else ""
	var same := FileAccess.file_exists(SAVE) == _had_save and after == _save_before
	if not same:
		# user:// is shared by every checkout: a soak bot elsewhere may write its own game meanwhile. Then at least the
		# festival must not be in it.
		var parsed: Variant = JSON.parse_string(after) if after != "" else {}
		same = typeof(parsed) == TYPE_DICTIONARY and not TodoRules.is_festival(parsed)
		print("note: user://save.json changed during the run (another game process?), festival data in it: %s" % [not same])
	_check(same, "the player's own save is unchanged")
	_finish()


# ---------------------------------------------------------------- helpers

func _scene_id() -> String:
	return String(root.get_node("Router").current)


func _ready_scene() -> bool:
	return current_scene != null and current_scene.is_node_ready() and not bool(load(TRANSITION).is_busy())


## The FIRST-60 world-grow overlay is on the wild scene.
func _growing() -> bool:
	if current_scene == null:
		return false
	for c in current_scene.get_children():
		var sc: Variant = c.get_script()
		if sc is Script and String((sc as Script).resource_path).ends_with("world_grow.gd"):
			return true
	return false


func _festival_card() -> Node:
	var f := get_first_node_in_group("festival")
	if f == null:
		return null
	var c: Variant = f.get("_card")
	return c if c is Node and is_instance_valid(c) else null


func _todo_step() -> String:
	var t := get_first_node_in_group("granny_todo")
	return String(t.get("_step")) if t != null else ""


func _done(step: String) -> bool:
	return TodoRules.is_done(TodoRules.bits_of(_gs.data), step)


func _until(cond: Callable, ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()) and Time.get_ticks_msec() - t0 < ms:
		await process_frame
	return bool(cond.call())


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> bool:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fail += 1
	return ok


func _shot(shot_name: String) -> void:
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("%s/%s%s.png" % [dir, shot_name, _suffix])
	print("saved ", ProjectSettings.globalize_path("%s/%s%s.png" % [dir, shot_name, _suffix]))


func _finish() -> void:
	print("FESTIVAL SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)
