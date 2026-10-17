extends SceneTree
## QA-FIX probes (docs/qa/soak.md findings 1-5), each on a throwaway game in memory (nothing saved):
##   card    a forced Mastered press cook (the real press with autoplay, then finished emitted early) closed with
##           bot-style mouse clicks at several moments of the card's play-in; and the race (the mini-game result
##           delivered twice): Continue must leave no card behind.
##   path    Granny at (28, 15) taps the door, the cat is put on the fourth cell of her path: she must re-path and
##           use the door; the wandering cat may not step on any cell of her remaining path.
##   pager   the town's Orders tab with one order rendered 5 times: no orphan nodes.
##   pantry  30 jars on the shelves and 6 waiting: a drop from the inbox, a move on the board and Auto-arrange, in ms.
##   market  the town's "Market today!" banner fades (Transition) into the market; frame times of Fill, Open and the
##           first 12 s of the parade (Engine.time_scale x2 as the soak).
##   godot --path game --audio-driver Dummy -s res://tests/smoke/qa_fix_probe.gd [-- --only=card,path,...]
## Windowed (frame times are real). Exit 1 when a check fails.

const AUTOPLAY := {"autoplay": true}
const TRANSITION_GD := "res://ui/transition/transition.gd"
const DROP_MS := 16.0
const PARADE_MS := 33.0

var _gs: Node
var _router: Node
var _mask := 0
var _checks := 0
var _fails := 0
var _only: PackedStringArray = []


func _initialize() -> void:
	_gs = root.get_node("GameState")
	_router = root.get_node("Router")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.trim_prefix("--only=").split(",")
	_run()


