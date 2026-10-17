class_name GardenCrow
extends Node2D
## GARDEN-LIFE · A crow on a perch of garden_props.json (the scarecrow, the truck roof, the hen house ridge). Sits,
## caws now and then, flies off when Granny comes near and lands again once she has been away a while. Its node stands
## at its prop's feet (+1) so the y-sorted layer draws it over the prop and behind Granny when she is in front; the
## sprite sits up on the perch.
## Art: garden_crow.png 10x8 sit, caw, flap x2, facing right, feet at the bottom-centre. Whole pixels, never rotated.

const SHEET := "res://assets/sprites/garden/garden_crow.png"
const SIZE := Vector2i(10, 8)
const FLEE_PX := 44.0
const BACK_PX := 88.0  ## Granny this far for BACK_SEC: the crow comes back
const BACK_SEC := 6.0
const FLY_SEC := 1.4

var state := "sit"
var perch := Vector2.ZERO  ## feet on the perch, garden px

var _sprite: Sprite2D
var _t := 0.0
var _wait := 0.0
var _away := 0.0
var _dir := 1.0
var _off := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


## `p_perch`: feet on the scarecrow; `sort_y`: the scarecrow's feet y.
func setup(p_perch: Vector2i, sort_y: int, rng_seed: int) -> void:
	_rng.seed = rng_seed
	perch = Vector2(p_perch)
	position = Vector2(perch.x, sort_y + 1)
	_dir = -1.0 if _rng.randf() < 0.5 else 1.0
	_wait = _rng.randf_range(2.0, 8.0)
	if ResourceLoader.exists(SHEET):
		_sprite = Sprite2D.new()
		_sprite.texture = load(SHEET)
		_sprite.centered = false
		_sprite.hframes = 4
		add_child(_sprite)
	_place()


## One step; `granny` is her feet. True on the frame the crow takes off (the garden caws once for the flock).
func tick(delta: float, granny: Vector2) -> bool:
	_t += delta
	var d := granny.distance_to(Vector2(perch.x, position.y))
	var took_off := false
	match state:
		"sit", "caw":
			if d < FLEE_PX:
				_dir = 1.0 if granny.x < perch.x else -1.0
				_go("fly")
				took_off = true
			elif state == "caw" and _t > 0.5:
				_go("sit")
			else:
				_wait -= delta
				if _wait <= 0.0:
					_wait = _rng.randf_range(4.0, 11.0)
					_go("caw")
		"fly":
			var k := minf(_t / FLY_SEC, 1.0)
			_off = Vector2(_dir * 96.0 * k, -72.0 * k * (2.0 - k))
			if k >= 1.0:
				_away = 0.0
				_go("gone")
		"gone":
			_away = _away + delta if d > BACK_PX else 0.0
			if _away >= BACK_SEC:
				_dir = -_dir
				_go("land")
		"land":
			var k := minf(_t / FLY_SEC, 1.0)
			var u := 1.0 - k
			_off = Vector2(-_dir * 96.0 * u, -72.0 * u * (2.0 - u))
			if k >= 1.0:
				_off = Vector2.ZERO
				_go("sit")
	visible = state != "gone"
	_place()
	return took_off


func _go(s: String) -> void:
	state = s
	_t = 0.0


func _frame() -> int:
	match state:
		"caw":
			return 1
		"fly", "land":
			return 2 + int(_t / 0.1) % 2
	return 0


func _place() -> void:
	if _sprite == null:
		return
	_sprite.position = (perch + _off).round() - position - Vector2(floori(SIZE.x * 0.5), SIZE.y)
	_sprite.frame = _frame()
	_sprite.flip_h = _dir < 0.0  # drawn facing right
