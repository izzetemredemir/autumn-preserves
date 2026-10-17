class_name Grandkid
extends Node2D
## FESTIVAL · Mia or Leo, visiting Granny's garden on the Harvest Festival. A child villager (market villager v2,
## child archetype) dressed in the colours of their portrait. This node only shows and moves the child: run along a
## path of cells, stand, look about, wave (calling hop) and hop when tapped. Grandkids decides where to go.
## Position is the feet (bottom-centre of the cell), moved on whole pixels. Cosmetic: nothing is saved.

signal arrived

const Villager := preload("res://scenes/market/villager.gd")
const TILE := 16
const RUN_SEC := 0.19  ## per cell
const WALK_FPS := 10.0
const IDLE_FPS := 2.0
const WAVE_FPS := 5.0
const HOP_PX := 3

var kid := "mia"
var cell := Vector2i.ZERO
var look: Dictionary = {}

var _fig: Node2D
var _path: Array[Vector2i] = []
var _exact := Vector2.ZERO
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _step_t := 0.0
var _view := "front"
var _anim := "idle"
var _t := 0.0
var _wave_left := 0.0
var _hop_left := 0.0
var _rng := RandomNumberGenerator.new()


## Portrait colours: Mia copper pigtails, mustard jumper, red skirt; Leo brown mop, brown jacket, green scarf.
static func look_of(id: String) -> Dictionary:
	var base := {"arch": "child", "hat": "none", "glasses": false, "beard": false, "moustache": false, "carry": "none",
		"cane": false, "umbrella": false, "outfit": ""}
	var l: Dictionary = base.duplicate()
	if id == "leo":
		l.merge({"fem": false, "skirt": false, "hair": "tousled", "scarf": true, "colors": {
			"skin": ["c58845", "e19064", "e5bd7f", "c94d2e"], "hair": ["3d1f29", "50361e", "83571e"],
			"coat": ["50361e", "83571e", "b66813"], "lower": ["314524", "53612e", "747c37"], "shoes": ["23282a", "49423d"],
			"accent": ["314524", "53612e", "747c37"], "hat": ["314524", "53612e", "747c37"], "shirt": ["b9a697", "f2d9c5"]}}, true)
	else:
		l.merge({"fem": true, "skirt": true, "hair": "pigtails", "scarf": false, "colors": {
			"skin": ["e19064", "e5bd7f", "f2d9c5", "c94d2e"], "hair": ["62272c", "a22512", "c94d2e"],
			"coat": ["9b8039", "b1a13d", "c5bf3f"], "lower": ["3d1f29", "62272c", "a22512"], "shoes": ["3d1f29", "50361e"],
			"accent": ["a22512", "c94d2e", "e19064"], "hat": ["62272c", "a22512", "c94d2e"], "shirt": ["b9a697", "f2d9c5"]}}, true)
	return l


func setup(id: String, start: Vector2i, rng_seed: int) -> void:
	kid = id
	name = id.capitalize()
	look = look_of(id)
	_rng.seed = rng_seed
	_fig = Villager.new()
	add_child(_fig)
	_fig.setup(look)
	teleport(start)


static func feet(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE + TILE / 2, (c.y + 1) * TILE)


func teleport(c: Vector2i) -> void:
	cell = c
	_path.clear()
	_exact = feet(c)
	position = _exact


## Runs along `cells` (each next to the one before; the first is the next step). Replaces any path in progress.
func run(cells: Array) -> void:
	_path.clear()
	for c in cells:
		_path.append(c)
	_wave_left = 0.0
	if not _path.is_empty() and _step_t <= 0.0:
		_next_step()


func is_running() -> bool:
	return _step_t > 0.0 or not _path.is_empty()


func stop() -> void:
	_path.clear()


## Calls out to Granny: hops and waves for `sec` (front view, the talking pose with the hand up).
func wave(sec := 1.6) -> void:
	stop()
	_wave_left = sec


func is_waving() -> bool:
	return _wave_left > 0.0


## A happy hop (tapped, or a leaf caught).
func hop() -> void:
	_hop_left = 0.3


func face_towards(p: Vector2) -> void:
	var d := p - position
	if absf(d.x) > absf(d.y):
		_view = "right" if d.x > 0 else "left"
	else:
		_view = "front" if d.y >= 0 else "back"


## The way the child last ran (or faces): one of the four grid directions.
func dir() -> Vector2i:
	match _view:
		"right":
			return Vector2i.RIGHT
		"left":
			return Vector2i.LEFT
		"back":
			return Vector2i.UP
	return Vector2i.DOWN


## Click/tap area in world px (the child is about 14 x 32).
func hit_rect() -> Rect2:
	return Rect2(position + Vector2(-8, -34), Vector2(16, 34))


## World point just above the head, for a bubble.
func top() -> Vector2:
	return position + Vector2(0, -36)


func _process(delta: float) -> void:
	_t += delta
	var lift := 0
	if _step_t > 0.0:
		_step_t = maxf(_step_t - delta, 0.0)
		_exact = _to.lerp(_from, _step_t / RUN_SEC)
		if _step_t <= 0.0:
			_exact = _to
			if not _path.is_empty():
				_next_step()
			else:
				arrived.emit()
	if _wave_left > 0.0:
		_wave_left -= delta
		var f := int(_t * WAVE_FPS) % 2
		lift = HOP_PX if f == 0 else 0
		_show("front", "talk" if f == 0 else "idle", 0)
	elif _step_t > 0.0:
		_show(_view, "walk", int(_t * WALK_FPS))
	else:
		_show(_view if _view != "back" else "front", "idle", int(_t * IDLE_FPS))
	if _hop_left > 0.0:
		_hop_left -= delta
		lift = maxi(lift, roundi(sin((0.3 - _hop_left) / 0.3 * PI) * 4.0))
	position = _exact.round()
	_fig.position = Vector2(0, -lift)


func _next_step() -> void:
	var c: Vector2i = _path.pop_front()
	var d := c - cell
	if d.x != 0:
		_view = "right" if d.x > 0 else "left"
	else:
		_view = "front" if d.y > 0 else "back"
	cell = c
	_from = _exact
	_to = feet(c)
	_step_t = RUN_SEC


func _show(view: String, anim: String, frame: int) -> void:
	if _fig != null:
		_fig.show_pose(view, anim, frame)
