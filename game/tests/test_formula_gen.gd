extends "res://tests/_runner/test_case.gd"
## FORMULA-KITCHEN: invented dishes (FormulaGen, Kitchen.check_formula / cook_formula, ProductGen's fx hand-over).

const FONT := preload("res://assets/fonts/m6x11plus.ttf")
const SEEDS := [1, 24, 424242]
const SWEEP := 2100
const NESTED := "fx|knead|[jam|crabapple_3|cinnamon]+pear_2+walnut|honey"
const ZONES := ["dry", "room", "cool"]
const TR_FORMS := {"Konserve": "Konservesi", "Komposto": "Kompostosu", "Marmelat": "Marmeladı", "Çeşni": "Çeşnisi",
	"Yahni": "Yahnisi", "Ezme": "Ezmesi", "Şerbet": "Şerbeti", "Nektar": "Nektarı", "Şıra": "Şırası", "Tonik": "Toniği",
	"Demleme": "Demlemesi", "Süt": "Sütü", "Turta": "Turtası", "Gözleme": "Gözlemesi", "Rulo": "Rulosu", "Tatlı": "Tatlısı",
	"Börek": "Böreği", "Somun": "Somunu", "Çörek": "Çöreği", "Turşu": "Turşusu", "Ekşitme": "Ekşitmesi",
	"Salamura": "Salamurası"}


func _state(save_seed: int = 424242) -> Dictionary:
	var s := State.new_game(save_seed)
	VarietyGen.ensure_types(s.varieties, save_seed)
	s.energy = 80
	s.inbox = []
	s.pantry.items = []
	s.cupboard = {"honey": 2, "cinnamon": 1, "jar": 1}
	return s


## A fresh state holding what `components` and `addins` need (2 of each variety, 1 product, nuts, cupboard add-ins).
func _stocked(components: Array, addins: Array) -> Dictionary:
	var s := _state()
	for c: String in components:
		match FormulaGen.component_kind(c):
			"fresh":
				s.inbox.append(State.fresh(c, 3, 5))
			"nut":
				s.inbox.append(State.nut(c, 2))
			"product":
				s.pantry.items.append({"item": State.product(c, 2, 0), "x": 0, "y": 4, "rot": 0})
	for a: String in addins:
		if String(Data.addins()[a].kind) == "nut":
			s.inbox.append(State.nut(a, 1))
		else:
			s.cupboard[a] = int(s.cupboard.get(a, 0)) + 1
	return s


func _count(list: Array, pred: Callable) -> int:
	var n := 0
	for it in list:
		var item: Dictionary = it.item if it.has("item") else it
		if pred.call(item):
			n += int(item.get("count", 1))
	return n


## `n` random formulas of `s` (fresh, nuts, recipe products, earlier formulas as products).
func _random_keys(s: Dictionary, r: RandomNumberGenerator, n: int) -> Array:
	var vids: Array = s.varieties.keys()
	vids.sort()
	var nuts := ["walnut", "hazelnut", "chestnut"]
	var recipes: Array = Data.recipes().keys()
	var adds: Array = Data.addins().keys()
	var methods := FormulaGen.methods()
	var out: Array = []
	var shallow: Array = []
	for i in n:
		var comps: Array = []
		var want := r.randi_range(2, 4)
		while comps.size() < want:
			var k := r.randi_range(0, 11)
			var c := ""
			if k < 6:
				c = String(vids[r.randi_range(0, vids.size() - 1)])
			elif k < 8:
				c = String(nuts[r.randi_range(0, 2)])
			elif k < 10 or shallow.is_empty():
				c = _recipe_key(s, String(recipes[r.randi_range(0, recipes.size() - 1)]), r)
			else:
				c = String(shallow[r.randi_range(0, shallow.size() - 1)])
			if not comps.has(c):
				comps.append(c)
		var ads: Array = []
		for j in r.randi_range(0, 2):
			ads.append(adds[r.randi_range(0, adds.size() - 1)])
		var key := FormulaGen.make_key(String(methods[r.randi_range(0, methods.size() - 1)]), comps, ads)
		out.append(key)
		if FormulaGen.depth(key) == 1:
			shallow.append(key)
	return out


