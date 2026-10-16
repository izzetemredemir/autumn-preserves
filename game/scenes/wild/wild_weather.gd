class_name WildWeather
extends CanvasLayer
## CALENDAR-WEATHER · Weather over the wild map (spec §7.10). Cosmetic only: its own RandomNumberGenerator, never game
## state. "windy": palette leaves tumbling across the screen in gusts and a few gust streaks, on whole pixels. "foggy": fog.gdshader, a
## dithered palette fog closing in around `target` (Granny), so the view shrinks to a few tiles. Other weather: empty.
## Sits under the seed corner (layer 9) and the HUD (10). wild.gd: add_child(WildWeather.make(weather, granny)).

const FOG_SHADER := preload("res://scenes/wild/fog.gdshader")
const FOG_COLOR := Color("b9a697")
const LEAF_COLORS := ["a22512", "c94d2e", "e19064", "e5bd7f", "b66813", "c58845"]
const LEAF_OUTLINE := Color("3d1f29")
## Tumbling leaf frames ("L" leaf colour, "o" outline): slanted, edge-on, mirrored, upright. Outlined like the sprites so
## a leaf reads over the autumn ground and canopies.
const LEAF_FRAMES := [
	["..ooo.", ".oLLLo", "oLLLo.", ".ooo.."],
	[".oooo.", "oLLLLo", ".oooo."],
	[".ooo..", "oLLLo.", ".oLLLo", "..ooo."],
	[".oo.", "oLLo", "oLLo", ".oo."],
]
const LEAVES := 34
const STREAKS := 5
const STREAK_COLOR := Color("f2d9c5")
const LAYER := 4
## Granny's body centre above her feet (the node's origin), px.
const BODY_Y := -12

var weather := ""
var target: Node2D
var _fog: ColorRect
var _leaves: Control
var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _col := PackedInt32Array()
var _shape := PackedInt32Array()
var _t := 0.0


static func make(p_weather: String, p_target: Node2D) -> WildWeather:
	var w := WildWeather.new()
	w.weather = p_weather
	w.target = p_target
	return w


func _ready() -> void:
	layer = LAYER
	match weather:
		"windy":
			_build_wind()
		"foggy":
			_build_fog()
	set_process(_fog != null or _leaves != null)


func is_foggy() -> bool:
	return _fog != null


func leaf_count() -> int:
	return mini(_x.size(), LEAVES)


func _process(delta: float) -> void:
	_t += delta
	if _fog != null:
		_update_fog()
	if _leaves != null:
		_blow(delta)


# ---------- fog ----------

func _build_fog() -> void:
	_fog = ColorRect.new()
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = FOG_SHADER
	mat.set_shader_parameter("fog_color", FOG_COLOR)
	_fog.material = mat
	add_child(_fog)
	_update_fog()


## Granny's screen position and the camera offset (dither anchor) on whole pixels.
func _update_fog() -> void:
	var mat := _fog.material as ShaderMaterial
	var vp := get_viewport()
	var c := _fog.size / 2.0
	if is_instance_valid(target):
		c = target.get_global_transform_with_canvas().origin + Vector2(0, BODY_Y)
	mat.set_shader_parameter("rect_size", _fog.size)
	mat.set_shader_parameter("center", c.round())
	mat.set_shader_parameter("anchor", (-vp.canvas_transform.origin).round())


# ---------- wind ----------

func _build_wind() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026  # cosmetic only; game rules never read this
	_leaves = Control.new()
	_leaves.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leaves.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_leaves.draw.connect(_draw_leaves)
	add_child(_leaves)
	var size := _screen()
	for i in LEAVES + STREAKS:
		_x.append(rng.randf() * size.x)
		_y.append(rng.randf() * size.y)
		_speed.append(rng.randf_range(55.0, 120.0) if i < LEAVES else rng.randf_range(240.0, 320.0))
		_phase.append(rng.randf() * TAU)
		_col.append(rng.randi() % LEAF_COLORS.size())
		_shape.append(rng.randi() % LEAF_FRAMES.size() if i < LEAVES else rng.randi_range(10, 18))


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


## Leaves drift east in slow gusts, bob up and down and sink a little; off the east edge they come back in the west.
## Streaks (the last STREAKS slots, _shape = length) race across with gaps between them.
func _blow(delta: float) -> void:
	var size := _screen()
	var gust := 0.75 + 0.5 * (0.5 + 0.5 * sin(_t * 0.8))
	for i in _x.size():
		_x[i] += _speed[i] * gust * delta
		if i >= LEAVES:
			if _x[i] > size.x + 2.0:
				_x[i] = -float(_shape[i]) - fposmod(_phase[i] * 97.0 + _t * 53.0, size.x * 0.5)
				_y[i] = fposmod(_y[i] + 71.0, size.y)
			continue
		_y[i] += (sin(_t * 2.6 + _phase[i]) * 22.0 + 8.0) * delta
		if _x[i] > size.x + 4.0:
			_x[i] -= size.x + 8.0
			_y[i] = fposmod(_y[i] + 97.0, size.y)
		if _y[i] > size.y + 3.0:
			_y[i] -= size.y + 6.0
	_leaves.queue_redraw()


## Outlined palette leaves that tumble (each walks through LEAF_FRAMES at its own pace), and 1 px gust streaks with a
## lifted tail.
func _draw_leaves() -> void:
	for i in LEAVES:
		var p := Vector2i(floori(_x[i]), floori(_y[i]))
		var c := Color(LEAF_COLORS[_col[i]])
		var rows: Array = LEAF_FRAMES[(_shape[i] + int(_t * 5.0 + _phase[i])) % LEAF_FRAMES.size()]
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] != ".":
					_leaves.draw_rect(Rect2(p + Vector2i(x, y), Vector2.ONE), c if row[x] == "L" else LEAF_OUTLINE)
	for i in range(LEAVES, _x.size()):
		var p := Vector2i(floori(_x[i]), floori(_y[i]))
		var n := _shape[i]
		_leaves.draw_rect(Rect2(p, Vector2(n - 4, 1)), STREAK_COLOR)
		_leaves.draw_rect(Rect2(p + Vector2i(n - 4, -1), Vector2(4, 1)), STREAK_COLOR)
