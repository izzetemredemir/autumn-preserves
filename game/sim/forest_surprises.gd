class_name ForestSurprises
extends RefCounted
## FUN-FOREST · Little surprises in the forest (pure rules; the scene only draws and animates them).
## `plan(map, save_seed, day, varieties)` -> the day's surprises, deterministic per (seed, day), from its own stream
## "forest_surprise" (sub "cells" / "rewards"), so the map and its pickup lists (WildGen, then SpeciesGen) stay
## identical: the plan only reads the map and never changes it. Call it on the final map (after add_pickups).
## Entry: {"id", "kind": "bush" | "pile" | "sparkle", "x", "y", "reward"}. Cells are walkable, flood-fill reachable
## from the entrance, plain ground (grass, leaves, dirt), off every tree and pickup, not beside one, off the special
## place and away from the entrance. None of them blocks a tile, so no path can be closed by one.
## Reward: {"t": "critter", "critter": "squirrel" | "hedgehog"} | {"t": "item", "variety", "count"} |
## {"t": "nut", "type", "count"} | {"t": "coins", "n"} | {"t": "none"}. Only the forest has surprises.
## Consumed ones live in state.wild_today[biome].surprises (ids; reset every morning with wild_today).
## `collect(state, entry)` applies the reward: {"ok", "reason", "reward", "items", "new", "coins"}; a full bag
## (UI_BAG_FULL) leaves the surprise where it is.

const BIOME := "forest"
const BUSHES := [2, 3]
const PILES := [3, 5]
const SPARKLE_CHANCE := 0.7  ## at most one a day
const PILE_FIND_CHANCE := 0.4
const COIN_RANGE := [2, 5]
const ENTRANCE_D2 := 12
const BUSH_TABLE := {"critter": 5.0, "nut": 3.0, "species": 1.0, "rare": 1.0}
const NUTS := ["hazelnut", "chestnut", "walnut"]
const CRITTERS := ["squirrel", "hedgehog"]


static func plan(map: Dictionary, save_seed: int, day: int, varieties: Dictionary) -> Array:
	var out: Array = []
	if map.is_empty() or String(map.get("biome", "")) != BIOME:
		return out
	var cells := _cells(map, save_seed, day)
	var r := Seeds.rng(save_seed, "forest_surprise", day, "rewards")
	var rare := _variety_pool(varieties, ["rare"], ["fruit", "mushroom"])
	var shrooms := _variety_pool(varieties, ["common", "uncommon"], ["mushroom"])
	var want: Array = []  # kind per entry, in a fixed order
	for i in r.randi_range(int(BUSHES[0]), int(BUSHES[1])):
		want.append("bush")
	for i in r.randi_range(int(PILES[0]), int(PILES[1])):
		want.append("pile")
	if r.randf() < SPARKLE_CHANCE:
		want.append("sparkle")
	var ci := 0
	var spread: Array[Vector2i] = []
	for kind: String in want:
		var c := Vector2i(-1, -1)
		while ci < cells.size():  # next cell that keeps its distance from the earlier surprises
			var cand: Vector2i = cells[ci]
			ci += 1
			if _far_enough(cand, spread):
				c = cand
				break
		if c.x < 0:
			break
		spread.append(c)
		var reward := {"t": "none"}
		match kind:
			"bush":
				reward = _bush_reward(r, save_seed, day, rare)
			"pile":
				reward = _pile_reward(r, shrooms)
			"sparkle":
				reward = _sparkle_reward(r, save_seed, day, rare)
		out.append({"id": out.size(), "kind": kind, "x": c.x, "y": c.y, "reward": reward})
	return out


## The ids of today's consumed surprises.
static func consumed(state: Dictionary) -> Array:
	var t: Dictionary = state.get("wild_today", {}).get(BIOME, {})
	return t.get("surprises", [])


static func is_consumed(state: Dictionary, id: int) -> bool:
	for v in consumed(state):
		if int(v) == id:
			return true
	return false


