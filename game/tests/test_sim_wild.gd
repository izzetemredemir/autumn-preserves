extends "res://tests/_runner/test_case.gd"
## SIM-02: forest generator (spec §7.1) and foraging (spec §4, §7.1). Map checks run over 50 seeds.

const SEEDS := 50
const TYPES := ["apple", "crabapple", "pear", "quince", "blackberry", "chanterelle", "porcini"]

var _vars: Dictionary = {}


func before_each() -> void:
	_vars = _hand_varieties()


## 4 varieties per type, tiers as rules.varieties.tiers_p0 (VarietyGen is written in parallel).
func _hand_varieties() -> Dictionary:
	var out := {}
	var tiers: Array = Data.rules().varieties.tiers_p0
	for t in TYPES:
		for k in tiers.size():
			var id := "%s_%d" % [t, k + 1]
			out[id] = {"id": id, "type": t, "name": id, "rarity": tiers[k], "tier": k, "color_shift": 0,
				"taste_delta": [0, 0, 0, 0, 0], "size": "medium"}
	return out


func _seed(i: int) -> int:
	return 1000 + i * 7919


func _map(i: int, weather := "sunny") -> Dictionary:
	return WildGen.generate(_seed(i), 1 + i % 7, "forest", weather, _vars)


# ---------------- generator ----------------

func test_wild_same_seed_identical_map() -> void:
	for i in SEEDS:
		var a := _map(i)
		var b := WildGen.generate(_seed(i), 1 + i % 7, "forest", "sunny", _vars.duplicate(true))
		assert_eq(var_to_str(a), var_to_str(b), "seed %d" % _seed(i))
	assert_ne(var_to_str(_map(0)), var_to_str(_map(1)), "different seeds differ")
	var m := _map(0)
	assert_eq(int(m.seed), Seeds.seed_for(_seed(0), "wild:forest", 1), "map seed = wild:<biome> stream seed")
	assert_eq(int(m.w), int(Data.rules().wild.w))
	assert_eq(int(m.h), int(Data.rules().wild.h))


func test_wild_everything_reachable_from_entrance() -> void:
	for i in SEEDS:
		var m := _map(i)
		var w: int = m.w
		var h: int = m.h
		var e: Vector2i = m.entrance
		assert_eq(e.y, h - 1, "entrance on the south edge")
		assert_true(WildGen.is_walkable(m, e), "entrance walkable")
		var reach := _flood(m)
		for c in m.clearings:
			assert_true(reach.has(c), "seed %d clearing %s reachable" % [_seed(i), c])
		for t in m.fruit_trees:
			assert_true(_usable(reach, Vector2i(t.x, t.y), true), "seed %d tree %d reachable" % [_seed(i), t.id])
		for p in m.pickups:
			var blocker: bool = p.kind == "bush"
			assert_true(_usable(reach, Vector2i(p.x, p.y), blocker), "seed %d pickup %d reachable" % [_seed(i), p.id])
		# the solid layer agrees with the object lists
		var solid := 0
		for k in w * h:
			solid += int(m.solid[k])
		var bushes := 0
		for p in m.pickups:
			bushes += 1 if p.kind == "bush" else 0
		assert_eq(solid, m.decor_trees.size() + m.fruit_trees.size() + bushes, "seed %d solid count" % _seed(i))


