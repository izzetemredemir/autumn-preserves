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
	# STORY-02 memory objects (docs/story.md §4.3). The photos, hat and toys are drawn by Prop; the armchair and
	# the window are painted.
	"teo": Rect2i(178, 8, 18, 22),  # Teo's photo on the wall left of the window
	"nora": Rect2i(178, 34, 18, 22),  # Nora's childhood photo under it
	"hat": Rect2i(56, 30, 22, 58),  # his hat on a peg and the walking stick, right of the door
	"chair": Rect2i(176, 72, 76, 58),  # the armchair by the window
	"toys": Rect2i(104, 198, 44, 26),  # the wooden train and the cloth rabbit on the floor left of the rug
	"window": Rect2i(214, 8, 68, 38),  # the window with the falling leaves
	"jar": Rect2i(240, 48, 18, 22),  # the empty jar on the sill; full once the first jar is shelved
}
## Memory objects: hotspot kind -> caption key (the story line is STORY_OBJ_<kind>).
const MEMORY_CAPTIONS := {
	"teo": "STORY_OBJ_CAP_PHOTO", "nora": "STORY_OBJ_CAP_PHOTO", "hat": "STORY_OBJ_CAP_HAT",
	"chair": "STORY_OBJ_CAP_CHAIR", "toys": "STORY_OBJ_CAP_TOYS", "window": "STORY_OBJ_CAP_WINDOW",
	"jar": "STORY_OBJ_CAP_JAR",
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


## STORY-02 · Small hand-drawn props over the painting (local px inside their hotspot rect; palette constants only,
## filled rects, no alpha): "teo" and "nora" photo frames, "hat" (hat on a peg + stick), "toys" (train + rabbit) and
## "jar" (the sill jar: empty glass, or full of jam once `filled`).
class Prop extends Control:
	const KArt := preload("res://scenes/kitchen/kitchen_art.gd")
	var kind := ""
	var filled := false:
		set(v):
			filled = v
			queue_redraw()

	func _init(k := "") -> void:
		kind = k
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _r(x: int, y: int, w: int, h: int, c: Color) -> void:
		draw_rect(Rect2(x, y, w, h), c)

	func _draw() -> void:
		match kind:
			"teo":
				_photo(false)
			"nora":
				_photo(true)
			"hat":
				_hat()
			"toys":
				_toys()
			"jar":
				_jar()

	## 14x18 frame at (2,2): gold edge, plum mat, a small portrait.
	func _photo(girl: bool) -> void:
		_r(3, 3, 14, 18, KArt.PLUM)  # shadow on the wall
		_r(2, 2, 14, 18, KArt.GOLD)
		_r(3, 3, 12, 16, KArt.BARK)
		_r(4, 4, 10, 14, KArt.SLATE if not girl else KArt.GOLD_PALE)
		_r(5, 14, 8, 4, KArt.WINE if not girl else KArt.TEAL)  # shoulders
		_r(7, 8, 4, 5, KArt.PEACH)  # face
		if girl:
			_r(7, 7, 4, 2, KArt.AMBER)  # hair and two plaits
			_r(6, 9, 1, 5, KArt.AMBER)
			_r(11, 9, 1, 5, KArt.AMBER)
			_r(8, 15, 3, 3, KArt.RED)  # her jar
			_r(8, 14, 3, 1, KArt.CREAM)
		else:
			_r(7, 7, 4, 1, KArt.CREAM_LO)  # grey hair
			_r(7, 12, 4, 1, KArt.CREAM_LO)  # beard
			_r(7, 10, 1, 1, KArt.INK)
			_r(10, 10, 1, 1, KArt.INK)

	## Hat on a peg (top) and a walking stick leaning beside it.
	func _hat() -> void:
		_r(4, 2, 3, 3, KArt.IRON_DK)  # peg
		_r(1, 12, 15, 2, KArt.INK)  # brim
		_r(2, 11, 13, 1, KArt.BARK)
		_r(4, 5, 9, 7, KArt.BROWN)  # crown
		_r(4, 5, 9, 1, KArt.BARK)
		_r(4, 10, 9, 2, KArt.OLIVE_DK)  # band
		_r(5, 6, 2, 3, KArt.TAN)
		for y in range(20, 56):  # stick, leaning one px to the right every 12 rows
			var x := 15 + (56 - y) / 12
			_r(x, y, 2, 1, KArt.TAN)
			_r(x + 2, y, 1, 1, KArt.BARK)
		_r(15 + 56 / 12 - 1, 18, 6, 2, KArt.BROWN)  # crook
		_r(15 + 56 / 12 + 3, 20, 2, 2, KArt.BROWN)

	## Wooden train (red engine, wine cab, two wheels each) and a cream cloth rabbit.
	func _toys() -> void:
		_r(2, 22, 38, 2, KArt.PLUM)  # shadows
		_r(3, 14, 16, 7, KArt.RED)  # engine
		_r(3, 14, 16, 1, KArt.RED_HI)
		_r(13, 9, 6, 5, KArt.WINE)  # cab
		_r(14, 10, 4, 2, KArt.GOLD_PALE)
		_r(5, 10, 3, 4, KArt.INK)  # chimney
		_r(4, 20, 4, 3, KArt.INK)
		_r(13, 20, 4, 3, KArt.INK)
		_r(5, 21, 2, 1, KArt.GOLD)
		_r(14, 21, 2, 1, KArt.GOLD)
		_r(20, 17, 6, 4, KArt.OLIVE)  # truck behind it
		_r(21, 20, 3, 3, KArt.INK)
		_r(29, 14, 8, 8, KArt.CREAM)  # rabbit
		_r(30, 7, 2, 7, KArt.CREAM)  # ears
		_r(34, 7, 2, 7, KArt.CREAM)
		_r(31, 8, 1, 4, KArt.PEACH)
		_r(35, 8, 1, 4, KArt.PEACH)
		_r(32, 16, 1, 1, KArt.INK)
		_r(35, 16, 1, 1, KArt.INK)
		_r(33, 18, 2, 1, KArt.PEACH)
		_r(29, 21, 8, 1, KArt.CREAM_LO)

	## Jar on the window sill, 10x14 at (4,6) inside its 18x22 rect: lid, glass, jam when filled.
	func _jar() -> void:
		_r(4, 20, 12, 2, KArt.BARK)  # shadow on the sill
		_r(5, 7, 10, 13, KArt.CREAM_LO)  # glass edge
		_r(6, 8, 8, 11, KArt.GLASS)
		_r(7, 9, 1, 8, KArt.CREAM)  # glint
		_r(6, 4, 8, 3, KArt.IRON)  # lid
		_r(6, 4, 8, 1, KArt.MUTED)
		if filled:
			_r(6, 10, 8, 9, KArt.RED)
			_r(6, 10, 8, 1, KArt.RED_HI)
			_r(7, 11, 1, 6, KArt.PEACH)
			_r(8, 14, 5, 3, KArt.CREAM)  # label
			_r(9, 15, 3, 1, KArt.CREAM_LO)
