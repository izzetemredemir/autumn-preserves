extends "res://tests/_runner/test_case.gd"
## KITCHEN-P1C: the six family recipes (spec §7.6): recipes.json rows on top of a base recipe, unlocked by a
## grandchild's love (3, 6, 10), one fixed ingredient type and add-in, "Granny's" names within 28 characters, a gold
## label and a value bonus.

const SEEDS := [1, 2, 3, 7, 11, 42, 99, 314, 777, 2026, 31337, 515151]


func _state(sd: int = 515151) -> Dictionary:
	var s := State.new_game(sd)
	s.energy = 99
	s.cupboard = {"jar": 10, "sugar": 10, "salt": 10, "vinegar": 10, "honey": 3, "cinnamon": 3, "ginger": 3, "chili": 3}
	s.inbox = []
	s.pantry.items = []
	return s


func _type_of(recipe_id: String) -> String:
	return String(Data.recipes()[recipe_id].main.types[0])


## Fills the inbox with enough of the recipe's one fresh type; returns the variety id.
func _stock(s: Dictionary, recipe_id: String) -> String:
	var vid := DevTools.first_variety(s, _type_of(recipe_id))
	s.inbox.append(State.fresh(vid, int(Data.recipes()[recipe_id].main.count) * 2, 6))
	return vid


func _unlock(s: Dictionary, recipe_id: String) -> void:
	Letters.ensure(s).unlocked_recipes.append(recipe_id)


func _kid_product(s: Dictionary, kid: String, req: Dictionary) -> Dictionary:
	for c in Letters.kid_candidates(s, kid):
		if Letters.meets(req, String(c.recipe), c.taste):
			return State.product(String(c.key), 2, 0)
	return {}


## A one-item request letter from `kid`, answered with one matching jar: exactly +1 heart.
func _one_heart(s: Dictionary, kid: String) -> Dictionary:
	var l := Letters.ensure(s)
	var req := {"recipe": "pickle" if kid == "leo" else "jam", "taste": ""}
	var letter := {"id": int(l.next_id), "kind": "request", "from": kid, "day": int(s.day), "note": "LET_NOTE_MIA_1",
		"request": [req], "done": false, "read": false}
	l.next_id = int(l.next_id) + 1
	l.inbox.append(letter)
	var jar := _kid_product(s, kid, req)
	s.inbox.append(jar)
	return Letters.pack(s, int(letter.id), [{"item": jar, "x": 0, "y": 0, "rot": 0}])


# --- data ---------------------------------------------------------------------------------------------------------

func test_six_family_rows_build_on_a_base_recipe() -> void:
	var all := Data.recipes()
	var ids: Array = []
	for kid in ["mia", "leo"]:
		ids.append_array(Letters.FAMILY_RECIPES[kid])
	assert_eq(Kitchen.family_ids(), ids, "one row per Letters.FAMILY_RECIPES id, Mia's then Leo's")
	for id: String in ids:
		var r: Dictionary = all[id]
		var base: Dictionary = all[String(r.family_of)]
		assert_false(base.has("family_of"), "%s builds on a base recipe" % id)
		assert_eq(String(r.method), String(base.method), "%s cooks like %s" % [id, r.family_of])
		assert_eq(String(r.vessel), String(base.vessel), id)
		assert_true(int(r.priority) > 1, "%s stays out of the P0/P1 sets (orders, requests)" % id)
		assert_eq(r.main.types.size(), 1, "%s takes one fixed type" % id)
		assert_true(Data.ingredients().has(_type_of(id)), id)
		var fixed := String(r.fixed_addin)
		assert_true(fixed == "" or Data.addins().has(fixed), "%s add-in %s" % [id, fixed])
		assert_eq(Kitchen.fixed_addin(id), fixed)
		assert_eq(ProductGen.base_value(r), ProductGen.base_value(base) + 20, "%s value bonus" % id)
		assert_eq(String(r.adjective), "Granny's")
	assert_eq(Kitchen.fixed_addin("jam"), null, "base recipes leave the add-in free")
	assert_false(Kitchen.is_family("jam"))
	assert_eq(Data.ids_up_to("recipes", 1).filter(func(i: String) -> bool: return Kitchen.is_family(i)), [])


func test_kid_and_love_of_each_family_recipe() -> void:
	for kid: String in Letters.FAMILY_RECIPES:
		var list: Array = Letters.FAMILY_RECIPES[kid]
		for i in list.size():
			assert_eq(Kitchen.family_kid(list[i]), kid)
			assert_eq(Kitchen.family_love(list[i]), [3, 6, 10][i], "%s at love %d" % [list[i], [3, 6, 10][i]])
	assert_eq(Kitchen.family_kid("jam"), "")
	assert_eq(Kitchen.family_love("jam"), 0)