func test_wild_counts_in_rules_ranges() -> void:
	var wr: Dictionary = Data.rules().wild
	var tree_types := WildGen.biome_types("forest", "tree")
	var bush_types := WildGen.biome_types("forest", "bush")
	var ground_types := WildGen.biome_types("forest", "ground")
	assert_eq(tree_types, ["apple", "crabapple", "pear"])
	assert_eq(bush_types, ["blackberry"])
	assert_eq(ground_types, ["chanterelle", "porcini", "walnut"])
	for i in SEEDS:
		var m := _map(i)
		var tag := "seed %d" % _seed(i)
		var fruit := 0
		var bush := 0
		var ground := 0
		var cells := {}
		for t in m.fruit_trees:
			_assert_cell_free(m, cells, t, tag)
			if t.get("special", false):
				continue
			fruit += 1
			assert_has(tree_types, t.type, tag)
			assert_true(_vars.has(t.variety) and _vars[t.variety].type == t.type, tag + " tree variety " + t.variety)
			assert_true(int(t.yield) >= 2 and int(t.yield) <= 3, tag + " yield")
		for p in m.pickups:
			_assert_cell_free(m, cells, p, tag)
			if p.get("special", false):
				continue
			if p.kind == "bush":
				bush += 1
				assert_has(bush_types, p.type, tag)
			else:
				ground += 1
				assert_has(ground_types, p.type, tag)
			if p.type == "walnut":
				assert_eq(p.variety, "", tag + " nuts have no variety")
			else:
				assert_true(_vars.has(p.variety) and _vars[p.variety].type == p.type, tag + " variety " + p.variety)
		for d in m.decor_trees:
			_assert_cell_free(m, cells, d, tag)
			assert_has(WildGen.DECOR_KINDS, d.kind, tag)
		assert_true(fruit >= int(wr.fruit_trees[0]) and fruit <= int(wr.fruit_trees[1]), "%s fruit trees %d" % [tag, fruit])
		assert_true(bush >= int(wr.bushes[0]) and bush <= int(wr.bushes[1]), "%s bushes %d" % [tag, bush])
		assert_true(ground >= int(wr.ground[0]) and ground <= int(wr.ground[1]), "%s ground %d" % [tag, ground])
		var nc: int = m.clearings.size()
		assert_true(nc >= int(wr.clearings[0]) and nc <= int(wr.clearings[1]), "%s clearings %d" % [tag, nc])
		for k in m.fruit_trees.size():
			assert_eq(int(m.fruit_trees[k].id), k, tag + " tree ids are indices")
		for k in m.pickups.size():
			assert_eq(int(m.pickups[k].id), k, tag + " pickup ids are indices")


## Path-side decor trees first, then the "near" fallback (a 4-neighbour within 3 steps of the path), so a fruit
## tree stands at most 4 tiles from a path tile. With poisson_r 4 (INT-WILD) the fallback is used more often.
func test_wild_fruit_trees_stand_beside_the_path() -> void:
	for i in SEEDS:
		var m := _map(i)
		var w: int = m.w
		for t in m.fruit_trees:
			if t.get("special", false):
				continue
			var beside := false
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					var x: int = int(t.x) + dx
					var y: int = int(t.y) + dy
					if x >= 0 and y >= 0 and x < w and y < int(m.h):
						var g: int = m.ground[y * w + x]
						beside = beside or g == WildGen.T_PATH or g == WildGen.T_STONE
			assert_true(beside, "seed %d tree %d near the path" % [_seed(i), t.id])


func test_wild_stream_and_stepping_stones() -> void:
	var with_water := 0
	for i in SEEDS:
		var m := _map(i)
		var w: int = m.w
		var water := 0
		for k in w * int(m.h):
			var g: int = m.ground[k]
			water += 1 if g == WildGen.T_WATER else 0
			if g == WildGen.T_STONE:
				assert_true(WildGen.is_walkable(m, Vector2i(k % w, k / w)), "stones are walkable")
		if water > 0:
			with_water += 1
			assert_false(WildGen.is_walkable(m, _first_water(m)), "water is not walkable")
	# rules.wild.stream_chance = 0.4 -> ~20 of 50
	assert_true(with_water >= 8 and with_water <= 32, "maps with a stream: %d / %d" % [with_water, SEEDS])


func test_wild_special_places() -> void:
	var specials := 0
	var fr: Dictionary = Data.rules().wild
	for i in SEEDS:
		var m := _map(i)
		if m.special.is_empty():
			continue
		specials += 1
		var tag := "seed %d %s" % [_seed(i), m.special.kind]
		assert_has(fr.special_kinds_p0, m.special.kind, tag)
		if m.special.kind == "mushroom_ring":
			var n := 0
			for p in m.pickups:
				if p.get("special", false):
					n += 1
					assert_eq(Data.ingredients()[p.type].group, "mushroom", tag)
			assert_true(n >= int(fr.ring_mushrooms[0]) and n <= int(fr.ring_mushrooms[1]), "%s ring %d" % [tag, n])
		else:
			var garden := WildGen.garden_varieties(_seed(i), _vars)
			var n := 0
			for t in m.fruit_trees:
				if t.get("special", false):
					n += 1
					assert_eq(t.type, "quince", tag)
					assert_false(garden.has(t.variety), tag + " orchard quince differs from the garden's")
			assert_eq(n, int(fr.orchard_quince_trees), tag)
	# rules.wild.special_chance = 0.35 -> ~17 of 50
	assert_true(specials >= 6 and specials <= 30, "special places: %d / %d" % [specials, SEEDS])


