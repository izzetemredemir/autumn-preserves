extends "res://tests/_runner/test_case.gd"
## SPECIES-GEN: generated forest species (SpeciesGen), their registry rows (Data), icons (IconLib) and forest pickups.

const SEEDS := [1, 7, 24, 452, 90210]
const DEMO_SEED := 452
const PALETTE := "../tools/palettes/autumn.hex"


func after_each() -> void:
	Data.clear_generated()


func _palette() -> Dictionary:
	var out := {}
	var path := ProjectSettings.globalize_path("res://").path_join(PALETTE)
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges() != "":
			out[line.strip_edges().to_lower()] = true
	return out


func _register(list: Array) -> void:
	for sp: Dictionary in list:
		SpeciesGen.register(sp)


# ---------------------------------------------------------------- generation

func test_same_seed_and_day_give_the_same_species_names_ramps_and_icon_bytes() -> void:
	var a := SpeciesGen.known(4242, 60)
	var a_json := JSON.stringify(a)
	_register(a)
	var icons_a: Array = []
	for sp: Dictionary in a:
		icons_a.append(IconLib.image(String(sp.id)).get_data())
	SpeciesGen.forget()
	Data.clear_generated()
	var b := SpeciesGen.known(4242, 60)
	assert_eq(JSON.stringify(b), a_json, "a second run from scratch")
	_register(b)
	for i in b.size():
		assert_eq(IconLib.image(String(b[i].id)).get_data(), icons_a[i], "icon bytes of " + String(b[i].display_name))
	assert_ne(JSON.stringify(SpeciesGen.known(4243, 60)), a_json, "another seed, other species")
	assert_eq(JSON.stringify(SpeciesGen.for_day(4242, 30)), JSON.stringify(a.filter(func(sp): return int(sp.day) == 30)))


func test_none_before_day_two_then_about_40_45_15() -> void:
	assert_eq(SpeciesGen.for_day(1, 1).size(), 0)
	assert_eq(SpeciesGen.known(1, 1).size(), 0)
	var counts := [0, 0, 0]
	for sd in range(1, 11):
		for d in range(2, 202):
			var n := SpeciesGen.for_day(sd, d).size()
			assert_true(n >= 0 and n <= 2, "0-2 a day")
			counts[n] += 1
	var total := float(counts[0] + counts[1] + counts[2])
	assert_near(counts[0] / total, 0.40, 0.05, "none")
	assert_near(counts[1] / total, 0.45, 0.05, "one")
	assert_near(counts[2] / total, 0.15, 0.04, "two")


func test_rows_are_shaped_like_ingredients_json() -> void:
	var groups := {}
	var rarities := {"common": 0, "uncommon": 0, "rare": 0}
	var textures := {}
	for row: Dictionary in Data.table("ingredients").values():
		textures[String(row.texture)] = true
	var list := SpeciesGen.known(7, 300)
	for sp: Dictionary in list:
		groups[sp.group] = true
		rarities[sp.rarity] += 1
		assert_true(["fruit", "mushroom", "vegetable"].has(sp.group), "group")
		assert_eq((sp.taste as Array).size(), 5)
		var hi := 0
		for v in sp.taste:
			assert_true(int(v) >= 0 and int(v) <= 9, "taste 0-9")
			hi = maxi(hi, int(v))
		assert_eq(int(sp.taste[SpeciesGen.AXES.find(sp.signature)]), hi, "the signature axis is the highest")
		assert_true(hi >= 5, "a signature axis pushed high")
		assert_eq((sp.ramp as Array).size(), 5, "5 ramp tones")
		assert_true(textures.has(String(sp.texture)), "texture from the existing set: " + String(sp.texture))
		assert_true(int(sp.shelf_days) >= 2, "shelf days")
		assert_true(int(sp.sell) >= 3 and int(sp.sell) <= 4, "grocer base on the base types' scale")
		assert_true(ResourceLoader.exists(IconLib.TEMPLATE % sp.template), "template " + String(sp.template))
		assert_eq(String(sp.sources[0]), "forest_bush" if sp.group == "fruit" else "forest_ground")
	assert_eq(groups.size(), 3, "all three groups appear")
	var n := float(list.size())
	assert_near(rarities.common / n, 0.6, 0.12, "common about 60 %")
	assert_near(rarities.rare / n, 0.1, 0.07, "rare about 10 %")


