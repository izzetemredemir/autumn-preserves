class_name Kitchen
extends RefCounted
## SIM-01 · Cooking rules (spec §6.3, §7.2). Fresh inputs come from inbox first, then pantry; bases from cupboard;
## nut add-ins from inbox/pantry nut stacks, shop add-ins from cupboard.
## Same-variety rule: every main slot takes only `main_variety`, the chutney vegetable slot only `second_variety`.
## Reasons: UI_KITCHEN_WRONG (recipe/variety/add-in does not fit), UI_KITCHEN_SAME_VARIETY (enough of the type, not of
## one variety), UI_KITCHEN_MISSING (see "missing": {variety_id | nut type | cupboard id: count short}), UI_TIRED.
## P1 (spec §6.3, §8.3): press and knead recipes need their station (Economy.unlocked "press" / "knead"); a recipe slot
## ({"recipe": "juice"}) takes matured products of that recipe whose main variety is `main_variety` (syrup); bread
## has no slot at all. A locked or unknown recipe answers UI_KITCHEN_WRONG.
## P1 mastery (spec §7.2): a variant cooked MASTERY_COOKS times with >= MASTERY_MIN_Q quality stars becomes Mastered
## (book.variants[key].mastered; "good" counts those cooks); batch_cook() then makes it without the mini-game, at its
## best quality, for the same energy. P1 big pot (spec §8.3): once "big_pot" is unlocked, stir_pot recipes may cook
## x2 (check_n / cook_n with mult 2): every input x2 -> 2 jars, one cook's energy, one mastery step.
## KITCHEN-P1C family recipes (spec §7.6): recipes.json rows with "family_of" (priority 2), one per id in
## Letters.FAMILY_RECIPES. Available once the grandchild's love unlocked them (state.letters.unlocked_recipes, love
## 3/6/10 in Letters.pack); one fixed ingredient type and "fixed_addin" (exactly that add-in, "" = none allowed).

const R_WRONG := "UI_KITCHEN_WRONG"
const R_MISSING := "UI_KITCHEN_MISSING"
const R_SAME := "UI_KITCHEN_SAME_VARIETY"
const R_TIRED := "UI_TIRED"
const R_NOT_MASTERED := "UI_BATCH_NOT_MASTERED"
const MASTERY_COOKS := 3
const MASTERY_MIN_Q := 2
const BIG_POT := "big_pot"
const BIG_POT_METHOD := "stir_pot"
## Cooking method -> unlock id of the station it needs (tech-spec §16). Stove and jar counter are always there.
const STATION_UNLOCK := {"press": "press", "knead": "knead"}


## {"ok": bool, "reason": i18n key ("" when ok), "missing": {id: count}}
static func check(state: Dictionary, recipe_id: String, main_variety: String, second_variety: String, addin_id: String) -> Dictionary:
	return check_n(state, recipe_id, main_variety, second_variety, addin_id, 1)


## check() for `mult` pots at once (1, or 2 with the big pot at the stove): every input x mult.
static func check_n(state: Dictionary, recipe_id: String, main_variety: String, second_variety: String, addin_id: String, mult: int) -> Dictionary:
	var plan := _plan(state, recipe_id, main_variety, second_variety, addin_id, mult)
	return {"ok": plan.ok, "reason": plan.reason, "missing": plan.missing}


## Consumes inputs and energy, puts the product in the inbox, updates book and stats.
## {"ok": bool, "item": product item, "desc": ProductGen.describe(), "is_new": bool} (+ the cook_n() extras)
static func cook(state: Dictionary, recipe_id: String, main_variety: String, second_variety: String, addin_id: String, quality: int) -> Dictionary:
	return cook_n(state, recipe_id, main_variety, second_variety, addin_id, quality, 1)


