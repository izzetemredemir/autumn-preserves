class_name KneadRules
extends RefCounted
## MG-KNEAD pure helpers (design 11.5): rhythm judging, trace hits, star maths. No autoloads.

const PERFECT_MS := 80.0
const GOOD_MS := 160.0
const HIT_PX := 4.0
const POINTS := 12
const MAX_SQUASH := 6


## Judge a press by its timing error in milliseconds.
static func judge(err_ms: float) -> String:
	var e := absf(err_ms)
	if e <= PERFECT_MS:
		return "perfect"
	if e <= GOOD_MS:
		return "good"
	return "miss"


## Same thresholds as press (11.4): Perfect >= 70% -> 3; Perfect+Good >= 60% -> 2; else 1.
static func rhythm_stars(perfect: int, good: int, total: int) -> int:
	if total <= 0:
		return 1
	if float(perfect) / total >= 0.7:
		return 3
	if float(perfect + good) / total >= 0.6:
		return 2
	return 1


## Crimp stars by points hit: >= 80% -> 3, >= 55% -> 2, else 1.
static func trace_stars(hits: int, total: int = POINTS) -> int:
	if total <= 0:
		return 1
	var r := float(hits) / total
	if r >= 0.8:
		return 3
	if r >= 0.55:
		return 2
	return 1


## Average of both parts, rounded up.
static func combine_stars(a: int, b: int) -> int:
	return clampi(ceili((a + b) / 2.0), 1, 3)


static func point_hit(point: Vector2, pos: Vector2, radius: float = HIT_PX) -> bool:
	return point.distance_to(pos) <= radius


## Distance from p to segment a-b (so fast drags do not skip points).
static func segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## n integer points evenly around a circle, starting at the top.
static func ring_points(center: Vector2, radius: float, n: int = POINTS) -> Array[Vector2]:
	return ellipse_points(center, radius, radius, n)


## n integer points evenly (by angle) around an ellipse, starting at the top: the bread loaf's outline.
static func ellipse_points(center: Vector2, rx: float, ry: float, n: int = POINTS) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in n:
		var a := -PI / 2.0 + TAU * i / n
		out.append((center + Vector2(cos(a) * rx, sin(a) * ry)).round())
	return out


## Bread part 2 ("shape the loaf"): the dough's radii after `hits` of `total` outline points, from a round ball
## (LOAF_START) to a long loaf (LOAF_END) that sits just inside the dotted outline.
const LOAF_START := Vector2i(40, 34)
const LOAF_END := Vector2i(86, 38)


static func loaf_radii(hits: int, total: int = POINTS) -> Vector2i:
	var t := clampf(float(hits) / maxf(total, 1), 0.0, 1.0)
	return Vector2i(roundi(lerpf(LOAF_START.x, LOAF_END.x, t)), roundi(lerpf(LOAF_START.y, LOAF_END.y, t)))


## Score marks on the loaf: one per third of the outline traced (0..3).
static func loaf_cuts(hits: int, total: int = POINTS) -> int:
	return clampi(floori(3.0 * hits / maxf(total, 1)), 0, 3)


## Dough squash step: one per good (Perfect/Good) press, capped.
static func squash_step(good_presses: int) -> int:
	return clampi(good_presses, 0, MAX_SQUASH)


## Beat side: even index = left (-1), odd = right (1).
static func beat_side(i: int) -> int:
	return -1 if i % 2 == 0 else 1
