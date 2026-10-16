class_name Forage
extends RefCounted
## SIM-02 · Foraging actions (spec §4, §7.1). Mutate state, return a result dict {"ok", "reason", "items", "energy"}.
## Today's progress lives in state.wild_today[biome] = {"collected": [pickup ids], "shaken": [tree ids]}.
## Result: "items" = what went into the bag, "energy" = energy left, "cost" = energy spent, "new" = variety ids found
## for the first time. Fail reasons: UI_BAG_FULL, UI_TIRED, UI_NOTHING_LEFT (already taken or unknown id).
## Ids may come back from JSON as floats; they are compared as ints.


## The map without today's collected pickups; shaken trees get "shaken": true.
static func visible_map(state: Dictionary, map: Dictionary) -> Dictionary:
	if map.is_empty():
		return {}
	var today := _today(state, map.biome)
	var out := map.duplicate()
	var picks: Array = []
	for p in map.pickups:
		if not _has_id(today.collected, int(p.id)):
			picks.append(p)
	out.pickups = picks
	var trees: Array = []
	for t in map.fruit_trees:
		var tc: Dictionary = t.duplicate()
		tc.shaken = _has_id(today.shaken, int(t.id))
		trees.append(tc)
	out.fruit_trees = trees
	return out


static func shake_tree(state: Dictionary, map: Dictionary, tree_id: int) -> Dictionary:
	var tree := _find(map.get("fruit_trees", []), tree_id)
	if tree.is_empty():
		return _fail("UI_NOTHING_LEFT", state)
	var today := _today(state, map.biome)
	if _has_id(today.shaken, tree_id):
		return _fail("UI_NOTHING_LEFT", state)
	if _free(state) < int(Data.rules().bag.shake_needs_free):
		return _fail("UI_BAG_FULL", state)
	var cost := _spend(state, "shake_tree")
	if cost < 0:
		return _fail("UI_TIRED", state)
	var count := int(tree.get("yield", 0))
	if count <= 0:
		var yr: Array = Data.rules().forage.tree_yield
		count = Seeds.rng(int(state.save_seed), "wild:" + str(map.biome), int(state.day), "shake:%d" % tree_id) \
			.randi_range(int(yr[0]), int(yr[1]))
	today.shaken.append(tree_id)
	return _gain(state, _make_item(tree.type, tree.variety, count), cost)


static func pick(state: Dictionary, map: Dictionary, pickup_id: int) -> Dictionary:
	var p := _find(map.get("pickups", []), pickup_id)
	if p.is_empty():
		return _fail("UI_NOTHING_LEFT", state)
	var today := _today(state, map.biome)
	if _has_id(today.collected, pickup_id):
		return _fail("UI_NOTHING_LEFT", state)
	if p.kind == "hive":
		return _take_honey(state, today, pickup_id)
	var fr: Dictionary = Data.rules().forage
	var bush: bool = p.kind == "bush"
	var count := int(fr.bush_yield) if bush else int(fr.ground_yield)
	if _free(state) < count:
		return _fail("UI_BAG_FULL", state)
	var cost := _spend(state, "pick_bush" if bush else "pick_ground")
	if cost < 0:
		return _fail("UI_TIRED", state)
	today.collected.append(pickup_id)
	return _gain(state, _make_item(p.type, p.variety, count), cost)


## Items in the bag (sum of stack counts; capacity is rules.bag.capacity items).
static func bag_count(state: Dictionary) -> int:
	var n := 0
	for item in state.get("bag", []):
		n += int(item.get("count", 1))
	return n


## Called when Granny enters the house: bag -> inbox, merging equal stacks.
static func empty_bag_to_inbox(state: Dictionary) -> void:
	if not state.has("inbox"):
		state.inbox = []
	for item in state.get("bag", []):
		add_stacked(state.inbox, item)
	state.bag = []


## Adds `item` to an item list: fills matching stacks up to rules.stack (fresh: same variety + days_left;
## nut: same type), then appends new stacks. Products are appended as they are.
static func add_stacked(list: Array, item: Dictionary) -> void:
	if not item.has("count"):
		list.append(item.duplicate(true))
		return
	var cap := _stack_max(item)
	var left := int(item.count)
	for s in list:
		if left <= 0:
			break
		if not _same_stack(s, item):
			continue
		var room := cap - int(s.count)
		if room <= 0:
			continue
		var add := mini(room, left)
		s.count = int(s.count) + add
		left -= add
	while left > 0:
		var part := item.duplicate(true)
		part.count = mini(cap, left)
		left -= int(part.count)
		list.append(part)


# ---------- helpers ----------

