extends Control
## Pantry (spec §7.4, tech-spec §7): shelf grid on the right (ArrangeBoard driven by PantryRules), inbox on the
## left, live stars, Auto-arrange and Back. Every move goes straight into GameState.data.pantry / inbox, followed
## by GameState.notify(["pantry", "inbox"]). Opened without a running game it starts seed 1 with sample items.
## Bought shelves (PantryRules.add_shelf, up to 3) keep the painted look: every one makes the room one BAND taller
## by repeating rows cut from BG (BG_STRIPS: a board, a name plate, a taller crate), and the room then scrolls
## under the fixed left column (goal, inbox, buttons): mouse wheel or trackpad, drag on empty space, W/S or
## Up/Down, and auto-scroll near the top/bottom edge while an item is held, so it can go on any shelf.
## JURY-PANTRY: the pantry reads as a puzzle. A lighter room (BG, one palette step up), a goal panel on top (the
## "Pantry" star meter, the energy it gives, the three rules as chips that light up with a check, pop and sound,
## and one plain tip for the next unmet rule, pantry_goal.gd), shelf signs that say what goes there, the shelves
## a held item likes glowing, "+★" over a drop that meets a rule, a compact inbox tray, and the three-star
## banner "Perfect pantry! +15 energy tomorrow" with FEEL's warm flash.

const InboxView := preload("res://scenes/pantry/inbox_view.gd")
const GoalChip := preload("res://scenes/pantry/goal_chip.gd")
const StarPop := preload("res://scenes/pantry/star_pop.gd")
const Goal := preload("res://scenes/pantry/pantry_goal.gd")
const CELL := 24
## Aligned to the drawn shelves of BG (ART-BG-A): shelves x=312..456 (inner shelf 300..470), block tops y=8/68/128
## so each bottom row stands on a board (top surfaces y~48/105/165), floor block y=206..254 on the floor planks.
## Bought shelves continue the rhythm (block tops 188/248/308, floor 60 px lower each) in room coordinates.
## JURY-PANTRY: bg_pantry_light.png is bg_pantry.png one warm palette step lighter (tools/style/src/pantry), same
## layout pixel for pixel.
const BG := "res://assets/sprites/scenes/bg_pantry_light.png"
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
## Left column (JURY-PANTRY): the goal panel (meter, bonus, rule chips, tip), the inbox tray, the buttons.
const GOAL_RECT := Rect2i(0, 0, 178, 136)
const CHIP_X := 7
const CHIP_Y := 39
const CHIP_W := 164
const CHIP_H := 18
const CHIP_STEP := 19
const RULE_KEYS := ["PANTRY_RULE_ZONE", "PANTRY_RULE_GROUP", "PANTRY_RULE_PRETTY"]
## The tip (%Hint) wraps to at most this many lines; a longer one names the kind by its short name.
const TIP_LINES := 2
const TRAY_POS := Vector2(4, 155)
const TRAY_COLS := 6
const TRAY_ROWS := 3
## A shelf item dropped anywhere in the tray's column (header and the tray at its tallest) goes back to the inbox.
const TRAY_AREA := Rect2(0, 136, 178, 102)
## Shelf signs: a second line under each zone label with what goes there, right-aligned, never left of NOTE_LEFT.
const NOTE_LEFT := 182
## Glow on the shelves a held item likes: a 1-in-4 gold dither that shimmers between two phases.
const GLOW_STEP := 0.3
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
const C_SIGN_LIT := Color("e5bd7f")
const C_SIGN_LIT_HI := Color("f2d9c5")
const C_SIGN_TEXT_LIT := Color("50361e")

@onready var board: ArrangeBoard = %Board
@onready var inbox_view: InboxView = %Inbox
@onready var inbox_count: Label = %InboxCount
@onready var inbox_empty: Label = %InboxEmpty
@onready var bonus: Label = %Bonus
@onready var hint: Label = %Hint
@onready var bubble: Control = %Bubble
@onready var meter: HBoxContainer = %Meter

