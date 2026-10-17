class_name BiomePicker
extends CanvasLayer
## BIOMES · The garden gate's "where to today?" card (spec §5, §7.1): forest, vineyard and creek with today's map
## seed. A locked biome shows what opens it and cannot be picked (vineyard: Economy.unlocked("vineyard"), Vito's
## 2-heart key; creek: Economy.unlocked("boots"), the grocer's rubber boots). The list and the locks come from
## WildGen.biome_choices; the card only reports the choice, the caller goes to the wild scene with it:
##   var p := BiomePicker.new(); add_child(p); p.open(GameState.data)
##   p.chosen.connect(func(b: String) -> void: Transition.go("wild", {"biome": b}))
## Mouse, touch and keys (arrows + Enter; Esc or a tap outside closes). Same paper card as the garden's PlantMenu.

signal chosen(biome: String)
signal closed

## Row icon per biome (16x16 ingredient icons).
const ICONS := {"forest": "chanterelle", "vineyard": "grape", "creek": "elderberry"}
const ICON := "res://assets/sprites/icons/%s.png"
const C_TITLE := Color("83571e")
const C_LOCKED := Color("23282a")  ## readable on the theme's grey disabled button

var _rows: Array[Button] = []
var _first: Button
var _done := false


func open(state: Dictionary) -> void:
	layer = 20
	var root := CenterContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_outside_input)
	add_child(root)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PaperPanel"
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"PaperLabel"
	title.add_theme_color_override("font_color", C_TITLE)
	title.text = tr("WILD_PICK_TITLE")
	box.add_child(title)
	for c: Dictionary in WildGen.biome_choices(state):
		var id := String(c.id)
		var b := Button.new()
		b.name = id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 20)
		var path := ICON % String(ICONS.get(id, ""))
		if ResourceLoader.exists(path):
			b.icon = load(path)
		var biome_name := tr("WILD_BIOME_" + id.to_upper())
		if bool(c.open):
			b.text = "%s  -  %s" % [biome_name, tr("UI_WEATHER_" + String(state.get("weather", "sunny")).to_upper())]
			b.pressed.connect(choose.bind(id))
			if _first == null:
				_first = b
		else:
			b.text = "%s  -  %s" % [biome_name, tr("WILD_LOCKED_" + id.to_upper())]
			b.disabled = true
			b.add_theme_color_override("font_disabled_color", C_LOCKED)
		box.add_child(b)
		_rows.append(b)
	var cancel := Button.new()
	cancel.text = tr("UI_CANCEL")
	cancel.custom_minimum_size = Vector2(0, 20)
	cancel.pressed.connect(close)
	box.add_child(cancel)
	if _first == null:
		_first = cancel
	_first.grab_focus.call_deferred()


func is_open() -> bool:
	return not _done


## The row button of a biome (tests and smoke shots), or null.
func row(id: String) -> Button:
	for b in _rows:
		if b.name == id:
			return b
	return null


func choose(biome: String) -> void:
	if _done:
		return
	Audio.play_ui("ui_click")
	chosen.emit(biome)
	close()


func close() -> void:
	if _done:
		return
	_done = true
	closed.emit()
	queue_free()


func _on_outside_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Audio.play_ui("ui_back")
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not _done and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		Audio.play_ui("ui_back")
		close()
