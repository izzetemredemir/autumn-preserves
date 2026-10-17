extends "res://tests/_runner/test_case.gd"
## FUN-REACT: what people say about a jar (Reactions; templates in data/reactions.json). Determinism, every template
## filled for 500 random products in English and Turkish within the bubble (m5x7 16 px, 168 px, 3 lines), Turkish
## suffixes, name fallbacks, likes and dislikes, the market's speak chance and the grandchild's reply.

const RV := preload("res://scenes/market/react_view.gd")
const SEEDS := [1, 24, 424242, 7, 99]
const PRODUCTS := 500
const WHO := ["grocer", "baker", "postman", "vintner", "librarian", "mia", "leo", "granny", "buyer"]
const DEMO := {
	"crabapple_4": {"id": "crabapple_4", "type": "crabapple", "name": "Ember Crabapple", "rarity": "rare", "tier": 3,
		"color_shift": 1, "taste_delta": [1, 0, 0, 0, 0], "size": "medium"},
	"pear_2": {"id": "pear_2", "type": "pear", "name": "Mill Pear", "rarity": "common", "tier": 1,
		"color_shift": 0, "taste_delta": [0, 0, 0, 1, 0], "size": "medium"},
}


func _state(save_seed: int) -> Dictionary:
	var s := State.new_game(save_seed)
	VarietyGen.ensure_types(s.varieties, save_seed)
	return s


## A product key of `recipe_id` with fitting varieties of `s` and a random add-in (bread: none).
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
					or slot.has("recipe") and g == "fruit":
				ok.append(id)
		ok.sort()
		if not ok.is_empty():
			vs.append(ok[r.randi_range(0, ok.size() - 1)])
	var fixed: Variant = Kitchen.fixed_addin(recipe_id)
	var adds: Array = Data.addins().keys()
	adds.sort()
	var addin := String(fixed) if fixed != null else (String(adds[r.randi_range(0, adds.size() - 1)]) if r.randf() < 0.6 else "")
	return ProductGen.make_key(recipe_id, vs, addin)


## `n` random keys of `s`: recipe products (family ones too) and about a quarter inventions.
func _random_keys(s: Dictionary, r: RandomNumberGenerator, n: int) -> Array:
	var recipes: Array = Data.recipes().keys()
	recipes.sort()
	var vids: Array = s.varieties.keys()
	vids.sort()
	var adds: Array = Data.addins().keys()
	adds.sort()
	var out: Array = []
	for i in n:
		if r.randf() < 0.25:
			var comps: Array = []
			for k in r.randi_range(2, 3):
				var c := String(vids[r.randi_range(0, vids.size() - 1)]) if r.randf() < 0.7 \
					else _recipe_key(s, String(recipes[r.randi_range(0, recipes.size() - 1)]), r)
				if not comps.has(c):
					comps.append(c)
			var ads: Array = []
			if r.randf() < 0.5:
				ads.append(adds[r.randi_range(0, adds.size() - 1)])
			var methods := FormulaGen.methods()
			out.append(FormulaGen.make_key(String(methods[r.randi_range(0, methods.size() - 1)]), comps, ads))
		else:
			out.append(_recipe_key(s, String(recipes[r.randi_range(0, recipes.size() - 1)]), r))
	return out


## Every template of a language: [[category, template], ...].
func _templates(lang: String) -> Array:
	var lt: Dictionary = Reactions.table()[lang]
	var out: Array = []
	for c in ["delight", "taste", "mild", "stars", "likes", "likes_buyer", "dislikes", "odd", "odd_granny"]:
		for t in lt[c]:
			out.append([c, String(t)])
	for who: String in lt.who:
		for t in lt.who[who]:
			out.append(["who:" + who, String(t)])
	return out


## Problems of one finished line: placeholders left, double spaces, over the length, glyphs m5x7 lacks, more than
## three lines or a line wider than the bubble, words lost in the wrap. "" when it is fine.
func _bad(s: String, max_chars: int) -> String:
	if s.contains("{") or s.contains("}"):
		return "placeholder left"
	if s.contains("  ") or s != s.strip_edges():
		return "spaces"
	if s.length() > max_chars:
		return "%d > %d chars" % [s.length(), max_chars]
	for i in s.length():
		if s[i] != " " and not RV.BODY.has_char(s.unicode_at(i)):
			return "glyph " + s[i]
	var wrapped := RV.wrap(s)
	var lines := wrapped.split("\n")
	if lines.size() > RV.MAX_LINES:
		return "%d lines" % lines.size()
	for l in lines:
		if RV.text_width(l) > RV.MAX_W - RV.PAD.x * 2:
			return "line %d px" % RV.text_width(l)
	if wrapped.replace("\n", " ") != s:
		return "wrap lost words"
	return ""


