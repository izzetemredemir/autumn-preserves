class_name ProductGen
extends RefCounted
## SIM-01 · Procedural preserves (spec §6.4, §7.3). Pure: same key -> same name, taste, look.
## key = "<recipe>|<variety>[|<variety2>]|<addin or ->", e.g. "jam|crabapple_3|cinnamon", "chutney|pear_1|pepper_2|-".
## The first variety is the main one (chutney: the fruit); the last one gives the chunk pattern (chutney: the vegetable).

const AXES := ["sweet", "sour", "spicy", "salty", "earthy"]
const RARITY_RANK := {"common": 0, "uncommon": 1, "rare": 2}
## Pantry cells per vessel (spec §7.4 table): bottles stand 1x2, pie and bread lie 2x1.
const VESSEL_SIZE := {"jam_jar": Vector2i(1, 1), "pickle_jar": Vector2i(1, 1), "bottle": Vector2i(1, 2), "pie": Vector2i(2, 1), "bread": Vector2i(2, 1)}
## Palette picks for the procedural look (art-bible §1.1): paper labels, gold metal lids, warm two-tone cloth checks.
const LABEL_COLORS := ["f2d9c5", "b9a697", "dbcc83", "e5bd7f"]
const MOTIFS := ["leaf", "star", "stripe"]
const METAL_LIDS := [["9b8039", "e5bd7f"], ["b66813", "e5bd7f"], ["9b8039", "dbcc83"]]
const CLOTH_LIDS := [["a22512", "f2d9c5"], ["62272c", "e19064"], ["83571e", "e5bd7f"], ["b66813", "f2d9c5"], ["c94d2e", "dbcc83"]]
## Fill of a product without a variety (bread): bark ramp.
const PLAIN_FILL := ["83571e", "c58845", "e5bd7f"]


static func make_key(recipe_id: String, variety_ids: Array, addin_id: String) -> String:
	var parts: Array = [recipe_id]
	parts.append_array(variety_ids)
	parts.append(addin_id if addin_id != "" else "-")
	return "|".join(parts)


## {"recipe": String, "varieties": Array[String], "addin": String ("" when none)}
static func parse_key(key: String) -> Dictionary:
	var p := key.split("|")
	var addin := p[p.size() - 1]
	return {"recipe": p[0], "varieties": Array(p.slice(1, p.size() - 1)), "addin": "" if addin == "-" else addin}


## Main variety taste (chutney: fruit and vegetable averaged, halves up) + method effect + add-in effect, clamped.
static func taste(key: String, varieties: Dictionary) -> Array:
	var p := parse_key(key)
	var vs: Array = p.varieties
	var out := [0, 0, 0, 0, 0]
	if vs.size() == 1:
		out = _variety_taste(String(vs[0]), varieties)
	elif vs.size() >= 2:
		var a := _variety_taste(String(vs[0]), varieties)
		var b := _variety_taste(String(vs[1]), varieties)
		for i in 5:
			out[i] = ceili((int(a[i]) + int(b[i])) / 2.0)
	var recipe: Dictionary = Data.recipes().get(p.recipe, {})
	_add_effect(out, recipe.get("effect"))
	if p.addin != "":
		var addin: Dictionary = Data.addins().get(p.addin, {})
		_add_effect(out, addin.get("effect"))
	var cfg: Dictionary = Data.rules().taste
	for i in 5:
		out[i] = clampi(int(out[i]), int(cfg.min), int(cfg.max))
	return out


## Axis ids for the label, 0-2 entries, e.g. ["sweet", "sour"].
static func profile(t: Array) -> Array:
	var thr := int(Data.rules().taste.profile_threshold)
	var out: Array = []
	for i: int in _ranked(t):
		if out.size() < 2 and int(t[i]) >= thr:
			out.append(AXES[i])
	return out


static func profile_label(t: Array) -> String:
	var ids := profile(t)
	if ids.is_empty():
		return "Mild"
	var names: Array = Data.grammar().axis_names
	var parts: Array = []
	for id in ids:
		parts.append(names[AXES.find(id)])
	return " & ".join(parts)


## +1 when the top two axes are both >= 4 and a liked pair; +1 when no axis is >= 8 and at least two are >= 3.
static func harmony(t: Array) -> int:
	var cfg: Dictionary = Data.rules().taste
	var h := 0
	var order := _ranked(t)
	var a: int = order[0]
	var b: int = order[1]
	var pair_min := int(cfg.harmony_pair_min)
	if int(t[a]) >= pair_min and int(t[b]) >= pair_min:
		for pair: Array in cfg.liked_pairs:
			if (pair[0] == AXES[a] and pair[1] == AXES[b]) or (pair[0] == AXES[b] and pair[1] == AXES[a]):
				h += 1
				break
	var high := 0
	var calm := true
	for v in t:
		if int(v) >= int(cfg.balance_max_exclusive):
			calm = false
		if int(v) >= int(cfg.balance_axis_min):
			high += 1
	if calm and high >= int(cfg.balance_axes_min_count):
		h += 1
	return h


