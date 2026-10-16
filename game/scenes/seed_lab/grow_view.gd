class_name GrowView
extends Node2D
## P1-SEEDLAB · Replays one WildGen run step by step (spec §10 P1) from the layers in map.steps
## (WildGen.generate(..., record_steps = true)). Draws the whole map at `ts` px per tile in flat palette colours;
## `set_time(t)` picks the moment. Phases have fixed lengths, so two maps side by side stay in step:
## value noise -> random-walk stream -> Poisson-disk trees -> A* paths -> weighted pickups -> flood-fill check.
## No alpha anywhere: tiles fade in through 4 dither steps, everything sits on whole pixels.

const PHASES := [1.8, 1.4, 1.9, 1.9, 1.6, 2.2]
const STEP_KEYS := ["WILD_STEP_NOISE", "WILD_STEP_STREAM", "WILD_STEP_TREES", "WILD_STEP_PATHS", "WILD_STEP_PICKUPS",
	"WILD_STEP_FLOOD"]
const FADE := 0.36  ## one tile's fade (4 dither steps)
const POP := 0.08  ## cream flash after something appears
const RING_T := 0.3  ## how long a Poisson-disk rejection circle stays
const WAVE := 1.3  ## flood-fill wave from the entrance
const SLIDE := 0.5  ## unreachable items slide to their new tile
const BAND := 3  ## wave front, in steps
const NEVER := 1.0e9
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

## Per WildGen.T_* id: [low noise, high noise] tones (art-bible §1; warm and olive, water stays cold).
const TONES := [["747c37", "9b8039"], ["b66813", "c94d2e"], ["50361e", "83571e"], ["415c5d", "415c5d"],
	["c58845", "c58845"], ["b4b3a0", "b4b3a0"], ["9b8039", "81746a"]]
const CANOPY := {"maple": ["c94d2e", "a22512"], "birch": ["e5bd7f", "9b8039"], "oak": ["747c37", "53612e"]}
const C_FRAME := Color("49423d")
const C_CREAM := Color("f2d9c5")
const C_GOLD := Color("e5bd7f")
const C_RED := Color("a22512")
const C_SPECIAL := Color("c94d2e")
const C_BARK := Color("3d1f29")
const C_INK := Color("111010")
const C_WATER_HEAD := Color("567c7d")
const C_FRUIT_TREE := [Color("b7b768"), Color("747c37")]
const C_BUSH := Color("53612e")

static var _masks := {}  # tile px -> [null, tex 25%, tex 50%, tex 75%]
static var _rings := {}  # radius px -> ring texture

var ts := 6
var w := 0
var h := 0
var t := 0.0
var _colors: Array[Color] = []  # TONES as Colors, flattened [type * 2 + tone]
var _g1 := PackedByteArray()
var _g2 := PackedByteArray()
var _g4 := PackedByteArray()
var _noise := PackedFloat32Array()
var _med := [0.5, 0.5, 0.5]
var _t_fade := PackedFloat32Array()
var _t_g2 := PackedFloat32Array()
var _t_g4 := PackedFloat32Array()
var _stream: Array = []
var _stream_t0 := 0.0
var _stream_dt := 1.0
var _trace: Array = []
var _trace_t0 := 0.0
var _trace_dt := 1.0
var _t_clear := NEVER
var _clearings: Array = []
var _decor: Array = []  # {"c": Vector2i, "kind", "pop", "gone"}
var _items: Array = []  # {"a": Vector2i before the flood fill, "b": final, "kind", "color", "pop"}
var _special: Dictionary = {}
var _t_special := NEVER
var _flood := PackedInt32Array()
var _max_d := 1
var _entrance := Vector2i.ZERO
var _ring_r := 3
var _notes: Array = ["", "", "", "", "", ""]


static func start(phase: int) -> float:
	var s := 0.0
	for i in mini(phase, PHASES.size()):
		s += float(PHASES[i])
	return s


static func total() -> float:
	return start(PHASES.size())


## Phase index at time `at` (0..5), PHASES.size() once the replay is over.
static func phase_at(at: float) -> int:
	for i in PHASES.size():
		if at < start(i + 1):
			return i
	return PHASES.size()


func size_px() -> Vector2i:
	return Vector2i(w * ts, h * ts)


