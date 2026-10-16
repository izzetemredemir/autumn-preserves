extends "res://tests/_runner/test_case.gd"
## BIOMES: vineyard and creek (spec §7.1, tech-spec §16), the forest's P1 points, lazy P1 varieties, the bee hive.

const SEEDS := 30
const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Forest fingerprints taken on the P0 generator before BIOMES (aed38cc): [save_seed, day, weather, md5].
## The P0 part of a forest (everything but the "p1" points) must never change for an old seed in days 1-7 (from day 8
## the harvest calendar weighs the week's types; test_calendar.gd).
const FOREST_BEFORE := [
	[1000, 1, "sunny", "ebe9dbeca0df9ae406f19040cf66e322"],
	[452, 3, "rainy", "72c083f6c3484a2e68a5a2471ae89327"],
	[20261016, 1, "sunny", "c077f436d52c618970dd553621577c7a"],
	[31, 2, "rainy", "a0eefefec4a604a900516a8feb86e601"],
	[7919, 5, "sunny", "6877048b2cf7cb7506ecdfb59405d9ef"],
	[123456, 4, "foggy", "b5d88569890e683de1b9c1795f99b143"],
	# day 9 is in the harvest calendar (Grape Harvest: pear trees x2), retaken at CALENDAR-WEATHER; was 4701302d...
	[8, 9, "sunny", "49412cfa5fd3454ffa82cc138b9f0fa0"],
	[99991, 2, "rainy", "5d7a695847bee51f6b80278bea7a69a8"],
]

var _vars: Dictionary = {}


func before_each() -> void:
	if _vars.is_empty():
		_vars = VarietyGen.generate_all(4242, 0)
		VarietyGen.ensure_types(_vars, 4242)


func _seed(i: int) -> int:
	return 500 + i * 6151


func _map(biome: String, i: int, weather := "sunny") -> Dictionary:
	return WildGen.generate(_seed(i), 1 + i % 6, biome, weather, _vars)


# ---------------- forest: old seeds keep their map ----------------

func test_forest_p0_part_unchanged_for_old_seeds() -> void:
	for c in FOREST_BEFORE:
		var v := VarietyGen.generate_all(int(c[0]), 0)
		var m := WildGen.generate(int(c[0]), int(c[1]), "forest", String(c[2]), v)
		assert_eq(_fingerprint(m), String(c[3]), "forest seed %d day %d" % [c[0], c[1]])
		# P1 varieties in the dict do not move or change a P0 point
		var v1 := v.duplicate(true)
		VarietyGen.ensure_types(v1, int(c[0]))
		assert_eq(_fingerprint(WildGen.generate(int(c[0]), int(c[1]), "forest", String(c[2]), v1)), String(c[3]))


func test_forest_p1_points_are_appended_and_reachable() -> void:
	var cfg := WildGen.biome_table("forest_p1")
	var bush_types := WildGen.p1_types("forest", "bush")
	var ground_types := WildGen.p1_types("forest", "ground")
	assert_eq(bush_types, ["rosehip"])
	assert_eq(ground_types, ["chestnut", "hazelnut"])
	var seen := {}
	var with_bush := 0
	for i in SEEDS:
		var m := _map("forest", i)
		var tag := "forest seed %d" % _seed(i)
		var first_p1 := -1
		var nb := 0
		var ng := 0
		for k in m.pickups.size():
			var p: Dictionary = m.pickups[k]
			if not p.get("p1", false):
				assert_eq(first_p1, -1, tag + " P1 points come after every P0 point")
				continue
			if first_p1 < 0:
				first_p1 = k
			seen[p.type] = true
			if p.kind == "bush":
				nb += 1
				assert_has(bush_types, p.type, tag)
				assert_true(_vars.has(p.variety) and _vars[p.variety].type == p.type, tag + " rosehip variety")
			else:
				ng += 1
				assert_has(ground_types, p.type, tag)
				assert_eq(p.variety, "", tag + " nuts have no variety")
		assert_true(nb <= int(cfg.bushes[1]), "%s P1 bushes %d" % [tag, nb])
		assert_true(ng >= int(cfg.ground[0]) and ng <= int(cfg.ground[1]), "%s P1 ground %d" % [tag, ng])
		with_bush += 1 if nb > 0 else 0
		_assert_reachable(m, tag)
	assert_true(with_bush >= SEEDS / 2, "most forests get a rosehip bush (%d / %d)" % [with_bush, SEEDS])
	for t in ["rosehip", "hazelnut", "chestnut"]:
		assert_true(seen.has(t), t + " shows up in the forest")


