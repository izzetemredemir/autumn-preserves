extends "res://tests/_runner/test_case.gd"
## WILD-LIFE: where the ambient critters sit (CritterRules, pure): deterministic per (save seed, day, biome), on valid
## cells, within the node budget, fewer birds in rain, the same elsewhere in other weather.

const SEEDS := [1, 7, 42, 4242, 90210]
const BIOMES := ["forest", "vineyard", "creek"]

var _vars: Dictionary = {}


func before_each() -> void:
	if _vars.is_empty():
		_vars = VarietyGen.generate_all(4242, 0)
		VarietyGen.ensure_types(_vars, 4242)


func _map(sd: int, day: int, biome: String, weather := "sunny") -> Dictionary:
	return WildGen.generate(sd, day, biome, weather, _vars)


func _count(list: Array, kind: String) -> int:
	var n := 0
	for p in list:
		n += 1 if p.kind == kind else 0
	return n


func test_wild_is_deterministic() -> void:
	for biome in BIOMES:
		for sd in SEEDS:
			var m := _map(sd, 3, biome)
			assert_eq(CritterRules.wild(m, sd, 3, "sunny"), CritterRules.wild(m, sd, 3, "sunny"), "%s seed %d" % [biome, sd])


func test_days_differ() -> void:
	for biome in BIOMES:
		var seen := {}
		for day in range(1, 9):
			seen[var_to_str(CritterRules.wild(_map(42, day, biome), 42, day, "sunny"))] = true
		assert_true(seen.size() > 3, "%s: critters move from day to day" % biome)


func test_each_biome_has_its_critters() -> void:
	for sd in SEEDS:
		var f := CritterRules.wild(_map(sd, 2, "forest"), sd, 2, "sunny")
		assert_true(_count(f, "squirrel") >= 1 and _count(f, "hedgehog") >= 1 and _count(f, "bird") >= 3, "forest %d" % sd)
		var v := CritterRules.wild(_map(sd, 2, "vineyard"), sd, 2, "sunny")
		var perched := 0
		for p in v:
			perched += 1 if p.kind == "bird" and bool(p.perch) else 0
		assert_true(perched >= 3, "vineyard %d sparrows on the posts" % sd)
		var c := CritterRules.wild(_map(sd, 2, "creek"), sd, 2, "sunny")
		assert_true(_count(c, "frog") >= 1 and _count(c, "ring") >= 3, "creek %d frogs and rings" % sd)


func test_cells_are_valid_and_within_budget() -> void:
	for biome in BIOMES:
		for sd in SEEDS:
			for day in [1, 4, 9]:
				var m := _map(sd, day, biome)
				var list := CritterRules.wild(m, sd, day, "sunny")
				assert_true(list.size() <= CritterRules.MAX_NODES, "%s %d: %d nodes" % [biome, sd, list.size()])
				var seen := {}
				for p in list:
					var c: Vector2i = p.cell
					var g := int(m.ground[c.y * int(m.w) + c.x])
					match String(p.kind):
						"ring":
							assert_eq(g, WildGen.T_WATER, "ring on water")
						"frog":
							assert_eq(g, WildGen.T_BANK, "frog on a bank")
						"squirrel":
							assert_false(WildGen.is_walkable(m, c), "squirrel at a trunk")
						"bird":
							if not bool(p.perch):
								assert_true(WildGen.is_walkable(m, c), "ground bird on open ground")
						_:
							assert_true(WildGen.is_walkable(m, c), "%s on open ground" % p.kind)
					if p.kind != "squirrel":
						assert_false(seen.has(c), "one critter per cell")
						seen[c] = true


func test_rain_leaves_fewer_birds_and_the_rest_alone() -> void:
	for biome in BIOMES:
		for sd in SEEDS:
			var m := _map(sd, 5, biome)
			var dry := CritterRules.wild(m, sd, 5, "sunny")
			var wet := CritterRules.wild(m, sd, 5, "rainy")
			assert_true(_count(wet, "bird") < _count(dry, "bird"), "%s %d: fewer birds in rain" % [biome, sd])
			for k in ["squirrel", "hedgehog", "frog", "ring"]:
				assert_eq(_count(wet, k), _count(dry, k), "%s: %s unchanged" % [biome, k])
			var kept: Array = []
			for p in dry:
				if p.kind == "bird":
					kept.append(p)
			for i in _count(wet, "bird"):
				assert_true(kept.has(wet[wet.size() - _count(wet, "bird") + i]), "rain keeps the same birds, just fewer")
			for w in ["windy", "foggy"]:
				assert_eq(CritterRules.wild(m, sd, 5, w), dry, "%s: %s changes nothing here (the scene handles it)" % [biome, w])


func test_birds_out() -> void:
	assert_eq(CritterRules.birds_out(5, "sunny"), 5)
	assert_eq(CritterRules.birds_out(5, "rainy"), 2)
	assert_eq(CritterRules.birds_out(1, "rainy"), 0)


func test_garden_robin_on_the_fence_is_deterministic() -> void:
	var open := func(c: Vector2i) -> bool: return true
	for sd in SEEDS:
		for day in range(1, 12):
			var a := CritterRules.garden(sd, day, "sunny", open)
			assert_eq(a, CritterRules.garden(sd, day, "sunny", open), "seed %d day %d" % [sd, day])
			assert_true(a.size() >= 2 and a.size() <= CritterRules.MAX_NODES)
			assert_eq(String(a[0].species), "robin", "the robin comes first")
			var c: Vector2i = a[0].cell
			assert_eq(c.y, CritterRules.Layout.H - 1, "on the bottom fence")
			assert_false(CritterRules.Layout.is_gate(c), "not on the gate")
			var rain := CritterRules.garden(sd, day, "rainy", open)
			assert_true(rain.size() < a.size() and rain.size() >= 1, "rain: the robin stays, fewer birds")
	assert_eq(CritterRules.garden(1, 1, "sunny", Callable()).size(), 1, "no lawn when nothing is walkable")


func test_empty_map_has_none() -> void:
	assert_eq(CritterRules.wild({}, 1, 1, "sunny"), [])