var _chips: Array = []
var _meter_stars: Array[TextureRect] = []
var _zone_labels: Array[Label] = []
var _label_zone: Array[String] = []
## Unscrolled (room) y of each zone label.
var _label_y: Array[int] = []
## Shelf signs under the zone labels (same order), their text widths and unscrolled y.
var _zone_notes: Array[Label] = []
var _note_w: Array[int] = []
var _note_y: Array[int] = []
var _note_right: Array[int] = []
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
var _menu_btn: Control
## Zone the held item likes ("" when nothing is held): its shelves glow and its sign lights up.
var _glow_zone := ""
var _glow_t := 0.0
var _glow_phase := 0
var _glow_tex: Array[ImageTexture] = []
## Board entry of the last drop, for the "+★" pop when that drop meets a rule (-1: none).
var _last_drop := -1
var _tip_queued := false


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_temp(1)
		GameState.data.inbox.append_array(sample_items())
	var data: Dictionary = GameState.data
	var pantry: Dictionary = data.pantry
	var b := PantryRules.board_of(pantry)
	_bg = load(BG) if ResourceLoader.exists(BG) else null
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # the glow dither tiles
	_glow_tex = [_dither(Vector2i(0, 0)), _dither(Vector2i(1, 1))]
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
	board.preview_changed.connect(func(_info: Dictionary) -> void: _lift_shadow())  # FEEL: again after a rotate
	board.entry_added.connect(func(i: int, _from: Dictionary) -> void: _puff(i))
	board.entry_moved.connect(_puff)
	board.entry_added.connect(func(i: int, _from: Dictionary) -> void: _last_drop = i)
	board.entry_moved.connect(func(i: int) -> void: _last_drop = i)
	_build_goal()
	board.setup(b, pantry.items, {
		"item_size": _item_size, "can_place": _can_place, "zone_for": _zone_for,
		"in_correct_zone": _in_zone, "can_rotate": _can_rotate, "stars": _stars_now,
	}, layout)
	_scroll_max = maxi(0, BOARD_TOP + int(board.size.y) - BOARD_BOTTOM)
	_build_blocks(b)
	inbox_view.cols = TRAY_COLS
	inbox_view.max_rows = TRAY_ROWS
	inbox_view.position = TRAY_POS
	inbox_view.setup(data.inbox, board, _make_view)
	%AutoArrange.pressed.connect(_on_auto)
	%Back.pressed.connect(_on_back)
	_menu_btn = PauseMenu.corner_button(Vector2(76, 238))  # PAUSE-MENU: the gear beside Back (Esc opens it too)
	add_child(_menu_btn)
	_hints = Control.new()
	_hints.name = "ScrollHints"
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hints)
	_hints.draw.connect(_draw_scroll_hints)
	_refresh_inbox_labels()
	_refresh_notes()
	_refresh_tip()
	queue_redraw()



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
	if _glow_zone != "":
		_glow_t += delta
		var phase := floori(_glow_t / GLOW_STEP) % 2
		if phase != _glow_phase:
			_glow_phase = phase
			queue_redraw()
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


## Zone whose shelves glow right now ("" when nothing is held). For the smoke shot.
func glow_zone() -> String:
	return _glow_zone


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
	for i in _zone_notes.size():
		_zone_notes[i].position.y = _note_y[i] - off
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
	for c: Control in [inbox_view, %AutoArrange, %Back, _menu_btn]:
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
## Under each label a sign says what goes there (_refresh_notes fills it in).
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
	var right := BOARD_X - 6
	if _on_art and shelf:
		var plate := plate_rect(_blocks.size() - 1)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(plate.position)
		l.size = Vector2(plate.size)
		right = plate.end.x
	else:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.position = Vector2(BOARD_X - LABEL_W - 6, BOARD_TOP + rect.position.y + 3)
		l.size = Vector2(LABEL_W, 16)
	l.add_theme_color_override("font_color", C_TEXT)
	add_child(l)
	_zone_labels.append(l)
	_label_zone.append(zone)
	_label_y.append(int(l.position.y))
	var note := Label.new()
	note.name = "ZoneNote%d" % _zone_notes.size()
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.position = Vector2(NOTE_LEFT, int(l.position.y) + 18)
	note.size = Vector2(right - 2 - NOTE_LEFT, 18)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(note)
	_zone_notes.append(note)
	_note_y.append(int(note.position.y))
	_note_w.append(0)
	_note_right.append(right)


