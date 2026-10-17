class_name ForestSurprise
extends Node2D
## FUN-FOREST · One little forest surprise on the map (rules: ForestSurprises). Drawn from palette rects, no sprites:
## (kind "knife", STORY-04: Teo's knife, drawn as a twinkle too) a shrub that shivers now and then ("bush"), a heap of leaves ("pile") or a twinkling spot ("sparkle").
## Position is the feet (bottom-centre of `cell`) so the y-sorted objects layer orders it with Granny and trees.
## None of them blocks a tile. A taken one is `gone`: invisible and no longer usable.

const C_INK := Color("111010")
const C_SHADOW := Color("3d1f29")
const C_GOLD := Color("e5bd7f")
const C_CREAM := Color("f2d9c5")
const SHIVER_EVERY := 4.2  ## seconds between two shivers of one bush
const SHIVER_LEN := 0.36
const SHIVER_STEPS := [2, -2, 1, -1, 1, 0]

var kind := ""
var id := -1
var cell := Vector2i.ZERO
var entry: Dictionary = {}
var gone := false
var highlighted := false:
	set(v):
		if v != highlighted:
			highlighted = v
			queue_redraw()
var _dx := 0  ## bush: whole-pixel sway of the top half
var _frame := 0  ## sparkle twinkle frame


func setup(p_entry: Dictionary) -> void:
	entry = p_entry
	kind = String(p_entry.kind)
	id = int(p_entry.id)
	cell = Vector2i(int(p_entry.x), int(p_entry.y))
	position = Vector2(cell.x * 16 + 8, cell.y * 16 + 16)
	queue_redraw()


func usable() -> bool:
	return not gone


func take() -> void:
	gone = true
	highlighted = false
	visible = false


## World point just above the thing, for bubbles.
func top() -> Vector2:
	return position + Vector2(0, -16 if kind != "pile" else -10)


func hit_rect() -> Rect2:
	var r := Rect2(-10, -16, 20, 16)
	if kind == "pile":
		r = Rect2(-9, -10, 18, 10)
	elif kind == "sparkle" or kind == "knife":
		r = Rect2(-10, -14, 20, 18)
	return Rect2(position + r.position, r.size)


func _process(_delta: float) -> void:
	if gone:
		return
	var ms := Time.get_ticks_msec()
	if kind == "bush":
		var t := fposmod(ms / 1000.0 + id * 1.7, SHIVER_EVERY)
		var dx := 0
		if t < SHIVER_LEN and not Juice.calm:
			dx = int(SHIVER_STEPS[mini(int(t / SHIVER_LEN * SHIVER_STEPS.size()), SHIVER_STEPS.size() - 1)])
		if dx != _dx:
			_dx = dx
			queue_redraw()
	elif kind == "sparkle" or kind == "knife":
		var f := (floori(ms / 170.0) + id) % 6
		if f != _frame:
			_frame = f
			queue_redraw()


## Whole-pixel "can't do that".
func nudge() -> void:
	var x := position.x
	var t := create_tween()
	for dx in [2, -2, 1, 0]:
		t.tween_property(self, "position:x", x + dx, 0.04)


## Shows the bush mid-shiver (smoke shots).
func shiver_now() -> void:
	_dx = 2
	queue_redraw()


func _draw() -> void:
	match kind:
		"bush":
			_draw_bush()
		"pile":
			_draw_pile()
		"sparkle", "knife":
			_draw_sparkle()
	if highlighted:
		var r := hit_rect()
		r.position -= position
		_outline(r, C_GOLD)


func _draw_bush() -> void:
	draw_rect(Rect2(-7, -3, 15, 3), C_SHADOW)
	draw_rect(Rect2(-7, -4, 14, 4), Color("314524"))  # the foot stays put
	var s := _dx
	var h := int(s / 2.0)
	draw_rect(Rect2(-8 + h, -9, 16, 5), Color("314524"))
	draw_rect(Rect2(-6 + s, -13, 12, 5), Color("314524"))
	draw_rect(Rect2(-4 + s, -15, 8, 3), Color("314524"))
	draw_rect(Rect2(-7 + h, -8, 14, 4), Color("53612e"))
	draw_rect(Rect2(-5 + s, -12, 10, 4), Color("53612e"))
	draw_rect(Rect2(-3 + s, -14, 6, 2), Color("53612e"))
	for p in [Vector2(-5, -7), Vector2(-1, -9), Vector2(3, -6), Vector2(-3, -12), Vector2(2, -13)]:
		draw_rect(Rect2(Vector2(p.x + (s if p.y < -8 else h), p.y), Vector2(2, 1)), Color("747c37"))
	draw_rect(Rect2(4 + s, -10, 1, 1), Color("b1a13d"))
	draw_rect(Rect2(-6 + h, -6, 1, 1), Color("c94d2e"))  # a stray autumn leaf
	draw_rect(Rect2(1 + s, -12, 1, 1), Color("e19064"))


func _draw_pile() -> void:
	draw_rect(Rect2(-8, -2, 17, 2), C_SHADOW)
	draw_rect(Rect2(-7, -3, 14, 3), Color("b66813"))
	draw_rect(Rect2(-6, -5, 12, 3), Color("c94d2e"))
	draw_rect(Rect2(-4, -7, 8, 3), Color("e19064"))
	draw_rect(Rect2(-2, -8, 4, 2), Color("e5bd7f"))
	for p in [Vector2(-5, -4), Vector2(2, -3), Vector2(-1, -6), Vector2(4, -5), Vector2(-6, -2)]:
		draw_rect(Rect2(p, Vector2(2, 1)), Color("a22512"))
	for p in [Vector2(-3, -3), Vector2(1, -7), Vector2(5, -3)]:
		draw_rect(Rect2(p, Vector2(2, 1)), Color("e5bd7f"))


## A four-pointed twinkle over a dark spot of ground, swelling and shrinking (frames 0-5).
func _draw_sparkle() -> void:
	var c := Vector2(0, -7)
	var arm: int = [0, 1, 2, 3, 2, 1][_frame]
	var col := C_GOLD if arm > 1 else Color("dbcc83")
	draw_rect(Rect2(-5, -3, 11, 3), C_SHADOW)
	draw_rect(Rect2(-4, -4, 9, 1), Color("83571e"))
	draw_rect(Rect2(c + Vector2(-arm - 1, -1), Vector2(arm * 2 + 3, 3)), col)
	draw_rect(Rect2(c + Vector2(-1, -arm - 1), Vector2(3, arm * 2 + 3)), col)
	draw_rect(Rect2(c + Vector2(-1, -1), Vector2(3, 3)), C_CREAM)


func _outline(r: Rect2, c: Color) -> void:
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), c)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), c)
	draw_rect(Rect2(r.position, Vector2(1, r.size.y)), c)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), c)
