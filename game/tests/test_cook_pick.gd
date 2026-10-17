extends "res://tests/_runner/test_case.gd"
## JURY-STOVE: what the cook panel picks on its own when a station opens (CookPick): the first recipe that can cook
## now, a variant the book does not have yet first, then the rarer variety; enough stock beats everything.

const CookPick := preload("res://scenes/kitchen/cook_pick.gd")
const SEED := 424242


## A fresh save with a stocked cupboard and an empty inbox and pantry.
func _state() -> Dictionary:
	var s := State.new_game(SEED)
	VarietyGen.ensure_types(s.varieties, SEED)
	s.energy = 80
	s.cupboard = {"jar": 10, "sugar": 10, "salt": 3, "vinegar": 4, "cinnamon": 1}
	s.inbox = []
	s.pantry.items = []
	return s


## Two varieties of `type` (sorted ids), the first common and the second rare.
func _two(s: Dictionary, type: String) -> Array:
	var ids: Array = s.varieties.keys().filter(func(k: String) -> bool: return State.type_of_variety(k) == type)
	ids.sort()
	assert_true(ids.size() >= 2, "two %s varieties in a new game" % type)
	s.varieties[ids[0]]["rarity"] = "common"
	s.varieties[ids[1]]["rarity"] = "rare"
	return ids.slice(0, 2)


func test_opens_on_a_jam_that_is_not_in_the_book() -> void:
	var s := _state()
	var apples := _two(s, "apple")
	s.inbox.append(State.fresh(apples[0], 5, 6))
	s.inbox.append(State.fresh(apples[1], 5, 6))
	s.book.variants[Kitchen.product_key("jam", apples[1], "", "")] = {"best_q": 2, "best_stars": 2, "count": 1, "first_day": 1}
	var p := CookPick.best_recipe(s, Kitchen.recipes_at(s, "stir_pot"))
	assert_eq(p.recipe, "jam")
	assert_eq(p.main, apples[0], "the jam the book lacks beats the rarer known one")
	assert_eq(p.addin, "", "no extra by default")
	assert_true(Kitchen.check(s, p.recipe, p.main, p.second, p.addin).ok, "the first press of Cook works")


func test_among_new_variants_the_rarer_fruit_wins() -> void:
	var s := _state()
	var apples := _two(s, "apple")
	s.inbox.append(State.fresh(apples[0], 9, 6))
	s.inbox.append(State.fresh(apples[1], 3, 6))
	var p := CookPick.best_recipe(s, Kitchen.recipes_at(s, "stir_pot"))
	assert_eq([p.recipe, p.main], ["jam", apples[1]])


func test_enough_stock_beats_rarity() -> void:
	var s := _state()
	var apples := _two(s, "apple")
	s.inbox.append(State.fresh(apples[0], 3, 6))
	s.inbox.append(State.fresh(apples[1], 2, 6))  # rare, but one short of a jam
	var p := CookPick.best_recipe(s, Kitchen.recipes_at(s, "stir_pot"))
	assert_eq(p.main, apples[0])


func test_known_variant_when_nothing_new_can_cook() -> void:
	var s := _state()
	var apple: String = _two(s, "apple")[0]
	s.inbox.append(State.fresh(apple, 3, 6))
	for r in ["jam"]:
		s.book.variants[Kitchen.product_key(r, apple, "", "")] = {"best_q": 2, "best_stars": 2, "count": 1, "first_day": 1}
	var p := CookPick.best_recipe(s, Kitchen.recipes_at(s, "stir_pot"))
	assert_eq([p.recipe, p.main], ["jam", apple], "butter needs 4: the known jam is still the one that cooks")


func test_skips_to_the_recipe_that_can_cook() -> void:
	var s := _state()
	var mush: String = DevTools.first_variety(s, "chanterelle")
	s.inbox.append(State.fresh(mush, 3, 6))
	var p := CookPick.best_recipe(s, Kitchen.recipes_at(s, "pack_jar"))
	assert_eq([p.recipe, p.main], ["brined_mushroom", mush])


func test_tired_still_opens_on_the_new_jam() -> void:
	var s := _state()
	var apple: String = _two(s, "apple")[0]
	s.inbox.append(State.fresh(apple, 3, 6))
	s.energy = 0
	var p := CookPick.best_recipe(s, Kitchen.recipes_at(s, "stir_pot"))
	assert_eq([p.recipe, p.main], ["jam", apple])
	assert_eq(Kitchen.check(s, "jam", apple, "", "").reason, Kitchen.R_TIRED, "the panel then says why")


func test_chutney_fills_both_slots() -> void:
	var s := _state()
	var apple: String = _two(s, "apple")[0]
	var veg: String = DevTools.first_variety(s, "cucumber")
	s.inbox.append(State.fresh(apple, 2, 6))
	s.inbox.append(State.fresh(veg, 2, 6))
	var p := CookPick.best_picks(s, "chutney", "", 1)
	assert_eq([p.main, p.second], [apple, veg])
	assert_true(Kitchen.check(s, "chutney", p.main, p.second, "").ok)


func test_a_pinned_slot_keeps_its_variety() -> void:
	var s := _state()
	var apples := _two(s, "apple")
	s.inbox.append(State.fresh(apples[0], 5, 6))
	s.inbox.append(State.fresh(apples[1], 5, 6))
	assert_eq(CookPick.best_picks(s, "jam", "", 1, {"main": apples[0]}).main, apples[0])


func test_nothing_in_stock_opens_on_the_first_tab_empty() -> void:
	var s := _state()
	var p := CookPick.best_recipe(s, Kitchen.recipes_at(s, "stir_pot"))
	assert_eq([p.recipe, p.main, p.second], ["jam", "", ""])
	assert_eq(CookPick.best_recipe(s, []), {})


func test_big_pot_falls_back_to_one_pot() -> void:
	var s := _state()
	var apple: String = _two(s, "apple")[0]
	Economy.unlock(s, Kitchen.BIG_POT)
	s.inbox.append(State.fresh(apple, 4, 6))  # enough for one jam, not for two
	var p := CookPick.best_recipe(s, Kitchen.recipes_at(s, "stir_pot"), 2)
	assert_eq([p.recipe, p.main, p.mult], ["jam", apple, 1])
