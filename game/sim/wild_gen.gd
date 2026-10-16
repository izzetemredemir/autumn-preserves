class_name WildGen
extends RefCounted
## SIM-02 · Daily wild map (spec §7.1). Pure: same inputs -> same map. Seed: Seeds.seed_for(save_seed, "wild:<biome>", day).
## Map: {"seed", "biome", "w", "h", "ground": PackedByteArray (w*h, row-major, T_* ids),
##  "decor_trees": [{"x","y","kind"}], "fruit_trees": [{"id","x","y","type","variety"}],
##  "pickups": [{"id","x","y","kind": "bush"|"ground","type","variety"}], "special": {} or {"kind","x","y","w","h"},
##  "entrance": Vector2i, "clearings": [Vector2i], "steps": {} (P1: per-step layers for the Seed Lab)}
## Ids are stable indices assigned after validation. Coordinates are tiles (16 px).
## Extra fields (SIM-02): fruit_trees[i].yield (2-3 fruit when shaken), "special": true on special-place trees and
##  pickups, decor kind "maple"|"birch"|"oak", "solid": PackedByteArray (w*h, 1 = tree or bush stands there).
## Walkable = not water and not solid. Ground pickups are walkable; trees and bushes are used from a 4-neighbour tile.
## Each step draws from its own sub-stream (sub = step name); types and varieties come from sub "kinds", so weather
## and the varieties dict never move a tree, bush or pickup.

const T_GRASS := 0
const T_LEAVES := 1
const T_DIRT := 2
const T_WATER := 3
const T_PATH := 4
const T_STONE := 5

const DECOR_KINDS := ["maple", "birch", "oak"]
## Type weight of an ingredient flagged "uncommon_spawn" (porcini is sparse in the forest, spec §6.1).
## TODO(rules.json): move to rules.forage.uncommon_spawn_weight.
const UNCOMMON_SPAWN_WEIGHT := 0.5
const MAX_PRIORITY := 0  # P0 content only


static func generate(save_seed: int, day: int, biome: String, weather: String, varieties: Dictionary) -> Dictionary:
	var b := Builder.new()
	b.setup(save_seed, day, biome, weather, varieties)
	return b.run()


static func is_walkable(map: Dictionary, cell: Vector2i) -> bool:
	if map.is_empty():
		return false
	var w: int = int(map.w)
	var h: int = int(map.h)
	if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= h:
		return false
	var i := cell.y * w + cell.x
	if int(map.ground[i]) == T_WATER:
		return false
	if map.has("solid"):
		return int(map.solid[i]) == 0
	for list_key in ["decor_trees", "fruit_trees"]:
		for t in map.get(list_key, []):
			if int(t.x) == cell.x and int(t.y) == cell.y:
				return false
	for p in map.get("pickups", []):
		if p.kind == "bush" and int(p.x) == cell.x and int(p.y) == cell.y:
			return false
	return true


## Ingredient types a biome offers in a slot ("tree" | "bush" | "ground" | "abandoned_orchard"), sorted.
## Read from ingredients.json "sources": tree -> "<biome>" (fruit), bush -> "<biome>_bush", ground -> "<biome>_ground".
static func biome_types(biome: String, slot: String) -> Array:
	var source := biome
	match slot:
		"bush":
			source = biome + "_bush"
		"ground":
			source = biome + "_ground"
		"abandoned_orchard":
			source = "abandoned_orchard"
	var ing := Data.ingredients()
	var out: Array = []
	for id in Data.ids_up_to("ingredients", MAX_PRIORITY):
		var row: Dictionary = ing[id]
		if not (row.sources as Array).has(source):
			continue
		if slot == "tree" and row.group != "fruit":
			continue
		out.append(id)
	return out


## Ground-point type weights: 1 per type, UNCOMMON_SPAWN_WEIGHT for "uncommon_spawn" types,
## mushrooms × rules.weather.rain_mushroom_mult when it rains (spec §7.10). {"types": [..], "weights": [..]}
static func ground_type_weights(biome: String, weather: String) -> Dictionary:
	var ing := Data.ingredients()
	var rain_mult := float(Data.rules().weather.rain_mushroom_mult) if weather == "rainy" else 1.0
	var types := biome_types(biome, "ground")
	var weights: Array = []
	for t in types:
		var row: Dictionary = ing[t]
		var wgt := UNCOMMON_SPAWN_WEIGHT if bool(row.get("uncommon_spawn", false)) else 1.0
		if row.group == "mushroom":
			wgt *= rain_mult
		weights.append(wgt)
	return {"types": types, "weights": weights}


