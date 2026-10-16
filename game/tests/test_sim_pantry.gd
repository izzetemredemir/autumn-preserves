extends "res://tests/_runner/test_case.gd"
## SIM-03: pantry board, sizes, zones, placement, stars, auto-arrange, night helpers.
## Base board: dry rows 0-1, room rows 2-3, cool rows 4-5 (6 cols), floor rows 6-7 (cols 0-3).


func _jam(variety := "apple_1") -> Dictionary:
	return State.product(ProductGen.make_key("jam", [variety], ""), 1, 0)


func _pickle() -> Dictionary:
	return State.product(ProductGen.make_key("pickle", ["cucumber_1"], ""), 1, 3)


func _juice() -> Dictionary:
	return State.product(ProductGen.make_key("juice", ["apple_1"], ""), 1, 0)


func _pie() -> Dictionary:
	return State.product(ProductGen.make_key("pie", ["apple_1"], ""), 1, 0, 3)


func _bread() -> Dictionary:
	return State.product(ProductGen.make_key("bread", [], ""), 1, 0, 3)


func _walnut() -> Dictionary:
	return State.nut("walnut", 5)


func _e(item: Dictionary, x: int, y: int, rot := 0) -> Dictionary:
	return {"item": item, "x": x, "y": y, "rot": rot}


func _pantry(items: Array, rows_extra := 0) -> Dictionary:
	return {"rows_extra": rows_extra, "items": items}


func _rules(items: Array) -> Array:
	return PantryRules.stars(_pantry(items)).rules


func test_board_cells() -> void:
	var b := PantryRules.board()
	assert_eq(PantryRules.cell_count(b), 44)
	assert_eq(int(b.cols), 6)
	assert_eq(int(b.rows), 8)
	assert_eq(PantryRules.zone_at(b, Vector2i(0, 0)), "dry")
	assert_eq(PantryRules.zone_at(b, Vector2i(5, 1)), "dry")
	assert_eq(PantryRules.zone_at(b, Vector2i(0, 2)), "room")
	assert_eq(PantryRules.zone_at(b, Vector2i(5, 5)), "cool")
	assert_eq(PantryRules.zone_at(b, Vector2i(0, 6)), "floor")
	assert_eq(PantryRules.zone_at(b, Vector2i(3, 7)), "floor")
	assert_eq(PantryRules.zone_at(b, Vector2i(4, 6)), "", "floor is 4 wide")
	assert_eq(PantryRules.zone_at(b, Vector2i(0, 8)), "")
	assert_eq(PantryRules.zone_at(b, Vector2i(-1, 0)), "")
	for n in 4:
		assert_eq(PantryRules.cell_count(PantryRules.board(n)), 44 + 12 * n, "%d extra shelves" % n)
	var b3 := PantryRules.board(3)
	assert_eq(PantryRules.zone_at(b3, Vector2i(0, 6)), "room", "1st extra shelf")
	assert_eq(PantryRules.zone_at(b3, Vector2i(0, 8)), "cool", "2nd extra shelf")
	assert_eq(PantryRules.zone_at(b3, Vector2i(0, 10)), "dry", "3rd extra shelf")
	assert_eq(PantryRules.zone_at(b3, Vector2i(0, 12)), "floor")
	assert_eq(b3.shelves.size(), 6)


func test_item_sizes() -> void:
	assert_eq(PantryRules.item_size(_jam()), Vector2i(1, 1))
	assert_eq(PantryRules.item_size(_pickle()), Vector2i(1, 1))
	assert_eq(PantryRules.item_size(_juice()), Vector2i(1, 2))
	assert_eq(PantryRules.item_size(_juice(), 1), Vector2i(1, 2), "bottles stay upright")
	assert_eq(PantryRules.item_size(_pie()), Vector2i(2, 1))
	assert_eq(PantryRules.item_size(_pie(), 1), Vector2i(1, 2))
	assert_eq(PantryRules.item_size(_bread()), Vector2i(2, 1))
	assert_eq(PantryRules.item_size(State.fresh("apple_1", 3, 5)), Vector2i(1, 1))
	assert_eq(PantryRules.item_size(_walnut()), Vector2i(1, 1))
	assert_eq(PantryRules.item_size(State.fresh("pumpkin_1", 1, 12)), Vector2i(2, 2))
	assert_true(PantryRules.can_rotate(_bread()))
	assert_false(PantryRules.can_rotate(_juice()))