## BIOMES: a wild bee hive (pickup kind "hive") gives rules.biomes.bee_hive.honey honey straight to the cupboard (an
## add-in, spec §6.1), so it needs no bag room; it costs a bush pick. Result item {"kind": "addin", "id", "count"}.
static func _take_honey(state: Dictionary, today: Dictionary, pickup_id: int) -> Dictionary:
	var cost := _spend(state, "pick_bush")
	if cost < 0:
		return _fail("UI_TIRED", state)
	today.collected.append(pickup_id)
	var n := int(WildGen.biome_table("bee_hive").get("honey", 2))
	if not state.has("cupboard"):
		state.cupboard = {}
	state.cupboard.honey = int(state.cupboard.get("honey", 0)) + n
	if state.has("stats"):
		state.stats.items_foraged = int(state.stats.get("items_foraged", 0)) + n
	return {"ok": true, "reason": "", "items": [{"kind": "addin", "id": "honey", "count": n}], "energy": int(state.energy),
		"cost": cost, "new": []}


static func _today(state: Dictionary, biome: String) -> Dictionary:
	if not state.has("wild_today") or typeof(state.wild_today) != TYPE_DICTIONARY:
		state.wild_today = {}
	if not state.wild_today.has(biome):
		state.wild_today[biome] = {"collected": [], "shaken": []}
	var t: Dictionary = state.wild_today[biome]
	if not t.has("collected"):
		t.collected = []
	if not t.has("shaken"):
		t.shaken = []
	return t


static func _has_id(list: Array, id: int) -> bool:
	for v in list:
		if int(v) == id:
			return true
	return false


static func _find(list: Array, id: int) -> Dictionary:
	if id >= 0 and id < list.size() and int(list[id].id) == id:
		return list[id]
	for e in list:
		if int(e.id) == id:
			return e
	return {}


static func _free(state: Dictionary) -> int:
	return bag_capacity(state) - bag_count(state)


## Items the bag holds: rules.bag.capacity, or the shop.json "bag" capacity of the level bought (UPGRADES: 40, 50).
static func bag_capacity(state: Dictionary) -> int:
	var cap := int(Data.rules().bag.capacity)
	var level := int(state.get("upgrades", {}).get("bag", 0))
	var caps: Array = Data.shop().upgrades.bag.capacity
	if level > 0:
		cap = int(caps[mini(level, caps.size()) - 1])
	return cap


## Energy through Economy.spend; while Economy is a stub (cost 0) the rules.json cost is taken here.
## Returns the energy spent, or -1 if there is not enough.
static func _spend(state: Dictionary, action: String) -> int:
	var cost := Economy.energy_cost(action)
	if cost > 0:
		return cost if Economy.spend(state, action) else -1
	cost = int(Data.rules().energy.costs.get(action, 0))
	if int(state.energy) < cost:
		return -1
	state.energy = int(state.energy) - cost
	return cost


static func _make_item(type: String, variety: String, count: int) -> Dictionary:
	var row: Dictionary = Data.ingredients().get(type, {})
	if row.get("group", "") == "nut":
		return State.nut(type, count)
	var days: Variant = row.get("shelf_days")
	return State.fresh(variety, count, int(days) if days != null else -1)


static func _gain(state: Dictionary, item: Dictionary, cost: int) -> Dictionary:
	if not state.has("bag"):
		state.bag = []
	add_stacked(state.bag, item)
	var fresh_ids: Array = []
	if item.kind == "fresh":
		if not state.has("found_varieties"):
			state.found_varieties = []
		if not state.found_varieties.has(item.variety):
			state.found_varieties.append(item.variety)
			fresh_ids.append(item.variety)
	if state.has("stats"):
		state.stats.items_foraged = int(state.stats.get("items_foraged", 0)) + int(item.count)
	return {"ok": true, "reason": "", "items": [item], "energy": int(state.energy), "cost": cost, "new": fresh_ids}


static func _fail(reason: String, state: Dictionary) -> Dictionary:
	return {"ok": false, "reason": reason, "items": [], "energy": int(state.get("energy", 0)), "cost": 0, "new": []}


static func _stack_max(item: Dictionary) -> int:
	var st: Dictionary = Data.rules().stack
	return int(st.nut_max) if item.kind == "nut" else int(st.fresh_max)


static func _same_stack(a: Dictionary, b: Dictionary) -> bool:
	if a.get("kind", "") != b.kind:
		return false
	match b.kind:
		"fresh":
			return a.variety == b.variety and int(a.days_left) == int(b.days_left)
		"nut":
			return a.type == b.type
	return false