# --- unlocks ------------------------------------------------------------------------------------------------------

func test_love_three_six_ten_unlocks_each_kids_recipes_in_order() -> void:
	for kid: String in Letters.FAMILY_RECIPES:
		var s := _state(11)
		var list: Array = Letters.FAMILY_RECIPES[kid]
		for id: String in list:
			assert_false(Kitchen.available(s, id), "%s locked at love %d" % [id, int(Letters.ensure(s).love[kid])])
		for i in list.size():
			s.letters.love[kid] = int(Letters.LOVE_STEPS[i]) - 1
			var res := _one_heart(s, kid)
			assert_true(res.ok, str(res))
			assert_eq(int(s.letters.love[kid]), int(Letters.LOVE_STEPS[i]))
			assert_eq(res.unlocked, [list[i]], "love %d unlocks %s" % [int(Letters.LOVE_STEPS[i]), list[i]])
			for j in list.size():
				assert_eq(Kitchen.available(s, list[j]), j <= i, "%s after love %d" % [list[j], int(s.letters.love[kid])])
		assert_eq(Kitchen.unlocked_family(s), list)


func test_unlocked_family_recipes_join_their_station_last() -> void:
	var s := _state()
	assert_eq(Kitchen.recipes_at(s, "stir_pot"), ["jam", "fruit_butter", "chutney"])
	_unlock(s, "pepper_relish")
	_unlock(s, "grannys_quince_butter")
	_unlock(s, "salted_porcini")
	assert_eq(Kitchen.recipes_at(s, "stir_pot"), ["jam", "fruit_butter", "chutney", "grannys_quince_butter", "pepper_relish"])
	assert_eq(Kitchen.recipes_at(s, "pack_jar"), ["pickle", "brined_mushroom", "kraut", "salted_porcini"])
	assert_eq(Kitchen.unlocked_family(s), ["grannys_quince_butter", "pepper_relish", "salted_porcini"])


func test_locked_or_old_save_answers_wrong() -> void:
	var s := _state()
	var vid := _stock(s, "grannys_quince_butter")
	assert_eq(Kitchen.check(s, "grannys_quince_butter", vid, "", "cinnamon").reason, Kitchen.R_WRONG, "locked")
	s.erase("letters")
	assert_false(Kitchen.family_unlocked(s, "grannys_quince_butter"), "old save without letters")
	assert_eq(Kitchen.unlocked_family(s), [])
	var r := Kitchen.cook(s, "grannys_quince_butter", vid, "", "cinnamon", 3)
	assert_false(r.ok)
	assert_eq(s.book.variants.size(), 0)


# --- check and cook -----------------------------------------------------------------------------------------------

func test_each_family_recipe_checks_and_cooks() -> void:
	for id: String in Kitchen.family_ids():
		var s := _state()
		_unlock(s, id)
		var r: Dictionary = Data.recipes()[id]
		var vid := _stock(s, id)
		var fixed := String(r.fixed_addin)
		var ok := Kitchen.check(s, id, vid, "", fixed)
		assert_true(ok.ok, "%s: %s" % [id, ok])
		# the add-in is fixed: another one, or none when one is asked for, does not fit
		var other := "clove" if fixed != "clove" else "honey"
		s.cupboard[other] = 1
		assert_eq(Kitchen.check(s, id, vid, "", other).reason, Kitchen.R_WRONG, "%s with %s" % [id, other])
		if fixed != "":
			assert_eq(Kitchen.check(s, id, vid, "", "").reason, Kitchen.R_WRONG, "%s without its %s" % [id, fixed])
		# only its one type fits
		var wrong_type := "apple" if _type_of(id) != "apple" else "pear"
		var wv := DevTools.first_variety(s, wrong_type)
		s.inbox.append(State.fresh(wv, 9, 6))
		assert_eq(Kitchen.check(s, id, wv, "", fixed).reason, Kitchen.R_WRONG, "%s with %s" % [id, wrong_type])
		# missing inputs are named
		if fixed != "":
			var had := int(s.cupboard[fixed])
			s.cupboard[fixed] = 0
			var miss := Kitchen.check(s, id, vid, "", fixed)
			assert_eq(miss.reason, Kitchen.R_MISSING, id)
			assert_eq(int(miss.missing.get(fixed, 0)), 1, "%s misses its %s" % [id, fixed])
			s.cupboard[fixed] = had
		var before: Dictionary = s.cupboard.duplicate()
		var energy := int(s.energy)
		var res := Kitchen.cook(s, id, vid, "", fixed, 3)
		assert_true(res.ok, "%s cooks: %s" % [id, res])
		var key := ProductGen.make_key(id, [vid], fixed)
		assert_eq(String(res.item.key), key)
		assert_eq(int(res.item.wait_left), int(r.wait_days), "%s waits like %s" % [id, r.family_of])
		assert_true(bool(res.is_new))
		assert_true(s.book.variants.has(key))
		assert_eq(energy - int(s.energy), Kitchen.energy_cost(String(r.method)))
		for b: String in r.base:
			assert_eq(int(before[b]) - int(s.cupboard[b]), int(r.base[b]), "%s uses %s" % [id, b])
		if fixed != "":
			assert_eq(int(before[fixed]) - int(s.cupboard[fixed]), 1, "%s uses its %s" % [id, fixed])
		assert_true(bool(res.desc.family), "%s is a family jar" % id)
		assert_eq(String(res.desc.appearance.label_color), ProductGen.FAMILY_LABEL, "%s gold label" % id)
		assert_eq(String(res.desc.appearance.motif), ProductGen.FAMILY_MOTIF)


