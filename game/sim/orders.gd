class_name Orders
extends RefCounted
## SIM-04 · Neighbour orders (spec §7.8). Order: {"id","npc","recipe" ("" = any),"axes": [axis ids],"min_stars","made_day","expires_day"}.
## Uses stream "orders" with the current day.
##
## Satisfiability is computed from "candidates": every unlocked recipe x common variety x (no add-in | shop add-in),
## with the taste from ProductGen.taste. The *_with / *_in variants take an injected taste function
## (key: String, varieties: Dictionary) -> Array or a ready candidate list, so tests do not depend on ProductGen.

const MAX_QUALITY := 3
const GUARANTEE_TRIES := 12


## Drops expired orders and fills empty slots (rules.orders.slots), keeping the "one satisfiable order" guarantee.
static func refill(state: Dictionary) -> void:
	refill_with(state, product_taste())


## refill with an injected taste function. Returns the orders it added.
static func refill_with(state: Dictionary, taste_fn: Callable) -> Array:
	var ro: Dictionary = Data.rules().orders
	var day := int(state.day)
	var kept: Array = []
	for o in state.orders:
		if int(o.expires_day) > day:
			kept.append(o)
	state.orders = kept
	if npc_pool(state).is_empty():
		return []
	var r := Seeds.rng(int(state.save_seed), "orders", day)
	var cands := candidates(state, taste_fn)
	var added: Array = []
	while state.orders.size() < int(ro.slots):
		var o := _generate(state, _pick_npc(state, r), r, cands)
		_commit(state, o)
		state.orders.append(o)
		added.append(o)
	for o in state.orders:
		if satisfiable_in(o, cands):
			return added
	# No order on the board can be met: swap the newest new order (else the oldest one) for a guaranteed one.
	var g := _guaranteed(state, r, cands)
	if g.is_empty():
		return added  # taste unknown (stubbed ProductGen): nothing can be proven satisfiable
	var slot: int = state.orders.size() - 1 if not added.is_empty() else _oldest(state.orders)
	if slot < 0:
		return added
	if not added.is_empty():
		added.pop_back()
	_commit(state, g)
	state.orders[slot] = g
	added.append(g)
	return added


static func generate(state: Dictionary, npc_id: String, r: RandomNumberGenerator) -> Dictionary:
	var o := _generate(state, npc_id, r, candidates(state, product_taste()))
	_commit(state, o)
	return o


## True when the product item satisfies the order (recipe, every axis >= threshold, quality + harmony >= min_stars).
static func matches(order: Dictionary, product_item: Dictionary, varieties: Dictionary) -> bool:
	if product_item.get("kind", "") != "product" or int(product_item.get("wait_left", 0)) > 0:
		return false
	var taste := ProductGen.taste(product_item.key, varieties)
	return meets(order, State.item_type(product_item), int(product_item.q), taste, ProductGen.harmony(taste))


## The order rule on plain values (the seam matches() and satisfiable() share).
static func meets(order: Dictionary, recipe_id: String, quality: int, taste: Array, harmony: int) -> bool:
	if String(order.get("recipe", "")) != "" and order.recipe != recipe_id:
		return false
	var threshold := int(Data.rules().orders.axis_threshold)
	for axis in order.axes:
		var i := ProductGen.AXES.find(axis)
		if i < 0 or i >= taste.size() or int(taste[i]) < threshold:
			return false
	return quality + harmony >= int(order.min_stars)


