extends Control
## Pantry (spec §7.4, tech-spec §7): shelf grid on the right (ArrangeBoard driven by PantryRules), inbox on the
## left, live stars, Auto-arrange and Back. Every move goes straight into GameState.data.pantry / inbox, followed
## by GameState.notify(["pantry", "inbox"]). Opened without a running game it starts seed 1 with sample items.
## Bought shelves (PantryRules.add_shelf, up to 3) keep the painted look: every one makes the room one BAND taller
## by repeating rows cut from BG (BG_STRIPS: a board, a name plate, a taller crate), and the room then scrolls
## under the fixed left column (inbox, stars, buttons): mouse wheel or trackpad, drag on empty space, W/S or
## Up/Down, and auto-scroll near the top/bottom edge while an item is held, so it can go on any shelf.

const InboxView := preload("res://scenes/pantry/inbox_view.gd")
const CELL := 24
## Aligned to the drawn shelves of BG (ART-BG-A): shelves x=312..456 (inner shelf 300..470), block tops y=8/68/128
## so each bottom row stands on a board (top surfaces y~48/105/165), floor block y=206..254 on the floor planks.
## Bought shelves continue the rhythm (block tops 188/248/308, floor 60 px lower each) in room coordinates.
const BG := "res://assets/sprites/scenes/bg_pantry.png"
const BOARD_X := 312
const BOARD_TOP := 8
const BOARD_BOTTOM := 254
const SHELF_GAP := 12
const FLOOR_GAP := 30
const LABEL_W := 38
## Blank name plates painted on the shelf post of BG, one per base shelf (top to bottom): shelf labels sit on them.
const PLATES := [Rect2i(261, 18, 36, 18), Rect2i(261, 75, 36, 18), Rect2i(261, 130, 36, 18)]
## One shelf tier of the room (2 cell rows + SHELF_GAP): each bought shelf makes the room this much taller.
const BAND := 60
## Vertical strips of BG, each grown by BAND rows per bought shelf by repeating rows that tile seamlessly there
## (no new art): [x0, x1, band_y, band_h, insert_y]. band_h divides BAND; rows from insert_y on slide down.
const BG_STRIPS := [
	[0, 122, 166, 30, 196],   # window wall, crate and bush: the crate grows taller
	[122, 302, 100, 60, 160], # door and shelf post: one more name plate (a copy of PLATES[2], BAND lower each)
	[302, 480, 80, 60, 140],  # shelves: one more board, cut through the dark back wall so no seam shows
]
## Scrolling (only when bought shelves make the room taller than the screen).
const SCROLL_X := 258 # the shelf column: edge auto-scroll works right of this x
const WHEEL_STEP := 24.0
const PAN_STEP := 6.0 # trackpad pan gesture, px per unit of delta
const EDGE := 18 # a held item this close to the top/bottom edge of the shelf column scrolls the room
const EDGE_SPEED := 200.0
const SCROLL_EASE := 14.0
const SCROLL_MIN_SPEED := 90.0
const SCROLL_BAR_X := 475 # arrows and thumb on the right shelf post (x 471..479), clear of plates and items
## Fallback look (no art): opaque cells and drawn shelf frames.
const ZONE_COLORS := {
	"dry": ["50361e", "3d1f29"], "room": ["62272c", "3d1f29"], "cool": ["2e3f3f", "23282a"], "floor": ["49423d", "23282a"],
}
## On the art: no fill, only a thin on-palette cell grid in the zone colour (subtle tint, no partial alpha).
const ZONE_TINTS := {
	"dry": ["00000000", "50361e"], "room": ["00000000", "62272c"], "cool": ["00000000", "2e3f3f"], "floor": ["00000000", "49423d"],
}
const SOUNDS := {"pick": "sfx_pantry_pick", "place": "sfx_pantry_place", "wrong": "sfx_pantry_wrong", "rotate": "sfx_piece_rotate"}
const STAR_FULL := "res://assets/sprites/ui/icon_star_full.png"
const STAR_EMPTY := "res://assets/sprites/ui/icon_star_empty.png"
const C_WALL := Color("3d1f29")
const C_WALL_LINE := Color("50361e")
const C_WOOD := Color("83571e")
const C_WOOD_HI := Color("c58845")
const C_WOOD_DARK := Color("50361e")
const C_STONE_EDGE := Color("23282a")
const C_TEXT := Color("f2d9c5")
const C_TEXT_DIM := Color("b9a697")
const C_TEXT_HI := Color("e5bd7f")
const C_INK := Color("111010")

