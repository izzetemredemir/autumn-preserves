class_name GrannyTodo
extends CanvasLayer
## Granny's To-Do note (spec §8.5): today's first-day steps in a small notebook, top right.
## Lives under the tree root so it survives scene changes; `GrannyTodo.ensure()` creates it once.
## Steps tick from GameState.changed (rules in TodoRules); progress is written to state.flags.tutorial.
## Scenes can read `GrannyTodo.current_step()` + TodoRules.SCENE_OF to make the step's object glow.
## FESTIVAL: a festival save shows its six-step checklist under the festival title, even with the tutorial setting off.
## ONBOARD-GUIDE: the note brings Granny's guide along (GuideArrow: arrow over the current step's target, her hint
## bubble, first-time key caps); the guide follows `_step`.

signal step_changed(step: String)

const PAPER := Color("f2d9c5")
const TEXT := Color("50361e")
const DONE := Color("b9a697")
const NOW := Color("a22512")
const FRAME := Color("83571e")
const HIDDEN_IN := ["", "title", "seed_lab"]
const CELEBRATE_SEC := 2.5
const POPUP_LAYERS := Vector2i(12, 60)  # CanvasLayers in this range with visible content hide the note
const NOTE_W := 150  ## collapsed width (x >= 326); a step needing a third line widens to NOTE_WIDE
const NOTE_WIDE := 232
const NOTE_OPEN_W := 210  ## expanded (click to open): long lines wrap inside; human: "açılınca kocaman duruyor"
const MODAL_GROUP := &"modal_card"  ## modal cards/panels outside the popup layers join this group (visible = note hides)
const BODY_FONT := preload("res://assets/fonts/m5x7.ttf")
const ICON_TEX := preload("res://assets/sprites/icons/icon_todo.png")
const PEEK_SEC := 3.0  ## TODO-ICON: the one-line step shows this long after a step changes, then folds to the icon
enum Fold { ICON, PEEK, OPEN }

var _panel: PanelContainer
var _solid: StyleBoxFlat
var _bare := StyleBoxEmpty.new()  ## the icon fold has no paper of its own
var _header: Label
var _root: Control
var _close: Control
var _rows: VBoxContainer
var _bits := -1
var _step := ""
var _fold := Fold.ICON
var _icon: IconFold
var _peek_left := 0.0
var _shown_step := "\u0001"  ## the step last shown in a peek (or open): a scene entry peeks when it differs
var _celebrating := false
var _earned := 0
var _orders := 0
static var _suppressed := 0  ## GrannyTodo.suppress(true/false) from panels that open/close
var _pending_peek := false  ## a step ticked: peek once _refresh knows the new step
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


## A panel or card calls suppress(true) on open and suppress(false) on close: the note hides while any is open.
static func suppress(on: bool) -> void:
	_suppressed = maxi(0, _suppressed + (1 if on else -1))


## The step the player should do next, "" when the note is hidden or finished.
static func current_step() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var todo := tree.get_first_node_in_group("granny_todo") as GrannyTodo if tree != null else null
	if todo == null or not todo.visible:
		return ""
	return todo._step


func _ready() -> void:
	# TODO-ICON: an envelope icon with a "5/7" badge; the step peeks for a few seconds, a click opens the list.
	layer = 11
	add_to_group("granny_todo")
	GuideArrow.ensure()
	_build()
	GameState.changed.connect(_on_changed)
	Router.scene_changed.connect(func(_id: String) -> void:
		if _auto_pinned:
			_auto_pinned = false
			_fold = Fold.ICON
		_evaluate(false)
		if visible and _step != _shown_step and _fold == Fold.ICON:
			_peek())
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
	# JURY-MG: the theme's paper dithers 50 % at 4x and reads as noise: solid paper, one ink-brown edge.
	var solid := StyleBoxFlat.new()
	solid.bg_color = PAPER
	solid.border_color = Color("111010")
	solid.set_border_width_all(1)
	solid.content_margin_left = 7
	solid.content_margin_right = 7
	solid.content_margin_top = 6
	solid.content_margin_bottom = 6
	solid.anti_aliasing = false
	_panel.add_theme_stylebox_override("panel", solid)
	_solid = solid
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
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # HUD-BAR: the whole step shows, on up to 2 lines
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
	_icon = IconFold.new()
	_icon.tooltip_text = tr("UI_TIP_TODO")
	_icon.pressed.connect(_on_icon_pressed)
	box.add_child(_icon)


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


## The money part of ctx since the last check: "delivered" when an order was finished (CUT-CLUTTER: day 2's step),
## "sold" when coins came in without one (the market, a find in the forest).
func _money_since_last() -> Dictionary:
	var stats: Dictionary = GameState.data.get("stats", {})
	var earned := int(stats.get("coins_earned", 0))
	var orders := int(stats.get("orders_done", 0))
	var out := {"delivered": orders > _orders, "sold": earned > _earned and orders == _orders}
	_earned = earned
	_orders = orders
	return out


func _evaluate(feedback: bool) -> void:
	if not GameState.has_game():
		visible = false
		return
	var d: Dictionary = GameState.data
	if not d.has("flags"):
		d["flags"] = {}
	var old := TodoRules.bits_of(d)
	var ctx := _money_since_last()
	ctx["scene"] = Router.current
	var bits := TodoRules.evaluate(d, old, ctx)
	if bits != old:
		d.flags["tutorial"] = bits
	var ticked := feedback and _bits >= 0 and bits != _bits and _visible_for(d, _bits)
	_bits = bits
	if ticked:
		Audio.play_ui("ui_confirm")
		if _fold == Fold.ICON:
			_pending_peek = true
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
	var _step_before := _step
	if step != _step:
		_step = step
		step_changed.emit(step)
	for c in _rows.get_children():
		c.queue_free()
	if visible and _pending_peek and _fold == Fold.ICON:
		_peek()
	elif visible and step != _step_before and _fold == Fold.ICON and step != "":
		_peek()  # a new step appears
	_pending_peek = false
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
		var rl := _label(tr(TodoRules.key_of(s)), color)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # HUD-BAR: long TR lines wrap instead of leaving the screen
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rl.custom_minimum_size = Vector2(40, 0)
		row.add_child(rl)
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


