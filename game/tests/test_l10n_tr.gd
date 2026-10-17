extends "res://tests/_runner/test_case.gd"
## L10N-TR: Turkish suffix helper, Turkish procedural names (same keys, same draws, 28-letter limit), language-neutral
## saves, the settings language and the Turkish string table.

const SEEDS := [1, 2, 3, 7, 42, 99, 1234, 12345, 424242, 2147483647, 5, 77]
const DEMO_VARIETIES := {
	"crabapple_4": {"id": "crabapple_4", "type": "crabapple", "name": "Ember Crabapple", "rarity": "rare", "tier": 3,
		"color_shift": 1, "taste_delta": [1, 0, 0, 0, 0], "size": "medium"},
	"pear_2": {"id": "pear_2", "type": "pear", "name": "Mill Pear", "rarity": "common", "tier": 1,
		"color_shift": 0, "taste_delta": [0, 0, 0, 1, 0], "size": "medium"},
	"crabapple_2": {"id": "crabapple_2", "type": "crabapple", "name": "Sharp Crabapple", "rarity": "common", "tier": 1,
		"color_shift": 0, "taste_delta": [0, 1, 0, 0, 0], "size": "medium"},
	"quince_1": {"id": "quince_1", "type": "quince", "name": "Ember Quince", "rarity": "common", "tier": 0,
		"color_shift": 1, "taste_delta": [0, 0, 1, 0, 0], "size": "medium"},
}


func _with_locale(locale: String, f: Callable) -> Variant:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale(locale)
	var out: Variant = f.call()
	TranslationServer.set_locale(before)
	return out


# --- suffix helper -------------------------------------------------------------------------------------------

func test_vowel_harmony_li() -> void:
	assert_eq(Turkish.with_li("Tarçın"), "Tarçınlı")
	assert_eq(Turkish.with_li("Ceviz"), "Cevizli")
	assert_eq(Turkish.with_li("Tuz"), "Tuzlu")
	assert_eq(Turkish.with_li("Süt"), "Sütlü")
	assert_eq(Turkish.with_li("Bal"), "Ballı")
	assert_eq(Turkish.with_li("Kestane"), "Kestaneli")
	assert_eq(Turkish.with_li("Acı"), "Acılı")
	assert_eq(Turkish.with_li("Fındık"), "Fındıklı")
	assert_eq(Turkish.with_li("Limon"), "Limonlu")
	assert_eq(Turkish.harmony4("KIR"), "ı", "capital I is the dotless one")
	assert_eq(Turkish.harmony4("İZ"), "i", "capital İ is the dotted one")


func test_compound_suffix_and_softening() -> void:
	assert_eq(Turkish.compound("Reçel"), "Reçeli")
	assert_eq(Turkish.compound("Elma"), "Elması")
	assert_eq(Turkish.compound("Turşu"), "Turşusu")
	assert_eq(Turkish.compound("Ezme"), "Ezmesi")
	assert_eq(Turkish.compound("Üzüm"), "Üzümü")
	assert_eq(Turkish.compound("Şurup"), "Şurubu", "p -> b")
	assert_eq(Turkish.compound("Ekmek"), "Ekmeği", "k -> ğ")
	assert_eq(Turkish.compound("Armut"), "Armudu", "t -> d")
	assert_eq(Turkish.compound("Salatalık"), "Salatalığı")
	assert_eq(Turkish.compound("Çelenk"), "Çelengi", "nk -> ng")
	assert_eq(Turkish.compound("Bal"), "Balı", "one syllable: no softening")
	assert_eq(Turkish.compound("Ayva Ezme"), "Ayva Ezmesi", "the last word takes it")
	assert_eq(Turkish.compound("Su", {"Su": "Suyu"}), "Suyu", "irregular words from the table")
	assert_eq(Turkish.compound("Çatni Sosu", Data.grammar().tr.compound_exceptions), "Çatni Sosu", "already compound: no second suffix")
	assert_eq(Turkish.stem("Ballı"), "Bal")
	assert_eq(Turkish.stem("Altın"), "Altın")


