class_name FormulaGen
extends RefCounted
## FORMULA-KITCHEN · Invented dishes (pure, data in res://data/formula.json). Same key -> same taste, name, look, value.
## key = "fx|<method>|<components sorted, joined by +>|<add-ins sorted, joined by + or ->", e.g.
## "fx|knead|[jam|crabapple_3|cinnamon]+pear_2+walnut|honey". A component is a fresh variety id ("pear_2"), a nut type
## ("walnut") or a finished product key in brackets (a recipe product or another formula, nesting depth <= max_depth).
## ProductGen hands every "fx|" key here (taste, names, rarity, value, describe, vessel, zone), so the pantry, inbox,
## market, shop, parcels and JarIcon treat an invention like any product. Orders never ask for one (its recipe is "fx").

const PREFIX := "fx|"
const RECIPE := "fx"
const KINDS := ["fresh", "nut", "product"]


static func cfg() -> Dictionary:
	return Data.table("formula")


static func is_formula(key: String) -> bool:
	return key.begins_with(PREFIX)


static func methods() -> Array:
	return cfg().methods


# --- key ----------------------------------------------------------------------------------------------------------

## Canonical key: duplicates merge, components and add-ins sorted, product keys bracketed (bare or bracketed input).
static func make_key(method: String, components: Array, addins: Array) -> String:
	var comps: Array = []
	for c in components:
		var s := token(String(c))
		if s != "" and not comps.has(s):
			comps.append(s)
	comps.sort()
	var ads := unique(addins)
	ads.sort()
	return "%s%s|%s|%s" % [PREFIX, method, "+".join(comps), "+".join(ads) if not ads.is_empty() else "-"]


## A component as it sits in a key: product keys (they hold "|") in brackets, the rest as they are.
static func token(id: String) -> String:
	if id.begins_with("["):
		return id
	return "[" + id + "]" if id.contains("|") else id


