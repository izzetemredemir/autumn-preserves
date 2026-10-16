extends Control
## Inbox column of the pantry (spec §7.4): new items wait here and are never lost. Press an item to put it in the
## board's hand (ArrangeBoard.begin_hold); dropping a board item here sends it back (handled by pantry.gd).

const SLOT := 24
const COLS := 6
const PAD := 4
const C_FRAME := Color("83571e")
const C_FRAME_HI := Color("c58845")
const C_FILL := Color("50361e")
const C_SLOT := Color("3d1f29")
const C_HOVER := Color("f2d9c5")

var items: Array = []
var board: ArrangeBoard
var make_view: Callable
var _views: Array[Control] = []
var _hidden := -1
var _hover := -1


func setup(p_items: Array, p_board: ArrangeBoard, p_make_view: Callable) -> void:
	items = p_items
	board = p_board
	make_view = p_make_view
	board.hold_ended.connect(_on_hold_ended)
	mouse_exited.connect(_set_hover.bind(-1))
	refresh()


func capacity() -> int:
	return COLS * floori((size.y - PAD * 2) / SLOT)


func slot_rect(i: int) -> Rect2i:
	return Rect2i(PAD + (i % COLS) * SLOT, PAD + floori(i / float(COLS)) * SLOT, SLOT, SLOT)


func refresh() -> void:
	for v in _views:
		remove_child(v)
		v.queue_free()
	_views.clear()
	for i in mini(items.size(), capacity()):
		var v: Control = make_view.call(items[i], 0, Vector2i(SLOT, SLOT))
		v.position = Vector2(slot_rect(i).position)
		v.visible = i != _hidden
		ArrangeBoard.ignore_mouse(v)
		add_child(v)
		_views.append(v)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hover(-1 if board.is_holding() else _index_at((event as InputEventMouseMotion).position))
		return
	if not (event is InputEventMouseButton) or not event.is_pressed():
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or board.is_holding():
		return
	var i := _index_at(mb.position)
	if i < 0:
		return
	var grab := mb.position - Vector2(slot_rect(i).position)
	if board.begin_hold(items[i], {"where": "inbox", "index": i}, get_global_transform_with_canvas() * mb.position, grab.floor()):
		_hidden = i
		_views[i].visible = false
		_set_hover(-1)
	accept_event()


func _index_at(p: Vector2) -> int:
	for i in mini(items.size(), capacity()):
		if slot_rect(i).has_point(Vector2i(p.floor())):
			return i
	return -1


func _set_hover(i: int) -> void:
	if i != _hover:
		_hover = i
		queue_redraw()


func _on_hold_ended(_item: Dictionary, _placed: bool) -> void:
	_hidden = -1
	refresh()


func _draw() -> void:
	var w := int(size.x)
	var h := int(size.y)
	draw_rect(Rect2(0, 0, w, h), C_FRAME)
	draw_rect(Rect2(0, 0, w, 1), C_FRAME_HI)
	draw_rect(Rect2(2, 2, w - 4, h - 4), C_FILL)
	for i in capacity():
		draw_rect(Rect2(slot_rect(i).grow(-1)), C_SLOT)
	if _hover >= 0:
		var r := slot_rect(_hover)
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), C_HOVER)
		draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), C_HOVER)
		draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), C_HOVER)
		draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), C_HOVER)
	var extra := items.size() - capacity()
	if extra > 0:
		ArrangeItemView.draw_number(self, extra, Vector2i(w - 3, h - 9))