## A short fact for the caption under the map while `phase` runs ("" when there is none).
func note(phase: int) -> String:
	return String(_notes[phase]) if phase >= 0 and phase < _notes.size() else ""


func set_time(at: float) -> void:
	t = at
	queue_redraw()


## Builds the replay from a WildGen map. Without recorded steps it shows the finished map.
func setup(map: Dictionary, varieties: Dictionary, tile_px: int) -> void:
	ts = maxi(tile_px, 2)
	w = int(map.get("w", 0))
	h = int(map.get("h", 0))
	_colors.clear()
	for pair in TONES:
		_colors.append(Color(String(pair[0])))
		_colors.append(Color(String(pair[1])))
	var n := w * h
	var st: Dictionary = map.get("steps", {})
	var ok := n > 0 and st.has("7_validate") and st.has("1_ground")
	var fin: PackedByteArray = map.get("ground", PackedByteArray())
	_g4 = fin
	_g1 = st["1_ground"].ground if ok else fin
	_g2 = st["2_stream"].ground if ok else fin
	_noise = st["1_ground"].get("noise", PackedFloat32Array()) if ok else PackedFloat32Array()
	if _noise.size() != n:
		_noise.resize(n)
		_noise.fill(0.5)
	_entrance = map.get("entrance", Vector2i(floori(w * 0.5), h - 1))
	_t_fade.resize(n)
	_t_g2.resize(n)
	_t_g4.resize(n)
	_t_g2.fill(NEVER)
	_t_g4.fill(NEVER)
	_notes = ["", "", "", "", "", ""]
	_stream = []
	_trace = []
	_clearings = map.get("clearings", [])
	_special = map.get("special", {})
	_decor = []
	_items = []
	_flood = PackedInt32Array()
	_t_clear = 0.0
	_t_special = 0.0
	if not ok:
		_t_fade.fill(0.0)
		for d in map.get("decor_trees", []):
			_decor.append({"c": Vector2i(int(d.x), int(d.y)), "kind": String(d.kind), "pop": 0.0, "gone": NEVER})
		_add_items(map.get("fruit_trees", []), map.get("fruit_trees", []), map.get("pickups", []), map.get("pickups", []),
			varieties, 0.0, 0.0)
		queue_redraw()
		return
	_setup_ground(n)
	_setup_stream(st, n)
	var first_trace := _setup_paths(st, n)
	_setup_trees(st, first_trace)
	_setup_pickups(st, map, varieties)
	_setup_flood(st, n)
	queue_redraw()


func _setup_ground(n: int) -> void:
	var lo := 1.0
	var hi := 0.0
	var per_type := [[], [], []]
	for i in n:
		lo = minf(lo, _noise[i])
		hi = maxf(hi, _noise[i])
		if _g1[i] <= 2:
			per_type[_g1[i]].append(_noise[i])
	for k in 3:
		var vals: Array = per_type[k]
		vals.sort()
		_med[k] = vals[floori(vals.size() * 0.5)] if not vals.is_empty() else 0.5
	var span := maxf(hi - lo, 0.0001)
	var room := float(PHASES[0]) - FADE - 0.2
	for i in n:
		_t_fade[i] = 0.1 + (_noise[i] - lo) / span * room
	_notes[0] = tr("WILD_STEP_NOTE_NOISE")


func _setup_stream(st: Dictionary, n: int) -> void:
	_stream = st["2_stream"].get("stream", [])
	var s1 := start(1)
	_stream_t0 = s1 + 0.1
	_stream_dt = (float(PHASES[1]) - 0.3) / maxf(_stream.size(), 1.0)
	for k in _stream.size():
		var c: Vector2i = _stream[k]
		_t_g2[c.y * w + c.x] = _stream_t0 + k * _stream_dt
	for i in n:
		if _g2[i] != _g1[i] and _t_g2[i] >= NEVER:
			_t_g2[i] = _stream_t0
	if _stream.is_empty():
		_notes[1] = tr("WILD_STEP_NOTE_NO_STREAM") % roundi(float(Data.rules().wild.stream_chance) * 100.0)
	else:
		_notes[1] = tr("WILD_STEP_NOTE_STREAM") % _stream.size()