# --- determinism ---------------------------------------------------------------------------------------------------

func test_same_seed_day_jar_and_person_give_the_same_line() -> void:
	var s := _state(424242)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var seen := {}
	for key: String in _random_keys(s, r, 40):
		for lang in ["en", "tr"]:
			var desc := Reactions.describe(key, s.varieties, 2, lang)
			for who: String in WHO:
				var sd := Reactions.seed_for(424242, 9, key, who)
				var a := Reactions.line(desc, who, lang, sd)
				var b := Reactions.line(Reactions.describe(key, s.varieties, 2, lang), who, lang, Reactions.seed_for(424242, 9, key, who))
				assert_eq(a, b, "%s %s %s" % [key, who, lang])
				assert_ne(a, "", "always something to say: %s %s %s" % [key, who, lang])
				seen[a] = true
	assert_eq(Reactions.seed_for(1, 3, "jam|pear_2|-", "baker"), Reactions.seed_for(1, 3, "jam|pear_2|-", "baker"))
	assert_ne(Reactions.seed_for(1, 3, "jam|pear_2|-", "baker"), Reactions.seed_for(1, 4, "jam|pear_2|-", "baker"))
	assert_ne(Reactions.seed_for(1, 3, "jam|pear_2|-", "baker"), Reactions.seed_for(1, 3, "jam|pear_2|-", "grocer"))
	assert_true(seen.size() > 120, "lines vary (%d different)" % seen.size())


# --- every template, 500 products ----------------------------------------------------------------------------------

func test_every_template_fills_for_500_products_in_both_languages() -> void:
	var max_chars := int(Reactions.table().max_chars)
	var granny_max := int(Reactions.table().granny_max_chars)
	var filled := {}
	var total := 0
	var first_bad := ""
	for save_seed: int in SEEDS:
		var s := _state(save_seed)
		var r := RandomNumberGenerator.new()
		r.seed = save_seed
		for key: String in _random_keys(s, r, PRODUCTS / SEEDS.size()):
			total += 1
			for lang in ["en", "tr"]:
				var desc := Reactions.describe(key, s.varieties, r.randi_range(1, 3), lang)
				var prof: Array = desc.profile
				for ct: Array in _templates(lang):
					var axes_sets: Array = [prof]
					for a: String in ProductGen.AXES:
						axes_sets.append([a])  # likes / dislikes name one axis
					for axes: Array in axes_sets:
						var out := Reactions.fill(String(ct[1]), desc, axes, lang, max_chars)
						if out == "":
							continue
						filled["%s|%s" % [lang, ct[1]]] = true
						var why := _bad(out, max_chars)
						if why != "" and first_bad == "":
							first_bad = "%s: %s (%s)" % [why, out, key]
				for who: String in WHO:
					var sd := Reactions.seed_for(save_seed, 5, key, who)
					var mx := granny_max if who == "granny" else max_chars
					var l := Reactions.line(desc, who, lang, sd, {"max": mx})
					var why := _bad(l, mx) if l != "" else "empty"
					if why != "" and first_bad == "":
						first_bad = "%s %s: %s %s (%s)" % [who, lang, why, l, key]
	assert_true(total >= PRODUCTS, "%d products" % total)
	assert_eq(first_bad, "", "every line fits the bubble")
	for lang in ["en", "tr"]:
		for ct: Array in _templates(lang):
			assert_true(filled.has("%s|%s" % [lang, ct[1]]), "template never filled: %s %s" % [lang, ct[1]])