## A product key of `recipe_id` with a fitting variety of `s` (bread: none).
func _recipe_key(s: Dictionary, recipe_id: String, r: RandomNumberGenerator) -> String:
	var row: Dictionary = Data.recipes()[recipe_id]
	var vs: Array = []
	for slot_name in ["main", "second"]:
		var slot: Variant = row.get(slot_name)
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var ok: Array = []
		for id: String in s.varieties:
			var t := String(s.varieties[id].type)
			var g := String(Data.ingredients().get(t, {}).get("group", ""))
			if slot.has("types") and slot.types.has(t) or slot.has("groups") and slot.groups.has(g) \
					or slot.has("recipe") and String(Data.ingredients().get(t, {}).get("group", "")) == "fruit":
				ok.append(id)
		ok.sort()
		vs.append(ok[r.randi_range(0, ok.size() - 1)])
	var fixed: Variant = Kitchen.fixed_addin(recipe_id)
	var addin := String(fixed) if fixed != null else ""
	return ProductGen.make_key(recipe_id, vs, addin)


# --- key -----------------------------------------------------------------------------------------------------------

func test_any_order_of_the_same_parts_gives_the_same_key() -> void:
	var a := FormulaGen.make_key("knead", ["pear_2", "jam|crabapple_3|cinnamon", "walnut"], ["honey"])
	var b := FormulaGen.make_key("knead", ["walnut", "[jam|crabapple_3|cinnamon]", "pear_2", "pear_2"], ["honey", "honey"])
	assert_eq(a, NESTED, "canonical form")
	assert_eq(b, a, "permutation, brackets and duplicates")
	var c := FormulaGen.make_key("stir_pot", ["apple_1", "pear_1"], ["honey", "cinnamon"])
	assert_eq(c, FormulaGen.make_key("stir_pot", ["pear_1", "apple_1"], ["cinnamon", "honey"]))
	assert_true(c.ends_with("|cinnamon+honey"), "add-ins sorted")
	assert_true(FormulaGen.make_key("press", ["apple_1", "pear_1"], []).ends_with("|-"), "no add-in: -")


func test_nested_keys_parse_and_round_trip() -> void:
	var p := FormulaGen.parse(NESTED)
	assert_true(p.ok)
	assert_eq(p.method, "knead")
	assert_eq(p.components, [{"kind": "product", "id": "jam|crabapple_3|cinnamon"}, {"kind": "fresh", "id": "pear_2"},
		{"kind": "nut", "id": "walnut"}])
	assert_eq(p.addins, ["honey"])
	var inner := FormulaGen.make_key("stir_pot", ["apple_1", "pickle|cucumber_1|-"], [])
	var outer := FormulaGen.make_key("press", [inner, "grape_2", "hazelnut"], ["mint"])
	assert_true(outer.contains("[" + inner + "]"), "a formula component is bracketed whole: " + outer)
	var q := FormulaGen.parse(outer)
	var ids: Array = []
	for c: Dictionary in q.components:
		ids.append(c.id)
	assert_has(ids, inner)
	assert_eq(FormulaGen.make_key(q.method, ids, q.addins), outer, "round trip")
	assert_eq(FormulaGen.depth("jam|apple_1|-"), 0)
	assert_eq(FormulaGen.depth(NESTED), 1)
	assert_eq(FormulaGen.depth(outer), 2)
	assert_eq(FormulaGen.depth(FormulaGen.make_key("knead", [outer, "pear_1"], [])), 3)
	var pk := ProductGen.parse_key(NESTED)
	assert_eq(pk.recipe, "fx", "no recipe order or slot takes an invention")
	assert_eq(pk.varieties, ["pear_2"])
	assert_eq(pk.addin, "honey")


