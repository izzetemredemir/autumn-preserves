extends MiniGame
## pack_jar: jar packing (design spec 11.2). Tetris-like drop on a 6x8 grid, no line clears, no physics.
## Phases: PACK -> BRINE (hold to pour) -> LID (3 clicks or one circle) -> DONE.
## Rows are counted from the bottom (row 0 = jar floor). The fill line sits above row 6: 7 rows x 6 cols = 42 cells.

enum Phase { IDLE, PACK, BRINE, LID, DONE }

const COLS := 6
const ROWS := 8
const LINE_ROWS := 7
const BELOW_LINE_CELLS := COLS * LINE_ROWS
const CELL := 16
const JAR_X := 192
const JAR_Y := 104
const BRINE_RATE := 2.5
const DROP_TAP_DELAY := 0.25
const FALL_TIME := 0.1

const ART := "res://assets/sprites/minigames/pack_jar/"
const C_TEXT := Color("f2d9c5")
const C_LINE := Color("e19064")
const C_BRINE := Color("738c7a")
const C_BRINE_DEEP := Color("4e7664")
const C_BRINE_TOP := Color("b4b3a0")
const C_GHOST := Color("415c5d")
const FALLBACK_FILL := Color("b7b768")
const FALLBACK_EDGE := Color("747c37")

var phase := Phase.IDLE
var _ctx: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _types: Array = []
var _grid: Array = []  # _grid[row][col] = 0 empty, else piece id
var _piece_info: Dictionary = {}  # piece id -> {type, x, row, w, h}
var _tex := {}
var _ramp_cache := {}
var _next_id := 1
var _piece: Dictionary = {}  # {type, w, h, x}
var _next_type := ""
var _fall: Dictionary = {}  # {x, w, h, row, id, t}
var _shake := 0.0
var _pending_drop := -1.0
var _press_pos := Vector2.ZERO
var _press_moved := false
var _mouse_held := false
var _brine := 0.0
var _poured := false
var _lid_clicks := 0
var _lid_angle := 0.0
var _last_angle := 0.0
var _stars := 0
var _fill := 0.0
var _brine_ok := true
var _done_t := 0.0
var _emitted := false
var _autoplay := false
var _bot_t := 0.0
var _bot_pour := 0.0

var _hint: Label
var _fill_label: Label
var _done_btn: Button


