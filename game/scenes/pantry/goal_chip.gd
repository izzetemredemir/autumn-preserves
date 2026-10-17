extends Control
## JURY-PANTRY · One star rule of the pantry as a chip in the goal panel: a dim wooden strip with an empty box while
## the rule is unmet; met, it lights up gold with a green check. pantry.gd pops it and plays the sound.

const C_INK := Color("111010")
const C_OFF_FILL := Color("50361e")
const C_OFF_HI := Color("83571e")
const C_OFF_BOX := Color("b9a697")
const C_OFF_TEXT := Color("b9a697")
const C_ON_FILL := Color("e5bd7f")
const C_ON_HI := Color("f2d9c5")
const C_ON_LO := Color("9b8039")
const C_ON_TEXT := Color("50361e")
const C_BOX := Color("747c37")
const C_CHECK := Color("f2d9c5")
const BOX := Rect2i(3, 4, 11, 10)
## 7 x 5 check mark inside the box, row-major.
const CHECK := ["......#", ".....##", "#...##.", "##.##..", ".###..."]
const TEXT_X := 18

var met := false
var label: Label


## `key` is the rule's string key (Label translates it).
func setup(key: String) -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	label = Label.new()
	label.text = key
	label.position = Vector2(TEXT_X, 0)
	label.size = Vector2(size.x - TEXT_X - 2, size.y)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(label)
	set_met(false)


func set_met(on: bool) -> void:
	met = on
	if label != null:
		label.add_theme_color_override("font_color", C_ON_TEXT if on else C_OFF_TEXT)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0) if on else C_INK)
	queue_redraw()


func _draw() -> void:
	var w := int(size.x)
	var h := int(size.y)
	draw_rect(Rect2(0, 0, w, h), C_INK)
	draw_rect(Rect2(1, 1, w - 2, h - 2), C_ON_FILL if met else C_OFF_FILL)
	draw_rect(Rect2(1, 1, w - 2, 1), C_ON_HI if met else C_OFF_HI)
	if met:
		draw_rect(Rect2(1, h - 2, w - 2, 1), C_ON_LO)
	var b := BOX
	if met:
		draw_rect(Rect2(b), C_INK)
		draw_rect(Rect2(b.grow(-1)), C_BOX)
		for y in CHECK.size():
			var row: String = CHECK[y]
			for x in row.length():
				if row[x] == "#":
					draw_rect(Rect2(b.position.x + 2 + x, b.position.y + 2 + y, 1, 1), C_CHECK)
	else:
		draw_rect(Rect2(b.position.x, b.position.y, b.size.x, 1), C_OFF_BOX)
		draw_rect(Rect2(b.position.x, b.end.y - 1, b.size.x, 1), C_OFF_BOX)
		draw_rect(Rect2(b.position.x, b.position.y, 1, b.size.y), C_OFF_BOX)
		draw_rect(Rect2(b.end.x - 1, b.position.y, 1, b.size.y), C_OFF_BOX)
