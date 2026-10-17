class_name State
extends RefCounted
## Save model helpers (tech-spec §4). The state is one Dictionary; GameState holds the live copy.
## Items: fresh {"kind":"fresh","variety","count","days_left","nights"} · nut {"kind":"nut","type","count"}
##        product {"kind":"product","key","q","wait_left","days_left"}  (days_left -1 = never spoils)
## Item refs: {"where": "bag"|"inbox"|"pantry", "index": int}. Pantry entries are {"item", "x", "y", "rot"}.

const VERSION := 1


static func new_game(save_seed: int) -> Dictionary:
	var rules := Data.rules()
	var start: Dictionary = rules.start
	var varieties := VarietyGen.generate_all(save_seed, 0)
	var s := {
		"version": VERSION,
		"save_seed": save_seed,
		"day": 1,
		"energy": int(rules.energy.base),
		"energy_max": int(rules.energy.base),
		"coins": int(start.coins),
		"weather": "sunny",
		"varieties": varieties,
		"found_varieties": [],
		"species_seen": {},  # SPECIES-GEN: species id -> day Granny first met it (old saves: get("species_seen", {}))
		"garden": {"trees": [], "beds": [], "compost": 0, "fertilizer": 0},
		"bag": [],
		"inbox": [],
		"pantry": {"rows_extra": 0, "items": []},
		"cupboard": {},
		"book": {"variants": {}},
		"orders": [],
		"next_order_id": 1,
		"friendship": {},
		"wild_today": {},
		"upgrades": {"pantry_row": 0},
		"flags": {"tutorial": 0, "completed": false},
		"stats": {"jars_made": 0, "coins_earned": 0, "orders_done": 0, "items_foraged": 0},
	}
	for k in start.cupboard:
		s.cupboard[k] = int(start.cupboard[k])
	var r := Seeds.rng(save_seed, "garden", 0)
	for t in rules.garden.trees:
		s.garden.trees.append({"type": t.type, "variety": _garden_variety(varieties, t.type, r), "fruit": true, "refill_in": 0})
	for i in int(rules.garden.beds):
		s.garden.beds.append({"crop": "", "variety": "", "days_left": 0, "fertilized": false})
	var bi := 0
	for b in start.beds:
		s.garden.beds[bi] = {"crop": b.crop, "variety": _garden_variety(varieties, b.crop, r), "days_left": int(b.days_left), "fertilized": false}
		bi += 1
	for npc_id in Data.ids_up_to("npcs", 0):
		if npc_id != "grandkids":
			s.friendship[npc_id] = 0
	var fo: Dictionary = start.first_order
	s.orders.append({"id": 0, "npc": fo.npc, "recipe": "", "axes": fo.axes.duplicate(), "min_stars": int(fo.min_stars),
		"made_day": 1, "expires_day": 1 + int(rules.orders.expire_days)})
	Orders.refill(s)
	return s


## A common or uncommon variety of `type` (garden plants are never rare). "" for types without varieties.
static func _garden_variety(varieties: Dictionary, type: String, r: RandomNumberGenerator) -> String:
	var ids: Array = []
	for id in varieties:
		if varieties[id].type == type and varieties[id].rarity != "rare":
			ids.append(id)
	if ids.is_empty():
		return ""
	ids.sort()
	return ids[r.randi_range(0, ids.size() - 1)]


static func fresh(variety_id: String, count: int, days_left: int) -> Dictionary:
	return {"kind": "fresh", "variety": variety_id, "count": count, "days_left": days_left, "nights": 0}


static func nut(type: String, count: int) -> Dictionary:
	return {"kind": "nut", "type": type, "count": count}


static func product(key: String, quality: int, wait_left: int, days_left: int = -1) -> Dictionary:
	return {"kind": "product", "key": key, "q": quality, "wait_left": wait_left, "days_left": days_left}


## "crabapple_3" -> "crabapple"
static func type_of_variety(variety_id: String) -> String:
	var parts := variety_id.rsplit("_", true, 1)
	return parts[0]


## Ingredient type for fresh items, nut type for nuts, recipe id for products.
static func item_type(item: Dictionary) -> String:
	match item.kind:
		"fresh":
			return type_of_variety(item.variety)
		"nut":
			return item.type
		"product":
			return item.key.split("|")[0]
	return ""


static func get_item(state: Dictionary, ref: Dictionary) -> Dictionary:
	match ref.where:
		"bag":
			return state.bag[ref.index]
		"inbox":
			return state.inbox[ref.index]
		"pantry":
			return state.pantry.items[ref.index].item
	return {}


## Removes the referenced item (or `count` of a stack) and returns what was taken.
static func take(state: Dictionary, ref: Dictionary, count: int = -1) -> Dictionary:
	var item := get_item(state, ref)
	if item.is_empty():
		return {}
	if count > 0 and item.has("count") and int(item.count) > count:
		item.count = int(item.count) - count
		var part := item.duplicate(true)
		part.count = count
		return part
	match ref.where:
		"bag":
			state.bag.remove_at(ref.index)
		"inbox":
			state.inbox.remove_at(ref.index)
		"pantry":
			state.pantry.items.remove_at(ref.index)
	return item