# --- determinism and the sweep -------------------------------------------------------------------------------------

func test_same_key_same_taste_name_look_value() -> void:
	var s1 := _state(24)
	var s2 := _state(24)
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for key: String in _random_keys(s1, r, 60):
		assert_eq(FormulaGen.taste(key, s1.varieties), FormulaGen.taste(key, s2.varieties), key)
		for lang in ["en", "tr"]:
			assert_eq(ProductGen.product_name(key, s1.varieties, lang), ProductGen.product_name(key, s2.varieties, lang))
		assert_eq(FormulaGen.appearance(key, s1.varieties), FormulaGen.appearance(key, s2.varieties), key)
		for q in [1, 2, 3]:
			assert_eq(ProductGen.value(key, s1.varieties, q), ProductGen.value(key, s2.varieties, q))
		var d := ProductGen.describe(key, s1.varieties)
		assert_eq(d.harmony, FormulaGen.harmony(key, s1.varieties))
	var a := ProductGen.describe(NESTED, s1.varieties)
	var b := ProductGen.describe(NESTED, s1.varieties)
	assert_eq(a, b, "describe twice")


func test_sweep_names_fit_glyphs_values_inside_caps() -> void:
	var lim: Dictionary = Data.rules().taste
	var max_len := int(Data.grammar().product_name_max)
	var palette := {}
	for h: String in JarIcon.PALETTE:
		palette[h] = true
	var total := 0
	var with_notes := 0
	var bad_glyph := ""
	for save_seed: int in SEEDS:
		var s := _state(save_seed)
		var r := RandomNumberGenerator.new()
		r.seed = save_seed
		for key: String in _random_keys(s, r, ceili(SWEEP / float(SEEDS.size()))):
			total += 1
			var d := ProductGen.describe(key, s.varieties)
			for lang in ["en", "tr"]:
				var n := ProductGen.product_name(key, s.varieties, lang)
				if n.length() > max_len or n == "":
					assert_true(false, "%s name %d chars: %s (%s)" % [lang, n.length(), n, key])
				for i in n.length():
					if n[i] != " " and not FONT.has_char(n.unicode_at(i)):
						bad_glyph = "%s in %s" % [n[i], n]
			for v in d.taste:
				if int(v) < int(lim.min) or int(v) > int(lim.max):
					assert_true(false, "taste %s %s" % [d.taste, key])
			if not d.notes.is_empty():
				with_notes += 1
			assert_true(d.notes.size() <= 2)
			assert_true(ProductGen.VESSEL_SIZE.has(d.vessel), "vessel %s" % d.vessel)
			assert_has(ZONES, d.zone)
			for hexc in d.appearance.fill:
				if not palette.has(String(hexc)):
					assert_true(false, "fill %s off palette: %s" % [hexc, key])
			var floor_v := FormulaGen.floor_value(key, s.varieties)
			for q in [1, 2, 3]:
				var v := ProductGen.value(key, s.varieties, q)
				var cap := FormulaGen.cap(key, ProductGen.total_stars(q, int(d.harmony)))
				if v < floor_v or v > maxi(cap, floor_v):
					assert_true(false, "value %d outside [%d, max(%d, floor)] %s" % [v, floor_v, cap, key])
	assert_true(total >= 2000, "%d formulas" % total)
	assert_eq(bad_glyph, "", "every glyph in m6x11plus")
	assert_true(with_notes > total / 10, "taste notes show up (%d of %d)" % [with_notes, total])


