class_name RainOverlay
extends CanvasLayer
## Pixel rain (GD-HUD): integer-positioned 1 px drops, visible only when weather == "rainy".

const DROPS := 70
const SIZE := Vector2(480, 270)
const COLORS: Array[Color] = [Color("567c7d"), Color("738c7a"), Color("b4b3a0")]

var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _col := PackedInt32Array()
var _canvas: Control


func _ready() -> void:
	layer = 5
	var rng := RandomNumberGenerator.new()
	rng.seed = 1  # cosmetic only; game rules never read this
	for i in DROPS:
		_x.append(rng.randf() * SIZE.x)
		_y.append(rng.randf() * SIZE.y)
		_speed.append(rng.randf_range(160.0, 260.0))
		_col.append(rng.randi() % COLORS.size())
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_rain)
	add_child(_canvas)
	GameState.changed.connect(func(_k: PackedStringArray) -> void: _update_visible())
	_update_visible()


func _update_visible() -> void:
	visible = String(GameState.data.get("weather", "sunny")) == "rainy"
	set_process(visible)


func _process(delta: float) -> void:
	for i in DROPS:
		_y[i] += _speed[i] * delta
		_x[i] -= _speed[i] * delta * 0.15
		if _y[i] > SIZE.y:
			_y[i] -= SIZE.y + 6.0
		if _x[i] < 0.0:
			_x[i] += SIZE.x
	_canvas.queue_redraw()


func _draw_rain() -> void:
	for i in DROPS:
		_canvas.draw_rect(Rect2(floorf(_x[i]), floorf(_y[i]), 1, 3), COLORS[_col[i]])
