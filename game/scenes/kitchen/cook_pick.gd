extends RefCounted
## JURY-STOVE · What the cook panel picks on its own (presentation, not a rule): when a station opens, the first recipe
## the player can cook right now, its slots filled with the best varieties in stock, a variant the book does not have
## yet first ("New!"). Kitchen.check_n always gives the verdict; this only chooses what to ask it about.
## Pure and autoload-free (game/tests/test_cook_pick.gd). Ranking of one fill: enough of each slot for `mult` pots,
## then not in the book, then the rarer variety, the higher value estimate, the bigger stack, the id.

const SLOTS := ["main", "second"]
const RARITY := {"common": 0, "uncommon": 1, "rare": 2}
const EST_Q := 2  ## quality stars a value estimate assumes (the middle of 1..3)


## A recipe's slot spec ("main" / "second"); null when it has none (bread, jam's second).
static func spec(recipe_id: String, which: String) -> Variant:
	var s: Variant = Data.recipes().get(recipe_id, {}).get(which)
	return s if typeof(s) == TYPE_DICTIONARY else null


## Fresh units per variety id in the inbox and the pantry.
static func fresh_stock(d: Dictionary) -> Dictionary:
	var out := {}
	var items: Array = d.get("inbox", []).duplicate()
	for e: Dictionary in d.get("pantry", {}).get("items", []):
		items.append(e.item)
	for item: Dictionary in items:
		if String(item.get("kind", "")) == "fresh":
			out[item.variety] = int(out.get(item.variety, 0)) + int(item.count)
	return out


## Units per variety a slot can draw from: matured products of its recipe (syrup's juices) or fresh stacks.
static func slot_stock(d: Dictionary, s: Variant) -> Dictionary:
	if s == null:
		return {}
	if s.has("recipe"):
		return Kitchen.product_stock(d, String(s.recipe))
	return fresh_stock(d)


## Slot routing: does variety `vid` belong in slot spec `s`? (`stock`: the slot's stock when the caller has it.)
static func fits(d: Dictionary, s: Variant, vid: String, stock: Variant = null) -> bool:
	if s == null or vid == "":
		return false
	if s.has("recipe"):
		return (stock if stock is Dictionary else slot_stock(d, s)).has(vid)
	var v: Dictionary = d.get("varieties", {}).get(vid, {})
	var type := String(v.get("type", State.type_of_variety(vid)))
	if s.has("types"):
		return s.types.has(type)
	return s.has("groups") and s.groups.has(String(Data.ingredients().get(type, {}).get("group", "")))


## The add-in a recipe opens with: its fixed one (family recipes), else none.
static func default_addin(recipe_id: String) -> String:
	var fixed: Variant = Kitchen.fixed_addin(recipe_id)
	return String(fixed) if fixed != null else ""


## Every way to fill `recipe_id`'s slots from stock, best first:
## [{"main", "second", "key", "new": bool, "enough": bool, "have": {"main": n, "second": n}}].
## `only` pins a slot to one variety ({"main": vid}). A slot nothing fits stays "" (never enough). A recipe without
## slots (bread) has one fill with both "".
static func fills(d: Dictionary, recipe_id: String, addin: String, mult: int, only: Dictionary = {}) -> Array:
	var stocks := {}
	var lists := {}
	for which: String in SLOTS:
		var s: Variant = spec(recipe_id, which)
		var ids: Array = []
		if s != null:
			var stock := slot_stock(d, s)
			stocks[which] = stock
			var pin := String(only.get(which, ""))
			for vid: String in stock:
				if int(stock[vid]) > 0 and fits(d, s, vid, stock) and (pin == "" or vid == pin):
					ids.append(vid)
		lists[which] = ids if not ids.is_empty() else [""]
	var book: Dictionary = d.get("book", {}).get("variants", {})
	var vars: Dictionary = d.get("varieties", {})
	var out: Array = []
	for m: String in lists.main:
		for s2: String in lists.second:
			if m != "" and m == s2:
				continue
			var have := {}
			var enough := true
			for which: String in SLOTS:
				var s: Variant = spec(recipe_id, which)
				if s == null:
					continue
				var vid := m if which == "main" else s2
				have[which] = int(stocks[which].get(vid, 0)) if vid != "" else 0
				enough = enough and vid != "" and int(have[which]) >= int(s.count) * mult
			var key := Kitchen.product_key(recipe_id, m, s2, addin)
			var filled := not ((spec(recipe_id, "main") != null and m == "") or (spec(recipe_id, "second") != null and s2 == ""))
			out.append({"main": m, "second": s2, "key": key, "new": not book.has(key), "enough": enough, "have": have,
				"rank": maxi(_rarity(vars, m), _rarity(vars, s2)),
				"value": ProductGen.value(key, vars, EST_Q) if filled else 0})
	out.sort_custom(_better)
	return out


## The best fill of `recipe_id` ({"main", "second"}, "" where nothing fits).
static func best_picks(d: Dictionary, recipe_id: String, addin: String, mult: int, only: Dictionary = {}) -> Dictionary:
	var all := fills(d, recipe_id, addin, mult, only)
	if all.is_empty():
		return {"main": "", "second": ""}
	return {"main": String(all[0].main), "second": String(all[0].second)}


## What a station opens on, from its tab `recipes` (in tab order): the first that can cook now (or only lacks
## energy) and makes a variant not in the book; else the first that can cook; else the first tab.
## {"recipe", "main", "second", "addin", "mult"}; {} without recipes. `mult` is the pots wanted (x2 falls back to x1
## when no recipe can cook twice).
static func best_recipe(d: Dictionary, recipes: Array, mult: int = 1) -> Dictionary:
	if recipes.is_empty():
		return {}
	var tries: Array = [mult] if mult <= 1 else [mult, 1]
	var first := {}
	for m: int in tries:
		var ready := {}
		for r: String in recipes:
			var pots := mini(m, Kitchen.max_mult(d, r))
			var addin := default_addin(r)
			var p := best_picks(d, r, addin, pots)
			var pick := {"recipe": r, "main": p.main, "second": p.second, "addin": addin, "mult": pots}
			if first.is_empty():
				first = pick
			var c := Kitchen.check_n(d, r, p.main, p.second, addin, pots)
			if not (bool(c.ok) or String(c.reason) == Kitchen.R_TIRED):
				continue
			if not d.get("book", {}).get("variants", {}).has(Kitchen.product_key(r, p.main, p.second, addin)):
				return pick
			if ready.is_empty():
				ready = pick
		if not ready.is_empty():
			return ready
	return first


static func _rarity(vars: Dictionary, vid: String) -> int:
	if vid == "":
		return -1
	return int(RARITY.get(String(vars.get(vid, {}).get("rarity", "common")), 0))


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if a.enough != b.enough:
		return a.enough
	if a.new != b.new:
		return a.new
	if a.rank != b.rank:
		return a.rank > b.rank
	if a.value != b.value:
		return a.value > b.value
	var ha := _least(a.have)
	var hb := _least(b.have)
	if ha != hb:
		return ha > hb
	if a.main != b.main:
		return String(a.main) < String(b.main)
	return String(a.second) < String(b.second)


static func _least(have: Dictionary) -> int:
	var n := 1 << 30
	for k in have:
		n = mini(n, int(have[k]))
	return n