## cook() for `mult` pots: inputs x mult -> `mult` jars of one quality, one cook's energy, one mastery step.
## Adds "items" (every jar; "item" is the first), "quality" and "mastered" (true when this cook made it Mastered).
static func cook_n(state: Dictionary, recipe_id: String, main_variety: String, second_variety: String, addin_id: String, quality: int, mult: int) -> Dictionary:
	var plan := _plan(state, recipe_id, main_variety, second_variety, addin_id, mult)
	if not plan.ok:
		return {"ok": false, "reason": plan.reason, "missing": plan.missing}
	if not _spend_energy(state, plan.action):
		return {"ok": false, "reason": R_TIRED, "missing": {}}
	_consume(state, plan)
	var recipe: Dictionary = Data.recipes()[recipe_id]
	var key := ProductGen.make_key(recipe_id, plan.varieties, addin_id)
	var q := clampi(quality, 1, 3)
	var items: Array = []
	for i in int(plan.mult):
		var item := State.product(key, q, int(recipe.get("wait_days", 0)), int(recipe.get("shelf_days", -1)))
		state.inbox.append(item)
		items.append(item)
	var desc := ProductGen.describe(key, state.varieties)
	var stars := ProductGen.total_stars(q, int(desc.harmony))
	var book: Dictionary = state.book.variants
	var is_new := not book.has(key)
	var good := 1 if q >= MASTERY_MIN_Q else 0
	var was_mastered := false
	if is_new:
		book[key] = {"best_q": q, "best_stars": stars, "count": int(plan.mult), "first_day": int(state.day), "good": good}
	else:
		var e: Dictionary = book[key]
		was_mastered = entry_mastered(e)
		e.good = good_cooks(e) + good
		e.best_q = maxi(int(e.best_q), q)
		e.best_stars = maxi(int(e.best_stars), stars)
		e.count = int(e.count) + int(plan.mult)
	var entry: Dictionary = book[key]
	var mastered_now := not was_mastered and entry_mastered(entry)
	if mastered_now:
		entry.mastered = true
	state.stats.jars_made = int(state.stats.jars_made) + int(plan.mult)
	return {"ok": true, "item": items[0], "items": items, "desc": desc, "is_new": is_new, "quality": q, "mastered": mastered_now}


## Batch cook (spec §7.2): a Mastered variant without the mini-game, at its best quality, for the same energy.
## Same result as cook_n(); "reason" is UI_BATCH_NOT_MASTERED while the variant is not Mastered.
static func batch_cook(state: Dictionary, recipe_id: String, main_variety: String, second_variety: String, addin_id: String, mult: int = 1) -> Dictionary:
	var key := product_key(recipe_id, main_variety, second_variety, addin_id)
	if not is_mastered(state, key):
		return {"ok": false, "reason": R_NOT_MASTERED, "missing": {}}
	return cook_n(state, recipe_id, main_variety, second_variety, addin_id, best_quality(state, key), mult)


## Cooks with >= MASTERY_MIN_Q quality stars. Entries from before mastery lack "good": a best_q >= 2 proves one.
static func good_cooks(entry: Dictionary) -> int:
	return int(entry.get("good", 1 if int(entry.get("best_q", 0)) >= MASTERY_MIN_Q else 0))


static func entry_mastered(entry: Dictionary) -> bool:
	return bool(entry.get("mastered", false)) or good_cooks(entry) >= MASTERY_COOKS


## True when the book holds `key` as Mastered.
static func is_mastered(state: Dictionary, key: String) -> bool:
	return entry_mastered(state.get("book", {}).get("variants", {}).get(key, {}))


## Quality stars a batch cook gives: the best this variant was ever cooked with.
static func best_quality(state: Dictionary, key: String) -> int:
	return clampi(int(state.get("book", {}).get("variants", {}).get(key, {}).get("best_q", 1)), 1, 3)


## Pots one cook may make: 2 for stove (stir_pot) recipes once the big pot is bought, else 1.
static func max_mult(state: Dictionary, recipe_id: String) -> int:
	var recipe: Dictionary = Data.recipes().get(recipe_id, {})
	if String(recipe.get("method", "")) == BIG_POT_METHOD and Economy.unlocked(state, BIG_POT):
		return 2
	return 1


## True when the recipe can be cooked in this save: P0 always; P1 once its station is unlocked and, for a recipe
## slot (syrup), once the input recipe is available too.
static func available(state: Dictionary, recipe_id: String) -> bool:
	var recipes := Data.recipes()
	if not recipes.has(recipe_id):
		return false
	var recipe: Dictionary = recipes[recipe_id]
	if recipe.has("family_of") and not family_unlocked(state, recipe_id):
		return false
	if int(recipe.get("priority", 0)) <= 0:
		return true
	var gate := String(STATION_UNLOCK.get(String(recipe.method), ""))
	if gate != "" and not Economy.unlocked(state, gate):
		return false
	var main: Variant = recipe.get("main")
	if typeof(main) == TYPE_DICTIONARY and main.has("recipe") and String(main.recipe) != recipe_id:
		return available(state, String(main.recipe))
	return true


# --- family recipes (KITCHEN-P1C) ---------------------------------------------------------------------------------

## A family recipe row (Granny's recipes the grandkids send back)?
static func is_family(recipe_id: String) -> bool:
	return Data.recipes().get(recipe_id, {}).has("family_of")


## Every family recipe id in recipes.json order (Mia's three, then Leo's).
static func family_ids() -> Array:
	var out: Array = []
	var all := Data.recipes()
	for id: String in all:
		if all[id].has("family_of"):
			out.append(id)
	return out


