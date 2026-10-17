class_name Premise
extends Control
## FIRST-60 · The premise (spec §1.1) as a short painted intro on New Game, about 20 s: the valley, Granny's cottage,
## a jar on the shelf, snow beyond the hills, then her garden (intro_beats.gd). Each beat dithers in over the one
## before, pans slowly in whole pixels and types its line into a caption at the bottom.
## First view: a click, tap or key finishes the line, the next one moves on to the next beat. Once the intro has
## been watched (settings.cfg game/intro_seen) any click, tap or key skips all of it.
## Emits `finished` once, at the end or on skip; the title then goes to the garden.

signal finished

const Beats := preload("res://ui/premise/intro_beats.gd")
const CPS := 36.0
const TYPE_AT := 0.4  ## seconds into a beat before its line starts typing
const CAPTION_W := 452
const SEEN := "intro_seen"

var _beats: Array = []
var _t := 0.0
var _beat := -1
var _typed_all := false
var _skippable := false
var _left := false
var _caption: Label
var _caption_box: Control
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 2  # over the title backdrop's front leaves
	_skippable = bool(GameSettings.get_value("game", SEEN))
	for i in Beats.count():
		var b: Control = Beats.make(i)
		b.visible = false
		add_child(b)
		_beats.append(b)
	_caption_box = CenterContainer.new()
	_caption_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption_box.offset_top = -72
	_caption_box.offset_bottom = -22
	_caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption_box)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_box.add_child(panel)
	_caption = Label.new()
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING  # lay out the full line, reveal it
	_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # set already translated
	panel.add_child(_caption)
	_hint = Label.new()
	_hint.text = tr("PREMISE_SKIP")
	_hint.add_theme_color_override("font_color", Color("b9a697"))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)  # calm: the bottom edge, under the caption
	_hint.offset_top = -20
	_hint.offset_bottom = -2
	_hint.offset_left = 0
	_hint.offset_right = 0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = false
	add_child(_hint)
	_apply()


func _process(delta: float) -> void:
	_t = minf(_t + delta, Beats.total())
	_apply()
	if _t >= Beats.total():
		_leave()


## Intro time in seconds (smoke shots and the UI audit seek to each beat).
func seek(t: float) -> void:
	_t = clampf(t, 0.0, Beats.total())
	_apply()


## Moments where each beat's line is fully typed (the UI audit checks every caption).
func audit_moments() -> Array:
	var out := []
	for i in Beats.count():
		out.append(Beats.start(i + 1) - 0.15)
	return out


func _apply() -> void:
	for i in _beats.size():
		var b: Control = _beats[i]
		b.visible = Beats.shown(i, _t)
		if b.visible:
			b.set_level(Beats.level(i, _t))
			b.at(_t - Beats.start(i))
	var i := Beats.index_at(_t)
	if i != _beat:
		_beat = i
		_typed_all = false
		_set_line(tr(String(Beats.BEATS[i][1])))
	var local := _t - Beats.start(i)
	_caption_box.visible = local >= TYPE_AT
	var n := int((local - TYPE_AT) * CPS)
	_caption.visible_characters = -1 if _typed_all or n >= _caption.text.length() else maxi(n, 0)
	_hint.visible = _skippable and not _left and int(_t * 2.0) % 3 != 2


## A snug caption: as wide as the line, wrapping only past CAPTION_W.
func _set_line(text: String) -> void:
	_caption.text = text
	var font := _caption.get_theme_font("font")
	var w := CAPTION_W
	if font != null:
		w = mini(ceili(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			_caption.get_theme_font_size("font_size")).x) + 2, CAPTION_W)
	_caption.custom_minimum_size = Vector2(w, 0)


func _line_done() -> bool:
	return _typed_all or _caption.visible_characters == -1


## The player clicked, tapped or pressed: skip all once seen; else finish the line, then go to the next beat.
func _skip_or_leave() -> void:
	if _left:
		return
	if _skippable:
		skip()
	elif not _line_done():
		_typed_all = true
		_apply()
	elif _beat < Beats.count() - 1:
		_t = Beats.start(_beat + 1)
		_apply()
	else:
		_leave()


## Leaves at once (tests, and any input once the intro has been seen).
func skip() -> void:
	_leave()


func _leave() -> void:
	if _left:
		return
	_left = true
	_hint.visible = false
	GameSettings.set_value("game", SEEN, true)
	Audio.play_ui("ui_confirm")
	finished.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_skip_or_leave()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") or event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		_skip_or_leave()
