class_name CritterRules
extends RefCounted
## WILD-LIFE · Where the little animals of a map sit today. Pure (no autoloads, no scene): ambient critters have no
## gameplay and are never saved, so this only picks places. Streams are Seeds.rng(save_seed, "critters:<biome>", day)
## ("critters:garden" for the garden). Everything is drawn first and weather only trims the list afterwards, so one
## day's critters are the same in any weather except that rain leaves fewer birds.
##
## A placement is {"kind": "squirrel"|"hedgehog"|"bird"|"frog"|"ring", "cell": Vector2i, ...}:
##   squirrel: sits at the foot of the decor tree on `cell` and runs up it when Granny comes near.
##   bird: "species" "sparrow"|"robin", "perch" (sits up on a vine post or the fence, flies off) or on the ground
##         (hops). "lift" is the perch height in px above the cell's feet; "feet" (garden fence) overrides the position.
##   hedgehog: in the leaves, curls up when Granny is close. frog: on a creek bank next to the water.
##   ring: a fish ring on a water cell.
## Order is stable: birds are listed so that rain keeps the first ones.

const MAX_NODES := 40  ## per map, the frame-time budget
const RAIN_BIRD_SHARE := 0.4
const ENTRANCE_D2 := 25  ## no critter this close (squared cells) to the entrance
const VINE_LIFT := 26  ## px above the vine's feet where a sparrow perches
const SPECIES := ["sparrow", "robin"]
const Layout := preload("res://scenes/garden/garden_layout.gd")
const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Garden fence: the bottom row's post caps; a perched bird stands 3 px under the cell's top edge.
const FENCE_STAND := 3
const GARDEN_LAWN_ROWS := Vector2i(3, 14)


## Placements for a wild map (WildGen.generate output) on `day`. Empty for an empty map.
static func wild(map: Dictionary, save_seed: int, day: int, weather: String) -> Array:
	if map.is_empty():
		return []
	var biome := String(map.get("biome", "forest"))
	var r := Seeds.rng(save_seed, "critters:" + biome, day)
	var out: Array = []
	var birds: Array = []
	match biome:
		"vineyard":
			var posts := _pick(_cells_of_vines(map), r.randi_range(5, 8), r)
			for c in posts:
				birds.append({"kind": "bird", "species": "sparrow", "cell": c, "perch": true, "lift": VINE_LIFT})
			for c in _pick(_free_cells(map, [WildGen.T_GRASS, WildGen.T_LEAVES]), r.randi_range(1, 2), r):
				birds.append(_ground_bird(c, r))
		"creek":
			for c in _pick(_bank_cells(map), r.randi_range(3, 5), r):
				out.append({"kind": "frog", "cell": c})
			for c in _pick(_cells_with(map, [WildGen.T_WATER]), r.randi_range(4, 6), r):
				out.append({"kind": "ring", "cell": c})
			for c in _pick(_free_cells(map, [WildGen.T_GRASS, WildGen.T_LEAVES]), r.randi_range(2, 3), r):
				birds.append(_ground_bird(c, r))
		_:
			for t in _pick(_decor_trees(map), r.randi_range(2, 3), r):
				out.append({"kind": "squirrel", "cell": t})
			for c in _pick(_free_cells(map, [WildGen.T_LEAVES]), r.randi_range(1, 2), r):
				out.append({"kind": "hedgehog", "cell": c})
			for c in _pick(_free_cells(map, [WildGen.T_GRASS, WildGen.T_LEAVES]), r.randi_range(4, 6), r):
				birds.append(_ground_bird(c, r))
	return _finish(out, birds, weather)


## Placements for the garden: a robin on the bottom fence and a sparrow or two on the lawn. `walkable(cell) -> bool`
## says which lawn cells are free (the scene knows about beds, trees and signs).
static func garden(save_seed: int, day: int, weather: String, walkable: Callable) -> Array:
	var r := Seeds.rng(save_seed, "critters:garden", day)
	var posts: Array = []
	for x in range(3, Layout.W - 3):
		var c := Vector2i(x, Layout.H - 1)
		if not Layout.is_gate(c) and not Layout.is_gate(c + Vector2i.LEFT) and not Layout.is_gate(c + Vector2i.RIGHT):
			posts.append(c)
	var birds: Array = []
	for c in _pick(posts, 1, r):
		birds.append({"kind": "bird", "species": "robin", "cell": c, "perch": true, "feet": FENCE_STAND})
	var lawn: Array = []
	for y in range(GARDEN_LAWN_ROWS.x, GARDEN_LAWN_ROWS.y + 1):
		for x in range(2, Layout.W - 2):
			var c := Vector2i(x, y)
			if Layout.ground(c) == Layout.T_LEAVES and walkable.is_valid() and bool(walkable.call(c)):
				lawn.append(c)
	for c in _pick(lawn, r.randi_range(1, 2), r):
		birds.append({"kind": "bird", "species": "sparrow", "cell": c, "perch": false})
	return _finish([], birds, weather)


## How many of `n` birds are out in `weather`: rain leaves RAIN_BIRD_SHARE of them (rounded), other weather all.
static func birds_out(n: int, weather: String) -> int:
	return int(floorf(n * RAIN_BIRD_SHARE + 0.5)) if weather == "rainy" else n


static func _finish(out: Array, birds: Array, weather: String) -> Array:
	out.append_array(birds.slice(0, birds_out(birds.size(), weather)))
	return out.slice(0, MAX_NODES)


static func _ground_bird(c: Vector2i, r: RandomNumberGenerator) -> Dictionary:
	return {"kind": "bird", "species": SPECIES[r.randi_range(0, SPECIES.size() - 1)], "cell": c, "perch": false}


## `n` of `cells` (a scan-ordered list), shuffled by `r`; fewer when the list is short.
static func _pick(cells: Array, n: int, r: RandomNumberGenerator) -> Array:
	var a := cells.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a.slice(0, mini(n, a.size()))


static func _decor_trees(map: Dictionary) -> Array:
	var out: Array = []
	for d in map.get("decor_trees", []):
		if String(d.get("kind", "")) != "vine":
			out.append(Vector2i(int(d.x), int(d.y)))
	return out


static func _cells_of_vines(map: Dictionary) -> Array:
	var out: Array = []
	for d in map.get("decor_trees", []):
		if String(d.get("kind", "")) == "vine":
			out.append(Vector2i(int(d.x), int(d.y)))
	return out


static func _cells_with(map: Dictionary, ground_ids: Array) -> Array:
	var out: Array = []
	var w := int(map.w)
	for i in (map.ground as PackedByteArray).size():
		if int(map.ground[i]) in ground_ids:
			out.append(Vector2i(i % w, floori(float(i) / w)))
	return out


## Walkable cells of the given ground ids, off the entrance.
static func _free_cells(map: Dictionary, ground_ids: Array) -> Array:
	var out: Array = []
	var e: Vector2i = map.get("entrance", Vector2i(-100, -100))
	for c in _cells_with(map, ground_ids):
		var d: Vector2i = c - e
		if d.x * d.x + d.y * d.y > ENTRANCE_D2 and WildGen.is_walkable(map, c):
			out.append(c)
	return out


## Walkable creek-bank cells with water right beside them.
static func _bank_cells(map: Dictionary) -> Array:
	var out: Array = []
	var w := int(map.w)
	var h := int(map.h)
	for c in _free_cells(map, [WildGen.T_BANK]):
		for n in N4:
			var q: Vector2i = c + n
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and int(map.ground[q.y * w + q.x]) == WildGen.T_WATER:
				out.append(c)
				break
	return out