# --- names ---------------------------------------------------------------------------------------------------

func test_turkish_names_follow_the_grammar() -> void:
	var v := DEMO_VARIETIES
	assert_eq(ProductGen.product_name("jam|crabapple_4|cinnamon", v, "en"), "Cinnamon Ember Crabapple Jam", "English unchanged")
	assert_eq(ProductGen.product_name("jam|crabapple_4|cinnamon", v, "tr"), "Tarçınlı Yaban Elması Reçeli", "33 > 28: feature dropped")
	# The card's example "Cinnamon Sharp Crabapple Jam": "Tarçınlı Ekşi Yaban Elması Reçeli" is 33, so the feature goes.
	assert_eq(VarietyGen.tr_phrase("Ekşi", "crabapple"), "Ekşi Yaban Elması")
	assert_eq(ProductGen.product_name("jam|crabapple_2|cinnamon", v, "tr"), "Tarçınlı Yaban Elması Reçeli")
	assert_eq(ProductGen.name_parts("jam|crabapple_2|cinnamon", v, "tr").feature, "Ekşi")
	assert_eq(ProductGen.product_name("jam|crabapple_2|honey", v, "tr"), "Ballı Yaban Elması Reçeli", "30 > 28: feature dropped")
	assert_eq(ProductGen.product_name("pickle|crabapple_2|clove", v, "tr"), "Yaban Elması Turşusu", "both dropped: 31 > 28")
	assert_eq(ProductGen.product_name("jam|pear_2|cinnamon", v, "tr"), "Tarçınlı Köy Armudu Reçeli", "noun feature: compound type")
	assert_eq(ProductGen.product_name("syrup|pear_2|-", v, "tr").ends_with("Armudu Şurubu"), true)
	assert_eq(ProductGen.product_name("juice|quince_1|honey", v, "tr"), "Ballı Kızıl Ayva Suyu", "irregular Su -> Suyu")
	assert_eq(ProductGen.product_name("bread|walnut", {}, "tr"), "Cevizli Ekmek", "no type: the bare recipe word")
	var parts := ProductGen.name_parts("jam|crabapple_4|cinnamon", v, "tr")
	assert_true(parts.feature_long, "the How it was made card can tell why")
	assert_eq(parts.feature, "Kızıl")
	assert_eq(VarietyGen.display_name(v.crabapple_4, "tr"), "Kızıl Yaban Elması")
	assert_eq(VarietyGen.display_name(v.pear_2, "tr"), "Köy Armudu")
	assert_eq(VarietyGen.display_name(v.pear_2, "en"), "Mill Pear")
	assert_eq(ProductGen.profile_label([6, 4, 3, 0, 0], "tr"), "Tatlı & Ekşi")
	assert_eq(ProductGen.profile_label([1, 1, 1, 1, 1], "tr"), "Hafif")
	assert_eq(ProductGen.recipe_name("fruit_butter", "tr"), "Meyve Ezmesi")
	assert_eq(ProductGen.recipe_name("fruit_butter", "en"), "Fruit Butter")


func test_chutney_is_catni_sosu() -> void:
	# TR-GLOSS: "Çatni Sosu" already carries its compound suffix; the 28-letter limit and both fallbacks still hold.
	var v := {"apple_7": {"id": "apple_7", "type": "apple", "name": "Ember Apple", "rarity": "common", "tier": 0,
		"color_shift": 1, "taste_delta": [0, 3, 0, 0, 0], "size": "medium"}}
	assert_eq(ProductGen.recipe_name("chutney", "tr"), "Çatni Sosu")
	assert_eq(ProductGen.product_name("chutney|apple_7|-", v, "tr"), "Mayhoş Kızıl Elma Çatni Sosu", "28: fits")
	assert_eq(ProductGen.product_name("chutney|apple_7|cinnamon", v, "tr"), "Tarçınlı Elma Çatni Sosu", "30 > 28: feature dropped")
	assert_eq(ProductGen.product_name("chutney|apple_7|-", v, "en"), "Tart Ember Apple Chutney", "English unchanged")