## Rare-variety weight multiplier from the weather (fog, P1).
static func weather_rare_mult(weather: String) -> float:
	return float(Data.rules().weather.fog_rare_mult) if weather == "foggy" else 1.0


## A variety id of `type`, drawn from `r` by rarity weight. Nuts -> "". No varieties for the type -> "<type>_1".
## Uses VarietyGen.spawn_weights when it answers, else rules.varieties tiers/weights by the variety's tier or rarity.
static func pick_variety(r: RandomNumberGenerator, varieties: Dictionary, type: String, rare_mult: float = 1.0,
		exclude: Array = []) -> String:
	var row: Dictionary = Data.ingredients().get(type, {})
	if row.get("group", "") == "nut":
		return ""
	var sw: Dictionary = VarietyGen.spawn_weights(varieties, type, rare_mult)
	var ids: Array = []
	var weights: Array = []
	if sw.has("ids") and not (sw.ids as Array).is_empty() and (sw.ids as Array).size() == (sw.weights as Array).size():
		ids = sw.ids
		weights = sw.weights
	else:
		var own := rarity_weights(varieties, type, rare_mult)
		ids = own.ids
		weights = own.weights
	if not exclude.is_empty():
		var keep_ids: Array = []
		var keep_w: Array = []
		for i in ids.size():
			if not exclude.has(ids[i]):
				keep_ids.append(ids[i])
				keep_w.append(weights[i])
		if not keep_ids.is_empty():
			ids = keep_ids
			weights = keep_w
	if ids.is_empty():
		return type + "_1"
	return ids[Seeds.pick_weighted(r, weights)]


## {"ids": sorted variety ids of `type`, "weights": rules.varieties weight of each (tier index, else rarity)}.
static func rarity_weights(varieties: Dictionary, type: String, rare_mult: float = 1.0) -> Dictionary:
	var vr: Dictionary = Data.rules().varieties
	var ids: Array = []
	for id in varieties:
		if varieties[id].get("type", "") == type:
			ids.append(id)
	ids.sort()
	var p1: bool = ids.size() > int(vr.count_p0)
	var tiers: Array = vr.tiers_p1 if p1 else vr.tiers_p0
	var tw: Array = vr.weights_p1 if p1 else vr.weights_p0
	var weights: Array = []
	for id in ids:
		var v: Dictionary = varieties[id]
		var tier := int(v.get("tier", -1))
		var rarity: String = v.get("rarity", "common")
		if tier < 0 or tier >= tw.size():
			tier = maxi(tiers.find(rarity), 0)
		var wgt := float(tw[tier])
		if rarity == "rare":
			wgt *= rare_mult
		weights.append(wgt)
	return {"ids": ids, "weights": weights}


## Varieties on the save's garden trees: mirrors State.new_game (stream "garden", day 0, rules.garden.trees order).
static func garden_varieties(save_seed: int, varieties: Dictionary) -> Array:
	var out: Array = []
	var r := Seeds.rng(save_seed, "garden", 0)
	for t in Data.rules().garden.trees:
		var v := State._garden_variety(varieties, t.type, r)
		if v != "":
			out.append(v)
	return out


