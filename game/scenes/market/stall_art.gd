extends Control
## The market stall drawn in palette rectangles (MARKET): striped awning with scallops, sign board on the roof,
## posts, plank back wall with bunting, a gingham cloth under the 6x2 board, counter front and a hard ground shadow.
## Full-screen Control (480x270, mouse ignored); geometry from the board rect so the cloth always sits under it.

const C_INK := Color("111010")
const C_RED := Color("c94d2e")
const C_RED_DK := Color("a22512")
const C_CREAM := Color("f2d9c5")
const C_CREAM_DK := Color("b9a697")
const C_PEACH := Color("e19064")
const C_GOLD := Color("e5bd7f")
const C_GOLD_HI := Color("dbcc83")
const C_OLIVE := Color("747c37")
const C_WOOD := Color("83571e")
const C_WOOD_HI := Color("c58845")
const C_WOOD_DK := Color("50361e")
const C_PLUM := Color("3d1f29")
const STRIPE := 10

## Board rect in this Control's coordinates (set by the scene before the first draw).
var board_rect := Rect2i(168, 140, 144, 48)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Where the sign text goes (the scene puts a Label there).
func sign_rect() -> Rect2i:
	var x0 := board_rect.position.x + 22
	return Rect2i(x0, board_rect.position.y - 92, board_rect.size.x - 44, 20)


func _draw() -> void:
	var b := board_rect
	var x0 := b.position.x - 10
	var x1 := b.end.x + 10
	var awning_y := b.position.y - 70
	var counter_y := b.position.y - 4
	var front_y := b.end.y
	var ground_y := front_y + 24
	# ground shadow (hard, offset to the lower right)
	_rect(x0 + 4, ground_y, x1 - x0, 3, C_PLUM)
	# back wall planks
	_rect(x0 + 4, awning_y + 26, x1 - x0 - 8, counter_y - awning_y - 26, C_WOOD)
	for y in range(awning_y + 33, counter_y, 7):
		_rect(x0 + 4, y, x1 - x0 - 8, 1, C_WOOD_DK)
	# bunting under the awning
	var cols := [C_RED, C_GOLD, C_OLIVE, C_PEACH]
	var n := 0
	for x in range(x0 + 8, x1 - 10, 12):
		var c: Color = cols[n % cols.size()]
		for row in 5:
			_rect(x + row, awning_y + 27 + row, 9 - row * 2, 1, c)
		n += 1
	_rect(x0 + 4, awning_y + 26, x1 - x0 - 8, 1, C_WOOD_DK)
	# posts
	for px in [x0, x1 - 4]:
		_rect(px, awning_y, 4, ground_y - awning_y, C_WOOD)
		_rect(px, awning_y, 1, ground_y - awning_y, C_WOOD_HI)
		_rect(px + 3, awning_y, 1, ground_y - awning_y, C_WOOD_DK)
	# sign board on the roof, two legs
	var s := sign_rect()
	for lx in [s.position.x + 8, s.end.x - 10]:
		_rect(lx, s.end.y, 2, awning_y - s.end.y, C_WOOD_DK)
	_rect(s.position.x - 2, s.position.y - 2, s.size.x + 4, s.size.y + 4, C_WOOD_DK)
	_rect(s.position.x, s.position.y, s.size.x, s.size.y, C_GOLD)
	_rect(s.position.x, s.position.y, s.size.x, 1, C_GOLD_HI)
	_rect(s.position.x, s.end.y - 1, s.size.x, 1, C_WOOD_HI)
	# awning: stripes, dark top edge, scalloped hem
	var aw0 := x0 - 6
	var aw1 := x1 + 6
	_rect(aw0 + 2, awning_y - 1, aw1 - aw0 - 4, 1, C_RED_DK)
	var i := 0
	for x in range(aw0, aw1, STRIPE):
		var w := mini(STRIPE, aw1 - x)
		var c: Color = C_RED if i % 2 == 0 else C_CREAM
		var shade: Color = C_RED_DK if i % 2 == 0 else C_CREAM_DK
		_rect(x, awning_y, w, 20, c)
		_rect(x, awning_y + 14, w, 6, shade)
		_rect(x + 1, awning_y + 20, w - 2, 2, shade)
		_rect(x + 3, awning_y + 22, w - 6, 1, shade)
		i += 1
	_rect(aw0, awning_y + 13, aw1 - aw0, 1, C_RED_DK)
	# counter top
	_rect(x0, counter_y, x1 - x0, 4, C_WOOD_HI)
	_rect(x0, counter_y, x1 - x0, 1, C_GOLD_HI)
	_rect(x0, counter_y + 3, x1 - x0, 1, C_WOOD)
	# gingham cloth under the board (4 px checks)
	for y in range(b.position.y, b.end.y, 4):
		for x in range(b.position.x - 2, b.end.x + 2, 4):
			var dark := (floori((x - b.position.x) / 4.0) + floori((y - b.position.y) / 4.0)) % 2 == 0
			_rect(x, y, mini(4, b.end.x + 2 - x), mini(4, b.end.y - y), C_PEACH if dark else C_CREAM)
	# counter front: planks and a red skirt with scallops
	_rect(x0 + 4, front_y, x1 - x0 - 8, ground_y - front_y, C_WOOD)
	for x in range(x0 + 4, x1 - 4, 12):
		_rect(x, front_y, 1, ground_y - front_y, C_WOOD_DK)
	_rect(x0 + 4, front_y, x1 - x0 - 8, 6, C_RED)
	_rect(x0 + 4, front_y, x1 - x0 - 8, 1, C_RED_DK)
	for x in range(x0 + 4, x1 - 4, 8):
		_rect(x + 1, front_y + 6, 6, 1, C_RED)
		_rect(x + 2, front_y + 7, 4, 1, C_RED_DK)
	_rect(x0 + 4, ground_y - 1, x1 - x0 - 8, 1, C_WOOD_DK)


func _rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	if w > 0 and h > 0:
		draw_rect(Rect2(x, y, w, h), c)
