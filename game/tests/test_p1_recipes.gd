extends "res://tests/_runner/test_case.gd"
## P1-RECIPES: press and dough board stations, juice / fruit vinegar / syrup / kraut / pie / bread (spec §6.3),
## the home vinegar chain, pie and bread going stale (§7.5), pantry sizes and zones (§6.5, §7.4).

const SEED := 424242


## A fresh save with P1 varieties (cabbage, grape...) merged in, a stocked cupboard and empty inbox / pantry.
func _state(unlocks: Array = []) -> Dictionary:
	var s := State.new_game(SEED)
	var p1 := VarietyGen.generate_all(SEED, 1)
	for id in p1:
		var type := String(p1[id].type)
		if int(Data.ingredients()[type].get("priority", 0)) > 0:
			s.varieties[id] = p1[id]
	for u in unlocks:
		Economy.unlock(s, u)
	s.energy = 80
	s.cupboard = {"jar": 5, "sugar": 3, "salt": 3, "vinegar": 0, "bottle": 4, "flour": 4}
	s.inbox = []
	s.pantry.items = []
	return s


func _first(s: Dictionary, type: String) -> String:
	return DevTools.first_variety(s, type)


func _cell_in(zone: String, size := Vector2i.ONE) -> Vector2i:
	var b := PantryRules.board(0)
	for y in int(b.rows):
		for x in int(b.cols):
			var ok := true
			for dy in size.y:
				for dx in size.x:
					ok = ok and PantryRules.zone_at(b, Vector2i(x + dx, y + dy)) == zone
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _place(s: Dictionary, item: Dictionary, zone: String) -> void:
	var spot := PantryRules.first_free(PantryRules.board_of(s.pantry), s.pantry.items, item, zone)
	assert_false(spot.is_empty(), "room in %s" % zone)
	if not spot.is_empty():
		assert_true(PantryRules.place(s.pantry, item, spot.cell, int(spot.rot)), "placed in %s" % zone)


func _juice(vid: String) -> Dictionary:
	return State.product(ProductGen.make_key("juice", [vid], ""), 2, 0)


# --- shop gate and stations -------------------------------------------------------------------------------------

func test_p1_rows_are_on_sale_and_the_press_unlocks_the_station() -> void:
	var s := _state()
	s.coins = 1000
	for id in ["bottle", "flour", "seed_cabbage", "press"]:
		assert_true(Economy.price(s, id) > 0, id + " on sale")
	assert_eq(Economy.price(s, "press"), 350)
	assert_false(Kitchen.available(s, "juice"))
	var r := Economy.buy(s, "press")
	assert_true(r.ok)
	assert_eq(int(s.coins), 650)
	assert_true(Economy.unlocked(s, "press"))
	assert_eq(Economy.price(s, "press"), -1, "bought once")
	assert_true(Kitchen.available(s, "juice"))
	assert_eq(Economy.buy(s, "flour", 2).ok, true)
	assert_eq(int(s.cupboard.flour), 6)


func test_station_recipe_lists() -> void:
	var s := _state()
	assert_eq(Kitchen.recipes_at(s, "stir_pot"), ["jam", "fruit_butter", "chutney"])
	assert_eq(Kitchen.recipes_at(s, "pack_jar"), ["pickle", "brined_mushroom", "kraut"])
	assert_eq(Kitchen.recipes_at(s, "press"), [])
	assert_eq(Kitchen.recipes_at(s, "knead"), [])
	Economy.unlock(s, "press")
	assert_eq(Kitchen.recipes_at(s, "stir_pot"), ["jam", "fruit_butter", "chutney", "syrup"])
	assert_eq(Kitchen.recipes_at(s, "press"), ["juice", "fruit_vinegar"])
	Economy.unlock(s, "knead")
	assert_eq(Kitchen.recipes_at(s, "knead"), ["pie", "bread"])


