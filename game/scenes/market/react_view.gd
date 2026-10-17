extends RefCounted
## FUN-REACT · Views for reaction lines (Reactions builds the words). Bubbles are UI-COMPACT's SpeechBubble (body font
## m5x7 16 px through the BodyPaper theme type, at most SpeechBubble.MAX_W wide and LINES lines); this file adds the
## town's delivery card (portrait in a paper frame + a SpeechBubble beside it, a heart pop when the jar meets their
## likes), Granny's one-line comment under the kitchen's result card (BodyPaper text in a small paper box) and the
## wrap measure the tests use. Nothing here takes input: every node ignores the mouse.

const BODY := preload("res://assets/fonts/m5x7.ttf")  ## the theme's Body font, for measuring without a tree
const BODY_SIZE := 16
const MAX_W := SpeechBubble.MAX_W
const MAX_LINES := SpeechBubble.LINES
const PAD := Vector2i(SpeechBubble.PAD_X, SpeechBubble.PAD_TOP)
const C_FILL := Color("f2d9c5")
const C_SHADE := Color("b9a697")
const C_INK := Color("111010")
const C_HEART := Color("c94d2e")
const HEART := [".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]


## Greedy word wrap at `width` px of the body font, joined with "\n"; at most `max_lines` lines. What a SpeechBubble
## does with the line (tests measure with it; scenes hand SpeechBubble the plain line).
static func wrap(text: String, width: int = MAX_W - PAD.x * 2, max_lines: int = MAX_LINES) -> String:
	var lines: Array = []
	var cur := ""
	for w in text.split(" ", false):
		var cand := w if cur == "" else cur + " " + w
		if cur != "" and text_width(cand) > width:
			lines.append(cur)
			cur = w
		else:
			cur = cand
	if cur != "":
		lines.append(cur)
	return "\n".join(lines.slice(0, max_lines))


static func text_width(s: String) -> int:
	return ceili(BODY.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, BODY_SIZE).x)


## A pixel heart (7x6 at 2x, ink outline) that pops up and floats away.
class HeartPop:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(14, 12)
		pivot_offset = Vector2(7, 6)
		scale = Vector2(0.4, 0.4)
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(y: float) -> void: position.y = roundf(y), position.y, position.y - 14.0, 0.9)
		tw.tween_callback(queue_free)

	func _draw() -> void:  # ink outline first (reads on any backdrop), then the red
		for y in HEART.size():
			for x in 7:
				if String(HEART[y])[x] == "X":
					draw_rect(Rect2(x * 2 - 1, y * 2 - 1, 4, 4), C_INK)
		for y in HEART.size():
			for x in 7:
				if String(HEART[y])[x] == "X":
					draw_rect(Rect2(x * 2, y * 2, 2, 2), C_HEART)
		draw_rect(Rect2(2, 2, 2, 2), C_FILL)  # a glint


## The town's delivery card: the neighbour's portrait in a paper frame with their line in a SpeechBubble beside it;
## a heart pops over the portrait when the jar meets their likes. Pops in, stays `life` seconds, then goes. Call
## setup() once the card is in the tree (the bubble sizes itself with the theme font). Never takes input.
class DeliveryCard:
	extends Control
	signal gone
	var bubble: SpeechBubble
	var portrait: Control

	func setup(face: Control, text: String, loved: bool, life := 3.6) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait = face
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.position = Vector2(2, 2)
		portrait.size = Vector2(48, 48)
		add_child(portrait)
		bubble = SpeechBubble.new()
		add_child(bubble)
		bubble.say(text)
		bubble.position = Vector2(57, 6)
		bubble.side = "left"
		bubble.tail = Vector2(-5, 2)  # the portrait frame's right edge
		size = Vector2(57 + bubble.size.x, maxf(52.0, bubble.size.y + 6.0))
		pivot_offset = Vector2(26, 26)
		scale = Vector2(0.6, 0.6)
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if loved:
			tw.tween_callback(func() -> void:
				var h := HeartPop.new()
				h.position = Vector2(38, -6)
				add_child(h))
		tw.tween_interval(life)
		tw.tween_property(self, "scale", Vector2(0.6, 0.6), 0.1)
		tw.tween_callback(func() -> void:
			gone.emit()
			queue_free())

	func _draw() -> void:  # the portrait's paper frame with a 1 px ink edge
		draw_rect(Rect2(0, 0, 52, 52), C_INK)
		draw_rect(Rect2(1, 1, 50, 50), C_FILL)
		draw_rect(Rect2(1, 50, 50, 1), C_SHADE)

	func text() -> String:
		return bubble.label.text if bubble != null else ""


## Granny's one short line under the kitchen's result card: "Granny: Mmm, ..." as one line of BodyPaper text in a small
## paper box, centred under `panel` (the card's paper) and following it while it plays in; above it when there is no
## room below. Call setup() once it is in the tree.
class GrannyLine:
	extends Control
	var panel: Control
	var label: Label

	func setup(card_panel: Control, text: String) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel = card_panel
		label = Label.new()
		label.theme_type_variation = &"BodyPaper"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = text
		add_child(label)
		var ls := label.get_minimum_size()
		label.position = Vector2(PAD)
		label.size = Vector2(ceili(ls.x), ceili(ls.y))
		size = Vector2(ceili(ls.x) + PAD.x * 2, ceili(ls.y) + SpeechBubble.PAD_TOP + SpeechBubble.PAD_BOTTOM)
		_follow()

	func _process(_dt: float) -> void:
		_follow()

	func _follow() -> void:
		if panel == null or not is_instance_valid(panel):
			return
		var r := panel.get_global_rect()
		var view := Vector2(480, 270)
		var x := roundf(r.get_center().x - size.x / 2.0)
		var y := r.end.y + 3.0
		if y + size.y > view.y - 2.0:
			y = r.position.y - 3.0 - size.y
		global_position = Vector2(clampf(x, 3.0, view.x - 3.0 - size.x), clampf(roundf(y), 3.0, view.y - 3.0 - size.y))

	func _draw() -> void:
		var w := int(size.x)
		var h := int(size.y)
		draw_rect(Rect2(1, 1, w - 2, h - 2), C_FILL)
		draw_rect(Rect2(2, h - 2, w - 4, 1), C_SHADE)
		draw_rect(Rect2(2, 0, w - 4, 1), C_INK)
		draw_rect(Rect2(2, h - 1, w - 4, 1), C_INK)
		draw_rect(Rect2(0, 2, 1, h - 4), C_INK)
		draw_rect(Rect2(w - 1, 2, 1, h - 4), C_INK)
		for c in [Vector2(1, 1), Vector2(w - 2, 1), Vector2(1, h - 2), Vector2(w - 2, h - 2)]:
			draw_rect(Rect2(c, Vector2.ONE), C_INK)

	func text() -> String:
		return label.text if label != null else ""
