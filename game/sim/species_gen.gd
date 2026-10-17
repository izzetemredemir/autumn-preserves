class_name SpeciesGen
extends RefCounted
## SPECIES-GEN · New forest species every day, generated. Pure and stateless: everything follows from (save_seed, day)
## through new Seeds streams only ("species", "species_id", "species_wild"), so every existing stream, forest, demo
## seed and the festival save stay as they were (the festival simply knows the species of days 2-14).
##   for_day(save_seed, day): 0-2 species from day 2 (COUNT_ODDS: about 40 % none, 45 % one, 15 % two).
##   known(save_seed, day): every species of days 2..day, in day order. Names are unique within a save, so a day's
##   names depend on the days before it; known() is memoised per save seed (same inputs, same answer).
## A species is an ingredients.json-shaped row plus its own fields:
##   {"id": "sp_<hex>", "day", "group": "fruit"|"mushroom"|"vegetable", "sources", "shelf_days", "taste": [5 ints],
##    "ramp": [5 palette hex, dark -> light], "texture", "priority": 0, "display_name" (English, also the variety name),
##    "display_name_tr", "compound_tr" (the Turkish name is a compound: "Kor Eriği"), "rarity", "template" (IconLib),
##    "signature" (the taste axis pushed high), "sell" (grocer base per piece, the base types' scale), "species": true}
## sync(state) registers the known rows in Data (Data.ingredients() then holds them: recipes take them by group, the
## bag, pantry, shop and market see them; orders keep to base types since they read Data.ids_up_to) and adds one
## variety per species, "<id>_1", to state.varieties. add_pickups() puts today's species into a forest map.

const FIRST_DAY := 2
const COUNT_ODDS := [0.40, 0.45, 0.15]  ## none, one, two species on a day
const GROUPS := ["fruit", "mushroom", "vegetable"]
const GROUP_WEIGHTS := [45, 30, 25]
const RARITIES := ["common", "uncommon", "rare"]
const RARITY_WEIGHTS := [60, 30, 10]
const AXES := ["sweet", "sour", "spicy", "salty", "earthy"]
const NAME_MAX := 16  ## EN and TR: product names with a species then stay within grammar.product_name_max (28)
const NEW_DAYS := 3  ## the book tags a species "New" this many days after Granny first met it
const OLD_CHANCE := 0.25  ## an earlier species shows up again on a day (one pickup)
const TODAY_PICKUPS := [1, 3]  ## pickups of each of today's species

## Taste per group: [min, max] per axis before the signature axis is pushed; signature weights per axis.
const BASE_TASTE := {
	"fruit": [[1, 4], [1, 4], [0, 0], [0, 0], [0, 1]],
	"mushroom": [[0, 0], [0, 0], [0, 1], [0, 2], [3, 4]],
	"vegetable": [[0, 2], [0, 2], [0, 1], [0, 0], [1, 3]],
}
const SIGNATURE_WEIGHTS := {"fruit": [3, 3, 2, 1, 1], "mushroom": [2, 1, 2, 3, 2], "vegetable": [2, 2, 3, 1, 2]}
const SIGNATURE_VALUE := {"common": [5, 6], "uncommon": [6, 7], "rare": [7, 8]}
const SHELF := {"fruit": [2, 5], "mushroom": [2, 3], "vegetable": [3, 7]}
const TEXTURES := {"fruit": ["seeds", "slices"], "mushroom": ["caps"], "vegetable": ["rings", "strips", "shreds", "chunks"]}
const SOURCES := {"fruit": ["forest_bush"], "mushroom": ["forest_ground"], "vegetable": ["forest_ground"]}