func test_locked_recipes_answer_wrong_and_old_saves_have_no_unlocks() -> void:
	var s := _state()
	var apple := _first(s, "apple")
	s.inbox = [State.fresh(apple, 5, 6)]
	s.erase("unlocks")
	for rid in ["juice", "fruit_vinegar", "pie"]:
		assert_eq(Kitchen.check(s, rid, apple, "", "").reason, Kitchen.R_WRONG, rid)
	assert_eq(Kitchen.check(s, "bread", "", "", "").reason, Kitchen.R_WRONG)
	assert_false(Kitchen.cook(s, "juice", apple, "", "", 3).ok)
	assert_eq(s.inbox.size(), 1, "nothing consumed")


func test_product_key_skips_missing_slots() -> void:
	assert_eq(Kitchen.product_key("bread", "", "", ""), "bread|-")
	assert_eq(Kitchen.product_key("bread", "apple_1", "x", "walnut"), "bread|walnut")
	assert_eq(Kitchen.product_key("jam", "apple_1", "pear_1", ""), "jam|apple_1|-")
	assert_eq(Kitchen.product_key("chutney", "apple_1", "pepper_1", "clove"), "chutney|apple_1|pepper_1|clove")
	assert_eq(Kitchen.product_key("syrup", "apple_1", "", ""), "syrup|apple_1|-")


# --- press: juice and fruit vinegar ------------------------------------------------------------------------------

func test_juice_check_and_cook() -> void:
	var s := _state(["press"])
	var apple := _first(s, "apple")
	s.inbox = [State.fresh(apple, 5, 6)]
	s.cupboard.bottle = 0
	var c := Kitchen.check(s, "juice", apple, "", "")
	assert_eq(c.reason, Kitchen.R_MISSING)
	assert_eq(int(c.missing.bottle), 1)
	s.cupboard.bottle = 1
	assert_true(Kitchen.check(s, "juice", apple, "", "").ok)
	var r := Kitchen.cook(s, "juice", apple, "", "", 2)
	assert_true(r.ok)
	assert_eq(r.item.key, "juice|%s|-" % apple)
	assert_eq(int(r.item.wait_left), 0)
	assert_eq(int(r.item.days_left), -1, "bottles never spoil")
	assert_eq(r.desc.vessel, "bottle")
	assert_eq(int(s.cupboard.bottle), 0)
	assert_eq(int(s.energy), 80 - Kitchen.energy_cost("press"))
	assert_eq(int(s.inbox[0].count), 1, "4 of 5 apples pressed")
	assert_true(r.is_new)
	assert_true(s.book.variants.has(r.item.key))


func test_fruit_vinegar_only_takes_apples_or_grapes() -> void:
	var s := _state(["press"])
	var pear := _first(s, "pear")
	var grape := _first(s, "grape")
	s.inbox = [State.fresh(pear, 4, 4), State.fresh(grape, 4, 3)]
	assert_eq(Kitchen.check(s, "fruit_vinegar", pear, "", "").reason, Kitchen.R_WRONG)
	assert_true(s.varieties.has(grape), "P1 grape varieties merged")
	assert_true(Kitchen.check(s, "fruit_vinegar", grape, "", "").ok)
	s.cupboard.bottle = 1
	assert_eq(int(Kitchen.check(s, "fruit_vinegar", grape, "", "").missing.bottle), 1, "two bottles")