## Goal panel: "Pantry" and its star meter (the title sits in %Meter), the bonus line, the three rule chips.
func _build_goal() -> void:
	_full = load(STAR_FULL) if ResourceLoader.exists(STAR_FULL) else null
	_empty = load(STAR_EMPTY) if ResourceLoader.exists(STAR_EMPTY) else null
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(3, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.add_child(gap)
	for i in 3:
		var t := TextureRect.new()
		t.name = "Star%d" % i
		t.texture = _empty
		t.custom_minimum_size = Vector2(16, 16)
		t.stretch_mode = TextureRect.STRETCH_KEEP
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter.add_child(t)
		_meter_stars.append(t)
	for i in RULE_KEYS.size():
		var c: Control = GoalChip.new()
		c.name = "Chip%d" % i
		c.position = Vector2(CHIP_X, CHIP_Y + i * CHIP_STEP)
		c.size = Vector2(CHIP_W, CHIP_H)
		add_child(c)
		c.setup(RULE_KEYS[i])
		_chips.append(c)


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
	_refresh_notes()
	_queue_tip()
	GameState.notify(PackedStringArray(["pantry", "inbox"]))


func _on_entry_added(_index: int, from: Dictionary) -> void:
	if String(from.get("where", "")) != "inbox":
		return
	var inbox: Array = GameState.data.inbox
	var i := int(from.get("index", -1))
	if i >= 0 and i < inbox.size():
		inbox.remove_at(i)


## A board item dropped on the inbox tray (or anywhere in its column) goes back there; anywhere else it returns to
## its cell.
func _on_released_outside(item: Dictionary, from: Dictionary, global_pos: Vector2) -> void:
	if String(from.get("where", "")) != "board":
		return
	if not (TRAY_AREA.has_point(global_pos) or inbox_view.get_global_rect().has_point(global_pos)):
		return
	GameState.data.inbox.append(item)
	board.remove_entry(int(from.index))
	Audio.play_sfx("sfx_pantry_place")


## Chips and meter follow the rules; a rule met just now pops its chip and star with a rising note, and "+★" rises
## over the item whose drop did it. Three stars: jingle, banner and FEEL's warm flash.
func _on_stars_changed(result: Dictionary, prev: Dictionary) -> void:
	var flags: Array = result.get("rules", [false, false, false])
	var was: Array = prev.get("rules", [false, false, false])
	var first := prev.is_empty()
	var newly := 0
	for i in mini(flags.size(), _chips.size()):
		var on := bool(flags[i])
		_chips[i].set_met(on)
		if on and not first and not bool(was[i]):
			Juice.pop(_chips[i], 1.12, 0.18)
			Juice.sfx_pitched(self, "sfx_star_pop", 3.0 * i)  # a soft note, higher for each rule
			newly += 1
	var n := int(result.get("stars", 0))
	var n_was := int(prev.get("stars", 0))
	for k in _meter_stars.size():
		_meter_stars[k].texture = _full if k < n else _empty
		if not first and k < n and k >= n_was:
			Juice.pop(_meter_stars[k], 1.6)
	var per := int(Data.rules().energy.pantry_bonus_per_star)
	bonus.text = tr("PANTRY_BONUS") % (n * per) if n > 0 else tr("PANTRY_BONUS_NONE")
	if newly > 0 and _last_drop >= 0 and _last_drop < board.entries.size():
		var r := board.entry_rect(_last_drop)
		StarPop.spawn(board, Vector2(r.position.x + r.size.x / 2.0, r.position.y))
	_last_drop = -1
	if n >= 3 and not first and n_was < 3:
		Audio.play_jingle("jgl_pantry_3stars")
		_show_lovely(3 * per)
		_warm_flash()
	_queue_tip()


func _on_hold_started(item: Dictionary, _from: Dictionary) -> void:
	_lift_shadow()
	_edge_armed = _edge_dir(_pointer) == 0
	_last_drop = -1
	_glow_zone = PantryRules.zone_for(item)
	_glow_t = 0.0
	_glow_phase = 0
	var d := Goal.zone_tip(item)
	if PantryRules.can_rotate(item) and String(d.key) == "PANTRY_TIP_ZONE":
		d.key = "PANTRY_TIP_TURN"
	hint.text = _tip_text(d)
	_light_zone(_glow_zone)
	inbox_empty.visible = false
	queue_redraw()


func _on_hold_ended(_item: Dictionary, _placed: bool) -> void:
	_glow_zone = ""
	_light_zone("")
	_refresh_inbox_labels()
	_refresh_tip()
	queue_redraw()


func _on_auto() -> void:
	board.cancel_hold()
	var data: Dictionary = GameState.data
	var inbox: Array = data.inbox
	if inbox.is_empty():
		Audio.play_sfx("sfx_pantry_wrong")
		return
	_last_drop = -1
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


# --- goal words (pantry_goal.gd) ---------------------------------------------------------------------------------

## The tip waits for the board's stars of this change (they are re-run after `changed`).
func _queue_tip() -> void:
	if _tip_queued:
		return
	_tip_queued = true
	_refresh_tip.call_deferred()


func _refresh_tip() -> void:
	_tip_queued = false
	if board.is_holding():
		return
	var flags: Array = board.stars_result().get("rules", [false, false, false])
	hint.text = _tip_text(Goal.tip(GameState.data.pantry, flags, GameState.data.inbox.size()))


## Words for a Goal tip; a kind whose full name would not fit the tip's TIP_LINES lines is named by its short name.
func _tip_text(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	var text := _format_tip(d, String(d.get("kind", "")))
	if d.has("short") and _lines(text) > TIP_LINES:
		text = _format_tip(d, String(d.short))
	return text


## Lines `text` takes in the tip label (word wrapped at its width).
func _lines(text: String) -> int:
	var keep := hint.text
	hint.text = text
	var n := hint.get_line_count()
	hint.text = keep
	return n


func _format_tip(d: Dictionary, kind: String) -> String:
	var key := String(d.key)
	match key:
		"PANTRY_TIP_ZONE", "PANTRY_TIP_TURN":
			return tr(key) % [kind, _zone_name(String(d.zone))]
		"PANTRY_TIP_FLOOR", "PANTRY_TIP_GROUP":
			return tr(key) % kind
		"PANTRY_TIP_GROUP_MORE", "PANTRY_TIP_PRETTY":
			return tr(key) % int(d.n)
		"PANTRY_TIP_FILL":
			return tr(key) % [_zone_name(String(d.zone)), int(d.n)]
	return tr(key)


## Each shelf sign lists what goes there, as many names as fit its width.
func _refresh_notes() -> void:
	var entries: Array = GameState.data.pantry.get("items", [])
	var inbox: Array = GameState.data.inbox
	var changed := false
	for i in _zone_notes.size():
		var note := _zone_notes[i]
		var names := Goal.zone_kinds(_label_zone[i], entries, inbox)
		var text := ", ".join(names)
		while names.size() > 1 and _text_w(note, text) > note.size.x - 4:
			names.remove_at(names.size() - 1)
			text = ", ".join(names)
		if text != note.text:
			note.text = text
			_note_w[i] = _text_w(note, text) if text != "" else 0
			changed = true
	if changed:
		queue_redraw()


func _text_w(l: Label, text: String) -> int:
	return ceili(l.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x)


## The liked zone's plate label turns gold and its sign lights up; "" = all plain.
func _light_zone(zone: String) -> void:
	for i in _zone_labels.size():
		var lit := _label_zone[i] == zone
		_zone_labels[i].add_theme_color_override("font_color", C_TEXT_HI if lit else C_TEXT)
		_zone_notes[i].add_theme_color_override("font_color", C_SIGN_TEXT_LIT if lit else C_TEXT)
		_zone_notes[i].add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0) if lit else C_INK)


