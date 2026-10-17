extends "res://tests/_runner/test_case.gd"
## FUN-FOREST: the forest's little surprises (ForestSurprises). Pure rules: determinism per (seed, day), flood-fill
## reachability, the plain WildGen + species pickup list stays an unchanged prefix (seeds 1, 452, the festival),
## consumed ones stay consumed, a full bag takes nothing.

const CASES := [[1, 14], [452, 14], [24, 14], [7, 3], [99, 20]]  ## [save_seed, day]; (24, 14) is the festival forest
const SEEDS := 40


func _state(sd: int, day: int) -> Dictionary:
	var s := State.new_game(sd)
	VarietyGen.ensure_types(s.varieties, sd)
	s.day = day
	SpeciesGen.sync(s)
	return s


## The forest as the wild scene builds it: WildGen, then the species pickups.
func _map(s: Dictionary) -> Dictionary:
	var m := WildGen.generate(int(s.save_seed), int(s.day), "forest", "sunny", s.varieties)
	SpeciesGen.add_pickups(m, int(s.save_seed), int(s.day))
	return m


func _flood(m: Dictionary) -> Dictionary:
	var seen := {m.entrance: true}
	var q: Array[Vector2i] = [m.entrance]
	var head := 0
	while head < q.size():
		var p := q[head]
		head += 1
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = p + d
			if not seen.has(n) and WildGen.is_walkable(m, n):
				seen[n] = true
				q.append(n)
	return seen


func test_same_seed_and_day_give_the_same_plan() -> void:
	for c in CASES:
		var s := _state(c[0], c[1])
		var a := ForestSurprises.plan(_map(s), c[0], c[1], s.varieties)
		var s2 := _state(c[0], c[1])
		var b := ForestSurprises.plan(_map(s2), c[0], c[1], s2.varieties)
		assert_eq(var_to_str(a), var_to_str(b), "seed %d day %d" % c)
		assert_false(a.is_empty(), "something to find, seed %d day %d" % c)
	var s1 := _state(1, 14)
	var s3 := _state(1, 15)
	assert_ne(var_to_str(ForestSurprises.plan(_map(s1), 1, 14, s1.varieties)),
		var_to_str(ForestSurprises.plan(_map(s3), 1, 15, s3.varieties)), "another day, another plan")


func test_every_surprise_is_walkable_reachable_and_off_the_items() -> void:
	for i in SEEDS:
		var sd := 500 + i * 37
		var day := 1 + i % 20
		var s := _state(sd, day)
		var m := _map(s)
		var reach := _flood(m)
		var taken := {}
		for key in ["decor_trees", "fruit_trees", "pickups"]:
			for t in m[key]:
				taken[Vector2i(int(t.x), int(t.y))] = true
		var plan := ForestSurprises.plan(m, sd, day, s.varieties)
		var sparkles := 0
		var cells := {}
		for e: Dictionary in plan:
			var c := Vector2i(int(e.x), int(e.y))
			assert_true(WildGen.is_walkable(m, c), "seed %d walkable %s" % [sd, c])
			assert_true(reach.has(c), "seed %d reachable %s" % [sd, c])
			assert_false(taken.has(c), "seed %d off the items %s" % [sd, c])
			assert_false(cells.has(c), "one per tile")
			assert_ne(int(m.ground[c.y * int(m.w) + c.x]), WildGen.T_PATH, "not on the path")
			assert_true(c.distance_squared_to(m.entrance) > 8, "away from the entrance")
			assert_true(["bush", "pile", "sparkle"].has(e.kind))
			cells[c] = true
			sparkles += 1 if e.kind == "sparkle" else 0
		assert_true(sparkles <= 1, "at most one sparkle a day")
		assert_true(plan.size() >= 3, "a few per forest (seed %d: %d)" % [sd, plan.size()])