## Total stars 1..5 = quality (1..3) + harmony (0..2).
static func total_stars(quality: int, harmony_stars: int) -> int:
	return clampi(quality + harmony_stars, 1, 5)


## "[Adjective] [Feature] [Type] [Short]": add-in adjective or profile adjective; repeat rule; 28-char fallbacks.
static func product_name(key: String, varieties: Dictionary) -> String:
	var p := parse_key(key)
	var recipe: Dictionary = Data.recipes().get(p.recipe, {})
	var short := String(recipe.get("short", String(p.recipe).capitalize()))
	var adjective := ""
	if p.addin != "":
		var addin: Dictionary = Data.addins().get(p.addin, {})
		adjective = String(addin.get("adjective", String(p.addin).capitalize()))
	else:
		var adjs: Dictionary = Data.grammar().profile_adjectives
		var prof := profile(taste(key, varieties))
		adjective = String(adjs.mild if prof.is_empty() else adjs[prof[0]])
	var feature := ""
	var type_part := ""
	var vs: Array = p.varieties
	if not vs.is_empty():
		var v := _variety_or_type(String(vs[0]), varieties)
		feature = VarietyGen.feature_of(v)
		type_part = VarietyGen.base_name(v)
	return compose_name(adjective, feature, type_part, short)


## Applies the repeat rule (adjective and feature share their first 4 letters -> drop the feature), then the length
## limit: drop the feature first, then the adjective.
static func compose_name(adjective: String, feature: String, type_part: String, short: String) -> String:
	var max_len := int(Data.grammar().product_name_max)
	if adjective != "" and feature != "" and adjective.left(4).to_lower() == feature.left(4).to_lower():
		feature = ""
	var out := _join([adjective, feature, type_part, short])
	if out.length() > max_len:
		out = _join([adjective, type_part, short])
	if out.length() > max_len:
		out = _join([type_part, short])
	return out


## Rarest variety in the key; "common" without varieties.
static func rarity(key: String, varieties: Dictionary) -> String:
	var best := "common"
	for id in parse_key(key).varieties:
		var r := String(varieties.get(id, {}).get("rarity", "common"))
		if int(RARITY_RANK.get(r, 0)) > int(RARITY_RANK[best]):
			best = r
	return best


## floor(base * rarity_mult * star_mult[quality + harmony]) + addin_bonus
static func value(key: String, varieties: Dictionary, quality: int) -> int:
	var p := parse_key(key)
	var recipe: Dictionary = Data.recipes().get(p.recipe, {})
	var cfg: Dictionary = Data.rules().value
	var stars := total_stars(quality, harmony(taste(key, varieties)))
	var star_mult: Array = cfg.star_mult
	var mult := float(cfg.rarity_mult[rarity(key, varieties)]) * float(star_mult[stars])
	var v := floori(float(base_value(recipe)) * mult + 0.000001)
	if p.addin != "":
		var addin: Dictionary = Data.addins().get(p.addin, {})
		v += int(cfg.addin_bonus.get(addin.get("kind", ""), 0))
	return v


## Base value of a recipe row. Fruit vinegar has none of its own: it is worth sell_each per cupboard unit it makes
## (spec §6.3: 2 vinegar, 10 each).
static func base_value(recipe: Dictionary) -> int:
	var v := int(recipe.get("base_value", 0))
	if v <= 0 and recipe.has("sell_each") and typeof(recipe.get("output_cupboard")) == TYPE_DICTIONARY:
		for id in recipe.output_cupboard:
			v += int(recipe.sell_each) * int(recipe.output_cupboard[id])
	return v


