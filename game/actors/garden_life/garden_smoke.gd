class_name GardenSmoke
extends Node2D
## GARDEN-LIFE · Chimney smoke: little puffs rise from the cottage chimney (garden_props.json "chimney"), grow through
## the three frames of garden_smoke.png (6x6) and drift with the wind (further on windy days). One node, whole pixels.

const SHEET := "res://assets/sprites/garden/garden_smoke.png"
const SIZE := 6
const LIFE := 2.6
const RISE := 22.0
const EVERY := [0.85, 0.55]  ## seconds between puffs: calm, windy
const DRIFT := [7.0, 26.0]

var windy := false

var _tex: Texture2D
var _puffs: Array[Dictionary] = []
var _next := 0.0
var _rng := RandomNumberGenerator.new()


func setup(chimney: Vector2i, p_windy: bool) -> void:
	position = Vector2(chimney)
	windy = p_windy
	_rng.randomize()
	_tex = load(SHEET) if ResourceLoader.exists(SHEET) else null
	for i in 3:  # already smoking when Granny steps out
		_puffs.append({"age": LIFE * (0.25 + i * 0.25), "dx": _rng.randf_range(-1.0, 1.0)})


func _process(delta: float) -> void:
	_next -= delta
	if _next <= 0.0:
		_next = EVERY[1 if windy else 0]
		_puffs.append({"age": 0.0, "dx": _rng.randf_range(-1.0, 1.0)})
	for i in range(_puffs.size() - 1, -1, -1):
		_puffs[i].age = float(_puffs[i].age) + delta
		if float(_puffs[i].age) >= LIFE:
			_puffs.remove_at(i)
	queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var drift: float = DRIFT[1 if windy else 0]
	for p in _puffs:
		var k := float(p.age) / LIFE
		var at := Vector2(float(p.dx) + drift * k * k, -RISE * k).round() - Vector2(SIZE / 2, SIZE)
		var f := mini(int(k * 3.0), 2)
		draw_texture_rect_region(_tex, Rect2(at, Vector2(SIZE, SIZE)), Rect2(f * SIZE, 0, SIZE, SIZE))