## Returns {cell index: time the A* trace first reaches it}.
func _setup_paths(st: Dictionary, n: int) -> Dictionary:
	var s3 := start(3)
	_t_clear = s3 + 0.15
	for p in st["4_paths"].get("paths", []):
		for c in p:
			_trace.append(c)
	_trace_t0 = s3 + 0.35
	_trace_dt = (float(PHASES[3]) - 0.5) / maxf(_trace.size(), 1.0)
	var first := {}
	for k in _trace.size():
		var c: Vector2i = _trace[k]
		var i := c.y * w + c.x
		if not first.has(i):
			first[i] = _trace_t0 + k * _trace_dt
	for i in n:
		if _g4[i] != _g2[i]:
			_t_g4[i] = first.get(i, _t_clear)
	_notes[3] = tr("WILD_STEP_NOTE_PATHS") % _clearings.size()
	return first


func _setup_trees(st: Dictionary, first_trace: Dictionary) -> void:
	var s2 := start(2)
	var d3: Array = st["3_decor"].get("decor_trees", [])
	_ring_r = int(st["3_decor"].get("poisson_r", 3))
	var room := float(PHASES[2]) - RING_T - 0.1
	var later := [_cells(st["4_paths"].get("decor_trees", [])), _cells(st["5_pickups"].get("decor_trees", [])),
		_cells(st["6_special"].get("decor_trees", st["5_pickups"].get("decor_trees", [])))]
	for k in d3.size():
		var c := Vector2i(int(d3[k].x), int(d3[k].y))
		var i := c.y * w + c.x
		var gone := NEVER
		if not later[0].has(i):
			gone = first_trace.get(i, _t_clear)
		elif not later[1].has(i):
			gone = -1.0  # becomes a fruit tree: set when the pickups are timed
		elif not later[2].has(i):
			gone = -2.0  # cleared for the special place
		_decor.append({"c": c, "kind": String(d3[k].kind), "pop": s2 + 0.05 + room * k / maxf(d3.size(), 1.0), "gone": gone})
	_notes[2] = tr("WILD_STEP_NOTE_TREES") % [d3.size(), _ring_r]


func _setup_pickups(st: Dictionary, map: Dictionary, varieties: Dictionary) -> void:
	var s4 := start(4)
	var pre: Dictionary = st["6_special"]
	_add_items(pre.get("fruit_trees", []), map.get("fruit_trees", []), pre.get("pickups", []), map.get("pickups", []),
		varieties, s4 + 0.05, float(PHASES[4]) - 0.35)
	_t_special = s4 + float(PHASES[4]) * 0.75
	for it in _items:
		if it.special:
			_t_special = minf(_t_special, it.pop)
	var fruit_at := {}
	for it in _items:
		if it.kind == "fruit_tree":
			fruit_at[it.a.y * w + it.a.x] = it.pop
	for d in _decor:
		if d.gone == -1.0:
			d.gone = fruit_at.get(d.c.y * w + d.c.x, s4 + 0.05)
		elif d.gone == -2.0:
			d.gone = _t_special
	_notes[4] = tr("WILD_STEP_NOTE_PICKUPS") % _items.size()


## Items in pop order: fruit trees, bushes and ground points, then the special place's own.
func _add_items(fruit_a: Array, fruit_b: Array, pick_a: Array, pick_b: Array, varieties: Dictionary, t0: float,
		room: float) -> void:
	var plain: Array = []
	var special: Array = []
	for k in fruit_a.size():
		var it := _item(fruit_a[k], fruit_b[k] if k < fruit_b.size() else fruit_a[k], "fruit_tree", varieties)
		(special if it.special else plain).append(it)
	for k in pick_a.size():
		var it := _item(pick_a[k], pick_b[k] if k < pick_b.size() else pick_a[k], String(pick_a[k].get("kind", "ground")),
			varieties)
		(special if it.special else plain).append(it)
	_items = plain + special
	for k in _items.size():
		_items[k].pop = t0 + room * k / maxf(_items.size(), 1.0)


func _item(a: Dictionary, b: Dictionary, kind: String, varieties: Dictionary) -> Dictionary:
	return {"a": Vector2i(int(a.x), int(a.y)), "b": Vector2i(int(b.x), int(b.y)), "kind": kind,
		"color": WildMapView.fruit_color(String(a.get("type", "")), String(a.get("variety", "")), varieties),
		"special": bool(a.get("special", false)), "pop": 0.0}


