extends "res://tests/_runner/test_case.gd"
## P2-CAT: the cat's nap spot, wandering and petting lines (CatRules, pure).

const SEEDS := [1, 2, 7, 42, 314, 4242, 90210, 123456]


func _spot_cells() -> Array:
	var out: Array = []
	for s in CatRules.SPOTS:
		out.append(s.cell)
	return out


func test_spot_is_deterministic() -> void:
	for sd in SEEDS:
		for day in range(1, 30):
			assert_eq(CatRules.spot_for(sd, day).id, CatRules.spot_for(sd, day).id, "seed %d day %d" % [sd, day])


func test_spot_is_one_of_the_list_and_varies() -> void:
	var seen := {}
	for sd in SEEDS:
		for day in range(1, 30):
			var s: Dictionary = CatRules.spot_for(sd, day)
			assert_has(_spot_cells(), s.cell, "spot cell is on the list")
			seen[s.id] = true
	assert_eq(seen.size(), CatRules.SPOTS.size(), "every spot comes up over many days")


func test_spots_are_open_garden_cells() -> void:
	var layout: GDScript = load("res://scenes/garden/garden_layout.gd")
	for s in CatRules.SPOTS:
		var c: Vector2i = s.cell
		assert_true(layout.in_map(c) and not layout.HOUSE.has_point(c), "%s is in the garden" % s.id)


func test_wander_stays_close_and_open() -> void:
	var home := Vector2i(10, 10)
	var open := func(c: Vector2i) -> bool: return c.x != 11
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for _i in 100:
		var c := CatRules.wander_cell(home, r, open)
		assert_true(c == home or (maxi(absi(c.x - home.x), absi(c.y - home.y)) <= CatRules.WANDER_RADIUS and c.x != 11), "wander %s" % c)
	var none := func(_c: Vector2i) -> bool: return false
	assert_eq(CatRules.wander_cell(home, r, none), home, "nowhere to go: stays home")


func test_wander_is_deterministic() -> void:
	var open := func(_c: Vector2i) -> bool: return true
	var a := Seeds.rng(7, "cat_walk", 3)
	var b := Seeds.rng(7, "cat_walk", 3)
	for _i in 10:
		assert_eq(CatRules.wander_cell(Vector2i(9, 8), a, open), CatRules.wander_cell(Vector2i(9, 8), b, open))


func test_near_looks_at_granny() -> void:
	assert_true(CatRules.near(Vector2i(10, 10), Vector2i(13, 12)))
	assert_false(CatRules.near(Vector2i(10, 10), Vector2i(15, 10)))


func test_pet_line_in_range_and_never_repeats() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var last := 0
	for _i in 200:
		var n := CatRules.pet_line(r, last)
		assert_true(n >= 1 and n <= CatRules.PET_LINES, "line %d" % n)
		assert_ne(n, last, "no immediate repeat")
		last = n