func test_vinegar_chain_apple_press_vinegar_pickles() -> void:
	var s := _state(["press"])
	var apple := _first(s, "apple")
	var cuc := _first(s, "cucumber")
	s.inbox = [State.fresh(apple, 4, 6)]
	var r := Kitchen.cook(s, "fruit_vinegar", apple, "", "", 3)
	assert_true(r.ok)
	assert_eq(int(r.item.wait_left), 5)
	assert_eq(int(s.cupboard.bottle), 2)
	assert_eq(r.desc.zone, "cool")
	assert_true(ProductGen.value(r.item.key, s.varieties, 1) > 0, "worth something on its own")
	# In the inbox the wait never counts; in its zone it does, and when it ends the bottle empties into the cupboard.
	DayEnd.run(s)
	assert_eq(int(s.inbox[0].wait_left), 5, "inbox does not count")
	var bottle: Dictionary = s.inbox.pop_back()
	_place(s, bottle, "cool")
	for night in 4:
		DayEnd.run(s)
		assert_eq(s.pantry.items.size(), 1, "still waiting after night %d" % (night + 1))
		assert_eq(int(s.cupboard.get("vinegar", 0)), 0)
	var events := DayEnd.run(s)
	assert_eq(s.pantry.items.size(), 0, "the vinegar bottle is gone")
	assert_eq(int(s.cupboard.vinegar), 2, "2 home vinegar in the cupboard")
	var seen := false
	for e in events:
		if e.type == "to_cupboard":
			seen = int(e.items.vinegar) == 2 and String(e.key).begins_with("fruit_vinegar|")
	assert_true(seen, "to_cupboard event")
	# Home vinegar works like the grocer's: pickles now cook.
	s.inbox = [State.fresh(cuc, 3, 3)]
	assert_true(Kitchen.check(s, "pickle", cuc, "", "").ok)
	assert_true(Kitchen.cook(s, "pickle", cuc, "", "", 2).ok)
	assert_eq(int(s.cupboard.vinegar), 1)


func test_vinegar_in_the_wrong_zone_keeps_waiting() -> void:
	var s := _state(["press"])
	var item := State.product(ProductGen.make_key("fruit_vinegar", [_first(s, "apple")], ""), 2, 5)
	_place(s, item, "dry")
	for night in 6:
		DayEnd.run(s)
	assert_eq(s.pantry.items.size(), 1)
	assert_eq(int(s.pantry.items[0].item.wait_left), 5)
	assert_eq(int(s.cupboard.get("vinegar", 0)), 0)


# --- stove: syrup from two juices --------------------------------------------------------------------------------

func test_syrup_takes_two_juices_of_one_variety() -> void:
	var s := _state(["press"])
	var a1 := "apple_1"
	var a2 := "apple_2"
	assert_true(s.varieties.has(a1) and s.varieties.has(a2))
	s.inbox = [_juice(a1), _juice(a2), State.fresh(a1, 5, 6)]
	var c := Kitchen.check(s, "syrup", a1, "", "")
	assert_eq(c.reason, Kitchen.R_MISSING, "fresh apples are not juice")
	assert_eq(int(c.missing[a1]), 1)
	assert_eq(Kitchen.product_stock(s, "juice"), {a1: 1, a2: 1})
	_place(s, _juice(a1), "room")
	assert_eq(int(Kitchen.product_stock(s, "juice")[a1]), 2, "pantry juice counts too")
	assert_true(Kitchen.check(s, "syrup", a1, "", "").ok)
	assert_eq(Kitchen.check(s, "syrup", "", "", "").reason, Kitchen.R_WRONG)
	var r := Kitchen.cook(s, "syrup", a1, "", "", 3)
	assert_true(r.ok)
	assert_eq(r.item.key, "syrup|%s|-" % a1)
	assert_eq(r.desc.vessel, "bottle")
	assert_eq(int(s.cupboard.bottle), 3)
	assert_eq(int(s.energy), 80 - Kitchen.energy_cost("stir_pot"))
	assert_eq(s.pantry.items.size(), 0, "pantry juice used")
	assert_eq(Kitchen.product_stock(s, "juice"), {a2: 1}, "the other variety stays")
	assert_eq(int(s.inbox[1].count), 5, "fresh apples untouched")
	var no_press := _state()
	no_press.inbox = [_juice(a1), _juice(a1)]
	assert_eq(Kitchen.check(no_press, "syrup", a1, "", "").reason, Kitchen.R_WRONG, "syrup needs the press")