## Colour chains, dark -> light (luminance rises), from the families of tools/palettes/autumn_ramps.json (palette
## colours only). A ramp is 5 tones of one chain (shifted window) or two compatible chains recombined.
const CHAINS := {
	"ember": ["3d1f29", "62272c", "a22512", "c94d2e", "e19064", "f2d9c5"],
	"plum": ["23282a", "3d1f29", "62272c", "81746a", "b9a697", "f2d9c5"],
	"amber": ["50361e", "83571e", "b66813", "c58845", "e5bd7f", "f2d9c5"],
	"gold": ["50361e", "83571e", "9b8039", "b1a13d", "dbcc83", "f2d9c5"],
	"olive": ["314524", "53612e", "747c37", "b1a13d", "c5bf3f", "dbcc83"],
	"teal": ["2e3f3f", "275e4c", "4e7664", "738c7a", "b4b3a0", "f2d9c5"],
	"slate": ["23282a", "2e3f3f", "415c5d", "567c7d", "738c7a", "b4b3a0"],
	"bark": ["3d1f29", "50361e", "83571e", "c58845", "e5bd7f", "f2d9c5"],
	"stone": ["111010", "23282a", "49423d", "81746a", "b4b3a0", "f2d9c5"],
}
const GROUP_CHAINS := {
	"fruit": {"ember": 3, "plum": 2, "amber": 2, "gold": 1, "teal": 2, "slate": 1, "olive": 1},
	"mushroom": {"bark": 3, "amber": 2, "gold": 1, "stone": 2, "plum": 1, "ember": 1, "slate": 1},
	"vegetable": {"olive": 3, "teal": 2, "amber": 1, "ember": 2, "gold": 1, "plum": 1},
}
const CHAIN_PAIRS := {
	"ember": ["amber", "plum"], "plum": ["ember", "teal", "slate"], "amber": ["ember", "bark", "gold"],
	"gold": ["olive", "amber", "bark"], "olive": ["gold", "teal"], "teal": ["plum", "olive", "stone", "slate"],
	"slate": ["teal", "plum"], "bark": ["amber", "gold", "stone"], "stone": ["teal", "bark"],
}
const RECOMBINE_CHANCE := 0.35

## Name words. Prefix: [English, Turkish, Turkish compound (the noun takes -ı/-si: "Kor Eriği"; false: "Kadife Şapka")].
const PREFIXES := {
	"sweet": [["Honey", "Bal", true], ["Velvet", "Kadife", false], ["Sugar", "Şeker", true], ["Amber", "Kehribar", true],
		["Candle", "Mum", true], ["Treacle", "Pekmez", true]],
	"sour": [["Tart", "Mayhoş", false], ["Sharp", "Ekşi", false], ["Frost", "Kırağı", true], ["Brisk", "Keskin", false],
		["Crisp", "Gevrek", false]],
	"spicy": [["Ember", "Kor", true], ["Fire", "Ateş", true], ["Flame", "Alev", true], ["Fox", "Tilki", true],
		["Spark", "Kıvılcım", true]],
	"salty": [["Mill", "Köy", true], ["Salt", "Tuz", true], ["Shore", "Kıyı", true], ["Stone", "Taş", true],
		["Briny", "Tuzlu", false]],
	"earthy": [["Moss", "Yosun", true], ["Hollow", "Dere", true], ["Ridge", "Yamaç", true], ["Bark", "Kabuk", true],
		["Owl", "Baykuş", true], ["Burrow", "Oyuk", true]],
	"look": [["Lantern", "Fener", true], ["Golden", "Altın", false], ["Copper", "Bakır", false], ["Moon", "Ay", true],
		["Star", "Yıldız", true], ["Little", "Minik", false], ["Speckled", "Benekli", false], ["Sleepy", "Uykulu", false],
		["Misty", "Puslu", false]],
}
const SIGNATURE_PREFIX_CHANCE := 0.7
## Group nouns: [English, Turkish, IconLib template].
const NOUNS := {
	"fruit": [["Berry", "Yemiş", "fruit_bramble"], ["Plum", "Erik", "fruit_round"], ["Cherry", "Kiraz", "fruit_cluster"],
		["Haw", "Alıç", "fruit_cluster"], ["Drop", "Damla", "fruit_pear"], ["Bead", "Boncuk", "fruit_cluster"],
		["Fig", "İncir", "fruit_pear"], ["Globe", "Top", "fruit_round"]],
	"mushroom": [["Cap", "Şapka", "mushroom_cap"], ["Hood", "Başlık", "mushroom_tall"], ["Button", "Düğme", "mushroom_cap"],
		["Funnel", "Huni", "mushroom_funnel"], ["Bell", "Çan", "mushroom_tall"], ["Ear", "Kulak", "mushroom_fan"],
		["Fan", "Yelpaze", "mushroom_fan"], ["Cup", "Fincan", "mushroom_funnel"]],
	"vegetable": [["Root", "Kök", "veg_root"], ["Tuber", "Yumru", "veg_root"], ["Leaf", "Yaprak", "veg_leafy"],
		["Sprout", "Filiz", "veg_leafy"], ["Turnip", "Şalgam", "veg_round"], ["Gourd", "Kabak", "veg_round"],
		["Pod", "Bakla", "veg_pod"], ["Horn", "Boynuz", "veg_pod"]],
}
## Combinations that name a real plant or a known cultivar: never used.
## Nouns never repeat a base type name, so a species never reads like a variety ("Ember Apple").
const BANNED := ["Honey Berry", "Sugar Plum", "Golden Berry", "Moon Drop", "Honey Drop", "Fire Cherry", "Golden Root",
	"Star Fruit", "Golden Fig", "Honey Fig"]

