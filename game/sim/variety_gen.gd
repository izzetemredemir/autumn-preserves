class_name VarietyGen
extends RefCounted
## SIM-01 · Ingredient varieties of a save (spec §6.2). Deterministic in save_seed (stream "variety", day 0).
## Variety: {"id": "crabapple_3", "type", "name", "rarity": "common"|"uncommon"|"rare", "tier": int,
##           "color_shift": -1|0|1, "taste_delta": [5 ints], "size": "small"|"medium"|"large"}
## Ids are "<type>_<n>", n = 1..count in tier order (rules.varieties.tiers_p0). Nut types have no varieties.
## tier = n - 1, the index into rules.varieties.tiers_pX / weights_pX. Each type draws from its own sub-stream
## (sub = type), so adding a type never changes the others.

const AXES := ["sweet", "sour", "spicy", "salty", "earthy"]


static func generate_all(save_seed: int, max_priority: int = 0) -> Dictionary:
	var cfg: Dictionary = Data.rules().varieties
	var tiers: Array = cfg.tiers_p1 if max_priority >= 1 else cfg.tiers_p0
	var ings := Data.ingredients()
	var out := {}
	for type: String in Data.ids_up_to("ingredients", max_priority):
		if ings[type].group == "nut":
			continue
		var r := Seeds.rng(save_seed, "variety", 0, type)
		var used: Array = []
		for i in tiers.size():
			var v := _roll(r, type, i, String(tiers[i]), cfg, used)
			out[v.id] = v
	return out


## BIOMES (P1): adds the varieties of every P1 type (priority 1, not a nut) that `varieties` has none of, in place:
## rules.varieties.count_p1 of them in tiers_p1 order, each type from its own sub-stream exactly as
## generate_all(save_seed, 1) rolls it. Old saves and P0 new games get the same P1 varieties whenever this runs; P0
## types are never touched (they keep their 4). Returns the added ids, sorted.
static func ensure_types(varieties: Dictionary, save_seed: int) -> Array:
	var cfg: Dictionary = Data.rules().varieties
	var tiers: Array = cfg.tiers_p1
	var ings := Data.ingredients()
	var have := {}
	for id in varieties:
		have[String(varieties[id].get("type", ""))] = true
	var added: Array = []
	for type: String in Data.ids_up_to("ingredients", 1):
		if int(ings[type].get("priority", 0)) < 1 or ings[type].group == "nut" or have.has(type):
			continue
		var r := Seeds.rng(save_seed, "variety", 0, type)
		var used: Array = []
		for i in tiers.size():
			var v := _roll(r, type, i, String(tiers[i]), cfg, used)
			varieties[v.id] = v
			added.append(v.id)
	added.sort()
	return added


## Base taste of the type + taste_delta, each axis clamped to 0..9.
static func taste_of(variety: Dictionary) -> Array:
	var out := [0, 0, 0, 0, 0]
	var ing: Dictionary = Data.ingredients().get(variety.get("type", ""), {})
	var base: Variant = ing.get("taste")
	if typeof(base) != TYPE_ARRAY:
		return out
	var delta: Array = variety.get("taste_delta", [0, 0, 0, 0, 0])
	var t: Dictionary = Data.rules().taste
	for i in 5:
		out[i] = clampi(int(base[i]) + int(delta[i]), int(t.min), int(t.max))
	return out


## Spawn weights of a type's varieties, aligned with the sorted variety ids of that type.
static func spawn_weights(varieties: Dictionary, type: String, rare_mult: float = 1.0) -> Dictionary:
	var ids: Array = []
	for id in varieties:
		if varieties[id].get("type", "") == type:
			ids.append(id)
	ids.sort()
	var cfg: Dictionary = Data.rules().varieties
	var table: Array = cfg.weights_p1 if ids.size() == int(cfg.count_p1) else cfg.weights_p0
	var weights: Array = []
	for i in ids.size():
		var v: Dictionary = varieties[ids[i]]
		var tier := int(v.get("tier", i))
		var w := float(table[tier]) if tier >= 0 and tier < table.size() else 0.0
		if v.get("rarity", "") == "rare":
			w *= rare_mult
		weights.append(w)
	return {"ids": ids, "weights": weights}


