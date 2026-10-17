class_name DitherCover
extends Control
## Full-screen cover that fades in ordered-dither steps (4x4 Bayer, 17 levels), never with alpha blending.
## level 0 = clear, 16 = solid `color`. `fade(to, seconds)` returns a signal to await.

const LEVELS := 16
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const DIM_LEVEL := 4  ## UI-COMPACT: the dim behind a modal card, one ink pixel in four, so the scene stays readable
const INK := Color("111010")

static var _patterns: Array[ImageTexture] = []

var color := Color("23282a")
var level := 0:
	set(v):
		level = clampi(v, 0, LEVELS)
		queue_redraw()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## UI-COMPACT · The light dim every modal card sits on: a sparse 25 % ink dither over the whole screen (clicks pass
## through it; the card's own root decides whether they reach the scene).
static func dim() -> DitherCover:
	var d := DitherCover.new()
	d.color = INK
	d.level = DIM_LEVEL
	return d


## White 4x4 tiles, one per level; drawn with `color` as modulate (white * color = exact palette colour).
static func _pattern(lvl: int) -> ImageTexture:
	if _patterns.is_empty():
		for l in LEVELS + 1:
			var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
			for i in 16:
				if BAYER[i] < l:
					img.set_pixel(i % 4, i >> 2, Color.WHITE)
			_patterns.append(ImageTexture.create_from_image(img))
	return _patterns[lvl]


func _draw() -> void:
	if level <= 0:
		return
	var r := Rect2(Vector2.ZERO, size)
	if level >= LEVELS:
		draw_rect(r, color)
	else:
		draw_texture_rect(_pattern(level), r, true, color)


## Steps the dither toward `to` over `seconds`; blocks clicks while anything is covered.
func fade(to: int, seconds: float) -> Signal:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween()
	t.tween_method(_set_level, float(level), float(to), maxf(seconds, 0.01))
	if to <= 0:
		t.tween_callback(func() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE)
	return t.finished


func _set_level(v: float) -> void:
	var l := roundi(v)
	if l != level:
		level = l