func test_names_unique_and_at_most_16_chars_over_300_days() -> void:
	for sd in SEEDS:
		var en := {}
		var tr_names := {}
		for sp: Dictionary in SpeciesGen.known(sd, 301):
			var e := String(sp.display_name)
			var t := String(sp.display_name_tr)
			assert_true(e.length() <= 16 and t.length() <= 16, "%s / %s" % [e, t])
			assert_false(en.has(e), "EN name repeats in seed %d: %s" % [sd, e])
			assert_false(tr_names.has(t), "TR name repeats in seed %d: %s" % [sd, t])
			assert_false(SpeciesGen.BANNED.has(e), "banned name " + e)
			en[e] = true
			tr_names[t] = true


func test_turkish_names_take_the_compound_suffix() -> void:
	var nouns: Dictionary = SpeciesGen.NOUNS
	assert_eq(SpeciesGen.compose(["Ember", "Kor", true], nouns.fruit[1]).tr, "Kor Eriği")
	assert_eq(SpeciesGen.compose(["Lantern", "Fener", true], nouns.fruit[0]).tr, "Fener Yemişi")
	assert_eq(SpeciesGen.compose(["Velvet", "Kadife", false], nouns.mushroom[0]).tr, "Kadife Şapka")
	assert_eq(SpeciesGen.compose(["Moss", "Yosun", true], nouns.vegetable[2]).tr, "Yosun Yaprağı")
	assert_eq(SpeciesGen.compose(["Velvet", "Kadife", false], nouns.mushroom[0]).en, "Velvet Cap")


func test_product_names_with_a_species_fit_28_chars() -> void:
	var list := SpeciesGen.known(1, 301)
	_register(list)
	var vs := {}
	var veg := ""
	for sp: Dictionary in list:
		vs[SpeciesGen.variety_id(sp.id)] = SpeciesGen.variety_of(sp)
		if sp.group == "vegetable" and veg == "":
			veg = SpeciesGen.variety_id(sp.id)
	var addins: Array = [""]
	addins.append_array(Data.addins().keys())
	var checked := 0
	for sp: Dictionary in list:
		var vid := SpeciesGen.variety_id(sp.id)
		var keys: Array = []
		for rid: String in Data.recipes():
			var rec: Dictionary = Data.recipes()[rid]
			var main: Variant = rec.get("main")
			if typeof(main) != TYPE_DICTIONARY or not main.has("groups") or not (main.groups as Array).has(sp.group):
				continue
			for a: String in addins:
				keys.append(ProductGen.make_key(rid, [vid, veg] if rec.get("second") != null else [vid], a))
		for key: String in keys:
			for lang in ["en", "tr"]:
				var nm := ProductGen.product_name(key, vs, lang)
				assert_true(nm.length() <= 28, "%s (%s): %s" % [key, lang, nm])
				checked += 1
	assert_true(checked > 1000, "swept %d names" % checked)


# ---------------------------------------------------------------- registry and save

func test_registry_adds_rows_without_touching_base_tables() -> void:
	var s := State.new_game(11)
	s.day = 30
	var added := SpeciesGen.sync(s)
	var known := SpeciesGen.known(11, 30)
	assert_eq(added.size(), known.size(), "one variety per species")
	var sp: Dictionary = known[0]
	var vid := SpeciesGen.variety_id(sp.id)
	assert_true(Data.ingredients().has(sp.id), "Data.ingredients() holds the species")
	assert_false(Data.table("ingredients").has(sp.id), "the base table does not")
	assert_false(Data.ids_up_to("ingredients", 9).has(sp.id), "ids_up_to stays base only")
	assert_eq(State.type_of_variety(vid), String(sp.id))
	assert_eq(VarietyGen.display_name(s.varieties[vid], "en"), String(sp.display_name))
	assert_eq(VarietyGen.display_name(s.varieties[vid], "tr"), String(sp.display_name_tr))
	assert_eq(VarietyGen.taste_of(s.varieties[vid]), sp.taste)
	assert_eq(SpeciesGen.sync(s).size(), 0, "idempotent")


