extends SceneTree
## Smoke shot (MARKET, MARKET-LIVE): a day-7 seed-1 game in memory (no save). Clicks the town's "Market today!" banner,
## drags a jar onto Granny's counter with the mouse, fills the stall and opens it with the keyboard (Enter on the
## focused buttons), checks the save after Market.run, then jumps through the parade (MarketCrowd) and shoots five
## moments: the square filling, browsing at the stalls, a buyer at the counter with a bubble, the busy middle, the
## last buyers. Esc skips to the end card, Enter goes back to town (banner gone).
## Shots: user://shots/market_town.png, market_setup.png, market_parade_1..5.png, market_end.png.
## `-- --rainy` plays a rainy market day (fewer strollers, umbrellas, rain) and adds "_rain" to the shot names;
## `-- --locale=tr` plays it in Turkish and adds "_tr".
##   godot --audio-driver Dummy --path game -s res://tests/smoke/market_shot.gd   (exit 1 when a check fails)

var _gs: Node
var _scene: Control
var _checks := 0
var _fails := 0
var _mask := 0
var _suffix := ""


func _initialize() -> void:
	_gs = root.get_node("GameState")
	_run()


func _run() -> void:
	await process_frame
	var s := State.new_game(1)
	s.day = 7
	s.flags["temp"] = true
	if "--rainy" in OS.get_cmdline_user_args():
		s.weather = "rainy"
		_suffix = "_rain"
	if "--locale=tr" in OS.get_cmdline_user_args():
		GameSettings.apply_language("tr")
		_suffix += "_tr"
	s.inbox = (load("res://scenes/market/market.gd") as GDScript).call("sample_items")
	s.inbox.append(State.product("jam|pear_3|-", 2, 3))  # still waiting: stays home
	_gs.set("data", s)
	var town := (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(town)
	await _frames(6)
	var banner := town.find_child("MarketToday", true, false) as Control
	_check("town shows the Market today banner", banner != null and banner.visible)
	_shot("market_town")
	if banner == null:
		quit(1)
		return
	_move(banner.get_global_rect().get_center())
	_button(banner.get_global_rect().get_center(), true)
	_button(banner.get_global_rect().get_center(), false)
	await _frames(2)
	var transition: GDScript = load("res://ui/transition/transition.gd")
	_check("the banner fades out to the market (no hard cut)", bool(transition.call("is_busy")))
	var t0 := Time.get_ticks_msec()
	while (bool(transition.call("is_busy")) or root.get_node("Router").get("current") != "market") and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	if is_instance_valid(town):
		town.queue_free()
	_scene = current_scene as Control
	_check("the banner opens the market", root.get_node("Router").get("current") == "market" and _scene != null and _scene.name == "Market")
	if _scene == null:
		quit(1)
		return
	await _frames(4)
	var board: ArrangeBoard = _scene.get("_board")
	var jars: Control = _scene.get("_source_view")
	var source: Array = _scene.get("_source")
	var counter: Rect2i = _scene.get("_counter")
	_check("the counter is the layout's 6x2 grid (%s)" % str(counter), counter.size == Vector2i(144, 48))
	_check("the board sits on the counter", Vector2i(board.position) == counter.position)
	_check("five vendors at their stalls", (_scene.get("_vendors") as Dictionary).size() == 5)
	_check("Granny stands at her stall", _scene.get("_granny") != null)
	_check("ready jars offered, waiting jar not", source.size() == 14)
	_check("Fill stall has the focus", _focused() == _scene.get("_fill_btn"))
	var first: Dictionary = source[0]
	_drag(_slot(jars, 0), board.get_global_rect().position + Vector2(12, 12))
	await _frames(2)
	var entries: Array = _scene.get("_entries")
	_check("mouse drag puts a jar on the stall", entries.size() == 1 and is_same(entries[0].item, first))
	_check("the jar left the column", source.size() == 13)
	_key(KEY_ENTER)
	await _frames(3)
	_check("Enter on Fill stall fills it", entries.size() >= 8)
	var mult := Market.stall_score(entries, s.varieties)
	_check("appeal above x1 (%.2f)" % mult, mult > 1.2)
	_check("Open stall has the focus", _focused() == _scene.get("_open_btn"))
	_check("setup panels clear of the stall", (_scene.get("_open_btn") as Control).position.x >= 334.0)
	await _frames(20)
	_shot("market_setup")
	var coins := int(s.coins)
	var stall_n := entries.size()
	_key(KEY_ENTER)
	await _frames(3)
	var plan: Dictionary = _scene.get("_plan")
	var crowd: Dictionary = _scene.get("_crowd")
	var earned := 0
	for v in plan.sales:
		earned += int(v.price)
	_check("parade started", int(_scene.get("_phase")) == 1)
	_check("coins paid at once (+%d)" % earned, int(s.coins) == coins + earned and earned > 0)
	_check("reputation 1, last_day 7", int(Market.info(s).reputation) == 1 and int(Market.info(s).last_day) == 7)
	_check("sold jars left the inbox", s.inbox.size() == 15 - plan.sales.size())
	_check("parade length 30-45 s (%.1f)" % float(_scene.get("_t_end")), float(_scene.get("_t_end")) >= 29.0 and float(_scene.get("_t_end")) <= 47.0)
	_check("jars stay on the counter", _visible_jars() == stall_n)
	var cv: Node = _scene.get("_crowd_view")
	# five moments of the parade
	var buyers: Array = (crowd.people as Array).filter(func(p: Dictionary) -> bool: return float(p.buy_t) >= 0.0)
	buyers.sort_custom(func(a: Dictionary, z: Dictionary) -> bool: return float(a.buy_t) < float(z.buy_t))
	var at_buy := float(buyers[mini(2, buyers.size() - 1)].line_t) + 0.3 if not buyers.is_empty() else 12.0
	var moments := [1.0, 6.5, at_buy, float(crowd.length) * 0.55, float(crowd.length) - 4.0]
	var most := 0
	for i in moments.size():
		_scene.set("_t", float(moments[i]))
		await _frames(10)
		var n := int(cv.call("visible_count"))
		most = maxi(most, n)
		var bubbles: Array = (_scene.get("_bubbles") as Control).call("shown")
		_check("moment %d (%.1f s): %d people, %d bubbles" % [i + 1, float(moments[i]), n, bubbles.size()], n >= 3 and bubbles.size() <= 3)
		for b in bubbles:
			_check("bubble %s clear of the counter" % b.who, not (b.rect as Rect2).intersects(Rect2(counter)))
			for c in bubbles:
				if c != b:
					_check("bubbles apart", not (b.rect as Rect2).intersects(c.rect))
		_shot("market_parade_%d" % (i + 1))
	_check("a lively square (%d at once)" % most, most >= 8)
	_check("coins tick up", int(_scene.get("_sold")) >= 2)
	_check("sold jars left the counter", _visible_jars() < stall_n)
	_key(KEY_ESCAPE)
	await _frames(14)
	var card: Control = _scene.get("_end_card")
	_check("Esc skips to the end card", card.visible and int(_scene.get("_phase")) == 2)
	_check("end card counts every sale", int(_scene.get("_sold")) == plan.sales.size())
	_check("every sold jar gone from the counter", _visible_jars() == stall_n - plan.sales.size())
	_shot("market_end")
	_key(KEY_ENTER)
	await _frames(8)
	var back := current_scene
	_check("Back to town", back != null and back.name == "Town")
	_check("no banner after the market", back != null and back.find_child("MarketToday", true, false) == null)
	print("market smoke: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _visible_jars() -> int:
	var n := 0
	var views: Dictionary = _scene.get("_jar_views")
	for k in views:
		if (views[k] as Control).visible:
			n += 1
	return n


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _shot(name: String) -> void:
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("%s/%s%s.png" % [dir, name, _suffix])
	print("saved ", ProjectSettings.globalize_path("%s/%s%s.png" % [dir, name, _suffix]))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("ok   " if ok else "FAIL ") + what)


func _slot(view: Control, i: int) -> Vector2:
	var r: Rect2i = view.call("slot_rect", i)
	return view.get_global_rect().position + Vector2(r.position) + Vector2(12, 12)


func _drag(a: Vector2, b: Vector2) -> void:
	_move(a)
	_button(a, true)
	_move(a.lerp(b, 0.5))
	_move(b)
	_button(b, false)


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


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		root.push_input(ev, true)