static var _memo := {}  ## save_seed -> {"day": last day rolled, "list": [species], "en": {name: true}, "tr": {...}}


# ---------------------------------------------------------------- generation

## The species that appear on `day` (0-2; none before FIRST_DAY).
static func for_day(save_seed: int, day: int) -> Array:
	var out: Array = []
	for sp: Dictionary in known(save_seed, day):
		if int(sp.day) == day:
			out.append(sp)
	return out


## Every species of days FIRST_DAY..day, in day order (then roll order).
static func known(save_seed: int, day: int) -> Array:
	if day < FIRST_DAY:
		return []
	if not _memo.has(save_seed):
		_memo[save_seed] = {"day": FIRST_DAY - 1, "list": [], "en": {}, "tr": {}, "ids": {}}
	var m: Dictionary = _memo[save_seed]
	while int(m.day) < day:
		m.day = int(m.day) + 1
		(m.list as Array).append_array(_roll_day(save_seed, int(m.day), m))
	var out: Array = []
	for sp: Dictionary in m.list:
		if int(sp.day) > day:
			break
		out.append(sp)
	return out


## Drops the memo (tests: a second run must give the same species from scratch).
static func forget() -> void:
	_memo.clear()


## One day's species: the count from stream "species" (day), each species from its own sub-stream "k<n>".
static func _roll_day(save_seed: int, day: int, m: Dictionary) -> Array:
	var r := Seeds.rng(save_seed, "species", day)
	var n := Seeds.pick_weighted(r, COUNT_ODDS)
	var out: Array = []
	for k in n:
		var rs := Seeds.rng(save_seed, "species", day, "k%d" % k)
		var id := "sp_%x" % Seeds.seed_for(save_seed, "species_id", day, str(k))
		while m.ids.has(id):
			id += "b"
		m.ids[id] = true
		out.append(_roll(rs, id, day, m.en, m.tr))
	return out


static func _roll(r: RandomNumberGenerator, id: String, day: int, used_en: Dictionary, used_tr: Dictionary) -> Dictionary:
	var group: String = GROUPS[Seeds.pick_weighted(r, GROUP_WEIGHTS)]
	var rarity: String = RARITIES[Seeds.pick_weighted(r, RARITY_WEIGHTS)]
	var sig := Seeds.pick_weighted(r, SIGNATURE_WEIGHTS[group])
	var taste := [0, 0, 0, 0, 0]
	var base: Array = BASE_TASTE[group]
	for a in 5:
		taste[a] = r.randi_range(int(base[a][0]), int(base[a][1]))
	var sv: Array = SIGNATURE_VALUE[rarity]
	taste[sig] = clampi(r.randi_range(int(sv[0]), int(sv[1])), 0, 9)
	var shelf: Array = SHELF[group]
	var textures: Array = TEXTURES[group]
	var shelf_days := r.randi_range(int(shelf[0]), int(shelf[1]))
	var texture := String(textures[r.randi_range(0, textures.size() - 1)])
	var ramp := _ramp(r, group)
	var nm := _name(r, group, String(AXES[sig]), used_en, used_tr)
	used_en[nm.en] = true
	used_tr[nm.tr] = true
	return {
		"id": id, "day": day, "group": group, "sources": (SOURCES[group] as Array).duplicate(), "shelf_days": shelf_days,
		"taste": taste, "ramp": ramp, "texture": texture, "priority": 0, "display_name": nm.en,
		"display_name_tr": nm.tr, "compound_tr": nm.compound, "rarity": rarity, "template": nm.template,
		"signature": AXES[sig], "sell": int(Data.shop().get("sell", {}).get("fresh", {}).get(group, 3)), "species": true,
	}