func test_save_round_trip_and_old_saves() -> void:
	var s := State.new_game(5)
	s.day = 25
	SpeciesGen.sync(s)
	var first: Dictionary = SpeciesGen.known(5, 25)[0]
	assert_true(SpeciesGen.mark_seen(s, String(first.id)), "first meeting")
	assert_false(SpeciesGen.mark_seen(s, String(first.id)), "only once")
	assert_false(SpeciesGen.mark_seen(s, "apple"), "base types are not species")
	var disk: Dictionary = JSON.parse_string(JSON.stringify(s))
	Data.clear_generated()
	assert_eq(SpeciesGen.sync(disk).size(), 0, "the loaded save already holds every variety")
	assert_true(SpeciesGen.seen(disk, String(first.id)))
	assert_true(SpeciesGen.is_new(disk, String(first.id)))
	disk.day = 25 + SpeciesGen.NEW_DAYS
	assert_false(SpeciesGen.is_new(disk, String(first.id)), "the New tag fades")
	assert_eq(JSON.stringify(Data.ingredients()[first.id]), JSON.stringify(first), "the row is back after loading")
	var old := State.new_game(5)
	old.erase("species_seen")
	old.day = 25
	assert_false(SpeciesGen.seen(old, String(first.id)), "old save: nothing met yet")
	assert_eq(SpeciesGen.sync(old).size(), SpeciesGen.known(5, 25).size())
	assert_true(SpeciesGen.mark_seen(old, String(first.id)), "an old save learns species too")


func test_day_end_adds_the_new_days_species() -> void:
	var s := State.new_game(1)
	var before: int = s.varieties.size()
	for i in 12:
		DayEnd.run(s)
	var known := SpeciesGen.known(1, int(s.day))
	assert_true(known.size() > 0, "species by day %d" % int(s.day))
	assert_eq(s.varieties.size(), before + known.size())
	for sp: Dictionary in known:
		assert_true(s.varieties.has(SpeciesGen.variety_id(sp.id)), String(sp.display_name))


# ---------------------------------------------------------------- icons

func test_icons_are_palette_clean() -> void:
	var pal := _palette()
	assert_true(pal.size() >= 30, "palette read")
	var list := SpeciesGen.known(24, 60)
	_register(list)
	assert_true(list.size() >= 20, "enough species to check")
	for sp: Dictionary in list:
		for img: Image in [IconLib.image(String(sp.id)), IconLib.bush(String(sp.id), false).get_image()]:
			assert_true(img != null, "image")
			var opaque := 0
			for y in img.get_height():
				for x in img.get_width():
					var p := img.get_pixel(x, y)
					assert_true(p.a == 0.0 or p.a == 1.0, "binary alpha")
					if p.a == 1.0:
						opaque += 1
						assert_true(pal.has(p.to_html(false)), "%s: off-palette %s" % [sp.display_name, p.to_html(false)])
			assert_true(opaque > 40, "a real icon")


func test_templates_are_five_gray_value_maps() -> void:
	var names := {}
	for g: String in SpeciesGen.NOUNS:
		for n: Array in SpeciesGen.NOUNS[g]:
			names[String(n[2])] = true
	assert_true(names.size() >= 10, "3-4 templates per group")
	for t: String in names:
		var img := IconLib.template(t)
		assert_true(img != null and img.get_width() == 16 and img.get_height() == 16, t)
		for y in 16:
			for x in 16:
				var p := img.get_pixel(x, y)
				if p.a > 0.0:
					assert_eq(p.a, 1.0, t)
					assert_true([0, 64, 128, 192, 255].has(roundi(p.r * 255.0)) and p.r == p.g and p.g == p.b, t)


# ---------------------------------------------------------------- the forest