func test_wild_rain_doubles_mushroom_weight() -> void:
	var sunny := WildGen.ground_type_weights("forest", "sunny")
	var rainy := WildGen.ground_type_weights("forest", "rainy")
	var mult := float(Data.rules().weather.rain_mushroom_mult)
	assert_eq(mult, 2.0)
	assert_eq(sunny.types, rainy.types)
	for k in (sunny.types as Array).size():
		var t: String = sunny.types[k]
		var expect: float = sunny.weights[k] * (mult if Data.ingredients()[t].group == "mushroom" else 1.0)
		assert_near(float(rainy.weights[k]), expect, 0.0001, t)
	# porcini is sparse: half the chanterelle weight
	assert_near(float(sunny.weights[1]), float(sunny.weights[0]) * WildGen.uncommon_spawn_weight())
	# over 50 maps rain shifts ground points to mushrooms; the layout itself does not move
	var share := {"sunny": [0, 0], "rainy": [0, 0]}
	for i in SEEDS:
		var a := _map(i, "sunny")
		var b := _map(i, "rainy")
		assert_eq(var_to_str(_positions(a)), var_to_str(_positions(b)), "weather keeps the layout, seed %d" % _seed(i))
		for pair in [["sunny", a], ["rainy", b]]:
			for p in pair[1].pickups:
				if p.kind == "ground" and not p.get("special", false):
					share[pair[0]][1] += 1
					if p.type != "walnut":
						share[pair[0]][0] += 1
	var s: float = float(share.sunny[0]) / share.sunny[1]
	var r: float = float(share.rainy[0]) / share.rainy[1]
	assert_true(r > s + 0.05, "mushroom share sunny %.2f rainy %.2f" % [s, r])


func test_wild_empty_varieties_fallback() -> void:
	for i in 10:
		var m := WildGen.generate(_seed(i), 1, "forest", "sunny", {})
		for t in m.fruit_trees:
			assert_eq(t.variety, t.type + "_1")
		for p in m.pickups:
			assert_eq(p.variety, "" if p.type == "walnut" else p.type + "_1")


func test_wild_debug_steps() -> void:
	var m := _map(3)
	if OS.is_debug_build():
		assert_eq((m.steps as Dictionary).keys(), ["1_ground", "2_stream", "3_decor", "4_paths", "5_pickups", "6_special", "7_validate"])
		assert_eq((m.steps["1_ground"].ground as PackedByteArray).size(), int(m.w) * int(m.h))
	else:
		assert_true((m.steps as Dictionary).is_empty())


func test_wild_generation_time() -> void:
	WildGen.generate(1, 1, "forest", "sunny", _vars)  # warm caches
	var total := 0
	var worst := 0
	for i in SEEDS:
		var t0 := Time.get_ticks_usec()
		WildGen.generate(_seed(i) + 17, 2 + i, "forest", "rainy" if i % 4 == 0 else "sunny", _vars)
		var dt := Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
	var avg_ms := total / 1000.0 / SEEDS
	print("wild gen: avg %.1f ms, max %.1f ms over %d maps (48x30)" % [avg_ms, worst / 1000.0, SEEDS])
	assert_true(avg_ms < 50.0, "average %.1f ms" % avg_ms)


# ---------------- foraging ----------------

func _game() -> Dictionary:
	var s := State.new_game(777)
	s.varieties = _vars
	return s


func _forest(s: Dictionary) -> Dictionary:
	return WildGen.generate(int(s.save_seed), int(s.day), "forest", "sunny", _vars)