# ---------------- vineyard and creek ----------------

func test_biomes_same_seed_same_map() -> void:
	for b in ["vineyard", "creek"]:
		for i in 10:
			var a := _map(b, i)
			var c := WildGen.generate(_seed(i), 1 + i % 6, b, "sunny", _vars.duplicate(true))
			assert_eq(var_to_str(a), var_to_str(c), "%s seed %d" % [b, _seed(i)])
			assert_eq(int(a.seed), Seeds.seed_for(_seed(i), "wild:" + b, 1 + i % 6), "map seed = wild:<biome>")
			assert_eq(a.biome, b)
		assert_ne(var_to_str(_map(b, 0)), var_to_str(_map(b, 1)), b + ": different seeds differ")
	assert_ne(var_to_str(_map("vineyard", 0).ground), var_to_str(_map("creek", 0).ground), "biomes differ")
	assert_eq(WildGen.generate(1, 1, "moon", "sunny", _vars), {}, "unknown biome")


func test_biomes_everything_reachable() -> void:
	for b in ["vineyard", "creek"]:
		for i in SEEDS:
			_assert_reachable(_map(b, i, "rainy" if i % 3 == 0 else "sunny"), "%s seed %d" % [b, _seed(i)])


func test_biomes_counts_and_types() -> void:
	var wr: Dictionary = Data.rules().wild
	assert_eq(WildGen.biome_types("vineyard", "tree"), ["grape", "pear"])
	assert_eq(WildGen.biome_types("vineyard", "bush"), ["blackberry", "rosehip"])
	assert_eq(WildGen.biome_types("vineyard", "ground"), ["grape", "walnut"])
	assert_eq(WildGen.biome_types("creek", "tree"), ["elderberry"])
	assert_eq(WildGen.biome_types("creek", "bush"), ["rosehip"])
	assert_eq(WildGen.biome_types("creek", "ground"), ["hazelnut", "oyster_mushroom"])
	var grapes := 0
	var pears := 0
	for b in ["vineyard", "creek"]:
		var trees := WildGen.biome_types(b, "tree")
		var bushes := WildGen.biome_types(b, "bush")
		var grounds := WildGen.biome_types(b, "ground")
		for i in SEEDS:
			var m := _map(b, i)
			var tag := "%s seed %d" % [b, _seed(i)]
			var nf := 0
			var nb := 0
			var ng := 0
			var cells := {}
			for t in m.fruit_trees:
				_assert_cell_free(m, cells, t, tag)
				assert_false(t.get("special", false), tag + " no special trees in P1 biomes")
				nf += 1
				assert_has(trees, t.type, tag)
				grapes += 1 if t.type == "grape" else 0
				pears += 1 if t.type == "pear" else 0
				assert_true(_vars.has(t.variety) and _vars[t.variety].type == t.type, tag + " variety " + t.variety)
			for p in m.pickups:
				_assert_cell_free(m, cells, p, tag)
				assert_false(p.get("p1", false), tag + " only the forest appends P1 points")
				if p.get("special", false):
					continue
				if p.kind == "bush":
					nb += 1
					assert_has(bushes, p.type, tag)
				else:
					ng += 1
					assert_eq(p.kind, "ground", tag)
					assert_has(grounds, p.type, tag)
				if Data.ingredients()[p.type].group == "nut":
					assert_eq(p.variety, "", tag)
				else:
					assert_true(_vars.has(p.variety) and _vars[p.variety].type == p.type, tag + " variety " + p.variety)
			assert_true(nf >= int(wr.fruit_trees[0]) and nf <= int(wr.fruit_trees[1]), "%s fruit trees or vines %d" % [tag, nf])
			assert_true(nb >= int(wr.bushes[0]) and nb <= int(wr.bushes[1]), "%s bushes %d" % [tag, nb])
			assert_true(ng >= int(wr.ground[0]) and ng <= int(wr.ground[1]), "%s ground %d" % [tag, ng])
			for k in m.fruit_trees.size():
				assert_eq(int(m.fruit_trees[k].id), k)
			for k in m.pickups.size():
				assert_eq(int(m.pickups[k].id), k)
	assert_true(grapes > pears * 2 and pears > 0, "vines outnumber pear trees (%d grape, %d pear)" % [grapes, pears])