func _setup_flood(st: Dictionary, n: int) -> void:
	_flood = st["7_validate"].get("flood", PackedInt32Array())
	if _flood.size() != n:
		_flood = PackedInt32Array()
	_max_d = 1
	for d in _flood:
		_max_d = maxi(_max_d, d)
	var moved := 0
	for it in _items:
		if it.a != it.b:
			moved += 1
	_notes[5] = tr("WILD_STEP_NOTE_MOVED") % moved if moved > 0 else tr("WILD_STEP_NOTE_REACHED")


func _cells(list: Array) -> Dictionary:
	var out := {}
	for d in list:
		out[int(d.y) * w + int(d.x)] = true
	return out


# ---------- drawing ----------

func _draw() -> void:
	if w == 0 or h == 0:
		return
	var masks := _mask_set(ts)
	_frame(Rect2i(-1, -1, w * ts + 2, h * ts + 2), C_FRAME)
	_draw_ground(masks)
	_draw_heads()
	_draw_wave(masks)
	if t >= _t_clear:
		for c in _clearings:
			var cv: Vector2i = c
			_frame(Rect2i((cv.x - 1) * ts, (cv.y - 1) * ts, ts * 3, ts * 3), C_GOLD)
	if not _special.is_empty() and t >= _t_special:
		_frame(Rect2i(int(_special.x) * ts, int(_special.y) * ts, int(_special.get("w", 1)) * ts,
			int(_special.get("h", 1)) * ts), C_SPECIAL)
	if t >= 0.1:
		_frame(Rect2i(_entrance.x * ts - 1, _entrance.y * ts - 1, ts + 2, ts + 2), C_CREAM)
	for d in _decor:
		if t >= d.pop and t < d.gone:
			if t - d.pop < POP:
				_tree(d.c * ts, C_CREAM, C_CREAM)
			else:
				var cc: Array = CANOPY.get(d.kind, CANOPY.oak)
				_tree(d.c * ts, Color(String(cc[0])), Color(String(cc[1])))
	var ring := _ring_tex(_ring_r * ts)
	var half := floori(ts * 0.5)
	for d in _decor:
		if t >= d.pop and t - d.pop < RING_T:
			draw_texture(ring, Vector2(d.c * ts + Vector2i(half, half) - Vector2i(_ring_r * ts, _ring_r * ts)), C_CREAM)
	_draw_items()


func _draw_ground(masks: Array) -> void:
	for y in h:
		for x in w:
			var i := y * w + x
			var tf := _t_fade[i]
			if t < tf:
				continue
			var g := _g1[i]
			if t >= _t_g4[i]:
				g = _g4[i]
			elif t >= _t_g2[i]:
				g = _g2[i]
			var hi := 1 if g <= 2 and _noise[i] > _med[g] else 0
			var c := _colors[clampi(g, 0, TONES.size() - 1) * 2 + hi]
			var lvl := mini(int((t - tf) / FADE * 4.0) + 1, 4)
			if lvl >= 4:
				draw_rect(Rect2(x * ts, y * ts, ts, ts), c)
			else:
				draw_texture(masks[lvl], Vector2(x * ts, y * ts), c)


## The random walk's newest water tile and the A* trace head with a short trail.
func _draw_heads() -> void:
	if t >= _stream_t0 and t < start(2) and not _stream.is_empty():
		var k := mini(int((t - _stream_t0) / _stream_dt), _stream.size() - 1)
		var c: Vector2i = _stream[k]
		draw_rect(Rect2(c.x * ts, c.y * ts, ts, ts), C_WATER_HEAD)
	if t >= _trace_t0 and t < start(4) and not _trace.is_empty():
		var k := int((t - _trace_t0) / _trace_dt)
		for back in 3:
			var j := k - back
			if j >= 0 and j < _trace.size():
				var c: Vector2i = _trace[j]
				draw_rect(Rect2(c.x * ts, c.y * ts, ts, ts), C_CREAM if back == 0 else C_GOLD)


func _draw_wave(masks: Array) -> void:
	var s5 := start(5)
	if _flood.is_empty() or t < s5 or t >= s5 + WAVE:
		return
	var front := (t - s5) / WAVE * float(_max_d + BAND)
	for i in _flood.size():
		var d := _flood[i]
		if d >= 0 and d <= front and d > front - BAND:
			draw_texture(masks[2], Vector2((i % w) * ts, floori(float(i) / w) * ts), C_GOLD)


