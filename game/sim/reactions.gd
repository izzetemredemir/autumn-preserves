class_name Reactions
extends RefCounted
## FUN-REACT · What people say about the jar you made (pure, templates in res://data/reactions.json, no autoloads).
## line(desc, who, lang, seed) builds one short line from the jar's generated name, its top taste words, its stars and
## the person: delight ("Cinnamon Ember Crabapple Jam? My favourite!"), taste ("So tangy and sweet, just right."),
## playful for inventions ("Pumpkin and pear... brave! I love it."), likes and dislikes from npcs.json, and each
## person's own flavour. Turkish lines take their suffixes from Turkish (question particle "mi/mı/mu/mü", compound
## nouns). A name too long for the line falls back like ProductGen's names (without the feature, then the adjective,
## then the dish word alone). Same (save seed, day, jar key, who) -> same line: seed_for() feeds line().
## who: a neighbour id (npcs.json), a grandchild ("mia", "leo"), "granny" or "buyer" (a market customer; opts.likes
## carries their wishes).

const STREAM := "react"
## Category order: the weighted pick walks it, so the draw never depends on Dictionary order.
const CATEGORIES := ["delight", "taste", "stars", "likes", "dislikes", "odd", "who"]
const KIDS := ["mia", "leo"]
## Categories that never fit Granny talking about her own jar.
const GRANNY_SKIP := ["delight", "likes", "dislikes"]


static func table() -> Dictionary:
	return Data.table("reactions")


## Seed of one person's line about one jar on one day (tech-spec §6: its own stream "react").
static func seed_for(save_seed: int, day: int, key: String, who: String) -> int:
	return Seeds.seed_for(save_seed, STREAM, day, "%s|%s" % [key, who])


## Whether this buyer says their line out loud (the market: some sales, not all). Same seed -> same answer.
static func speaks(seed_value: int) -> bool:
	var chance := float(table().get("speak_chance", 0.5))
	return Hash.fnv1a31("%d|speak" % seed_value) % 100 < int(chance * 100.0)


## Everything a line needs about one jar, in one language:
## {"key", "lang", "names": [full name .. dish word], "name", "taste", "profile", "stars", "formula", "family",
##  "words": [an invention's ingredient words], "noun": dish word, "noun_c": Turkish compound form of it ("" none)}.
static func describe(key: String, varieties: Dictionary, quality: int, lang_code: String = "") -> Dictionary:
	var lang := ProductGen.lang(lang_code)
	var formula := FormulaGen.is_formula(key)
	var t := ProductGen.taste(key, varieties)
	var parts := ProductGen.name_parts(key, varieties, lang)
	var p := ProductGen.parse_key(key)
	var family := not formula and (Data.recipes().get(p.recipe, {}) as Dictionary).has("family_of")
	var noun := String(parts.get("noun", "")) if formula else ProductGen.recipe_short(String(p.recipe), lang)
	var names: Array = []
	for n: String in [String(parts.name), ProductGen._join([parts.adjective, parts.type, parts.short]),
			ProductGen._join([parts.type, parts.short]), noun]:
		if n != "" and not names.has(n):
			names.append(n)
	var noun_c := ""
	if lang == "tr" and not family:
		var exc: Dictionary = Data.grammar().get("tr", {}).get("compound_exceptions", {})
		noun_c = FormulaGen.tr_compound(noun) if formula else Turkish.compound(noun, exc)
	var harmony := FormulaGen.harmony(key, varieties) if formula else ProductGen.harmony(t)
	return {"key": key, "lang": lang, "names": names, "name": names[0] if not names.is_empty() else "",
		"taste": t, "profile": ProductGen.profile(t), "stars": ProductGen.total_stars(quality, harmony),
		"formula": formula, "family": family, "words": FormulaGen.words(key, lang) if formula else [],
		"noun": _lower(noun, lang), "noun_c": _lower(noun_c, lang)}