func test_vineyard_vine_rows() -> void:
	var gap := int(WildGen.biome_table("vineyard").row_gap)
	for i in SEEDS:
		var m := _map("vineyard", i)
		var tag := "vineyard seed %d" % _seed(i)
		var w := int(m.w)
		var rows := {}
		var vines := 0
		for d in m.decor_trees:
			if d.kind == "vine":
				vines += 1
				rows[int(d.y)] = true
				assert_eq(int(m.ground[int(d.y) * w + int(d.x)]), WildGen.T_DIRT, tag + " vines stand on their soil strip")
			else:
				assert_has(WildGen.biome_table("vineyard").edge_tree_kinds, d.kind, tag)
		var ys: Array = rows.keys()
		ys.sort()
		assert_true(ys.size() >= 5, "%s vine rows %d" % [tag, ys.size()])
		assert_true(vines >= 120, "%s vines %d" % [tag, vines])
		for k in range(1, ys.size()):
			assert_eq((int(ys[k]) - int(ys[k - 1])) % gap, 0, tag + " rows on a %d-tile grid" % gap)
		for t in m.fruit_trees:
			if t.type == "grape":
				assert_true(rows.has(int(t.y)), tag + " grape vines hang in a row")
		var water := 0
		for g in m.ground:
			water += 1 if int(g) == WildGen.T_WATER else 0
		assert_eq(water, 0, tag + " no stream in the vineyard")


func test_creek_wide_river_with_banks() -> void:
	var rw: Array = WildGen.biome_table("creek").river_width
	for i in SEEDS:
		var m := _map("creek", i)
		var tag := "creek seed %d" % _seed(i)
		var w := int(m.w)
		var h := int(m.h)
		var start := Vector2i(-1, -1)
		var water := {}
		for x in w:
			var run := 0
			for y in h:
				var g := int(m.ground[y * w + x])
				if g == WildGen.T_WATER or g == WildGen.T_STONE:
					run += 1
					water[Vector2i(x, y)] = true
					if x == 0 and start.x < 0:
						start = Vector2i(x, y)
			assert_true(run >= int(rw[0]) - 1 and run <= int(rw[1]) + 1, "%s column %d water %d" % [tag, x, run])
		# one body of water from the west edge to the east edge
		var seen := {start: true}
		var queue: Array[Vector2i] = [start]
		var east := false
		while not queue.is_empty():
			var p: Vector2i = queue.pop_back()
			east = east or p.x == w - 1
			for d: Vector2i in N4:
				if water.has(p + d) and not seen.has(p + d):
					seen[p + d] = true
					queue.append(p + d)
		assert_true(east, tag + " the river runs edge to edge")
		assert_eq(seen.size(), water.size(), tag + " one river")
		var banks := 0
		for k in w * h:
			if int(m.ground[k]) != WildGen.T_BANK:
				continue
			banks += 1
			var c := Vector2i(k % w, floori(float(k) / w))
			var by_water := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					by_water = by_water or water.has(c + Vector2i(dx, dy))
			assert_true(by_water, tag + " bank %s lies by the water" % c)
		assert_true(banks >= w, "%s bank tiles %d" % [tag, banks])
		for d in m.decor_trees:
			assert_ne(int(m.ground[int(d.y) * w + int(d.x)]), WildGen.T_BANK, tag + " banks stay open")
			assert_has(WildGen.biome_table("creek").decor_kinds, d.kind, tag)