## 5 palette tones, dark -> light: a window of one chain, or (RECOMBINE_CHANCE) the two darkest tones of one chain's
## window under the three lightest of a compatible chain's window, kept only when luminance still rises.
static func _ramp(r: RandomNumberGenerator, group: String) -> Array:
	var gc: Dictionary = GROUP_CHAINS[group]
	var names: Array = gc.keys()
	var a: String = names[Seeds.pick_weighted(r, gc.values())]
	var chain: Array = CHAINS[a]
	var start := r.randi_range(0, chain.size() - 5)
	var ramp: Array = chain.slice(start, start + 5)
	if r.randf() < RECOMBINE_CHANCE:
		var pairs: Array = CHAIN_PAIRS[a]
		var other: Array = CHAINS[pairs[r.randi_range(0, pairs.size() - 1)]]
		var s2 := r.randi_range(0, other.size() - 5)
		var mix: Array = ramp.slice(0, 2) + other.slice(s2 + 2, s2 + 5)
		if _rising(mix):
			ramp = mix
	return ramp


static func _rising(ramp: Array) -> bool:
	for i in range(1, ramp.size()):
		if String(ramp[i]) == String(ramp[i - 1]) or _lum(ramp[i]) < _lum(ramp[i - 1]):
			return false
	return true


static func _lum(hex: String) -> float:
	var c := Color.html(hex)
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## {"en", "tr", "compound", "template"}: a prefix that fits the signature axis (else a looks word) and a group noun,
## both names <= NAME_MAX and unused in the save; after 24 draws every combination in table order; last a numbered one.
static func _name(r: RandomNumberGenerator, group: String, sig: String, used_en: Dictionary, used_tr: Dictionary) -> Dictionary:
	var nouns: Array = NOUNS[group]
	for i in 24:
		var pool: Array = PREFIXES[sig] if r.randf() < SIGNATURE_PREFIX_CHANCE else PREFIXES.look
		var c := compose(pool[r.randi_range(0, pool.size() - 1)], nouns[r.randi_range(0, nouns.size() - 1)])
		if _free(c, used_en, used_tr):
			return c
	for key: String in [sig, "look", "sweet", "sour", "spicy", "salty", "earthy"]:
		for p: Array in PREFIXES[key]:
			for nn: Array in nouns:
				var c := compose(p, nn)
				if _free(c, used_en, used_tr):
					return c
	var last := compose(PREFIXES.look[0], nouns[0])
	var k := 2
	while used_en.has("%s %d" % [last.en, k]):
		k += 1
	return {"en": "%s %d" % [last.en, k], "tr": "%s %d" % [last.tr, k], "compound": last.compound, "template": last.template}


## English and Turkish name of a prefix row and a noun row ("Ember Plum" / "Kor Eriği", "Velvet Cap" / "Kadife Şapka").
static func compose(prefix: Array, noun: Array) -> Dictionary:
	var compound := bool(prefix[2])
	var noun_tr := String(noun[1])
	if compound:
		noun_tr = Turkish.compound(noun_tr, Data.grammar().get("tr", {}).get("compound_exceptions", {}))
	return {"en": "%s %s" % [prefix[0], noun[0]], "tr": "%s %s" % [prefix[1], noun_tr], "compound": compound,
		"template": String(noun[2])}


static func _free(c: Dictionary, used_en: Dictionary, used_tr: Dictionary) -> bool:
	var en := String(c.en)
	var tr_name := String(c.tr)
	return en.length() <= NAME_MAX and tr_name.length() <= NAME_MAX and not used_en.has(en) and not used_tr.has(tr_name) \
		and not BANNED.has(en)


# ---------------------------------------------------------------- the save

static func variety_id(species_id: String) -> String:
	return species_id + "_1"