func _t(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(ART + name + ".png")
	return _tex[name]


func _ui(name: String) -> Texture2D:
	var key := "ui/" + name
	if not _tex.has(key):
		_tex[key] = load("res://assets/sprites/ui/" + name + ".png")
	return _tex[key]


func _panel(rect: Rect2) -> void:
	var p := NinePatchRect.new()
	p.texture = _ui("ui_panel_dark")
	p.position = rect.position
	p.size = rect.size
	for m in ["left", "top", "right", "bottom"]:
		p.set("patch_margin_" + m, 5)
	p.z_index = 1
	add_child(p)


func _ready() -> void:
	_panel(Rect2(16, 4, 448, 44))
	_panel(Rect2(304, 106, 124, 32))
	_hint = _make_label(Vector2(24, 8), 432, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.size = Vector2(432, 36)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fill_label = _make_label(Vector2(314, 112), 108, HORIZONTAL_ALIGNMENT_LEFT)
	_done_btn = Button.new()
	_done_btn.text = "MG_PACK_DONE"
	_done_btn.position = Vector2(300, 196)
	_done_btn.size = Vector2(110, 24)
	_done_btn.focus_mode = Control.FOCUS_NONE
	_done_btn.z_index = 2
	_done_btn.pressed.connect(_start_brine)
	_done_btn.visible = false
	add_child(_done_btn)
	_autoplay = "--autoplay" in OS.get_cmdline_user_args()
	get_tree().create_timer(0.2).timeout.connect(_self_start)


func _make_label(pos: Vector2, w: float, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(w, 20)
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", C_TEXT)
	l.add_theme_font_size_override("font_size", 18)
	l.z_index = 2
	add_child(l)
	return l


func _self_start() -> void:
	if phase != Phase.IDLE:
		return
	finished.connect(func(r: Dictionary) -> void: print("pack_jar result: ", r))
	start({"seed": 1, "recipe": "pickle", "varieties": [], "addin": "", "desc": {},
			"ingredient_types": ["cucumber", "pepper", "chanterelle", "cabbage"]})


func start(ctx: Dictionary) -> void:
	_ctx = ctx
	_rng = Seeds.rng(int(ctx.get("seed", 1)), "pack_jar", 0)
	_types = ctx.get("ingredient_types", [])
	if _types.is_empty():
		_types = ["cucumber"]
	_grid.clear()
	for r in ROWS:
		var row: Array = []
		row.resize(COLS)
		row.fill(0)
		_grid.append(row)
	_next_type = _random_type()
	phase = Phase.PACK
	_done_btn.visible = true
	_hint.text = "MG_PACK_HINT_PACK"
	_spawn_piece()
	_update_fill_label()
	queue_redraw()


func _random_type() -> String:
	return str(_types[_rng.randi() % _types.size()])


func _texture_of(type: String) -> String:
	var info: Dictionary = Data.ingredients().get(type, {})
	return str(info.get("texture", "rings"))


const MARKERS := [Color("111010"), Color("49423d"), Color("81746a"), Color("b9a697"), Color("f2d9c5")]
const PIECE_SPRITES := ["rings", "slices", "strips", "caps", "shreds", "seeds", "chunks"]


func _ramp(type: String) -> Array:
	var info: Dictionary = Data.ingredients().get(type, {})
	var ramp: Array = info.get("ramp", [])
	var out: Array = []
	if ramp.size() >= 5:
		for c in ramp:
			out.append(Color(str(c)))
	else:
		out = [FALLBACK_EDGE.darkened(0.3), FALLBACK_EDGE, FALLBACK_FILL, FALLBACK_FILL.lightened(0.2), FALLBACK_FILL.lightened(0.5)]
	return out


## Piece sprites are drawn with five marker greys; recolour them with the ingredient's palette ramp (cached).
func _piece_tex(type: String, w: int, h: int) -> Texture2D:
	var tex_name := _texture_of(type)
	if not PIECE_SPRITES.has(tex_name):
		tex_name = "chunks"
	var base := PackJarRules.piece_size(tex_name)
	var rotated := base.x != w
	var key := "%s|%s|%d" % [type, tex_name, 1 if rotated else 0]
	if _ramp_cache.has(key):
		return _ramp_cache[key]
	var src: Image = _t("piece_" + tex_name + ("_r" if rotated else "")).get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var ramp := _ramp(type)
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a == 0.0:
				continue
			for i in 5:
				if c.is_equal_approx(MARKERS[i]):
					src.set_pixel(x, y, ramp[i])
					break
	var t := ImageTexture.create_from_image(src)
	_ramp_cache[key] = t
	return t


# ---------------------------------------------------------------- pieces

func _fits_anywhere(w: int, h: int) -> bool:
	var hs := PackJarRules.heights_of(_grid)
	for x in range(0, COLS - w + 1):
		if PackJarRules.landing_row(hs, x, w) + h <= ROWS:
			return true
	return false


func _spawn_piece() -> void:
	if _min_height() >= ROWS:
		_start_brine()
		return
	var type := _next_type
	for _i in 12:
		var sz := PackJarRules.piece_size(_texture_of(type))
		if _fits_anywhere(sz.x, sz.y) or _fits_anywhere(sz.y, sz.x):
			break
		type = _random_type()
	var sz2 := PackJarRules.piece_size(_texture_of(type))
	if not (_fits_anywhere(sz2.x, sz2.y) or _fits_anywhere(sz2.y, sz2.x)):
		type = ""
		sz2 = Vector2i(1, 1)
	_next_type = _random_type()
	_piece = {"type": type, "w": sz2.x, "h": sz2.y, "x": (COLS - sz2.x) / 2}
	if not _fits_anywhere(sz2.x, sz2.y):
		var t: int = _piece.w
		_piece.w = _piece.h
		_piece.h = t
		_piece.x = clampi(int(_piece.x), 0, COLS - int(_piece.w))
	_pending_drop = -1.0
	queue_redraw()


func _min_height() -> int:
	var m := ROWS
	for h in PackJarRules.heights_of(_grid):
		m = mini(m, int(h))
	return m


func _move_piece(dx: int) -> void:
	if phase != Phase.PACK or not _fall.is_empty() or _piece.is_empty():
		return
	_set_piece_x(int(_piece.x) + dx)


func _set_piece_x(x: int) -> void:
	_piece.x = clampi(x, 0, COLS - int(_piece.w))
	queue_redraw()


func _rotate_piece() -> void:
	if phase != Phase.PACK or not _fall.is_empty() or _piece.is_empty():
		return
	var nw := int(_piece.h)
	var nh := int(_piece.w)
	if nw == nh:
		return
	if not _fits_anywhere(nw, nh):
		_shake = 0.15
		return
	_piece.w = nw
	_piece.h = nh
	_piece.x = clampi(int(_piece.x), 0, COLS - nw)
	queue_redraw()


func _drop_piece() -> void:
	if phase != Phase.PACK or not _fall.is_empty() or _piece.is_empty():
		return
	var w := int(_piece.w)
	var h := int(_piece.h)
	var x := int(_piece.x)
	var row := PackJarRules.landing_row(PackJarRules.heights_of(_grid), x, w)
	if row + h > ROWS:
		_shake = 0.15
		return
	var id := _next_id
	_next_id += 1
	_piece_info[id] = {"type": str(_piece.type), "x": x, "row": row, "w": w, "h": h}
	for r in range(row, row + h):
		for c in range(x, x + w):
			_grid[r][c] = id
	_fall = {"x": x, "w": w, "h": h, "row": row, "id": id, "t": 0.0}
	_piece = {}
	_pending_drop = -1.0
	Audio.play_sfx("sfx_jar_piece_drop")
	_update_fill_label()
	queue_redraw()


func _update_fill_label() -> void:
	var pct := int(round(PackJarRules.fill_ratio(PackJarRules.count_below_line(_grid)) * 100.0))
	_fill_label.text = tr("MG_PACK_FILL") % pct


# ---------------------------------------------------------------- phases

func _start_brine() -> void:
	if phase != Phase.PACK:
		return
	phase = Phase.BRINE
	_piece = {}
	_pending_drop = -1.0
	_mouse_held = false
	_done_btn.visible = false
	_hint.text = "MG_PACK_HINT_BRINE"
	queue_redraw()


func _start_lid() -> void:
	phase = Phase.LID
	_mouse_held = false
	Audio.set_loop_sfx("sfx_brine_pour_loop", false)
	_brine_ok = PackJarRules.brine_in_band(_brine)
	_hint.text = "MG_PACK_HINT_LID"
	queue_redraw()


func _finish() -> void:
	phase = Phase.DONE
	_fill = PackJarRules.fill_ratio(PackJarRules.count_below_line(_grid))
	_stars = PackJarRules.stars_for(_fill, _brine_ok)
	_hint.text = "MG_PACK_HINT_DONE"
	Audio.play_sfx("sfx_jar_pop")
	queue_redraw()


func _lid_step() -> void:
	_lid_clicks += 1
	Audio.play_sfx("sfx_lid_twist")
	_check_lid()


func _check_lid() -> void:
	if phase == Phase.LID and (_lid_clicks >= 3 or _lid_angle >= TAU):
		_finish()
	queue_redraw()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	match phase:
		Phase.PACK:
			_input_pack(event)
		Phase.LID:
			_input_lid(event)
		Phase.BRINE:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				_mouse_held = event.pressed


func _column_at(mp: Vector2) -> int:
	return roundi((mp.x - JAR_X) / CELL - int(_piece.w) / 2.0)


func _input_pack(event: InputEvent) -> void:
	if event.is_action_pressed("move_left"):
		_move_piece(-1)
	elif event.is_action_pressed("move_right"):
		_move_piece(1)
	elif event.is_action_pressed("rotate"):
		_rotate_piece()
	elif event.is_action_pressed("move_down") or event.is_action_pressed("stir"):
		_drop_piece()
	elif event.is_action_pressed("interact"):
		_start_brine()
	elif event is InputEventMouseMotion:
		if _piece.is_empty() or not _fall.is_empty():
			return
		var mp := get_local_mouse_position()
		_set_piece_x(_column_at(mp))
		if _mouse_held and mp.distance_to(_press_pos) > 4.0:
			_press_moved = true
	elif event is InputEventMouseButton:
		var mp2 := get_local_mouse_position()
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_rotate_piece()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_held = true
				_press_pos = mp2
				_press_moved = false
				if _pending_drop >= 0.0 or event.double_click:
					_pending_drop = -1.0
					_rotate_piece()
					_press_moved = true  # swallow the release
				elif not _piece.is_empty():
					_set_piece_x(_column_at(mp2))
			else:
				_mouse_held = false
				if _press_moved and mp2.distance_to(_press_pos) > 4.0:
					_drop_piece()
				elif not _press_moved:
					_pending_drop = DROP_TAP_DELAY  # tap: drops unless a second tap rotates


func _input_lid(event: InputEvent) -> void:
	if event.is_action_pressed("stir") or event.is_action_pressed("interact"):
		_lid_step()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_held = true
			_press_pos = get_local_mouse_position()
			_press_moved = false
			_last_angle = _lid_center().angle_to_point(_press_pos)
		else:
			_mouse_held = false
			if not _press_moved:
				_lid_step()
	elif event is InputEventMouseMotion and _mouse_held:
		var mp := get_local_mouse_position()
		if mp.distance_to(_press_pos) > 8.0:
			_press_moved = true
		if _press_moved:
			var a := _lid_center().angle_to_point(mp)
			_lid_angle += absf(angle_difference(_last_angle, a))
			_last_angle = a
			_check_lid()


func _lid_center() -> Vector2:
	return Vector2(JAR_X + COLS * CELL / 2.0, JAR_Y - 6)


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(_shake - delta, 0.0)
		queue_redraw()
	if not _fall.is_empty():
		_fall.t += delta
		if _fall.t >= FALL_TIME:
			_fall = {}
			_spawn_piece()
		queue_redraw()
	if _pending_drop >= 0.0:
		_pending_drop -= delta
		if _pending_drop < 0.0:
			_pending_drop = -1.0
			_drop_piece()
	match phase:
		Phase.BRINE:
			_process_brine(delta)
		Phase.DONE:
			_done_t += delta
			if _done_t >= 0.8 and not _emitted:
				_emitted = true
				finished.emit({"stars": _stars, "fill": _fill})
				if _autoplay:
					get_tree().quit()
	if _autoplay:
		_bot(delta)


func _process_brine(delta: float) -> void:
	var pouring := Input.is_action_pressed("stir") or _mouse_held
	if pouring and _brine < float(ROWS):
		_brine = minf(_brine + BRINE_RATE * delta, float(ROWS))
		_poured = true
		Audio.set_loop_sfx("sfx_brine_pour_loop", true)
		queue_redraw()
	else:
		Audio.set_loop_sfx("sfx_brine_pour_loop", false)
		if _poured:
			_start_lid()


## Headless demo player (scene run with `-- --autoplay`): greedy packing, then pour, then lid clicks.
func _bot(delta: float) -> void:
	_bot_t -= delta
	if _bot_t > 0.0:
		return
	_bot_t = 0.02
	match phase:
		Phase.PACK:
			if _piece.is_empty() or not _fall.is_empty():
				return
			var best := Vector2i(-1, 0)
			var best_row := 99
			var hs := PackJarRules.heights_of(_grid)
			for rot in 2:
				var w := int(_piece.w) if rot == 0 else int(_piece.h)
				var h := int(_piece.h) if rot == 0 else int(_piece.w)
				for x in range(0, COLS - w + 1):
					var row := PackJarRules.landing_row(hs, x, w)
					if row + h <= ROWS and row < best_row:
						best_row = row
						best = Vector2i(x, rot)
			if best.x < 0:
				_start_brine()
				return
			if best.y == 1:
				_rotate_piece()
			_set_piece_x(best.x)
			_drop_piece()
		Phase.BRINE:
			_bot_pour += 0.02
			_mouse_held = _bot_pour < float(LINE_ROWS) / BRINE_RATE
		Phase.LID:
			_lid_step()
			_bot_t = 0.1


# ---------------------------------------------------------------- drawing

func _cell_rect(col: int, row: int) -> Rect2:
	return Rect2(JAR_X + col * CELL, JAR_Y + (ROWS - 1 - row) * CELL, CELL, CELL)


func _draw_piece(pos: Vector2, type: String, w: int, h: int) -> void:
	draw_texture(_piece_tex(type, w, h), pos)


func _draw() -> void:
	draw_texture(_t("jar_bg"), Vector2.ZERO)
	var jar := Rect2(JAR_X, JAR_Y, COLS * CELL, ROWS * CELL)
	draw_texture(_t("jar_back"), jar.position)
	if _brine > 0.0:
		var bh := int(round(_brine * CELL))
		var top := JAR_Y + int(jar.size.y) - bh
		draw_rect(Rect2(JAR_X, top, jar.size.x, bh), C_BRINE)
		if bh > 24:
			draw_rect(Rect2(JAR_X, top + 24, jar.size.x, bh - 24), C_BRINE_DEEP)
		draw_rect(Rect2(JAR_X, top, jar.size.x, 1), C_BRINE_TOP)
		for bx in range(JAR_X + 6, JAR_X + COLS * CELL - 4, 22):
			draw_rect(Rect2(bx, top + 3 + (bx * 7) % 9, 2, 2), C_BRINE_TOP)
	var falling_id: int = int(_fall.id) if not _fall.is_empty() else -1
	for id in _piece_info:
		if int(id) == falling_id:
			continue
		var pi: Dictionary = _piece_info[id]
		var pos := _cell_rect(int(pi.x), int(pi.row) + int(pi.h) - 1).position
		_draw_piece(pos, str(pi.type), int(pi.w), int(pi.h))
	if not _fall.is_empty():
		var k := clampf(float(_fall.t) / FALL_TIME, 0.0, 1.0)
		var off := int(round((1.0 - k) * 2.0 * CELL))
		var fi: Dictionary = _piece_info[falling_id]
		var fpos := _cell_rect(int(fi.x), int(fi.row) + int(fi.h) - 1).position - Vector2(0, off)
		_draw_piece(fpos, str(fi.type), int(fi.w), int(fi.h))
	var ly := JAR_Y + (ROWS - LINE_ROWS) * CELL
	for x in range(JAR_X, JAR_X + COLS * CELL, 8):
		draw_rect(Rect2(x, ly, 4, 1), C_LINE)
	if phase == Phase.PACK and not _piece.is_empty() and _fall.is_empty():
		_draw_current_piece()
	draw_texture(_t("jar_front"), Vector2(JAR_X - 8, JAR_Y - 4))
	if phase == Phase.LID or phase == Phase.DONE:
		_draw_lid()
	if phase == Phase.DONE:
		_draw_stars()
	if phase == Phase.PACK:
		var sz := PackJarRules.piece_size(_texture_of(_next_type))
		_draw_piece(Vector2(120, 130), _next_type, sz.x, sz.y)


func _draw_current_piece() -> void:
	var w := int(_piece.w)
	var h := int(_piece.h)
	var x := int(_piece.x)
	var row := PackJarRules.landing_row(PackJarRules.heights_of(_grid), x, w)
	if row + h <= ROWS:
		for r in range(row, row + h):
			for c in range(x, x + w):
				var gp := _cell_rect(c, r).position
				draw_rect(Rect2(gp, Vector2(CELL, 1)), C_GHOST)
				draw_rect(Rect2(gp + Vector2(0, CELL - 1), Vector2(CELL, 1)), C_GHOST)
	var sx := int(round(sin(_shake * 80.0) * 2.0)) if _shake > 0.0 else 0
	var top := JAR_Y - 8 - h * CELL
	_draw_piece(Vector2(JAR_X + x * CELL + sx, top), str(_piece.type), w, h)


func _draw_lid() -> void:
	var k := 1.0
	if phase == Phase.LID:
		k = clampf(maxf(_lid_clicks / 3.0, _lid_angle / TAU), 0.0, 1.0)
	var y := JAR_Y - 14 + int(round(k * 12.0))
	draw_texture(_t("jar_lid"), Vector2(JAR_X - 8, y))


func _draw_stars() -> void:
	var full := _ui("icon_star_full")
	var empty := _ui("icon_star_empty")
	for i in 3:
		var cx := 240 - 40 + i * 40
		draw_texture_rect_region(full if i < _stars else empty, Rect2(cx - 16, 56, 32, 32), Rect2(0, 0, 16, 16))
