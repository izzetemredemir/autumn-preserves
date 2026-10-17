extends Control
## KITCHEN-P1C · The grandkids' reply drawings on the kitchen wall (spec §7.6: "the drawing hangs on the kitchen wall").
## Up to MAX_SHOWN latest reply letters, each the very picture its letter shows (KidDrawing.render with the letter's
## seed and subject), as a small copy in a wooden frame pinned on the stone wall (under the HUD line): the newest at
## half size right of the window, the two before it at a third, side by side on the side wall (SPOTS).
## Each frame is a button: hovering names the child (`hovered`), a click or Enter asks the kitchen to open it big
## (`open_requested`, Viewer: the 48x48 drawing at 2x on paper, UI-COMPACT).
## show_letters(state) rebuilds the frames only when the set of letters changed.

signal hovered(text: String)
signal open_requested(letter: Dictionary)

const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const MAX_SHOWN := 3
## Frame spots, newest first, and how much each copy shrinks the 48x48 drawing (2 -> 24x24, 3 -> 16x16; frames add
## a 1 px edge). HOUSE-DOORS: the parlour door now fills the wall left of the window, so the newest hangs on the
## stone strip between the window's right curtain and the tall cupboard (x 259-287, y 31-58) and the two before it
## on the side wall under the framed picture (x 362-410, below y 91: clear of Granny's To-Do note).
const SPOTS := [Vector2i(260, 32), Vector2i(370, 91), Vector2i(390, 91)]
const SHRINK := [2, 3, 3]
const PAPER := Color("f2d9c5")

var _ids: Array = []
var _frames: Array[Button] = []
var _active := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------------------------------------------------------------- pure helpers

## The latest reply letters (the ones that carry a drawing), newest first, at most `n`.
static func latest(state: Dictionary, n: int = MAX_SHOWN) -> Array:
	var out: Array = []
	var l: Variant = state.get("letters")
	if typeof(l) != TYPE_DICTIONARY:
		return out
	for letter: Dictionary in l.get("inbox", []):
		if String(letter.get("kind", "")) == "reply":
			out.append(letter)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) > int(b.id))
	return out.slice(0, n)


## Same seed as the letter screen: a letter always shows the same picture.
static func drawing_seed(letter: Dictionary) -> int:
	return Hash.fnv1a31("%d|%s" % [int(letter.id), String(letter.from)])


## What the child drew for a reply: the jars from Granny's parcel (letter screen's subject, reply branch).
static func drawing_subject(state: Dictionary, letter: Dictionary) -> Dictionary:
	var items: Array = []
	var parcel := Letters.parcel_for(state, int(letter.get("re", -1)))
	for key in parcel.get("keys", []):
		var look: Dictionary = ProductGen.describe(String(key), state.get("varieties", {})).appearance
		var lids: Array = look.get("lid_colors", ["9b8039"])
		items.append({"vessel": String(look.vessel), "fill": look.fill, "lid": String(lids[0]),
			"label": String(look.label_color)})
	return {"kind": "reply", "kid": String(letter.from), "care": bool(letter.get("care", false)), "items": items}


static func drawing(state: Dictionary, letter: Dictionary) -> Image:
	return KidDrawing.render(drawing_seed(letter), drawing_subject(state, letter))


## A copy `k` times smaller without blending: each k x k block keeps its most used crayon colour (paper only when
## the block is all paper; ties go to the darker colour), so the thin crayon lines survive. Palette in, palette out.
static func thumb(img: Image, k: int = 2) -> Image:
	var w := img.get_width() / k
	var h := img.get_height() / k
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var counts := {}
			for j in k:
				for i in k:
					var c := img.get_pixel(x * k + i, y * k + j)
					if not c.is_equal_approx(PAPER):
						counts[c] = int(counts.get(c, 0)) + 1
			var best := PAPER
			var best_n := 0
			for c: Color in counts:
				var n: int = counts[c]
				if n > best_n or (n == best_n and c.get_luminance() < best.get_luminance()):
					best = c
					best_n = n
			out.set_pixel(x, y, best)
	return out