# --- feel (FEEL) -------------------------------------------------------------------------------------------------

## The held item floats ArrangeBoard.LIFT px up; a 1 px shadow stays on the shelf under it (plum, lower edge).
func _lift_shadow() -> void:
	var v: Variant = board.get("_held_view")
	if not (v is Control) or not is_instance_valid(v) or (v as Control).has_node("LiftShadow"):
		return
	var held := v as Control
	var w := int(held.size.x)
	var h := int(held.size.y)
	var r := Rect2i(floori((w - 16) / 2.0) + 3, floori((h - 16) / 2.0) + 16, 10, 1)  # a 16x16 icon, centred
	var jar: JarIcon = null
	for c in held.get_children():
		if c is JarIcon:
			jar = c
	if bool(held.get("_crate")):
		r = Rect2i(2, h, w - 4, 1)
	elif jar != null:
		r = Rect2i(int(jar.position.x) + 2, int(jar.position.y + jar.size.y), maxi(int(jar.size.x) - 4, 2), 1)
	var sh := ColorRect.new()
	sh.name = "LiftShadow"
	sh.color = C_INK  # the back wall is plum: the shadow one tone darker
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.position = Vector2(r.position.x, r.position.y + ArrangeBoard.LIFT - 1)
	sh.size = Vector2(r.size)
	held.add_child(sh)


## A tiny dust puff from both bottom corners of the item just set down at board entry `index`.
func _puff(index: int) -> void:
	if index < 0 or index >= board.entries.size():
		return
	var r := board.entry_rect(index)
	Juice.dust_puff(board, Vector2(r.position.x + floori(r.size.x / 2.0), r.end.y - 1), floori(r.size.x / 2.0) - 2)


