extends "res://tests/_runner/test_case.gd"
## SIM-04: the night pipeline (spec §9) and the order guarantee over the first ten days.

const Fx := preload("res://tests/test_sim_economy.gd")
const SEEDS := [1, 7, 42, 4242, 90210, 123456, 2026, 31337]


func _entry(item: Dictionary, x: int, y: int) -> Dictionary:
	return {"item": item, "x": x, "y": y, "rot": 0}


func _cell_in(zone: String) -> Vector2i:
	var b := PantryRules.board(0)
	for y in int(b.rows):
		for x in int(b.cols):
			if PantryRules.zone_at(b, Vector2i(x, y)) == zone:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_weather_is_deterministic_per_seed_and_day() -> void:
	for sd in SEEDS:
		for d in range(1, 31):
			var w := DayEnd.weather_for(sd, d)
			assert_eq(w, DayEnd.weather_for(sd, d), "seed %d day %d" % [sd, d])
			assert_has(["sunny", "rainy"], w)
	var a := State.new_game(55)
	var b := State.new_game(55)
	for i in 8:
		DayEnd.run(a)
		DayEnd.run(b)
		assert_eq(a.weather, b.weather, "night %d" % i)
		assert_eq(a.weather, DayEnd.weather_for(55, int(a.day)), "weather of the new day")
	var rainy := 0
	for d in range(1, 2001):
		if DayEnd.weather_for(9, d) == "rainy":
			rainy += 1
	assert_true(rainy > 440 and rainy < 560, "P0 rain about 25%%, got %d / 2000" % rainy)
	for d in range(1, 200):
		assert_ne(DayEnd.weather_for(3, d, "foggy", "p1"), "foggy", "no two foggy days")


func test_fresh_in_cool_zone_skips_every_third_night() -> void:
	var s := State.new_game(4242)
	var cool := _cell_in("cool")
	assert_eq(PantryRules.zone_for(State.fresh("apple_1", 2, 10)), "cool")
	s.pantry.items = [_entry(State.fresh("apple_1", 2, 10), cool.x, cool.y)]
	s.inbox = [State.fresh("apple_1", 2, 10)]
	var dry := _cell_in("dry")
	s.pantry.items.append(_entry(State.fresh("pear_1", 1, 10), dry.x, dry.y))
	var left: Array = []
	for i in 6:
		DayEnd.run(s)
		left.append(int(s.pantry.items[0].item.days_left))
	assert_eq(left, [9, 8, 8, 7, 6, 6], "cool zone: nights 3 and 6 skip")
	assert_eq(int(s.pantry.items[0].item.nights), 6)
	assert_eq(int(s.inbox[0].days_left), 4, "inbox decays every night")
	assert_eq(int(s.pantry.items[1].item.days_left), 4, "wrong zone decays every night")


func test_waiting_jars_in_wrong_zone_do_not_count_down() -> void:
	var s := State.new_game(4242)
	var key := "pickle|cucumber_1|-"
	assert_eq(PantryRules.zone_for(State.product(key, 2, 3)), "cool")
	var room := _cell_in("room")
	var cool := _cell_in("cool")
	s.pantry.items = [_entry(State.product(key, 2, 3), room.x, room.y), _entry(State.product(key, 2, 3), cool.x, cool.y)]
	s.inbox = [State.product(key, 2, 3)]
	DayEnd.run(s)
	assert_eq(int(s.pantry.items[0].item.wait_left), 3, "room shelf is the wrong zone for pickles")
	assert_eq(int(s.pantry.items[1].item.wait_left), 2, "cool shelf counts")
	assert_eq(int(s.inbox[0].wait_left), 3, "inbox never counts")
	var events := DayEnd.run(s)
	events.append_array(DayEnd.run(s))
	assert_eq(int(s.pantry.items[1].item.wait_left), 0)
	assert_eq(int(s.pantry.items[0].item.wait_left), 3)
	var matured := 0
	for e in events:
		if e.type == "matured":
			matured += 1
	assert_eq(matured, 1)
	var t := {"pantry": {"items": [_entry(State.product(key, 1, 2), 0, 0)]}}
	DayEnd.tick_waiting(t, func(_e: Dictionary) -> bool: return false)
	assert_eq(int(t.pantry.items[0].item.wait_left), 2, "injected wrong zone")
	DayEnd.tick_waiting(t, func(_e: Dictionary) -> bool: return true)
	assert_eq(int(t.pantry.items[0].item.wait_left), 1)