## The one variety of a species: its name is the species name (English; Turkish through VarietyGen.display_name).
static func variety_of(sp: Dictionary) -> Dictionary:
	return {"id": variety_id(String(sp.id)), "type": String(sp.id), "name": String(sp.display_name),
		"rarity": String(sp.rarity), "tier": 0, "color_shift": 0, "taste_delta": [0, 0, 0, 0, 0], "size": "medium",
		"species": true}


## Registers every species known on the save's day in Data and adds the missing varieties to state.varieties.
## Idempotent; call it on load, at every new day and before a forest is made. Returns the variety ids it added.
static func sync(state: Dictionary) -> Array:
	var added: Array = []
	if not state.has("varieties"):
		return added
	var vs: Dictionary = state.varieties
	for sp: Dictionary in known(int(state.get("save_seed", 0)), int(state.get("day", 1))):
		register(sp)
		var vid := variety_id(String(sp.id))
		if not vs.has(vid):
			vs[vid] = variety_of(sp)
			added.append(vid)
	return added


static func register(sp: Dictionary) -> void:
	if not Data.generated().has(String(sp.id)):
		Data.register_generated(String(sp.id), sp)


## A generated species row (registered), or {} for any other type.
static func row(type: String) -> Dictionary:
	var r: Dictionary = Data.ingredients().get(type, {})
	return r if bool(r.get("species", false)) else {}


static func is_species(type: String) -> bool:
	return not row(type).is_empty()


## Granny meets a species: true the first time (state.species_seen[id] = day), false after or for other types.
static func mark_seen(state: Dictionary, type: String) -> bool:
	if not is_species(type):
		return false
	var seen: Dictionary = state.get("species_seen", {})
	if seen.has(type):
		return false
	seen[type] = int(state.get("day", 1))
	state["species_seen"] = seen
	return true


static func seen(state: Dictionary, type: String) -> bool:
	return state.get("species_seen", {}).has(type)


## Met in the last NEW_DAYS days: the book's "New" tag.
static func is_new(state: Dictionary, type: String) -> bool:
	var s: Dictionary = state.get("species_seen", {})
	return s.has(type) and int(state.get("day", 1)) - int(s[type]) < NEW_DAYS


## The species name in a language ("" = the current one).
static func display_name(sp: Dictionary, lang: String = "") -> String:
	return String(sp.get("display_name_tr" if ProductGen.lang(lang) == "tr" else "display_name", sp.get("id", "")))


# ---------------------------------------------------------------- the forest

## What the forest holds of the species on `day`: [{"species", "count"}], from stream "species_wild" (day): each of
## today's species TODAY_PICKUPS times, then each earlier species with OLD_CHANCE, once.
static func pickup_plan(save_seed: int, day: int) -> Array:
	var plan: Array = []
	if day < FIRST_DAY:
		return plan
	var r := Seeds.rng(save_seed, "species_wild", day)
	for sp: Dictionary in for_day(save_seed, day):
		plan.append({"species": sp, "count": r.randi_range(int(TODAY_PICKUPS[0]), int(TODAY_PICKUPS[1]))})
	for sp: Dictionary in known(save_seed, day - 1):
		if r.randf() < OLD_CHANCE:
			plan.append({"species": sp, "count": 1})
	return plan