## Third star: a warm gold flash over the shelves and a few twinkles.
func _warm_flash() -> void:
	var r := Rect2(board.position - Vector2(6, 6), board.size + Vector2(12, 12)).intersection(Rect2(Vector2.ZERO, size))
	Juice.dither_flash(self, r, C_TEXT_HI, 30)
	Juice.sparkle(self, r.grow(-8), 12, 31)


# --- view helpers ------------------------------------------------------------------------------------------------

func _refresh_inbox_labels() -> void:
	var n: int = GameState.data.inbox.size()
	inbox_count.text = str(n) if n > 0 else ""
	inbox_empty.visible = n == 0 and not board.is_holding()


## The three-star banner: "Perfect pantry!" and tomorrow's energy, low over the shelf column (the floor), so the
## shelf that just did it and its "+★" stay in view.
func _show_lovely(energy: int) -> void:
	if _bubble_tween != null:
		_bubble_tween.kill()
	(bubble.get_node("Box/Sub") as Label).text = tr("PANTRY_BONUS") % energy
	bubble.visible = true
	bubble.reset_size()
	bubble.position = Vector2(roundi(BOARD_X + 72 - bubble.size.x / 2.0), int(size.y) - int(bubble.size.y) - 12)
	bubble.pivot_offset = (bubble.size * 0.5).floor()
	bubble.scale = Vector2(0.4, 0.4)
	_bubble_tween = create_tween()
	_bubble_tween.tween_property(bubble, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_interval(2.6)
	_bubble_tween.tween_callback(bubble.hide)
	Audio.play_sfx("sfx_sparkle")


## A 2 x 2 tile with one gold pixel at `at` (the rest clear): the shelf glow, tiled.
func _dither(at: Vector2i) -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixelv(at, C_TEXT_HI)
	return ImageTexture.create_from_image(img)


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
	if not _on_art:
		for i in _blocks.size():
			var r := Rect2i(_blocks[i].position + origin, _blocks[i].size)
			var is_floor := _block_zone[i] == String(Data.rules().pantry.floor.zone)
			draw_rect(Rect2(r.grow(4)), C_WOOD_DARK if is_floor else C_WOOD)
			draw_rect(Rect2(r.position.x - 4, r.position.y - 4, r.size.x + 8, 1), C_WOOD_HI)
			draw_rect(Rect2(r.position.x - 4, r.end.y + 3, r.size.x + 8, 1), C_WOOD_DARK)
			draw_rect(Rect2(r.grow(1)), C_STONE_EDGE if is_floor else C_WOOD_DARK)
	_draw_glow(origin)
	if _on_art:
		for i in _blocks.size():
			var line: Color = Color(str(ZONE_TINTS[_block_zone[i]][1])) if ZONE_TINTS.has(_block_zone[i]) else C_WOOD_DARK
			var r := Rect2i(_blocks[i].position + origin, _blocks[i].size)
			draw_rect(Rect2(r.position.x - 1, r.position.y - 1, r.size.x + 1, 1), line)
			draw_rect(Rect2(r.position.x - 1, r.position.y, 1, r.size.y), line)
	_draw_signs()
	draw_style_box(get_theme_stylebox("panel", &"DarkPanel"), Rect2(GOAL_RECT))


## The shelves the held item likes: every cell of that zone under a shimmering gold dither (items stay on top).
func _draw_glow(origin: Vector2i) -> void:
	if _glow_zone == "" or _glow_tex.size() < 2:
		return
	var tex := _glow_tex[_glow_phase]
	for y in int(board.board.get("rows", 0)):
		for x in int(board.board.get("cols", 0)):
			var c := Vector2i(x, y)
			if board.zone_at(c) != _glow_zone:
				continue
			var r := board.cell_rect(c)
			draw_texture_rect(tex, Rect2(r.position + origin, r.size - Vector2i(1, 1)), true)


## A small wooden sign behind each shelf note (gold while its zone glows).
func _draw_signs() -> void:
	for i in _zone_notes.size():
		var wn := _note_w[i]
		if wn <= 0:
			continue
		var y := _note_y[i] - _offset
		if y + 18 <= 0 or y >= int(size.y):
			continue
		var r := Rect2(_note_right[i] - 2 - wn - 4, y + 2, wn + 7, 16)
		var lit := _label_zone[i] == _glow_zone
		draw_rect(r, C_INK)
		draw_rect(r.grow(-1), C_SIGN_LIT if lit else C_WOOD)
		draw_rect(Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 2, 1), C_SIGN_LIT_HI if lit else C_WOOD_HI)


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