## Removes the item, pays value * reward_mult, adds friendship. {"ok","coins","hearts_before","hearts_after"}
static func fulfill(state: Dictionary, order_id: int, item_ref: Dictionary) -> Dictionary:
	var idx := -1
	for i in state.orders.size():
		if int(state.orders[i].id) == order_id:
			idx = i
	if idx < 0 or not Economy.valid_ref(state, item_ref):
		return {"ok": false, "reason": "UI_NOT_AVAILABLE"}
	var order: Dictionary = state.orders[idx]
	var item := State.get_item(state, item_ref)
	if not matches(order, item, state.varieties):
		return {"ok": false, "reason": "UI_ORDER_NO_MATCH"}
	var ro: Dictionary = Data.rules().orders
	var coins := floori(ProductGen.value(item.key, state.varieties, int(item.q)) * float(ro.reward_mult))
	var before := Economy.hearts(state, order.npc)
	State.take(state, item_ref)
	state.orders.remove_at(idx)
	Economy.earn(state, coins)
	Economy.add_friendship(state, order.npc, int(ro.friendship))
	state.stats.orders_done = int(state.stats.get("orders_done", 0)) + 1
	return {"ok": true, "reason": "", "coins": coins, "hearts_before": before, "hearts_after": Economy.hearts(state, order.npc)}


## Can this order be met with unlocked recipes, common varieties and shop add-ins?
static func satisfiable(state: Dictionary, order: Dictionary) -> bool:
	return satisfiable_in(order, candidates(state, product_taste()))


static func satisfiable_with(state: Dictionary, order: Dictionary, taste_fn: Callable) -> bool:
	return satisfiable_in(order, candidates(state, taste_fn))


static func satisfiable_in(order: Dictionary, cands: Array) -> bool:
	for c in cands:
		if meets(order, c.recipe, MAX_QUALITY, c.taste, c.harmony):
			return true
	return false


## Distinct {"recipe","key","taste","harmony"} reachable today: unlocked recipes x common varieties x
## (no add-in | shop add-ins). Keys come from ProductGen.make_key, tastes from taste_fn.
static func candidates(state: Dictionary, taste_fn: Callable) -> Array:
	var commons := _commons_by_type(state.varieties)
	var addins: Array = [""]
	for a in Data.ids_up_to("addins", 0):
		if Data.addins()[a].source == "shop":
			addins.append(a)
	var recipes := Data.recipes()
	var out: Array = []
	var seen := {}
	for rid in unlocked_recipes(state):
		var rec: Dictionary = recipes[rid]
		var mains := _slot_varieties(rec.get("main"), commons)
		var seconds: Array = [""]
		if rec.has("second"):
			seconds = _slot_varieties(rec.second, commons)
		for m in mains:
			for s in seconds:
				var vs: Array = [m] if s == "" else [m, s]
				for a in addins:
					var key := ProductGen.make_key(rid, vs, a)
					var taste: Array = taste_fn.call(key, state.varieties)
					var dedupe := "%s|%s" % [rid, str(taste)]
					if seen.has(dedupe):
						continue
					seen[dedupe] = true
					out.append({"recipe": rid, "key": key, "taste": taste, "harmony": ProductGen.harmony(taste)})
	return out


## Recipes the board may ask for (P0 set; P1 unlocks such as the press extend this).
static func unlocked_recipes(_state: Dictionary) -> Array:
	return Data.ids_up_to("recipes", 0)


## Neighbours who can post orders: day 1 only the first-order neighbour (spec §8.4), then everyone in state.friendship.
static func npc_pool(state: Dictionary) -> Array:
	if int(state.day) < 2:
		return [Data.rules().start.first_order.npc]
	var out: Array = []
	var npcs := Data.npcs()
	for id in state.friendship:
		if npcs.has(id) and npcs[id].has("likes"):
			out.append(id)
	out.sort()
	return out


static func _generate(state: Dictionary, npc_id: String, r: RandomNumberGenerator, cands: Array) -> Dictionary:
	var ro: Dictionary = Data.rules().orders
	var likes: Array = Data.npcs()[npc_id].likes
	var n := clampi(r.randi_range(int(ro.axes_count[0]), int(ro.axes_count[1])), 1, likes.size())
	var axes := _pick_n(likes, n, r)
	var min_stars := r.randi_range(int(ro.min_stars[0]), int(ro.min_stars[1]))
	var recipe := ""
	if r.randf() < float(ro.recipe_chance):
		# Only name a recipe that can actually meet the asked tastes.
		var ok: Array = []
		var probe := {"recipe": "", "axes": axes, "min_stars": min_stars}
		for rid in unlocked_recipes(state):
			probe.recipe = rid
			if satisfiable_in(probe, cands):
				ok.append(rid)
		if not ok.is_empty():
			recipe = ok[r.randi_range(0, ok.size() - 1)]
	var day := int(state.day)
	return {"id": -1, "npc": npc_id, "recipe": recipe, "axes": axes, "min_stars": min_stars,
		"made_day": day, "expires_day": day + int(ro.expire_days)}