## Everything a view needs: {"key","recipe","name","taste","profile","profile_label","harmony","rarity","zone",
##  "vessel","size": Vector2i, "appearance": {"vessel","fill": [3 hex],"chunk","chunk_seed","label_shape": 0..2,
##  "label_color": hex,"motif": "leaf"|"star"|"stripe","lid": "metal"|"cloth","lid_colors": [2 hex]}}
## appearance also carries "tint": the add-in's palette hex ("" without add-in).
static func describe(key: String, varieties: Dictionary) -> Dictionary:
	var p := parse_key(key)
	var recipe: Dictionary = Data.recipes().get(p.recipe, {})
	var t := taste(key, varieties)
	var vessel := String(recipe.get("vessel", "jam_jar"))
	return {
		"key": key, "recipe": p.recipe, "name": product_name(key, varieties), "taste": t,
		"profile": profile(t), "profile_label": profile_label(t), "harmony": harmony(t),
		"rarity": rarity(key, varieties), "zone": String(recipe.get("zone", "room")), "vessel": vessel,
		"size": vessel_size(vessel), "appearance": _appearance(key, p, vessel, varieties),
	}


static func vessel_size(vessel: String) -> Vector2i:
	return VESSEL_SIZE.get(vessel, Vector2i.ONE)


## Appearance seed (spec §6.4): fnv1a32(key) & 0x7FFFFFFF. Same key -> same look in every save.
static func appearance_seed(key: String) -> int:
	return Hash.fnv1a31(key)


## Three ramp tones [1+shift .. 3+shift] of the variety's type; an add-in moves the window one tone toward its tint.
static func fill_tones(variety: Dictionary, addin_id: String) -> Array:
	var ing: Dictionary = Data.ingredients().get(variety.get("type", ""), {})
	var ramp: Variant = ing.get("ramp")
	if typeof(ramp) != TYPE_ARRAY or ramp.size() < 3:
		return PLAIN_FILL.duplicate()
	var top: int = ramp.size() - 3
	var start := clampi(1 + int(variety.get("color_shift", 0)), 0, top)
	if addin_id != "":
		var tint := String(Data.addins().get(addin_id, {}).get("tint", ""))
		if tint != "":
			var lt := Color.html(tint).get_luminance()
			var lm := Color.html(String(ramp[start + 1])).get_luminance()
			if lt < lm:
				start = clampi(start - 1, 0, top)
			elif lt > lm:
				start = clampi(start + 1, 0, top)
	return ramp.slice(start, start + 3)


static func _appearance(key: String, p: Dictionary, vessel: String, varieties: Dictionary) -> Dictionary:
	var seed_v := appearance_seed(key)
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var vs: Array = p.varieties
	var fill: Array = PLAIN_FILL.duplicate()
	var chunk := "none"
	if not vs.is_empty():
		fill = fill_tones(_variety_or_type(String(vs[0]), varieties), p.addin)
		var last := _variety_or_type(String(vs[vs.size() - 1]), varieties)
		var ing: Dictionary = Data.ingredients().get(last.get("type", ""), {})
		chunk = String(ing.get("texture", "none"))
	var tint := ""
	if p.addin != "":
		tint = String(Data.addins().get(p.addin, {}).get("tint", ""))
	var label_shape := r.randi_range(0, 2)
	var label_color := String(LABEL_COLORS[r.randi_range(0, LABEL_COLORS.size() - 1)])
	var motif := String(MOTIFS[r.randi_range(0, MOTIFS.size() - 1)])
	var lid := "metal" if r.randf() < 0.5 else "cloth"
	var lids: Array = METAL_LIDS if lid == "metal" else CLOTH_LIDS
	var lid_colors: Array = lids[r.randi_range(0, lids.size() - 1)].duplicate()
	return {
		"vessel": vessel, "fill": fill, "chunk": chunk, "chunk_seed": seed_v, "label_shape": label_shape,
		"label_color": label_color, "motif": motif, "lid": lid, "lid_colors": lid_colors, "tint": tint,
	}


## Axis indices by value, high to low; ties keep axis order (sweet > sour > spicy > salty > earthy).
static func _ranked(t: Array) -> Array:
	var order := [0, 1, 2, 3, 4]
	order.sort_custom(func(a: int, b: int) -> bool: return int(t[a]) > int(t[b]) or (int(t[a]) == int(t[b]) and a < b))
	return order


static func _variety_or_type(id: String, varieties: Dictionary) -> Dictionary:
	if varieties.has(id):
		return varieties[id]
	return {"type": State.type_of_variety(id)}


static func _variety_taste(id: String, varieties: Dictionary) -> Array:
	return VarietyGen.taste_of(_variety_or_type(id, varieties))


static func _add_effect(into: Array, effect: Variant) -> void:
	if typeof(effect) != TYPE_ARRAY:
		return
	for i in mini(5, effect.size()):
		into[i] = int(into[i]) + int(effect[i])


static func _join(words: Array) -> String:
	var kept: Array = []
	for w in words:
		if String(w) != "":
			kept.append(w)
	return " ".join(kept)