func test_zone_for() -> void:
	assert_eq(PantryRules.zone_for(_jam()), "room")
	assert_eq(PantryRules.zone_for(_juice()), "room")
	assert_eq(PantryRules.zone_for(_pickle()), "cool")
	assert_eq(PantryRules.zone_for(State.product("brined_mushroom|porcini_1|-", 1, 2)), "cool")
	assert_eq(PantryRules.zone_for(_bread()), "dry")
	assert_eq(PantryRules.zone_for(State.fresh("apple_1", 3, 5)), "cool")
	assert_eq(PantryRules.zone_for(State.fresh("cucumber_2", 3, 3)), "cool")
	assert_eq(PantryRules.zone_for(State.fresh("chanterelle_1", 2, 2)), "cool")
	assert_eq(PantryRules.zone_for(_walnut()), "dry")
	assert_eq(PantryRules.zone_for(State.fresh("pumpkin_1", 1, 12)), "floor")


func test_bottle_needs_two_free_vertical_cells() -> void:
	var b := PantryRules.board()
	var juice := _juice()
	assert_true(PantryRules.can_place(b, [], juice, Vector2i(0, 2), 0))
	assert_false(PantryRules.can_place(b, [], juice, Vector2i(0, 7), 0), "bottom row: no cell below")
	assert_false(PantryRules.can_place(b, [], juice, Vector2i(4, 6), 0), "not a cell")
	var below := [_e(_jam(), 0, 3)]
	assert_false(PantryRules.can_place(b, below, juice, Vector2i(0, 2), 0), "lower cell taken")
	assert_true(PantryRules.can_place(b, below, juice, Vector2i(1, 2), 0))
	var above := [_e(_jam(), 0, 2)]
	assert_false(PantryRules.can_place(b, above, juice, Vector2i(0, 2), 0), "upper cell taken")
	assert_false(PantryRules.can_place(b, above, juice, Vector2i(0, 1), 0), "lower cell taken")


func test_can_place_overlap_and_bounds() -> void:
	var b := PantryRules.board()
	var entries := [_e(_pie(), 0, 2)]
	assert_false(PantryRules.can_place(b, entries, _jam(), Vector2i(1, 2), 0), "pie covers (1,2)")
	assert_true(PantryRules.can_place(b, entries, _jam(), Vector2i(2, 2), 0))
	assert_true(PantryRules.can_place(b, entries, _jam(), Vector2i(1, 2), 0, 0), "ignore the dragged entry")
	assert_false(PantryRules.can_place(b, [], _pie(), Vector2i(5, 2), 0), "sticks out right")
	assert_true(PantryRules.can_place(b, [], _pie(), Vector2i(5, 2), 1), "turned fits")
	assert_false(PantryRules.can_place(b, [], _jam(), Vector2i(-1, 0), 0))
	assert_false(PantryRules.can_place(b, [], _jam(), Vector2i(6, 0), 0))
	assert_false(PantryRules.can_place(b, [], _jam(), Vector2i(0, 8), 0))


func test_place_move_and_correct_zone() -> void:
	var p := _pantry([])
	var b := PantryRules.board()
	assert_true(PantryRules.place(p, _jam(), Vector2i(0, 2), 0))
	assert_false(PantryRules.place(p, _jam(), Vector2i(0, 2), 0), "occupied")
	assert_eq(p.items.size(), 1)
	assert_true(PantryRules.in_correct_zone(b, p.items[0]))
	assert_true(PantryRules.place(p, _jam(), Vector2i(0, 0), 0))
	assert_false(PantryRules.in_correct_zone(b, p.items[1]), "jam on the dry shelf")
	assert_true(PantryRules.place(p, _juice(), Vector2i(5, 3), 1))
	assert_eq(int(p.items[2].rot), 0, "bottle rot normalised")
	assert_false(PantryRules.in_correct_zone(b, p.items[2]), "bottle across room and cool")
	assert_true(PantryRules.place(p, State.fresh("pumpkin_1", 1, 12), Vector2i(0, 6), 0))
	assert_true(PantryRules.in_correct_zone(b, p.items[3]))
	assert_false(PantryRules.in_correct_zone(b, _jam()), "bare inbox item")
	assert_true(PantryRules.move(p, 1, Vector2i(1, 2), 0))
	assert_true(PantryRules.in_correct_zone(b, p.items[1]))
	assert_false(PantryRules.move(p, 1, Vector2i(0, 2), 0), "onto another jar")
	assert_eq(int(p.items[1].x), 1, "unchanged after a failed move")


