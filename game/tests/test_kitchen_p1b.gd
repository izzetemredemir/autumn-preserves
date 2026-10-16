extends "res://tests/_runner/test_case.gd"
## KITCHEN-P1B: mastery (spec §7.2: 3 cooks with >= 2 quality stars), batch cook (no mini-game, best quality, same
## energy), the big pot (spec §8.3: stove recipes x2, inputs x2 -> 2 jars), press / knead fill tones and the loaf.

const SEED := 515151


## A fresh save with a stocked cupboard, `apples` of one apple variety in the inbox and an empty pantry.
func _state(apples: int = 12) -> Dictionary:
	var s := State.new_game(SEED)
	s.energy = 80
	s.cupboard = {"jar": 10, "sugar": 10, "salt": 3, "vinegar": 4, "cinnamon": 1}
	s.inbox = []
	s.pantry.items = []
	if apples > 0:
		s.inbox.append(State.fresh(_apple(s), apples, 6))
	return s


func _apple(s: Dictionary) -> String:
	return DevTools.first_variety(s, "apple")


func _fresh(s: Dictionary, vid: String) -> int:
	var n := 0
	for item in s.inbox:
		if item.kind == "fresh" and item.variety == vid:
			n += int(item.count)
	return n


func _products(s: Dictionary, key: String) -> Array:
	return s.inbox.filter(func(i: Dictionary) -> bool: return i.kind == "product" and i.key == key)


# --- mastery ----------------------------------------------------------------------------------------------------

func test_mastery_needs_three_cooks_with_two_quality_stars() -> void:
	var s := _state(30)
	var a := _apple(s)
	var key := Kitchen.product_key("jam", a, "", "")
	for q in [1, 3, 1, 2]:  # two good cooks among four
		var r := Kitchen.cook(s, "jam", a, "", "", q)
		assert_true(r.ok, str(r))
		assert_false(r.mastered, "not yet after q=%d" % q)
	assert_false(Kitchen.is_mastered(s, key))
	assert_eq(Kitchen.good_cooks(s.book.variants[key]), 2)
	var third := Kitchen.cook(s, "jam", a, "", "", 2)
	assert_true(third.mastered, "the third good cook masters it")
	assert_true(Kitchen.is_mastered(s, key))
	assert_eq(s.book.variants[key].mastered, true)
	assert_eq(int(s.book.variants[key].count), 5)
	var again := Kitchen.cook(s, "jam", a, "", "", 3)
	assert_true(again.ok)
	assert_false(again.mastered, "mastered only once")
	assert_true(Kitchen.is_mastered(s, key))


func test_old_book_entries_count_their_best_cook() -> void:
	assert_eq(Kitchen.good_cooks({"best_q": 3, "best_stars": 4, "count": 5, "first_day": 1}), 1)
	assert_eq(Kitchen.good_cooks({"best_q": 1, "best_stars": 2, "count": 4, "first_day": 1}), 0)
	assert_false(Kitchen.entry_mastered({"best_q": 3, "count": 9}))
	assert_false(Kitchen.entry_mastered({}))
	var s := _state()
	var a := _apple(s)
	var key := Kitchen.product_key("jam", a, "", "")
	s.book.variants[key] = {"best_q": 2, "best_stars": 2, "count": 6, "first_day": 1}  # a save from before mastery
	assert_false(Kitchen.cook(s, "jam", a, "", "", 3).mastered)
	assert_true(Kitchen.cook(s, "jam", a, "", "", 2).mastered, "1 proven + 2 new good cooks")
	assert_eq(Kitchen.best_quality(s, key), 3)


# --- batch cook ---------------------------------------------------------------------------------------------------

func test_batch_cook_needs_mastery_and_spends_nothing_until_then() -> void:
	var s := _state()
	var a := _apple(s)
	var r := Kitchen.batch_cook(s, "jam", a, "", "")
	assert_false(r.ok)
	assert_eq(r.reason, Kitchen.R_NOT_MASTERED)
	assert_eq(int(s.energy), 80, "no energy spent")
	assert_eq(_fresh(s, a), 12, "no apples used")
	assert_eq(s.inbox.size(), 1)