## Distinct non-empty ids in first-seen order.
static func unique(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		if String(id) != "" and not out.has(String(id)):
			out.append(String(id))
	return out


## {"ok", "method", "components": [{"kind": "fresh"|"nut"|"product", "id"}], "addins": [ids]}. Product ids come
## back without brackets. No state needed: a bracket is a product, a nut ingredient type a nut, the rest a variety.
static func parse(key: String) -> Dictionary:
	var out := {"ok": false, "method": "", "components": [], "addins": []}
	if not is_formula(key):
		return out
	var parts := _split_top(key, "|")
	if parts.size() != 4:
		return out
	out.method = parts[1]
	for c: String in _split_top(parts[2], "+"):
		if c == "":
			continue
		out.components.append({"kind": component_kind(c), "id": c.substr(1, c.length() - 2) if c.begins_with("[") else c})
	if parts[3] != "-":
		for a: String in parts[3].split("+", false):
			out.addins.append(a)
	out.ok = out.method != "" and not out.components.is_empty()
	return out


## "product" for a bracketed key, "nut" for a nut ingredient type, else "fresh" (a variety id).
static func component_kind(token_or_id: String) -> String:
	if token_or_id.begins_with("[") or token_or_id.contains("|"):
		return "product"
	if String(Data.ingredients().get(token_or_id, {}).get("group", "")) == "nut":
		return "nut"
	return "fresh"


## Formula levels in a key: 0 for a recipe product, 1 + the deepest product component for a formula.
static func depth(key: String) -> int:
	if not is_formula(key):
		return 0
	var d := 0
	for c: Dictionary in parse(key).components:
		if c.kind == "product":
			d = maxi(d, depth(String(c.id)))
	return d + 1


## Splits at `sep` outside brackets.
static func _split_top(s: String, sep: String) -> Array:
	var out: Array = []
	var level := 0
	var start := 0
	for i in s.length():
		var ch := s[i]
		if ch == "[":
			level += 1
		elif ch == "]":
			level -= 1
		elif ch == sep and level == 0:
			out.append(s.substr(start, i - start))
			start = i + 1
	out.append(s.substr(start))
	return out


# --- taste --------------------------------------------------------------------------------------------------------

## Five axes: weighted mean of the components -> method transform -> pair interactions -> add-ins -> clamp.
static func taste(key: String, varieties: Dictionary) -> Array:
	return _eval(key, varieties).taste


## Up to 2 taste-note ids ("bright", "warming", "savoury", "muddy"); show them with tr("FX_NOTE_<ID>").
static func notes(key: String, varieties: Dictionary) -> Array:
	return _eval(key, varieties).notes


## ProductGen.harmony of the taste plus the notes' harmony (muddy -1), never below 0.
static func harmony(key: String, varieties: Dictionary) -> int:
	var e := _eval(key, varieties)
	return maxi(ProductGen.harmony(e.taste) + int(e.harmony_mod), 0)


static func _eval(key: String, varieties: Dictionary) -> Dictionary:
	var c := cfg()
	var p := parse(key)
	var sum := [0.0, 0.0, 0.0, 0.0, 0.0]
	var wsum := 0.0
	for comp: Dictionary in p.components:
		var w := float(c.weights.get(comp.kind, 1.0))
		var t := _component_taste(comp, varieties)
		for i in 5:
			sum[i] += w * float(t[i])
		wsum += w
	var out := [0, 0, 0, 0, 0]
	var m: Dictionary = c.method.get(p.method, {})
	var mult: Array = m.get("mult", [1, 1, 1, 1, 1])
	var add: Array = m.get("add", [0, 0, 0, 0, 0])
	for i in 5:
		var mean := roundi(sum[i] / wsum) if wsum > 0.0 else 0
		out[i] = roundi(mean * float(mult[i])) + int(add[i])
	var snap := out.duplicate()
	var hits: Array = []
	var hmod := 0
	for rule: Dictionary in c.pairs:
		if _rule_hits(rule, snap):
			hits.append(String(rule.id))
			ProductGen._add_effect(out, rule.get("add"))
			hmod += int(rule.get("harmony", 0))
	for a: String in p.addins:
		ProductGen._add_effect(out, Data.addins().get(a, {}).get("effect"))
	var lim: Dictionary = Data.rules().taste
	for i in 5:
		out[i] = clampi(int(out[i]), int(lim.min), int(lim.max))
	return {"taste": out, "notes": hits.slice(0, 2), "harmony_mod": hmod}


static func _rule_hits(rule: Dictionary, t: Array) -> bool:
	if rule.has("when"):
		for axis: String in rule.when:
			if int(t[ProductGen.AXES.find(axis)]) < int(rule.when[axis]):
				return false
		return true
	if rule.has("axes_at_least"):
		var n := 0
		for v in t:
			if int(v) >= int(rule.axes_at_least):
				n += 1
		return n >= int(rule.get("count", 5))
	return false


static func _component_taste(comp: Dictionary, varieties: Dictionary) -> Array:
	match String(comp.kind):
		"product":
			return ProductGen.taste(String(comp.id), varieties)
		"nut":
			var eff: Variant = Data.addins().get(String(comp.id), {}).get("effect")
			return eff if typeof(eff) == TYPE_ARRAY and eff.size() >= 5 else [0, 0, 0, 0, 0]
	return VarietyGen.taste_of(_variety(String(comp.id), varieties))


static func _variety(id: String, varieties: Dictionary) -> Dictionary:
	if varieties.has(id):
		return varieties[id]
	return {"type": State.type_of_variety(id)}


# --- groups, words, names -----------------------------------------------------------------------------------------

## Ingredient group a component stands for: fresh by its type, nuts "nut", a product by its main variety (a formula:
## its own dominant group; bread, which has none, "grain" -> group_alias).
static func component_group(comp: Dictionary) -> String:
	var g := ""
	match String(comp.kind):
		"nut":
			g = "nut"
		"fresh":
			g = String(Data.ingredients().get(State.type_of_variety(String(comp.id)), {}).get("group", ""))
		"product":
			var k := String(comp.id)
			if is_formula(k):
				return dominant_group(k)
			var vs: Array = ProductGen.parse_key(k).varieties
			g = String(Data.ingredients().get(State.type_of_variety(String(vs[0])), {}).get("group", "")) if not vs.is_empty() else "grain"
	g = String(cfg().group_alias.get(g, g))
	return g if cfg().groups.has(g) else String(cfg().groups[0])


## The group with the most weight among the components; ties go to the earlier group in formula.json "groups".
static func dominant_group(key: String) -> String:
	var c := cfg()
	var w := {}
	for comp: Dictionary in parse(key).components:
		var g := component_group(comp)
		w[g] = float(w.get(g, 0.0)) + float(c.weights.get(comp.kind, 1.0))
	var best := String(c.groups[0])
	var best_w := -1.0
	for g: String in c.groups:
		if float(w.get(g, 0.0)) > best_w:
			best = g
			best_w = float(w.get(g, 0.0))
	return best


## Components of the dominant group first, then heaviest first (product 1.5, fresh 1, nut 0.5), key order last:
## the order the name's words and the fill's tones come in.
static func ranked(key: String) -> Array:
	var c := cfg()
	var comps: Array = parse(key).components
	var dom := dominant_group(key)
	var rank := []
	for comp: Dictionary in comps:
		rank.append((10.0 if component_group(comp) == dom else 0.0) + float(c.weights.get(comp.kind, 1.0)))
	var order: Array = range(comps.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return rank[a] > rank[b] or (rank[a] == rank[b] and a < b))
	var out: Array = []
	for i: int in order:
		out.append(comps[i])
	return out


## The name word of a component: the ingredient type ("Pear", "Armut"), a product's main type (bread: "Bread").
static func component_word(comp: Dictionary, lang_code: String = "") -> String:
	match String(comp.kind):
		"fresh", "nut":
			return VarietyGen.type_name(State.type_of_variety(String(comp.id)) if comp.kind == "fresh" else String(comp.id), lang_code)
		"product":
			var k := String(comp.id)
			if is_formula(k):
				var w := words(k, lang_code)
				return String(w[0]) if not w.is_empty() else ""
			var p := ProductGen.parse_key(k)
			if p.varieties.is_empty():
				return ProductGen.recipe_short(String(p.recipe), lang_code)
			return VarietyGen.type_name(State.type_of_variety(String(p.varieties[0])), lang_code)
	return ""


## Distinct component words, heaviest component first.
static func words(key: String, lang_code: String = "") -> Array:
	var out: Array = []
	for comp: Dictionary in ranked(key):
		var w := component_word(comp, lang_code)
		if w != "" and not out.has(w):
			out.append(w)
	return out


## [English, Turkish] dish noun: method x dominant group, picked by the key hash.
static func noun_pair(key: String) -> Array:
	var p := parse(key)
	var table: Dictionary = cfg().nouns.get(p.method, {})
	var list: Array = table.get(dominant_group(key), [])
	if list.is_empty():
		return ["Dish", "Yemek"]
	return list[Hash.fnv1a31(key) % list.size()]


static func product_name(key: String, varieties: Dictionary, lang_code: String = "") -> String:
	return String(name_parts(key, varieties, lang_code).name)


## Taste adjective (the first note's, else the top axis', else mild; one that does not echo a word) + up to two
## component words + the dish noun (Turkish: in its compound form after a word, "Armut Turtası"). Two-stage
## shortening like ProductGen: drop the second word, then the adjective (then the first word, never needed in data).
## Same keys as ProductGen.name_parts so the book's views can read either.
static func name_parts(key: String, varieties: Dictionary, lang_code: String = "") -> Dictionary:
	var turkish_on := ProductGen.lang(lang_code) == "tr"
	var li := 1 if turkish_on else 0
	var noun := String(noun_pair(key)[li])
	var ws := words(key, lang_code)
	var w1 := String(ws[0]) if ws.size() > 0 else ""
	var w2 := String(ws[1]) if ws.size() > 1 else ""
	var e := _eval(key, varieties)
	var kind := "note"
	var options: Array = []
	if not e.notes.is_empty():
		options = [cfg().note_adjectives.get(String(e.notes[0]), ["", ""])]
	else:
		var prof := ProductGen.profile(e.taste)
		kind = "mild" if prof.is_empty() else "profile"
		options = cfg().adjectives.get("mild" if prof.is_empty() else String(prof[0]), [])
	var adjective := ""
	var repeat := false
	var start := (Hash.fnv1a31(key) >> 8) % maxi(options.size(), 1)
	for i in options.size():
		var cand := String(options[(start + i) % options.size()][li])
		if not _echoes(cand, [noun, w1, w2]):
			adjective = cand
			break
		repeat = true
	var head := tr_compound(noun) if turkish_on and w1 != "" else noun
	var max_len := int(Data.grammar().product_name_max)
	var cands := [
		ProductGen._join([adjective, w1, w2, head]) if w2 != "" else "",
		ProductGen._join([adjective, w1, head]),
		ProductGen._join([w1, head]),
		noun,
	]
	var pick := 3
	for i in cands.size():
		if cands[i] != "" and String(cands[i]).length() <= max_len:
			pick = i
			break
	return {"name": cands[pick], "adjective": adjective, "adjective_kind": kind, "feature": w2, "type": w1,
		"short": head, "repeat": repeat, "feature_long": w2 != "" and pick >= 1, "adjective_long": pick >= 2,
		"words": ws, "noun": noun, "notes": e.notes}


## A Turkish dish noun in its compound form after a word ("Turta" -> "Turtası", "Şerbet" -> "Şerbeti"): grammar.json's
## exceptions plus formula.json's.
static func tr_compound(noun: String) -> String:
	var ex: Dictionary = Data.grammar().get("tr", {}).get("compound_exceptions", {}).duplicate()
	ex.merge(cfg().get("tr_compound_exceptions", {}), true)
	return Turkish.compound(noun, ex)


## True when `word` shares its first 4 letters (Turkish lower case) with any of `others`.
static func _echoes(word: String, others: Array) -> bool:
	if word == "":
		return false
	var a := Turkish.lower_word(word).left(4)
	for o in others:
		if String(o) != "" and Turkish.lower_word(String(o)).left(4) == a:
			return true
	return false


# --- stats --------------------------------------------------------------------------------------------------------

## The rarest component (a product: its own rarity; nuts are common).
static func rarity(key: String, varieties: Dictionary) -> String:
	var best := "common"
	for comp: Dictionary in parse(key).components:
		var r := "common"
		match String(comp.kind):
			"fresh":
				r = String(varieties.get(String(comp.id), {}).get("rarity", "common"))
			"product":
				r = ProductGen.rarity(String(comp.id), varieties)
		if int(ProductGen.RARITY_RANK.get(r, 0)) > int(ProductGen.RARITY_RANK[best]):
			best = r
	return best


## floor((fresh and nut sell prices * method value_mult + products' 1-star values) * star_mult[quality + harmony])
## + add-in bonuses, at most cap(), never under floor_value() (the grocer price of what went in: inventing never
## loses money; the floor wins where the two cross).
static func value(key: String, varieties: Dictionary, quality: int) -> int:
	var p := parse(key)
	var c := cfg()
	var fresh := 0
	var products := 0
	for comp: Dictionary in p.components:
		var use := int(c.use.get(comp.kind, 1))
		match String(comp.kind):
			"product":
				products += ProductGen.value(String(comp.id), varieties, 1) * use
			"nut":
				fresh += Economy.sell_price(State.nut(String(comp.id), use), varieties)
			_:
				fresh += Economy.sell_price(State.fresh(String(comp.id), use, 1), varieties)
	var stars := ProductGen.total_stars(quality, harmony(key, varieties))
	var m: Dictionary = c.method.get(p.method, {})
	var base := float(fresh) * float(m.get("value_mult", 1.0)) + float(products)
	var raw := floori(base * float(Data.rules().value.star_mult[stars]) + 0.000001) + addin_bonus(p.addins)
	return maxi(mini(raw, cap(key, stars)), floor_value(key, varieties))


## Highest value an invention of this method can have at `stars` (quality + harmony): what the method's best base
## recipe is worth at those stars, times cap_mult, + add-in bonuses.
static func cap(key: String, stars: int) -> int:
	var p := parse(key)
	var star_mult := float(Data.rules().value.star_mult[clampi(stars, 0, 5)])
	return floori(float(cfg().cap_mult) * float(best_base_value(String(p.method))) * star_mult + 0.000001) \
		+ addin_bonus(p.addins)


## Grocer price of everything a cook takes: fresh and nut units at their sell price, products at product_ratio of
## their 1-star value.
static func floor_value(key: String, varieties: Dictionary) -> int:
	var c := cfg()
	var ratio := float(Data.shop().sell.product_ratio)
	var out := 0
	for comp: Dictionary in parse(key).components:
		var use := int(c.use.get(comp.kind, 1))
		match String(comp.kind):
			"product":
				out += floori(ProductGen.value(String(comp.id), varieties, 1) * ratio) * use
			"nut":
				out += Economy.sell_price(State.nut(String(comp.id), use), varieties)
			_:
				out += Economy.sell_price(State.fresh(String(comp.id), use, 1), varieties)
	return out


static func addin_bonus(addins: Array) -> int:
	var bonus: Dictionary = Data.rules().value.addin_bonus
	var out := 0
	for a in addins:
		out += int(bonus.get(String(Data.addins().get(String(a), {}).get("kind", "")), 0))
	return out


## Best base value among the method's base recipes (family recipes left out): stove 100 (syrup), counter 50, press 40,
## board 60.
static func best_base_value(method: String) -> int:
	var best := 0
	var all := Data.recipes()
	for id: String in all:
		var r: Dictionary = all[id]
		if String(r.get("method", "")) == method and not r.has("family_of"):
			best = maxi(best, ProductGen.base_value(r))
	return best


static func vessel(key: String) -> String:
	var p := parse(key)
	var v: Variant = cfg().method.get(p.method, {}).get("vessel", "jam_jar")
	if typeof(v) == TYPE_DICTIONARY:
		return String(v.get(dominant_group(key), "jam_jar"))
	return String(v)


## Pantry zone: the method's ("bread" vessels "dry"), then the first zone rule the taste meets. Uses the types' base
## tastes (no varieties), so the pantry can ask with the item alone.
static func zone(key: String) -> String:
	if vessel(key) == "bread":
		return "dry"
	var z := String(cfg().method.get(parse(key).method, {}).get("zone", "room"))
	var t := taste(key, {})
	for rule: Dictionary in cfg().zone_rules:
		if int(t[ProductGen.AXES.find(String(rule.axis))]) >= int(rule.min):
			return String(rule.zone)
	return z


static func wait_days(key: String) -> int:
	return int(cfg().method.get(parse(key).method, {}).get("wait_days", 0))


static func shelf_days(key: String) -> int:
	return int(cfg().method.get(parse(key).method, {}).get("shelf_days", -1))


# --- look ---------------------------------------------------------------------------------------------------------

## The same dict as ProductGen.describe (recipe "fx"), plus "formula": true, "method" and "notes".
static func describe(key: String, varieties: Dictionary) -> Dictionary:
	var e := _eval(key, varieties)
	var t: Array = e.taste
	var v := vessel(key)
	return {
		"key": key, "recipe": RECIPE, "name": product_name(key, varieties), "taste": t,
		"profile": ProductGen.profile(t), "profile_label": ProductGen.profile_label(t),
		"harmony": maxi(ProductGen.harmony(t) + int(e.harmony_mod), 0), "rarity": rarity(key, varieties),
		"zone": zone(key), "vessel": v, "size": ProductGen.vessel_size(v), "appearance": appearance(key, varieties),
		"family": false, "formula": true, "method": String(parse(key).method), "notes": e.notes,
	}


## Fill: the heaviest component's three tones with one of them swapped for the second component's tone at the same
## place (palette colours only, never blended), dark to light; chunks from the last fresh component; label, motif
## and lid drawn from appearance_seed in ProductGen's order.
static func appearance(key: String, varieties: Dictionary) -> Dictionary:
	var seed_v := ProductGen.appearance_seed(key)
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var p := parse(key)
	var comps := ranked(key)
	var first_addin := String(p.addins[0]) if not p.addins.is_empty() else ""
	var fill: Array = component_tones(comps[0], varieties, first_addin) if not comps.is_empty() else ProductGen.PLAIN_FILL.duplicate()
	if comps.size() >= 2:
		var other := component_tones(comps[1], varieties, "")
		var at := r.randi_range(0, 2)
		fill[at] = other[at]
		fill.sort_custom(func(a: String, b: String) -> bool:
			var la := Color.html(a).get_luminance()
			var lb := Color.html(b).get_luminance()
			return la < lb or (la == lb and a < b))
	var chunk := "none"
	for comp: Dictionary in comps:
		if comp.kind == "fresh":
			chunk = String(Data.ingredients().get(State.type_of_variety(String(comp.id)), {}).get("texture", "none"))
	var tint := String(Data.addins().get(first_addin, {}).get("tint", "")) if first_addin != "" else ""
	var label_shape := r.randi_range(0, 2)
	var label_color := String(ProductGen.LABEL_COLORS[r.randi_range(0, ProductGen.LABEL_COLORS.size() - 1)])
	var motif := String(ProductGen.MOTIFS[r.randi_range(0, ProductGen.MOTIFS.size() - 1)])
	var lid := "metal" if r.randf() < 0.5 else "cloth"
	var lids: Array = ProductGen.METAL_LIDS if lid == "metal" else ProductGen.CLOTH_LIDS
	var lid_colors: Array = lids[r.randi_range(0, lids.size() - 1)].duplicate()
	return {
		"vessel": vessel(key), "fill": fill, "chunk": chunk, "chunk_seed": seed_v, "label_shape": label_shape,
		"label_color": label_color, "motif": motif, "lid": lid, "lid_colors": lid_colors, "tint": tint,
	}


## Three palette tones of a component: a variety's ramp window (ProductGen.fill_tones), a nut's ramp, a product's fill.
static func component_tones(comp: Dictionary, varieties: Dictionary, addin_id: String = "") -> Array:
	match String(comp.kind):
		"fresh":
			return ProductGen.fill_tones(_variety(String(comp.id), varieties), addin_id)
		"nut":
			var ramp: Variant = Data.ingredients().get(String(comp.id), {}).get("ramp")
			return ramp.slice(1, 4) if typeof(ramp) == TYPE_ARRAY and ramp.size() >= 4 else ProductGen.PLAIN_FILL.duplicate()
		"product":
			var k := String(comp.id)
			if is_formula(k):
				return appearance(k, varieties).fill.duplicate()
			var vs: Array = ProductGen.parse_key(k).varieties
			if vs.is_empty():
				return ProductGen.PLAIN_FILL.duplicate()
			return ProductGen.fill_tones(_variety(String(vs[0]), varieties), String(ProductGen.parse_key(k).addin))
	return ProductGen.PLAIN_FILL.duplicate()