## One generation run. Members hold the working layers so the steps write packed arrays in place.
class Builder:
	extends RefCounted

	const O_FREE := 0
	const O_DECOR := 1
	const O_FRUIT := 2
	const O_BUSH := 3
	const O_GROUND := 4
	const CLEARING_R2 := 6  # cells with dx²+dy² <= 6 around a clearing centre are cleared
	const ENTRANCE_R2 := 8  # nothing solid this close to the entrance
	const RING := [Vector2i(2, 0), Vector2i(2, 1), Vector2i(1, 2), Vector2i(0, 2), Vector2i(-1, 2), Vector2i(-2, 1),
		Vector2i(-2, 0), Vector2i(-2, -1), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -1)]
	const ORCHARD_SPOTS := [Vector2i(-2, -1), Vector2i(1, -1), Vector2i(-2, 1), Vector2i(1, 1), Vector2i(-1, -2),
		Vector2i(0, -2), Vector2i(-3, 0), Vector2i(2, 0), Vector2i(-1, 2), Vector2i(0, 2)]
	const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	var save_seed := 0
	var day := 0
	var biome := ""
	var weather := ""
	var varieties: Dictionary = {}
	var wr: Dictionary = {}
	var stream := ""
	var w := 0
	var h := 0
	var debug := false
	var r_kind: RandomNumberGenerator

	var ground := PackedByteArray()
	var noise := PackedFloat32Array()
	var occ := PackedByteArray()
	var on_path := PackedByteArray()
	var clearing_mask := PackedByteArray()
	var path_dist := PackedInt32Array()
	var decor: Dictionary = {}  # cell index -> kind, insertion order = generation order
	var fruit: Array = []
	var pickups: Array = []
	var special: Dictionary = {}
	var entrance := Vector2i.ZERO
	var clearings: Array = []
	var paths: Array = []
	var moved: Array = []
	var steps: Dictionary = {}

	func setup(p_save_seed: int, p_day: int, p_biome: String, p_weather: String, p_varieties: Dictionary) -> void:
		save_seed = p_save_seed
		day = p_day
		biome = p_biome
		weather = p_weather
		varieties = p_varieties
		wr = Data.rules().wild
		stream = "wild:" + biome
		w = int(wr.w)
		h = int(wr.h)
		debug = OS.is_debug_build()
		r_kind = _rng("kinds")
		ground.resize(w * h)
		occ.resize(w * h)
		on_path.resize(w * h)
		clearing_mask.resize(w * h)
		occ.fill(O_FREE)
		on_path.fill(0)
		clearing_mask.fill(0)

	func run() -> Dictionary:
		_step_ground(_rng("ground"))
		_snap("1_ground", {"ground": ground.duplicate()})
		_step_stream(_rng("stream"))
		_snap("2_stream", {"ground": ground.duplicate()})
		_step_decor(_rng("decor"))
		_snap("3_decor", {"decor_trees": _decor_list()})
		_step_paths(_rng("paths"))
		_snap("4_paths", {"ground": ground.duplicate(), "decor_trees": _decor_list(), "clearings": clearings.duplicate(),
			"paths": paths.duplicate(true)})
		_step_pickups(_rng("pickups"))
		_snap("5_pickups", {"decor_trees": _decor_list(), "fruit_trees": fruit.duplicate(true), "pickups": pickups.duplicate(true)})
		_step_special(_rng("special"))
		_snap("6_special", {"special": special.duplicate(), "fruit_trees": fruit.duplicate(true), "pickups": pickups.duplicate(true)})
		_step_validate()
		for i in fruit.size():
			fruit[i].id = i
		for i in pickups.size():
			pickups[i].id = i
		_snap("7_validate", {"moved": moved.duplicate(true), "fruit_trees": fruit.duplicate(true), "pickups": pickups.duplicate(true)})
		var solid := PackedByteArray()
		solid.resize(w * h)
		for i in w * h:
			solid[i] = 1 if _is_solid(i) else 0
		return {
			"seed": Seeds.seed_for(save_seed, stream, day),
			"biome": biome,
			"w": w,
			"h": h,
			"ground": ground,
			"decor_trees": _decor_list(),
			"fruit_trees": fruit,
			"pickups": pickups,
			"special": special,
			"entrance": entrance,
			"clearings": clearings,
			"steps": steps,
			"solid": solid,
		}

	# ---------- step 1: two-octave value noise -> grass / leaf litter / dirt ----------

	func _step_ground(r: RandomNumberGenerator) -> void:
		entrance = Vector2i(r.randi_range(floori(w / 2.0) - 6, floori(w / 2.0) + 6), h - 1)
		var o1 := _value_noise(r, 8)
		var o2 := _value_noise(r, 4)
		noise.resize(w * h)
		for i in w * h:
			var n := 0.65 * o1[i] + 0.35 * o2[i]
			noise[i] = n
			if n < 0.36:
				ground[i] = WildGen.T_DIRT
			elif n < 0.56:
				ground[i] = WildGen.T_GRASS
			else:
				ground[i] = WildGen.T_LEAVES

	func _value_noise(r: RandomNumberGenerator, period: int) -> PackedFloat32Array:
		var gw := floori(float(w) / period) + 2
		var gh := floori(float(h) / period) + 2
		var lat := PackedFloat32Array()
		lat.resize(gw * gh)
		for i in lat.size():
			lat[i] = r.randf()
		var out := PackedFloat32Array()
		out.resize(w * h)
		for y in h:
			var fy := float(y) / period
			var y0 := floori(fy)
			var ty := _fade(fy - y0)
			for x in w:
				var fx := float(x) / period
				var x0 := floori(fx)
				var tx := _fade(fx - x0)
				var a := lerpf(lat[y0 * gw + x0], lat[y0 * gw + x0 + 1], tx)
				var b := lerpf(lat[(y0 + 1) * gw + x0], lat[(y0 + 1) * gw + x0 + 1], tx)
				out[y * w + x] = lerpf(a, b, ty)
		return out

	func _fade(t: float) -> float:
		return t * t * (3.0 - 2.0 * t)

	# ---------- step 2: stream, edge to edge random walk (40%) ----------

	func _step_stream(r: RandomNumberGenerator) -> void:
		if r.randf() >= float(wr.stream_chance):
			return
		if r.randf() < 0.5:
			# west -> east, kept clear of the south rows around the entrance
			var lo := 3
			var hi := h - 9
			var y := r.randi_range(lo + 1, hi - 1)
			for x in w:
				_water(x, y)
				if r.randf() < 0.45:
					var ny := clampi(y + (1 if r.randf() < 0.5 else -1), lo, hi)
					_water(x, ny)  # same column: the stream stays 4-connected
					y = ny
				if r.randf() < 0.3:
					_water(x, y + 1)
		else:
			# north -> south, on one side of the entrance
			var lo := 2
			var hi := entrance.x - 6
			if r.randf() < 0.5 or hi < lo + 4:
				lo = entrance.x + 6
				hi = w - 3
			var x := r.randi_range(lo, hi)
			for y in h:
				_water(x, y)
				if r.randf() < 0.45:
					var nx := clampi(x + (1 if r.randf() < 0.5 else -1), lo, hi)
					_water(nx, y)
					x = nx
				if r.randf() < 0.3:
					_water(x + 1, y)

	func _water(x: int, y: int) -> void:
		if x >= 0 and y >= 0 and x < w and y < h:
			ground[y * w + x] = WildGen.T_WATER

	# ---------- step 3: decor trees, Poisson-disk (r = rules.wild.poisson_r) ----------

	func _step_decor(r: RandomNumberGenerator) -> void:
		var order := PackedInt32Array()
		order.resize(w * h)
		for i in w * h:
			order[i] = i
		for i in range(w * h - 1, 0, -1):
			var j := r.randi_range(0, i)
			var t := order[i]
			order[i] = order[j]
			order[j] = t
		var rad := int(wr.poisson_r)
		var r2 := rad * rad
		for idx in order:
			if ground[idx] == WildGen.T_WATER:
				continue
			var x := idx % w
			@warning_ignore("integer_division")
			var y := idx / w
			if _d2(x, y, entrance) <= ENTRANCE_R2 + 4:
				continue
			var ok := true
			for dy in range(1 - rad, rad):
				var yy := y + dy
				if yy < 0 or yy >= h:
					continue
				for dx in range(1 - rad, rad):
					var xx := x + dx
					if xx < 0 or xx >= w or dx * dx + dy * dy >= r2:
						continue
					if occ[yy * w + xx] == O_DECOR:
						ok = false
						break
				if not ok:
					break
			if ok:
				occ[idx] = O_DECOR
				decor[idx] = DECOR_KINDS[r.randi_range(0, DECOR_KINDS.size() - 1)]

	# ---------- step 4: clearings + A* paths from the entrance, stepping stones over water ----------

	func _step_paths(r: RandomNumberGenerator) -> void:
		var cr: Array = wr.clearings
		var want := r.randi_range(int(cr[0]), int(cr[1]))
		var min_d := 12.0
		var tries := 0
		while clearings.size() < want and tries < 600:
			tries += 1
			if tries % 100 == 0:
				min_d = maxf(min_d - 2.0, 4.0)
			var c := Vector2i(r.randi_range(5, w - 6), r.randi_range(3, h - 10))
			if sqrt(float(_d2(c.x, c.y, entrance))) < min_d + 2.0:
				continue
			var ok := true
			for o in clearings:
				if sqrt(float(_d2(c.x, c.y, o))) < min_d:
					ok = false
					break
			if ok and tries < 500:
				ok = not _water_within(c, 9)
			if ok:
				clearings.append(c)
		for c in clearings:
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var x: int = c.x + dx
					var y: int = c.y + dy
					if dx * dx + dy * dy > CLEARING_R2 or not _in(x, y):
						continue
					var i := y * w + x
					if ground[i] != WildGen.T_WATER:
						ground[i] = WildGen.T_GRASS
					if occ[i] == O_DECOR:
						occ[i] = O_FREE
						decor.erase(i)
					clearing_mask[i] = 1

		var astar := AStarGrid2D.new()
		astar.region = Rect2i(0, 0, w, h)
		astar.cell_size = Vector2(1, 1)
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		astar.update()
		for y in h:
			for x in w:
				var i := y * w + x
				var wt := 1.0 + 2.0 * noise[i] + r.randf() * 0.5
				if ground[i] == WildGen.T_WATER:
					wt += 6.0
				elif occ[i] == O_DECOR:
					wt += 3.0
				if x == 0 or y == 0 or x == w - 1:
					wt += 4.0
				if clearing_mask[i] == 1:
					wt = 0.8
				astar.set_point_weight_scale(Vector2i(x, y), wt)
		var order := clearings.duplicate()
		order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := _d2(a.x, a.y, entrance)
			var db := _d2(b.x, b.y, entrance)
			return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
		for c in order:
			var pts: Array[Vector2i] = astar.get_id_path(entrance, c)
			paths.append(pts)
			for p in pts:
				var i := p.y * w + p.x
				if on_path[i] == 1:
					continue  # shared trunk: already a path tile or a stepping stone
				on_path[i] = 1
				ground[i] = WildGen.T_STONE if ground[i] == WildGen.T_WATER else WildGen.T_PATH
				if occ[i] == O_DECOR:
					occ[i] = O_FREE
					decor.erase(i)
				astar.set_point_weight_scale(p, 0.35)  # later paths reuse the trunk

	# ---------- step 5: fruit trees from path-side decor trees, bushes, ground points ----------

	func _step_pickups(r: RandomNumberGenerator) -> void:
		var rare_mult := WildGen.weather_rare_mult(weather)
		_compute_path_dist()

		var tree_types := WildGen.biome_types(biome, "tree")
		var fr: Array = wr.fruit_trees
		var n_fruit := r.randi_range(int(fr[0]), int(fr[1]))
		if not tree_types.is_empty():
			var beside: Array = []
			var near: Array = []
			for idx in decor:
				if _touches_path(idx):
					beside.append(idx)
				elif _has_neighbour_dist(idx, 3):
					near.append(idx)
			_shuffle(r, beside)
			_shuffle(r, near)
			var chosen := _pick_spaced(beside, n_fruit, 25, [])
			if chosen.size() < n_fruit:
				chosen = _pick_spaced(beside, n_fruit, 0, chosen)
			if chosen.size() < n_fruit:
				chosen = _pick_spaced(near, n_fruit, 0, chosen)
			if chosen.size() < n_fruit:
				chosen = _pick_spaced(_free_cells(r, 1, 2, false), n_fruit, 0, chosen)
			var yr: Array = Data.rules().forage.tree_yield
			for idx in chosen:
				decor.erase(idx)
				occ[idx] = O_FRUIT
				var t: String = tree_types[r_kind.randi_range(0, tree_types.size() - 1)]
				fruit.append({"id": -1, "x": idx % w, "y": _row(idx), "type": t,
					"variety": WildGen.pick_variety(r_kind, varieties, t, rare_mult),
					"yield": r.randi_range(int(yr[0]), int(yr[1]))})

		var bush_types := WildGen.biome_types(biome, "bush")
		var br: Array = wr.bushes
		var n_bush := r.randi_range(int(br[0]), int(br[1]))
		if not bush_types.is_empty():
			var spots := _pick_spaced(_free_cells(r, 1, 3, true), n_bush, 9, [])
			if spots.size() < n_bush:
				spots = _pick_spaced(_free_cells(r, 1, 6, false), n_bush, 4, spots)
			if spots.size() < n_bush:
				spots = _pick_spaced(_free_cells(r, 1, 999, false), n_bush, 0, spots)
			for idx in spots:
				occ[idx] = O_BUSH
				var t: String = bush_types[r_kind.randi_range(0, bush_types.size() - 1)]
				pickups.append({"id": -1, "x": idx % w, "y": _row(idx), "kind": "bush", "type": t,
					"variety": WildGen.pick_variety(r_kind, varieties, t, rare_mult)})

		var gtw := WildGen.ground_type_weights(biome, weather)
		var gr: Array = wr.ground
		var n_ground := r.randi_range(int(gr[0]), int(gr[1]))
		if not (gtw.types as Array).is_empty():
			var taken: Array = []
			for p in pickups:
				taken.append(int(p.y) * w + int(p.x))
			var total := taken.size() + n_ground
			var spots := _pick_spaced(_free_cells(r, 1, 5, false), total, 4, taken)
			if spots.size() < total:
				spots = _pick_spaced(_free_cells(r, 1, 999, false), total, 4, spots)
			if spots.size() < total:
				spots = _pick_spaced(_free_cells(r, 0, 999, false), total, 0, spots)
			for k in range(taken.size(), spots.size()):
				var idx: int = spots[k]
				occ[idx] = O_GROUND
				var t: String = gtw.types[Seeds.pick_weighted(r_kind, gtw.weights)]
				pickups.append({"id": -1, "x": idx % w, "y": _row(idx), "kind": "ground", "type": t,
					"variety": WildGen.pick_variety(r_kind, varieties, t, rare_mult)})

	## Free cells (walkable, nothing on them, off the path, outside clearings and the entrance zone)
	## whose distance to the path is in [dmin, dmax], shuffled. open4: all 4 neighbours free of trees and bushes.
	func _free_cells(r: RandomNumberGenerator, dmin: int, dmax: int, open4: bool) -> Array:
		var out: Array = []
		for i in w * h:
			if occ[i] != O_FREE or on_path[i] == 1 or clearing_mask[i] == 1 or ground[i] == WildGen.T_WATER:
				continue
			var d := path_dist[i]
			if d < dmin or d > dmax:
				continue
			var x := i % w
			var y := _row(i)
			if _d2(x, y, entrance) <= ENTRANCE_R2:
				continue
			if open4 and not _open4(x, y):
				continue
			out.append(i)
		_shuffle(r, out)
		return out

	## A copy of `taken` plus cells from `cands` until it holds `total`, each new cell at squared distance >= min_d2
	## from every cell already in the list.
	func _pick_spaced(cands: Array, total: int, min_d2: int, taken: Array) -> Array:
		var out := taken.duplicate()
		for c in cands:
			if out.size() >= total:
				break
			if out.has(c):
				continue
			var cx: int = c % w
			var cy := _row(c)
			var ok := true
			if min_d2 > 0:
				for o in out:
					var dx: int = o % w - cx
					var dy: int = _row(o) - cy
					if dx * dx + dy * dy < min_d2:
						ok = false
						break
			if ok:
				out.append(c)
		return out

	# ---------- step 6: special place (35%): mushroom ring or abandoned orchard, in a clearing ----------

	func _step_special(r: RandomNumberGenerator) -> void:
		if clearings.is_empty() or r.randf() >= float(wr.special_chance):
			return
		var kinds: Array = wr.special_kinds_p0
		var kind: String = kinds[r.randi_range(0, kinds.size() - 1)]
		var c: Vector2i = clearings[r.randi_range(0, clearings.size() - 1)]
		var rare_mult := WildGen.weather_rare_mult(weather)
		match kind:
			"mushroom_ring":
				var gtw := WildGen.ground_type_weights(biome, weather)
				var types: Array = []
				var weights: Array = []
				var ing := Data.ingredients()
				for k in (gtw.types as Array).size():
					if ing[gtw.types[k]].group == "mushroom":
						types.append(gtw.types[k])
						weights.append(gtw.weights[k])
				if types.is_empty():
					return
				var rm: Array = wr.ring_mushrooms
				var n := r.randi_range(int(rm[0]), int(rm[1]))
				var k0 := r.randi_range(0, RING.size() - 1)
				var ring_mult := rare_mult * float(Data.rules().forage.ring_rare_weight_mult)
				for k in n:
					var off: Vector2i = RING[(k0 + floori(k * float(RING.size()) / n)) % RING.size()]
					var p := c + off
					if not _in(p.x, p.y):
						continue
					var i := p.y * w + p.x
					if ground[i] == WildGen.T_WATER or occ[i] != O_FREE:
						continue
					occ[i] = O_GROUND
					var t: String = types[Seeds.pick_weighted(r_kind, weights)]
					pickups.append({"id": -1, "x": p.x, "y": p.y, "kind": "ground", "type": t,
						"variety": WildGen.pick_variety(r_kind, varieties, t, ring_mult), "special": true})
				special = {"kind": kind, "x": c.x - 2, "y": c.y - 2, "w": 5, "h": 5}
			"abandoned_orchard":
				var types := WildGen.biome_types(biome, "abandoned_orchard")
				if types.is_empty():
					return
				var x0 := maxi(c.x - 3, 0)
				var y0 := maxi(c.y - 2, 0)
				var x1 := mini(c.x + 2, w - 1)
				var y1 := mini(c.y + 2, h - 1)
				for y in range(y0, y1 + 1):
					for x in range(x0, x1 + 1):
						var i := y * w + x
						if occ[i] == O_DECOR:
							occ[i] = O_FREE
							decor.erase(i)
				var spots := ORCHARD_SPOTS.duplicate()
				_shuffle(r, spots)
				var placed: Array = []
				var garden := WildGen.garden_varieties(save_seed, varieties)
				var yr: Array = Data.rules().forage.tree_yield
				for off in spots:
					if placed.size() >= int(wr.orchard_quince_trees):
						break
					var p: Vector2i = c + off
					if not _in(p.x, p.y):
						continue
					var i := p.y * w + p.x
					if ground[i] == WildGen.T_WATER or occ[i] != O_FREE or on_path[i] == 1:
						continue
					var far := true
					for q in placed:
						if _d2(p.x, p.y, q) < 4:
							far = false
					if not far:
						continue
					placed.append(p)
					occ[i] = O_FRUIT
					var t: String = types[r_kind.randi_range(0, types.size() - 1)]
					fruit.append({"id": -1, "x": p.x, "y": p.y, "type": t,
						"variety": WildGen.pick_variety(r_kind, varieties, t, rare_mult, garden),
						"yield": r.randi_range(int(yr[0]), int(yr[1])), "special": true})
				special = {"kind": kind, "x": x0, "y": y0, "w": x1 - x0 + 1, "h": y1 - y0 + 1}

	# ---------- step 7: flood fill from the entrance; move what cannot be reached ----------

	func _step_validate() -> void:
		for pass_i in 6:
			var all_ok := true
			var reach := _flood()
			for list in [fruit, pickups]:
				for item in list:
					if _item_reachable(item, reach):
						continue
					all_ok = false
					_move(item, reach)
					reach = _flood()
			if all_ok:
				return

	func _item_reachable(item: Dictionary, reach: PackedByteArray) -> bool:
		var x := int(item.x)
		var y := int(item.y)
		if item.get("kind", "tree") == "ground":
			return reach[y * w + x] == 1
		for d in N4:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if _in(nx, ny) and reach[ny * w + nx] == 1:
				return true
		return false

	## Moves an item to the nearest reachable empty tile (BFS order from its cell, deterministic).
	func _move(item: Dictionary, reach: PackedByteArray) -> void:
		var blocker: bool = item.get("kind", "tree") != "ground"
		var from := Vector2i(int(item.x), int(item.y))
		var seen := PackedByteArray()
		seen.resize(w * h)
		seen.fill(0)
		var queue: Array[Vector2i] = [from]
		seen[from.y * w + from.x] = 1
		var head := 0
		var best := -1
		var fallback := -1
		while head < queue.size():
			var p: Vector2i = queue[head]
			head += 1
			var i := p.y * w + p.x
			if p != from and reach[i] == 1 and occ[i] == O_FREE and p != entrance:
				if not blocker:
					best = i
					break
				if on_path[i] == 0 and _d2(p.x, p.y, entrance) > ENTRANCE_R2:
					if _open4(p.x, p.y):
						best = i
						break
					if fallback < 0:
						fallback = i
			for d in N4:
				var q: Vector2i = p + d
				if _in(q.x, q.y) and seen[q.y * w + q.x] == 0:
					seen[q.y * w + q.x] = 1
					queue.append(q)
		if best < 0:
			best = fallback
		if best < 0:
			return
		var old := from.y * w + from.x
		var kind_o := occ[old]
		occ[old] = O_FREE
		occ[best] = kind_o
		item.x = best % w
		item.y = _row(best)
		moved.append({"from": from, "to": Vector2i(int(item.x), int(item.y))})

	func _flood() -> PackedByteArray:
		var reach := PackedByteArray()
		reach.resize(w * h)
		reach.fill(0)
		var start := entrance.y * w + entrance.x
		if not _walk(start):
			return reach
		var queue := PackedInt32Array([start])
		reach[start] = 1
		var head := 0
		while head < queue.size():
			var i := queue[head]
			head += 1
			var x := i % w
			if x > 0 and reach[i - 1] == 0 and _walk(i - 1):
				reach[i - 1] = 1
				queue.append(i - 1)
			if x < w - 1 and reach[i + 1] == 0 and _walk(i + 1):
				reach[i + 1] = 1
				queue.append(i + 1)
			if i >= w and reach[i - w] == 0 and _walk(i - w):
				reach[i - w] = 1
				queue.append(i - w)
			if i + w < w * h and reach[i + w] == 0 and _walk(i + w):
				reach[i + w] = 1
				queue.append(i + w)
		return reach

	# ---------- helpers ----------

	func _rng(sub: String) -> RandomNumberGenerator:
		return Seeds.rng(save_seed, stream, day, sub)

	func _snap(key: String, layers: Dictionary) -> void:
		if debug:
			steps[key] = layers

	func _decor_list() -> Array:
		var out: Array = []
		for idx in decor:
			out.append({"x": idx % w, "y": _row(idx), "kind": decor[idx]})
		return out

	func _row(i: int) -> int:
		@warning_ignore("integer_division")
		return i / w

	func _in(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h

	func _d2(x: int, y: int, p: Vector2i) -> int:
		return (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y)

	func _is_solid(i: int) -> bool:
		return occ[i] == O_DECOR or occ[i] == O_FRUIT or occ[i] == O_BUSH

	func _walk(i: int) -> bool:
		return ground[i] != WildGen.T_WATER and not _is_solid(i)

	func _open4(x: int, y: int) -> bool:
		for d in N4:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if _in(nx, ny) and not _walk(ny * w + nx):
				return false
		return true

	func _water_within(c: Vector2i, r2: int) -> bool:
		var found := false
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if dx * dx + dy * dy > r2:
					continue
				var x := c.x + dx
				var y := c.y + dy
				if _in(x, y) and ground[y * w + x] == WildGen.T_WATER:
					found = true
		return found

	func _touches_path(idx: int) -> bool:
		var x := idx % w
		var y := _row(idx)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if (dx != 0 or dy != 0) and _in(nx, ny) and on_path[ny * w + nx] == 1:
					return true
		return false

	## A 4-neighbour of idx is walkable and within `dmax` steps of the path.
	func _has_neighbour_dist(idx: int, dmax: int) -> bool:
		var x := idx % w
		var y := _row(idx)
		for d in N4:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if _in(nx, ny):
				var pd := path_dist[ny * w + nx]
				if pd >= 0 and pd <= dmax:
					return true
		return false

	## Steps from the nearest path tile over walkable tiles (-1 = not connected to the path).
	func _compute_path_dist() -> void:
		path_dist.resize(w * h)
		path_dist.fill(-1)
		var queue := PackedInt32Array()
		for i in w * h:
			if on_path[i] == 1:
				path_dist[i] = 0
				queue.append(i)
		var head := 0
		while head < queue.size():
			var i := queue[head]
			head += 1
			var x := i % w
			var nd := path_dist[i] + 1
			for j in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w, i + w]:
				if j < 0 or j >= w * h or path_dist[j] != -1 or not _walk(j):
					continue
				path_dist[j] = nd
				queue.append(j)

	func _shuffle(r: RandomNumberGenerator, a: Array) -> void:
		for i in range(a.size() - 1, 0, -1):
			var j := r.randi_range(0, i)
			var t: Variant = a[i]
			a[i] = a[j]
			a[j] = t
