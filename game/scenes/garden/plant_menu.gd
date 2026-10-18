extends CanvasLayer
## GD-GARDEN · "Plant what?" card for an empty bed: one button per seed packet in the cupboard, Cancel. Mouse, touch
## and keys (arrows + Enter; Esc or a tap outside closes). CUT-CLUTTER: no fertilizer toggle (Garden.plant_auto uses
## the compost's fertilizer by itself). It only reports the choice; the garden scene plants.
##   var m := PlantMenu.new(); add_child(m); m.open([{"crop": "cucumber", "count": 2}])

signal chosen(crop: String)
signal closed

const ICON := "res://assets/sprites/icons/seed_%s.png"
const C_TITLE := Color("83571e")

var _first: Button
var _done := false


func open(options: Array) -> void:
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
	title.text = tr("GARDEN_PLANT_TITLE")
	box.add_child(title)
	for o in options:
		var crop := String(o.crop)
		var b := Button.new()
		b.text = "%s x%d" % [tr("TOWN_ITEM_SEED_" + crop.to_upper()), int(o.count)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 20)
		var path := ICON % crop
		if ResourceLoader.exists(path):
			b.icon = load(path)
		b.pressed.connect(choose.bind(crop))
		box.add_child(b)
		if _first == null:
			_first = b
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


func choose(crop: String) -> void:
	if _done:
		return
	chosen.emit(crop)
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