func _assert_no_overlap(p: Dictionary) -> void:
	var b := PantryRules.board_of(p)
	var seen := {}
	for e in p.items:
		for c in PantryRules.entry_cells(e):
			assert_ne(PantryRules.zone_at(b, c), "", "on the board %s" % c)
			assert_false(seen.has(c), "overlap at %s" % c)
			seen[c] = true


func test_auto_arrange_never_overlaps_and_jam_goes_to_room() -> void:
	var p := _pantry([_e(_pickle(), 0, 4)])
	var incoming := [_jam("apple_1"), _jam("pear_1"), _juice(), _pie(), _bread(), State.fresh("apple_1", 3, 5),
		_walnut(), _pickle(), State.fresh("pumpkin_1", 1, 12), _jam("quince_2")]
	var left := PantryRules.auto_arrange(p, incoming)
	assert_eq(left.size(), 0)
	assert_eq(p.items.size(), 11)
	_assert_no_overlap(p)
	var b := PantryRules.board()
	for e in p.items:
		assert_true(PantryRules.in_correct_zone(b, e), "own zone: %s" % State.item_type(e.item))
		if State.item_type(e.item) == "jam":
			assert_eq(PantryRules.zone_at(b, Vector2i(int(e.x), int(e.y))), "room")
	assert_eq(Vector2i(int(p.items[1].x), int(p.items[1].y)), Vector2i(0, 2), "first jam: first room cell")
	assert_eq(Vector2i(int(p.items[6].x), int(p.items[6].y)), Vector2i(1, 4), "apples skip the taken cool cell")


func test_auto_arrange_overflow_and_turn() -> void:
	var p := _pantry([])
	var jams: Array = []
	for i in 12:
		jams.append(_jam())
	assert_eq(PantryRules.auto_arrange(p, jams).size(), 0)
	var extra := [_jam()]
	assert_eq(PantryRules.auto_arrange(p, extra).size(), 0)
	assert_eq(Vector2i(int(p.items[12].x), int(p.items[12].y)), Vector2i(0, 6), "room full -> floor")
	jams.clear()
	for i in 8:
		jams.append(_jam())
	var left := PantryRules.auto_arrange(p, jams)
	assert_eq(left.size(), 1, "floor holds 8, then leftovers")
	assert_eq(p.items.size(), 20)
	_assert_no_overlap(p)
	var b := PantryRules.board()
	for e in p.items:
		assert_true(PantryRules.zone_at(b, Vector2i(int(e.x), int(e.y))) in ["room", "floor"], "never another shelf")
	# Only a vertical 1x2 gap left on the room shelf: the pie turns into it.
	var q := _pantry([])
	for y in [2, 3]:
		for x in 5:
			q.items.append(_e(_jam(), x, y))
	assert_eq(PantryRules.auto_arrange(q, [_pie()]).size(), 0)
	assert_eq(q.items[10].x, 5)
	assert_eq(q.items[10].y, 2)
	assert_eq(int(q.items[10].rot), 1)


func test_star_correct_zone() -> void:
	assert_eq(PantryRules.stars(_pantry([])), {"stars": 0, "rules": [false, false, false]}, "empty pantry")
	var on := [_e(_jam(), 0, 2), _e(_jam(), 1, 2), _e(_jam(), 2, 2), _e(_jam(), 3, 2), _e(_jam(), 0, 0)]
	assert_eq(_rules(on), [true, false, false], "4 of 5 = 80%")
	assert_eq(int(PantryRules.stars(_pantry(on)).stars), 1)
	var off := [_e(_jam(), 0, 2), _e(_jam(), 1, 2), _e(_jam(), 2, 2), _e(_jam(), 0, 0), _e(_jam(), 2, 0)]
	assert_false(_rules(off)[0], "3 of 5")


