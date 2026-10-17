class_name ArrangeBoard
extends Control
## Generic placement grid (spec §7.4; reused by the parcel §7.6 and the market stall §7.7). It knows nothing about
## pantries: the host passes a board, the entries Array (edited in place) and the rules as Callables.
##   board   {"cols": int, "rows": int, "zones": Array}   row-major zone id per cell, "" = no cell
##   entries [{"item": Dictionary, "x": int, "y": int, "rot": 0|1}]
##   rules   "item_size": func(item, rot) -> Vector2i                                     (required)
##           "can_place": func(board, entries, item, cell: Vector2i, rot, ignore_index) -> bool (required)
##           "zone_for": func(item) -> String               liked-zone outline while holding
##           "in_correct_zone": func(board, entry) -> bool  green vs yellow preview (default: every cell in zone_for)
##           "can_rotate": func(item) -> bool               default: the size changes when turned
##           "stars": func(entries) -> {"stars": int, ...}  star display hook, re-run after every change
##   layout  {"cell": 24, "row_gaps": {row: px above it}, "col_gaps": {col: px}, "zone_colors": {zone: [fill, line]}}
## Input: press an entry to pick it up, drag, release to drop. A tap keeps it in hand until the next press.
## Turn with R, right click or a second finger; Esc puts it back. Items from outside (an inbox) enter with
## begin_hold(); a drop off the board emits released_outside and the host decides (e.g. back to the inbox).
## Views (view_factory) are kept across refreshes while their item, turn and footprint stay the same (QA-FIX: a drop
## rebuilt every view); setup() makes them all again.

signal changed
signal entry_added(index: int, from: Dictionary)
signal entry_moved(index: int)
signal entry_rotated(index: int)
signal entry_removed(index: int, item: Dictionary)
signal hold_started(item: Dictionary, from: Dictionary)
signal hold_ended(item: Dictionary, placed: bool)
signal released_outside(item: Dictionary, from: Dictionary, global_pos: Vector2)
signal drop_refused(item: Dictionary, from: Dictionary)
## {"cell": Vector2i, "size": Vector2i, "fits": bool, "correct": bool, "zone": String}, or {} when off the board.
signal preview_changed(info: Dictionary)
signal stars_changed(result: Dictionary, previous: Dictionary)

const TAP_SLOP := 4.0
const LIFT := 2
const HELD_Z := 50
const C_OK := Color("747c37")
const C_OK_EDGE := Color("b7b768")
const C_WRONG := Color("9b8039")
const C_WRONG_EDGE := Color("dbcc83")
const C_BLOCKED := Color("c94d2e")
const C_HOVER := Color("f2d9c5")
const C_LIKED := Color("e5bd7f")
const C_ORIGIN := Color("b4b3a0")
const C_FILL := Color("49423d")
const C_LINE := Color("23282a")
const VIEW_KEY := &"arrange_view_key"

var board: Dictionary = {}
var entries: Array = []
var rules: Dictionary = {}
## func(item: Dictionary, rot: int, size_px: Vector2i) -> Control. Default: ArrangeItemView.make.
var view_factory: Callable
## Audio ids for "pick", "place", "wrong", "rotate", played through the Audio autoload when it exists.
var sounds: Dictionary = {}
var cell := 24

var _cols := 0
var _rows := 0
var _col_x := PackedInt32Array()
var _row_y := PackedInt32Array()
var _zone_colors: Dictionary = {}
var _views: Array[Control] = []
var _overlay: Control
var _holding := false
var _h_item: Dictionary = {}
var _h_from: Dictionary = {}
var _h_index := -1
var _h_rot := 0
var _h_grab := Vector2.ZERO
var _held_view: Control
var _preview: Dictionary = {}
var _pointer := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _moved := false
var _sticky := false
var _swallow_release := false
var _hover := -1
var _finger0 := Vector2.ZERO
var _stars: Dictionary = {}


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	_ensure_overlay()
	mouse_exited.connect(_on_mouse_exited)