func test_batch_cook_gives_best_quality_for_the_same_energy() -> void:
	var s := _state(30)
	var a := _apple(s)
	var key := Kitchen.product_key("jam", a, "", "cinnamon")
	s.book.variants[key] = {"best_q": 3, "best_stars": 3, "count": 3, "first_day": 1, "good": 3, "mastered": true}
	var energy := int(s.energy)
	var jars := int(s.stats.jars_made)
	var r := Kitchen.batch_cook(s, "jam", a, "", "cinnamon")
	assert_true(r.ok, str(r))
	assert_eq(int(r.quality), 3, "best quality")
	assert_eq(int(r.item.q), 3)
	assert_eq(r.item.key, key)
	assert_false(r.is_new)
	assert_eq(int(s.energy), energy - Kitchen.energy_cost("stir_pot"), "same energy as a cook")
	assert_eq(_fresh(s, a), 30 - int(Data.recipes().jam.main.count), "same inputs as a cook")
	assert_eq(int(s.cupboard.cinnamon), 0)
	assert_eq(int(s.cupboard.sugar), 9)
	assert_eq(int(s.cupboard.jar), 9)
	assert_eq(_products(s, key).size(), 1)
	assert_eq(int(s.stats.jars_made), jars + 1)
	assert_eq(int(s.book.variants[key].count), 4)
	var tired := _state(30)
	tired.book.variants[Kitchen.product_key("jam", _apple(tired), "", "")] = {"best_q": 2, "good": 3}
	tired.energy = 3
	assert_eq(Kitchen.batch_cook(tired, "jam", _apple(tired), "", "").reason, Kitchen.R_TIRED)


func test_batch_cook_uses_the_best_quality_ever_cooked() -> void:
	var s := _state(30)
	var a := _apple(s)
	for q in [2, 2, 2]:
		Kitchen.cook(s, "jam", a, "", "", q)
	var r := Kitchen.batch_cook(s, "jam", a, "", "")
	assert_true(r.ok)
	assert_eq(int(r.quality), 2)


# --- big pot ------------------------------------------------------------------------------------------------------

func test_big_pot_is_on_sale_and_doubles_only_stove_recipes() -> void:
	var s := _state()
	s.coins = 1000
	assert_eq(Economy.price(s, "big_pot"), 600)
	assert_eq(Kitchen.max_mult(s, "jam"), 1)
	assert_eq(Kitchen.check_n(s, "jam", _apple(s), "", "", 2).reason, Kitchen.R_WRONG, "no x2 without the pot")
	assert_true(Economy.buy(s, "big_pot").ok)
	assert_eq(int(s.coins), 400)
	assert_true(Economy.unlocked(s, "big_pot"))
	assert_eq(Economy.price(s, "big_pot"), -1, "bought once")
	for rid in ["jam", "fruit_butter", "chutney"]:
		assert_eq(Kitchen.max_mult(s, rid), 2, rid)
	for rid in ["pickle", "brined_mushroom"]:
		assert_eq(Kitchen.max_mult(s, rid), 1, rid)
	Economy.unlock(s, "press")
	assert_eq(Kitchen.max_mult(s, "syrup"), 2, "syrup is cooked on the stove")
	assert_eq(Kitchen.max_mult(s, "juice"), 1)
	assert_eq(Kitchen.check_n(s, "jam", _apple(s), "", "", 3).reason, Kitchen.R_WRONG)
	assert_eq(Kitchen.check_n(s, "jam", _apple(s), "", "", 0).reason, Kitchen.R_WRONG)


func test_big_pot_takes_double_inputs_and_makes_two_jars() -> void:
	var s := _state(7)
	Economy.unlock(s, "big_pot")
	var a := _apple(s)
	var need := int(Data.recipes().jam.main.count)
	var c := Kitchen.check_n(s, "jam", a, "", "cinnamon", 2)
	assert_false(c.ok)
	assert_eq(int(c.missing.get("cinnamon", 0)), 1, "one add-in per jar")
	c = Kitchen.check_n(s, "jam", a, "", "", 2)
	assert_true(c.ok, str(c))
	var energy := int(s.energy)
	var r := Kitchen.cook_n(s, "jam", a, "", "", 3, 2)
	assert_true(r.ok, str(r))
	assert_eq(r.items.size(), 2)
	assert_eq(r.item, r.items[0])
	var key := Kitchen.product_key("jam", a, "", "")
	assert_eq(_products(s, key).size(), 2, "two jars in the inbox")
	for item in _products(s, key):
		assert_eq(int(item.q), 3)
	assert_eq(_fresh(s, a), 7 - need * 2, "inputs x2")
	assert_eq(int(s.cupboard.sugar), 8)
	assert_eq(int(s.cupboard.jar), 8)
	assert_eq(int(s.energy), energy - Kitchen.energy_cost("stir_pot"), "one cook's energy")
	assert_eq(int(s.stats.jars_made), 2)
	assert_eq(int(s.book.variants[key].count), 2)
	assert_eq(Kitchen.good_cooks(s.book.variants[key]), 1, "one mastery step per cook")
	s.inbox.append(State.fresh(a, need * 2 - 2, 6))  # one apple short of a second double pot
	var short := Kitchen.check_n(s, "jam", a, "", "", 2)
	assert_eq(int(short.missing.get(a, 0)), 1, "x2 asks for the full double amount")
	assert_true(Kitchen.check(s, "jam", a, "", "").ok, "x1 still fits")


