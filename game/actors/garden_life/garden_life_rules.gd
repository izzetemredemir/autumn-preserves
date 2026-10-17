class_name GardenLifeRules
extends RefCounted
## GARDEN-LIFE · The garden's little lives, pure (no autoloads, no scene): the hens' seeded routes in their run, where
## they scatter to, the truck bed's load for the calendar week, which line Granny says. Cosmetic: nothing here is
## saved or changes the game. Hen routes use Seeds.rng(save_seed, "hens", day, "hen<i>").
##
## A route is a loop of steps {"act": "walk"|"stop"|"peck"|"scratch", "to": Vector2i (feet, garden px), "sec"}:
## the hen walks to "to", then does "act" for "sec" ("walk" has none). Every "to" is inside `area` and outside
## every `avoid` rect (the hen house).

const HENS := 3  ## plus one rooster
const ROUTE_STEPS := 18
const ACTS := ["stop", "peck", "peck", "scratch"]  ## what a hen does after a walk (peck twice as likely)
const HEN_HALF_W := 6  ## px: half a hen's width; the feet keep this far from the side fences
const HEN_H := 10  ## px: the feet keep this far under the back fence (the hen stands inside)
const FRONT_GAP := 3  ## px above the front fence
const RAIN_DEPTH := 14  ## px in front of the hen house where they stay on rainy days
const SCATTER_PX := 18
## Truck bed load frames (garden_truck_bed.png): the hay load before the calendar starts, then one per week id.
const LOADS := {"grape_harvest": 1, "apple_moon": 2, "first_frost": 3}


## The flock: the rooster first, then the hens alternating the two colours.
## [{"kind": "rooster"|"hen", "variant": 0|1}]
static func flock() -> Array:
	var out: Array = [{"kind": "rooster", "variant": 0}]
	for i in HENS:
		out.append({"kind": "hen", "variant": i % 2})
	return out


## Where the hens' feet may be: inside the run (garden px) away from the fences; on rainy days only the strip just in
## front of the hen house (`coop`: its footprint in px, inside the run), so they stay near shelter.
static func area(run: Rect2i, coop: Rect2i, rainy: bool) -> Rect2i:
	var a := Rect2i(run.position + Vector2i(HEN_HALF_W + 1, HEN_H + 2),
		run.size - Vector2i(HEN_HALF_W * 2 + 2, HEN_H + 2 + FRONT_GAP))
	if rainy and coop.has_area():
		var near := Rect2i(coop.position.x - 4, coop.end.y + 1, coop.size.x + 8, RAIN_DEPTH)
		var wet := a.intersection(near)
		if wet.has_area():
			return wet
	return a


## One hen's loop for the day. Same inputs, same route.
static func route(save_seed: int, day: int, index: int, p_area: Rect2i, avoid: Array) -> Array:
	var r := Seeds.rng(save_seed, "hens", day, "hen%d" % index)
	var out: Array = []
	var at := _point(r, p_area, avoid)
	for _i in ROUTE_STEPS:
		at = _point(r, p_area, avoid, at)
		out.append({"act": "walk", "to": at, "sec": 0.0})
		for _j in r.randi_range(1, 2):
			var act: String = ACTS[r.randi_range(0, ACTS.size() - 1)]
			out.append({"act": act, "to": at, "sec": snappedf(r.randf_range(0.8, 2.6), 0.1)})
	return out


## Start feet of hen `index` (the first point of its route).
static func start(rt: Array) -> Vector2i:
	return rt[0].to if not rt.is_empty() else Vector2i.ZERO


## Where a startled hen at `from` runs: the spot SCATTER_PX or less away that is furthest from Granny (`granny`,
## garden px), inside `p_area` and off the hen house. `from` itself when every way is closer to her (it flaps on the spot).
static func scatter(from: Vector2i, granny: Vector2, p_area: Rect2i, avoid: Array) -> Vector2i:
	var away := Vector2(from) - granny
	if away.length() < 0.5:
		away = Vector2.DOWN
	away = away.normalized()
	var best := from
	var best_d := Vector2(from).distance_to(granny)
	for turn: float in [0.0, 0.6, -0.6, 1.2, -1.2, PI * 0.5, -PI * 0.5]:
		for k: float in [1.0, 0.6]:
			var p := Vector2i((Vector2(from) + away.rotated(turn) * SCATTER_PX * k).round())
			p = p.clamp(p_area.position, p_area.end - Vector2i.ONE)
			var d := Vector2(p).distance_to(granny)
			if p != from and _free(p, avoid) and d > best_d + 0.5:
				best = p
				best_d = d
	return best


static func inside(p: Vector2i, p_area: Rect2i, avoid: Array) -> bool:
	return p_area.has_point(p) and _free(p, avoid)


## Frame of garden_truck_bed.png for `day`: the hay load in the tutorial week, then the calendar week's load.
static func truck_load(day: int) -> int:
	return int(LOADS.get(Calendar.week_id(day), 0))


## 1..n: which of n lines to say, never `last` twice in a row (like CatRules.pet_line).
static func line(r: RandomNumberGenerator, n: int, last: int) -> int:
	var i := r.randi_range(1, n)
	if i == last and n > 1:
		i = i % n + 1
	return i


static func _point(r: RandomNumberGenerator, p_area: Rect2i, avoid: Array, near := Vector2i(-1, -1)) -> Vector2i:
	var p := p_area.position
	for _i in 16:
		p = Vector2i(r.randi_range(p_area.position.x, p_area.end.x - 1), r.randi_range(p_area.position.y, p_area.end.y - 1))
		if near.x >= 0:  # little routes: the next stop is a few steps away
			p = near + (p - near).clamp(Vector2i(-20, -12), Vector2i(20, 12))
		if _free(p, avoid) and p != near:
			return p
	return near if near.x >= 0 else p


static func _free(p: Vector2i, avoid: Array) -> bool:
	for a: Rect2i in avoid:
		if a.has_point(p):
			return false
	return true
