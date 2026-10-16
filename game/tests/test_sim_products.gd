extends "res://tests/_runner/test_case.gd"
## SIM-01: varieties, procedural preserves, cooking.

const SEEDS := [1, 2, 3, 7, 42, 99, 1234, 12345, 424242, 2147483647]

const DEMO_VARIETIES := {
	"crabapple_4": {"id": "crabapple_4", "type": "crabapple", "name": "Ember Crabapple", "rarity": "rare", "tier": 3,
		"color_shift": 1, "taste_delta": [1, 0, 0, 0, 0], "size": "medium"},
}


func _demo_state() -> Dictionary:
	var s := State.new_game(424242)
	s.varieties["crabapple_4"] = DEMO_VARIETIES.crabapple_4.duplicate(true)
	s.energy = 80
	s.cupboard = {"jar": 5, "sugar": 3, "salt": 2, "vinegar": 2, "cinnamon": 1}
	s.inbox = []
	s.pantry.items = []
	return s


func _pantry_entry(item: Dictionary) -> Dictionary:
	return {"item": item, "x": 0, "y": 4, "rot": 0}


func _fresh_count(state: Dictionary, variety_id: String) -> int:
	var n := 0
	for it: Dictionary in state.inbox:
		if it.kind == "fresh" and it.variety == variety_id:
			n += int(it.count)
	for e: Dictionary in state.pantry.items:
		if e.item.kind == "fresh" and e.item.variety == variety_id:
			n += int(e.item.count)
	return n


## Varieties of `varieties` that fit a recipe slot ({"groups"} or {"types"}).
func _fitting(varieties: Dictionary, slot: Dictionary) -> Array:
	var out: Array = []
	for id in varieties:
		var type: String = varieties[id].type
		var ok := false
		if slot.has("types"):
			ok = slot.types.has(type)
		else:
			ok = slot.groups.has(Data.ingredients()[type].group)
		if ok:
			out.append(id)
	out.sort()
	return out


# --- spec §7.3 demo jar ---------------------------------------------------------------------------------------

func test_demo_jar() -> void:
	var key := ProductGen.make_key("jam", ["crabapple_4"], "cinnamon")
	assert_eq(key, "jam|crabapple_4|cinnamon")
	assert_eq(VarietyGen.taste_of(DEMO_VARIETIES.crabapple_4), [2, 4, 0, 0, 0])
	var t := ProductGen.taste(key, DEMO_VARIETIES)
	assert_eq(t, [6, 4, 3, 0, 0])
	assert_eq(ProductGen.profile(t), ["sweet", "sour"])
	assert_eq(ProductGen.profile_label(t), "Sweet & Sour")
	assert_eq(ProductGen.harmony(t), 2)
	assert_eq(ProductGen.rarity(key, DEMO_VARIETIES), "rare")
	assert_eq(ProductGen.value(key, DEMO_VARIETIES, 3), 233)
	assert_eq(ProductGen.product_name(key, DEMO_VARIETIES), "Cinnamon Ember Crabapple Jam")
	var d := ProductGen.describe(key, DEMO_VARIETIES)
	assert_eq(d.name, "Cinnamon Ember Crabapple Jam")
	assert_eq(d.taste, [6, 4, 3, 0, 0])
	assert_eq(d.zone, "room")
	assert_eq(d.vessel, "jam_jar")
	assert_eq(d.size, Vector2i(1, 1))


# --- taste rules ---------------------------------------------------------------------------------------------

func test_profile_and_harmony_rules() -> void:
	assert_eq(ProductGen.profile_label([2, 2, 2, 2, 2]), "Mild")
	assert_eq(ProductGen.profile_label([0, 0, 3, 0, 0]), "Spicy")
	assert_eq(ProductGen.profile([4, 0, 4, 4, 0]), ["sweet", "spicy"], "ties follow axis order")
	assert_eq(ProductGen.profile_label([0, 0, 0, 5, 5]), "Salty & Earthy")
	assert_eq(ProductGen.harmony([9, 4, 0, 0, 0]), 1, "liked pair only, 9 breaks balance")
	assert_eq(ProductGen.harmony([5, 0, 0, 5, 0]), 1, "sweet-salty is not liked, balance holds")
	assert_eq(ProductGen.harmony([0, 4, 0, 4, 0]), 2, "sour-salty liked + balance")
	assert_eq(ProductGen.harmony([3, 0, 0, 0, 0]), 0)
	assert_eq(ProductGen.total_stars(1, 0), 1)
	assert_eq(ProductGen.total_stars(3, 2), 5)