func _draw_items() -> void:
	var s5 := start(5)
	var slide0 := s5 + WAVE
	for it in _items:
		if t < it.pop:
			continue
		var a: Vector2i = it.a * ts
		var b: Vector2i = it.b * ts
		var p := a
		var moved: bool = it.a != it.b
		if moved and t >= slide0:
			var e := clampf((t - slide0) / SLIDE, 0.0, 1.0)
			e = 1.0 - (1.0 - e) * (1.0 - e)
			p = Vector2i(roundi(lerpf(a.x, b.x, e)), roundi(lerpf(a.y, b.y, e)))
		var flash: bool = t - float(it.pop) < POP
		match String(it.kind):
			"fruit_tree":
				_tree(p, C_CREAM if flash else C_FRUIT_TREE[0], C_CREAM if flash else C_FRUIT_TREE[1])
				draw_rect(Rect2(p.x + 1, p.y + 1, 1, 1), it.color)
				if ts >= 5:
					draw_rect(Rect2(p.x + ts - 3, p.y + ts - 4, 1, 1), it.color)
			"bush":
				var top := floori(ts * 0.34)
				draw_rect(Rect2(p.x + 1, p.y + top, ts - 2, ts - top), C_CREAM if flash else C_BUSH)
				draw_rect(Rect2(p.x + floori(ts * 0.5), p.y + top + 1, 1, 1), it.color)
			_:
				var o := floori(ts * 0.5) - 2
				draw_rect(Rect2(p.x + o, p.y + o, 4, 4), C_INK)
				draw_rect(Rect2(p.x + o + 1, p.y + o + 1, 2, 2), C_CREAM if flash else it.color)
		if moved and t >= s5 and t < s5 + float(PHASES[5]):
			if t < slide0:
				if int((t - s5) / 0.12) % 2 == 0:
					_frame(Rect2i(a.x - 1, a.y - 1, ts + 2, ts + 2), C_RED)
			else:
				_frame(Rect2i(p.x - 1, p.y - 1, ts + 2, ts + 2), C_GOLD)


## Canopy, a shade row and a 1-px trunk, inside one tile at `p` (px).
func _tree(p: Vector2i, base: Color, shade: Color) -> void:
	var cw := ts - 2
	draw_rect(Rect2(p.x + 1, p.y, cw, cw), base)
	draw_rect(Rect2(p.x + 1, p.y + cw - 1, cw, 1), shade)
	draw_rect(Rect2(p.x + floori(ts * 0.5), p.y + cw, 1, ts - cw), C_BARK)


func _frame(r: Rect2i, c: Color) -> void:
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), c)
	draw_rect(Rect2(r.position.x, r.position.y + r.size.y - 1, r.size.x, 1), c)
	draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), c)
	draw_rect(Rect2(r.position.x + r.size.x - 1, r.position.y, 1, r.size.y), c)


## White tile-sized dither masks (Bayer 4x4) for 1/4, 2/4 and 3/4 coverage; drawn tinted, so no alpha blending.
static func _mask_set(px: int) -> Array:
	if _masks.has(px):
		return _masks[px]
	var out: Array = [null]
	for lvl in range(1, 4):
		var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in px:
			for x in px:
				if int(BAYER[(y % 4) * 4 + x % 4]) < lvl * 4:
					img.set_pixel(x, y, Color.WHITE)
		out.append(ImageTexture.create_from_image(img))
	_masks[px] = out
	return out


## A 1-px midpoint circle of radius r, white on transparent.
static func _ring_tex(r: int) -> ImageTexture:
	if _rings.has(r):
		return _rings[r]
	var s := 2 * r + 1
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var x := r
	var y := 0
	var err := 1 - r
	while x >= y:
		for q in [Vector2i(x, y), Vector2i(y, x), Vector2i(-y, x), Vector2i(-x, y), Vector2i(-x, -y), Vector2i(-y, -x),
				Vector2i(y, -x), Vector2i(x, -y)]:
			img.set_pixel(r + q.x, r + q.y, Color.WHITE)
		y += 1
		if err < 0:
			err += 2 * y + 1
		else:
			x -= 1
			err += 2 * (y - x) + 1
	var tex := ImageTexture.create_from_image(img)
	_rings[r] = tex
	return tex