@onready var board: ArrangeBoard = %Board
@onready var inbox_view: InboxView = %Inbox
@onready var inbox_count: Label = %InboxCount
@onready var inbox_empty: Label = %InboxEmpty
@onready var bonus: Label = %Bonus
@onready var hint: Label = %Hint
@onready var bubble: Control = %Bubble

var _rule_labels: Array[Label] = []
var _rule_icons: Array[TextureRect] = []
var _zone_labels: Array[Label] = []
var _label_zone: Array[String] = []
## Unscrolled (room) y of each zone label.
var _label_y: Array[int] = []
var _blocks: Array[Rect2i] = []
var _block_zone: Array[String] = []
var _full: Texture2D
var _empty: Texture2D
var _bg: Texture2D
## True when the room is painted (BG loaded), for any number of bought shelves.
var _on_art := false
var _bubble_tween: Tween
## Bought shelves below the base ones; the room is BAND px taller per shelf.
var _extra := 0
var _scroll := 0.0
var _scroll_to := 0.0
var _scroll_max := 0
## Applied scroll in whole pixels: the room, board and shelf labels sit this much higher.
var _offset := 0
## Last pointer position (viewport), for edge auto-scroll and keeping a held item under the pointer.
var _pointer := Vector2(-1, -1)
var _panning := false
## Edge auto-scroll waits until the held item has been outside the edge zone once (picking up near it is no move).
var _edge_armed := false
var _hints: Control


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_temp(1)
		GameState.data.inbox.append_array(sample_items())
	var data: Dictionary = GameState.data
	var pantry: Dictionary = data.pantry
	var b := PantryRules.board_of(pantry)
	_bg = load(BG) if ResourceLoader.exists(BG) else null
	var layout := _layout(b)
	board.position = Vector2(BOARD_X, BOARD_TOP)
	board.view_factory = _make_view
	board.sounds = SOUNDS
	board.changed.connect(_on_board_changed)
	board.entry_added.connect(_on_entry_added)
	board.released_outside.connect(_on_released_outside)
	board.stars_changed.connect(_on_stars_changed)
	board.hold_started.connect(_on_hold_started)
	board.hold_ended.connect(_on_hold_ended)
	_build_rule_stars()
	board.setup(b, pantry.items, {
		"item_size": _item_size, "can_place": _can_place, "zone_for": _zone_for,
		"in_correct_zone": _in_zone, "can_rotate": _can_rotate, "stars": _stars_now,
	}, layout)
	_scroll_max = maxi(0, BOARD_TOP + int(board.size.y) - BOARD_BOTTOM)
	_build_blocks(b)
	inbox_view.setup(data.inbox, board, _make_view)
	%AutoArrange.pressed.connect(_on_auto)
	%Back.pressed.connect(_on_back)
	_hints = Control.new()
	_hints.name = "ScrollHints"
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hints)
	_hints.draw.connect(_draw_scroll_hints)
	_refresh_inbox_labels()
	_set_hint("")
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		_on_back()