func test_star_groups() -> void:
	var wrong_but_grouped := [_e(_jam("apple_1"), 0, 0), _e(_jam("pear_1"), 1, 0), _e(_jam("quince_2"), 2, 0)]
	assert_eq(_rules(wrong_but_grouped), [false, true, false], "same recipe = one kind")
	var l_shape := [_e(_jam(), 0, 2), _e(_jam(), 0, 3), _e(_jam(), 1, 3), _e(_pickle(), 0, 5)]
	assert_true(_rules(l_shape)[1])
	var bottles := [_e(_juice(), 0, 2), _e(_juice(), 1, 3), _e(_juice(), 2, 4)]
	assert_true(_rules(bottles)[1], "multi-cell items touch through any cell")
	var split := [_e(_jam(), 0, 2), _e(_jam(), 1, 2), _e(_jam(), 2, 2), _e(_jam(), 5, 2)]
	assert_false(_rules(split)[1], "jam in two groups")
	var small := [_e(_jam(), 0, 2), _e(_jam(), 1, 2), _e(_pickle(), 0, 4), _e(_pickle(), 1, 4)]
	assert_eq(_rules(small), [true, false, false], "no group of 3")


func test_star_full_shelf() -> void:
	var full: Array = []
	for y in [0, 1]:
		for x in 6:
			full.append(_e(_jam() if (x + y) % 2 == 0 else _pickle(), x, y))
	assert_eq(_rules(full), [false, false, true], "full dry shelf of misplaced, scattered jars")
	var breads: Array = []
	for y in [0, 1]:
		for x in [0, 2, 4]:
			breads.append(_e(_bread(), x, y))
	assert_true(_rules(breads)[2], "6 breads fill a shelf")
	var nuts: Array = []
	for y in [0, 1]:
		for x in 6:
			nuts.append(_e(_walnut(), x, y))
	nuts.pop_back()
	assert_false(_rules(nuts)[2], "11 of 12 cells")
	var on_floor: Array = []
	for y in [6, 7]:
		for x in 4:
			on_floor.append(_e(_jam(), x, y))
	assert_false(_rules(on_floor)[2], "the floor is not a shelf")


func test_star_colour_order_with_hand_made_luminance() -> void:
	var b := PantryRules.board()
	var row: Array = []
	for x in 5:
		row.append(_e(_jam(), x, 3))
	var four := row.slice(0, 4)
	assert_true(PantryRules.colour_sorted(b, four, {0: 0.9, 1: 0.7, 2: 0.5, 3: 0.2}))
	assert_true(PantryRules.colour_sorted(b, four, {0: 0.9, 1: 0.7, 2: 0.7, 3: 0.2}), "ties allowed")
	assert_false(PantryRules.colour_sorted(b, four, {0: 0.2, 1: 0.5, 2: 0.7, 3: 0.9}), "dark to light")
	assert_false(PantryRules.colour_sorted(b, four, {0: 0.9, 1: 0.7, 2: 0.8, 3: 0.2}))
	assert_false(PantryRules.colour_sorted(b, four, {0: 0.5, 1: 0.5, 2: 0.5, 3: 0.5}), "all equal")
	assert_false(PantryRules.colour_sorted(b, four, {0: 0.9, 1: 0.7, 2: 0.5}), "3 jars")
	assert_false(PantryRules.colour_sorted(b, four, {}))
	assert_true(PantryRules.colour_sorted(b, row, {0: 0.1, 1: 0.9, 2: 0.7, 3: 0.5, 4: 0.2}), "run starts later")
	var gap := [_e(_jam(), 0, 2), _e(_jam(), 1, 2), _e(_jam(), 3, 2), _e(_jam(), 4, 2)]
	assert_false(PantryRules.colour_sorted(b, gap, {0: 0.9, 1: 0.7, 2: 0.5, 3: 0.2}), "side by side only")
	var floor_row := [_e(_jam(), 0, 6), _e(_jam(), 1, 6), _e(_jam(), 2, 6), _e(_jam(), 3, 6)]
	assert_false(PantryRules.colour_sorted(b, floor_row, {0: 0.9, 1: 0.7, 2: 0.5, 3: 0.2}), "floor is no shelf")
	assert_eq(PantryRules.jar_luminances(four, {}), {}, "no varieties -> colour branch skipped")


