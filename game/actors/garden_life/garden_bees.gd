class_name GardenBees
extends Node2D
## GARDEN-LIFE · A hive's bees: a few 2x2 bees hovering at the hive door and drifting to the nearest flower clumps and
## back. One node draws them all (cheap). Whole-pixel positions; bees stay in on rainy days (the garden doesn't make
## them). Art: garden_bee.png 2x2, two wing frames (a gold-and-ink stand-in until it lands). Not saved.

const SHEET := "res://assets/sprites/garden/garden_bee.png"
const FLY_PX := 20.0
const HOVER := Vector2(8.0, 4.0)

var door := Vector2.ZERO  ## where they hover at home (just in front of the hive), garden px
var flowers: Array[Vector2] = []

var _tex: Texture2D
var _bees: Array[Dictionary] = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()


## `p_door`: the hive door; `p_flowers`: flower clumps to visit (garden px); `n` bees.
func setup(p_door: Vector2, p_flowers: Array[Vector2], n: int, rng_seed: int) -> void:
	door = p_door
	flowers = p_flowers
	_rng.seed = rng_seed
	_tex = load(SHEET) if ResourceLoader.exists(SHEET) else null
	for i in n:
		var ph := _rng.randf_range(0.0, TAU)
		_bees.append({"pos": door, "anchor": door, "ph": ph, "next": _rng.randf_range(0.5, 4.0), "fly": false})


func _process(delta: float) -> void:
	_t += delta
	for b in _bees:
		if bool(b.fly):
			var to: Vector2 = (b.anchor as Vector2) + _hover(b)
			var p: Vector2 = b.pos
			var side := (to - p).orthogonal().normalized() * sin(_t * 9.0 + float(b.ph)) * 0.6
			b.pos = p.move_toward(to, FLY_PX * delta) + side
			if (b.pos as Vector2).distance_to(to) < 1.5:
				b.fly = false
				b.next = _rng.randf_range(1.0, 3.0)
		else:
			b.pos = (b.anchor as Vector2) + _hover(b)
			b.next = float(b.next) - delta
			if float(b.next) <= 0.0:
				var home := (b.anchor as Vector2) == door
				b.anchor = flowers[_rng.randi_range(0, flowers.size() - 1)] if home and not flowers.is_empty() else door
				b.fly = true
	queue_redraw()


## A hovering bee's little figure-eight around its anchor.
func _hover(b: Dictionary) -> Vector2:
	var ph := float(b.ph)
	return Vector2(sin(_t * 2.6 + ph) * HOVER.x, sin(_t * 4.1 + ph * 2.0) * HOVER.y - 4.0)


func _draw() -> void:
	if _tex == null:
		return
	var f := int(_t / 0.08) % 2
	for b in _bees:
		var p: Vector2 = (b.pos as Vector2).round()
		draw_texture_rect_region(_tex, Rect2(p, Vector2(2, 2)), Rect2(f * 2, 0, 2, 2))
