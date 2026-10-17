class_name GuideArrow
extends CanvasLayer
## ONBOARD-GUIDE · Granny's guide for the To-Do steps (the first days and the six Harvest Festival steps):
##   - a 2-frame bobbing pixel arrow over the current step's target; while the target is off screen it waits at the
##     screen edge (under the HUD bar) and points the way,
##   - Granny's hint: one short line (TODO_HINT_<STEP>, TodoRules.hint_key_of) in a compact speech bubble beside her
##     (body font m5x7 16 px, at most BUBBLE_W px wide and 3 lines, 1 px ink edge, a tail to her) for HINT_SEC when a
##     step becomes current, once per step,
##   - first-time key caps: an "E" key and a mouse over the first tree, bush, pickup or station Granny stands at, until
##     that kind has been used once.
## Lives under the tree root beside Granny's To-Do note (GrannyTodo creates it). The step is the note's (nothing shows
## while the note is hidden or closed), and the "Granny's To-Do" setting off turns arrows, hints and key caps off.
## Everything hides while a panel, card, mini-game, the book, letters, a fade or the menu is open.
## Scenes register once, in _ready:   GuideArrow.attach(self, _guide_at)
## `_guide_at(what: String) -> Variant` answers in the scene's canvas (world) coordinates:
##   a To-Do step id -> the point just above that step's target here (the thing, or the way to its scene), or null
##   "granny"        -> Granny's body rect (Rect2): her bubble sits beside her with its tail to her, or null
##   "bubble"        -> where a tail-less bubble's bottom centre goes when there is no Granny, or null (top centre)
##   "near"          -> {"kind", "at"} for the thing Granny stands at (or the station under focus), {} for none
## and calls GuideArrow.used(kind) when Granny uses something (kinds: KEY_OF).
## Progress lives in the save: state.flags.guide_hints (one bit per step, TodoRules.BITS) and state.flags.guide_keys.
## No autoload identifiers here (smoke scripts and --check-only reach this class): autoloads by node path.