func test_biome_special_places() -> void:
	var thicket := WildGen.biome_table("rosehip_thicket")
	var kinds_seen := {}
	for b in ["vineyard", "creek"]:
		var specials := 0
		for i in 60:
			var m := _map(b, i)
			if m.special.is_empty():
				continue
			specials += 1
			var kind := String(m.special.kind)
			var tag := "%s seed %d %s" % [b, _seed(i), kind]
			kinds_seen[kind] = true
			assert_has(WildGen.biome_table(b).special_kinds, kind, tag)
			var own: Array = m.pickups.filter(func(p: Dictionary) -> bool: return p.get("special", false))
			if kind == "bee_hive":
				assert_eq(own.size(), 1, tag)
				assert_eq(own[0].kind, "hive", tag)
				assert_eq(own[0].type, "honey", tag)
			else:
				assert_true(own.size() >= int(thicket.bushes[0]) and own.size() <= int(thicket.bushes[1]),
					"%s bushes %d" % [tag, own.size()])
				for p in own:
					assert_eq(p.kind, "bush", tag)
					assert_eq(p.type, String(thicket.type), tag)
		# rules.wild.special_chance = 0.35 -> ~21 of 60
		assert_true(specials >= 9 and specials <= 36, "%s special places %d / 60" % [b, specials])
	assert_true(kinds_seen.has("bee_hive") and kinds_seen.has("rosehip_thicket"), "both P1 special places show up")


func test_biome_steps_recorded_like_the_forest() -> void:
	for b in ["vineyard", "creek"]:
		var m := WildGen.generate(77, 2, b, "sunny", _vars, true)
		assert_eq((m.steps as Dictionary).keys(), ["1_ground", "2_stream", "3_decor", "4_paths", "5_pickups", "6_special",
			"7_validate"], b)
		var plain := WildGen.generate(77, 2, b, "sunny", _vars, false)
		var a := m.duplicate()
		var c := plain.duplicate()
		a.erase("steps")
		c.erase("steps")
		assert_eq(var_to_str(a), var_to_str(c), b + ": recording never changes the map")


func test_biome_generation_time() -> void:
	for b in ["vineyard", "creek"]:
		WildGen.generate(1, 1, b, "sunny", _vars)
		var total := 0
		for i in 20:
			var t0 := Time.get_ticks_usec()
			WildGen.generate(_seed(i) + 3, 2 + i, b, "sunny", _vars)
			total += Time.get_ticks_usec() - t0
		var avg_ms := total / 1000.0 / 20
		print("%s gen: avg %.1f ms" % [b, avg_ms])
		assert_true(avg_ms < 60.0, "%s average %.1f ms" % [b, avg_ms])


# ---------------- unlocks ----------------

func test_biome_choices_follow_unlocks() -> void:
	var s := State.new_game(321)
	s.day = 4
	var c := WildGen.biome_choices(s)
	assert_eq(c.map(func(x: Dictionary) -> String: return x.id), ["forest", "vineyard", "creek"])
	assert_eq(c.map(func(x: Dictionary) -> bool: return x.open), [true, false, false], "a new game has the forest only")
	assert_eq(c[1].unlock, "vineyard")
	assert_eq(c[2].unlock, "boots")
	for x in c:
		assert_eq(int(x.seed), Seeds.seed_for(321, "wild:" + String(x.id), 4))
		assert_eq(int(x.seed), int(WildGen.generate(321, 4, x.id, "sunny", s.varieties).seed), "the picker shows the map's seed")
	Economy.unlock(s, "vineyard")
	assert_true(WildGen.biome_open(s, "vineyard"))
	assert_false(WildGen.biome_open(s, "creek"))
	s.coins = 1000
	assert_true(Economy.on_sale("boots", Data.shop().upgrades.boots), "boots are on sale (Economy.LIVE)")
	assert_true(Economy.buy(s, "boots").ok)
	assert_true(WildGen.biome_open(s, "creek"), "buying the boots opens the creek")
	assert_false(WildGen.biome_open(s, "moon"))
	assert_true(WildGen.biome_open({}, "forest"), "old saves without unlocks still have the forest")