func test_chutney_taste_and_name() -> void:
	var v := {
		"pear_1": {"id": "pear_1", "type": "pear", "name": "Dusk Pear", "rarity": "uncommon", "tier": 2, "color_shift": -1,
			"taste_delta": [0, 0, 0, 0, 0], "size": "medium"},
		"pepper_1": {"id": "pepper_1", "type": "pepper", "name": "Big Pepper", "rarity": "common", "tier": 0, "color_shift": 0,
			"taste_delta": [0, 0, 0, 0, 0], "size": "large"},
	}
	var key := ProductGen.make_key("chutney", ["pear_1", "pepper_1"], "")
	# (4,1,0,0,0 + 1,0,2,0,0) / 2 rounded up = 3,1,1,0,0; + chutney 2,2,1,0,0
	assert_eq(ProductGen.taste(key, v), [5, 3, 2, 0, 0])
	assert_eq(ProductGen.product_name(key, v), "Golden Dusk Pear Chutney")
	assert_eq(ProductGen.harmony(ProductGen.taste(key, v)), 1)
	assert_eq(ProductGen.rarity(key, v), "uncommon")
	# floor(45 * 1.5 * star_mult[3 + 1] = 2.0) = 135
	assert_eq(ProductGen.value(key, v, 3), 135)
	assert_eq(ProductGen.describe(key, v).appearance.chunk, "strips", "chutney chunks come from the vegetable")


# --- names ---------------------------------------------------------------------------------------------------

func test_name_repeat_rule_and_fallbacks() -> void:
	var v := {"crabapple_2": {"id": "crabapple_2", "type": "crabapple", "name": "Tart Crabapple", "rarity": "common", "tier": 1,
		"color_shift": 0, "taste_delta": [0, 1, 0, 0, 0], "size": "medium"}}
	# 1,5,0,0,0 + jam 3,0,0,0,0 = 4,5: top axis sour -> "Tart", same root as the feature -> feature drops
	assert_eq(ProductGen.product_name("jam|crabapple_2|-", v), "Tart Crabapple Jam")
	var g := {"chanterelle_1": {"id": "chanterelle_1", "type": "chanterelle", "name": "Golden Chanterelle", "rarity": "common",
		"tier": 0, "color_shift": 1, "taste_delta": [0, 0, 0, 0, 0], "size": "medium"}}
	assert_eq(ProductGen.product_name("brined_mushroom|chanterelle_1|hazelnut", g), "Hazelnut Chanterelle Brine", "over 28 -> drop feature")
	assert_eq(ProductGen.compose_name("Honeyed", "Honey", "Pear", "Jam"), "Honeyed Pear Jam")
	assert_eq(ProductGen.compose_name("Cinnamon", "Little", "Extraordinarylongfruit", "Chutney"), "Extraordinarylongfruit Chutney",
		"still over 28 -> drop adjective")


func test_all_p0_names_within_limits() -> void:
	var recipes := Data.recipes()
	var addins: Array = [""]
	addins.append_array(Data.ids_up_to("addins", 0))
	var max_len := int(Data.grammar().product_name_max)
	var checked := 0
	for s in SEEDS:
		var v := VarietyGen.generate_all(s, 0)
		for rid: String in Data.ids_up_to("recipes", 0):
			var r: Dictionary = recipes[rid]
			var mains := _fitting(v, r.main)
			var seconds: Array = [""]
			if r.has("second"):
				seconds = _fitting(v, r.second)
			assert_false(mains.is_empty(), "%s has main varieties" % rid)
			for m: String in mains:
				for sec: String in seconds:
					var ids: Array = [m] if sec == "" else [m, sec]
					for a: String in addins:
						var n := ProductGen.product_name(ProductGen.make_key(rid, ids, a), v)
						checked += 1
						if n.length() > max_len or n.length() == 0 or not n.ends_with(" " + String(r.short)):
							fail("bad name '%s' for %s" % [n, ProductGen.make_key(rid, ids, a)])
	assert_true(checked > 1000, "checked %d names" % checked)