const LAYER := 11  ## with the To-Do note: over the HUD (10), under the popups (12-60) the note and festival watch for
const META := &"guide_at"
const POPUPS := Vector2i(12, 99)  ## CanvasLayers here with visible content hide the guide (popups, fades, menu)
const BUSY_VARS := ["menu", "_mg", "_card"]  ## scene members holding an open menu, mini-game or result card
const HINT_SEC := 3.4
const HINT_DELAY := 0.8  ## a new hint waits until the screen has been clear this long (fades, the festival's start card)
const EDGE := 6  ## px from the screen sides and bottom for the edge arrow
const TOP := 34  ## px from the screen top: under the HUD bar
const BUBBLE_W := 168  ## widest hint bubble (base px, paper edge included); its text wraps inside
const HINT_FONT := preload("res://assets/fonts/m5x7.ttf")  ## body font for the hint (titles and buttons: m6x11plus)
const HINT_SIZE := 16
const HINT_LINES := 3
const PAD := Vector2i(4, 2)  ## paper around the hint text (x, y), the 1 px ink edge included
const GAP := 4  ## px between Granny and her bubble (the tail fills it)
const BOB_HZ := 3.0
const EDGE_TAG := {"f_shake": "FESTIVAL_RARE_TREE"}  ## a paper tag beside the edge arrow
## Scene kinds -> key cap kind (one "used" bit each). Garden beds and the compost bin are walked up to like trees; the
## kitchen's stations are clicked or picked with the keyboard focus, so they keep their own cap.
const KEY_OF := {
	"tree": "tree", "fruit_tree": "tree", "bush": "bush", "ground": "pickup", "hive": "pickup",
	"bed": "bed", "compost": "bed", "station": "station",
}
const KEY_BITS := {"tree": 0, "bush": 1, "pickup": 2, "station": 3, "bed": 4}
const C_INK := Color("111010")
const C_GOLD := Color("e5bd7f")
const C_PAPER := Color("f2d9c5")
const C_TEXT := Color("50361e")
const C_SIDE := Color("b9a697")
## The arrow pointing down, tip at the bottom centre (#: ink, c: cream, g: gold shade). Other directions are the same
## pixels turned in 90 degree steps while drawing, never a rotated sprite. Cream reads on red and orange leaves.
const ARROW := [
	"...#####...",
	"...#ccg#...",
	"...#ccg#...",
	"...#ccg#...",
	"####ccg####",
	"#cccccgggg#",
	".#ccccggg#.",
	"..#cccgg#..",
	"...#ccg#...",
	"....#c#....",
	".....#.....",
]
const TAIL := ["ppppp", "#ppp#", ".#p#.", "..#.."]  ## the bubble's tail, from its edge row (paper over the ink) to the tip
const E_GLYPH := ["###", "#..", "##.", "#..", "###"]
const MOUSE := ["..###..", ".#g#p#.", "#gg#pp#", "#gg#pp#", "#######", "#ppppp#", "#ppppp#", ".#ppp#.", "..###.."]
const STEP := {"up": Vector2(0, -1), "down": Vector2(0, 1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}

var _ink: Node2D
var _bubble: PanelContainer
var _label: Label
var _tag: PanelContainer
var _tag_label: Label
var _t := 0.0
var _step := ""
var _pending := ""  ## step whose hint waits for a clear screen
var _hint_left := 0.0
var _clear_for := 0.0  ## seconds the screen has been clear of popups, fades and menus
var _aim := Vector2(-1, -1)  ## screen point of the step's target (may be off screen); (-1, -1) when none
var _tip := Vector2(-1, -1)  ## where the arrow's tip is drawn
var _dir := "down"
var _arrow_on := false
var _cap_on := false
var _cap_at := Vector2.ZERO  ## bottom centre of the key cap
var _tail := Vector2(-1, -1)  ## tip of the bubble's tail, (-1, -1) for none
var _tail_dir := "down"  ## where the tail points (towards Granny)
var _drawn: Array = []


static func ensure() -> GuideArrow:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group("guide_arrow") as GuideArrow
	if found != null:
		return found
	var g := GuideArrow.new()
	g.name = "GuideArrow"
	tree.root.add_child.call_deferred(g)
	return g


## A play scene tells the guide where things are (see the header). Call once in the scene's _ready.
static func attach(scene: Node, where: Callable) -> void:
	scene.set_meta(META, where)


## Granny used a thing of `kind` (a scene kind of KEY_OF or a key kind): its first-time key cap stops showing.
static func used(kind: String) -> void:
	var key := String(KEY_OF.get(kind, ""))
	var d := _data()
	if key == "" or d.is_empty():
		return
	if not d.has("flags"):
		d["flags"] = {}
	d.flags["guide_keys"] = int(d.flags.get("guide_keys", 0)) | (1 << int(KEY_BITS[key]))


## True when the guide runs (the "Granny's To-Do" setting on): the festival leaves its rare-tree marker to it.
static func enabled() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return GameSettings.tutorial_enabled() and tree != null and tree.get_first_node_in_group("guide_arrow") != null


static func _data() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("GameState") if tree != null else null
	return gs.get("data") if gs != null else {}


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS  # hides itself under the pause menu too
	add_to_group("guide_arrow")
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/theme.tres")
	add_child(root)
	_bubble = _paper(PAD)
	_label = Label.new()
	_label.theme_type_variation = &"PaperLabel"
	_label.add_theme_font_override("font", HINT_FONT)
	_label.add_theme_font_size_override("font_size", HINT_SIZE)
	_label.add_theme_constant_override("line_spacing", 0)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.max_lines_visible = HINT_LINES
	_bubble.add_child(_label)
	root.add_child(_bubble)
	_tag = _paper(Vector2i(5, 2))
	_tag_label = Label.new()
	_tag_label.theme_type_variation = &"PaperLabel"
	_tag.add_child(_tag_label)
	root.add_child(_tag)
	_ink = Node2D.new()
	_ink.z_index = 1  # arrow, key cap and the bubble's tail over the paper
	_ink.draw.connect(_draw_ink)
	add_child(_ink)


## A small paper box with a 1 px ink edge and `pad` px of paper round its text.
func _paper(pad: Vector2i) -> PanelContainer:
	var p := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = C_PAPER
	box.border_color = C_INK
	box.set_border_width_all(1)
	box.content_margin_left = pad.x
	box.content_margin_right = pad.x
	box.content_margin_top = pad.y
	box.content_margin_bottom = pad.y + 1
	box.anti_aliasing = false
	p.add_theme_stylebox_override("panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	return p


# ---------------------------------------------------------------- state for tests and smokes

## The step the arrow follows ("" when none).
func step() -> String:
	return _step


## True while the arrow is drawn.
func showing() -> bool:
	return _arrow_on


## Screen point the arrow aims at (the target, even off screen); (-1, -1) while no arrow shows.
func aim() -> Vector2:
	return _aim if _arrow_on else Vector2(-1, -1)


## "over" when the arrow sits over its target, "edge" when it waits at the screen edge, "" when hidden.
func mode() -> String:
	if not _arrow_on:
		return ""
	return "over" if _tip.distance_to(_aim) <= 4.0 else "edge"


func hint_text() -> String:
	return _label.text if _bubble.visible else ""


func key_cap_showing() -> bool:
	return _cap_on


# ---------------------------------------------------------------- every frame

func _process(delta: float) -> void:
	_t += delta
	var d := _data()
	var scene := get_tree().current_scene
	var where: Callable = scene.get_meta(META) if scene != null and scene.has_meta(META) else Callable()
	var on := not d.is_empty() and GameSettings.tutorial_enabled()
	var now_step := _todo_step() if on else ""
	if now_step != _step:
		_step = now_step
		_pending = now_step if now_step != "" and not _hinted(d, now_step) else ""
		_hint_left = 0.0
	var clear := on and where.is_valid() and not _busy(scene)
	_clear_for = _clear_for + delta if clear else 0.0
	_update_arrow(where if clear else Callable(), now_step)
	_update_cap(where if clear else Callable(), d)
	_update_hint(where if clear else Callable(), d, delta)
	var now := [_arrow_on, _tip, _dir, _cap_on, _cap_at, _bubble.visible, _tail, _tail_dir, _bubble.position]
	if now != _drawn:
		_drawn = now
		_ink.queue_redraw()


## The note's current step, "" while the note is hidden, closed or finished.
func _todo_step() -> String:
	var todo := get_tree().get_first_node_in_group("granny_todo") as CanvasLayer
	if todo == null or not todo.visible:
		return ""
	return String(todo.get("_step"))


func _hinted(d: Dictionary, s: String) -> bool:
	var bits := int(d.get("flags", {}).get("guide_hints", 0))
	return bits & (1 << int(TodoRules.BITS.get(s, 31))) != 0


func _key_used(d: Dictionary, key: String) -> bool:
	var bits := int(d.get("flags", {}).get("guide_keys", 0))
	return bits & (1 << int(KEY_BITS[key])) != 0


## A popup, card, mini-game, letters, book, fade or the menu is on screen (CanvasLayers in POPUPS with visible
## content under the root or the scene), or the scene holds an open menu, mini-game or result card.
func _busy(scene: Node) -> bool:
	var nodes: Array[Node] = get_tree().root.get_children()
	nodes.append_array(scene.get_children())
	for n in nodes:
		var cl := n as CanvasLayer
		if cl == null or cl == self or not cl.visible or cl.layer < POPUPS.x or cl.layer > POPUPS.y:
			continue
		for c in cl.get_children():
			if c is CanvasItem and (c as CanvasItem).visible:
				return true
	for key in BUSY_VARS:
		var v: Variant = scene.get(key)
		if v is Object and is_instance_valid(v):
			return true
	return false


func _screen(p: Vector2) -> Vector2:
	return (get_viewport().get_canvas_transform() * p).round()


func _bob() -> int:
	return int(_t * BOB_HZ) % 2 * 2


func _update_arrow(where: Callable, s: String) -> void:
	var at: Variant = where.call(s) if where.is_valid() and s != "" else null
	_arrow_on = at is Vector2
	_tag.visible = false
	if not _arrow_on:
		_aim = Vector2(-1, -1)
		return
	_aim = _screen(at)
	var vp := get_viewport().get_visible_rect().size
	var bob := _bob()
	if Rect2(2, 10, vp.x - 4, vp.y - 12).has_point(_aim):
		_dir = "down"
		_tip = _aim - Vector2(0, bob)
		# HUD-BAR: never draw over the To-Do note's text; point up from below the target instead
		var note := _note_rect().grow(2)
		if note.has_area() and note.intersects(Rect2(_tip.x - 6, _tip.y - 12, 12, 13)):
			_dir = "up"
			_tip = _aim + Vector2(0, bob)
		return
	var r := Rect2(EDGE, TOP, vp.x - 2 * EDGE, vp.y - TOP - EDGE)
	var c := Vector2(clampf(_aim.x, r.position.x, r.end.x), clampf(_aim.y, r.position.y, r.end.y))
	var note_zone := _note_rect().grow(14)  # HUD-BAR: the edge arrow stays outside the To-Do note
	if note_zone.has_area() and note_zone.has_point(c):
		c.y = clampf(note_zone.end.y, r.position.y, r.end.y)
	var away := _aim - c
	_dir = ("up" if away.y < 0 else "down") if absf(away.y) >= absf(away.x) else ("left" if away.x < 0 else "right")
	var key := String(EDGE_TAG.get(s, ""))
	var plate := Vector2.ZERO
	if key != "":
		_tag_label.text = tr(key)
		plate = _tag.get_combined_minimum_size()
		if _dir in ["up", "down"]:  # keep the tag on screen beside the arrow
			c.x = clampf(c.x, r.position.x + ceilf(plate.x / 2.0), r.end.x - ceilf(plate.x / 2.0))
		else:
			c.y = clampf(c.y, r.position.y + ceilf(plate.y / 2.0), r.end.y - ceilf(plate.y / 2.0))
	_tip = c.round() + (STEP[_dir] as Vector2) * bob
	if key == "":
		return
	var off: Vector2
	match _dir:
		"up":
			off = Vector2(-floorf(plate.x / 2.0), 11)
		"down":
			off = Vector2(-floorf(plate.x / 2.0), -11 - plate.y)
		"left":
			off = Vector2(11, -floorf(plate.y / 2.0))
		_:
			off = Vector2(-11 - plate.x, -floorf(plate.y / 2.0))
	_tag.size = plate
	_tag.position = _tip - (STEP[_dir] as Vector2) * bob + off
	_tag.visible = true


func _update_cap(where: Callable, d: Dictionary) -> void:
	_cap_on = false
	if not where.is_valid():
		return
	var near: Variant = where.call("near")
	if typeof(near) != TYPE_DICTIONARY or not (near as Dictionary).has("at"):
		return
	var key := String(KEY_OF.get(String(near.get("kind", "")), ""))
	if key == "" or _key_used(d, key):
		return
	var at := _screen(near.at)
	if _arrow_on and _dir == "down" and at.distance_to(_aim) <= 4.0:
		_cap_at = Vector2(_tip.x + 15, _tip.y - 1)  # beside the arrow over the same thing
	else:
		_cap_at = at - Vector2(0, _bob())
	_cap_on = true


func _update_hint(where: Callable, d: Dictionary, delta: float) -> void:
	if not where.is_valid():
		_bubble.visible = false
		return
	if _pending != "" and _pending == _step and _clear_for >= HINT_DELAY:
		_label.text = tr(TodoRules.hint_key_of(_pending))
		var w := HINT_FONT.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE).x
		_label.custom_minimum_size = Vector2(minf(ceilf(w), BUBBLE_W - 2 * PAD.x), 0)
		_label.size = Vector2(_label.custom_minimum_size.x, 0)  # shape the lines at this width from the first frame
		_hint_left = HINT_SEC
		if not d.has("flags"):
			d["flags"] = {}
		d.flags["guide_hints"] = int(d.flags.get("guide_hints", 0)) | (1 << int(TodoRules.BITS.get(_pending, 31)))
		_pending = ""
	if _hint_left <= 0.0:
		_bubble.visible = false
		return
	_hint_left -= delta
	_bubble.visible = true
	_bubble.size = _bubble.get_combined_minimum_size()
	var sz := _bubble.size
	var vp := get_viewport().get_visible_rect().size
	var body: Variant = where.call("granny")
	var wants: Array = []  ## [top-left, tail direction]
	if body is Rect2:
		# beside Granny (right, left), else over her head or under her feet, the bubble's foot at her chin
		var b := Rect2(_screen((body as Rect2).position), (body as Rect2).size)
		var y := b.position.y + 14 - sz.y
		var cx := roundf(b.get_center().x - sz.x / 2.0)
		wants = [[Vector2(b.end.x + GAP, y), "left"], [Vector2(b.position.x - GAP - sz.x, y), "right"],
			[Vector2(cx, b.position.y - GAP - sz.y), "down"], [Vector2(cx, b.end.y + GAP), "up"]]
	else:
		var spot: Variant = where.call("bubble")
		var at := _screen(spot) if spot is Vector2 else Vector2(roundf(vp.x / 2.0), TOP + sz.y + 4)
		wants = [[Vector2(roundf(at.x - sz.x / 2.0), at.y - sz.y), ""]]
	# the first spot that fits the screen and leaves the arrow, the key cap and Granny's To-Do note free
	var keep: Array[Rect2] = [_note_rect().grow(2)]
	if _arrow_on:
		keep.append(Rect2(_tip.x - 7, _tip.y - 13, 15, 16))
	if _cap_on:
		keep.append(Rect2(_cap_at.x - 11, _cap_at.y - 13, 23, 14))
	var pick := 0
	for i in wants.size():
		var w: Vector2 = wants[i][0]
		var free := w.x >= 4 and w.x + sz.x <= vp.x - 4 and w.y >= TOP and w.y + sz.y <= vp.y - 4
		for r in keep:
			free = free and not (r.has_area() and Rect2(w, sz).intersects(r))
		if free:
			pick = i
			break
	var want: Vector2 = wants[pick][0]
	var pos := Vector2(clampf(want.x, 4, vp.x - 4 - sz.x), clampf(want.y, TOP, vp.y - 4 - sz.y))
	_bubble.position = pos
	_tail_dir = String(wants[pick][1])
	_tail = Vector2(-1, -1)
	if _tail_dir == "" or pos != want:
		return
	var b2 := Rect2(_screen((body as Rect2).position), (body as Rect2).size)
	var ty := clampf(b2.position.y + 8, pos.y + 3, pos.y + sz.y - 4)
	var tx := clampf(b2.get_center().x, pos.x + 3, pos.x + sz.x - 4)
	match _tail_dir:
		"left":
			_tail = Vector2(pos.x - 3, ty)
		"right":
			_tail = Vector2(pos.x + sz.x + 2, ty)
		"down":
			_tail = Vector2(tx, pos.y + sz.y + 2)
		_:
			_tail = Vector2(tx, pos.y - 3)


## Granny's To-Do note on screen (global rect), or an empty rect.
func _note_rect() -> Rect2:
	var todo := get_tree().get_first_node_in_group("granny_todo") as CanvasLayer
	var panel: Variant = todo.get("_panel") if todo != null and todo.visible else null
	if panel is Control and (panel as Control).is_visible_in_tree():
		return (panel as Control).get_global_rect()
	return Rect2()


# ---------------------------------------------------------------- drawing (whole pixels, palette colours)

func _draw_ink() -> void:
	if _arrow_on:
		_draw_arrow(_tip, _dir)
	if _cap_on:
		_draw_cap(_cap_at)
	if _bubble.visible and _tail.x >= 0:
		# the tail: from the bubble's edge (paper over its ink) to its tip at Granny, drawn along `_tail_dir`
		var along: Vector2 = STEP[_tail_dir]
		var across := Vector2(absf(along.y), absf(along.x))
		for r in TAIL.size():
			var row: String = TAIL[r]
			for i in row.length():
				if row[i] != ".":
					var at := _tail - along * (3 - r) + across * (i - 2)
					_ink.draw_rect(Rect2(at, Vector2.ONE), C_INK if row[i] == "#" else C_PAPER)


func _draw_arrow(tip: Vector2, dir: String) -> void:
	var tip_y := ARROW.size() - 1
	for y in ARROW.size():
		var row: String = ARROW[y]
		for x in row.length():
			var ch := row[x]
			if ch == ".":
				continue
			var col := C_INK if ch == "#" else (C_PAPER if ch == "c" else C_GOLD)
			var p := Vector2(x - 5, y - tip_y)
			match dir:
				"up":
					p = Vector2(p.x, -p.y)
				"right":
					p = Vector2(p.y, p.x)
				"left":
					p = Vector2(-p.y, p.x)
			_ink.draw_rect(Rect2(tip + p, Vector2.ONE), col)


## An 11x11 "E" key cap and a small mouse with its left button lit, side by side, bottom centre at `at`.
func _draw_cap(at: Vector2) -> void:
	var o := Vector2(at.x - 10, at.y - 11)
	_ink.draw_rect(Rect2(o + Vector2(1, 0), Vector2(9, 11)), C_INK)
	_ink.draw_rect(Rect2(o + Vector2(0, 1), Vector2(11, 9)), C_INK)
	_ink.draw_rect(Rect2(o + Vector2(1, 1), Vector2(9, 7)), C_PAPER)
	_ink.draw_rect(Rect2(o + Vector2(1, 8), Vector2(9, 2)), C_SIDE)
	for y in E_GLYPH.size():
		for x in 3:
			if E_GLYPH[y][x] == "#":
				_ink.draw_rect(Rect2(o + Vector2(4 + x, 2 + y), Vector2.ONE), C_TEXT)
	var m := o + Vector2(13, 1)
	for y in MOUSE.size():
		var row: String = MOUSE[y]
		for x in row.length():
			var ch := row[x]
			if ch != ".":
				_ink.draw_rect(Rect2(m + Vector2(x, y), Vector2.ONE), C_INK if ch == "#" else (C_GOLD if ch == "g" else C_PAPER))