func test_long_names_fall_back_like_product_names() -> void:
	var desc := Reactions.describe("jam|crabapple_4|cinnamon", DEMO, 2, "en")
	assert_eq(desc.names[0], "Cinnamon Ember Crabapple Jam")
	assert_eq(desc.names[desc.names.size() - 1], "Jam", "the dish word is the last resort")
	assert_eq(Reactions.fill("{name}? My favourite!", desc, [], "en", 52), "Cinnamon Ember Crabapple Jam? My favourite!")
	assert_eq(Reactions.fill("{name}? My favourite!", desc, [], "en", 38), "Cinnamon Crabapple Jam? My favourite!", "feature dropped")
	assert_eq(Reactions.fill("{name}? My favourite!", desc, [], "en", 32), "Crabapple Jam? My favourite!", "adjective too")
	assert_eq(Reactions.fill("{name}? My favourite!", desc, [], "en", 18), "Jam? My favourite!")
	assert_eq(Reactions.fill("{name}? My favourite!", desc, [], "en", 10), "", "nothing fits: the template is skipped")
	assert_eq(Reactions.fill("So {a} and {b}, just right.", desc, ["sweet"], "en", 52), "", "a missing word skips the template")


# --- Turkish -------------------------------------------------------------------------------------------------------

func test_turkish_suffixes_on_a_sample() -> void:
	var desc := Reactions.describe("jam|crabapple_4|cinnamon", DEMO, 2, "tr")
	assert_eq(desc.names[0], "Tarçınlı Yaban Elması Reçeli")
	assert_eq(Reactions.fill("{name} {mi}? Bayıldım!", desc, [], "tr", 52), "Tarçınlı Yaban Elması Reçeli mi? Bayıldım!")
	assert_eq(Reactions.particles("Armut Turşusu {mi}?", "tr"), "Armut Turşusu mu?")
	assert_eq(Reactions.particles("Kuru Üzüm {mi}?", "tr"), "Kuru Üzüm mü?")
	assert_eq(Reactions.particles("Ayva Suyu {mi}?", "tr"), "Ayva Suyu mu?")
	assert_eq(Reactions.particles("Topraksı {mi}?", "tr"), "Topraksı mı?")
	assert_eq(Reactions.particles("Cevizli Ekmek {mi}?", "tr"), "Cevizli Ekmek mi?")
	assert_eq(Reactions.particles("Balkabağı ile armut {mi}? Ne buluş!", "tr"), "Balkabağı ile armut mu? Ne buluş!")
	assert_eq(Reactions.particles("Jam {mi}? Lovely!", "en"), "Jam? Lovely!", "English has no particle")
	assert_eq(Reactions.describe("syrup|pear_2|-", DEMO, 2, "tr").noun_c, "şurubu", "p -> b")
	assert_eq(Reactions.describe("bread|walnut", {}, 2, "tr").noun_c, "ekmeği", "k -> ğ")
	assert_eq(Reactions.describe("juice|pear_2|-", DEMO, 2, "tr").noun_c, "suyu", "Su -> Suyu")
	assert_eq(Reactions.describe("chutney|pear_2|-", DEMO, 2, "tr").noun_c, "çatni sosu", "already compound")
	assert_eq(Reactions.describe("pickle|pear_2|-", DEMO, 2, "tr").noun_c, "turşusu")
	assert_eq(Reactions.fill("Kasabanın en güzel {noun_c}!", Reactions.describe("syrup|pear_2|-", DEMO, 2, "tr"), [], "tr", 52),
		"Kasabanın en güzel şurubu!")
	assert_eq(Reactions.fill("{A} {mi}? Senin için denerim!", desc, ["salty"], "tr", 52), "Tuzlu mu? Senin için denerim!")
	assert_eq(Reactions.fill("{A} {mi}? Senin için denerim!", desc, ["sour"], "tr", 52), "Ekşi mi? Senin için denerim!")
	assert_eq(Reactions.upper_first("ılık", "tr"), "Ilık")
	assert_eq(Reactions.upper_first("incir", "tr"), "İncir")
	assert_eq(Reactions.upper_first("incir", "en"), "Incir")


func test_inventions_get_playful_lines_with_their_words() -> void:
	var s := _state(24)
	var vids: Array = s.varieties.keys()
	vids.sort()
	var key := FormulaGen.make_key("stir_pot", [vids[0], vids[vids.size() - 1]], [])
	for lang in ["en", "tr"]:
		var desc := Reactions.describe(key, s.varieties, 2, lang)
		assert_true(desc.formula)
		assert_true((desc.words as Array).size() >= 1, str(desc.words))
		var odd := Reactions.fill(String(Reactions.table()[lang].odd[2]), desc, [], lang, 52)
		assert_ne(odd, "", "the dish-word line fits every invention")
	var w := Reactions.describe(key, s.varieties, 2, "en").words as Array
	if w.size() >= 2:
		var line := Reactions.fill("{W1} and {w2}... brave! I love it.", Reactions.describe(key, s.varieties, 2, "en"), [], "en", 52)
		assert_true(line.begins_with(String(w[0])) and line.contains(" and " + String(w[1]).to_lower()), line)


