class_name CatRules
extends RefCounted
## P2-CAT · Granny's cat, pure logic (no autoloads, no scene): which nap spot it picks today, where it wanders,
## when it looks at Granny. The cat is a pure delight: no needs, no gameplay effect, nothing to feed or fail.
## Spots are garden cells ([col, row], see garden_layout.gd); the stream is Seeds.rng(save_seed, "cat", day).

const SPOTS := [
	{"id": "doorstep", "cell": Vector2i(15, 6)},
	{"id": "compost", "cell": Vector2i(12, 11)},  ## on the compost lid
	{"id": "bed_edge", "cell": Vector2i(9, 8)},  ## the sunny gap between the first two beds
	{"id": "gate_post", "cell": Vector2i(12, 15)},
]
const LOOK_RADIUS := 4  ## cells (Chebyshev): she is "near" when this close
const WANDER_RADIUS := 3
const PET_LINES := 4


## Today's nap spot (a SPOTS entry). Same save seed and day always give the same one.
static func spot_for(save_seed: int, day: int) -> Dictionary:
	var r := Seeds.rng(save_seed, "cat", day)
	return SPOTS[r.randi_range(0, SPOTS.size() - 1)]


## A cell within WANDER_RADIUS of `home` that is open and not `home` itself; `home` when none is. `walkable(cell) -> bool`.
static func wander_cell(home: Vector2i, r: RandomNumberGenerator, walkable: Callable) -> Vector2i:
	for _i in 12:
		var c := home + Vector2i(r.randi_range(-WANDER_RADIUS, WANDER_RADIUS), r.randi_range(-WANDER_RADIUS, WANDER_RADIUS))
		if c != home and bool(walkable.call(c)):
			return c
	return home


static func near(cat_cell: Vector2i, granny_cell: Vector2i) -> bool:
	return maxi(absi(cat_cell.x - granny_cell.x), absi(cat_cell.y - granny_cell.y)) <= LOOK_RADIUS


## 1..PET_LINES: which CAT_PET_<n> line to say, never the same as `last` twice in a row.
static func pet_line(r: RandomNumberGenerator, last: int) -> int:
	var n := r.randi_range(1, PET_LINES)
	if n == last:
		n = n % PET_LINES + 1
	return n
