class_name SpeciesCard
extends CanvasLayer
## SPECIES-GEN · The "New species!" card: shown once per species, the first time Granny picks it (SpeciesGen.mark_seen).
## Paper card on a dithered dim: the icon at 3x, the name, what kind it is and how rare, the taste chart, the axis that
## stands out and one line ("Granny notes it in her book."). Closes with its button, Esc, E or Enter; emits `closed`.
##   SpeciesCard.open(parent, species_id).closed.connect(...)

signal closed

const PAPER := Color("f2d9c5")
const FRAME := Color("83571e")
const TEXT := Color("50361e")
const TITLE := Color("a22512")
const SOFT := Color("83571e")
const INK := Color("111010")
const ICON_BG := Color("e5bd7f")
const RARITY_COLORS := {"common": Color("50361e"), "uncommon": Color("4e7664"), "rare": Color("a22512")}

var type := ""
var _panel: PanelContainer
var _ok: Button
var _done := false


static func open(parent: Node, species_id: String) -> SpeciesCard:
	var c := SpeciesCard.new()
	c.type = species_id
	parent.add_child(c)
	return c


func _ready() -> void:
	layer = 30
	_build()
	_pop()


func _build() -> void:
	var sp := SpeciesGen.row(type)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = load("res://ui/theme/theme.tres")
	add_child(root)
	var di := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	di.fill(Color(0, 0, 0, 0))
	di.set_pixel(0, 0, INK)
	di.set_pixel(1, 1, INK)
	var dim := TextureRect.new()
	dim.texture = ImageTexture.create_from_image(di)
	dim.stretch_mode = TextureRect.STRETCH_TILE
	dim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _box_style(PAPER, FRAME, 2, 8))
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)

	var title := _label(tr("SPECIES_NEW_TITLE"), TITLE)
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box_style(ICON_BG, FRAME, 1, 2))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = IconLib.ingredient(type)
	frame.add_child(icon)
	row.add_child(frame)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	var nm := _label(SpeciesGen.display_name(sp), TEXT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(nm)
	var rarity := String(sp.get("rarity", "common"))
	var kind := _label("%s, %s" % [tr("SPECIES_KIND_" + String(sp.get("group", "fruit")).to_upper()),
		tr("BOOK_RARITY_" + rarity.to_upper())], RARITY_COLORS.get(rarity, TEXT))
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(kind)
	var chart := Book.BarChart.new()
	chart.set_taste(sp.get("taste", [0, 0, 0, 0, 0]))
	chart.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chart)

	box.add_child(_label(tr("SPECIES_STANDS_OUT") % tr("UI_TASTE_" + String(sp.get("signature", "sweet")).to_upper()), SOFT))
	box.add_child(_label(tr("SPECIES_NEW_NOTE"), TEXT))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	_ok = Button.new()
	_ok.text = tr("SPECIES_OK")
	_ok.custom_minimum_size = Vector2(72, 0)
	_ok.pressed.connect(close)
	buttons.add_child(_ok)
	_ok.grab_focus.call_deferred()


func close() -> void:
	if _done:
		return
	_done = true
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play_ui("ui_confirm")
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if _done or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("cancel") or event.is_action("ui_cancel") or event.is_action("interact"):
		get_viewport().set_input_as_handled()
		close()


## Pops the paper card in with the new-recipe jingle.
func _pop() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play_jingle("jgl_new_recipe")
	_panel.scale = Vector2(0.6, 0.6)
	_panel.resized.connect(func() -> void: _panel.pivot_offset = (_panel.size / 2.0).floor(), CONNECT_ONE_SHOT)
	_panel.create_tween().tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return l


func _box_style(bg: Color, border: Color, width: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = false
	return sb