## In-game name of an ingredient type ("Crabapple", "Oyster Cap").
static func type_name(type: String) -> String:
	var ing: Dictionary = Data.ingredients().get(type, {})
	return String(ing.get("display_name", type.capitalize()))


## The feature word of a variety name ("Ember" in "Ember Crabapple"), "" when the name has none.
static func feature_of(variety: Dictionary) -> String:
	var n := String(variety.get("name", ""))
	var tn := type_name(String(variety.get("type", "")))
	if n.ends_with(" " + tn):
		return n.substr(0, n.length() - tn.length() - 1)
	return ""


## The name without its feature ("Crabapple"); the whole name when it does not follow the grammar.
static func base_name(variety: Dictionary) -> String:
	var tn := type_name(String(variety.get("type", "")))
	var n := String(variety.get("name", ""))
	if n == "" or n == tn or n.ends_with(" " + tn):
		return tn
	return n


static func _roll(r: RandomNumberGenerator, type: String, tier: int, rarity: String, cfg: Dictionary, used: Array) -> Dictionary:
	var base: Array = Data.ingredients()[type].taste
	var shifts: Array = cfg.color_shift
	var sizes: Array = cfg.sizes
	var shift := int(shifts[r.randi_range(0, shifts.size() - 1)])
	var size := String(sizes[r.randi_range(0, sizes.size() - 1)])
	var axes_max := int(cfg.taste_delta_axes_max)
	var n_axes := axes_max if rarity == "rare" else r.randi_range(1, axes_max)
	var delta := [0, 0, 0, 0, 0]
	var axes := [0, 1, 2, 3, 4]
	for k in n_axes:
		var j := r.randi_range(k, axes.size() - 1)
		var a: int = axes[j]
		axes[j] = axes[k]
		axes[k] = a
		var s := 1 if r.randf() < 0.5 else -1
		if int(base[a]) <= 0:
			s = 1
		elif int(base[a]) >= 9:
			s = -1
		delta[a] = s
	var feature := _pick_feature(r, type, delta, size, shift, used)
	used.append(feature)
	var tn := type_name(type)
	return {
		"id": "%s_%d" % [type, tier + 1], "type": type, "name": tn if feature == "" else feature + " " + tn,
		"rarity": rarity, "tier": tier, "color_shift": shift, "taste_delta": delta, "size": size,
	}


## One unused feature word: from taste and looks first, then the generic words, then any word that fits.
static func _pick_feature(r: RandomNumberGenerator, type: String, delta: Array, size: String, shift: int, used: Array) -> String:
	var feats: Dictionary = Data.grammar().features
	var pool: Array = []
	for a in 5:
		if int(delta[a]) > 0:
			_add_words(pool, feats.get(AXES[a] + "_up", []))
	if size == "small":
		_add_words(pool, feats.get("small", []))
	elif size == "large":
		_add_words(pool, feats.get("large", []))
	if shift < 0:
		_add_words(pool, feats.get("shift_down", []))
	elif shift > 0:
		_add_words(pool, feats.get("shift_up", []))
	var generic: Array = []
	_add_words(generic, feats.get("earthy_up", []))
	_add_words(generic, feats.get("salty_up", []))
	var every: Array = []
	for k in feats:
		_add_words(every, feats[k])
	every.sort()
	var max_len := int(Data.grammar().variety_name_max)
	var tn := type_name(type)
	for candidates: Array in [pool, generic, every]:
		var ok: Array = []
		for w: String in candidates:
			if not used.has(w) and (w + " " + tn).length() <= max_len:
				ok.append(w)
		if not ok.is_empty():
			return String(ok[r.randi_range(0, ok.size() - 1)])
	return ""


static func _add_words(into: Array, words: Array) -> void:
	for w in words:
		if not into.has(w):
			into.append(w)