func _first(m: Dictionary, kind: String, type := "") -> Dictionary:
	for p in m.pickups:
		if p.kind == kind and (type == "" or p.type == type) and not p.get("special", false):
			return p
	return {}


func test_forage_pick_ground_and_bush() -> void:
	var s := _game()
	var m := _forest(s)
	var e0 := int(s.energy)
	var g := _first(m, "ground")
	var res := Forage.pick(s, m, int(g.id))
	assert_true(res.ok)
	assert_eq(Forage.bag_count(s), 1)
	assert_eq(int(s.energy), e0 - 1, "pick_ground costs 1")
	assert_eq(int(res.energy), e0 - 1)
	assert_eq(s.wild_today.forest.collected, [int(g.id)])
	assert_eq(int(s.stats.items_foraged), 1)
	var again := Forage.pick(s, m, int(g.id))
	assert_false(again.ok)
	assert_eq(again.reason, "UI_NOTHING_LEFT")
	assert_eq(int(s.energy), e0 - 1, "a failed pick is free")
	var b := _first(m, "bush")
	var rb := Forage.pick(s, m, int(b.id))
	assert_true(rb.ok)
	assert_eq(Forage.bag_count(s), 3, "a bush gives 2")
	assert_eq(int(s.energy), e0 - 3, "pick_bush costs 2")
	assert_eq(rb.items[0].kind, "fresh")
	assert_eq(rb.items[0].variety, b.variety)
	assert_eq(int(rb.items[0].days_left), int(Data.ingredients().blackberry.shelf_days))
	assert_has(s.found_varieties, b.variety)
	var vis := Forage.visible_map(s, m)
	assert_eq(vis.pickups.size(), m.pickups.size() - 2)
	for p in vis.pickups:
		assert_ne(int(p.id), int(g.id))
		assert_ne(int(p.id), int(b.id))
	assert_eq(m.pickups.size(), _forest(s).pickups.size(), "the map itself is not changed")


func test_forage_nut_item() -> void:
	for i in 20:
		var s := _game()
		s.save_seed = 777 + i
		var m := _forest(s)
		var nut := _first(m, "ground", "walnut")
		if nut.is_empty():
			continue
		var res := Forage.pick(s, m, int(nut.id))
		assert_true(res.ok)
		assert_eq(res.items[0], State.nut("walnut", 1))
		return
	fail("no walnut in 20 maps")


func test_forage_shake_tree() -> void:
	var s := _game()
	var m := _forest(s)
	var e0 := int(s.energy)
	var t: Dictionary = m.fruit_trees[0]
	var res := Forage.shake_tree(s, m, int(t.id))
	assert_true(res.ok)
	var n := Forage.bag_count(s)
	assert_eq(n, int(t.yield))
	assert_true(n >= 2 and n <= 3, "2-3 fruit")
	assert_eq(int(s.energy), e0 - 3, "shake costs 3")
	assert_eq(res.items[0].variety, t.variety)
	var vis := Forage.visible_map(s, m)
	assert_true(vis.fruit_trees[0].shaken)
	assert_false(vis.fruit_trees[1].shaken)
	var again := Forage.shake_tree(s, m, int(t.id))
	assert_false(again.ok)
	assert_eq(again.reason, "UI_NOTHING_LEFT")
	assert_false(Forage.shake_tree(s, m, 999).ok, "unknown tree")


func test_forage_bag_full() -> void:
	var s := _game()
	var m := _forest(s)
	for k in 5:
		s.bag.append(State.fresh("pear_1", 5, 4))
	s.bag.append(State.fresh("pear_2", 3, 4))
	assert_eq(Forage.bag_count(s), 28)
	var res := Forage.shake_tree(s, m, 0)
	assert_false(res.ok)
	assert_eq(res.reason, "UI_BAG_FULL", "shaking needs 3 free slots")
	assert_true(Forage.pick(s, m, int(_first(m, "bush").id)).ok, "2 free: a bush fits")
	assert_eq(Forage.bag_count(s), 30)
	var g := Forage.pick(s, m, int(_first(m, "ground").id))
	assert_false(g.ok)
	assert_eq(g.reason, "UI_BAG_FULL")


