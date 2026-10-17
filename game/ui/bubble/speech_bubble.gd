class_name SpeechBubble
extends Control
## UI-COMPACT · The one speech bubble of the game: a small paper box with a 1 px ink edge and rounded corners, body
## text (m5x7 16 px, theme type BodyPaper) that wraps at MAX_W and shows at most LINES lines, and a tail on `side`
## (where the speaker is: "below", "above", "left" or "right") pointing at `tail` (local px).
##   SpeechBubble.pop(parent, head_top, text, seconds, who, avoid)   world bubbles (garden, wild, kids, cat), placed
##       above the speaker or beside them, kept on screen, one per speaker, auto-hide (Fx.bubble calls this);
##   var b := SpeechBubble.new(); add_child(b); b.say(text)            managers that place their own (market, town).

const MAX_W := 168  ## widest bubble in base px, edge included
const LINES := 3
const PAD_X := 4  ## edge + space left and right of the text
const PAD_TOP := 1  ## m5x7 leaves 4 px above capitals inside its line box
const PAD_BOTTOM := 2
const GAP := 3  ## tail length: px between the box and the speaker's head
const SIDE := 9  ## px from the speaker's centre to a bubble beside them
const HUD_H := 32  ## screen px under the top edge the HUD row covers
const EDGE := 2
const C_FILL := Color("f2d9c5")
const C_SHADE := Color("b9a697")
const C_INK := Color("111010")

var side := "below"
var tail := Vector2.ZERO
var label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.theme_type_variation = &"BodyPaper"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.max_lines_visible = LINES
	label.position = Vector2(PAD_X, PAD_TOP)
	add_child(label)


## A bubble with `text` (already translated) for the speaker whose head top is `at` (parent coordinates): above the
## speaker with its tail pointing down, or beside them when that would leave the screen, go under the HUD, cover
## `avoid` (the thing talked about) or another bubble of this parent. Pops in and goes away after `seconds`. One
## bubble per speaker: a new line from `who` (default: the speaker's spot) replaces the old one.
static func pop(parent: Node, at: Vector2, text: String, seconds := 1.4, who := "", avoid := Rect2()) -> SpeechBubble:
	var key := who if who != "" else "%d,%d" % [roundi(at.x), roundi(at.y)]
	var live: Dictionary = parent.get_meta(&"speech_bubbles", {})
	var taken: Array[Rect2] = []
	for k: String in live.keys():
		var other: Variant = live[k]
		if not is_instance_valid(other) or (other as Node).is_queued_for_deletion():
			live.erase(k)
		elif k == key:
			(other as Node).queue_free()
			live.erase(k)
		else:
			taken.append(Rect2((other as Control).position, (other as Control).size))
	var b := SpeechBubble.new()
	b.z_index = 50
	parent.add_child(b)
	b.say(text)
	if avoid.has_area():
		taken.append(avoid)
	var spot := place(at, b.size, view_rect(parent), taken)
	b.position = spot.pos
	b.side = String(spot.side)
	b.tail = at - b.position
	live[key] = b
	parent.set_meta(&"speech_bubbles", live)
	b.pivot_offset = b.tail.clamp(Vector2.ZERO, b.size).floor()
	b.scale = Vector2(0.6, 0.6)
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(seconds + 0.25)
	t.tween_callback(b.queue_free)
	return b


## The part of the screen a world bubble may use, in `parent` coordinates: the visible view minus the HUD row and a
## small margin.
static func view_rect(parent: Node) -> Rect2:
	var ci := parent as CanvasItem
	if ci == null or not ci.is_inside_tree():
		return Rect2(EDGE, HUD_H, 480 - EDGE * 2, 270 - HUD_H - EDGE)
	var vp := ci.get_viewport_rect()
	var screen := Rect2(vp.position + Vector2(EDGE, HUD_H), vp.size - Vector2(EDGE * 2, HUD_H + EDGE))
	return ci.get_global_transform_with_canvas().affine_inverse() * screen


