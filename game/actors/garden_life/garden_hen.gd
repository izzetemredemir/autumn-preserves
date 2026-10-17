class_name GardenHen
extends Node2D
## GARDEN-LIFE · A hen (or the rooster) in the run. Walks its seeded loop (GardenLifeRules.route: walk, stop, peck,
## scratch), scatters flapping when Granny comes to the fence and goes back to pecking after a moment; the rooster
## crows when the garden asks. Moves on whole pixels, never rotated or scaled. Position is the feet.
## Art (ART-GARDEN2, facing right): garden_hen.png 12x12 idle, walk x2, peck x2, flap x2, frames 0-6 rust and 7-13
## cream; garden_rooster.png 12x14 idle, crow x2, walk x2. Feet at the bottom-centre pixel.

const HEN_SHEET := "res://assets/sprites/garden/garden_hen.png"
const ROOSTER_SHEET := "res://assets/sprites/garden/garden_rooster.png"
const HEN_SIZE := Vector2i(12, 12)
const ROOSTER_SIZE := Vector2i(12, 14)
## Frames per pose and seconds per frame.
const HEN_POSES := {"idle": [[0], 1.0], "walk": [[1, 2], 0.16], "peck": [[3, 4, 3, 0], 0.14],
	"scratch": [[1, 0, 2, 0], 0.12], "flap": [[5, 6], 0.08], "crow": [[0], 1.0]}
const ROOSTER_POSES := {"idle": [[0], 1.0], "walk": [[3, 4], 0.16], "peck": [[0, 3], 0.2],
	"scratch": [[3, 0, 4, 0], 0.12], "flap": [[3, 4], 0.08], "crow": [[1, 2, 2, 1], 0.22]}
const WALK_PX := 13.0  ## px per second
const RUN_PX := 44.0
const CALM_SEC := Vector2(0.8, 1.6)
const CROW_SEC := 1.6
const HEN_FRAMES := 7  ## per colour

var kind := "hen"
var variant := 0
var route: Array = []
var step := 0
var area := Rect2i()
var avoid: Array = []
var pose := "idle"

var _sprite: Sprite2D
var _poses: Dictionary
var _size := HEN_SIZE
var _pos := Vector2.ZERO  ## exact feet
var _left := 0.0  ## seconds left of the current act (after arriving)
var _arrived := false
var _scared_to := Vector2i(-1, -1)
var _calm := 0.0
var _crow := 0.0
var _t := 0.0
var _dir := 1.0  ## 1 faces right (as drawn), -1 left
var _rng := RandomNumberGenerator.new()


func setup(p_kind: String, p_variant: int, p_route: Array, p_area: Rect2i, p_avoid: Array, rng_seed: int) -> void:
	kind = p_kind
	variant = p_variant
	route = p_route
	area = p_area
	avoid = p_avoid
	_rng.seed = rng_seed
	_poses = ROOSTER_POSES if kind == "rooster" else HEN_POSES
	_size = ROOSTER_SIZE if kind == "rooster" else HEN_SIZE
	_pos = Vector2(GardenLifeRules.start(route))
	step = _rng.randi_range(0, maxi(0, route.size() - 1))  # the flock doesn't move in step
	var path := ROOSTER_SHEET if kind == "rooster" else HEN_SHEET
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if tex != null:
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		_sprite.centered = false
		_sprite.hframes = maxi(1, int(tex.get_width() / _size.x))
		_sprite.position = Vector2(-floori(_size.x * 0.5), -_size.y)
		add_child(_sprite)
	position = _pos.round()


func is_scared() -> bool:
	return _scared_to.x >= 0 or _calm > 0.0


## Startled by Granny at `granny` (garden px): run and flap away from her inside the run.
func scatter(granny: Vector2) -> void:
	_scared_to = GardenLifeRules.scatter(Vector2i(_pos.round()), granny, area, avoid)
	_calm = 0.0
	_crow = 0.0
	if _scared_to == Vector2i(_pos.round()):
		_scared_to = Vector2i(-1, -1)
		_calm = _rng.randf_range(CALM_SEC.x, CALM_SEC.y)
	_set_pose("flap")


## The rooster's morning call (the garden plays the sound).
func crow() -> void:
	_crow = CROW_SEC
	_set_pose("crow")


## A little peck now (the garden plays the cluck).
func cluck() -> void:
	if not is_scared() and _crow <= 0.0:
		_arrived = true
		_left = 0.6
		_set_pose("peck")


func _process(delta: float) -> void:
	_t += delta
	if _scared_to.x >= 0:
		if _move(Vector2(_scared_to), RUN_PX, delta):
			_scared_to = Vector2i(-1, -1)
			_calm = _rng.randf_range(CALM_SEC.x, CALM_SEC.y)
			_set_pose("idle")
	elif _calm > 0.0:
		_calm -= delta
		if _calm <= 0.0:
			_arrived = false  # back to the loop: walk to this step's spot first
	elif _crow > 0.0:
		_crow -= delta
	elif not route.is_empty():
		_follow(delta)
	position = _pos.round()
	_draw_frame()


func _follow(delta: float) -> void:
	var s: Dictionary = route[step]
	if not _arrived:
		_set_pose("walk")
		if _move(Vector2(s.to), WALK_PX, delta):
			_arrived = true
			_left = float(s.sec)
			_set_pose(String(s.act) if String(s.act) != "walk" else "idle")
		return
	_left -= delta
	if _left <= 0.0:
		step = (step + 1) % route.size()
		_arrived = false


## Moves the feet toward `to` at `speed`; true when there.
func _move(to: Vector2, speed: float, delta: float) -> bool:
	if absf(to.x - _pos.x) >= 1.0:
		_dir = 1.0 if to.x > _pos.x else -1.0
	_pos = _pos.move_toward(to, speed * delta)
	return _pos.distance_to(to) < 0.5


func _set_pose(p: String) -> void:
	if p != pose:
		pose = p
		_t = 0.0


func _frame() -> int:
	var a: Array = _poses.get(pose, _poses.idle)
	var seq: Array = a[0]
	return int(seq[int(_t / float(a[1])) % seq.size()])


func _draw_frame() -> void:
	if _sprite == null:
		return
	var offset := variant * HEN_FRAMES if kind == "hen" and _sprite.hframes >= HEN_FRAMES * 2 else 0
	_sprite.frame = clampi(offset + _frame(), 0, _sprite.hframes - 1)
	_sprite.flip_h = _dir < 0.0  # drawn facing right