## One line about the jar `desc` (describe()) by `who`. opts: "likes" (a buyer's wished axes), "named" (only lines
## that say the jar's name: letters), "max" (characters; default reactions.json max_chars). "" when nothing fits.
static func line(desc: Dictionary, who: String, lang_code: String, seed_value: int, opts: Dictionary = {}) -> String:
	var lang := ProductGen.lang(lang_code)
	var tab := table()
	var lt: Dictionary = tab.get(lang, {})
	var max_chars := int(opts.get("max", tab.get("max_chars", 52)))
	var kind := kind_of(who)
	var profile: Array = desc.get("profile", [])
	var love := liked(desc, who, opts)
	var hate := disliked(desc, who) if love == "" else ""
	# a speaker's own variant of a category wins ("likes_buyer": strangers at the market, "odd_granny": her own dish)
	var own := func(c: String) -> Array: return lt.get("%s_%s" % [c, kind], lt.get(c, []))
	var pools := {
		"delight": [own.call("delight"), profile],
		"taste": [own.call("taste") if not profile.is_empty() else own.call("mild"), profile],
		"stars": [own.call("stars") if int(desc.get("stars", 0)) >= 4 else [], profile],
		"likes": [own.call("likes") if love != "" else [], [love]],
		"dislikes": [own.call("dislikes") if hate != "" else [], [hate] if hate != "*" else []],
		"odd": [own.call("odd") if bool(desc.get("formula", false)) else [], profile],
		"who": [(lt.get("who", {}) as Dictionary).get(kind, []), profile],
	}
	var weights_cfg: Dictionary = (tab.get("weights", {}) as Dictionary).merged(
		(tab.get("weights_of", {}) as Dictionary).get(kind, {}), true)
	var usable: Array = []  # [[filled lines], ...] per category
	var weights: Array = []
	for c: String in CATEGORIES:
		if kind == "granny" and c in GRANNY_SKIP:
			continue
		var lines: Array = []
		for t: String in pools[c][0]:
			if bool(opts.get("named", false)) and not t.contains("{name}"):
				continue
			var s := fill(t, desc, pools[c][1], lang, max_chars)
			if s != "":
				lines.append(s)
		if not lines.is_empty():
			usable.append(lines)
			weights.append(float(weights_cfg.get(c, 1)))
	if usable.is_empty():
		return ""
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var pick: Array = usable[Seeds.pick_weighted(r, weights)]
	return String(pick[r.randi_range(0, pick.size() - 1)])


## The template category key of a speaker: "buyer3" -> "buyer".
static func kind_of(who: String) -> String:
	return "buyer" if who.begins_with("buyer") else who


## Taste axes `who` likes: opts.likes, a neighbour's or a grandchild's npcs.json likes, else none.
static func likes_of(who: String, opts: Dictionary = {}) -> Array:
	if opts.has("likes"):
		return opts.likes
	var npcs := Data.npcs()
	if who in KIDS:
		return (npcs.get("grandkids", {}) as Dictionary).get(who, {}).get("likes", [])
	return (npcs.get(who, {}) as Dictionary).get("likes", []) if who != "grandkids" else []


## The liked axis the jar is strongest in (taste >= the gift rule's gift_like_min), "" when it meets no like. The town's
## heart pop.
static func liked(desc: Dictionary, who: String, opts: Dictionary = {}) -> String:
	var t: Array = desc.get("taste", [])
	var need := int(Data.rules().friendship.gift_like_min)
	var best := ""
	var best_v := -1
	for axis in likes_of(who, opts):
		var i := ProductGen.AXES.find(String(axis))
		if i >= 0 and i < t.size() and int(t[i]) >= need and int(t[i]) > best_v:
			best = String(axis)
			best_v = int(t[i])
	return best