func test_forage_tired() -> void:
	var s := _game()
	var m := _forest(s)
	s.energy = 2
	var res := Forage.shake_tree(s, m, 0)
	assert_false(res.ok)
	assert_eq(res.reason, "UI_TIRED")
	assert_eq(int(s.energy), 2)
	assert_eq(Forage.visible_map(s, m).fruit_trees[0].shaken, false, "a failed shake leaves the tree")
	assert_true(Forage.pick(s, m, int(_first(m, "bush").id)).ok)
	assert_eq(int(s.energy), 0)
	assert_eq(Forage.pick(s, m, int(_first(m, "ground").id)).reason, "UI_TIRED")


func test_forage_ids_from_json_floats() -> void:
	var s := _game()
	var m := _forest(s)
	s.wild_today = {"forest": {"collected": [0.0, 2.0], "shaken": [1.0]}}
	assert_eq(Forage.pick(s, m, 0).reason, "UI_NOTHING_LEFT")
	assert_eq(Forage.shake_tree(s, m, 1).reason, "UI_NOTHING_LEFT")
	var vis := Forage.visible_map(s, m)
	assert_eq(vis.pickups.size(), m.pickups.size() - 2)
	assert_true(vis.fruit_trees[1].shaken)


func test_forage_empty_bag_merges_stacks() -> void:
	var s := _game()
	s.inbox = [State.fresh("apple_1", 3, 6)]
	s.bag = [State.fresh("apple_1", 4, 6), State.fresh("apple_1", 1, 5), State.nut("walnut", 7), State.nut("walnut", 6)]
	Forage.empty_bag_to_inbox(s)
	assert_eq(s.bag, [])
	assert_eq(s.inbox, [State.fresh("apple_1", 5, 6), State.fresh("apple_1", 2, 6), State.fresh("apple_1", 1, 5),
		State.nut("walnut", 10), State.nut("walnut", 3)])
	var total := 0
	for it in s.inbox:
		total += int(it.count)
	assert_eq(total, 21, "nothing lost")


func test_forage_bag_stacks_on_pick() -> void:
	var s := _game()
	var list: Array = []
	Forage.add_stacked(list, State.fresh("pear_1", 3, 4))
	Forage.add_stacked(list, State.fresh("pear_1", 3, 4))
	Forage.add_stacked(list, State.fresh("pear_1", 3, 3))
	assert_eq(list, [State.fresh("pear_1", 5, 4), State.fresh("pear_1", 1, 4), State.fresh("pear_1", 3, 3)])
	assert_eq(int(s.energy), int(Data.rules().energy.base))


# ---------------- helpers ----------------

func _flood(m: Dictionary) -> Dictionary:
	var seen := {}
	var e: Vector2i = m.entrance
	seen[e] = true
	var queue: Array[Vector2i] = [e]
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if not seen.has(q) and WildGen.is_walkable(m, q):
				seen[q] = true
				queue.append(q)
	return seen


func _usable(reach: Dictionary, c: Vector2i, blocker: bool) -> bool:
	if not blocker:
		return reach.has(c)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if reach.has(c + d):
			return true
	return false


func _assert_cell_free(m: Dictionary, cells: Dictionary, o: Dictionary, tag: String) -> void:
	var c := Vector2i(int(o.x), int(o.y))
	assert_false(cells.has(c), "%s two objects on %s" % [tag, c])
	cells[c] = true
	assert_ne(int(m.ground[c.y * int(m.w) + c.x]), WildGen.T_WATER, "%s object on water at %s" % [tag, c])


func _first_water(m: Dictionary) -> Vector2i:
	var w: int = m.w
	for k in w * int(m.h):
		if int(m.ground[k]) == WildGen.T_WATER:
			return Vector2i(k % w, k / w)
	return Vector2i(-1, -1)


func _positions(m: Dictionary) -> Array:
	var out: Array = []
	for t in m.fruit_trees:
		out.append(Vector2i(t.x, t.y))
	for p in m.pickups:
		out.append([p.kind, Vector2i(p.x, p.y)])
	return out
