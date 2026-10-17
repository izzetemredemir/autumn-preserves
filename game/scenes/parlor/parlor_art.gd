extends RefCounted
## PARLOR · Where things are in the painted parlour (bg_parlor.png, 480x270 design space) and the two small pieces
## drawn over paintings: the paper tag with the unread letters on the side table, and the kitchen's way into the
## parlour (a rag doormat on the front of the kitchen floor: the kitchen painting has no door there, the parlour lies
## through the front wall, towards the viewer). Colours are KitchenArt's palette constants.

const BACKGROUND := "res://assets/sprites/scenes/bg_parlor.png"
## Hit rects (each >= 16 px). Granny's To-Do note covers the top right (x >= 250, y < 150) on days 1-2: the bed nook
## reaches well below it, the door and the bookshelf stay left of it.
const OBJECTS := {
	"door": Rect2i(4, 30, 48, 150),  # the plank door on the left wall, back to the kitchen
	"shelf": Rect2i(86, 8, 80, 114),  # the bookshelf with the red recipe book lying on a low shelf
	"letters": Rect2i(266, 80, 50, 48),  # the round side table with the letters and the tea cup
	"cat": Rect2i(280, 160, 54, 42),  # the wicker basket on the rug
	"bed": Rect2i(380, 64, 88, 144),  # the bed nook on the right wall
}
## Granny at the painting's scale (granny_kitchen.png, 44x88) just in from the kitchen door, feet at (70, 186),
## left of the bookshelf's caption.
const GRANNY_AT := Vector2(48, 100)
## The cat's feet in her basket (Cat draws a 24x24 frame above this point).
const CAT_AT := Vector2(307, 192)
## Where the unread-letters tag sits, inside the letters hotspot.
const TAG_AT := Vector2i(26, 0)
## The kitchen's parlour hotspot: the doormat on the floor in front of the stove's hearth, left of the P1 press
## (it ends at y 218) and clear of the stove's caption (x 22-62, under the stove); its caption goes above it.
const KITCHEN_DOOR := Rect2i(72, 218, 64, 20)


## A paper tag with the number of unread letters (KitchenArt's pantry tag), nothing at 0.
class Tag extends Control:
	const KArt := preload("res://scenes/kitchen/kitchen_art.gd")
	var count := 0:
		set(v):
			count = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(22, 16)

	func _draw() -> void:
		if count > 0:
			KArt._tag(self, 0, 0, count)


## The rag doormat in the kitchen (64x20 local): a striped wine and red mat with cream fringes, a hard plum shadow
## and two cream chevrons pointing out of the room, towards the viewer.
class KitchenDoor extends Control:
	const KArt := preload("res://scenes/kitchen/kitchen_art.gd")
	const CHEVRON := ["c.....c", ".c...c.", "..c.c..", "...c..."]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(64, 20)

	func _r(x: int, y: int, w: int, h: int, c: Color) -> void:
		draw_rect(Rect2(x, y, w, h), c)

	func _draw() -> void:
		_r(4, 17, 58, 2, KArt.PLUM)  # shadow on the planks
		_r(3, 2, 58, 15, KArt.BARK)  # mat edge
		_r(4, 3, 56, 13, KArt.WINE)
		for y in [4, 14]:
			_r(4, y, 56, 1, KArt.RED)
		for y in [6, 12]:
			_r(4, y, 56, 1, KArt.BROWN)
		for x in range(4, 60, 4):  # woven middle band
			_r(x, 7, 2, 5, KArt.RED_HI)
			_r(x + 2, 7, 2, 5, KArt.TAN)
		for y in range(3, 16, 2):  # fringes on the short ends
			_r(0, y, 3, 1, KArt.CREAM_LO)
			_r(61, y, 3, 1, KArt.CREAM_LO)
		for k in 2:  # two chevrons, ink shadowed, in a wine patch on the band
			var y0 := 4 + k * 5
			_r(27, y0 - 1, 11, 6, KArt.WINE)
			for j in CHEVRON.size():
				var row: String = CHEVRON[j]
				for i in row.length():
					if row[i] == "c":
						_r(29 + i, y0 + j + 1, 1, 1, KArt.INK)
						_r(29 + i, y0 + j, 1, 1, KArt.CREAM)
