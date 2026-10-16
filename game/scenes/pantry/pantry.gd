extends Control
## Pantry (spec §7.4, tech-spec §7): shelf grid on the right (ArrangeBoard driven by PantryRules), inbox on the
## left, live stars, Auto-arrange and Back. Every move goes straight into GameState.data.pantry / inbox, followed
## by GameState.notify(["pantry", "inbox"]). Opened without a running game it starts seed 1 with sample items.

const InboxView := preload("res://scenes/pantry/inbox_view.gd")
const CELL := 24
## Art-bible §3.7 alignment: shelves at x=312..456, tops y=20/80/140, floor y=206..254.
const BOARD_X := 312
const BOARD_TOP := 20
const BOARD_BOTTOM := 254
const SHELF_GAP := 12
const FLOOR_GAP := 18
const TIGHT_GAP := 4
const LABEL_W := 38
const ZONE_COLORS := {
	"dry": ["50361e", "3d1f29"], "room": ["62272c", "3d1f29"], "cool": ["2e3f3f", "23282a"], "floor": ["49423d", "23282a"],
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
var _blocks: Array[Rect2i] = []
var _block_zone: Array[String] = []
var _full: Texture2D
var _empty: Texture2D
var _bubble_tween: Tween


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_temp(1)
		GameState.data.inbox.append_array(sample_items())
	var data: Dictionary = GameState.data
	var pantry: Dictionary = data.pantry
	var b := PantryRules.board_of(pantry)
	var layout := _layout(b)
	board.position = Vector2(BOARD_X, int(layout.top))
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
	_build_blocks(b)
	inbox_view.setup(data.inbox, board, _make_view)
	%AutoArrange.pressed.connect(_on_auto)
	%Back.pressed.connect(_on_back)
	_refresh_inbox_labels()
	_set_hint("")
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		_on_back()


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

## Row gaps between shelves and above the floor; tighter when bought shelves would push the floor off screen.
func _layout(b: Dictionary) -> Dictionary:
	var rows := int(b.rows)
	var floor_y := int(b.get("floor_y", rows))
	var shelves: Array = b.get("shelves", [])
	var shelf_gap := SHELF_GAP
	var floor_gap := FLOOR_GAP if floor_y < rows else 0
	var top := BOARD_TOP
	var height := rows * CELL + maxi(shelves.size() - 1, 0) * shelf_gap + floor_gap
	if top + height > BOARD_BOTTOM:
		shelf_gap = TIGHT_GAP
		floor_gap = TIGHT_GAP if floor_y < rows else 0
		height = rows * CELL + maxi(shelves.size() - 1, 0) * shelf_gap + floor_gap
		top = maxi(4, BOARD_BOTTOM - height)
	var gaps := {}
	for sh in shelves:
		if int(sh.y) > 0:
			gaps[int(sh.y)] = shelf_gap
	if floor_y > 0 and floor_y < rows:
		gaps[floor_y] = floor_gap
	return {"cell": CELL, "row_gaps": gaps, "zone_colors": ZONE_COLORS, "top": top}


func _build_blocks(b: Dictionary) -> void:
	for sh in b.get("shelves", []):
		_add_block(int(sh.y), int(sh.rows), String(sh.zone))
	var floor_y := int(b.get("floor_y", int(b.rows)))
	if floor_y < int(b.rows):
		_add_block(floor_y, int(b.rows) - floor_y, String(Data.rules().pantry.floor.zone))


func _add_block(y0: int, n: int, zone: String) -> void:
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
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.position = Vector2(BOARD_X - LABEL_W - 6, int(board.position.y) + rect.position.y + 3)
	l.size = Vector2(LABEL_W, 16)
	l.add_theme_color_override("font_color", C_TEXT_DIM)
	add_child(l)
	_zone_labels.append(l)
	_label_zone.append(zone)


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
		_show_lovely()


func _on_hold_started(item: Dictionary, _from: Dictionary) -> void:
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
	draw_rect(Rect2(0, 0, w, h), C_WALL)
	for x in range(8, w, 16):
		draw_rect(Rect2(x, 0, 1, h), C_WALL_LINE)
	draw_rect(Rect2(0, 258, w, h - 258), C_WOOD_DARK)
	draw_rect(Rect2(0, 258, w, 1), C_WOOD)
	var origin := Vector2i(board.position)
	for i in _blocks.size():
		var r := Rect2i(_blocks[i].position + origin, _blocks[i].size)
		var is_floor := _block_zone[i] == String(Data.rules().pantry.floor.zone)
		draw_rect(Rect2(r.grow(4)), C_WOOD_DARK if is_floor else C_WOOD)
		draw_rect(Rect2(r.position.x - 4, r.position.y - 4, r.size.x + 8, 1), C_WOOD_HI)
		draw_rect(Rect2(r.position.x - 4, r.end.y + 3, r.size.x + 8, 1), C_WOOD_DARK)
		draw_rect(Rect2(r.grow(1)), C_STONE_EDGE if is_floor else C_WOOD_DARK)
