extends "res://tests/_runner/test_case.gd"
## P1-SEEDLAB: WildGen step recording for the Seed Lab replay (spec §10). Recording is an explicit opt-in that works in
## release builds and never changes the map.

const SEEDS := 16
const KEYS := ["1_ground", "2_stream", "3_decor", "4_paths", "5_pickups", "6_special", "7_validate", "8_p1"]
const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _vars: Dictionary = {}


func before_each() -> void:
	if _vars.is_empty():
		_vars = VarietyGen.generate_all(4242, 0)


func _seed(i: int) -> int:
	return 31 + i * 104729


func _stepped(i: int) -> Dictionary:
	return WildGen.generate(_seed(i), 1 + i % 5, "forest", "rainy" if i % 3 == 0 else "sunny", _vars, true)


func _without_steps(m: Dictionary) -> String:
	var c := m.duplicate()
	c.erase("steps")
	return var_to_str(c)


func test_wild_steps_final_map_equals_normal_call() -> void:
	for i in SEEDS:
		var plain := WildGen.generate(_seed(i), 1 + i % 5, "forest", "rainy" if i % 3 == 0 else "sunny", _vars)
		var stepped := _stepped(i)
		assert_eq(_without_steps(stepped), _without_steps(plain), "seed %d" % _seed(i))


func test_wild_steps_recorded_on_request() -> void:
	var m := _stepped(0)
	var st: Dictionary = m.steps
	assert_eq(st.keys(), KEYS)
	var n := int(m.w) * int(m.h)
	assert_eq((st["1_ground"].ground as PackedByteArray).size(), n)
	assert_eq((st["1_ground"].noise as PackedFloat32Array).size(), n)
	assert_eq(st["1_ground"].entrance, m.entrance)
	assert_eq(int(st["3_decor"].poisson_r), int(Data.rules().wild.poisson_r))
	assert_eq((st["7_validate"].flood as PackedInt32Array).size(), n)
	assert_eq(var_to_str(st["4_paths"].ground), var_to_str(m.ground), "nothing after the paths changes the ground")
	assert_eq(var_to_str(st["6_special"].decor_trees), var_to_str(m.decor_trees), "decor is final after step 6")


func test_wild_steps_stream_is_the_walk() -> void:
	var with_stream := 0
	for i in SEEDS:
		var m := _stepped(i)
		var g1: PackedByteArray = m.steps["1_ground"].ground
		var g2: PackedByteArray = m.steps["2_stream"].ground
		var walk: Array = m.steps["2_stream"].stream
		var w := int(m.w)
		var water := 0
		for k in g2.size():
			assert_ne(int(g1[k]), WildGen.T_WATER, "no water before the stream")
			if g2[k] == WildGen.T_WATER:
				water += 1
		assert_eq(walk.size(), water, "every new water tile once, seed %d" % _seed(i))
		var seen := {}
		for c: Vector2i in walk:
			assert_eq(int(g2[c.y * w + c.x]), WildGen.T_WATER)
			assert_false(seen.has(c), "no repeats")
			seen[c] = true
		if not walk.is_empty():
			with_stream += 1
			var first: Vector2i = walk[0]
			assert_true(first.x == 0 or first.y == 0, "the walk starts on the west or north edge")
	assert_true(with_stream > 0 and with_stream < SEEDS, "some maps have a stream (%d/%d)" % [with_stream, SEEDS])


func test_wild_steps_decor_order_keeps_poisson_radius() -> void:
	for i in 6:
		var m := _stepped(i)
		var trees: Array = m.steps["3_decor"].decor_trees
		var r := int(m.steps["3_decor"].poisson_r)
		for a in trees.size():
			for b in range(a + 1, trees.size()):
				var dx := int(trees[a].x) - int(trees[b].x)
				var dy := int(trees[a].y) - int(trees[b].y)
				assert_true(dx * dx + dy * dy >= r * r, "trees %d and %d too close" % [a, b])
		var before := _cells(trees)
		for key in ["4_paths", "5_pickups", "6_special"]:
			var now := _cells(m.steps[key].decor_trees)
			for c in now:
				assert_true(before.has(c), "%s adds no decor tree" % key)
			before = now


func test_wild_steps_paths_link_entrance_to_clearings() -> void:
	for i in SEEDS:
		var m := _stepped(i)
		var paths: Array = m.steps["4_paths"].paths
		var clearings: Array = m.steps["4_paths"].clearings
		assert_eq(paths.size(), clearings.size())
		for p: Array in paths:
			assert_eq(p[0], m.entrance)
			assert_has(clearings, p[p.size() - 1])
			for k in range(1, p.size()):
				var d: Vector2i = p[k] - p[k - 1]
				assert_eq(absi(d.x) + absi(d.y), 1, "A* steps are 4-neighbours")


func test_wild_steps_flood_and_moves() -> void:
	for i in SEEDS:
		var m := _stepped(i)
		var w := int(m.w)
		var flood: PackedInt32Array = m.steps["7_validate"].flood
		var e: Vector2i = m.entrance
		assert_eq(flood[e.y * w + e.x], 0, "the flood starts at the entrance")
		for k in flood.size():
			var d := flood[k]
			if d <= 0:
				continue
			var x := k % w
			var y := floori(float(k) / w)
			var ok := false
			for o: Vector2i in N4:
				var nx := x + o.x
				var ny := y + o.y
				if nx >= 0 and ny >= 0 and nx < w and ny < int(m.h) and flood[ny * w + nx] == d - 1:
					ok = true
			assert_true(ok, "flood step %d at %d,%d has a parent" % [d, x, y])
		var pre: Array = m.steps["6_special"].fruit_trees + m.steps["6_special"].pickups
		var post: Array = m.fruit_trees + m.pickups.filter(func(p: Dictionary) -> bool: return not p.get("p1", false))
		assert_eq(pre.size(), post.size(), "validation keeps every item")
		var targets := {}
		for mv in m.steps["7_validate"].moved:
			targets[mv.to] = true
		for k in pre.size():
			assert_eq(String(pre[k].type), String(post[k].type), "same order before and after the flood fill")
			var a := Vector2i(int(pre[k].x), int(pre[k].y))
			var b := Vector2i(int(post[k].x), int(post[k].y))
			if a != b:
				assert_true(targets.has(b), "a moved item ends on a recorded move target")


func _cells(list: Array) -> Dictionary:
	var out := {}
	for d in list:
		out[Vector2i(int(d.x), int(d.y))] = true
	return out
