extends "res://tests/_runner/test_case.gd"
## LIVING-TOWN: the town square crowd (TownCrowd, pure). Same day -> same square; every route runs over the walk graph;
## the loop repeats without a seam; Barnaby, Rosie and Pip stand still while Vito and Edith stroll all loop long;
## 5-10 villagers are out on a sunny day, fewer in the rain; every line is a town string.

const LAYOUT := "res://assets/sprites/town/town_layout.json"


func _layout() -> Dictionary:
	var f := FileAccess.open(LAYOUT, FileAccess.READ)
	assert_true(f != null, "town_layout.json exists")
	var d: Variant = JSON.parse_string(f.get_as_text()) if f != null else {}
	return d if d is Dictionary else {}


func test_same_day_same_square() -> void:
	var lay := _layout()
	for sd in [1, 7, 42]:
		for rainy in [false, true]:
			var a := TownCrowd.build(sd, 3, lay, rainy)
			var b := TownCrowd.build(sd, 3, lay, rainy)
			assert_eq(var_to_str(a.people), var_to_str(b.people), "seed %d people" % sd)
			assert_eq(var_to_str(a.neighbours), var_to_str(b.neighbours), "seed %d neighbours" % sd)
			assert_eq(var_to_str(a.lines), var_to_str(b.lines), "seed %d lines" % sd)
	assert_ne(var_to_str(TownCrowd.build(1, 3, lay).people), var_to_str(TownCrowd.build(2, 3, lay).people), "another save")
	assert_ne(var_to_str(TownCrowd.build(1, 3, lay).people), var_to_str(TownCrowd.build(1, 4, lay).people), "another day")


func test_every_route_on_the_graph() -> void:
	var lay := _layout()
	var g := MarketCrowd.graph(lay)
	assert_true(g.lane.is_empty(), "no Granny lane in the town")
	for sd in [1, 3, 99]:
		for rainy in [false, true]:
			var c := TownCrowd.build(sd, 5, lay, rainy)
			for p in c.people:
				assert_true(MarketCrowd.on_graph(g, p.path), "person %d walks the graph" % int(p.id))
				assert_true(float(p.spawn) >= 0.0 and float(p.spawn) < TownCrowd.LOOP, "spawn inside the loop")
				assert_true(float(p.end) - float(p.spawn) <= TownCrowd.LOOP, "a visit is shorter than the loop")
				var last := float(p.spawn)
				for st in p.steps:
					assert_true(float(st.t1) >= float(st.t0), "time runs forward")
					assert_near(float(st.t0), last, 0.001, "steps follow each other")
					last = float(st.t1)
					if String(st.do) == "walk":
						assert_true(MarketCrowd.on_graph(g, [int(st.a), int(st.b)]), "walk %d->%d is an edge" % [int(st.a), int(st.b)])
						assert_eq(st.from, g.nodes[int(st.a)])
						assert_eq(st.to, g.nodes[int(st.b)])
					else:
						assert_eq(int(st.a), int(st.b), "a stop stays on one node")
				assert_near(last, float(p.end), 0.001, "the last step ends the visit")
				if String(p.npc) == "":
					var first: int = p.path[0]
					var exit: int = p.path.back()
					assert_has(g.entries, first, "villagers come in at an entry")
					assert_has(g.entries, exit, "villagers leave at an entry")


func test_neighbours() -> void:
	var lay := _layout()
	var c := TownCrowd.build(11, 2, lay)
	var stand_ids: Array = []
	for n in c.neighbours:
		stand_ids.append(String(n.id))
		var t := 0.0
		for a in n.acts:
			assert_near(float(a.t0), t, 0.001, "%s acts follow each other" % n.id)
			assert_has(["idle", "wipe", "arrange", "wave"], String(a.do))
			t = float(a.t1)
		assert_near(t, TownCrowd.LOOP, 0.001, "%s acts fill the loop" % n.id)
	assert_eq(stand_ids, ["grocer", "baker", "postman"], "Barnaby, Rosie and Pip stand at their places")
	var strollers: Array = []
	for p in c.people:
		if String(p.npc) != "":
			strollers.append(String(p.npc))
			assert_eq(float(p.spawn), 0.0, "%s is out from the start" % p.npc)
			assert_eq(float(p.end), TownCrowd.LOOP, "%s strolls all loop long" % p.npc)
			assert_eq(p.path[0], p.path.back(), "%s ends where the loop starts again" % p.npc)
			var steps: Array = p.steps
			assert_eq(steps[0].from, steps.back().to, "%s: no jump when the loop repeats" % p.npc)
			for k in 30:
				assert_true(TownCrowd.local_time(p, k * 7.3) >= 0.0, "%s is always out" % p.npc)
	assert_eq(strollers, ["vintner", "librarian"], "Vito and Edith stroll")


func test_crowd_size_and_rain() -> void:
	var lay := _layout()
	for sd in [1, 5, 23]:
		var sunny := TownCrowd.build(sd, 2, lay, false)
		var rainy := TownCrowd.build(sd, 2, lay, true)
		var sum_s := 0
		var sum_r := 0
		var most := 0
		var fewest := 99
		var samples := 180
		for k in samples:
			var t := k * TownCrowd.LOOP / samples
			var n := TownCrowd.out_at(sunny, t)
			sum_s += n
			most = maxi(most, n)
			fewest = mini(fewest, n)
			sum_r += TownCrowd.out_at(rainy, t)
		var avg_s := float(sum_s) / samples
		var avg_r := float(sum_r) / samples
		assert_true(avg_s >= 5.0 and avg_s <= 10.0, "seed %d: 5-10 villagers out on a sunny day (%.1f)" % [sd, avg_s])
		assert_true(most <= TownCrowd.CAP, "seed %d: at most CAP out at once (%d)" % [sd, most])
		assert_true(fewest >= 2, "seed %d: the square is never empty (%d)" % [sd, fewest])
		assert_true(avg_r < avg_s * 0.7 and avg_r >= 1.5, "seed %d: rain thins the crowd (%.1f vs %.1f)" % [sd, avg_r, avg_s])
		var kinds := {}
		for p in sunny.people:
			kinds[String(p.kind)] = true
		for k in ["reader", "shopper", "kid", "npc"]:
			assert_true(kinds.has(k), "seed %d: someone is a %s" % [sd, k])
		for p in rainy.people:
			assert_ne(String(p.kind), "kid", "no kids play in the rain")


func test_lines() -> void:
	var lay := _layout()
	for rainy in [false, true]:
		var c := TownCrowd.build(4, 6, lay, rainy)
		assert_true(c.lines.size() >= 10, "the square talks")
		var ids := {}
		for p in c.people:
			ids["p%d" % int(p.id)] = true
		for n in c.neighbours:
			ids["n" + String(n.id)] = true
		var last := 0.0
		for l in c.lines:
			assert_true(String(l.key).begins_with("TOWN_CALL_") or String(l.key).begins_with("TOWN_CHAT_"), String(l.key))
			assert_true(float(l.t) >= 0.0 and float(l.t) < TownCrowd.LOOP, "line inside the loop")
			assert_true(float(l.t) >= last, "lines in time order")
			assert_true(ids.has(String(l.who)), "a line by someone in the square")
			last = float(l.t)