func test_coins_are_altin() -> void:
	# TR-GLOSS: the coin word is "Altın" in every Turkish string, inflected ("altına", "altının").
	var tr := _csv("res://i18n/strings_tr.csv")
	assert_eq(tr.UI_COINS, "Altın")
	assert_eq(tr.TOWN_SOLD, "%d altına satıldı")
	assert_eq(tr.UI_NO_COINS, "Altının yetmiyor")
	for k in tr:
		if String(tr[k]).to_lower().contains("akç"):
			fail("old coin word in " + k)


func test_repeat_rule_on_turkish_stems() -> void:
	# "Honeyed" + "Honey" is the English repeat; in Turkish "Ballı" + "Bal" share the stem: no "Ballı Bal Elması".
	var v := {"apple_1": {"id": "apple_1", "type": "apple", "name": "Honey Apple", "rarity": "common", "tier": 0,
		"color_shift": 0, "taste_delta": [1, 0, 0, 0, 0], "size": "medium"},
		"pumpkin_1": {"id": "pumpkin_1", "type": "pumpkin", "name": "Honey Pumpkin", "rarity": "common", "tier": 0,
		"color_shift": 0, "taste_delta": [1, 0, 0, 0, 0], "size": "medium"}}
	assert_eq(ProductGen.product_name("jam|apple_1|honey", v, "tr"), "Ballı Elma Reçeli")
	assert_eq(ProductGen.product_name("pie|pumpkin_1|cinnamon", v, "tr"), "Tarçınlı Balkabağı Turtası", "no 'Bal Balkabağı'")
	assert_eq(VarietyGen.display_name(v.pumpkin_1, "tr"), "Balkabağı")


func test_every_p0_p1_name_fits_in_turkish_over_12_seeds() -> void:
	var max_len := int(Data.grammar().product_name_max)
	var addins: Array = [""]
	addins.append_array(Data.ids_up_to("addins", 1))
	var checked := 0
	for s in SEEDS:
		var v := VarietyGen.generate_all(s, 1)
		for rid: String in Data.ids_up_to("recipes", 2):
			var r: Dictionary = Data.recipes()[rid]
			var mains := _fitting(v, r.get("main"))
			var seconds: Array = [""]
			if r.has("second"):
				seconds = _fitting(v, r.second)
			var with: Array = [String(r.fixed_addin)] if r.has("fixed_addin") else addins
			for m: String in mains:
				for sec: String in seconds:
					var ids: Array = []
					for id in [m, sec]:
						if id != "":
							ids.append(id)
					for a: String in with:
						var key := ProductGen.make_key(rid, ids, a)
						var n := ProductGen.product_name(key, v, "tr")
						checked += 1
						if n.length() > max_len or n.length() == 0 or n.contains("  ") or n != n.strip_edges():
							fail("bad Turkish name '%s' (%d) for %s" % [n, n.length(), key])
		for id in v:
			var dn := VarietyGen.display_name(v[id], "tr")
			if dn.length() > int(Data.grammar().variety_name_max):
				fail("Turkish variety name '%s' over %d" % [dn, int(Data.grammar().variety_name_max)])
	assert_true(checked > 3000, "checked %d names" % checked)


func _fitting(v: Dictionary, main: Variant) -> Array:
	if typeof(main) != TYPE_DICTIONARY:
		return [""]
	var out: Array = []
	for id in v:
		var t := String(v[id].type)
		var g := String(Data.ingredients()[t].group)
		if main.has("types") and main.types.has(t) or main.has("groups") and main.groups.has(g):
			out.append(id)
		elif main.has("recipe") and g == "fruit":
			out.append(id)
	out.sort()
	return out