# --- jar counter: kraut ------------------------------------------------------------------------------------------

func test_kraut_needs_cabbage() -> void:
	var s := _state()
	var cab := _first(s, "cabbage")
	var pep := _first(s, "pepper")
	assert_true(s.varieties.has(cab))
	s.inbox = [State.fresh(cab, 2, 8), State.fresh(pep, 3, 4)]
	assert_eq(Kitchen.check(s, "kraut", pep, "", "").reason, Kitchen.R_WRONG)
	assert_true(Kitchen.check(s, "kraut", cab, "", "").ok)
	var r := Kitchen.cook(s, "kraut", cab, "", "", 2)
	assert_true(r.ok)
	assert_eq(int(r.item.wait_left), 5)
	assert_eq(r.desc.vessel, "pickle_jar")
	assert_eq(r.desc.zone, "cool")
	assert_eq(int(s.cupboard.jar), 4)
	assert_eq(int(s.cupboard.salt), 2)
	assert_eq(int(s.cupboard.vinegar), 0, "no vinegar in kraut")
	assert_eq(PantryRules.zone_for(State.fresh(cab, 1, 8)), "cool")


# --- dough board: pie and bread ----------------------------------------------------------------------------------

func test_pie_check_and_cook() -> void:
	var s := _state(["knead"])
	var pear := _first(s, "pear")
	s.inbox = [State.fresh(pear, 3, 4)]
	s.cupboard.flour = 1
	var c := Kitchen.check(s, "pie", pear, "", "")
	assert_eq(c.reason, Kitchen.R_MISSING)
	assert_eq(int(c.missing.flour), 1)
	s.cupboard.flour = 2
	var r := Kitchen.cook(s, "pie", pear, "", "", 3)
	assert_true(r.ok)
	assert_eq(r.item.key, "pie|%s|-" % pear)
	assert_eq(int(r.item.days_left), 3)
	assert_eq(r.desc.vessel, "pie")
	assert_eq(r.desc.zone, "room")
	assert_eq(int(s.cupboard.flour), 0)
	assert_eq(int(s.cupboard.sugar), 2)
	assert_eq(int(s.cupboard.jar), 5, "no jar for a pie")
	assert_eq(int(s.energy), 80 - Kitchen.energy_cost("knead"))
	assert_eq(s.inbox.size(), 1, "the pears are used up, the pie is in")


func test_bread_has_no_slot_and_takes_an_addin() -> void:
	var s := _state(["knead"])
	assert_true(Kitchen.check(s, "bread", "", "", "").ok)
	s.inbox = [State.nut("walnut", 2)]
	var r := Kitchen.cook(s, "bread", "", "", "walnut", 2)
	assert_true(r.ok)
	assert_eq(r.item.key, "bread|walnut")
	assert_eq(int(r.item.days_left), 3)
	assert_eq(r.desc.zone, "dry")
	assert_eq(r.desc.vessel, "bread")
	assert_eq(int(s.inbox[0].count), 1, "one walnut used")
	assert_eq(int(s.cupboard.flour), 2)
	var plain := Kitchen.cook(s, "bread", "", "", "", 1)
	assert_eq(plain.item.key, "bread|-")
	assert_eq(int(s.cupboard.flour), 0)
	assert_eq(Kitchen.check(s, "bread", "", "", "").reason, Kitchen.R_MISSING)