## Scrolling runs before the GUI so focused buttons do not eat Up/Down and the wheel works over the board.
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer = (event as InputEventMouse).position
	if _scroll_max <= 0 or not is_visible_in_tree():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var f := clampf(mb.factor, 0.25, 4.0) if mb.factor > 0.0 else 1.0
				scroll_to(_scroll_to + WHEEL_STEP * f * (-1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0))
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_panning = mb.pressed and _is_empty_space(mb.position)
	elif event is InputEventMouseMotion:
		if not _panning:
			return
		var mm := event as InputEventMouseMotion
		if board.is_holding() or (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_panning = false
			return
		scroll_to(_scroll_to - mm.relative.y, true)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		scroll_to(_scroll_to + (event as InputEventPanGesture).delta.y * PAN_STEP, true)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_pressed():
		var dir := 1 if event.is_action("move_down") else (-1 if event.is_action("move_up") else 0)
		if dir != 0:
			scroll_to(snappedf(_scroll_to, BAND) + dir * BAND)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _scroll_max <= 0:
		return
	if board.is_holding():
		var dir := _edge_dir(_pointer)
		if dir == 0:
			_edge_armed = true
		elif _edge_armed and _pointer.x >= SCROLL_X:
			scroll_to(_scroll_to + dir * EDGE_SPEED * delta, true)
			return
	if _scroll != _scroll_to:
		var ease_step := absf(_scroll_to - _scroll) * (1.0 - exp(-SCROLL_EASE * delta))
		_scroll = move_toward(_scroll, _scroll_to, maxf(ease_step, SCROLL_MIN_SPEED * delta))
		_apply_scroll()


# --- scrolling (public for scripted demos and the smoke shot) ---------------------------------------------------

## Scrolls the room so room row `y` is at the top of the screen (clamped). `instant` skips the easing.
func scroll_to(y: float, instant := false) -> void:
	_scroll_to = clampf(y, 0.0, float(_scroll_max))
	if instant:
		_scroll = _scroll_to
		_apply_scroll()


func scroll_offset() -> int:
	return _offset


func scroll_max() -> int:
	return _scroll_max


func on_art() -> bool:
	return _on_art


## Name plate of shelf `i` in room coordinates: the three painted ones, then one copy per bought shelf.
static func plate_rect(i: int) -> Rect2i:
	if i < PLATES.size():
		return PLATES[i]
	var last: Rect2i = PLATES[PLATES.size() - 1]
	return Rect2i(last.position + Vector2i(0, BAND * (i - PLATES.size() + 1)), last.size)


func _apply_scroll() -> void:
	var off := clampi(roundi(_scroll), 0, _scroll_max)
	if off == _offset:
		return
	_offset = off
	board.position.y = BOARD_TOP - off
	for i in _zone_labels.size():
		_zone_labels[i].position.y = _label_y[i] - off
	if board.is_holding() and _pointer.x >= 0.0:
		board.move_hold_to(board.get_global_transform_with_canvas().affine_inverse() * _pointer)
	queue_redraw()
	_hints.queue_redraw()


## -1 / 1 when `p` is in the top / bottom auto-scroll zone of the screen, else 0.
func _edge_dir(p: Vector2) -> int:
	if p.y < EDGE:
		return -1
	if p.y >= size.y - EDGE:
		return 1
	return 0


## Drag-to-scroll starts on empty space only: not the inbox, a button or a shelf item, with nothing in hand.
func _is_empty_space(p: Vector2) -> bool:
	if board.is_holding() or not get_global_rect().has_point(p):
		return false
	for c: Control in [inbox_view, %AutoArrange, %Back]:
		if c.get_global_rect().has_point(p):
			return false
	if board.get_global_rect().has_point(p):
		return board.entry_index_at(board.get_global_transform_with_canvas().affine_inverse() * p) < 0
	return true


## Test and first-run content: a few of every kind and size (jars, bottle, pie, bread, fresh stacks, nuts).
static func sample_items() -> Array:
	return [
		State.product("jam|apple_1|-", 2, 0),
		State.product("jam|quince_1|-", 3, 0),
		State.product("jam|pear_2|-", 2, 0),
		State.product("jam|crabapple_1|-", 1, 0),
		State.product("pie|apple_1|-", 2, 0, 3),
		State.product("pickle|cucumber_1|-", 2, 2),
		State.product("pickle|cucumber_2|-", 1, 2),
		State.product("chutney|pear_1|pepper_1|-", 2, 0),
		State.product("brined_mushroom|chanterelle_1|-", 2, 1),
		State.product("bread|-", 1, 0, 3),
		State.product("juice|apple_2|-", 2, 0),
		State.fresh("apple_1", 5, 6),
		State.fresh("blackberry_2", 3, 2),
		State.fresh("chanterelle_1", 2, 2),
		State.nut("walnut", 8),
	]


# --- rules (PantryRules, wrapped as Callables for the generic board) --------------------------------------------

func _item_size(item: Dictionary, rot: int) -> Vector2i:
	return PantryRules.item_size(item, rot)


func _can_place(b: Dictionary, entries: Array, item: Dictionary, c: Vector2i, rot: int, ignore: int) -> bool:
	return PantryRules.can_place(b, entries, item, c, rot, ignore)


func _zone_for(item: Dictionary) -> String:
	return PantryRules.zone_for(item)


func _in_zone(b: Dictionary, entry: Dictionary) -> bool:
	return PantryRules.in_correct_zone(b, entry)


func _can_rotate(item: Dictionary) -> bool:
	return PantryRules.can_rotate(item)


func _stars_now(_entries: Array) -> Dictionary:
	return PantryRules.state_stars(GameState.data)


func _make_view(item: Dictionary, rot: int, px: Vector2i) -> Control:
	return ArrangeItemView.make(item, rot, px, GameState.data.varieties)


# --- layout ------------------------------------------------------------------------------------------------------

## Same gaps for every shelf count (one shelf tier = BAND px): bought shelves make the room taller, never tighter.
func _layout(b: Dictionary) -> Dictionary:
	var rows := int(b.rows)
	var floor_y := int(b.get("floor_y", rows))
	var shelves: Array = b.get("shelves", [])
	var gaps := {}
	for sh in shelves:
		if int(sh.y) > 0:
			gaps[int(sh.y)] = SHELF_GAP
	if floor_y > 0 and floor_y < rows:
		gaps[floor_y] = FLOOR_GAP
	_extra = maxi(shelves.size() - PLATES.size(), 0)
	_on_art = _bg != null
	return {"cell": CELL, "row_gaps": gaps, "zone_colors": ZONE_TINTS if _on_art else ZONE_COLORS}


func _build_blocks(b: Dictionary) -> void:
	for sh in b.get("shelves", []):
		_add_block(int(sh.y), int(sh.rows), String(sh.zone), true)
	var floor_y := int(b.get("floor_y", int(b.rows)))
	if floor_y < int(b.rows):
		_add_block(floor_y, int(b.rows) - floor_y, String(Data.rules().pantry.floor.zone), false)


## A shelf's label sits on its painted name plate; the floor's (and every label without art) beside its block.
func _add_block(y0: int, n: int, zone: String, shelf: bool) -> void:
	var rect := Rect2i()
	var found := false
	for y in range(y0, y0 + n):
		for x in int(board.board.cols):
			if board.zone_at(Vector2i(x, y)) == "":
				continue
			var r := board.cell_rect(Vector2i(x, y))
			rect = rect.merge(r) if found else r
			found = true
	if not found:
		return
	_blocks.append(rect)
	_block_zone.append(zone)
	var l := Label.new()
	l.text = _zone_name(zone)
	if _on_art and shelf:
		var plate := plate_rect(_blocks.size() - 1)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(plate.position)
		l.size = Vector2(plate.size)
	else:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.position = Vector2(BOARD_X - LABEL_W - 6, BOARD_TOP + rect.position.y + 3)
		l.size = Vector2(LABEL_W, 16)
	l.add_theme_color_override("font_color", C_TEXT_DIM)
	add_child(l)
	_zone_labels.append(l)
	_label_zone.append(zone)
	_label_y.append(int(l.position.y))


func _build_rule_stars() -> void:
	_full = load(STAR_FULL) if ResourceLoader.exists(STAR_FULL) else null
	_empty = load(STAR_EMPTY) if ResourceLoader.exists(STAR_EMPTY) else null
	for l: Label in [%RuleZone, %RuleGroup, %RulePretty]:
		var t := TextureRect.new()
		t.texture = _empty
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.position = Vector2(int(l.position.x) - 18, int(l.position.y))
		t.size = Vector2(16, 16)
		add_child(t)
		_rule_icons.append(t)
		_rule_labels.append(l)


func _zone_name(z: String) -> String:
	match z:
		"dry":
			return tr("PANTRY_ZONE_DRY")
		"room":
			return tr("PANTRY_ZONE_ROOM")
		"cool":
			return tr("PANTRY_ZONE_COOL")
		"floor":
			return tr("PANTRY_ZONE_FLOOR")
	return z.capitalize()


# --- board events ------------------------------------------------------------------------------------------------

func _on_board_changed() -> void:
	inbox_view.refresh()
	_refresh_inbox_labels()
	GameState.notify(PackedStringArray(["pantry", "inbox"]))


func _on_entry_added(_index: int, from: Dictionary) -> void:
	if String(from.get("where", "")) != "inbox":
		return
	var inbox: Array = GameState.data.inbox
	var i := int(from.get("index", -1))
	if i >= 0 and i < inbox.size():
		inbox.remove_at(i)


## A board item dropped on the inbox goes back there; anywhere else it returns to its cell.
func _on_released_outside(item: Dictionary, from: Dictionary, global_pos: Vector2) -> void:
	if String(from.get("where", "")) != "board" or not inbox_view.get_global_rect().has_point(global_pos):
		return
	GameState.data.inbox.append(item)
	board.remove_entry(int(from.index))
	Audio.play_sfx("sfx_pantry_place")


func _on_stars_changed(result: Dictionary, prev: Dictionary) -> void:
	var flags: Array = result.get("rules", [false, false, false])
	var was: Array = prev.get("rules", [false, false, false])
	var first := prev.is_empty()
	var newly := 0
	for i in mini(flags.size(), _rule_icons.size()):
		var on := bool(flags[i])
		_rule_icons[i].texture = _full if on else _empty
		_rule_labels[i].add_theme_color_override("font_color", C_TEXT if on else C_TEXT_DIM)
		if on and not first and not bool(was[i]):
			newly += 1
			_pop(_rule_icons[i], 1.6)
	if newly > 0:
		Audio.play_sfx("sfx_star_pop")
	var n := int(result.get("stars", 0))
	var per := int(Data.rules().energy.pantry_bonus_per_star)
	bonus.text = tr("PANTRY_BONUS") % (n * per) if n > 0 else tr("PANTRY_BONUS_NONE")
	if n >= 3 and not first and int(prev.get("stars", 0)) < 3:
		Audio.play_jingle("jgl_pantry_3stars")
		_show_lovely()


func _on_hold_started(item: Dictionary, _from: Dictionary) -> void:
	_edge_armed = _edge_dir(_pointer) == 0
	_set_hint(PantryRules.zone_for(item))
	inbox_empty.visible = false


func _on_hold_ended(_item: Dictionary, _placed: bool) -> void:
	_set_hint("")
	_refresh_inbox_labels()


func _on_auto() -> void:
	board.cancel_hold()
	var data: Dictionary = GameState.data
	var inbox: Array = data.inbox
	if inbox.is_empty():
		Audio.play_sfx("sfx_pantry_wrong")
		return
	var left := PantryRules.auto_arrange(data.pantry, inbox.duplicate())
	inbox.clear()
	inbox.append_array(left)
	if not is_same(board.entries, data.pantry.items):
		board.entries = data.pantry.items
	board.notify_changed()
	board.pop_all()
	Audio.play_sfx("sfx_pantry_auto")


func _on_back() -> void:
	board.cancel_hold()
	Router.goto("kitchen" if Router.exists("kitchen") else "title")


# --- view helpers ------------------------------------------------------------------------------------------------

func _refresh_inbox_labels() -> void:
	var n: int = GameState.data.inbox.size()
	inbox_count.text = str(n) if n > 0 else ""
	inbox_empty.visible = n == 0 and not board.is_holding()


## zone "" = idle hint; otherwise "Likes: <zone>" and that zone's label lights up.
func _set_hint(zone: String) -> void:
	hint.text = tr("PANTRY_HINT") if zone == "" else tr("PANTRY_LIKES") % _zone_name(zone)
	for i in _zone_labels.size():
		_zone_labels[i].add_theme_color_override("font_color", C_TEXT_HI if _label_zone[i] == zone else C_TEXT_DIM)


func _show_lovely() -> void:
	if _bubble_tween != null:
		_bubble_tween.kill()
	bubble.visible = true
	bubble.pivot_offset = (bubble.size * 0.5).floor()
	bubble.scale = Vector2(0.4, 0.4)
	_bubble_tween = create_tween()
	_bubble_tween.tween_property(bubble, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_interval(2.4)
	_bubble_tween.tween_callback(bubble.hide)
	Audio.play_sfx("sfx_sparkle")


func _pop(c: Control, amount: float) -> void:
	c.pivot_offset = (c.size * 0.5).floor()
	c.scale = Vector2(amount, amount)
	c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var w := int(size.x)
	var h := int(size.y)
	if _bg != null:
		_draw_room()
	else:
		draw_rect(Rect2(0, 0, w, h), C_WALL)
		for x in range(8, w, 16):
			draw_rect(Rect2(x, 0, 1, h), C_WALL_LINE)
		var fy := 258 + BAND * _extra - _offset
		if fy < h:
			draw_rect(Rect2(0, fy, w, h - fy), C_WOOD_DARK)
			draw_rect(Rect2(0, fy, w, 1), C_WOOD)
	var origin := Vector2i(board.position)
	if _on_art:
		for i in _blocks.size():
			var line: Color = Color(str(ZONE_TINTS[_block_zone[i]][1])) if ZONE_TINTS.has(_block_zone[i]) else C_WOOD_DARK
			var r := Rect2i(_blocks[i].position + origin, _blocks[i].size)
			draw_rect(Rect2(r.position.x - 1, r.position.y - 1, r.size.x + 1, 1), line)
			draw_rect(Rect2(r.position.x - 1, r.position.y, 1, r.size.y), line)
		return
	for i in _blocks.size():
		var r := Rect2i(_blocks[i].position + origin, _blocks[i].size)
		var is_floor := _block_zone[i] == String(Data.rules().pantry.floor.zone)
		draw_rect(Rect2(r.grow(4)), C_WOOD_DARK if is_floor else C_WOOD)
		draw_rect(Rect2(r.position.x - 4, r.position.y - 4, r.size.x + 8, 1), C_WOOD_HI)
		draw_rect(Rect2(r.position.x - 4, r.end.y + 3, r.size.x + 8, 1), C_WOOD_DARK)
		draw_rect(Rect2(r.grow(1)), C_STONE_EDGE if is_floor else C_WOOD_DARK)


## BG with BAND more rows per bought shelf in every strip (BG_STRIPS), scrolled up by _offset.
func _draw_room() -> void:
	var grow := BAND * _extra
	var bg_h := _bg.get_height()
	for s: Array in BG_STRIPS:
		var x0 := int(s[0])
		var w := int(s[1]) - x0
		var band_y := int(s[2])
		var band_h := int(s[3])
		var at := int(s[4])
		_blit(Rect2i(x0, 0, w, at), 0)
		for n in floori(grow / float(band_h)):
			_blit(Rect2i(x0, band_y, w, band_h), at + n * band_h)
		_blit(Rect2i(x0, at, w, bg_h - at), at + grow)


## Draws the BG region `src` at room row `y`, skipped when it is off screen.
func _blit(src: Rect2i, y: int) -> void:
	var dy := y - _offset
	if dy + src.size.y <= 0 or dy >= int(size.y):
		return
	draw_texture_rect_region(_bg, Rect2(src.position.x, dy, src.size.x, src.size.y), Rect2(src))


## Scroll bar on the right shelf post: an arrow where more shelves wait, a thumb for where the view is.
func _draw_scroll_hints() -> void:
	if _scroll_max <= 0:
		return
	var h := int(size.y)
	var top := 9
	var track := h - 2 * top
	var thumb := maxi(12, floori(track * h / float(h + _scroll_max)))
	var ty := top + roundi(float(_offset) * (track - thumb) / _scroll_max)
	_hints.draw_rect(Rect2(SCROLL_BAR_X - 1, ty, 4, thumb), C_INK)
	_hints.draw_rect(Rect2(SCROLL_BAR_X, ty + 1, 2, thumb - 2), C_TEXT_HI)
	if _offset > 0:
		_arrow(Vector2i(SCROLL_BAR_X, 2), -1)
	if _offset < _scroll_max:
		_arrow(Vector2i(SCROLL_BAR_X, h - 7), 1)


## 7x4 arrow inside a 1-px ink outline (9x6 from at.y - 1), centred on `at.x`; dir 1 points down.
func _arrow(at: Vector2i, dir: int) -> void:
	for k in 6:
		var y := at.y - 1 + (k if dir > 0 else 5 - k)
		var half := 4 - maxi(k - 1, 0)
		_hints.draw_rect(Rect2(at.x - half, y, 2 * half + 1, 1), C_INK)
		if k >= 1 and k <= 4:
			_hints.draw_rect(Rect2(at.x - half + 1, y, 2 * half - 1, 1), C_TEXT_HI)