# ---------------------------------------------------------------- view

func show_letters(state: Dictionary) -> void:
	var letters := latest(state)
	var ids: Array = letters.map(func(l: Dictionary) -> int: return int(l.id))
	if ids == _ids:
		return
	_ids = ids
	for f in _frames:
		remove_child(f)
		f.queue_free()
	_frames.clear()
	# oldest first: focus walks up the wall to the newest (SPOTS[0])
	for i in range(letters.size() - 1, -1, -1):
		var letter: Dictionary = letters[i]
		var f := Frame.new()
		f.position = Vector2(SPOTS[i])
		f.set_picture(ImageTexture.create_from_image(thumb(drawing(state, letter), int(SHRINK[i]))))
		var hint := tr("UI_FAMILY_DRAWING_HINT") % Letters.kid_name(String(letter.from))  # on the message bar
		f.pressed.connect(func() -> void: open_requested.emit(letter))
		f.mouse_entered.connect(func() -> void: hovered.emit(hint))
		f.focus_entered.connect(func() -> void: hovered.emit(hint))
		f.mouse_exited.connect(func() -> void: hovered.emit(""))
		f.focus_exited.connect(func() -> void: hovered.emit(""))
		add_child(f)
		_frames.append(f)
	set_active(_active)


## Clickable and focusable only while the room is (no panel, dialog or mini-game over it).
func set_active(on: bool) -> void:
	_active = on
	for f in _frames:
		f.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		f.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


func frame_count() -> int:
	return _frames.size()


## The frame of the newest drawing (SPOTS[0]), or null.
func newest() -> Button:
	return _frames[_frames.size() - 1] if not _frames.is_empty() else null


## A pinned drawing: wooden frame (gold when hovered or focused), the small copy, a red pin on top.
class Frame extends Button:
	var texture: Texture2D

	func set_picture(t: Texture2D) -> void:
		texture = t
		size = Vector2(t.get_width() + 2, t.get_height() + 2)
		custom_minimum_size = size
		queue_redraw()

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_ALL
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _draw() -> void:
		var lit := has_focus() or is_hovered()
		var w := int(size.x)
		var h := int(size.y)
		draw_rect(Rect2(0, 0, w, h), Art.GOLD if lit else Art.BROWN)
		draw_rect(Rect2(w - 1, 1, 1, h - 1), Art.BARK)  # shadow edge right and bottom
		draw_rect(Rect2(1, h - 1, w - 1, 1), Art.BARK)
		if texture != null:
			draw_texture(texture, Vector2(1, 1))
		var cx := w / 2 - 1
		draw_rect(Rect2(cx, -1, 2, 2), Art.RED)
		draw_rect(Rect2(cx, -1, 1, 1), Art.RED_HI)


## The drawing big: 2x on paper in the middle of the screen (UI-COMPACT: a small card on the light dim, lines in
## the body font), who drew it and how to close. Any click, Esc or interact closes it (`closed`).
class Viewer extends Control:
	signal closed

	const ZOOM := 2

	func setup(img: Image, kid_name: String) -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(DitherCover.dim())  # sparse ink dither, no partial alpha
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		var paper := PanelContainer.new()
		paper.theme_type_variation = &"PaperPanel"
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(paper)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(box)
		var big := img.duplicate() as Image
		big.resize(img.get_width() * ZOOM, img.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
		var pic := TextureRect.new()
		pic.texture = ImageTexture.create_from_image(big)
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		pic.custom_minimum_size = Vector2(big.get_width(), big.get_height())
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(pic)
		for t in [tr("UI_FAMILY_DRAWING_FROM") % kid_name, tr("UI_FAMILY_DRAWING_CLOSE")]:
			var l := Label.new()
			l.theme_type_variation = &"BodyPaper"
			l.text = t
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(l)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			accept_event()
			close()

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
			close()

	func close() -> void:
		if is_queued_for_deletion():
			return
		closed.emit()
		queue_free()