func _run() -> void:
	await process_frame
	if _want("card"):
		await _probe_card()
	if _want("path"):
		await _probe_path()
	if _want("pager"):
		await _probe_pager()
	if _want("pantry"):
		await _probe_pantry()
	if _want("market"):
		await _probe_market()
	print("PROBE qa_fix: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _want(s: String) -> bool:
	return _only.is_empty() or _only.has(s)


# ================================================================ 1. result card after a Mastered press cook

func _probe_card() -> void:
	_gs.start_temp(452)
	var d: Dictionary = _gs.data
	DevTools.unlock_p1(d)
	var apple := DevTools.first_variety(d, "apple")
	d.inbox.append(State.fresh(apple, 99, 6))
	d.cupboard["bottle"] = 50
	d.energy = 999
	_router.current = "kitchen"
	var k: Control = (load("res://scenes/kitchen/kitchen.tscn") as PackedScene).instantiate()
	root.add_child(k)
	current_scene = k
	await _frames(12)
	var key := Kitchen.product_key("juice", apple, "", "")
	Engine.time_scale = 2.0
	# the real press, autoplayed to the end, then the bot's click 22 frames after the card shows
	var delays := [22, 0, 1, 2, 4, 8, 14, 30, 60]
	for i in delays.size():
		d.book.variants[key] = {"best_q": 3, "best_stars": 3, "count": 2, "first_day": 1, "good": 2}
		d.energy = 999
		k.set("debug_ctx", AUTOPLAY.duplicate() if i == 0 else {})
		k.call("_open_panel", "press")
		k.call("_on_cook_requested", "juice", apple, "", "")
		var mg: Node = k.get("_mg")
		if mg == null:
			_check("card: the press mini-game starts (trial %d)" % i, false)
			break
		if i > 0:
			await _frames(5)
			mg.emit_signal("finished", {"stars": 3})
		if not await _until(func() -> bool: return k.get("_card") != null, 40000):
			_check("card: the result card shows after the press (trial %d)" % i, false)
			break
		var card: Control = k.get("_card")
		var banner: Label = card.get("_banner")
		var mastered := Kitchen.is_mastered(_gs.data, key) and banner.visible and banner.text == tr("UI_MASTERY_BANNER")
		await _frames(int(delays[i]))
		await _click_ctrl(card.get("_button"))
		var closed := await _until(func() -> bool: return k.get("_card") == null and _cards_in(k) == 0, 1500)
		_check("card: Mastered press card %d closes with one Continue click %d frames in (Mastered %s)" % [i, delays[i], mastered], closed)
		if not closed:
			_close_all_cards(k)
		await _frames(4)
	# the race: the mini-game's result delivered twice must not stack two cards
	d.book.variants[key] = {"best_q": 3, "best_stars": 3, "count": 2, "first_day": 1, "good": 2}
	k.set("debug_ctx", {})
	k.call("_open_panel", "press")
	k.call("_on_cook_requested", "juice", apple, "", "")
	await _frames(3)
	k.call("_on_minigame_done", {"stars": 3})
	k.call("_on_minigame_done", {"stars": 3})
	await _frames(2)
	var stacked := _cards_in(k)
	if k.get("_card") != null:
		await _frames(10)
		await _click_ctrl((k.get("_card") as Control).get("_button"))
	var gone := await _until(func() -> bool: return k.get("_card") == null and _cards_in(k) == 0, 1500)
	_check("card: a result delivered twice leaves no card after one Continue (cards shown %d)" % stacked, gone)
	# a card someone else lost track of still closes itself
	var rc: Control = (load("res://ui/result_card/result_card.tscn") as PackedScene).instantiate()
	(k.get("_overlay") as Node).add_child(rc)
	rc.call("show_result", ProductGen.describe(key, d.varieties), 3, false)
	await _frames(10)
	await _click_ctrl(rc.get("_button"))
	await _frames(3)
	_check("card: a card nobody listens to closes itself on Continue", not is_instance_valid(rc) or not rc.is_visible_in_tree())
	Engine.time_scale = 1.0
	_close_all_cards(k)
	k.queue_free()
	current_scene = null
	await _frames(3)


func _cards_in(k: Node) -> int:
	var n := 0
	for c in (k.get("_overlay") as Node).get_children():
		if c is ResultCard and not c.is_queued_for_deletion() and (c as Control).visible:
			n += 1
	return n


func _close_all_cards(k: Node) -> void:
	for c in (k.get("_overlay") as Node).get_children():
		if c is ResultCard:
			c.queue_free()
	k.set("_card", null)
	k.call("_set_room_active", true)


# ================================================================ 2. Granny's path and the cat

func _probe_path() -> void:
	_router.params = {}
	_router.current = "garden"
	_gs.start_temp(452)
	var g: Node = (load("res://scenes/garden/garden.tscn") as PackedScene).instantiate()
	root.add_child(g)
	current_scene = g
	await _frames(10)
	var granny: Node2D = g.get("granny")
	var cat: Node2D = g.get("cat")
	cat.set("_wander_in", 9999.0)
	granny.call("teleport", Vector2i(28, 15))
	await _frames(2)
	var door: Node = g.call("find_spot", "door")
	g.call("tap_world", (door as Object).call("hit_rect").get_center())
	var path: Array = granny.get("_path")
	_check("path: tapping the door plans a long walk (%d cells)" % path.size(), path.size() >= 15)
	if path.size() < 4:
		g.queue_free()
		return
	var on_path: Vector2i = path[3]
	var walk_ok := true
	for c: Vector2i in path:
		if bool(g.call("_cat_may_walk", c)):
			walk_ok = false
	_check("path: the cat may not walk onto any cell of Granny's remaining path", walk_ok)
	cat.set("cell", on_path)
	cat.position = Vector2(on_path.x * 16 + 8, (on_path.y + 1) * 16)
	var t0 := Time.get_ticks_msec()
	var used := await _until(func() -> bool: return bool(g.get("_leaving")), 10000)
	_check("path: with the cat on %s Granny re-paths and uses the door (%s, %d ms, stopped at %s)" % [
		on_path, used, Time.get_ticks_msec() - t0, granny.call("current_cell")], used)
	await _until(func() -> bool: return not _transition_busy(), 5000)
	await _frames(4)
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	if is_instance_valid(g):
		g.queue_free()
	current_scene = null
	await _frames(3)


# ================================================================ 3. town Orders pager

func _probe_pager() -> void:
	_gs.start_temp(452)
	var d: Dictionary = _gs.data
	Orders.refill(d)
	while d.orders.size() > 1:
		d.orders.pop_back()
	_router.current = "town"
	var t: Node = (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(t)
	current_scene = t
	await _frames(6)
	t.set("_tab", "orders")
	t.call("_render")
	await _frames(3)
	var before := Node.get_orphan_node_ids().size()
	for i in 5:
		t.call("_render")
		await _frames(2)
	var after := Node.get_orphan_node_ids().size()
	_check("pager: 5 renders of the Orders tab with %d order leave %d orphan nodes" % [d.orders.size(), after - before], after - before == 0)
	t.queue_free()
	current_scene = null
	await _frames(3)


# ================================================================ 4. pantry drops with 30 jars

func _probe_pantry() -> void:
	var s := State.new_game(452)
	VarietyGen.ensure_types(s.varieties, 452)
	s.flags["temp"] = true
	PantryRules.add_shelf(s.pantry)
	PantryRules.add_shelf(s.pantry)
	var keys := ["jam|%s|-" % DevTools.first_variety(s, "apple"), "brined_mushroom|%s|-" % DevTools.first_variety(s, "chanterelle"),
		"jam|%s|-" % DevTools.first_variety(s, "pear"), "pickle|%s|-" % DevTools.first_variety(s, "cucumber")]
	var pile: Array = []
	for i in 40:
		pile.append(State.product(keys[i % keys.size()], 2, 0))
	var left := PantryRules.auto_arrange(s.pantry, pile)
	var jars := 0
	for e in s.pantry.items:
		if String(e.item.get("kind", "")) == "product":
			jars += 1
	while jars > 30:
		s.pantry.items.pop_back()
		jars -= 1
	s.inbox = left.slice(0, 6)
	while s.inbox.size() < 6:
		s.inbox.append(State.product(keys[s.inbox.size() % keys.size()], 2, 0))
	_gs.set("data", s)
	_router.current = "pantry"
	var p: Control = (load("res://scenes/pantry/pantry.tscn") as PackedScene).instantiate()
	var t_load := Time.get_ticks_usec()
	root.add_child(p)
	var load_ms := (Time.get_ticks_usec() - t_load) / 1000.0
	current_scene = p
	await _frames(6)
	var board: ArrangeBoard = p.get_node("%Board")
	var inbox: Control = p.get_node("%Inbox")
	print("PROBE pantry: %d jars on the shelves, %d waiting, scene build %.1f ms" % [jars, s.inbox.size(), load_ms])
	var worst_drop := 0.0
	var worst_move := 0.0
	for i in 3:
		var cell := _free_cell(board, s.inbox[0])
		if cell.x < 0:
			break
		var gp := inbox.get_global_transform_with_canvas() * Vector2(inbox.call("slot_rect", 0).get_center())
		board.begin_hold(s.inbox[0], {"where": "inbox", "index": 0}, gp)
		await _frames(2)
		board.move_hold_to(Vector2(board.cell_rect(cell).position) + Vector2(4, 4))
		var t0 := Time.get_ticks_usec()
		board.drop_held()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst_drop = maxf(worst_drop, ms)
		print("PROBE pantry: drop %d from the inbox %.1f ms" % [i + 1, ms])
		await _frames(4)
		# move a board jar one free cell over
		var idx := board.entries.size() - 1
		var to := _free_cell(board, board.entries[idx].item, idx)
		if to.x >= 0:
			var e: Dictionary = board.entries[idx]
			var from_pt := board.get_global_transform_with_canvas() * Vector2(board.entry_rect(idx).position + Vector2i(4, 4))
			board.begin_hold(e.item, {"where": "board", "index": idx}, from_pt)
			await _frames(2)
			board.move_hold_to(Vector2(board.cell_rect(to).position) + Vector2(4, 4))
			t0 = Time.get_ticks_usec()
			board.drop_held()
			ms = (Time.get_ticks_usec() - t0) / 1000.0
			worst_move = maxf(worst_move, ms)
			print("PROBE pantry: move %d on the board %.1f ms" % [i + 1, ms])
			await _frames(4)
	var t1 := Time.get_ticks_usec()
	p.call("_on_auto")
	var auto_ms := (Time.get_ticks_usec() - t1) / 1000.0
	print("PROBE pantry: Auto-arrange %.1f ms" % auto_ms)
	_check("pantry: a drop from the inbox with 30 jars under %d ms (worst %.1f)" % [DROP_MS, worst_drop], worst_drop < DROP_MS)
	_check("pantry: a move on the board with 30 jars under %d ms (worst %.1f)" % [DROP_MS, worst_move], worst_move < DROP_MS)
	_check("pantry: Auto-arrange with 30 jars under %d ms (%.1f)" % [DROP_MS, auto_ms], auto_ms < DROP_MS)
	await _frames(4)
	p.queue_free()
	current_scene = null
	await _frames(3)


func _free_cell(board: ArrangeBoard, item: Dictionary, ignore := -1) -> Vector2i:
	var b: Dictionary = board.board
	for y in int(b.rows):
		for x in int(b.cols):
			var c := Vector2i(x, y)
			if board.zone_at(c) != "" and board.can_place_at(item, c, 0, ignore):
				if ignore >= 0 and Vector2i(int(board.entries[ignore].x), int(board.entries[ignore].y)) == c:
					continue
				return c
	return Vector2i(-1, -1)


# ================================================================ 5. the market: fade in, parade frames

func _probe_market() -> void:
	var s := State.new_game(1)
	s.day = 7
	s.flags["temp"] = true
	s.inbox = (load("res://scenes/market/market.gd") as GDScript).call("sample_items")
	_gs.set("data", s)
	_router.current = "town"
	var town: Node = (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(town)
	current_scene = town
	await _frames(8)
	var banner := town.find_child("MarketToday", true, false) as Control
	if banner == null:
		_check("market: the town shows the Market today banner", false)
		return
	var spikes: Array = []
	var watch := _FrameWatch.new()
	watch.tree = self
	await _click(banner.get_global_rect().get_center().floor())
	_check("market: the banner fades out (Transition) instead of a hard cut", _transition_busy() or _router.get("current") != "market")
	await _until(func() -> bool: return _router.get("current") == "market" and current_scene != null and current_scene.name == "Market" and not _transition_busy(), 10000)
	var m: Node = current_scene
	_check("market: the market opens", m != null and m.name == "Market")
	if m == null or m.name != "Market":
		return
	var vil: GDScript = load("res://scenes/market/villager.gd")
	await _frames(10)
	var tq := Time.get_ticks_usec()
	m.call("_queue_likely_crowd")
	print("PROBE market: likely crowd planned and queued in %.1f ms; %d poses baked so far" % [
		(Time.get_ticks_usec() - tq) / 1000.0, int(vil.call("baked_count"))])
	Engine.time_scale = 2.0
	await process_frame
	watch.reset()
	m.call("_on_fill")
	await _watched(watch, 3)
	var fill_ms := watch.worst
	await process_frame
	watch.reset()
	vil.set("composed_live", 0)
	m.call("_on_open")
	await _watched(watch, 2)
	var open_ms := watch.worst
	watch.reset()
	var t0 := Time.get_ticks_msec()
	var over := 0
	var frames := 0
	while Time.get_ticks_msec() - t0 < 12000 and int(m.get("_phase")) == 1:
		await process_frame
		frames += 1
		var ms := watch.tick()
		if ms > PARADE_MS:
			over += 1
			spikes.append("%.0f" % ms)
	Engine.time_scale = 1.0
	print("PROBE market: Fill frame %.1f ms, Open frame %.1f ms, parade %d frames, worst %.1f ms, %d over %d ms %s; %d poses composed in the parade's frames, %d baked" % [
		fill_ms, open_ms, frames, watch.worst, over, PARADE_MS, spikes, int(vil.get("composed_live")), int(vil.call("baked_count"))])
	_check("market: parade frames under %d ms (worst %.1f, %d over)" % [PARADE_MS, watch.worst, over], over == 0)
	_check("market: no villager pose composed in the parade's frames (%d)" % int(vil.get("composed_live")), int(vil.get("composed_live")) == 0)
	m.queue_free()
	if is_instance_valid(town):
		town.queue_free()
	current_scene = null
	await _frames(3)


## Real time between frames (Time.get_ticks_usec, time_scale does not change it).
class _FrameWatch:
	var tree: SceneTree
	var last := 0
	var worst := 0.0

	func reset() -> void:
		last = Time.get_ticks_usec()
		worst = 0.0

	func tick() -> float:
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		worst = maxf(worst, ms)
		return ms


# ================================================================ helpers

func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("PROBE %s %s" % ["ok  " if ok else "FAIL", what])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _watched(watch: _FrameWatch, n: int) -> void:
	for i in n:
		await process_frame
		watch.tick()


## Waits until `cond` holds, at most `max_ms` of real time.
func _until(cond: Callable, max_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		if bool(cond.call()):
			return true
		await process_frame
	return bool(cond.call())


## Transition is reached by path: a SceneTree script can't name a class that uses autoloads.
func _transition_busy() -> bool:
	return bool(load(TRANSITION_GD).call("is_busy"))


func _click_ctrl(c: Control) -> void:
	if c == null or not c.is_visible_in_tree():
		return
	await process_frame
	await _click(c.get_global_rect().get_center().floor())


func _click(at: Vector2) -> void:
	_move(at)
	await process_frame
	_button(at, true)
	await process_frame
	_button(at, false)
	await process_frame


func _button(p: Vector2, pressed: bool) -> void:
	_mask = 1 if pressed else 0
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = _mask
	ev.position = p
	ev.global_position = p
	root.push_input(ev, true)


func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.button_mask = _mask
	root.push_input(ev, true)
