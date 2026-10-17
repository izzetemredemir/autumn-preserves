extends "res://tests/_runner/test_case.gd"
## MARKET-LIVE: the market crowd (MarketCrowd, pure). Same market day -> same crowd; every route runs over the walk
## graph; every buyer reaches Granny's counter and buys during the parade; vendors stay put; the crowd stays small
## enough for the actor budget and changes with reputation and rain.

const LAYOUT := "res://assets/sprites/market/market_layout.json"
const KEYS := [
	"jam|apple_1|-", "jam|quince_1|ginger", "jam|crabapple_1|cinnamon", "pickle|cucumber_1|-",
	"chutney|pear_1|pepper_1|chili", "brined_mushroom|chanterelle_1|-", "fruit_butter|pear_2|honey",
	"pie|apple_1|-", "juice|apple_2|-", "pickle|cucumber_2|clove", "jam|blackberry_1|-", "bread|-",
]


func _layout() -> Dictionary:
	var f := FileAccess.open(LAYOUT, FileAccess.READ)
	if f == null:
		return _small_layout()
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else _small_layout()


## A layout without the optional keys (no jar_nodes, no front_node): the crowd builds its own lane and spurs.
func _small_layout() -> Dictionary:
	return {
		"granny_stall": {"x": 240, "y": 225, "counter": [168, 150, 144, 48], "granny": [320, 224]},
		"vendors": [{"id": "baker", "stand": [40, 200], "front": [60, 236]}, {"id": "postman", "stand": [440, 200], "front": [420, 236]}],
		"walk": {"nodes": [[10, 240], [120, 240], [240, 250], [360, 240], [470, 240], [240, 266]],
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [2, 5]]},
		"entries": [[0, 240], [479, 240], [240, 269]],
		"pigeon_zones": [[200, 255, 60, 10]],
	}


func _visits(sd: int, day := 7, rep := 2) -> Dictionary:
	var s := State.new_game(sd)
	s.day = day
	s.market = {"reputation": rep, "last_day": 0}
	for k in KEYS:
		s.inbox.append(State.product(k, 2, 0))
	return Market.plan(s, Market.auto_stall(s.inbox, s.varieties))


func _crowd(sd: int, layout: Dictionary, rep := 2, rainy := false) -> Dictionary:
	return MarketCrowd.build(sd, 7, _visits(sd, 7, rep).visits, layout, rep, rainy)


func test_same_day_same_crowd() -> void:
	var lay := _layout()
	for sd in [1, 7, 42]:
		var a := _crowd(sd, lay)
		var b := _crowd(sd, lay)
		assert_eq(var_to_str(a.people), var_to_str(b.people), "seed %d people" % sd)
		assert_eq(var_to_str(a.vendors), var_to_str(b.vendors), "seed %d vendors" % sd)
		assert_eq(var_to_str(a.lines), var_to_str(b.lines), "seed %d lines" % sd)
	assert_ne(var_to_str(_crowd(1, lay).people), var_to_str(_crowd(2, lay).people), "another save, another crowd")


func test_every_route_on_the_graph() -> void:
	for lay in [_layout(), _small_layout()]:
		for sd in [1, 3, 99]:
			var c := _crowd(sd, lay)
			var g := MarketCrowd.graph(lay)
			for p in c.people:
				assert_true(MarketCrowd.on_graph(g, p.path), "person %d walks the graph" % int(p.id))
				var last := -1.0
				for st in p.steps:
					assert_true(float(st.t1) >= float(st.t0), "time runs forward")
					assert_true(last < 0.0 or absf(float(st.t0) - last) < 0.001, "steps follow each other")
					last = float(st.t1)
					if String(st.do) == "walk":
						assert_true(MarketCrowd.on_graph(g, [int(st.a), int(st.b)]), "walk %d->%d is an edge" % [int(st.a), int(st.b)])
						assert_eq(st.from, g.nodes[int(st.a)])
						assert_eq(st.to, g.nodes[int(st.b)])
					else:
						assert_eq(int(st.a), int(st.b), "a stop stays on one node")
				assert_true((p.offset as Vector2).length() <= 12.0, "small offset from the path")