func test_the_plain_map_and_pickups_are_an_unchanged_prefix() -> void:
	for c in [[1, 14], [452, 14], [24, 14]]:
		var s := _state(c[0], c[1])
		var plain := WildGen.generate(c[0], c[1], "forest", "sunny", s.varieties)
		var n_plain := (plain.pickups as Array).size()
		SpeciesGen.add_pickups(plain, c[0], c[1])
		var before := var_to_str(plain)
		var picks_before := var_to_str(plain.pickups)
		ForestSurprises.plan(plain, c[0], c[1], s.varieties)
		assert_eq(var_to_str(plain), before, "the plan leaves the map alone (seed %d)" % c[0])
		assert_eq(var_to_str(plain.pickups), picks_before)
		var again := WildGen.generate(c[0], c[1], "forest", "sunny", s.varieties)
		assert_eq(var_to_str((plain.pickups as Array).slice(0, n_plain)), var_to_str(again.pickups),
			"WildGen pickups come first, seed %d" % c[0])
		SpeciesGen.add_pickups(again, c[0], c[1])
		assert_eq(var_to_str(again.pickups), picks_before, "then the species pickups")


func test_festival_forest_has_surprises_and_other_biomes_none() -> void:
	var fs := FestivalFacts.load_save()
	if not fs.is_empty():
		VarietyGen.ensure_types(fs.varieties, int(fs.save_seed))
		var m := _map(fs)
		assert_false(ForestSurprises.plan(m, int(fs.save_seed), int(fs.day), fs.varieties).is_empty(), "festival forest")
	var s := _state(3, 5)
	var vm := WildGen.generate(3, 5, "vineyard", "sunny", s.varieties)
	assert_true(ForestSurprises.plan(vm, 3, 5, s.varieties).is_empty(), "vineyard has none")


func test_collect_consumes_for_the_day() -> void:
	for sd in 40:
		var s := _state(sd, 12)
		var plan := ForestSurprises.plan(_map(s), sd, 12, s.varieties)
		for e: Dictionary in plan:
			var r := ForestSurprises.collect(s, e)
			assert_true(bool(r.ok), "first take works")
			assert_true(ForestSurprises.is_consumed(s, int(e.id)))
			var again := ForestSurprises.collect(s, e)
			assert_false(bool(again.ok), "taken stays taken")
		assert_eq(ForestSurprises.remaining(s, plan).size(), 0)
		s.wild_today = {}  # the next morning
		assert_eq(ForestSurprises.remaining(s, plan).size(), plan.size(), "all back the next day")


func test_rewards_land_in_the_bag_and_the_purse() -> void:
	var found_item := false
	var found_coin := false
	for sd in 60:
		var s := _state(sd, 12)
		var plan := ForestSurprises.plan(_map(s), sd, 12, s.varieties)
		for e: Dictionary in plan:
			var bag0 := Forage.bag_count(s)
			var coins0 := int(s.coins)
			var r := ForestSurprises.collect(s, e)
			match String(e.reward.t):
				"item", "nut":
					found_item = true
					assert_eq(Forage.bag_count(s), bag0 + int(e.reward.count), "items go in the bag")
					assert_eq((r.items as Array).size(), 1)
				"coins":
					found_coin = true
					assert_eq(int(s.coins), coins0 + int(e.reward.n), "coins go in the purse")
					assert_eq(Forage.bag_count(s), bag0)
				_:
					assert_eq(Forage.bag_count(s), bag0)
					assert_eq(int(s.coins), coins0)
	assert_true(found_item and found_coin, "both kinds show up over 60 seeds")


func test_a_full_bag_takes_nothing() -> void:
	for sd in 60:
		var s := _state(sd, 12)
		var plan := ForestSurprises.plan(_map(s), sd, 12, s.varieties)
		var e: Dictionary = {}
		for cand: Dictionary in plan:
			if ForestSurprises.needs_room(cand):
				e = cand
				break
		if e.is_empty():
			continue
		s.bag = [State.nut("walnut", Forage.bag_capacity(s))]
		var r := ForestSurprises.collect(s, e)
		assert_false(bool(r.ok))
		assert_eq(String(r.reason), "UI_BAG_FULL")
		assert_false(ForestSurprises.is_consumed(s, int(e.id)), "still there")
		return
	fail("no seed had an item surprise")


func test_old_saves_without_the_key_work() -> void:
	var s := _state(2, 4)
	s.erase("wild_today")
	var e := {"id": 0, "kind": "pile", "x": 5, "y": 5, "reward": {"t": "none"}}
	assert_true(bool(ForestSurprises.collect(s, e).ok))
	assert_true(ForestSurprises.is_consumed(s, 0))
