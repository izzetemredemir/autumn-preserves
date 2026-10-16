class_name Granny
extends Node2D
## Granny Tonty, the walking player (GD-WILD). Tile-by-tile movement that glides smoothly and is drawn on
## whole pixels; keyboard (move_* actions) and tap-to-walk (AStarGrid2D). The scene owns the map and the
## objects, Granny only asks it where she may stand:
##   granny.setup(Vector2i(w, h), func(cell: Vector2i) -> bool: return ..., start_cell)
##   granny.interact_requested.connect(...)    # `interact` key, with the tile she faces
##   granny.approach(object_cell, on_arrive)   # walk next to a thing, face it, then on_arrive.call()
## Position is the feet: bottom-centre of the current tile (sprite pivot 8,31, art-bible §3.2).
## The look lives in the Body child (granny_body.gd): ART-02 strips, or a gray box until they exist.

signal stepped(cell: Vector2i)  ## entered a new tile
signal interact_requested(cell: Vector2i)  ## `interact` pressed; `cell` is the tile she faces

const TILE := 16
const DIRS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]

@export var speed := 72.0  ## world px per second

var input_enabled := true
var facing := Vector2i.DOWN

var _size := Vector2i.ONE
var _walkable: Callable
var _cell := Vector2i.ZERO
var _to_cell := Vector2i.ZERO
var _moving := false
var _exact := Vector2.ZERO
var _path: Array[Vector2i] = []
var _on_arrive := Callable()
var _astar := AStarGrid2D.new()
var _bump: Tween

@onready var body: Node2D = $Body


## `walkable(cell) -> bool` is called for in-bounds cells only.
func setup(grid_size: Vector2i, walkable: Callable, start_cell: Vector2i, face := Vector2i.DOWN) -> void:
	_size = grid_size
	_walkable = walkable
	_astar.region = Rect2i(Vector2i.ZERO, grid_size)
	_astar.cell_size = Vector2(TILE, TILE)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()
	teleport(start_cell, face)


static func cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, (cell.y + 1) * TILE)


## The tile under a world point (a tap), not under the feet.
static func point_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func teleport(cell: Vector2i, face := Vector2i.DOWN) -> void:
	_cell = cell
	_to_cell = cell
	_moving = false
	stop()
	_exact = cell_to_pos(cell)
	position = _exact
	_face(face)


func stop() -> void:
	_path.clear()
	_on_arrive = Callable()


func current_cell() -> Vector2i:
	return _cell


## The tile Granny is in or is stepping into.
func dest_cell() -> Vector2i:
	return _to_cell if _moving else _cell


func facing_cell() -> Vector2i:
	return dest_cell() + facing


func is_moving() -> bool:
	return _moving or not _path.is_empty()


func can_stand(cell: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, _size).has_point(cell) and _walkable.is_valid() and bool(_walkable.call(cell))


## Walks to `cell` along an A* path; `on_arrive` runs once there. False when there is no way.
func walk_to(cell: Vector2i, on_arrive := Callable()) -> bool:
	var path := find_path(dest_cell(), cell)
	if path.is_empty():
		return false
	_follow(path, on_arrive)
	return true


## Walks to the closest free side of `target`, turns to face it, then runs `on_arrive`.
## Works for blocking things (trees) and for things lying on walkable tiles. False when no side is reachable.
func approach(target: Vector2i, on_arrive := Callable()) -> bool:
	var start := dest_cell()
	var best: Array[Vector2i] = []
	for d in DIRS:
		var side := target + d
		if side != start and not can_stand(side):
			continue
		var p := find_path(start, side)
		if not p.is_empty() and (best.is_empty() or p.size() < best.size()):
			best = p
	if best.is_empty():  # boxed in: stand on it instead
		if start == target:
			var here: Array[Vector2i] = [start]
			_follow(here, on_arrive)
			return true
		best = find_path(start, target)
		if best.is_empty():
			return false
	_follow(best, _arrive_facing.bind(target, on_arrive))
	return true


## A* over the injected walkability, from `from` (always allowed) to `to`. Includes both ends; [] if none.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	var region := Rect2i(Vector2i.ZERO, _size)
	if not region.has_point(from) or not region.has_point(to):
		return none
	if to != from and not can_stand(to):
		return none
	for y in _size.y:
		for x in _size.x:
			var c := Vector2i(x, y)
			_astar.set_point_solid(c, not can_stand(c))
	_astar.set_point_solid(from, false)
	return _astar.get_id_path(from, to)


## Action feedback: the sprite's one-shot animation ("shake" | "pick"), or a squash on the gray box.
func act(action: String) -> void:
	if bool(body.call("has_sprite")):
		body.call("act", action)
	else:
		bump()


## Short squash on the body.
func bump() -> void:
	if _bump != null and _bump.is_valid():
		_bump.kill()
	body.scale = Vector2(1.2, 0.8)
	_bump = create_tween()
	_bump.tween_property(body, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if input_enabled and event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		interact_requested.emit(facing_cell())


func _process(delta: float) -> void:
	var budget := speed * delta
	for i in 3:  # at most a few tile boundaries per frame
		if not _moving and not _start_step():
			break
		var target := cell_to_pos(_to_cell)
		var dist := _exact.distance_to(target)
		if dist > budget:
			_exact = _exact.move_toward(target, budget)
			break
		budget -= dist
		_exact = target
		_moving = false
		_cell = _to_cell
		stepped.emit(_cell)
	position = _exact.round()
	body.set("walking", _moving)
	if not _moving and _path.is_empty() and _on_arrive.is_valid():
		var cb := _on_arrive
		_on_arrive = Callable()
		cb.call()


func _start_step() -> bool:
	var dir := _input_dir() if input_enabled else Vector2i.ZERO
	if dir != Vector2i.ZERO:
		stop()  # keys win over a tapped path
		_face(dir)
		return _try_step(dir)
	if _path.is_empty():
		return false
	var next: Vector2i = _path.pop_front()
	var step := next - _cell
	if absi(step.x) + absi(step.y) != 1:
		stop()
		return false
	_face(step)
	if not _try_step(step):
		stop()  # something appeared in the way
		return false
	return true


func _try_step(dir: Vector2i) -> bool:
	var next := _cell + dir
	if not can_stand(next):
		return false
	_to_cell = next
	_moving = true
	return true


func _input_dir() -> Vector2i:
	var x := int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left"))
	var y := int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up"))
	if x != 0 and y != 0:  # both held: keep the axis she is already walking on
		if facing.x != 0:
			y = 0
		else:
			x = 0
	return Vector2i(x, y)


func _follow(path: Array[Vector2i], on_arrive: Callable) -> void:
	_path = path.duplicate()
	if not _path.is_empty() and _path[0] == dest_cell():
		_path.pop_front()
	_on_arrive = on_arrive


func _arrive_facing(target: Vector2i, on_arrive: Callable) -> void:
	_face(target - _cell)
	if on_arrive.is_valid():
		on_arrive.call()


func _face(dir: Vector2i) -> void:
	if absi(dir.x) + absi(dir.y) != 1:
		return
	facing = dir
	if body != null:
		body.set("facing", dir)
