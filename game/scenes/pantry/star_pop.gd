extends Node2D
## JURY-PANTRY · "+★" over an item whose drop met a star rule: a pixel plus and the full star rise a few whole
## pixels, hold, then go (no fade, no partial alpha). Frees itself.

const STAR := "res://assets/sprites/ui/icon_star_full.png"
const C_INK := Color("111010")
const C_CREAM := Color("f2d9c5")
const RISE := 8
const STEP := 0.035
const HOLD := 0.55
const W := 24

var _star: Texture2D
var _t := 0.0
var _y0 := 0.0


## A pop centred on `at` (the top centre of the item, local to `parent`).
static func spawn(parent: Node, at: Vector2) -> Node2D:
	var p: Node2D = load("res://scenes/pantry/star_pop.gd").new()
	p.name = "StarPop"
	p.position = (at - Vector2(W / 2.0, 14)).floor()
	p.z_index = 60
	parent.add_child(p)
	return p


func _ready() -> void:
	_star = load(STAR) if ResourceLoader.exists(STAR) else null
	_y0 = position.y


func _process(delta: float) -> void:
	_t += delta
	position.y = _y0 - mini(RISE, floori(_t / STEP))
	if _t >= RISE * STEP + HOLD:
		queue_free()


func _draw() -> void:
	# plus: 7 x 7 ink cross with a 5 x 5 cream cross inside, star icon to its right
	draw_rect(Rect2(0, 5, 7, 3), C_INK)
	draw_rect(Rect2(2, 3, 3, 7), C_INK)
	draw_rect(Rect2(1, 6, 5, 1), C_CREAM)
	draw_rect(Rect2(3, 4, 1, 5), C_CREAM)
	if _star != null:
		draw_texture(_star, Vector2(8, 0))