func test_turkish_dish_nouns_take_the_right_compound_suffix() -> void:
	var seen := {}
	var nouns: Dictionary = FormulaGen.cfg().nouns
	for m: String in nouns:
		var distinct := {}
		for g: String in nouns[m]:
			for pair: Array in nouns[m][g]:
				distinct[pair[0]] = true
				seen[String(pair[1])] = true
		assert_true(distinct.size() >= 4, "%s has %d nouns" % [m, distinct.size()])
	for tr_noun: String in seen:
		assert_true(TR_FORMS.has(tr_noun), "expected form listed for " + tr_noun)
		assert_eq(FormulaGen.tr_compound(tr_noun), String(TR_FORMS.get(tr_noun, "")), tr_noun)
	var s := _state()
	var key := FormulaGen.make_key("knead", ["pear_1", "pear_2", "apple_1"], [])
	var parts := ProductGen.name_parts(key, s.varieties, "tr")
	assert_true(String(parts.name).ends_with(FormulaGen.tr_compound(String(parts.noun))), "Turkish head: " + String(parts.name))


func test_notes_and_methods_have_strings() -> void:
	var csv := FileAccess.get_file_as_string("res://i18n/strings.csv")
	for rule: Dictionary in FormulaGen.cfg().pairs:
		assert_true(csv.contains("\nFX_NOTE_%s," % String(rule.id).to_upper()), "note string " + String(rule.id))


# --- cooking -------------------------------------------------------------------------------------------------------

func test_cook_formula_takes_the_parts_and_counts_the_invention() -> void:
	var jam := "jam|apple_1|-"
	var comps := ["pear_1", jam, "walnut"]
	var s := _stocked(comps, ["honey"])
	var honey_before := int(s.cupboard.honey)
	var chk := Kitchen.check_formula(s, "stir_pot", comps, ["honey"])
	assert_true(chk.ok, "check: %s %s" % [chk.reason, chk.missing])
	assert_eq(chk.key, FormulaGen.make_key("stir_pot", comps, ["honey"]))
	var energy := int(s.energy)
	var res := Kitchen.cook_formula(s, "stir_pot", comps, ["honey"], 2)
	assert_true(res.ok)
	assert_true(res.is_new and res.formula)
	assert_eq(int(s.energy), energy - Kitchen.energy_cost("stir_pot"), "same energy as a stove recipe")
	assert_eq(_count(s.inbox, func(it: Dictionary) -> bool: return it.kind == "fresh" and it.variety == "pear_1"), 1, "2 of 3 pears")
	assert_eq(_count(s.inbox, func(it: Dictionary) -> bool: return it.kind == "nut"), 1, "1 of 2 walnuts")
	assert_eq(s.pantry.items.size(), 0, "the jam went in")
	assert_eq(int(s.cupboard.honey), honey_before - 1)
	assert_eq(int(s.cupboard.jar), 1, "no jar taken")
	var item: Dictionary = s.inbox[s.inbox.size() - 1]
	assert_eq(item.key, chk.key)
	assert_eq(int(item.q), 2)
	assert_eq(int(item.wait_left), 0)
	assert_eq(s.formulas[chk.key].made, 1)
	assert_eq(s.formulas[chk.key].best, ProductGen.total_stars(2, int(res.desc.harmony)))
	assert_false(s.book.variants.has(chk.key), "inventions stay out of the recipe variants")
	s.inbox.append(State.fresh("pear_1", 2, 5))
	s.pantry.items.append({"item": State.product(jam, 3, 0), "x": 0, "y": 4, "rot": 0})
	var again := Kitchen.cook_formula(s, "stir_pot", comps, ["honey"], 3)
	assert_true(again.ok)
	assert_false(again.is_new)
	assert_eq(s.formulas[chk.key].made, 2)
	assert_eq(s.formulas[chk.key].best, ProductGen.total_stars(3, int(res.desc.harmony)))