func test_buyers_reach_grannys_stall() -> void:
	for lay in [_layout(), _small_layout()]:
		var plan := _visits(7, 7, 3)
		var c := MarketCrowd.build(7, 7, plan.visits, lay, 3, false)
		var lane: Array = c.lane
		var buyers := 0
		for i in plan.visits.size():
			var v: Dictionary = plan.visits[i]
			var p := {}
			for q in c.people:
				if int(q.visit) == i:
					p = q
			assert_false(p.is_empty(), "visit %d walks" % i)
			var at_stall := false
			for st in p.steps:
				if String(st.do) in ["buy", "browse", "look"] and int(st.a) in lane:
					at_stall = true
					if String(st.do) == "buy":
						assert_true(float(p.buy_t) >= float(st.t0) and float(p.buy_t) <= float(st.t1), "the jar hops while they stand there")
			assert_true(at_stall, "visit %d passes Granny's counter" % i)
			if not (v.item as Dictionary).is_empty():
				buyers += 1
				assert_true(float(p.buy_t) > 0.0 and float(p.buy_t) < float(c.length), "buys during the parade (%.1f)" % float(p.buy_t))
				assert_eq(String(p.line_key), String(v.line_key))
			else:
				assert_eq(float(p.buy_t), -1.0, "non-buyers buy nothing")
		assert_true(buyers > 0, "some buyers")
		assert_true(float(c.length) >= MarketCrowd.T_MIN and float(c.length) <= MarketCrowd.T_MAX)


func test_vendors_stay_put() -> void:
	var lay := _layout()
	var c := _crowd(5, lay)
	assert_eq((c.vendors as Array).size(), (lay.vendors as Array).size())
	for i in c.vendors.size():
		var v: Dictionary = c.vendors[i]
		assert_eq(String(v.id), String(lay.vendors[i].id))
		assert_eq(v.at, Vector2(float(lay.vendors[i].stand[0]), float(lay.vendors[i].stand[1])), "%s at the stand" % v.id)
		var t := -12.0
		for a in v.acts:
			assert_true(absf(float(a.t0) - t) < 0.001, "acts back to back")
			assert_true(String(a.do) in ["idle", "wipe", "arrange", "wave"])
			t = float(a.t1)
		assert_true(t >= float(c.length), "%s busy the whole parade" % v.id)
	for p in c.people:
		assert_false(String(p.kind) == "vendor")


func test_crowd_size_and_variety() -> void:
	var lay := _layout()
	var c := _crowd(11, lay, 2)
	var kinds := {}
	var arches := {}
	for p in c.people:
		kinds[p.kind] = true
		arches[p.arch] = true
	for t in [-4.0, 5.0, 15.0, 25.0, 35.0]:
		var n := 0
		for p in c.people:
			if t >= float(p.spawn) and t <= float(p.end):
				n += 1
		assert_true(n <= MarketCrowd.CAP, "%d on screen at %.0f s" % [n, t])
	assert_true(kinds.has("buyer"))
	assert_true(arches.size() >= 3, "%d archetypes" % arches.size())
	assert_true(MarketCrowd.strollers_for(0, false) == 6 and MarketCrowd.strollers_for(9, false) == 12)
	assert_true(MarketCrowd.strollers_for(9, true) < MarketCrowd.strollers_for(9, false), "fewer in the rain")
	# speeds match the bodies: elders slow, kids quick
	for p in c.people:
		if String(p.arch) == "elder":
			assert_true(float(p.speed) < 30.0)
		if String(p.kind) == "kid":
			assert_true(float(p.speed) > 50.0)


func test_pairs_walk_together_and_chat() -> void:
	var lay := _layout()
	var found := false
	for sd in range(1, 40):
		var c := _crowd(sd, lay, 6)
		for p in c.people:
			if String(p.kind) == "pair" and int(p.partner) >= 0:
				var q: Dictionary = c.people.filter(func(x: Dictionary) -> bool: return int(x.id) == int(p.partner))[0]
				assert_eq(var_to_str(p.path), var_to_str(q.path), "same route")
				assert_eq(float(p.spawn), float(q.spawn))
				var chats := (p.steps as Array).filter(func(s: Dictionary) -> bool: return String(s.do) == "chat")
				assert_eq(chats.size(), 1, "they stop to chat once")
				found = true
		if found:
			break
	assert_true(found, "some market day has a pair")