func _prefix_case(s: Dictionary) -> int:
	var sd := int(s.save_seed)
	var day := int(s.day)
	var plain := WildGen.generate(sd, day, "forest", String(s.weather), s.varieties)
	var plain_json := JSON.stringify([plain.pickups, plain.fruit_trees, plain.decor_trees, plain.ground, plain.special])
	SpeciesGen.sync(s)
	var map := WildGen.generate(sd, day, "forest", String(s.weather), s.varieties)
	var n0: int = plain.pickups.size()
	var added := SpeciesGen.add_pickups(map, sd, day)
	assert_eq(map.pickups.size(), n0 + added)
	assert_eq(JSON.stringify([map.pickups.slice(0, n0), map.fruit_trees, map.decor_trees, map.ground, map.special]),
		plain_json, "seed %d day %d: wild_gen's items stay as they were" % [sd, day])
	for i in range(n0, map.pickups.size()):
		var p: Dictionary = map.pickups[i]
		assert_eq(int(p.id), i, "ids continue")
		assert_true(bool(p.get("species", false)) and s.varieties.has(String(p.variety)), "species pickup")
		var t := int(map.ground[int(p.y) * int(map.w) + int(p.x)])
		assert_true(t != WildGen.T_WATER and t != WildGen.T_STONE and t != WildGen.T_PATH, "on open ground")
		assert_eq(String(p.kind), "bush" if SpeciesGen.row(String(p.type)).group == "fruit" else "ground")
	assert_true(SpeciesGen.all_reachable(map, SpeciesGen.reach_map(map)), "everything stays reachable")
	assert_eq(SpeciesGen.add_pickups(WildGen.generate(sd, day, "vineyard", String(s.weather), s.varieties), sd, day), 0,
		"only the forest")
	return added


func test_wild_pickups_keep_wild_gens_list_as_prefix() -> void:
	var added := 0
	for day in range(1, 15):
		var s := State.new_game(1)
		VarietyGen.ensure_types(s.varieties, 1)
		s.day = day
		s.weather = DayEnd.weather_for(1, day)
		added += _prefix_case(s)
	var demo := DevTools.load_demo()
	assert_false(demo.is_empty(), "demo save")
	assert_eq(int(demo.save_seed), DEMO_SEED)
	added += _prefix_case(demo)
	var fest := FestivalFacts.load_save()
	assert_false(fest.is_empty(), "festival save")
	var before: int = fest.varieties.size()
	added += _prefix_case(fest)
	assert_eq(fest.varieties.size(), before + SpeciesGen.known(24, 14).size(), "the festival knows days 2-14")
	assert_true(added > 0, "some species were placed")


func test_a_thirty_day_bot_meets_ten_species_and_cooks_a_jam_from_one() -> void:
	var sd := 1
	var s := State.new_game(sd)
	VarietyGen.ensure_types(s.varieties, sd)
	var met := 0
	var jam_key := ""
	for i in 30:
		var day := int(s.day)
		SpeciesGen.sync(s)
		var map := WildGen.generate(sd, day, "forest", String(s.weather), s.varieties)
		SpeciesGen.add_pickups(map, sd, day)
		for p: Dictionary in map.pickups:
			if not bool(p.get("species", false)):
				continue
			s.energy = 99
			var r := Forage.pick(s, map, int(p.id))
			assert_true(bool(r.ok), "pick " + String(p.type))
			if SpeciesGen.mark_seen(s, String(p.type)):
				met += 1
			Forage.empty_bag_to_inbox(s)
		if jam_key == "":
			jam_key = _try_jam(s)
		DayEnd.run(s)
	assert_true(met >= 10, "met %d species in 30 days" % met)
	assert_ne(jam_key, "", "a jam from a species")
	if jam_key != "":
		var vid := String(ProductGen.parse_key(jam_key).varieties[0])
		assert_true(SpeciesGen.is_species(State.type_of_variety(vid)), jam_key)
		assert_true(ProductGen.product_name(jam_key, s.varieties, "en").contains(String(s.varieties[vid].name)))


func _try_jam(s: Dictionary) -> String:
	var have := {}
	for it: Dictionary in s.inbox:
		if String(it.kind) == "fresh" and SpeciesGen.row(State.item_type(it)).get("group", "") == "fruit":
			have[it.variety] = int(have.get(it.variety, 0)) + int(it.count)
	for vid: String in have:
		if int(have[vid]) < 3:
			continue
		s.cupboard["jar"] = 9
		s.cupboard["sugar"] = 9
		s.energy = 99
		var r := Kitchen.cook(s, "jam", vid, "", "", 2)
		if bool(r.ok):
			return String(r.item.key)
	return ""