func test_fill_luminance() -> void:
	var light := {"appearance": {"fill": ["f2d9c5", "e19064", "c94d2e"]}}
	var dark := {"appearance": {"fill": ["3d1f29", "62272c", "a22512"]}}
	assert_true(PantryRules.fill_luminance(light) > PantryRules.fill_luminance(dark))
	assert_near(PantryRules.fill_luminance({"appearance": {"fill": ["ffffff"]}}), 1.0, 0.001)
	assert_eq(PantryRules.fill_luminance({}), -1.0)


## Uses the real ProductGen.describe once SIM-01 lands; while it is a stub the colour branch is skipped.
func test_star_colour_order_with_describe() -> void:
	var s := State.new_game(5)
	var keys: Array = []
	for i in 4:
		keys.append(ProductGen.make_key("jam", ["apple_%d" % (i + 1)], ""))
	var lum := {}
	for k in keys:
		lum[k] = PantryRules.fill_luminance(ProductGen.describe(k, s.varieties))
	var items: Array = []
	for x in 4:
		items.append(_e(State.product(keys[x], 1, 0), x, 2))
	if lum.values().min() < 0.0:
		assert_false(PantryRules.stars(_pantry(items), s.varieties).rules[2], "stub describe: no colour star")
		return
	keys.sort_custom(func(a, b): return lum[a] > lum[b])
	for x in 4:
		items[x].item = State.product(keys[x], 1, 0)
	var expected: bool = lum[keys[0]] > lum[keys[3]]
	assert_eq(PantryRules.state_stars({"pantry": _pantry(items), "varieties": s.varieties}).rules[2], expected)


func test_fresh_decay_skips() -> void:
	var b := PantryRules.board()
	var apple := _e(State.fresh("apple_1", 3, 5), 0, 4)
	assert_false(PantryRules.fresh_decay_skips(apple, 0, b))
	assert_false(PantryRules.fresh_decay_skips(apple, 1, b))
	assert_false(PantryRules.fresh_decay_skips(apple, 2, b))
	assert_true(PantryRules.fresh_decay_skips(apple, 3, b), "every 3rd night in the right zone")
	assert_false(PantryRules.fresh_decay_skips(apple, 4, b))
	assert_true(PantryRules.fresh_decay_skips(apple, 6, b))
	var wrong := _e(State.fresh("apple_1", 3, 5), 0, 2)
	assert_false(PantryRules.fresh_decay_skips(wrong, 3, b), "room shelf is wrong for fruit")
	assert_true(PantryRules.fresh_decay_skips(wrong, 3), "no board: caller checked the zone")
	assert_false(PantryRules.fresh_decay_skips(State.fresh("apple_1", 3, 5), 3, b), "inbox item")
	assert_false(PantryRules.fresh_decay_skips(_e(_pickle(), 0, 4), 3, b), "products do not decay here")


func test_wait_counts() -> void:
	var b := PantryRules.board()
	assert_true(PantryRules.wait_counts(b, _e(_pickle(), 0, 4)))
	assert_false(PantryRules.wait_counts(b, _e(_pickle(), 0, 2)), "wrong zone")
	assert_false(PantryRules.wait_counts(b, _pickle()), "inbox")
	assert_false(PantryRules.wait_counts(b, _e(State.fresh("apple_1", 3, 5), 0, 4)), "not a product")


func test_add_shelf_keeps_floor_items_on_floor() -> void:
	var p := _pantry([_e(_jam(), 0, 2), _e(State.fresh("pumpkin_1", 1, 12), 0, 6)])
	PantryRules.add_shelf(p)
	assert_eq(int(p.rows_extra), 1)
	assert_eq(int(p.items[0].y), 2)
	assert_eq(int(p.items[1].y), 8)
	var b := PantryRules.board_of(p)
	assert_eq(PantryRules.cell_count(b), 56)
	assert_eq(PantryRules.zone_at(b, Vector2i(0, 6)), "room")
	assert_true(PantryRules.in_correct_zone(b, p.items[1]))
	assert_true(PantryRules.state_stars({"pantry": p, "varieties": {}}).rules[0])