# --- varieties -----------------------------------------------------------------------------------------------

func test_generate_all_shape() -> void:
	var cfg: Dictionary = Data.rules().varieties
	var tiers: Array = cfg.tiers_p0
	var types: Array = []
	for t: String in Data.ids_up_to("ingredients", 0):
		if Data.ingredients()[t].group != "nut":
			types.append(t)
	for s in SEEDS:
		var v := VarietyGen.generate_all(s, 0)
		assert_eq(v.size(), types.size() * int(cfg.count_p0), "seed %d count" % s)
		assert_false(v.has("walnut_1"), "nuts have no varieties")
		for t: String in types:
			var names: Array = []
			for i in tiers.size():
				var id := "%s_%d" % [t, i + 1]
				assert_true(v.has(id), id)
				if not v.has(id):
					continue
				var x: Dictionary = v[id]
				assert_eq(x.id, id)
				assert_eq(x.type, t)
				assert_eq(x.rarity, tiers[i])
				assert_eq(int(x.tier), i)
				assert_has([-1, 0, 1], int(x.color_shift))
				assert_has(cfg.sizes, x.size)
				var axes := 0
				for d in x.taste_delta:
					assert_true(abs(int(d)) <= 1, "%s delta %s" % [id, str(x.taste_delta)])
					if int(d) != 0:
						axes += 1
				assert_true(axes >= 1 and axes <= int(cfg.taste_delta_axes_max), "%s delta axes" % id)
				assert_true(String(x.name).length() <= int(Data.grammar().variety_name_max), x.name)
				assert_true(String(x.name).ends_with(VarietyGen.type_name(t)), x.name)
				assert_false(names.has(x.name), "unique names per type: %s" % x.name)
				names.append(x.name)
				for k in VarietyGen.taste_of(x):
					assert_true(int(k) >= 0 and int(k) <= 9)


func test_generate_all_deterministic() -> void:
	assert_eq(var_to_str(VarietyGen.generate_all(77, 0)), var_to_str(VarietyGen.generate_all(77, 0)))
	assert_ne(var_to_str(VarietyGen.generate_all(77, 0)), var_to_str(VarietyGen.generate_all(78, 0)))
	var p1 := VarietyGen.generate_all(77, 1)
	assert_true(p1.has("grape_6") and p1.has("apple_6"), "P1: six varieties, P1 types")
	assert_eq(p1.apple_6.rarity, "rare")


func test_spawn_weights() -> void:
	var v := VarietyGen.generate_all(5, 0)
	var w := VarietyGen.spawn_weights(v, "crabapple")
	assert_eq(w.ids, ["crabapple_1", "crabapple_2", "crabapple_3", "crabapple_4"])
	assert_eq(w.weights, [35.0, 35.0, 25.0, 5.0])
	assert_eq(VarietyGen.spawn_weights(v, "crabapple", 3.0).weights, [35.0, 35.0, 25.0, 15.0])
	assert_eq(VarietyGen.spawn_weights(v, "walnut").ids, [])
	var p1 := VarietyGen.generate_all(5, 1)
	assert_eq(VarietyGen.spawn_weights(p1, "pear").weights, [23.0, 23.0, 24.0, 12.5, 12.5, 5.0])


# --- describe ------------------------------------------------------------------------------------------------