## A satisfiable order: random tries first, then the easiest liked axis any candidate reaches. {} if none exists.
static func _guaranteed(state: Dictionary, r: RandomNumberGenerator, cands: Array) -> Dictionary:
	var pool := npc_pool(state)
	for t in GUARANTEE_TRIES:
		var o := _generate(state, pool[r.randi_range(0, pool.size() - 1)], r, cands)
		if satisfiable_in(o, cands):
			return o
	var ro: Dictionary = Data.rules().orders
	var day := int(state.day)
	var pairs: Array = []
	for npc_id in pool:
		for axis in Data.npcs()[npc_id].likes:
			var o := {"id": -1, "npc": npc_id, "recipe": "", "axes": [axis], "min_stars": int(ro.min_stars[0]),
				"made_day": day, "expires_day": day + int(ro.expire_days)}
			if satisfiable_in(o, cands):
				pairs.append(o)
	if pairs.is_empty():
		return {}
	return pairs[r.randi_range(0, pairs.size() - 1)]


static func _commit(state: Dictionary, order: Dictionary) -> void:
	order.id = int(state.next_order_id)
	state.next_order_id = int(state.next_order_id) + 1


## Prefers neighbours without an order on the board.
static func _pick_npc(state: Dictionary, r: RandomNumberGenerator) -> String:
	var pool := npc_pool(state)
	var free: Array = []
	for id in pool:
		var busy := false
		for o in state.orders:
			if o.npc == id:
				busy = true
		if not busy:
			free.append(id)
	var from: Array = free if not free.is_empty() else pool
	return from[r.randi_range(0, from.size() - 1)]


static func _oldest(orders: Array) -> int:
	var best := -1
	for i in orders.size():
		if best < 0 or int(orders[i].expires_day) < int(orders[best].expires_day):
			best = i
	return best


## n distinct entries of `arr`, drawn from r (never the global RNG).
static func _pick_n(arr: Array, n: int, r: RandomNumberGenerator) -> Array:
	var pool := arr.duplicate()
	var out: Array = []
	for i in mini(n, pool.size()):
		out.append(pool.pop_at(r.randi_range(0, pool.size() - 1)))
	return out


## {type: [sorted common variety ids]}
static func _commons_by_type(varieties: Dictionary) -> Dictionary:
	var out := {}
	for id in varieties:
		var v: Dictionary = varieties[id]
		if v.get("rarity", "") == "common":
			var t := String(v.get("type", State.type_of_variety(id)))
			if not out.has(t):
				out[t] = []
			out[t].append(id)
	for t in out:
		out[t].sort()
	return out


## Common varieties that fit a recipe slot ({"groups": [...]} or {"types": [...]}); other slot kinds give none.
static func _slot_varieties(slot: Variant, commons: Dictionary) -> Array:
	if typeof(slot) != TYPE_DICTIONARY:
		return []
	var ings := Data.ingredients()
	var types: Array = []
	if slot.has("types"):
		types = slot.types
	elif slot.has("groups"):
		for t in Data.ids_up_to("ingredients", 0):
			if ings[t].group in slot.groups:
				types.append(t)
	var out: Array = []
	for t in types:
		out.append_array(commons.get(t, []))
	return out


## ProductGen.taste as a Callable (the default taste function).
static func product_taste() -> Callable:
	return func(key: String, varieties: Dictionary) -> Array: return ProductGen.taste(key, varieties)