func test_every_data_row_has_a_turkish_name() -> void:
	var tr: Dictionary = Data.grammar().tr
	for t in Data.ingredients():
		assert_true(tr.types.has(t), "tr.types." + t)
	for r in Data.recipes():
		assert_true(tr.recipes.has(r) and tr.recipes[r].has("name") and tr.recipes[r].has("short"), "tr.recipes." + r)
	for a in Data.addins():
		assert_true(tr.addins.has(a), "tr.addins." + a)
	var feats: Dictionary = Data.grammar().features
	for k in feats:
		for w in feats[k]:
			assert_true(tr.features.has(w), "tr.features." + String(w))


func test_current_locale_drives_the_default_language() -> void:
	var v := DEMO_VARIETIES
	var key := "jam|pear_2|cinnamon"
	var tr_name: String = _with_locale("tr", func() -> String: return ProductGen.describe(key, v).name)
	var en_name: String = _with_locale("en", func() -> String: return ProductGen.describe(key, v).name)
	assert_eq(tr_name, "Tarçınlı Köy Armudu Reçeli")
	assert_eq(en_name, "Cinnamon Mill Pear Jam")


# --- saves stay language-neutral ----------------------------------------------------------------------------

func _night_json(locale: String) -> String:
	return _with_locale(locale, func() -> String:
		var s := State.new_game(424242)
		VarietyGen.ensure_types(s.varieties, 424242)
		DayEnd.run(s)
		var demo := DevTools.load_demo()
		if not demo.is_empty():
			DayEnd.run(demo)
		var described := {}
		for id in s.varieties:
			var d := ProductGen.describe(ProductGen.make_key("jam", [id], "cinnamon"), s.varieties)
			d.erase("name")
			d.erase("profile_label")
			described[id] = d
		return JSON.stringify([s, demo, described]))


func test_saves_load_and_play_the_same_in_both_languages() -> void:
	var en := _night_json("en")
	var tr := _night_json("tr")
	assert_true(en == tr, "a new game, the demo save and one night each are identical in English and Turkish")
	assert_false(tr.contains("Reçel") or tr.contains("Yaban"), "no Turkish text in the state")
	for s in SEEDS:
		var a: Dictionary = _with_locale("en", func() -> Dictionary: return VarietyGen.generate_all(s, 1))
		var b: Dictionary = _with_locale("tr", func() -> Dictionary: return VarietyGen.generate_all(s, 1))
		assert_eq(JSON.stringify(a), JSON.stringify(b), "varieties of seed %d" % s)


# --- strings and settings ------------------------------------------------------------------------------------

func test_turkish_table_has_every_key_with_the_same_placeholders() -> void:
	var en := _csv("res://i18n/strings.csv")
	var tr := _csv("res://i18n/strings_tr.csv")
	assert_false(tr.is_empty(), "strings_tr.csv")
	var re := RegEx.create_from_string("%[-+0-9.]*[a-zA-Z]")
	for k in en:
		if not tr.has(k):
			fail("missing Turkish string " + k)
			continue
		var a: Array = re.search_all(en[k]).map(func(m: RegExMatch) -> String: return m.get_string())
		var b: Array = re.search_all(tr[k]).map(func(m: RegExMatch) -> String: return m.get_string())
		if a != b:
			fail("%s placeholders %s, Turkish has %s" % [k, a, b])


func _csv(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and row[0] != "":
			out[row[0]] = row[1]
	return out


func test_language_setting_applies_the_locale() -> void:
	var before := TranslationServer.get_locale()
	GameSettings.apply_language("tr")
	assert_eq(ProductGen.lang(), "tr")
	assert_eq(String(TranslationServer.translate("TITLE_NEW_GAME")), "Yeni Oyun")
	GameSettings.apply_language("en")
	assert_eq(ProductGen.lang(), "en")
	assert_eq(String(TranslationServer.translate("TITLE_NEW_GAME")), "New Game")
	TranslationServer.set_locale(before)