func test_describe_deterministic() -> void:
	var v := VarietyGen.generate_all(31337, 0)
	var looks := {}
	for key: String in ["jam|crabapple_3|cinnamon", "pickle|cucumber_1|-", "chutney|pear_2|pepper_4|chili",
			"brined_mushroom|porcini_4|walnut", "fruit_butter|quince_1|honey", "jam|blackberry_2|-"]:
		var a := ProductGen.describe(key, v)
		var b := ProductGen.describe(key, VarietyGen.generate_all(31337, 0))
		assert_eq(var_to_str(a), var_to_str(b), key)
		assert_eq(a.key, key)
		var ap: Dictionary = a.appearance
		assert_eq(ap.chunk_seed, Hash.fnv1a31(key))
		assert_eq(ap.fill.size(), 3)
		var ramp: Array = Data.ingredients()[State.type_of_variety(ProductGen.parse_key(key).varieties[0])].ramp
		for hex in ap.fill:
			assert_has(ramp, hex, key)
		assert_true(int(ap.label_shape) >= 0 and int(ap.label_shape) <= 2)
		assert_has(ProductGen.MOTIFS, ap.motif)
		assert_has(["metal", "cloth"], ap.lid)
		assert_eq(ap.lid_colors.size(), 2)
		looks[var_to_str([ap.label_shape, ap.label_color, ap.motif, ap.lid, ap.lid_colors])] = true
	assert_true(looks.size() >= 3, "labels and lids vary between keys")
	assert_eq(ProductGen.describe("pickle|cucumber_1|-", v).zone, "cool")
	assert_eq(ProductGen.vessel_size("bottle"), Vector2i(1, 2))


# --- kitchen -------------------------------------------------------------------------------------------------

func test_cook_consumes_exact_inputs() -> void:
	var s := _demo_state()
	s.inbox = [State.fresh("crabapple_4", 3, 5), State.fresh("crabapple_1", 5, 5), State.fresh("crabapple_4", 2, 4)]
	s.pantry.items = [_pantry_entry(State.fresh("crabapple_4", 4, 3)), _pantry_entry(State.nut("walnut", 3))]
	var energy_before := int(s.energy)
	var c := Kitchen.check(s, "jam", "crabapple_4", "", "cinnamon")
	assert_true(c.ok, str(c))
	assert_eq(c.reason, "")
	var res := Kitchen.cook(s, "jam", "crabapple_4", "", "cinnamon", 3)
	assert_true(res.ok, str(res))
	# 3 crabapple_4 taken (recipe count), all from the first inbox stack, nothing from the pantry
	assert_eq(_fresh_count(s, "crabapple_4"), 9 - int(Data.recipes().jam.main.count))
	assert_eq(int(s.pantry.items[0].item.count), 4, "inbox before pantry")
	assert_eq(_fresh_count(s, "crabapple_1"), 5, "other varieties untouched")
	assert_eq(int(s.pantry.items[1].item.count), 3, "walnut not used")
	assert_eq(s.cupboard, {"jar": 4, "sugar": 2, "salt": 2, "vinegar": 2, "cinnamon": 0})
	assert_eq(int(s.energy), energy_before - Kitchen.energy_cost("stir_pot"))
	assert_eq(Kitchen.energy_cost("stir_pot"), 7)
	assert_true(res.is_new)
	assert_eq(res.item, State.product("jam|crabapple_4|cinnamon", 3, 0, -1))
	assert_eq(s.inbox[s.inbox.size() - 1], res.item, "product lands in the inbox")
	assert_eq(res.desc.name, "Cinnamon Ember Crabapple Jam")
	assert_eq(s.book.variants["jam|crabapple_4|cinnamon"], {"best_q": 3, "best_stars": 5, "count": 1, "first_day": 1, "good": 1})
	assert_eq(int(s.stats.jars_made), 1)


func test_cook_from_pantry_with_nut_addin_and_repeat() -> void:
	var s := _demo_state()
	s.inbox = [State.fresh("crabapple_4", 1, 5)]
	s.pantry.items = [_pantry_entry(State.nut("walnut", 2)), _pantry_entry(State.fresh("crabapple_4", 5, 3)),
		_pantry_entry(State.fresh("crabapple_4", 3, 2))]
	var res := Kitchen.cook(s, "jam", "crabapple_4", "", "walnut", 1)
	assert_true(res.ok, str(res))
	assert_eq(_fresh_count(s, "crabapple_4"), 6)
	assert_eq(int(s.pantry.items[0].item.count), 1, "one walnut used from the pantry")
	assert_eq(int(s.pantry.items[1].item.count), 3, "2 from the first pantry stack")
	assert_eq(int(s.cupboard.cinnamon), 1, "cupboard add-in untouched")
	assert_true(res.is_new)
	var again := Kitchen.cook(s, "jam", "crabapple_4", "", "walnut", 2)
	assert_true(again.ok, str(again))
	assert_false(again.is_new)
	assert_eq(s.pantry.items.size(), 1, "emptied stacks (walnut, first crabapple stack) are removed")
	assert_eq(s.pantry.items[0].item, State.fresh("crabapple_4", 3, 2))
	var e: Dictionary = s.book.variants["jam|crabapple_4|walnut"]
	assert_eq(int(e.count), 2)
	assert_eq(int(e.best_q), 2)
	assert_eq(int(s.stats.jars_made), 2)