func test_gold_label_only_on_family_jars_and_look_stays_deterministic() -> void:
	var s := _state()
	var used := {}
	for rid: String in Data.ids_up_to("recipes", 1):
		for vid: String in s.varieties:
			var d := ProductGen.describe(Kitchen.product_key(rid, vid, vid, ""), s.varieties)
			used[String(d.appearance.label_color)] = true
			assert_false(bool(d.family))
	assert_false(used.has(ProductGen.FAMILY_LABEL), "no base jar wears the family gold")
	var key := ProductGen.make_key("crabapple_jelly", [DevTools.first_variety(s, "crabapple")], "")
	assert_eq(ProductGen.describe(key, s.varieties), ProductGen.describe(key, s.varieties))


# --- names and value ----------------------------------------------------------------------------------------------

func test_family_names_say_grannys_within_28_characters() -> void:
	var max_len := int(Data.grammar().product_name_max)
	var grannys := 0
	var total := 0
	for sd in SEEDS:
		var vs := VarietyGen.generate_all(sd, 0)
		for id: String in Kitchen.family_ids():
			var r: Dictionary = Data.recipes()[id]
			for vid: String in vs:
				if String(vs[vid].type) != _type_of(id):
					continue
				var n := ProductGen.product_name(ProductGen.make_key(id, [vid], String(r.fixed_addin)), vs)
				total += 1
				assert_true(n.length() <= max_len, "%s -> '%s' (%d)" % [id, n, n.length()])
				assert_true(n.ends_with(String(r.short)), "%s -> '%s'" % [id, n])
				if n.begins_with("Granny's "):
					grannys += 1
				else:
					assert_eq(n, String(r.short), "only the long one drops Granny's: '%s'" % n)
	assert_true(total > 50)
	assert_true(grannys > total / 2, "most family jars say Granny's (%d of %d)" % [grannys, total])
	var vs := VarietyGen.generate_all(7, 0)
	var quince := ""
	for vid: String in vs:
		if String(vs[vid].type) == "quince" and VarietyGen.feature_of(vs[vid]).length() <= 6:
			quince = vid
	if quince != "":
		var name := ProductGen.product_name(ProductGen.make_key("grannys_quince_butter", [quince], "cinnamon"), vs)
		assert_eq(name, "Granny's %s Quince Butter" % VarietyGen.feature_of(vs[quince]))


func test_family_jars_are_worth_more_than_their_base_recipe() -> void:
	var s := _state()
	var checked := 0
	for id: String in Kitchen.family_ids():
		var r: Dictionary = Data.recipes()[id]
		var fixed := String(r.fixed_addin)
		for vid: String in s.varieties:
			if String(s.varieties[vid].type) != _type_of(id):
				continue
			var fk := ProductGen.make_key(id, [vid], fixed)
			var bk := Kitchen.product_key(String(r.family_of), vid, vid, fixed)
			var fh := ProductGen.harmony(ProductGen.taste(fk, s.varieties))
			var bh := ProductGen.harmony(ProductGen.taste(bk, s.varieties))
			if fh < bh:
				continue
			for q in [1, 2, 3]:
				assert_true(ProductGen.value(fk, s.varieties, q) > ProductGen.value(bk, s.varieties, q), "%s %s q%d" % [id, vid, q])
				checked += 1
	assert_true(checked > 20, "compared %d" % checked)