## Appends the day's species pickups to a forest map (WildGen.generate output) in place, after every generated item,
## ids continuing from the last pickup: {"id", "x", "y", "kind": "bush" (fruit) | "ground", "type": species id,
## "variety": "<id>_1", "species": true}. Cells come shuffled from stream "species_wild" (sub "cells"): reachable,
## not water, stone or path, not at the entrance or in the special place, not next to another item; a bush also
## keeps every item and clearing reachable (map.solid is updated). Other biomes get none. Returns the number added.
static func add_pickups(map: Dictionary, save_seed: int, day: int) -> int:
	if map.is_empty() or String(map.get("biome", "")) != "forest":
		return 0
	var plan := pickup_plan(save_seed, day)
	if plan.is_empty():
		return 0
	var w := int(map.w)
	var h := int(map.h)
	var taken := {}
	for key in ["decor_trees", "fruit_trees", "pickups"]:
		for t in map.get(key, []):
			taken[Vector2i(int(t.x), int(t.y))] = true
	var r := Seeds.rng(save_seed, "species_wild", day, "cells")
	var cells: Array = []
	var entrance: Vector2i = map.entrance
	var sp_rect := Rect2i()
	var special: Dictionary = map.get("special", {})
	if special.has("x"):
		sp_rect = Rect2i(int(special.x), int(special.y), int(special.get("w", 1)), int(special.get("h", 1))).grow(1)
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			var t := int(map.ground[y * w + x])
			if t == WildGen.T_WATER or t == WildGen.T_STONE or t == WildGen.T_PATH or taken.has(c):
				continue
			if c.distance_squared_to(entrance) <= 8 or (sp_rect.size != Vector2i.ZERO and sp_rect.has_point(c)):
				continue
			cells.append(c)
	for i in range(cells.size() - 1, 0, -1):  # Fisher-Yates
		var j := r.randi_range(0, i)
		var tmp: Vector2i = cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	var reach := reach_map(map)
	var added := 0
	for entry: Dictionary in plan:
		var sp: Dictionary = entry.species
		var bush := String(sp.group) == "fruit"
		for n in int(entry.count):
			var c := _place(map, cells, taken, reach, bush)
			if c.x < 0:
				break
			taken[c] = true
			(map.pickups as Array).append({"id": (map.pickups as Array).size(), "x": c.x, "y": c.y,
				"kind": "bush" if bush else "ground", "type": String(sp.id), "variety": variety_id(String(sp.id)),
				"species": true})
			if bush:
				reach = reach_map(map)
			added += 1
	return added


## The first usable cell of `cells` (removed from it), or (-1, -1).
static func _place(map: Dictionary, cells: Array, taken: Dictionary, reach: PackedByteArray, bush: bool) -> Vector2i:
	var w := int(map.w)
	for i in cells.size():
		var c: Vector2i = cells[i]
		if taken.has(c) or _crowded(c, taken):
			continue
		var idx := c.y * w + c.x
		if not bush:
			if reach[idx] == 1:
				cells.remove_at(i)
				return c
			continue
		if reach[idx] != 1:
			continue
		var solid: PackedByteArray = map.solid
		solid[idx] = 1
		map["solid"] = solid
		map.pickups.append({"x": c.x, "y": c.y, "kind": "bush"})
		var ok := all_reachable(map, reach_map(map))
		map.pickups.pop_back()
		if ok:
			cells.remove_at(i)
			return c
		solid[idx] = 0
		map["solid"] = solid
	return Vector2i(-1, -1)


static func _crowded(c: Vector2i, taken: Dictionary) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if taken.has(c + Vector2i(dx, dy)):
				return true
	return false


## 1 = walkable (WildGen.is_walkable: not water, not solid) and reachable from the entrance, 4-neighbour flood.
static func reach_map(map: Dictionary) -> PackedByteArray:
	var w := int(map.w)
	var h := int(map.h)
	var reach := PackedByteArray()
	reach.resize(w * h)
	var e: Vector2i = map.entrance
	if not WildGen.is_walkable(map, e):
		return reach
	reach[e.y * w + e.x] = 1
	var queue: Array[Vector2i] = [e]
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb := p + d
			if nb.x < 0 or nb.y < 0 or nb.x >= w or nb.y >= h or reach[nb.y * w + nb.x] == 1:
				continue
			if WildGen.is_walkable(map, nb):
				reach[nb.y * w + nb.x] = 1
				queue.append(nb)
	return reach


## Every clearing centre, fruit tree and pickup can be reached (trees, bushes and hives from a 4-neighbour).
static func all_reachable(map: Dictionary, reach: PackedByteArray) -> bool:
	var w := int(map.w)
	for c: Vector2i in map.get("clearings", []):
		if reach[c.y * w + c.x] == 0:
			return false
	for key in ["fruit_trees", "pickups"]:
		for item in map.get(key, []):
			var x := int(item.x)
			var y := int(item.y)
			if String(item.get("kind", "tree")) == "ground":
				if reach[y * w + x] == 0:
					return false
				continue
			var ok := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx >= 0 and ny >= 0 and nx < w and ny < int(map.h) and reach[ny * w + nx] == 1:
					ok = true
					break
			if not ok:
				return false
	return true