# ---------------- varieties of the P1 types ----------------

func test_p1_varieties_generate_lazily_and_deterministically() -> void:
	var p1_types := ["cabbage", "elderberry", "grape", "oyster_mushroom", "pumpkin", "rosehip"]
	for sd in [7, 452, 99991]:
		var old := VarietyGen.generate_all(sd, 0)
		var p0 := old.duplicate(true)
		var added := VarietyGen.ensure_types(old, sd)
		assert_eq(added.size(), p1_types.size() * int(Data.rules().varieties.count_p1), "six varieties per P1 type")
		var full := VarietyGen.generate_all(sd, 1)
		for id in added:
			assert_has(p1_types, String(old[id].type))
			assert_eq(var_to_str(old[id]), var_to_str(full[id]), "%s same as a P1 roll" % id)
		for id in p0:
			assert_eq(var_to_str(old[id]), var_to_str(p0[id]), "P0 variety %s untouched" % id)
		assert_eq(VarietyGen.ensure_types(old, sd), [], "a second call adds nothing")
		var again := VarietyGen.generate_all(sd, 0)
		VarietyGen.ensure_types(again, sd)
		assert_eq(var_to_str(again), var_to_str(old), "same save seed, same P1 varieties")
		var rares := 0
		for id in added:
			rares += 1 if old[id].rarity == "rare" else 0
		assert_eq(rares, p1_types.size(), "one rare per type")
	# the demo save gets its P1 varieties without changing its forest
	var demo := DevTools.load_demo("res://dev/demo_save.json")
	if not demo.is_empty():
		var before := _fingerprint(WildGen.generate(int(demo.save_seed), int(demo.day), "forest", "rainy", demo.varieties))
		VarietyGen.ensure_types(demo.varieties, int(demo.save_seed))
		assert_true(demo.varieties.has("grape_6"))
		assert_eq(_fingerprint(WildGen.generate(int(demo.save_seed), int(demo.day), "forest", "rainy", demo.varieties)), before)


# ---------------- foraging: the bee hive ----------------

func test_forage_bee_hive_gives_honey_to_the_cupboard() -> void:
	var m := {}
	for i in 80:
		var c := _map("vineyard", i)
		if String(c.special.get("kind", "")) == "bee_hive":
			m = c
			break
	assert_false(m.is_empty(), "a vineyard with a bee hive in 80 seeds")
	if m.is_empty():
		return
	var hive: Dictionary = m.pickups.filter(func(p: Dictionary) -> bool: return p.kind == "hive")[0]
	var s := State.new_game(_seed(0))
	s.varieties = _vars
	for k in 6:
		s.bag.append(State.fresh("grape_1", 5, 3))
	assert_eq(Forage.bag_count(s), 30, "bag full")
	var honey0 := int(s.cupboard.get("honey", 0))
	var e0 := int(s.energy)
	var res := Forage.pick(s, m, int(hive.id))
	assert_true(res.ok, "honey needs no bag room")
	var n := int(WildGen.biome_table("bee_hive").honey)
	assert_eq(int(s.cupboard.honey), honey0 + n)
	assert_eq(int(s.energy), e0 - int(Data.rules().energy.costs.pick_bush))
	assert_eq(res.items, [{"kind": "addin", "id": "honey", "count": n}])
	assert_eq(Forage.bag_count(s), 30)
	assert_has(s.wild_today.vineyard.collected, int(hive.id))
	assert_eq(Forage.pick(s, m, int(hive.id)).reason, "UI_NOTHING_LEFT")
	var vis := Forage.visible_map(s, m)
	assert_eq(vis.pickups.size(), m.pickups.size() - 1)
	s.wild_today = {}
	s.energy = 1
	assert_eq(Forage.pick(s, m, int(hive.id)).reason, "UI_TIRED")