## Entries still there (not consumed today).
static func remaining(state: Dictionary, entries: Array) -> Array:
	var out: Array = []
	for e: Dictionary in entries:
		if not is_consumed(state, int(e.id)):
			out.append(e)
	return out


## True when the reward needs room in the bag (items and nuts).
static func needs_room(entry: Dictionary) -> bool:
	var t := String(entry.get("reward", {}).get("t", ""))
	return t == "item" or t == "nut"


## Takes the surprise: marks it consumed and puts its reward into the state. A full bag fails with UI_BAG_FULL and
## consumes nothing. Critters and empty piles just get consumed. Costs no energy.
static func collect(state: Dictionary, entry: Dictionary) -> Dictionary:
	var id := int(entry.get("id", -1))
	var rw: Dictionary = entry.get("reward", {"t": "none"})
	var res := {"ok": true, "reason": "", "reward": rw, "items": [], "new": [], "coins": 0}
	if id < 0 or is_consumed(state, id):
		res.ok = false
		res.reason = "UI_NOTHING_LEFT"
		return res
	var item := _item_of(state, rw)
	if not item.is_empty():
		if Forage.bag_capacity(state) - Forage.bag_count(state) < int(item.count):
			res.ok = false
			res.reason = "UI_BAG_FULL"
			return res
		if not state.has("bag"):
			state.bag = []
		Forage.add_stacked(state.bag, item)
		res.items = [item]
		if item.kind == "fresh":
			if not state.has("found_varieties"):
				state.found_varieties = []
			if not state.found_varieties.has(item.variety):
				state.found_varieties.append(item.variety)
				res.new = [item.variety]
		if state.has("stats"):
			state.stats.items_foraged = int(state.stats.get("items_foraged", 0)) + int(item.count)
	elif String(rw.get("t", "")) == "coins":
		res.coins = int(rw.n)
		Economy.earn(state, int(rw.n))
	_today(state).surprises.append(id)
	return res


# ---------------------------------------------------------------- rewards

static func _bush_reward(r: RandomNumberGenerator, save_seed: int, day: int, rare: Array) -> Dictionary:
	var species := SpeciesGen.known(save_seed, day)
	var weights := [BUSH_TABLE.critter, BUSH_TABLE.nut, BUSH_TABLE.species if not species.is_empty() else 0.0,
		BUSH_TABLE.rare if not rare.is_empty() else 0.0]
	var pick := Seeds.pick_weighted(r, weights)
	var a := r.randi_range(0, 1000)  # always drawn: the table never shifts the later draws
	match pick:
		0:
			return {"t": "critter", "critter": CRITTERS[a % CRITTERS.size()]}
		1:
			return {"t": "nut", "type": NUTS[a % NUTS.size()], "count": 2 + a % 2}
		2:
			var sp: Dictionary = species[a % species.size()]
			return {"t": "item", "variety": SpeciesGen.variety_id(String(sp.id)), "count": 1, "species": String(sp.id)}
		_:
			return {"t": "item", "variety": String(rare[a % rare.size()]), "count": 1}


static func _pile_reward(r: RandomNumberGenerator, shrooms: Array) -> Dictionary:
	var roll := r.randf()
	var a := r.randi_range(0, 1000)
	var coins := r.randi_range(int(COIN_RANGE[0]), int(COIN_RANGE[1]))
	if roll >= PILE_FIND_CHANCE:
		return {"t": "none"}
	if roll < PILE_FIND_CHANCE * 0.5 and not shrooms.is_empty():
		return {"t": "item", "variety": String(shrooms[a % shrooms.size()]), "count": 1}
	return {"t": "coins", "n": coins}


## Half a rare variety (two of them), half the newest species (one); a rare one when no species is known yet.
static func _sparkle_reward(r: RandomNumberGenerator, save_seed: int, day: int, rare: Array) -> Dictionary:
	var roll := r.randf()
	var a := r.randi_range(0, 1000)
	var species := SpeciesGen.for_day(save_seed, day)
	if species.is_empty():
		species = SpeciesGen.known(save_seed, day).slice(-1)
	if roll < 0.5 and not rare.is_empty() or species.is_empty():
		if rare.is_empty():
			return {"t": "none"}
		return {"t": "item", "variety": String(rare[a % rare.size()]), "count": 2}
	var sp: Dictionary = species[a % species.size()]
	return {"t": "item", "variety": SpeciesGen.variety_id(String(sp.id)), "count": 2, "species": String(sp.id)}


