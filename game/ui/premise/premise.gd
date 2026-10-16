class_name Premise
extends Control
## The two-line premise (spec §1.1), shown once on New Game over falling leaves.
## Lines type out; a click, tap or key first finishes the typing, then emits `finished`.

signal finished

const LINES := ["TITLE_PREMISE_1", "TITLE_PREMISE_2"]
const CHARS_PER_SEC := 48.0
const LINE_PAUSE_SEC := 0.5
const TEXT_WIDTH := 360

var _labels: Array[Label] = []
var _hint: Label
var _line := 0
var _chars := 0.0
var _pause := 0.0
var _done := false
var _left := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := TitleBackdrop.new()
	bg.leaves_only = true
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	for key in LINES:
		var l := Label.new()
		l.text = tr(key)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
		l.visible_characters = 0
		box.add_child(l)
		_labels.append(l)
	_labels[1].add_theme_color_override("font_color", Color("e5bd7f"))
	_hint = Label.new()
	_hint.text = tr("TITLE_PREMISE_HINT")
	_hint.add_theme_color_override("font_color", Color("b9a697"))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -28
	_hint.offset_bottom = -12
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = false
	add_child(_hint)


func _process(delta: float) -> void:
	if _done:
		_hint.visible = int(Time.get_ticks_msec() / 500.0) % 2 == 0
		return
	if _pause > 0.0:
		_pause -= delta
		return
	var label := _labels[_line]
	_chars += delta * CHARS_PER_SEC
	label.visible_characters = int(_chars)
	if label.visible_characters >= label.get_total_character_count():
		label.visible_characters = -1
		_next_line()


func _next_line() -> void:
	_line += 1
	_chars = 0.0
	if _line >= _labels.size():
		_done = true
	else:
		_pause = LINE_PAUSE_SEC


func _skip_or_leave() -> void:
	if not _done:
		for l in _labels:
			l.visible_characters = -1
		_line = _labels.size()
		_done = true
		return
	if _left:
		return
	_left = true
	Audio.play_ui("ui_confirm")
	finished.emit()


func _gui_input(event: InputEvent) -> void:
	var tap: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if tap:
		accept_event()
		_skip_or_leave()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") or event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		_skip_or_leave()