func test_forage_progress_is_kept_per_biome() -> void:
	var s := State.new_game(_seed(2))
	s.varieties = _vars
	var a := WildGen.generate(int(s.save_seed), int(s.day), "creek", "sunny", _vars)
	var f := WildGen.generate(int(s.save_seed), int(s.day), "forest", "sunny", _vars)
	assert_true(Forage.shake_tree(s, a, 0).ok)
	assert_eq(a.fruit_trees[0].type, "elderberry")
	assert_true(Forage.visible_map(s, a).fruit_trees[0].shaken)
	assert_false(Forage.visible_map(s, f).fruit_trees[0].shaken, "the creek's tree 0 is not the forest's")
	assert_eq(s.wild_today.creek.shaken, [0])
	assert_eq(s.wild_today.forest.shaken, [])


# ---------------- helpers ----------------

static func _fingerprint(m: Dictionary) -> String:
	var picks: Array = []
	var solid: PackedByteArray = (m.solid as PackedByteArray).duplicate()
	for p in m.pickups:
		if bool(p.get("p1", false)):
			if p.kind != "ground":
				solid[int(p.y) * int(m.w) + int(p.x)] = 0
			continue
		picks.append(p)
	var d := {"seed": m.seed, "biome": m.biome, "w": m.w, "h": m.h, "ground": m.ground, "decor": m.decor_trees,
		"fruit": m.fruit_trees, "pickups": picks, "special": m.special, "entrance": m.entrance, "clearings": m.clearings,
		"solid": solid}
	return var_to_str(d).md5_text()


func _assert_reachable(m: Dictionary, tag: String) -> void:
	var e: Vector2i = m.entrance
	assert_eq(e.y, int(m.h) - 1, tag + " entrance on the south edge")
	assert_true(WildGen.is_walkable(m, e), tag + " entrance walkable")
	var reach := {e: true}
	var queue: Array[Vector2i] = [e]
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for d: Vector2i in N4:
			if not reach.has(p + d) and WildGen.is_walkable(m, p + d):
				reach[p + d] = true
				queue.append(p + d)
	for c in m.clearings:
		assert_true(reach.has(c), "%s clearing %s reachable" % [tag, c])
	for t in m.fruit_trees:
		assert_true(_usable(reach, Vector2i(t.x, t.y), true), "%s tree %d reachable" % [tag, t.id])
	var blockers := 0
	for p in m.pickups:
		var blocker: bool = p.kind != "ground"
		blockers += 1 if blocker else 0
		assert_true(_usable(reach, Vector2i(p.x, p.y), blocker), "%s pickup %d (%s) reachable" % [tag, p.id, p.kind])
	var solid := 0
	for k in (m.solid as PackedByteArray).size():
		solid += int(m.solid[k])
	assert_eq(solid, m.decor_trees.size() + m.fruit_trees.size() + blockers, tag + " solid layer matches the lists")


func _usable(reach: Dictionary, c: Vector2i, blocker: bool) -> bool:
	if not blocker:
		return reach.has(c)
	for d: Vector2i in N4:
		if reach.has(c + d):
			return true
	return false


func _assert_cell_free(m: Dictionary, cells: Dictionary, o: Dictionary, tag: String) -> void:
	var c := Vector2i(int(o.x), int(o.y))
	assert_false(cells.has(c), "%s two objects on %s" % [tag, c])
	cells[c] = true
	assert_ne(int(m.ground[c.y * int(m.w) + c.x]), WildGen.T_WATER, "%s object on water at %s" % [tag, c])
