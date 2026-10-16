class_name Garden
extends RefCounted
## SIM-04 · Garden actions (spec §5, §7.5, §8.1). Trees refill rules.garden.tree_refill_days after shaking.
## Shaken fruit and harvests go into the bag. Random draws use stream "garden" with the current day and a sub per spot.


static func shake_tree(state: Dictionary, tree_index: int) -> Dictionary:
	var trees: Array = state.garden.trees
	if tree_index < 0 or tree_index >= trees.size():
		return {"ok": false, "reason": "UI_NOT_AVAILABLE", "items": []}
	var tree: Dictionary = trees[tree_index]
	if not bool(tree.fruit):
		return {"ok": false, "reason": "UI_TREE_EMPTY", "items": []}
	var rules := Data.rules()
	if bag_free(state) < int(rules.bag.shake_needs_free):
		return {"ok": false, "reason": "UI_BAG_FULL", "items": []}
	if not Economy.spend(state, "shake_tree"):
		return {"ok": false, "reason": "UI_TIRED", "items": []}
	var y: Array = rules.forage.tree_yield
	var r := Seeds.rng(int(state.save_seed), "garden", int(state.day), "tree%d" % tree_index)
	var item := _crop_item(tree.type, tree.variety, r.randi_range(int(y[0]), int(y[1])))
	tree.fruit = false
	tree.refill_in = int(rules.garden.tree_refill_days)
	add_to_bag(state, item)
	return {"ok": true, "reason": "", "items": [item], "energy": int(state.energy)}


## Plants a "seed_<crop>" from the cupboard. The bed gets a common or uncommon variety; fertilizer saves days.
## {"ok", "reason", "variety", "days_left"}
static func plant(state: Dictionary, bed_index: int, crop: String, use_fertilizer: bool = false) -> Dictionary:
	var beds: Array = state.garden.beds
	var seeds: Dictionary = Data.shop().seeds
	if bed_index < 0 or bed_index >= beds.size() or not seeds.has(crop) or int(seeds[crop].get("priority", 0)) > Economy.MAX_PRIORITY:
		return {"ok": false, "reason": "UI_NOT_AVAILABLE"}
	if String(beds[bed_index].crop) != "":
		return {"ok": false, "reason": "UI_BED_BUSY"}
	var seed_id := "seed_" + crop
	if int(state.cupboard.get(seed_id, 0)) < 1:
		return {"ok": false, "reason": "UI_NO_SEED"}
	if use_fertilizer and int(state.garden.fertilizer) < 1:
		return {"ok": false, "reason": "UI_NO_FERTILIZER"}
	if not Economy.spend(state, "bed_plant"):
		return {"ok": false, "reason": "UI_TIRED"}
	state.cupboard[seed_id] = int(state.cupboard[seed_id]) - 1
	var days := int(seeds[crop].grow_days)
	if use_fertilizer:
		state.garden.fertilizer = int(state.garden.fertilizer) - 1
		days = maxi(1, days - int(Data.rules().garden.fertilizer_days_saved))
	var r := Seeds.rng(int(state.save_seed), "garden", int(state.day), "bed%d" % bed_index)
	var variety := State._garden_variety(state.varieties, crop, r)
	beds[bed_index] = {"crop": crop, "variety": variety, "days_left": days, "fertilized": use_fertilizer}
	return {"ok": true, "reason": "", "variety": variety, "days_left": days}


## Picks a ready bed: shop.seeds[crop].yield fresh items into the bag, the bed empties. {"ok", "reason", "items"}
static func harvest(state: Dictionary, bed_index: int) -> Dictionary:
	var beds: Array = state.garden.beds
	if bed_index < 0 or bed_index >= beds.size():
		return {"ok": false, "reason": "UI_NOT_AVAILABLE", "items": []}
	var bed: Dictionary = beds[bed_index]
	if String(bed.crop) == "" or int(bed.days_left) > 0:
		return {"ok": false, "reason": "UI_NOT_READY", "items": []}
	var n := int(Data.shop().seeds.get(bed.crop, {}).get("yield", 1))
	if bag_free(state) < n:
		return {"ok": false, "reason": "UI_BAG_FULL", "items": []}
	if not Economy.spend(state, "bed_harvest"):
		return {"ok": false, "reason": "UI_TIRED", "items": []}
	var item := _crop_item(bed.crop, bed.variety, n)
	beds[bed_index] = {"crop": "", "variety": "", "days_left": 0, "fertilized": false}
	add_to_bag(state, item)
	return {"ok": true, "reason": "", "items": [item], "energy": int(state.energy)}


## Free bag space in items (capacity grows with the P1 bag upgrade).
static func bag_free(state: Dictionary) -> int:
	var cap := int(Data.rules().bag.capacity)
	var level := int(state.upgrades.get("bag", 0))
	if level > 0:
		cap = int(Data.shop().upgrades.bag.capacity[level - 1])
	return cap - Forage.bag_count(state)


## Adds an item to the bag, topping up equal stacks (same variety + days_left, or same nut type) to rules.stack.
static func add_to_bag(state: Dictionary, item: Dictionary) -> void:
	var stack: Dictionary = Data.rules().stack
	var cap := int(stack.nut_max) if item.kind == "nut" else int(stack.fresh_max)
	var left := int(item.count)
	for b in state.bag:
		if left <= 0:
			break
		if b.kind != item.kind or int(b.count) >= cap:
			continue
		var same: bool = (b.kind == "nut" and b.type == item.type) or \
			(b.kind == "fresh" and b.variety == item.variety and int(b.days_left) == int(item.days_left))
		if same:
			var put := mini(cap - int(b.count), left)
			b.count = int(b.count) + put
			left -= put
	while left > 0:
		var part := item.duplicate(true)
		part.count = mini(cap, left)
		left -= int(part.count)
		state.bag.append(part)


## Fresh item of a garden variety, or a nut stack for nut trees (walnut).
static func _crop_item(type: String, variety: String, count: int) -> Dictionary:
	var ing: Dictionary = Data.ingredients()[type]
	if ing.group == "nut":
		return State.nut(type, count)
	return State.fresh(variety, count, int(ing.shelf_days))
