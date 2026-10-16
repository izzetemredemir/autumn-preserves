class_name FollowCamera
extends Camera2D
## Camera for walked scenes (tech-spec §7): keeps `target` centred on whole pixels, clamped to `bounds`
## (world px; a map smaller than the screen is centred). No zoom, no smoothing. Shake moves `offset` in whole pixels.

var target: Node2D
var bounds := Rect2i()

var _shake_left := 0.0
var _shake_px := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	position_smoothing_enabled = false
	process_priority = 100  # after whatever moves the target
	_rng.randomize()


func _process(delta: float) -> void:
	snap()
	if _shake_left > 0.0:
		_shake_left -= delta
		offset = Vector2(_rng.randi_range(-_shake_px, _shake_px), _rng.randi_range(-_shake_px, _shake_px))
		if _shake_left <= 0.0:
			offset = Vector2.ZERO


func snap() -> void:
	if target == null or not is_instance_valid(target):
		return
	var view := Vector2i(get_viewport_rect().size)
	var t := Vector2i(target.global_position.round())
	global_position = Vector2(_axis(t.x, view.x, bounds.position.x, bounds.size.x),
		_axis(t.y, view.y, bounds.position.y, bounds.size.y))


func shake(px := 2, seconds := 0.25) -> void:
	_shake_px = px
	_shake_left = seconds


static func _axis(t: int, view: int, lo: int, size: int) -> int:
	if size <= 0:
		return t - floori(view * 0.5)
	if size <= view:
		return lo - floori((view - size) * 0.5)
	return clampi(t - floori(view * 0.5), lo, lo + size - view)