func setup(p_board: Dictionary, p_entries: Array, p_rules: Dictionary, layout: Dictionary = {}) -> void:
	_ensure_overlay()
	cancel_hold()
	board = p_board
	entries = p_entries
	rules = p_rules
	cell = int(layout.get("cell", 24))
	_cols = int(board.get("cols", 0))
	_rows = int(board.get("rows", 0))
	_zone_colors.clear()
	var zc: Dictionary = layout.get("zone_colors", {})
	for z in zc:
		_zone_colors[z] = [Color(str(zc[z][0])), Color(str(zc[z][1]))]
	_col_x = _offsets(_cols, layout.get("col_gaps", {}))
	_row_y = _offsets(_rows, layout.get("row_gaps", {}))
	var w := _col_x[_cols - 1] + cell if _cols > 0 else 0
	var h := _row_y[_rows - 1] + cell if _rows > 0 else 0
	custom_minimum_size = Vector2(w, h)
	size = custom_minimum_size
	_overlay.size = size
	_stars = {}
	refresh(true)
	_update_stars()


# --- queries -------------------------------------------------------------------------------------------------

func is_holding() -> bool:
	return _holding


func held_item() -> Dictionary:
	return _h_item


func stars_result() -> Dictionary:
	return _stars


func view_at(index: int) -> Control:
	return _views[index] if index >= 0 and index < _views.size() else null