func test_big_pot_chutney_doubles_both_slots() -> void:
	var s := _state(4)
	Economy.unlock(s, "big_pot")
	var veg := DevTools.first_variety(s, "pepper")
	s.inbox.append(State.fresh(veg, 4, 5))
	var r := Kitchen.cook_n(s, "chutney", _apple(s), veg, "", 2, 2)
	assert_true(r.ok, str(r))
	assert_eq(_fresh(s, _apple(s)), 0)
	assert_eq(_fresh(s, veg), 0)
	assert_eq(int(s.cupboard.vinegar), 2)
	assert_eq(r.items.size(), 2)


func test_batch_cook_with_the_big_pot() -> void:
	var s := _state(12)
	Economy.unlock(s, "big_pot")
	var a := _apple(s)
	var key := Kitchen.product_key("jam", a, "", "")
	s.book.variants[key] = {"best_q": 3, "best_stars": 3, "count": 3, "first_day": 1, "good": 3, "mastered": true}
	var energy := int(s.energy)
	var r := Kitchen.batch_cook(s, "jam", a, "", "", 2)
	assert_true(r.ok, str(r))
	assert_eq(_products(s, key).size(), 2)
	assert_eq(int(s.energy), energy - Kitchen.energy_cost("stir_pot"))
	assert_eq(_fresh(s, a), 12 - 2 * int(Data.recipes().jam.main.count))


# --- mini-game colours and the loaf ------------------------------------------------------------------------------

func test_fill_tones_read_three_colours() -> void:
	var t := PressRules.fill_tones(["a22512", "c94d2e", "e19064"], Color.BLACK)
	assert_eq(t, [Color("a22512"), Color("c94d2e"), Color("e19064")] as Array[Color])
	assert_eq(PressRules.fill_tones("c94d2e", Color.BLACK), [Color("c94d2e"), Color("c94d2e"), Color("c94d2e")] as Array[Color])
	assert_eq(PressRules.fill_tones(null, Color.WHITE), [Color.WHITE, Color.WHITE, Color.WHITE] as Array[Color])
	assert_eq(PressRules.fill_tones(["nope"], Color.WHITE)[1], Color.WHITE)
	var s := _state()
	var desc := ProductGen.describe(ProductGen.make_key("juice", [_apple(s)], ""), s.varieties)
	var fill: Array = desc.appearance.fill
	var tones := PressRules.fill_tones(fill, Color.BLACK)
	for i in 3:
		assert_eq(tones[i], Color.html(String(fill[i])), "tone %d from describe()" % i)


func test_loaf_outline_and_shaping() -> void:
	var pts := KneadRules.ellipse_points(Vector2(240, 140), 96.0, 44.0)
	assert_eq(pts.size(), KneadRules.POINTS)
	assert_eq(pts[0], Vector2(240, 96), "starts at the top")
	assert_eq(pts[3], Vector2(336, 140))
	assert_eq(pts[6], Vector2(240, 184))
	assert_eq(KneadRules.loaf_radii(0), KneadRules.LOAF_START)
	assert_eq(KneadRules.loaf_radii(12), KneadRules.LOAF_END)
	assert_eq(KneadRules.loaf_radii(99), KneadRules.LOAF_END)
	var mid := KneadRules.loaf_radii(6)
	assert_true(mid.x > KneadRules.LOAF_START.x and mid.x < KneadRules.LOAF_END.x, "stretches as it is shaped")
	assert_eq(KneadRules.loaf_cuts(0), 0)
	assert_eq(KneadRules.loaf_cuts(3), 0)
	assert_eq(KneadRules.loaf_cuts(4), 1)
	assert_eq(KneadRules.loaf_cuts(12), 3)


func test_loaf_image_stays_on_palette() -> void:
	var tones := PressRules.fill_tones(ProductGen.PLAIN_FILL, Color.BLACK)
	var img: Image = Knead.loaf_image(KneadRules.LOAF_END.x, KneadRules.LOAF_END.y, tones, 3)
	var allowed := {"111010": true, "83571e": true, "c58845": true, "e5bd7f": true, "f2d9c5": true}  # ink, bark ramp, cream
	var bad := 0
	var opaque := 0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a == 0.0:
				continue
			opaque += 1
			if p.a < 1.0 or not allowed.has(p.to_html(false)):
				bad += 1
	assert_eq(bad, 0, "palette colours, no partial alpha")
	assert_true(opaque > 2000, "a loaf-sized shape (%d px)" % opaque)