func test_pie_and_bread_go_stale_after_three_days() -> void:
	var s := _state(["knead"])
	var pie := State.product(ProductGen.make_key("pie", [_first(s, "apple")], ""), 2, 0, 3)
	var bread := State.product("bread|-", 1, 0, 3)
	var jam := State.product(ProductGen.make_key("jam", [_first(s, "apple")], ""), 2, 0)
	_place(s, pie, "room")
	_place(s, jam, "room")
	s.inbox = [bread]
	var compost0 := int(s.garden.compost)
	for night in 2:
		DayEnd.run(s)
		assert_eq(s.pantry.items.size(), 2, "pie still fine after night %d" % (night + 1))
		assert_eq(s.inbox.size(), 1, "bread still fine after night %d" % (night + 1))
	assert_eq(int(pie.days_left), 1)
	var events := DayEnd.run(s)
	assert_eq(s.pantry.items.size(), 1, "pie gone on the third night")
	assert_eq(s.pantry.items[0].item.key, jam.key, "jars never spoil")
	assert_eq(s.inbox.size(), 0, "bread gone on the third night")
	var spoiled := 0
	for e in events:
		if e.type == "spoiled" and e.item.kind == "product":
			spoiled += 1
	assert_eq(spoiled, 2)
	assert_eq(int(s.garden.compost) + int(s.garden.fertilizer) * int(Data.rules().garden.compost_per_fertilizer), compost0 + 2, "stale bakes go to the compost")


# --- pantry sizes, zones and names -------------------------------------------------------------------------------

func test_pantry_sizes_and_zones_of_p1_products() -> void:
	var s := _state(["press", "knead"])
	var a := _first(s, "apple")
	var cab := _first(s, "cabbage")
	var cases := {
		"juice": [[a], Vector2i(1, 2), false, "room"],
		"fruit_vinegar": [[a], Vector2i(1, 2), false, "cool"],
		"syrup": [[a], Vector2i(1, 2), false, "room"],
		"kraut": [[cab], Vector2i(1, 1), false, "cool"],
		"pie": [[a], Vector2i(2, 1), true, "room"],
		"bread": [[], Vector2i(2, 1), true, "dry"],
	}
	for rid in cases:
		var c: Array = cases[rid]
		var item := State.product(ProductGen.make_key(rid, c[0], ""), 2, 0)
		assert_eq(PantryRules.item_size(item), c[1], rid + " size")
		assert_eq(PantryRules.can_rotate(item), c[2], rid + " rotates")
		var turned: Vector2i = c[1] if not c[2] else Vector2i(c[1].y, c[1].x)
		assert_eq(PantryRules.item_size(item, 1), turned, rid + " turned")
		assert_eq(PantryRules.zone_for(item), c[3], rid + " zone")
		assert_eq(ProductGen.describe(item.key, s.varieties).size, c[1], rid + " describe size")
	var p := {"rows_extra": 0, "items": []}
	var bread := State.product("bread|-", 1, 0, 3)
	var dry := _cell_in("dry")
	assert_true(PantryRules.place(p, bread, dry, 1), "bread turned upright spans both dry rows")
	assert_true(PantryRules.in_correct_zone(PantryRules.board(0), p.items[0]))


func test_p1_product_names_are_procedural_and_short() -> void:
	var s := _state()
	var max_len := int(Data.grammar().product_name_max)
	var keys := []
	for vid in s.varieties:
		var type := String(s.varieties[vid].type)
		if type in ["apple", "grape"]:
			keys.append(ProductGen.make_key("fruit_vinegar", [vid], ""))
		if Data.ingredients()[type].group == "fruit":
			for rid in ["juice", "syrup", "pie"]:
				keys.append(ProductGen.make_key(rid, [vid], ""))
		if type == "cabbage":
			keys.append(ProductGen.make_key("kraut", [vid], "ginger"))
	keys.append("bread|-")
	keys.append("bread|walnut")
	var names := {}
	for k in keys:
		var n := ProductGen.product_name(k, s.varieties)
		var short := String(Data.recipes()[ProductGen.parse_key(k).recipe].short)
		assert_true(n.length() > short.length() and n.length() <= max_len, "%s -> '%s'" % [k, n])
		assert_true(n.ends_with(short), "%s ends with %s" % [n, short])
		assert_eq(n, ProductGen.product_name(k, s.varieties), "deterministic")
		names[n] = true
	assert_true(names.size() > keys.size() / 2.0, "names vary with the variety")