## First free spot for a box of size `bs` speaking for a head top at `at`: above (centred), then right, then left of
## the speaker, each kept inside `view` and clear of `taken`; above (kept inside `view`) when none is.
## Returns {"pos": Vector2, "side": String}.
static func place(at: Vector2, bs: Vector2, view: Rect2, taken: Array[Rect2]) -> Dictionary:
	var cands := [
		[Vector2(at.x - floorf(bs.x / 2.0), at.y - GAP - bs.y), "below"],
		[Vector2(at.x + SIDE, at.y + 2), "left"],
		[Vector2(at.x - SIDE - bs.x, at.y + 2), "right"],
	]
	for c in cands:
		var pos := keep_in((c[0] as Vector2).round(), bs, view)
		var r := Rect2(pos, bs)
		var ok := true
		match String(c[1]):
			"below":
				ok = r.end.y <= at.y - 1.0  # pushed down onto the speaker's head: try beside
			"left":
				ok = r.position.x >= at.x + 2.0
			"right":
				ok = r.end.x <= at.x - 2.0
		for x in taken:
			if ok and r.grow(1.0).intersects(x):
				ok = false
		if ok:
			return {"pos": pos, "side": c[1]}
	return {"pos": keep_in((cands[0][0] as Vector2).round(), bs, view), "side": "below"}


static func keep_in(pos: Vector2, bs: Vector2, view: Rect2) -> Vector2:
	return Vector2(clampf(pos.x, ceilf(view.position.x), floorf(view.end.x - bs.x)),
		clampf(pos.y, ceilf(view.position.y), floorf(view.end.y - bs.y)))


## Sets the line and sizes the box around it (call once the bubble is in the tree, so the theme font is known).
func say(text: String) -> void:
	label.text = text
	var font := label.get_theme_font("font")
	var fs := label.get_theme_font_size("font_size")
	var inner := MAX_W - PAD_X * 2
	var w := ceili(font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if w > inner:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w = mini(inner, ceili(font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, inner, fs, -1,
			TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).x) + 1)
	label.size = Vector2(w, 0)
	var lines := clampi(label.get_line_count(), 1, LINES)
	var h := lines * int(font.get_height(fs)) + (lines - 1) * label.get_theme_constant("line_spacing")
	label.size = Vector2(w, h)
	size = Vector2(w + PAD_X * 2, h + PAD_TOP + PAD_BOTTOM)
	queue_redraw()


## Lines the text needs at this width (more than LINES means some are cut).
func line_count() -> int:
	return label.get_line_count()


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
	match side:
		"below", "above":
			var tx := clampi(roundi(tail.x) - 1, 3, w - 6)
			var y0 := h - 1 if side == "below" else 0
			var dy := 1 if side == "below" else -1
			_px(tx - 1, y0, C_INK)
			_px(tx, y0, C_FILL)
			_px(tx + 1, y0, C_FILL)
			_px(tx + 2, y0, C_INK)
			_px(tx, y0 + dy, C_INK)
			_px(tx + 1, y0 + dy, C_FILL)
			_px(tx + 2, y0 + dy, C_INK)
			_px(tx + 1, y0 + dy * 2, C_INK)
			_px(tx + 2, y0 + dy * 2, C_INK)
		"left", "right":
			var ty := clampi(roundi(tail.y) + 4, 3, h - 5)
			var x0 := 0 if side == "left" else w - 1
			var dx := -1 if side == "left" else 1
			_px(x0, ty - 1, C_INK)
			_px(x0, ty, C_FILL)
			_px(x0, ty + 1, C_FILL)
			_px(x0, ty + 2, C_INK)
			_px(x0 + dx, ty, C_INK)
			_px(x0 + dx, ty + 1, C_FILL)
			_px(x0 + dx, ty + 2, C_INK)
			_px(x0 + dx * 2, ty + 1, C_INK)
			_px(x0 + dx * 2, ty + 2, C_INK)


func _px(x: int, y: int, c: Color) -> void:
	draw_rect(Rect2(x, y, 1, 1), c)
