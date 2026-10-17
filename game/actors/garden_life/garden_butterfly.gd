class_name GardenButterfly
extends Node2D
## GARDEN-LIFE · A late butterfly over a flower clump (CritterRules.garden "butterfly" placement): flutters in a loose
## loop above the flowers, lifts away while Granny is close, drifts back after. Drawn in palette colours (5x4, two
## wing frames), whole pixels. Not saved, no gameplay.

const SHY_PX := 30.0
const C_INK := Color("3d1f29")
## Wing colours by "tint": [outer, inner].
const TINTS := [[Color("f2d9c5"), Color("e19064")], [Color("e5bd7f"), Color("c94d2e")]]

var home := Vector2.ZERO  ## above the flowers, garden px

var _t := 0.0
var _ph := 0.0
var _shy := 0.0  ## 0 at the flowers .. 1 lifted away
var _tint := 0
var _rng := RandomNumberGenerator.new()


func setup(info: Dictionary, rng_seed: int) -> void:
	_rng.seed = rng_seed
	var c: Vector2i = info.cell
	home = Vector2(c.x * 16 + 8, c.y * 16 + 4)
	_tint = int(info.get("tint", 0)) % TINTS.size()
	_ph = _rng.randf_range(0.0, TAU)
	position = home


func tick(delta: float, granny: Vector2) -> void:
	_t += delta
	var near := granny.distance_to(home + Vector2(0, 10)) < SHY_PX
	_shy = clampf(_shy + (delta * 1.2 if near else -delta * 0.35), 0.0, 1.0)
	var loop := Vector2(sin(_t * 0.8 + _ph) * 9.0, sin(_t * 1.7 + _ph) * 4.0 - 4.0)
	position = (home + loop + Vector2(14.0, -26.0) * _shy).round()
	queue_redraw()


func _draw() -> void:
	var open := int(_t / 0.11 + _ph) % 2 == 0
	var outer: Color = TINTS[_tint][0]
	var inner: Color = TINTS[_tint][1]
	draw_rect(Rect2(0, -3, 1, 3), C_INK)  # body
	if open:
		for s in [-1, 1]:
			var x := -2 if s < 0 else 1
			draw_rect(Rect2(x, -4, 2, 2), outer)
			draw_rect(Rect2(x + (1 if s < 0 else 0), -3, 1, 1), inner)
			draw_rect(Rect2(x + (1 if s < 0 else 0), -2, 1, 1), outer)
			draw_rect(Rect2(x + (0 if s < 0 else 1), -4, 1, 1), C_INK)
	else:
		draw_rect(Rect2(-1, -5, 1, 2), outer)
		draw_rect(Rect2(1, -5, 1, 2), outer)