## Has the grandchild's love unlocked it? Old saves without letters: no.
static func family_unlocked(state: Dictionary, recipe_id: String) -> bool:
	var l: Variant = state.get("letters")
	if typeof(l) != TYPE_DICTIONARY or typeof(l.get("unlocked_recipes")) != TYPE_ARRAY:
		return false
	return l.unlocked_recipes.has(recipe_id)


## Unlocked family recipes, in family_ids() order.
static func unlocked_family(state: Dictionary) -> Array:
	return family_ids().filter(func(id: String) -> bool: return family_unlocked(state, id))


## The grandchild whose love unlocks it ("" for other recipes).
static func family_kid(recipe_id: String) -> String:
	for kid: String in Letters.FAMILY_RECIPES:
		if Letters.FAMILY_RECIPES[kid].has(recipe_id):
			return kid
	return ""


## Love that unlocks it (Letters.LOVE_STEPS by its place in the kid's list; 0 for other recipes).
static func family_love(recipe_id: String) -> int:
	var kid := family_kid(recipe_id)
	if kid == "":
		return 0
	var i: int = Letters.FAMILY_RECIPES[kid].find(recipe_id)
	return int(Letters.LOVE_STEPS[mini(i, Letters.LOVE_STEPS.size() - 1)])


## The add-in a recipe insists on: null for free choice, "" for none at all, else the add-in id.
static func fixed_addin(recipe_id: String) -> Variant:
	var recipe: Dictionary = Data.recipes().get(recipe_id, {})
	if recipe.has("fixed_addin"):
		return String(recipe.fixed_addin)
	return null


## Available recipes cooked with `method`: P0 first, each priority in recipes.json order (stove: jam, butter,
## chutney, syrup; counter: pickles, brine, kraut; press: juice, vinegar; board: pie, bread), unlocked family last.
static func recipes_at(state: Dictionary, method: String) -> Array:
	var all := Data.recipes()
	var out: Array = []
	for prio in [0, 1, 2]:
		for id: String in all:
			var r: Dictionary = all[id]
			if int(r.get("priority", 0)) == prio and String(r.get("method", "")) == method and available(state, id):
				out.append(id)
	return out


## The product key cook() would make: only the slots the recipe has count (bread -> "bread|-").
static func product_key(recipe_id: String, main_variety: String, second_variety: String, addin_id: String) -> String:
	var recipe: Dictionary = Data.recipes().get(recipe_id, {})
	var vs: Array = []
	if typeof(recipe.get("main")) == TYPE_DICTIONARY:
		vs.append(main_variety)
	if typeof(recipe.get("second")) == TYPE_DICTIONARY:
		vs.append(second_variety)
	return ProductGen.make_key(recipe_id, vs, addin_id)


## Matured products of `recipe_id` in inbox + pantry, counted per main variety (the syrup slot's stock).
static func product_stock(state: Dictionary, recipe_id: String) -> Dictionary:
	var out := {}
	var items: Array = state.inbox.duplicate()
	for e: Dictionary in state.pantry.items:
		items.append(e.item)
	for item: Dictionary in items:
		if String(item.get("kind", "")) != "product" or int(item.get("wait_left", 0)) > 0:
			continue
		var p := ProductGen.parse_key(String(item.key))
		if p.recipe == recipe_id and not p.varieties.is_empty():
			var vid := String(p.varieties[0])
			out[vid] = int(out.get(vid, 0)) + int(item.get("count", 1))
	return out


## Energy of a cooking method. Falls back to rules.energy.costs while Economy (SIM-04) returns 0.
static func energy_cost(action: String) -> int:
	var c := Economy.energy_cost(action)
	if c > 0:
		return c
	return int(Data.rules().energy.costs.get(action, 0))


