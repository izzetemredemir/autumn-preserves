class_name SpeciesCard
extends CanvasLayer
## SPECIES-GEN · The "New species!" note: shown once per species, the first time Granny picks it (SpeciesGen.mark_seen).
## UI-COMPACT: a small paper toast at the top of the screen that never stops Granny: the icon at 2x, "New species!"
## and the name. It slides in under the HUD with the new-recipe jingle, goes away by itself after SECONDS, and a click
## on it opens the book at the forest species page that lists it. Emits `closed` when it is gone.
##   SpeciesCard.open(parent, species_id).closed.connect(...)

signal closed

const PAPER := Color("f2d9c5")
const FRAME := Color("83571e")
const TITLE := Color("a22512")
const ICON_BG := Color("e5bd7f")
const SECONDS := 4.0
const TOP := 34  ## px from the screen's top edge: just under the HUD row
const SLIDE := 0.18

var type := ""
var _panel: PanelContainer
var _tween: Tween
var _done := false


## Shows the note for `species_id` under `parent`; a note already showing there gives way to it.
static func open(parent: Node, species_id: String) -> SpeciesCard:
	for c in parent.get_children():
		if c is SpeciesCard:
			(c as SpeciesCard).close()
	var c := SpeciesCard.new()
	c.type = species_id
	parent.add_child(c)
	return c


func _ready() -> void:
	layer = 30
	_build()
	_slide_in()


func _build() -> void:
	var sp := SpeciesGen.row(type)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never blocks the scene: only the note itself takes a click
	root.theme = load("res://ui/theme/theme.tres")
	add_child(root)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _box_style(PAPER, FRAME, 1, 4))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_panel.gui_input.connect(_on_input)
	root.add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box_style(ICON_BG, FRAME, 1, 0))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = IconLib.ingredient(type)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(icon)
	row.add_child(frame)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var title := Label.new()
	title.text = tr("SPECIES_NEW_TITLE")
	title.add_theme_color_override("font_color", TITLE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(title)
	var nm := Label.new()
	nm.theme_type_variation = &"BodyPaper"
	nm.text = SpeciesGen.display_name(sp)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(nm)
	_panel.size = _panel.get_combined_minimum_size()


## Slides down from above the screen, stays SECONDS, slides back up and goes.
func _slide_in() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play_jingle("jgl_new_recipe")
	var vw := _panel.get_viewport_rect().size.x
	_panel.position = Vector2(roundi((vw - _panel.size.x) / 2.0), -_panel.size.y - 2)
	_tween = _panel.create_tween()
	_tween.tween_property(_panel, "position:y", float(TOP), SLIDE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(SECONDS)
	_tween.tween_property(_panel, "position:y", -_panel.size.y - 2, SLIDE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(close)


func _on_input(event: InputEvent) -> void:
	if _done or not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	_panel.accept_event()
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play_ui("ui_confirm")
	open_book()
	close()


## Opens the book's Varieties tab at the forest species spread that lists this species.
func open_book() -> void:
	var b := Book.open()
	if b == null:
		return
	b.show_book(1)
	var gs := get_node_or_null("/root/GameState")
	var d: Dictionary = gs.data if gs != null else {}
	var index := 0
	var list := SpeciesGen.known(int(d.get("save_seed", 0)), int(d.get("day", 1)))
	for i in list.size():
		if String(list[i].get("id", "")) == type:
			index = i
			break
	b._page = b._type_pages() + floori(index / float(SpeciesPage.LEFT_ROWS + SpeciesPage.RIGHT_ROWS))
	b._refresh()


func close() -> void:
	if _done:
		return
	_done = true
	if _tween != null:
		_tween.kill()
	closed.emit()
	queue_free()


func _box_style(bg: Color, border: Color, width: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_content_margin_all(margin + width)
	sb.anti_aliasing = false
	return sb