## Sorted variety ids of the given rarities whose type belongs to one of `groups` (forest finds; no species).
static func _variety_pool(varieties: Dictionary, rarities: Array, groups: Array) -> Array:
	var ing := Data.ingredients()
	var out: Array = []
	for id: String in varieties:
		var v: Dictionary = varieties[id]
		var type := String(v.get("type", ""))
		if not rarities.has(String(v.get("rarity", ""))) or SpeciesGen.is_species(type):
			continue
		if groups.has(String(ing.get(type, {}).get("group", ""))):
			out.append(id)
	out.sort()
	return out


## The item a reward puts in the bag ({} for critters, coins and nothing).
static func _item_of(state: Dictionary, rw: Dictionary) -> Dictionary:
	match String(rw.get("t", "")):
		"nut":
			return State.nut(String(rw.type), int(rw.count))
		"item":
			var variety := String(rw.variety)
			var type := String(state.get("varieties", {}).get(variety, {}).get("type", ""))
			if type == "" and SpeciesGen.is_species(String(rw.get("species", ""))):
				type = String(rw.species)
			var days: Variant = Data.ingredients().get(type, {}).get("shelf_days")
			return State.fresh(variety, int(rw.count), int(days) if days != null else -1)
	return {}


# ---------------------------------------------------------------- cells

## Shuffled candidate cells (stream "forest_surprise", sub "cells").
static func _cells(map: Dictionary, save_seed: int, day: int) -> Array:
	var w := int(map.w)
	var h := int(map.h)
	var taken := {}
	for key in ["decor_trees", "fruit_trees", "pickups"]:
		for t in map.get(key, []):
			taken[Vector2i(int(t.x), int(t.y))] = true
	var sp_rect := Rect2i()
	var special: Dictionary = map.get("special", {})
	if special.has("x"):
		sp_rect = Rect2i(int(special.x), int(special.y), int(special.get("w", 1)), int(special.get("h", 1))).grow(1)
	var reach := SpeciesGen.reach_map(map)
	var entrance: Vector2i = map.entrance
	var cells: Array = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := Vector2i(x, y)
			var t := int(map.ground[y * w + x])
			if t != WildGen.T_GRASS and t != WildGen.T_LEAVES and t != WildGen.T_DIRT:
				continue
			if reach[y * w + x] != 1 or taken.has(c) or _beside(c, taken):
				continue
			if c.distance_squared_to(entrance) <= ENTRANCE_D2 or (sp_rect.size != Vector2i.ZERO and sp_rect.has_point(c)):
				continue
			cells.append(c)
	var r := Seeds.rng(save_seed, "forest_surprise", day, "cells")
	for i in range(cells.size() - 1, 0, -1):  # Fisher-Yates
		var j := r.randi_range(0, i)
		var tmp: Vector2i = cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	return cells


static func _beside(c: Vector2i, taken: Dictionary) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if taken.has(c + Vector2i(dx, dy)):
				return true
	return false


## At least 4 tiles from every earlier surprise.
static func _far_enough(c: Vector2i, others: Array[Vector2i]) -> bool:
	for o in others:
		if c.distance_squared_to(o) < 16:
			return false
	return true


static func _today(state: Dictionary) -> Dictionary:
	if not state.has("wild_today") or typeof(state.wild_today) != TYPE_DICTIONARY:
		state.wild_today = {}
	if not state.wild_today.has(BIOME):
		state.wild_today[BIOME] = {"collected": [], "shaken": []}
	var t: Dictionary = state.wild_today[BIOME]
	if not t.has("surprises"):
		t.surprises = []
	return t
