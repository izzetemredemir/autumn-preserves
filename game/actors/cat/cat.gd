class_name Cat
extends Node2D
## P2-CAT · Granny's orange tabby (art: assets/sprites/cat/, ported from the old project). Lives in the garden:
## naps at its spot of the day, wakes to look at Granny when she is near, wanders a few cells now and then, purrs
## when petted. Draws and moves only; the spot choice is CatRules. Position is the feet (bottom-centre of the cell).

signal petted

const TILE := 16
const SHEETS := {
	"idle": [preload("res://assets/sprites/cat/cat_idle.png"), 4, 0.45],
	"look": [preload("res://assets/sprites/cat/cat_look.png"), 3, 0.5],
	"sleep": [preload("res://assets/sprites/cat/cat_sleep.png"), 2, 1.0],
	"purr": [preload("res://assets/sprites/cat/cat_purr.png"), 4, 0.22],
}
const HEART := preload("res://assets/sprites/cat/cat_heart.png")
const FRAME := 24
const WALK_SEC_PER_CELL := 0.3
const PURR_SEC := 2.2

var cell := Vector2i.ZERO  ## the cell it sits on (its end cell while walking)
var home := Vector2i.ZERO
var pose := ""
var near_granny := false
var wander_walkable := Callable()  ## (cell) -> bool, set by the garden

var _sprite := Sprite2D.new()
var _heart := Sprite2D.new()
var _t := 0.0
var _purr_left := 0.0
var _wander_in := 12.0
var _walk: Tween
var _rng := RandomNumberGenerator.new()


func setup(rng_seed: int, home_cell: Vector2i) -> void:
	_rng.seed = rng_seed
	home = home_cell
	cell = home_cell
	position = _feet(home_cell)
	_sprite.centered = false
	_sprite.position = Vector2(-FRAME / 2, -FRAME)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_heart.texture = HEART
	_heart.region_enabled = true
	_heart.region_rect = Rect2(8, 0, 8, 8)
	_heart.centered = true
	_heart.position = Vector2(0, -FRAME - 4)
	_heart.visible = false
	_heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_heart)
	_wander_in = _rng.randf_range(10.0, 25.0)
	_set_pose("sleep")


static func _feet(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE + TILE / 2, (c.y + 1) * TILE)


func is_walking() -> bool:
	return _walk != null and _walk.is_running()


func is_purring() -> bool:
	return _purr_left > 0.0


## Click/tap area in world px (at least 16x16).
func hit_rect() -> Rect2:
	return Rect2(position + Vector2(-FRAME / 2, -FRAME), Vector2(FRAME, FRAME))


## World point just above the cat, for the line it gets.
func top() -> Vector2:
	return position + Vector2(0, -FRAME - 6)


## Petted: purr and show a heart for a moment. The garden plays the sound and says the line.
func pet() -> void:
	_purr_left = PURR_SEC
	_heart.visible = true
	_heart.position.y = -FRAME - 4
	var tw := create_tween()
	tw.tween_property(_heart, "position:y", -FRAME - 10.0, PURR_SEC)
	_set_pose("purr")
	petted.emit()


func _process(delta: float) -> void:
	_t += delta
	var sheet: Array = SHEETS[pose]
	_sprite.frame = int(_t / float(sheet[2])) % int(sheet[1])
	if _purr_left > 0.0:
		_purr_left -= delta
		if _purr_left <= 0.0:
			_heart.visible = false
			_settle()
		return
	if is_walking():
		return
	_settle()
	_wander_in -= delta
	if _wander_in <= 0.0 and not near_granny and wander_walkable.is_valid():
		_wander()


## Picks the resting pose: look while Granny is near, sleep at home, sit otherwise.
func _settle() -> void:
	_set_pose("look" if near_granny else ("sleep" if cell == home else "idle"))


func _set_pose(p: String) -> void:
	if p == pose:
		return
	pose = p
	_t = 0.0
	var sheet: Array = SHEETS[p]
	_sprite.texture = sheet[0]
	_sprite.hframes = int(sheet[1])
	_sprite.frame = 0


## Away from home, or back to it when it is already out.
func _wander() -> void:
	_wander_in = _rng.randf_range(15.0, 35.0)
	var target := home
	if cell == home:
		target = CatRules.wander_cell(home, _rng, wander_walkable)
	if target == cell:
		return
	var dist := maxi(absi(target.x - cell.x), absi(target.y - cell.y))
	cell = target
	_set_pose("idle")
	_walk = create_tween()
	_walk.tween_property(self, "position", _feet(target), dist * WALK_SEC_PER_CELL)
