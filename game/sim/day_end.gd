class_name DayEnd
extends RefCounted
## SIM-04 · Night pipeline, the 11 steps of spec §9, in order. Mutates state; returns events
## [{"type": "matured"|"spoiled"|"grown"|"order_new"|"weather"|...,  ...}] for the morning summary.
##
## Zone rule (spec §7.4), through PantryRules: a waiting product counts down only where PantryRules.wait_counts
## (bag/inbox/wrong zone: no change); a fresh item in its correct zone adds a tick to item.nights and skips decay when
## PantryRules.fresh_decay_skips says so (every 3rd such night). Fallback: an empty board (stub) counts as correct zone.


static func run(state: Dictionary) -> Array:
	return run_with(state, {})


## run with optional seams: {"in_zone": Callable(entry) -> bool (pantry zone check for steps 1-2),
## "stars": Callable(state) -> int, "taste": Callable(key, varieties) -> Array (passed to Orders.refill_with)}.
static func run_with(state: Dictionary, seams: Dictionary) -> Array:
	var events: Array = []
	var b := PantryRules.board_of(state.pantry)
	var waits: Callable = seams.get("in_zone", Callable())
	var fresh_zone: Callable = waits
	if not waits.is_valid():
		if b.is_empty():
			waits = func(_e: Dictionary) -> bool: return true
			fresh_zone = waits
		else:
			waits = func(e: Dictionary) -> bool: return PantryRules.wait_counts(b, e)
			fresh_zone = func(e: Dictionary) -> bool: return PantryRules.in_correct_zone(b, e)
	# 1-2. Waiting products, then fresh decay and compost.
	events.append_array(tick_waiting(state, waits))
	events.append_array(tick_fresh(state, fresh_zone))
	# 3. Beds grow (fertilizer was applied at planting), trees refill.
	events.append_array(grow_garden(state))
	# 4. Pantry stars -> tomorrow's energy.
	var stars := int(seams.stars.call(state)) if seams.has("stars") else int(PantryRules.state_stars(state).get("stars", 0))
	var e: Dictionary = Data.rules().energy
	state.energy_max = int(e.base) + int(e.pantry_bonus_per_star) * stars
	state.energy = int(state.energy_max)
	events.append({"type": "energy", "stars": stars, "energy": int(state.energy)})
	# 5. New day: every seed from here on uses the new day number.
	state.day = int(state.day) + 1
	events.append({"type": "day", "day": int(state.day)})
	# 6. Weather.
	state.weather = weather_for(int(state.save_seed), int(state.day), String(state.weather))
	events.append({"type": "weather", "weather": state.weather})
	# 7. Orders: expired ones are replaced silently, empty slots fill, one stays satisfiable.
	for o in Orders.refill_with(state, seams.get("taste", Orders.product_taste())):
		events.append({"type": "order_new", "order": o})
	# 8. Letters and parcels (P1, stream "letters"): replies two days after a parcel, a new letter every 3-4 days.
	events.append_array(Letters.night(state))
	# 9. Market on every 7th day (P1, stream "market").
	# 10. Today's wild progress resets.
	state.wild_today = {}
	# 11. Autosave: the caller (GameState.end_day) saves; sim code never touches the disk.
	return events


## Step 1. Waiting pantry products count down where `waits`(entry) is true; 0 = matured. Bag and inbox never count.
static func tick_waiting(state: Dictionary, waits: Callable) -> Array:
	var events: Array = []
	for entry in state.pantry.items:
		var item: Dictionary = entry.item
		if item.kind == "product" and int(item.wait_left) > 0 and bool(waits.call(entry)):
			item.wait_left = int(item.wait_left) - 1
			if int(item.wait_left) == 0:
				events.append({"type": "matured", "key": item.key})
	return events


## Step 2. Fresh items lose a day; pantry items where `in_zone`(entry) add a night to item.nights and may skip
## (PantryRules.fresh_decay_skips). Spoiled items and expired short-lived products (days_left >= 0) go to compost;
## every compost_per_fertilizer makes fertilizer.
static func tick_fresh(state: Dictionary, in_zone: Callable) -> Array:
	var events: Array = []
	var spoiled := 0
	for where in ["bag", "inbox", "pantry"]:
		var list: Array = state.pantry.items if where == "pantry" else state[where]
		for i in range(list.size() - 1, -1, -1):
			var item: Dictionary = list[i].item if where == "pantry" else list[i]
			var counts_down := false
			if item.kind == "fresh":
				counts_down = true
				if where == "pantry" and bool(in_zone.call(list[i])):
					item.nights = int(item.get("nights", 0)) + 1
					counts_down = not PantryRules.fresh_decay_skips(list[i], int(item.nights))
			elif item.kind == "product" and int(item.get("days_left", -1)) >= 0:
				counts_down = true
			if not counts_down:
				continue
			item.days_left = int(item.days_left) - 1
			if int(item.days_left) <= 0:
				list.remove_at(i)
				var n := int(item.get("count", 1))
				spoiled += n
				events.append({"type": "spoiled", "item": item, "where": where})
	if spoiled > 0:
		var g: Dictionary = state.garden
		g.compost = int(g.compost) + spoiled
		var per := int(Data.rules().garden.compost_per_fertilizer)
		var made := floori(float(g.compost) / per)
		if made > 0:
			g.compost = int(g.compost) - made * per
			g.fertilizer = int(g.fertilizer) + made
			events.append({"type": "fertilizer", "made": made, "fertilizer": int(g.fertilizer)})
	return events


## Step 3. Beds grow a day; shaken trees refill when refill_in reaches 0.
static func grow_garden(state: Dictionary) -> Array:
	var events: Array = []
	var beds: Array = state.garden.beds
	for i in beds.size():
		var bed: Dictionary = beds[i]
		if String(bed.crop) != "" and int(bed.days_left) > 0:
			bed.days_left = int(bed.days_left) - 1
			if int(bed.days_left) == 0:
				events.append({"type": "grown", "bed": i, "crop": bed.crop})
	var trees: Array = state.garden.trees
	for i in trees.size():
		var tree: Dictionary = trees[i]
		if not bool(tree.fruit):
			tree.refill_in = int(tree.refill_in) - 1
			if int(tree.refill_in) <= 0:
				tree.refill_in = 0
				tree.fruit = true
				events.append({"type": "tree_refilled", "tree": i, "tree_type": tree.type})
	return events


## Weather of `day` from stream "weather" (spec §7.10). P0 table: sunny 75 / rainy 25. Two foggy days never follow.
static func weather_for(save_seed: int, day: int, prev: String = "", table: String = "p0") -> String:
	var w: Dictionary = Data.rules().weather[table]
	var ids: Array = w.keys()
	ids.sort()
	if prev == "foggy":
		ids.erase("foggy")
	var weights: Array = []
	for id in ids:
		weights.append(float(w[id]))
	var r := Seeds.rng(save_seed, "weather", day)
	return ids[Seeds.pick_weighted(r, weights)]
