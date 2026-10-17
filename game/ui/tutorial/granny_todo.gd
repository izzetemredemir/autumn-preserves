class_name GrannyTodo
extends CanvasLayer
## Granny's To-Do note (spec §8.5): today's first-day steps in a small notebook, top right.
## Lives under the tree root so it survives scene changes; `GrannyTodo.ensure()` creates it once.
## Steps tick from GameState.changed (rules in TodoRules); progress is written to state.flags.tutorial.
## Scenes can read `GrannyTodo.current_step()` + TodoRules.SCENE_OF to make the step's object glow.
## FESTIVAL: a festival save shows its six-step checklist under the festival title, even with the tutorial setting off.

signal step_changed(step: String)

const PAPER := Color("f2d9c5")
const TEXT := Color("50361e")
const DONE := Color("b9a697")
const NOW := Color("a22512")
const FRAME := Color("83571e")
const HIDDEN_IN := ["", "title", "seed_lab"]
const CELEBRATE_SEC := 2.5
const POPUP_LAYERS := Vector2i(12, 60)  # CanvasLayers in this range with visible content hide the note
const NOTE_W := 150

var _panel: PanelContainer
var _header: Label
var _root: Control
var _close: Control
var _hover := false
var _rows: VBoxContainer
var _bits := -1
var _step := ""
var _collapsed := false
var _celebrating := false
var _earned := 0
var _orders := 0
var _auto_pinned := false  ## pin_open() holds the note open until the next scene change


static func ensure() -> GrannyTodo:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group("granny_todo") as GrannyTodo
	if found != null:
		return found
	var todo := GrannyTodo.new()
	tree.root.add_child.call_deferred(todo)
	return todo


## The step the player should do next, "" when the note is hidden or finished.
static func current_step() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var todo := tree.get_first_node_in_group("granny_todo") as GrannyTodo if tree != null else null
	if todo == null or not todo.visible:
		return ""
	return todo._step


func _ready() -> void:
	# Always a one-line note; hover peeks at the list, a click pins it open.
	_collapsed = true
	layer = 11
	add_to_group("granny_todo")
	_build()
	GameState.changed.connect(_on_changed)
	Router.scene_changed.connect(func(_id: String) -> void:
		if _auto_pinned:
			_auto_pinned = false
			_collapsed = true
		_evaluate(false))
	_sync_money()
	_evaluate(false)


func _build() -> void:
	var root := Control.new()
	_root = root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/theme.tres")
	add_child(root)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"PaperPanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -4
	_panel.offset_right = -4
	_panel.offset_top = 4
	_panel.custom_minimum_size = Vector2(NOTE_W, 0)
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_header = _label(_title(), FRAME)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.clip_text = true
	_header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header.custom_minimum_size = Vector2(40, 0)
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.gui_input.connect(_on_header_input)
	head.add_child(_header)
	_close = CloseCross.new()
	_close.pressed.connect(_on_close)
	head.add_child(_close)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	box.add_child(_rows)


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return l


func _on_changed(keys: PackedStringArray) -> void:
	if "*" in keys:
		_sync_money()
		_bits = -1
	_evaluate(true)


## "Granny's To-Do", or the festival's title on a festival save.
func _title() -> String:
	return tr("FESTIVAL_NOTE_TITLE") if TodoRules.is_festival(GameState.data) else tr("TUT_TITLE")


func _sync_money() -> void:
	var stats: Dictionary = GameState.data.get("stats", {})
	_earned = int(stats.get("coins_earned", 0))
	_orders = int(stats.get("orders_done", 0))


## Coins earned without a finished order means something was sold.
func _sold_since_last() -> bool:
	var stats: Dictionary = GameState.data.get("stats", {})
	var earned := int(stats.get("coins_earned", 0))
	var orders := int(stats.get("orders_done", 0))
	var sold := earned > _earned and orders == _orders
	_earned = earned
	_orders = orders
	return sold


func _evaluate(feedback: bool) -> void:
	if not GameState.has_game():
		visible = false
		return
	var d: Dictionary = GameState.data
	if not d.has("flags"):
		d["flags"] = {}
	var old := TodoRules.bits_of(d)
	var ctx := {"scene": Router.current, "sold": _sold_since_last()}
	var bits := TodoRules.evaluate(d, old, ctx)
	if bits != old:
		d.flags["tutorial"] = bits
	var ticked := feedback and _bits >= 0 and bits != _bits and _visible_for(d, _bits)
	_bits = bits
	if ticked:
		Audio.play_ui("ui_confirm")
		if TodoRules.day_finished(d, bits):
			_celebrate()
	_refresh(ticked)


func _visible_for(d: Dictionary, bits: int) -> bool:
	if TodoRules.is_closed(bits) or not (GameSettings.tutorial_enabled() or TodoRules.is_festival(d)):
		return false
	if Router.current in HIDDEN_IN:
		return false
	if TodoRules.steps_for(d).is_empty():
		return false
	return _celebrating or not TodoRules.day_finished(d, bits)


func _celebrate() -> void:
	_celebrating = true
	await get_tree().create_timer(CELEBRATE_SEC).timeout
	_celebrating = false
	_refresh(false)