## Works out what a cook of `mult` pots would take. {"ok","reason","missing","takes": [{where, index, count}],
## "cupboard": {id: count}, "varieties": [ids for the key], "action": method, "mult": pots}
static func _plan(state: Dictionary, recipe_id: String, main_variety: String, second_variety: String, addin_id: String, mult: int = 1) -> Dictionary:
	var out := {"ok": false, "reason": "", "missing": {}, "takes": [], "cupboard": {}, "varieties": [], "action": "", "mult": mult}
	var recipes := Data.recipes()
	if not available(state, recipe_id) or mult < 1 or mult > max_mult(state, recipe_id):
		out.reason = R_WRONG
		return out
	var recipe: Dictionary = recipes[recipe_id]
	if recipe.has("fixed_addin") and addin_id != String(recipe.fixed_addin):
		out.reason = R_WRONG  # family recipes take exactly their own add-in
		return out
	out.action = String(recipe.method)
	var missing: Dictionary = out.missing
	var same_hint := false
	for slot_name in ["main", "second"]:
		var slot: Variant = recipe.get(slot_name)
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var vid := main_variety if slot_name == "main" else second_variety
		if not _fits(state, slot, vid):
			out.reason = R_WRONG
			return out
		out.varieties.append(vid)
		var need := int(slot.count) * mult
		var got := _gather(state, slot, vid, need)
		out.takes.append_array(got.takes)
		if int(got.have) < need:
			missing[vid] = need - int(got.have)
			if not slot.has("recipe") and _count_type(state, State.type_of_variety(vid)) >= need:
				same_hint = true
	var cup_need: Dictionary = {}
	var base: Dictionary = recipe.get("base", {})
	for id in base:
		cup_need[id] = int(cup_need.get(id, 0)) + int(base[id]) * mult
	if addin_id != "":
		var addins := Data.addins()
		if not addins.has(addin_id):
			out.reason = R_WRONG
			return out
		if addins[addin_id].kind == "nut":
			var got := _gather(state, {"nut": addin_id}, addin_id, mult)
			out.takes.append_array(got.takes)
			if int(got.have) < mult:
				missing[addin_id] = mult - int(got.have)
		else:
			cup_need[addin_id] = int(cup_need.get(addin_id, 0)) + mult
	for id in cup_need:
		var have := int(state.cupboard.get(id, 0))
		if have < int(cup_need[id]):
			missing[id] = int(cup_need[id]) - have
	out.cupboard = cup_need
	if not missing.is_empty():
		out.reason = R_SAME if same_hint else R_MISSING
		return out
	if int(state.energy) < energy_cost(out.action):
		out.reason = R_TIRED
		return out
	out.ok = true
	return out


## Does variety `vid` belong in this slot? Slots: {"groups": [..]} | {"types": [..]} | {"recipe": id} (+ "count").
static func _fits(state: Dictionary, slot: Dictionary, vid: String) -> bool:
	if vid == "" or not state.varieties.has(vid):
		return false
	var type := String(state.varieties[vid].type)
	if slot.has("types"):
		return slot.types.has(type)
	if slot.has("groups"):
		var ing: Dictionary = Data.ingredients().get(type, {})
		return slot.groups.has(ing.get("group", ""))
	return slot.has("recipe")


## Up to `need` matching units, inbox first (in order), then pantry. {"have": int, "takes": [{where, index, count}]}
static func _gather(state: Dictionary, slot: Dictionary, id: String, need: int) -> Dictionary:
	var takes: Array = []
	var have := 0
	var sources := [["inbox", state.inbox], ["pantry", state.pantry.items]]
	for src: Array in sources:
		var list: Array = src[1]
		for i in list.size():
			if have >= need:
				break
			var item: Dictionary = list[i].item if src[0] == "pantry" else list[i]
			if not _matches(slot, id, item):
				continue
			var n := mini(int(item.get("count", 1)), need - have)
			takes.append({"where": src[0], "index": i, "count": n})
			have += n
	return {"have": have, "takes": takes}


static func _matches(slot: Dictionary, id: String, item: Dictionary) -> bool:
	match String(item.get("kind", "")):
		"fresh":
			return not slot.has("recipe") and not slot.has("nut") and item.variety == id
		"nut":
			return slot.has("nut") and item.type == id
		"product":
			if not slot.has("recipe") or int(item.get("wait_left", 0)) > 0:
				return false
			var p := ProductGen.parse_key(String(item.key))
			return p.recipe == slot.recipe and not p.varieties.is_empty() and p.varieties[0] == id
	return false


## Fresh units of any variety of `type` in inbox and pantry (for the same-variety hint).
static func _count_type(state: Dictionary, type: String) -> int:
	var n := 0
	for item: Dictionary in state.inbox:
		if item.kind == "fresh" and State.type_of_variety(item.variety) == type:
			n += int(item.count)
	for e: Dictionary in state.pantry.items:
		var item: Dictionary = e.item
		if item.kind == "fresh" and State.type_of_variety(item.variety) == type:
			n += int(item.count)
	return n


static func _spend_energy(state: Dictionary, action: String) -> bool:
	if Economy.energy_cost(action) > 0:
		return Economy.spend(state, action)
	var cost := energy_cost(action)
	if int(state.energy) < cost:
		return false
	state.energy = int(state.energy) - cost
	return true


## Takes from the highest index down so removed stacks never shift a later take.
static func _consume(state: Dictionary, plan: Dictionary) -> void:
	var takes: Array = plan.takes.duplicate()
	takes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.index) > int(b.index))
	for t: Dictionary in takes:
		State.take(state, {"where": t.where, "index": int(t.index)}, int(t.count))
	for id in plan.cupboard:
		state.cupboard[id] = int(state.cupboard.get(id, 0)) - int(plan.cupboard[id])