func zone_at(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= _cols or c.y >= _rows:
		return ""
	return str(board.zones[c.y * _cols + c.x])


func item_size(item: Dictionary, rot: int) -> Vector2i:
	return rules.item_size.call(item, rot)


func can_place_at(item: Dictionary, c: Vector2i, rot: int, ignore_index: int = -1) -> bool:
	return bool(rules.can_place.call(board, entries, item, c, rot, ignore_index))


func liked_zone(item: Dictionary) -> String:
	return str(rules.zone_for.call(item)) if rules.has("zone_for") else ""


func in_correct_zone_at(item: Dictionary, c: Vector2i, rot: int) -> bool:
	if rules.has("in_correct_zone"):
		return bool(rules.in_correct_zone.call(board, {"item": item, "x": c.x, "y": c.y, "rot": rot}))
	var want := liked_zone(item)
	if want == "":
		return true
	var sz := item_size(item, rot)
	for dy in sz.y:
		for dx in sz.x:
			if zone_at(c + Vector2i(dx, dy)) != want:
				return false
	return true


func can_rotate(item: Dictionary) -> bool:
	if rules.has("can_rotate"):
		return bool(rules.can_rotate.call(item))
	return item_size(item, 0) != item_size(item, 1)


func cell_rect(c: Vector2i) -> Rect2i:
	return Rect2i(_px(_col_x, _cols, c.x), _px(_row_y, _rows, c.y), cell, cell)


## Pixel rect (board-local) covered by `sz` cells from `c`, gaps included.
func footprint_rect(c: Vector2i, sz: Vector2i) -> Rect2i:
	var a := Vector2i(_px(_col_x, _cols, c.x), _px(_row_y, _rows, c.y))
	var b := Vector2i(_px(_col_x, _cols, c.x + sz.x - 1), _px(_row_y, _rows, c.y + sz.y - 1)) + Vector2i(cell, cell)
	return Rect2i(a, b - a)


func entry_rect(index: int) -> Rect2i:
	var e: Dictionary = entries[index]
	return footprint_rect(_cell_of(e), item_size(e.item, _rot_of(e)))


func entry_index_at(local: Vector2) -> int:
	var p := Vector2i(local.floor())
	for i in range(entries.size() - 1, -1, -1):
		if entry_rect(i).has_point(p):
			return i
	return -1


# --- changes ---------------------------------------------------------------------------------------------------

## Rebuilds every item view from `entries` (call after editing entries from outside).
## Places a view on every entry. Views whose item, turn and footprint did not change are moved, not rebuilt;
## `rebuild` makes them all new (setup, or a host whose view_factory now draws differently).
func refresh(rebuild := false) -> void:
	var spare := {}  # view key -> views free to reuse
	for v in _views:
		if not is_instance_valid(v):
			continue
		if rebuild or v.is_queued_for_deletion():
			_drop_view(v)
			continue
		var k := String(v.get_meta(VIEW_KEY, ""))
		if not spare.has(k):
			spare[k] = []
		(spare[k] as Array).append(v)
	_views.clear()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var r := entry_rect(i)
		var rot := _rot_of(e)
		var k := view_key(e.item, rot, r.size)
		var v := _take_view(spare.get(k, []), e.item)
		if v == null:
			v = _make_view(e.item, rot, r.size)
			v.set_meta(VIEW_KEY, k)
			add_child(v)
		v.position = Vector2(r.position)
		v.visible = not (_holding and i == _h_index)
		_views.append(v)
	for k in spare:
		for v: Control in spare[k]:
			_drop_view(v)
	move_child(_overlay, -1)
	queue_redraw()
	_overlay.queue_redraw()


## What a view shows: the item's content, its turn and its footprint in px.
static func view_key(item: Dictionary, rot: int, px: Vector2i) -> String:
	return "%d|%d|%d|%d" % [item.hash(), rot, px.x, px.y]


## A spare view for `item`: the one made for this very item when there is one, else any of the same look.
func _take_view(pool: Array, item: Dictionary) -> Control:
	if pool.is_empty():
		return null
	for j in pool.size():
		var v: Control = pool[j]
		if is_same(v.get("item"), item):
			pool.remove_at(j)
			return v
	return pool.pop_back()


func _drop_view(v: Control) -> void:
	if v.get_parent() == self:
		remove_child(v)
	v.queue_free()


## For hosts that edit `entries` in bulk (auto-arrange): redraw, emit changed, re-run the stars hook.
func notify_changed() -> void:
	refresh()
	_emit_changed()


func remove_entry(index: int) -> Dictionary:
	if index < 0 or index >= entries.size():
		return {}
	if _holding:
		cancel_hold()
	var e: Dictionary = entries[index]
	entries.remove_at(index)
	refresh()
	entry_removed.emit(index, e.item)
	_emit_changed()
	return e.item


func rotate_entry(index: int) -> bool:
	if index < 0 or index >= entries.size():
		return false
	var e: Dictionary = entries[index]
	var nr := 1 - _rot_of(e)
	if not can_rotate(e.item) or not can_place_at(e.item, _cell_of(e), nr, index):
		_play("wrong")
		_nudge(view_at(index))
		return false
	e.rot = nr
	refresh()
	_pop(view_at(index))
	_play("rotate")
	entry_rotated.emit(index)
	_emit_changed()
	return true


## Puts `item` in hand. `from` is {"where": "board", "index": i} for entries, anything else for outside items.
## `pointer` is in viewport coordinates; `grab` is the pointer offset from the item's top-left (default: centre
## of its first cell).
func begin_hold(item: Dictionary, from: Dictionary, pointer: Vector2, grab: Vector2 = Vector2(-1, -1), rot: int = 0) -> bool:
	if _holding or item.is_empty():
		return false
	_holding = true
	_h_item = item
	_h_from = from
	_h_index = int(from.get("index", -1)) if str(from.get("where", "")) == "board" else -1
	_h_rot = rot
	# An item from the inbox is held by the centre of its left/top cell whatever the slot offset was, so the ghost
	# (and the drop) sits under the cursor instead of half a cell off.
	var from_inbox := str(from.get("where", "")) == "inbox"
	_h_grab = grab if grab.x >= 0.0 and not from_inbox else Vector2(cell, cell) * 0.5
	_held_view = _make_view(item, rot, item_size(item, rot) * cell)
	_held_view.z_index = HELD_Z
	add_child(_held_view)
	if view_at(_h_index) != null:
		view_at(_h_index).visible = false
	_press_pos = _to_local(pointer)
	_moved = false
	_sticky = false
	_hover = -1
	_update_hold(_press_pos)
	_pop(_held_view)
	_play("pick")
	hold_started.emit(item, from)
	return true


func rotate_held() -> bool:
	if not _holding:
		return false
	if not can_rotate(_h_item):
		_play("wrong")
		_nudge(_held_view)
		return false
	_h_rot = 1 - _h_rot
	_h_grab = Vector2(_h_grab.y, _h_grab.x)
	_held_view.queue_free()
	_held_view = _make_view(_h_item, _h_rot, item_size(_h_item, _h_rot) * cell)
	_held_view.z_index = HELD_Z
	add_child(_held_view)
	_update_hold(_pointer)
	_pop(_held_view)
	_play("rotate")
	return true


func cancel_hold() -> void:
	if _holding:
		_end_hold(false)


## Moves the held item to a board-local pointer position (input handlers and scripted demos use this).
func move_hold_to(local: Vector2) -> void:
	if _holding:
		_update_hold(local)


## Drops the held item where the preview shows (as a release would).
func drop_held() -> void:
	if _holding:
		_drop()


func pop_all(stagger: float = 0.025) -> void:
	for i in _views.size():
		var v := _views[i]
		v.pivot_offset = (v.size * 0.5).floor()
		var t := v.create_tween()
		t.tween_interval(stagger * i)
		t.tween_property(v, "scale", Vector2(1.15, 1.15), 0.05)
		t.tween_property(v, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		ignore_mouse(c)


# --- input -----------------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if _holding:
		return
	if event is InputEventMouseMotion:
		_set_hover(entry_index_at((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		var i := entry_index_at(mb.position)
		if i < 0:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var e: Dictionary = entries[i]
			var r := entry_rect(i)
			var grab := (mb.position - Vector2(r.position)).floor()
			begin_hold(e.item, {"where": "board", "index": i}, get_global_transform_with_canvas() * mb.position, grab, _rot_of(e))
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			rotate_entry(i)
			accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_on_touch(event)
		return
	if event is InputEventMouseButton:
		var rel := event as InputEventMouseButton
		if _swallow_release and rel.button_index == MOUSE_BUTTON_LEFT and not rel.pressed:
			_swallow_release = false
			get_viewport().set_input_as_handled()
			return
	if not _holding:
		return
	if event is InputEventMouseMotion:
		var p := _to_local((event as InputEventMouseMotion).position)
		if p.distance_to(_press_pos) > TAP_SLOP:
			_moved = true
		_update_hold(p)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var lp := _to_local(mb.position)
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				rotate_held()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if mb.pressed:
				if _sticky:
					_swallow_release = true
					_update_hold(lp)
					_drop()
			elif not _moved and not _sticky:
				_sticky = true
			else:
				_update_hold(lp)
				_drop()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if _is_key(event, "rotate", KEY_R):
		if _holding:
			rotate_held()
		elif _hover >= 0:
			rotate_entry(_hover)
		else:
			return
		get_viewport().set_input_as_handled()
	elif _holding and _is_key(event, "cancel", KEY_ESCAPE):
		cancel_hold()
		get_viewport().set_input_as_handled()


## A second finger turns the held item (or the entry under the first finger).
func _on_touch(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == 0:
			_finger0 = _to_local(d.position)
		return
	var t := event as InputEventScreenTouch
	if t.index == 0:
		_finger0 = _to_local(t.position)
		return
	if not t.pressed:
		return
	if _holding:
		rotate_held()
	else:
		var i := entry_index_at(_finger0)
		if i < 0:
			return
		rotate_entry(i)
	get_viewport().set_input_as_handled()


func _is_key(event: InputEvent, action: String, key: Key) -> bool:
	if InputMap.has_action(action) and event.is_action(action):
		return true
	var k := event as InputEventKey
	return k.physical_keycode == key or k.keycode == key


func _on_mouse_exited() -> void:
	_set_hover(-1)


func _set_hover(i: int) -> void:
	if i != _hover:
		_hover = i
		_overlay.queue_redraw()


# --- hold internals --------------------------------------------------------------------------------------------

func _update_hold(p: Vector2) -> void:
	_pointer = p
	var tl := (p - _h_grab).floor()
	_held_view.position = tl - Vector2(0, LIFT)
	var info := {}
	if Rect2(Vector2.ZERO, size).grow(4.0).has_point(p):
		var sz := item_size(_h_item, _h_rot)
		var c := Vector2i(_nearest(_col_x, tl.x), _nearest(_row_y, tl.y))
		c.x = clampi(c.x, 0, maxi(0, _cols - sz.x))
		c.y = clampi(c.y, 0, maxi(0, _rows - sz.y))
		var fits := can_place_at(_h_item, c, _h_rot, _h_index)
		info = {"cell": c, "size": sz, "fits": fits, "correct": fits and in_correct_zone_at(_h_item, c, _h_rot),
			"zone": liked_zone(_h_item)}
	if info != _preview:
		_preview = info
		preview_changed.emit(info)
	_overlay.queue_redraw()


func _drop() -> void:
	var item := _h_item
	var from := _h_from
	if _preview.is_empty():
		var gp := get_global_transform_with_canvas() * _pointer
		_end_hold(false)
		released_outside.emit(item, from, gp)
		return
	if not bool(_preview.fits):
		_end_hold(false)
		_play("wrong")
		drop_refused.emit(item, from)
		return
	var c: Vector2i = _preview.cell
	var correct: bool = _preview.correct
	var index := _h_index
	if index >= 0:
		var e: Dictionary = entries[index]
		e.x = c.x
		e.y = c.y
		e.rot = _h_rot
		entry_moved.emit(index)
	else:
		entries.append({"item": item, "x": c.x, "y": c.y, "rot": _h_rot})
		index = entries.size() - 1
		entry_added.emit(index, from)
	_end_hold(true)
	refresh()
	_squash(view_at(index))
	_play("place" if correct else "wrong")
	_emit_changed()


func _end_hold(placed: bool) -> void:
	var item := _h_item
	if is_instance_valid(_held_view):
		_held_view.queue_free()
	_held_view = null
	if view_at(_h_index) != null:
		view_at(_h_index).visible = true
	_holding = false
	_h_item = {}
	_h_from = {}
	_h_index = -1
	_sticky = false
	_moved = false
	if not _preview.is_empty():
		_preview = {}
		preview_changed.emit({})
	_overlay.queue_redraw()
	hold_ended.emit(item, placed)


func _emit_changed() -> void:
	changed.emit()
	_update_stars()


func _update_stars() -> void:
	if not rules.has("stars"):
		return
	var r: Dictionary = rules.stars.call(entries)
	if r != _stars:
		var prev := _stars
		_stars = r
		stars_changed.emit(r, prev)


# --- helpers ---------------------------------------------------------------------------------------------------

func _ensure_overlay() -> void:
	if _overlay != null:
		return
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.z_index = 1
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)


func _offsets(n: int, gaps: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var p := 0
	for i in n:
		p += int(gaps.get(i, gaps.get(str(i), 0)))
		out.append(p)
		p += cell
	return out


## Pixel offset of column/row `i`, extrapolated past the edges.
func _px(offs: PackedInt32Array, n: int, i: int) -> int:
	if n == 0:
		return i * cell
	if i < 0:
		return offs[0] + i * cell
	if i >= n:
		return offs[n - 1] + (i - n + 1) * cell
	return offs[i]


func _nearest(offs: PackedInt32Array, v: float) -> int:
	var best := 0
	var best_d := INF
	for i in offs.size():
		var d := absf(v - offs[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func _cell_of(e: Dictionary) -> Vector2i:
	return Vector2i(int(e.get("x", 0)), int(e.get("y", 0)))


func _rot_of(e: Dictionary) -> int:
	return int(e.get("rot", 0))


func _to_local(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos


func _make_view(item: Dictionary, rot: int, px: Vector2i) -> Control:
	var v: Control
	if view_factory.is_valid():
		v = view_factory.call(item, rot, px)
	else:
		v = ArrangeItemView.make(item, rot, px)
	v.size = Vector2(px)
	ignore_mouse(v)
	return v


func _play(key: String) -> void:
	if not sounds.has(key):
		return
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("play_sfx"):
		audio.call("play_sfx", str(sounds[key]))


func _pop(v: Control) -> void:
	if v == null:
		return
	v.pivot_offset = (v.size * 0.5).floor()
	v.scale = Vector2(1.15, 1.15)
	v.create_tween().tween_property(v, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _squash(v: Control) -> void:
	if v == null:
		return
	v.pivot_offset = Vector2(floorf(v.size.x * 0.5), v.size.y)
	v.scale = Vector2(1.2, 0.8)
	v.create_tween().tween_property(v, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _nudge(v: Control) -> void:
	if v == null:
		return
	var x0 := v.position.x
	var t := v.create_tween()
	for dx in [2, -2, 2, -2, 0]:
		t.tween_property(v, "position:x", x0 + dx, 0.03)


# --- drawing ---------------------------------------------------------------------------------------------------

func _draw() -> void:
	for y in _rows:
		for x in _cols:
			var z := zone_at(Vector2i(x, y))
			if z == "":
				continue
			var pair: Array = _zone_colors.get(z, [C_FILL, C_LINE])
			var r := cell_rect(Vector2i(x, y))
			draw_rect(Rect2(r), pair[0])
			draw_rect(Rect2(r.end.x - 1, r.position.y, 1, cell), pair[1])
			draw_rect(Rect2(r.position.x, r.end.y - 1, cell, 1), pair[1])


func _draw_overlay() -> void:
	if not _holding:
		if _hover >= 0 and _hover < entries.size():
			_frame(entry_rect(_hover).grow(1), C_HOVER)
		return
	var want := liked_zone(_h_item)
	if want != "":
		_outline_zone(want, C_LIKED)
	if _h_index >= 0 and _h_index < entries.size():
		_dotted(entry_rect(_h_index), C_ORIGIN)
	if _preview.is_empty():
		return
	var c: Vector2i = _preview.cell
	var sz: Vector2i = _preview.size
	var fits: bool = _preview.fits
	var correct: bool = _preview.correct
	for dy in sz.y:
		for dx in sz.x:
			var cc := c + Vector2i(dx, dy)
			if zone_at(cc) == "":
				continue
			var r := cell_rect(cc)
			if not fits:
				_frame(r, C_BLOCKED)
				_frame(r.grow(-1), C_BLOCKED)
			elif correct:
				_overlay.draw_rect(Rect2(r.grow(-1)), C_OK)
				_frame(r.grow(-1), C_OK_EDGE)
			else:
				# Wrong zone is allowed: yellow with diagonal stripes, so it does not rely on colour alone.
				var inner := r.grow(-1)
				_overlay.draw_rect(Rect2(inner), C_WRONG)
				for py in range(inner.position.y, inner.end.y):
					for px in range(inner.position.x, inner.end.x):
						if posmod(px + py, 4) == 0:
							_overlay.draw_rect(Rect2(px, py, 1, 1), C_WRONG_EDGE)
				_frame(inner, C_WRONG_EDGE)


func _frame(r: Rect2i, col: Color) -> void:
	_overlay.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), col)
	_overlay.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), col)
	_overlay.draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), col)
	_overlay.draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), col)


func _dotted(r: Rect2i, col: Color) -> void:
	for x in range(r.position.x, r.end.x, 2):
		_overlay.draw_rect(Rect2(x, r.position.y, 1, 1), col)
		_overlay.draw_rect(Rect2(x, r.end.y - 1, 1, 1), col)
	for y in range(r.position.y, r.end.y, 2):
		_overlay.draw_rect(Rect2(r.position.x, y, 1, 1), col)
		_overlay.draw_rect(Rect2(r.end.x - 1, y, 1, 1), col)


## 1-px outline just outside every cell of `zone`, on edges that border another zone, no cell or a gap.
func _outline_zone(zone: String, col: Color) -> void:
	for y in _rows:
		for x in _cols:
			var c := Vector2i(x, y)
			if zone_at(c) != zone:
				continue
			var r := cell_rect(c)
			if x == 0 or zone_at(c + Vector2i.LEFT) != zone or cell_rect(c + Vector2i.LEFT).end.x != r.position.x:
				_overlay.draw_rect(Rect2(r.position.x - 1, r.position.y - 1, 1, cell + 2), col)
			if x == _cols - 1 or zone_at(c + Vector2i.RIGHT) != zone or cell_rect(c + Vector2i.RIGHT).position.x != r.end.x:
				_overlay.draw_rect(Rect2(r.end.x, r.position.y - 1, 1, cell + 2), col)
			if y == 0 or zone_at(c + Vector2i.UP) != zone or cell_rect(c + Vector2i.UP).end.y != r.position.y:
				_overlay.draw_rect(Rect2(r.position.x - 1, r.position.y - 1, cell + 2, 1), col)
			if y == _rows - 1 or zone_at(c + Vector2i.DOWN) != zone or cell_rect(c + Vector2i.DOWN).position.y != r.end.y:
				_overlay.draw_rect(Rect2(r.position.x - 1, r.end.y, cell + 2, 1), col)