func test_check_formula_reasons() -> void:
	var s := _stocked(["apple_1", "pear_1"], [])
	assert_eq(Kitchen.check_formula(s, "stir_pot", ["apple_1"], []).reason, Kitchen.R_FX_COUNT, "one component")
	assert_eq(Kitchen.check_formula(s, "stir_pot", ["apple_1", "pear_1"], ["honey", "cinnamon", "clove"]).reason,
		Kitchen.R_FX_COUNT, "three add-ins")
	assert_eq(Kitchen.check_formula(s, "press", ["apple_1", "pear_1"], []).reason, Kitchen.R_WRONG, "no press yet")
	assert_eq(Kitchen.check_formula(s, "boil", ["apple_1", "pear_1"], []).reason, Kitchen.R_WRONG, "no such method")
	var miss := Kitchen.check_formula(s, "pack_jar", ["apple_1", "quince_1"], [])
	assert_eq(miss.reason, Kitchen.R_MISSING)
	assert_eq(miss.missing, {"quince_1": 2})
	assert_eq(Kitchen.check_formula(s, "stir_pot", ["apple_1", "pear_1"], ["clove"]).missing, {"clove": 1})
	s.energy = 1
	assert_eq(Kitchen.check_formula(s, "stir_pot", ["apple_1", "pear_1"], []).reason, Kitchen.R_TIRED)
	s.energy = 80
	Economy.unlock(s, "press")
	assert_true(Kitchen.check_formula(s, "press", ["apple_1", "pear_1"], []).ok, "press once unlocked")
	assert_eq(Kitchen.formula_methods(s), ["stir_pot", "pack_jar", "press"])
	var deep := FormulaGen.make_key("press", [FormulaGen.make_key("stir_pot", ["apple_1", "jam|apple_1|-"], []), "pear_1"], [])
	assert_eq(FormulaGen.depth(deep), 2)
	assert_eq(Kitchen.check_formula(s, "knead", [deep, "apple_1"], []).reason, Kitchen.R_WRONG, "board still locked")
	Economy.unlock(s, "knead")
	assert_eq(Kitchen.check_formula(s, "knead", [deep, "apple_1"], []).reason, Kitchen.R_FX_DEEP, "a formula of a formula of a formula")
	assert_eq(Kitchen.check_formula(s, "knead", ["pear_1", "nope_9"], []).reason, Kitchen.R_WRONG, "unknown variety")


func test_a_nut_as_component_and_add_in_needs_two() -> void:
	var s := _stocked(["apple_1", "walnut"], [])
	var chk := Kitchen.check_formula(s, "stir_pot", ["apple_1", "walnut"], ["walnut"])
	assert_true(chk.ok, "two walnuts in the inbox")
	s.inbox = s.inbox.filter(func(it: Dictionary) -> bool: return it.kind != "nut")
	s.inbox.append(State.nut("walnut", 1))
	assert_eq(Kitchen.check_formula(s, "stir_pot", ["apple_1", "walnut"], ["walnut"]).missing, {"walnut": 1})


# --- the invention out in the world --------------------------------------------------------------------------------

func _invention(s: Dictionary, method: String, comps: Array, addins: Array, q: int = 2) -> Dictionary:
	for c: String in comps:
		match FormulaGen.component_kind(c):
			"fresh":
				s.inbox.append(State.fresh(c, 2, 5))
			"nut":
				s.inbox.append(State.nut(c, 1))
	var res := Kitchen.cook_formula(s, method, comps, addins, q)
	assert_true(res.ok, "cooked %s" % [comps])
	return res.get("item", {})


func test_inventions_sell_at_the_grocer_and_the_market() -> void:
	var s := _state()
	var item := _invention(s, "stir_pot", ["apple_1", "pear_1"], ["honey"])
	var price := Economy.sell_price(item, s.varieties)
	assert_eq(price, floori(ProductGen.value(item.key, s.varieties, 2) * float(Data.shop().sell.product_ratio)))
	assert_true(price > 0)
	var coins := int(s.coins)
	var sold := Economy.sell(s, {"where": "inbox", "index": s.inbox.find(item)})
	assert_true(sold.ok)
	assert_eq(int(s.coins), coins + price)
	s.day = 7
	s.energy = 999
	var mixes := [["apple_1", "pear_1"], ["crabapple_1", "apple_2"], ["pear_2", "quince_1"], ["apple_1", "quince_2"],
		["blackberry_1", "pear_1"], ["crabapple_2", "pear_3"]]
	for comps: Array in mixes:
		_invention(s, "stir_pot", comps, [])
	var items: Array = []
	for src in Market.sources(s):
		items.append(src.item)
	assert_eq(items.size(), mixes.size())
	var stall := Market.auto_stall(items, s.varieties)
	assert_eq(stall.size(), mixes.size(), "every invention fits the stall")
	var sales := Market.run(s, stall)
	assert_false(sales.is_empty(), "customers buy inventions")
	for sale in sales:
		assert_eq(int(sale.price), ProductGen.value(String(sale.item.key), s.varieties, int(sale.item.q)))