## icon (default): envelope + "n/m" badge. peek: "n/m <current step>" on one line for PEEK_SEC. open (a click, or
## pinned): title, counter, full list. Hover does nothing (touch has none).
func _apply_fold() -> void:
	var open := _fold == Fold.OPEN
	var icon := _fold == Fold.ICON
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
	_icon.set_count(count)
	_icon.visible = icon
	_header.get_parent().visible = not icon
	_rows.visible = open
	_close.visible = open
	_panel.add_theme_stylebox_override("panel", _bare if icon else _solid)
	var w := NOTE_OPEN_W if open else NOTE_W
	if not open and _lines_at(_header.text, NOTE_W - 14) > 2:
		w = NOTE_WIDE
	_panel.custom_minimum_size = Vector2(0 if icon else w, 0)
	_fit()
	_fit.call_deferred()  # wrapped labels know their height one frame later


## Shows the current step for PEEK_SEC (when the note is folded), then folds back to the icon by itself.
func _peek() -> void:
	if _fold == Fold.OPEN:
		return
	_fold = Fold.PEEK
	_peek_left = PEEK_SEC
	_shown_step = _step
	_apply_fold()


func _set_fold(f: Fold) -> void:
	_fold = f
	_peek_left = 0.0
	if f != Fold.ICON:
		_shown_step = _step
	_apply_fold()


## Resizes the note to its content and keeps its right edge at x = 476.
func _fit() -> void:
	if _panel == null:
		return
	_panel.reset_size()
	_panel.position.x = _panel.get_viewport_rect().size.x - 4 - _panel.size.x


## Lines the folded header needs at `width` px of panel content (the close cross is hidden when folded).
func _lines_at(text: String, width: int) -> int:
	var sz := BODY_FONT.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, 16)
	return int(round(sz.y / float(BODY_FONT.get_height(16))))


func _process(_delta: float) -> void:
	if _root == null or not visible:
		return
	var hide_now := _popup_open()
	if _root.visible == hide_now:
		_root.visible = not hide_now
	if hide_now:
		return
	_avoid_hud()
	if _fold == Fold.PEEK:
		_peek_left -= _delta
		if _peek_left <= 0.0:
			_set_fold(Fold.ICON)
	if _panel.size.y > _panel.get_combined_minimum_size().y or _panel.position.x + _panel.size.x != 476.0:
		_fit()  # wrapped labels settle over a couple of frames


## True while a popup/overlay (plant menu, cook panel, book, letters, card) shows content.
func _popup_open() -> bool:
	var tree := get_tree()
	if _suppressed > 0:
		return true
	for m in tree.get_nodes_in_group(MODAL_GROUP):
		if m is CanvasItem and (m as CanvasItem).is_visible_in_tree():
			return true
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
	_auto_pinned = true
	_set_fold(Fold.OPEN)


func is_open() -> bool:
	return _fold == Fold.OPEN


func fold_name() -> String:
	return Fold.keys()[_fold].to_lower()


func _on_icon_pressed() -> void:
	Audio.play_ui("ui_click")
	_set_fold(Fold.OPEN)


## Esc or a click outside the open note folds it to the icon (the click still reaches what is under it).
func _input(event: InputEvent) -> void:
	if _fold != Fold.OPEN or _root == null or not _root.visible or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_auto_pinned = false
		_set_fold(Fold.ICON)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _panel.get_global_rect().has_point(event.position):
			_auto_pinned = false
			_set_fold(Fold.ICON)


func _on_header_input(event: InputEvent) -> void:
	var tap: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if tap:
		_auto_pinned = false
		Audio.play_ui("ui_click")
		_set_fold(Fold.ICON if _fold == Fold.OPEN else Fold.OPEN)


## The cross folds the note back to the icon; it never removes the note (the Tutorial setting does).
func _on_close() -> void:
	Audio.play_ui("ui_back")
	_auto_pinned = false
	_set_fold(Fold.ICON)


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


## TODO-ICON: the "n/m" badge (TEXT on a 1-px PAPER plate) left of the 16x16 envelope; one click target, <= 44x16.
class IconFold:
	extends Control
	signal pressed
	var _text := ""
	var _tw := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_count(t: String) -> void:
		_text = t
		_tw = int(BODY_FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
		custom_minimum_size = Vector2(_tw + 2 + 1 + 16, 16)
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var h := BODY_FONT.get_height(16)
		var top := int((16 - h) / 2)
		draw_rect(Rect2(0, top, _tw + 2, h), PAPER)
		draw_string(BODY_FONT, Vector2(1, top + BODY_FONT.get_ascent(16)), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)
		draw_texture(ICON_TEX, Vector2(_tw + 3, 0))


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


## HUD-BAR: the note sits right under the full-width bar (bar bottom + 2), right edge at x = 476.
func _avoid_hud() -> void:
	var bar := Hud.bar_rect()
	var top := int(bar.end.y) + 2 if bar.has_area() else 30
	if int(_panel.offset_top) != top:
		_panel.offset_top = top