func test_chutney_and_pickle_cook() -> void:
	var s := _demo_state()
	var fruit: String = _fitting(s.varieties, {"groups": ["fruit"]})[0]
	var veg: String = _fitting(s.varieties, {"groups": ["vegetable"]})[0]
	s.inbox = [State.fresh(fruit, 2, 3), State.fresh(veg, 4, 3)]
	var res := Kitchen.cook(s, "chutney", fruit, veg, "", 2)
	assert_true(res.ok, str(res))
	assert_eq(res.item.key, "chutney|%s|%s|-" % [fruit, veg])
	assert_eq(_fresh_count(s, fruit), 0)
	assert_eq(_fresh_count(s, veg), 2)
	assert_eq(int(s.cupboard.vinegar), 1)
	assert_eq(int(s.cupboard.sugar), 3, "chutney needs no sugar")
	var pk := Kitchen.cook(s, "pickle", veg, "", "", 1)
	assert_false(pk.ok, "only 2 vegetables left")
	assert_eq(pk.missing, {veg: 1})
	s.inbox.append(State.fresh(veg, 1, 2))
	pk = Kitchen.cook(s, "pickle", veg, "", "", 1)
	assert_true(pk.ok, str(pk))
	assert_eq(int(pk.item.wait_left), 3)
	assert_eq(int(s.cupboard.salt), 1)
	assert_eq(int(s.cupboard.vinegar), 0)


func test_check_failures() -> void:
	var s := _demo_state()
	s.inbox = [State.fresh("crabapple_4", 2, 5), State.fresh("crabapple_1", 2, 5)]
	var c := Kitchen.check(s, "jam", "crabapple_4", "", "")
	assert_false(c.ok)
	assert_eq(c.reason, "UI_KITCHEN_SAME_VARIETY", "4 crabapples, but not of one variety")
	assert_eq(c.missing, {"crabapple_4": 1})
	s.inbox.append(State.fresh("crabapple_4", 2, 5))
	assert_true(Kitchen.check(s, "jam", "crabapple_4", "", "").ok)
	assert_eq(Kitchen.check(s, "pickle", "crabapple_4", "", "").reason, "UI_KITCHEN_WRONG", "fruit is no pickle")
	assert_eq(Kitchen.check(s, "fruit_butter", "crabapple_4", "", "").reason, "UI_KITCHEN_WRONG", "butter: apple/pear/quince")
	assert_eq(Kitchen.check(s, "jam", "crabapple_4", "", "saffron").reason, "UI_KITCHEN_WRONG")
	assert_eq(Kitchen.check(s, "nope", "crabapple_4", "", "").reason, "UI_KITCHEN_WRONG")
	var w := Kitchen.check(s, "jam", "crabapple_4", "", "walnut")
	assert_eq(w.reason, "UI_KITCHEN_MISSING")
	assert_eq(w.missing, {"walnut": 1})
	s.cupboard.sugar = 0
	var m := Kitchen.check(s, "jam", "crabapple_4", "", "honey")
	assert_eq(m.reason, "UI_KITCHEN_MISSING")
	assert_eq(m.missing, {"sugar": 1, "honey": 1})
	s.cupboard.sugar = 1
	s.energy = 3
	assert_eq(Kitchen.check(s, "jam", "crabapple_4", "", "").reason, "UI_TIRED")
	var before := var_to_str([s.inbox, s.cupboard, s.energy])
	assert_false(Kitchen.cook(s, "jam", "crabapple_4", "", "", 3).ok)
	assert_eq(var_to_str([s.inbox, s.cupboard, s.energy]), before, "a failed cook changes nothing")