func test_inventions_sit_in_the_pantry_in_their_zone() -> void:
	var s := _state()
	Economy.unlock(s, "press")
	var bottle := _invention(s, "press", ["apple_1", "pear_1"], [])
	assert_eq(PantryRules.vessel_of(bottle), "bottle")
	assert_eq(PantryRules.item_size(bottle), Vector2i(1, 2), "a bottle stands 1x2")
	assert_eq(PantryRules.zone_for(bottle), ProductGen.describe(bottle.key, s.varieties).zone)
	var pickle := _invention(s, "pack_jar", ["cucumber_1", "pepper_1"], [])
	assert_eq(PantryRules.zone_for(pickle), "cool")
	assert_eq(int(pickle.wait_left), 1, "packed jars wait a night")
	var b := PantryRules.board_of(s.pantry)
	var placed := false
	for y in int(b.rows):
		for x in int(b.cols):
			if not placed and PantryRules.zone_at(b, Vector2i(x, y)) == PantryRules.zone_for(bottle) \
					and PantryRules.place(s.pantry, bottle.duplicate(), Vector2i(x, y), 0):
				placed = true
	assert_true(placed, "the bottle goes on a shelf of its zone")
	assert_true(PantryRules.in_correct_zone(b, s.pantry.items[0]))
	Economy.unlock(s, "knead")
	var loaf := _invention(s, "knead", ["porcini_1", "chanterelle_1"], [])
	assert_eq(PantryRules.vessel_of(loaf), "bread")
	assert_eq(PantryRules.zone_for(loaf), "dry")
	assert_eq(int(loaf.days_left), 3, "baked goods keep 3 days")


func test_an_invention_goes_into_a_parcel_but_fills_no_recipe_order() -> void:
	var s := _state()
	var jar := _invention(s, "stir_pot", ["apple_1", "pear_1"], ["honey"])
	var taste := ProductGen.taste(jar.key, s.varieties)
	var axis := String(ProductGen.AXES[ProductGen._ranked(taste)[0]])
	var l := Letters.ensure(s)
	var letter := {"id": int(l.next_id), "kind": "request", "from": "mia", "day": int(s.day), "note": "LET_NOTE_MIA_1",
		"request": [{"recipe": "", "taste": axis}], "done": false, "read": false}
	l.next_id = int(l.next_id) + 1
	l.inbox.append(letter)
	assert_true(Letters.giftable("mia", jar))
	var res := Letters.pack(s, int(letter.id), [{"item": jar, "x": 0, "y": 0, "rot": 0}])
	assert_true(res.ok, "packed: %s" % res.get("reason", ""))
	assert_eq(int(res.matched), 1, "a taste request takes an invention")
	assert_eq(s.inbox.find(jar), -1, "it left with the parcel")
	var other := _invention(s, "stir_pot", ["apple_1", "pear_1"], ["honey"])
	var order := {"id": 9, "npc": "baker", "recipe": "jam", "axes": [axis], "min_stars": 1, "made_day": 1, "expires_day": 9}
	assert_false(Orders.matches(order, other, s.varieties), "a recipe order wants that recipe")
	order.recipe = ""
	assert_true(Orders.matches(order, other, s.varieties), "a taste order may take it")


