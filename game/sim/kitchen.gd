class_name Kitchen
extends RefCounted
## SIM-01 · Cooking rules (spec §6.3, §7.2). Fresh inputs come from inbox first, then pantry; bases from cupboard;
## nut add-ins from inbox/pantry nut stacks, shop add-ins from cupboard.
## Same-variety rule: every main slot takes only `main_variety`, the chutney vegetable slot only `second_variety`.
## Reasons: UI_KITCHEN_WRONG (recipe/variety/add-in does not fit), UI_KITCHEN_SAME_VARIETY (enough of the type, not of
## one variety), UI_KITCHEN_MISSING (see "missing": {variety_id | nut type | cupboard id: count short}), UI_TIRED.

const R_WRONG := "UI_KITCHEN_WRONG"
const R_MISSING := "UI_KITCHEN_MISSING"
const R_SAME := "UI_KITCHEN_SAME_VARIETY"
const R_TIRED := "UI_TIRED"


## {"ok": bool, "reason": i18n key ("" when ok), "missing": {id: count}}
static func check(state: Dictionary, recipe_id: String, main_variety: String, second_variety: String, addin_id: String) -> Dictionary:
	var plan := _plan(state, recipe_id, main_variety, second_variety, addin_id)
	return {"ok": plan.ok, "reason": plan.reason, "missing": plan.missing}


## Consumes inputs and energy, puts the product in the inbox, updates book and stats.
## {"ok": bool, "item": product item, "desc": ProductGen.describe(), "is_new": bool}
static func cook(state: Dictionary, recipe_id: String, main_variety: String, second_variety: String, addin_id: String, quality: int) -> Dictionary:
	var plan := _plan(state, recipe_id, main_variety, second_variety, addin_id)
	if not plan.ok:
		return {"ok": false, "reason": plan.reason, "missing": plan.missing}
	if not _spend_energy(state, plan.action):
		return {"ok": false, "reason": R_TIRED, "missing": {}}
	_consume(state, plan)
	var recipe: Dictionary = Data.recipes()[recipe_id]
	var key := ProductGen.make_key(recipe_id, plan.varieties, addin_id)
	var q := clampi(quality, 1, 3)
	var item := State.product(key, q, int(recipe.get("wait_days", 0)), int(recipe.get("shelf_days", -1)))
	state.inbox.append(item)
	var desc := ProductGen.describe(key, state.varieties)
	var stars := ProductGen.total_stars(q, int(desc.harmony))
	var book: Dictionary = state.book.variants
	var is_new := not book.has(key)
	if is_new:
		book[key] = {"best_q": q, "best_stars": stars, "count": 1, "first_day": int(state.day)}
	else:
		var e: Dictionary = book[key]
		e.best_q = maxi(int(e.best_q), q)
		e.best_stars = maxi(int(e.best_stars), stars)
		e.count = int(e.count) + 1
	state.stats.jars_made = int(state.stats.jars_made) + 1
	return {"ok": true, "item": item, "desc": desc, "is_new": is_new}


## Energy of a cooking method. Falls back to rules.energy.costs while Economy (SIM-04) returns 0.
static func energy_cost(action: String) -> int:
	var c := Economy.energy_cost(action)
	if c > 0:
		return c
	return int(Data.rules().energy.costs.get(action, 0))


## Works out what a cook would take. {"ok","reason","missing","takes": [{where, index, count}],
## "cupboard": {id: count}, "varieties": [ids for the key], "action": method}
static func _plan(state: Dictionary, recipe_id: String, main_variety: String, second_variety: String, addin_id: String) -> Dictionary:
	var out := {"ok": false, "reason": "", "missing": {}, "takes": [], "cupboard": {}, "varieties": [], "action": ""}
	var recipes := Data.recipes()
	if not recipes.has(recipe_id):
		out.reason = R_WRONG
		return out
	var recipe: Dictionary = recipes[recipe_id]
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
		var need := int(slot.count)
		var got := _gather(state, slot, vid, need)
		out.takes.append_array(got.takes)
		if int(got.have) < need:
			missing[vid] = need - int(got.have)
			if not slot.has("recipe") and _count_type(state, State.type_of_variety(vid)) >= need:
				same_hint = true
	var cup_need: Dictionary = {}
	var base: Dictionary = recipe.get("base", {})
	for id in base:
		cup_need[id] = int(cup_need.get(id, 0)) + int(base[id])
	if addin_id != "":
		var addins := Data.addins()
		if not addins.has(addin_id):
			out.reason = R_WRONG
			return out
		if addins[addin_id].kind == "nut":
			var got := _gather(state, {"nut": addin_id}, addin_id, 1)
			out.takes.append_array(got.takes)
			if int(got.have) < 1:
				missing[addin_id] = 1
		else:
			cup_need[addin_id] = int(cup_need.get(addin_id, 0)) + 1
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