# --- people --------------------------------------------------------------------------------------------------------

func test_likes_and_dislikes_follow_npcs_json() -> void:
	var salty_sour := {"key": "x", "taste": [1, 5, 0, 6, 0], "profile": ["salty", "sour"]}
	assert_eq(Reactions.liked(salty_sour, "grocer"), "salty", "Barnaby likes salty and sour: the strongest one")
	assert_eq(Reactions.liked(salty_sour, "baker"), "")
	assert_eq(Reactions.disliked(salty_sour, "baker"), "salty", "Rosie dislikes salty")
	assert_eq(Reactions.liked(salty_sour, "buyer3", {"likes": ["sour"]}), "sour", "a buyer's wishes")
	assert_eq(Reactions.liked({"taste": [3, 3, 3, 3, 3]}, "grocer"), "", "below gift_like_min")
	assert_eq(Reactions.kind_of("buyer12"), "buyer")
	# a grandchild's disliked group (Leo: fruit) is a dislike without an axis
	var s := _state(7)
	for id: String in s.varieties:
		if String(Data.ingredients().get(String(s.varieties[id].type), {}).get("group", "")) == "fruit":
			assert_eq(Reactions.disliked({"key": "jam|%s|-" % id, "taste": [5, 0, 0, 0, 0]}, "leo"), "*")
			break
	# a liked jar shows the like (and the town's heart pop)
	var line := ""
	for sd in 40:
		line = Reactions.line(salty_sour.merged({"names": ["Briny Jam"], "stars": 3, "noun": "jam"}), "grocer", "en", sd)
		if line.begins_with("Salty!") or line.contains("salty, just how"):
			break
	assert_true(line.begins_with("Salty!") or line.contains("salty, just how"), line)


func test_granny_never_flatters_herself_and_stays_short() -> void:
	var s := _state(1)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var delight: Array = Reactions.table().en.delight
	for key: String in _random_keys(s, r, 60):
		var desc := Reactions.describe(key, s.varieties, 3, "en")
		var l := Reactions.line(desc, "granny", "en", Reactions.seed_for(1, 2, key, "granny"), {"max": int(Reactions.table().granny_max_chars)})
		assert_true(l.length() <= int(Reactions.table().granny_max_chars), l)
		for t: String in delight:
			assert_false(l == Reactions.fill(t, desc, desc.profile, "en", 52), "no 'You spoil me' from Granny: " + l)


func test_market_buyers_speak_on_some_sales_not_all() -> void:
	var yes := 0
	for i in 400:
		if Reactions.speaks(Reactions.seed_for(42, 7, "jam|pear_2|-", "buyer%d" % i)):
			yes += 1
	assert_true(yes > 120 and yes < 280, "%d of 400 speak" % yes)
	assert_eq(Reactions.speaks(12345), Reactions.speaks(12345))


func test_grandchild_reply_names_a_parcel_jar() -> void:
	var s := _state(77)
	var l := Letters.ensure(s)
	var vids: Array = s.varieties.keys()
	vids.sort()
	var keys := ["jam|%s|cinnamon" % vids[0], "pickle|%s|-" % vids[vids.size() - 1]]
	l.sent.append({"letter": 3, "to": "mia", "day": 8, "reply_day": 10, "keys": keys, "care": false, "hearts": 2,
		"unlocked": [], "replied": true})
	var reply := {"id": 4, "kind": "reply", "from": "mia", "day": 10, "note": "LET_REPLY_MIA_1", "re": 3, "care": false,
		"hearts": 2, "unlocked": [], "read": false}
	var jar := Letters.reply_jar(s, reply)
	assert_has(keys, jar)
	for lang in ["en", "tr"]:
		var line := Letters.reply_line(s, reply, lang)
		var names: Array = Reactions.describe(jar, s.varieties, 2, lang).names
		var named := false
		for n: String in names:
			named = named or line.contains(n)
		assert_true(named, "%s line names the jar: %s" % [lang, line])
		assert_eq(line, Letters.reply_line(s, reply, lang), "same letter, same line")
	assert_eq(Letters.reply_line(s, {"kind": "request", "from": "mia"}), "", "requests name no jar")
	assert_eq(Letters.reply_line(s, {"kind": "reply", "from": "mia", "re": 99}), "", "no parcel, no line")