func test_old_saves_load_and_invent() -> void:
	var s := _state()
	s.erase("formulas")
	s.inbox.append(State.fresh("apple_1", 2, 5))
	s.inbox.append(State.fresh("pear_1", 2, 5))
	var res := Kitchen.cook_formula(s, "stir_pot", ["apple_1", "pear_1"], [], 2)
	assert_true(res.ok)
	assert_true(s.has("formulas") and s.formulas.has(res.key), "formulas made on first use")
	var back: Variant = JSON.parse_string(JSON.stringify(s))  # numbers come back as floats, like Save.load_game
	assert_eq(ProductGen.describe(res.key, back.varieties).name, res.desc.name)
	assert_eq(ProductGen.value(res.key, back.varieties, int(back.inbox[back.inbox.size() - 1].q)), ProductGen.value(res.key, s.varieties, 2))
	var demo := DevTools.load_demo()
	assert_false(demo.is_empty())
	assert_true(State.formulas(demo) is Dictionary)
	var vids: Array = []
	for it: Dictionary in demo.inbox:
		if it.kind == "fresh" and int(it.count) >= 2 and not vids.has(it.variety):
			vids.append(it.variety)
	if vids.size() >= 2:
		demo.energy = 80
		assert_true(Kitchen.cook_formula(demo, "stir_pot", vids.slice(0, 2), [], 1).ok, "the demo save invents")


func test_forest_species_mix_in_and_names_still_fit() -> void:
	var s := _state(24)
	s.day = 60
	var added := SpeciesGen.sync(s)
	assert_false(added.is_empty(), "species met by day 60")
	var species: Array = []
	for id: String in s.varieties:
		if SpeciesGen.is_species(String(s.varieties[id].type)):
			species.append(id)
	assert_false(species.is_empty())
	var r := RandomNumberGenerator.new()
	r.seed = 60
	var max_len := int(Data.grammar().product_name_max)
	var methods := FormulaGen.methods()
	for i in 400:
		var comps: Array = [species[r.randi_range(0, species.size() - 1)], species[r.randi_range(0, species.size() - 1)]]
		if r.randf() < 0.5:
			comps.append("pear_1")
		var key := FormulaGen.make_key(String(methods[r.randi_range(0, 3)]), comps, [])
		if FormulaGen.parse(key).components.size() < 2:
			continue
		for lang in ["en", "tr"]:
			var n := ProductGen.product_name(key, s.varieties, lang)
			assert_true(n.length() <= max_len and n != "", "%s %s (%s)" % [lang, n, key])
			for j in n.length():
				if n[j] != " " and not FONT.has_char(n.unicode_at(j)):
					assert_true(false, "glyph %s in %s" % [n[j], n])
	s.inbox.append(State.fresh(String(species[0]), 2, 3))
	s.inbox.append(State.fresh("pear_1", 2, 3))
	var res := Kitchen.cook_formula(s, "stir_pot", [species[0], "pear_1"], [], 2)
	assert_true(res.ok, "a species cooks into an invention")
	Data.clear_generated()
	SpeciesGen.forget()


func test_unknown_or_generated_types_never_break_a_formula() -> void:
	var s := _state()
	s.varieties["lanternberry_1"] = {"id": "lanternberry_1", "type": "lanternberry", "name": "Lantern Berry", "rarity": "rare",
		"tier": 0, "color_shift": 0, "taste_delta": [0, 0, 0, 0, 0], "size": "medium"}
	s.inbox.append(State.fresh("lanternberry_1", 2, 3))
	s.inbox.append(State.fresh("pear_1", 2, 3))
	var res := Kitchen.cook_formula(s, "stir_pot", ["lanternberry_1", "pear_1"], [], 2)
	assert_true(res.ok)
	assert_eq(res.desc.rarity, "rare", "rarest component")
	assert_true(String(res.desc.name).length() <= int(Data.grammar().product_name_max))
	assert_eq(res.desc.appearance.fill.size(), 3)