func _refresh(pop_new: bool) -> void:
	var d: Dictionary = GameState.data
	visible = not d.is_empty() and _visible_for(d, _bits)
	var step := TodoRules.current_step(d, _bits) if visible else ""
	if step != _step:
		_step = step
		step_changed.emit(step)
	for c in _rows.get_children():
		c.queue_free()
	_apply_fold()
	if not visible:
		return
	for s in TodoRules.steps_for(d):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		var box := TickBox.new()
		box.done = TodoRules.is_done(_bits, s)
		box.current = s == step
		row.add_child(box)
		var color := DONE if box.done else (NOW if box.current else TEXT)
		row.add_child(_label(tr(TodoRules.key_of(s)), color))
		_rows.add_child(row)
		if pop_new and box.done and s == _last_done(d):
			box.pop()
	if TodoRules.day_finished(d, _bits):
		_rows.add_child(_label(tr("TUT_ALL_DONE"), FRAME))
	_apply_fold()


## The most recently finished step of today's list (the last done one in list order).
func _last_done(d: Dictionary) -> String:
	var last := ""
	for s in TodoRules.steps_for(d):
		if TodoRules.is_done(_bits, s):
			last = s
	return last


## Folded: "n/5 <current step>" on one line. Open (hover or pinned): title, counter, full list.
func _apply_fold() -> void:
	var open := not _collapsed or _hover
	var d: Dictionary = GameState.data
	var total := 0
	var done := 0
	if not d.is_empty():
		for s in TodoRules.steps_for(d):
			total += 1
			if TodoRules.is_done(_bits, s):
				done += 1
	var count := "%d/%d" % [done, total]
	if open:
		_header.text = "%s %s" % [_title(), count]
	elif _step != "":
		_header.text = "%s %s" % [count, tr(TodoRules.key_of(_step))]
	else:
		_header.text = "%s %s" % [count, tr("TUT_ALL_DONE")]
	_rows.visible = open
	_close.visible = open
	_panel.reset_size()


func _process(_delta: float) -> void:
	if _root == null or not visible:
		return
	var hide_now := _popup_open()
	if _root.visible == hide_now:
		_root.visible = not hide_now
	if hide_now:
		_hover = false
		return
	var over := _panel.get_global_rect().has_point(_panel.get_viewport().get_mouse_position())
	if over != _hover:
		_hover = over
		_apply_fold()


## True while a popup/overlay (plant menu, cook panel, book, letters, card) shows content.
func _popup_open() -> bool:
	var tree := get_tree()
	var nodes: Array[Node] = tree.root.get_children()
	if tree.current_scene != null:
		nodes.append_array(tree.current_scene.get_children())
	for n in nodes:
		var cl := n as CanvasLayer
		if cl == null or cl == self or cl.layer < POPUP_LAYERS.x or cl.layer > POPUP_LAYERS.y or not cl.visible:
			continue
		for c in cl.get_children():
			if c is CanvasItem and c.visible:
				return true
	return false


## Opens the note (after the festival's start card: the six steps show at once) until a click folds it or the
## scene changes.
func pin_open() -> void:
	_collapsed = false
	_auto_pinned = true
	_apply_fold()


func is_open() -> bool:
	return _rows != null and _rows.visible


func _on_header_input(event: InputEvent) -> void:
	var tap: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if tap:
		_auto_pinned = false
		_collapsed = not _collapsed
		Audio.play_ui("ui_click")
		_apply_fold()


func _on_close() -> void:
	Audio.play_ui("ui_back")
	var d: Dictionary = GameState.data
	if not d.has("flags"):
		d["flags"] = {}
	_bits = TodoRules.close(TodoRules.bits_of(d))
	d.flags["tutorial"] = _bits
	_refresh(false)


## 9x9 notebook box: empty, ticked, or with a bobbing pointer for the current step.
class TickBox:
	extends Control
	var done := false
	var current := false
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(9, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if current and not done:
			_t += delta
			queue_redraw()

	func pop() -> void:
		pivot_offset = Vector2(4, 6)
		scale = Vector2(1.5, 1.5)
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var y := 2
		draw_rect(Rect2(0, y, 9, 9), Color("83571e"))
		draw_rect(Rect2(1, y + 1, 7, 7), Color("f2d9c5"))
		if done:
			for p in [Vector2i(2, 4), Vector2i(3, 5), Vector2i(4, 6), Vector2i(5, 5), Vector2i(6, 4), Vector2i(7, 3)]:
				draw_rect(Rect2(p.x, y + p.y, 1, 1), Color("4e7664"))
			draw_rect(Rect2(2, y + 5, 1, 1), Color("4e7664"))
			draw_rect(Rect2(4, y + 7, 1, 1), Color("314524"))
		elif current:
			var dx := int(_t * 3.0) % 2
			draw_rect(Rect2(3 + dx, y + 3, 1, 3), Color("a22512"))
			draw_rect(Rect2(4 + dx, y + 4, 1, 1), Color("a22512"))


## 16x16 close button (UI kit icon_close, lifts 1 px on hover): closes the note.
class CloseCross:
	extends Control
	signal pressed
	const ICON := preload("res://assets/sprites/ui/icon_close.png")
	var _hover := false

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		draw_texture(ICON, Vector2(0, -1 if _hover else 0))