func test_spoiled_items_make_compost_and_fertilizer() -> void:
	var s := State.new_game(4242)
	s.inbox = [State.fresh("blackberry_1", 4, 1), State.nut("walnut", 6), State.product("jam|apple_1|-", 2, 0)]
	s.bag = [State.fresh("porcini_1", 1, 1)]
	s.garden.compost = 1
	var events := DayEnd.run(s)
	assert_eq(s.inbox.size(), 2, "nuts and jars never spoil")
	assert_eq(s.bag.size(), 0)
	assert_eq(int(s.garden.fertilizer), 1, "5 stale items = 1 fertilizer")
	assert_eq(int(s.garden.compost), 1)
	var kinds: Array = []
	for e in events:
		kinds.append(e.type)
	assert_has(kinds, "spoiled")
	assert_has(kinds, "fertilizer")


func test_energy_from_pantry_stars() -> void:
	var s := State.new_game(4242)
	s.energy = 3
	DayEnd.run_with(s, {"stars": func(_st: Dictionary) -> int: return 3})
	assert_eq(int(s.energy), 95)
	assert_eq(int(s.energy_max), 95)
	var stars := int(PantryRules.state_stars(s).stars)
	DayEnd.run(s)
	assert_eq(int(s.energy), 80 + 5 * stars)


func test_night_garden_day_and_wild() -> void:
	var s := State.new_game(4242)
	s.wild_today = {"forest": {"collected": [1, 2], "shaken": [0]}}
	Garden.shake_tree(s, 1)
	var events := DayEnd.run(s)
	assert_eq(int(s.day), 2)
	assert_eq(s.wild_today, {})
	assert_eq(int(s.garden.beds[0].days_left), 0, "start cucumbers are ready on day 2")
	var grown := 0
	for e in events:
		if e.type == "grown":
			grown += 1
	assert_eq(grown, 2)
	DayEnd.run(s)
	assert_false(bool(s.garden.trees[1].fruit))
	DayEnd.run(s)
	assert_true(bool(s.garden.trees[1].fruit), "shaken on day 1, fruit again on day 4")


func test_orders_expire_and_refill_overnight() -> void:
	var s := State.new_game(4242)
	for i in 5:
		DayEnd.run(s)
	assert_eq(int(s.day), 6)
	assert_eq(s.orders.size(), 3)
	for o in s.orders:
		assert_true(int(o.expires_day) > 6)
		assert_ne(int(o.id), 0, "the day-1 order expired")


## Acceptance: >= 1 satisfiable order every day 1-10, idle player and a player who delivers one order a day.
func test_new_game_has_satisfiable_order_days_1_to_10() -> void:
	var fake := Fx.fake_taste_fn()
	for deliver in [false, true]:
		for sd in SEEDS:
			var s := Fx.make_state(sd)
			var cands := Orders.candidates(s, fake)
			for d in range(1, 11):
				assert_eq(int(s.day), d)
				assert_eq(s.orders.size(), 3, "board full, seed %d day %d" % [sd, d])
				var idx := _first_ok(s.orders, cands)
				assert_true(idx >= 0, "injected taste: seed %d day %d deliver %s" % [sd, d, deliver])
				if deliver and idx >= 0:
					s.orders.remove_at(idx)
				DayEnd.run_with(s, {"taste": fake})


func test_satisfiable_with_real_products() -> void:
	for sd in SEEDS:
		var s := State.new_game(sd)
		var cands := Orders.candidates(s, Orders.product_taste())
		for d in range(1, 11):
			var idx := _first_ok(s.orders, cands)
			assert_true(idx >= 0, "ProductGen taste: seed %d day %d" % [sd, d])
			if idx >= 0 and d % 2 == 0:
				s.orders.remove_at(idx)
			DayEnd.run(s)


func _first_ok(orders: Array, cands: Array) -> int:
	for i in orders.size():
		if Orders.satisfiable_in(orders[i], cands):
			return i
	return -1
