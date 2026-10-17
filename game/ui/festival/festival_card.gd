class_name FestivalCard
extends Control
## FESTIVAL · The Harvest Festival's start card (Mia and Leo came to visit, six jobs today) and end card (what this
## Everfall was grown from: seed, tiles, trees, varieties, new recipes, coins), on a dithered dim. Paper card,
## pops in. Emits `chosen` with "go" (start), "keep" or "title" (end).
## UI-COMPACT: the card is sized to its content (text column WIDTH, under 60 % of the screen), its lines use the body
## font and it sits on the light dim (DitherCover.dim) so the scene stays visible.
##   var c := FestivalCard.new(); add_child(c); c.show_start()  /  c.show_end(FestivalFacts.summary(state))

signal chosen(id: String)

const PAPER := Color("f2d9c5")
const FRAME := Color("83571e")
const TEXT := Color("50361e")
const TITLE := Color("a22512")
const SOFT := Color("83571e")
const WIDTH := 260  ## text column: card 276 px wide with its frame
const PORTRAIT := "res://assets/sprites/portraits/portrait_%s.png"
const KIDS := ["mia", "leo"]

var mode := ""
var _panel: PanelContainer
var _box: VBoxContainer
var _buttons: Array[Button] = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = load("res://ui/theme/theme.tres")


## "Everfall's Harvest Festival!": the two grandchildren, why they came, the six jobs, "Let's go!".
func show_start() -> void:
	_build("start")
	_title(tr("FESTIVAL_START_TITLE"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kid in KIDS:
		row.add_child(_portrait(kid))
	_box.add_child(row)
	_text(tr("FESTIVAL_START_1"))
	_text(tr("FESTIVAL_START_2"), SOFT)
	_add_buttons([["FESTIVAL_GO", "go"]])
	_pop("jgl_morning")


## The summary: facts from FestivalFacts.summary(). Buttons Keep playing / Back to title.
func show_end(facts: Dictionary) -> void:
	_build("end")
	_title(tr("FESTIVAL_END_TITLE"))
	var sep := tr("FESTIVAL_THOUSANDS")
	_text(tr("FESTIVAL_END_MAP") % [int(facts.get("trees", 0)), int(facts.get("clearings", 0)), int(facts.get("paths", 0))])
	if GameSettings.show_seed():
		_text(tr("FESTIVAL_END_SEED") % FestivalFacts.thousands(int(facts.get("seed", 0)), sep), SOFT)
	_text(tr("FESTIVAL_END_FOUND") % [int(facts.get("found", 0)), int(facts.get("new_recipes", 0))])
	_text(tr("FESTIVAL_END_COINS") % int(facts.get("coins", 0)))
	_text(tr("FESTIVAL_END_BYE"), SOFT)
	_add_buttons([["FESTIVAL_KEEP", "keep"], ["FESTIVAL_TO_TITLE", "title"]])
	_pop("jgl_level")


func _build(m: String) -> void:
	mode = m
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	add_child(DitherCover.dim())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = FRAME
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	sb.anti_aliasing = false
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 3)
	_panel.add_child(_box)


func _title(text: String) -> void:
	var l := _label(text, TITLE)
	l.add_theme_font_size_override("font_size", 36)
	_box.add_child(l)


func _text(text: String, color := TEXT) -> void:
	var l := _label(text, color)
	l.theme_type_variation = &"BodyPaper"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH, 0)
	_box.add_child(l)


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return l


## A grandchild's portrait (48 x 48) in a 1 px frame.
func _portrait(kid: String) -> Control:
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("e5bd7f")
	sb.border_color = FRAME
	sb.set_border_width_all(1)
	sb.set_content_margin_all(1)
	sb.anti_aliasing = false
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := TextureRect.new()
	tex.custom_minimum_size = Vector2(48, 48)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(PORTRAIT % kid):
		tex.texture = load(PORTRAIT % kid)
	frame.add_child(tex)
	return frame


func _add_buttons(rows: Array) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	for r in rows:
		var b := Button.new()
		b.text = tr(String(r[0]))
		b.custom_minimum_size = Vector2(72, 0)
		b.pressed.connect(_choose.bind(String(r[1])))
		row.add_child(b)
		_buttons.append(b)
	_buttons[0].grab_focus.call_deferred()


func _choose(id: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play_ui("ui_confirm" if id != "title" else "ui_back")
	chosen.emit(id)


## Pops the paper card in (scale is brief juice) with a jingle.
func _pop(jingle: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play_jingle(jingle)
	_panel.pivot_offset = Vector2.ZERO
	_panel.scale = Vector2(0.6, 0.6)
	_panel.resized.connect(func() -> void: _panel.pivot_offset = (_panel.size / 2.0).floor(), CONNECT_ONE_SHOT)
	_panel.create_tween().tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("cancel") or event.is_action("ui_cancel"):
		get_viewport().set_input_as_handled()
		_choose("go" if mode == "start" else "keep")