## The disliked axis a neighbour tastes in the jar, "*" when a grandchild's disliked ingredient group is in it, else "".
static func disliked(desc: Dictionary, who: String) -> String:
	if who in KIDS:
		return "*" if Letters.dislikes(who, String(desc.get("key", ""))) else ""
	var axis := String((Data.npcs().get(who, {}) as Dictionary).get("dislikes", "")) if who != "grandkids" else ""
	var i := ProductGen.AXES.find(axis)
	var t: Array = desc.get("taste", [])
	if i >= 0 and i < t.size() and int(t[i]) >= int(Data.rules().friendship.gift_like_min):
		return axis
	return ""


## Fills one template; "" when the jar has nothing for a placeholder or even its shortest name is too long.
## `axes`: the axis ids {a} and {b} stand for.
static func fill(template: String, desc: Dictionary, axes: Array, lang_code: String, max_chars: int) -> String:
	var lang := ProductGen.lang(lang_code)
	var words: Dictionary = (table().get(lang, {}) as Dictionary).get("axes", {})
	var ax: Array = []
	for a in axes:
		if String(a) != "" and words.has(String(a)):
			ax.append(String(words[String(a)]))
	var ws: Array = desc.get("words", [])
	var s := template
	var need := {
		"{a}": ax.size() >= 1, "{A}": ax.size() >= 1, "{b}": ax.size() >= 2, "{B}": ax.size() >= 2,
		"{w1}": ws.size() >= 1, "{W1}": ws.size() >= 1, "{w2}": ws.size() >= 2, "{W2}": ws.size() >= 2,
		"{noun}": String(desc.get("noun", "")) != "", "{noun_c}": String(desc.get("noun_c", "")) != "",
		"{name}": not (desc.get("names", []) as Array).is_empty(),
	}
	for k: String in need:
		if s.contains(k) and not bool(need[k]):
			return ""
	if ax.size() >= 1:
		s = s.replace("{a}", String(ax[0])).replace("{A}", upper_first(String(ax[0]), lang))
	if ax.size() >= 2:
		s = s.replace("{b}", String(ax[1])).replace("{B}", upper_first(String(ax[1]), lang))
	if ws.size() >= 1:
		s = s.replace("{w1}", _lower(String(ws[0]), lang)).replace("{W1}", upper_first(String(ws[0]), lang))
	if ws.size() >= 2:
		s = s.replace("{w2}", _lower(String(ws[1]), lang)).replace("{W2}", upper_first(String(ws[1]), lang))
	s = s.replace("{noun_c}", String(desc.get("noun_c", ""))).replace("{noun}", String(desc.get("noun", "")))
	if not s.contains("{name}"):
		s = particles(s, lang)
		return s if s.length() <= max_chars and not s.contains("{") else ""
	for n in desc.get("names", []):
		var out := particles(s.replace("{name}", String(n)), lang)
		if out.length() <= max_chars and not out.contains("{"):
			return out
	return ""


## Turkish question particle: each " {mi}" becomes " mi/mı/mu/mü" by the vowel harmony of the word before it
## ("Reçeli mi", "Turşusu mu", "Üzüm mü", "Tuzlu mu"). English drops it.
static func particles(s: String, lang: String) -> String:
	while s.contains("{mi}"):
		var at := s.find("{mi}")
		if lang != "tr":
			var cut := at - 1 if at > 0 and s[at - 1] == " " else at
			s = s.substr(0, cut) + s.substr(at + 4)
			continue
		s = s.substr(0, at) + "m" + Turkish.harmony4(s.substr(0, at).strip_edges()) + s.substr(at + 4)
	return s


## First letter in upper case, Turkish aware ("ekşi" -> "Ekşi", "ılık" -> "Ilık", "incir" -> "İncir").
static func upper_first(w: String, lang: String) -> String:
	if w == "":
		return w
	var c := w[0]
	if lang == "tr" and c == "i":
		c = "İ"
	elif lang == "tr" and c == "ı":
		c = "I"
	else:
		c = c.to_upper()
	return c + w.substr(1)


static func _lower(w: String, lang: String) -> String:
	return Turkish.lower_word(w) if lang == "tr" else w.to_lower()
