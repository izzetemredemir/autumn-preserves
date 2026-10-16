class_name Knead
extends MiniGame
## MG-KNEAD: knead the dough on the beat (A/D or left/right half), then crimp the pie edge (design 11.5).
## Never touches GameState: only emits finished({"stars", "rhythm_stars", "trace_stars"}).

const READY_TIME := 1.5
const KNEAD_TIME := 20.0
const TRACE_TIME := 10.0
const BEAT_MS := 800.0
const FIRST_BEAT_MS := 800.0
const RESULT_HOLD := 2.0
const CENTER := Vector2(240, 140)
const RING_R := 72.0
const JUDGE_KEYS := {"miss": "MG_KNEAD_MISS", "good": "MG_KNEAD_GOOD", "perfect": "MG_KNEAD_PERFECT"}

const C_BG := Color("23282a")
const C_BOARD := Color("83571e")
const C_DOUGH := Color("e5bd7f")
const C_DOUGH_D := Color("c58845")
const C_CRUST := Color("c58845")
const C_POINT := Color("f2d9c5")
const C_DONE := Color("4e7664")
const C_CURSOR := Color("c94d2e")
const C_TEXT := Color("f2d9c5")
const C_BEAT := Color("e19064")

enum Phase { IDLE, READY, KNEAD, TRACE, DONE }

var phase := Phase.IDLE
var autoplay := false
var knead_time := KNEAD_TIME
var trace_time := TRACE_TIME
var crust := C_CRUST
var perfect := 0
var good := 0
var miss := 0
var beats := 0
var hit_points: Array[bool] = []
var points: Array[Vector2] = []
var rhythm_stars := 1
var trace_stars := 1
var stars := 1

var _t0 := 0  ## usec at start of the current phase
var _judged: Array[bool] = []
var _last_judge := ""
var _last_judge_t := -10.0
var _last_side := 0
var _press_flash := 0.0
var _dragging := false
var _pointer := Vector2(-100, -100)
var _prev_pointer := Vector2(-100, -100)
var _cursor_a := 0.0
var _result_t := 0.0
var _emitted := false
var _auto_i := 0
var _l_msg: Label
var _l_title: Label
var _l_hint: Label
var _l_stat: Label


func _ready() -> void:
	_l_title = _label(Vector2(12, 8), "MG_KNEAD_PART1")
	_l_stat = _label(Vector2(12, 24), "")
	_l_hint = _label(Vector2(12, 252), "MG_KNEAD_HINT1")
	_l_msg = _label(Vector2(0, 90), "")
	_l_msg.size = Vector2(480, 30)
	_l_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_msg.z_index = 10
	await get_tree().create_timer(0.2).timeout
	if phase == Phase.IDLE:
		var ctx := {"seed": 7, "recipe": "pie", "desc": {"appearance": {"fill": "c58845"}}}
		if "--autoplay" in OS.get_cmdline_user_args():
			ctx["autoplay"] = true
			ctx["knead_time"] = 6.0
			ctx["trace_time"] = 4.0
			finished.connect(func(_r: Dictionary) -> void: get_tree().quit())
		start(ctx)


func start(ctx: Dictionary) -> void:
	autoplay = bool(ctx.get("autoplay", false))
	knead_time = float(ctx.get("knead_time", KNEAD_TIME))
	trace_time = float(ctx.get("trace_time", TRACE_TIME))
	var desc: Dictionary = ctx.get("desc", {})
	var app = desc.get("appearance", {})
	if app is Dictionary and app.has("fill"):
		var f = app["fill"]
		if f is Color:
			crust = f
		elif f is String and Color.html_is_valid(f):
			crust = Color(f)
	perfect = 0
	good = 0
	miss = 0
	points = KneadRules.ring_points(CENTER, RING_R)
	hit_points.clear()
	for i in points.size():
		hit_points.append(false)
	beats = int(floor((knead_time * 1000.0 - FIRST_BEAT_MS) / BEAT_MS)) + 1
	_judged.clear()
	for i in beats:
		_judged.append(false)
	_set_phase(Phase.READY)


func _label(pos: Vector2, key: String) -> Label:
	var l := Label.new()
	l.text = key  # Label auto-translates keys
	l.position = pos
	l.add_theme_color_override("font_color", C_TEXT)
	l.add_theme_font_size_override("font_size", 10)
	add_child(l)
	return l


func _set_phase(p: Phase) -> void:
	phase = p
	_t0 = Time.get_ticks_usec()
	_auto_i = 0
	match p:
		Phase.READY:
			_l_msg.text = tr("MG_KNEAD_READY")
		Phase.KNEAD:
			_l_msg.text = ""
			_l_title.text = "MG_KNEAD_PART1"
			_l_hint.text = "MG_KNEAD_HINT1"
		Phase.TRACE:
			_l_title.text = "MG_KNEAD_PART2"
			_l_hint.text = "MG_KNEAD_HINT2"
			_l_msg.text = tr("MG_KNEAD_GO")
			_cursor_a = -PI / 2.0
	queue_redraw()


func _elapsed_ms(now_us: int = -1) -> float:
	if now_us < 0:
		now_us = Time.get_ticks_usec()
	return (now_us - _t0) / 1000.0


func _beat_ms(i: int) -> float:
	return FIRST_BEAT_MS + BEAT_MS * i


func _process(delta: float) -> void:
	_press_flash = maxf(0.0, _press_flash - delta)
	match phase:
		Phase.READY:
			if _elapsed_ms() >= READY_TIME * 1000.0:
				_set_phase(Phase.KNEAD)
		Phase.KNEAD:
			_knead_tick()
		Phase.TRACE:
			_trace_tick(delta)
		Phase.DONE:
			_result_t += delta
			if _result_t >= RESULT_HOLD or (_result_t > 0.4 and Input.is_action_just_pressed("interact")):
				_emit()
	queue_redraw()


func _knead_tick() -> void:
	var ms := _elapsed_ms()
	# Beats nobody answered become misses once the good window has passed.
	for i in beats:
		if not _judged[i] and ms > _beat_ms(i) + KneadRules.GOOD_MS:
			_judged[i] = true
			_register("miss")
	if autoplay:
		while _auto_i < beats and ms >= _beat_ms(_auto_i) + (30.0 if _auto_i % 5 else 100.0):
			var side := KneadRules.beat_side(_auto_i)
			_auto_i += 1
			_press(side, Time.get_ticks_usec())
	_l_stat.text = tr("MG_KNEAD_TIME") % ceili(maxf(0.0, knead_time - ms / 1000.0))
	if _last_judge != "" and Time.get_ticks_msec() / 1000.0 - _last_judge_t < 0.5:
		_l_msg.text = tr(JUDGE_KEYS[_last_judge])
	else:
		_l_msg.text = ""
	if ms >= knead_time * 1000.0:
		for i in beats:
			if not _judged[i]:
				_judged[i] = true
				_register("miss")
		_set_phase(Phase.TRACE)


func _trace_tick(delta: float) -> void:
	var ms := _elapsed_ms()
	_l_stat.text = tr("MG_KNEAD_TIME") % ceili(maxf(0.0, trace_time - ms / 1000.0))
	if ms > 700.0:
		_l_msg.text = ""
	# Keyboard cursor: one lap over the whole phase.
	_cursor_a += TAU / trace_time * delta
	if autoplay:
		var idx := int(ms / (trace_time * 1000.0) * points.size() * 2.0)
		while _auto_i <= mini(idx, points.size() - 1):
			_prev_pointer = _pointer
			_pointer = points[_auto_i]
			_check_hits(_pointer, _pointer)
			_auto_i += 1
	elif _dragging:
		_prev_pointer = _pointer
		_pointer = get_local_mouse_position()
		_check_hits(_prev_pointer, _pointer)
	if ms >= trace_time * 1000.0 or _hit_count() == points.size():
		_finish()


func _cursor_pos() -> Vector2:
	return (CENTER + Vector2(cos(_cursor_a), sin(_cursor_a)) * RING_R).round()


func _hit_count() -> int:
	var n := 0
	for h in hit_points:
		if h:
			n += 1
	return n


func _check_hits(a: Vector2, b: Vector2) -> void:
	for i in points.size():
		if not hit_points[i] and KneadRules.segment_distance(points[i], a, b) <= KneadRules.HIT_PX:
			hit_points[i] = true


func _input(event: InputEvent) -> void:
	if phase == Phase.KNEAD:
		var side := 0
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in [KEY_A, KEY_LEFT]:
				side = -1
			elif event.keycode in [KEY_D, KEY_RIGHT]:
				side = 1
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			side = -1 if get_local_mouse_position().x < 240.0 else 1
		if side != 0:
			_press(side, Time.get_ticks_usec())
	elif phase == Phase.TRACE:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if _dragging:
				_pointer = get_local_mouse_position()
				_prev_pointer = _pointer
				_check_hits(_pointer, _pointer)
		elif event.is_action_pressed("interact") or event.is_action_pressed("stir"):
			var c := _cursor_pos()
			_check_hits(c, c)


## Judge a press on `side` at absolute time now_us against the nearest unjudged beat.
func _press(side: int, now_us: int) -> void:
	var ms := _elapsed_ms(now_us)
	var best := -1
	var best_err := 1e9
	for i in beats:
		if _judged[i]:
			continue
		var e := absf(ms - _beat_ms(i))
		if e < best_err:
			best_err = e
			best = i
	_last_side = side
	_press_flash = 0.12
	if best < 0 or best_err > KneadRules.GOOD_MS:
		return  # stray press, ignored
	_judged[best] = true
	if KneadRules.beat_side(best) != side:
		_register("miss")
	else:
		_register(KneadRules.judge(best_err))


func _register(j: String) -> void:
	match j:
		"perfect":
			perfect += 1
		"good":
			good += 1
		_:
			miss += 1
	_last_judge = j
	_last_judge_t = Time.get_ticks_msec() / 1000.0


func _finish() -> void:
	if phase == Phase.DONE:
		return
	rhythm_stars = KneadRules.rhythm_stars(perfect, good, beats)
	trace_stars = KneadRules.trace_stars(_hit_count(), points.size())
	stars = KneadRules.combine_stars(rhythm_stars, trace_stars)
	_l_msg.text = tr("MG_KNEAD_DONE") % stars
	_result_t = 0.0
	phase = Phase.DONE


func _emit() -> void:
	if _emitted:
		return
	_emitted = true
	var res := {"stars": stars, "rhythm_stars": rhythm_stars, "trace_stars": trace_stars}
	print("knead result: ", res)
	finished.emit(res)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), C_BG)
	if phase == Phase.TRACE or phase == Phase.DONE:
		_draw_pie()
	else:
		_draw_dough()


func _draw_dough() -> void:
	draw_rect(Rect2(60, 190, 360, 14), C_BOARD)
	var step := KneadRules.squash_step(perfect + good)
	var w := 56 + step * 8
	var h := 56 - step * 4
	draw_rect(Rect2(240 - w / 2, 190 - h, w, h), C_DOUGH)
	draw_rect(Rect2(240 - w / 2, 184, w, 6), C_DOUGH_D)
	# Hands as blocks; the one that just pressed moves in and down.
	var l_down := _press_flash > 0.0 and _last_side < 0
	var r_down := _press_flash > 0.0 and _last_side > 0
	draw_rect(Rect2(150 if l_down else 130, 150 if l_down else 130, 28, 20), C_DOUGH_D)
	draw_rect(Rect2(302 if r_down else 322, 150 if r_down else 130, 28, 20), C_DOUGH_D)
	# Beat lane: upcoming beats slide toward the centre hit mark.
	var ms := _elapsed_ms() if phase == Phase.KNEAD else 0.0
	draw_rect(Rect2(238, 60, 4, 16), C_POINT)
	for i in beats:
		if _judged[i]:
			continue
		var dt := _beat_ms(i) - ms
		if dt < -200.0 or dt > 2400.0:
			continue
		var off := int(dt / 2400.0 * 200.0) * KneadRules.beat_side(i)
		draw_rect(Rect2(240 + off - 4, 62, 8, 12), C_BEAT)


func _draw_pie() -> void:
	draw_circle(CENTER, RING_R + 12, crust)
	draw_circle(CENTER, RING_R - 10, C_DOUGH)
	for i in points.size():
		var c: Color = C_DONE if hit_points[i] else C_POINT
		draw_rect(Rect2(points[i] - Vector2(2, 2), Vector2(4, 4)), c)
	if phase == Phase.TRACE and not autoplay:
		var cp := _cursor_pos()
		draw_rect(Rect2(cp - Vector2(3, 3), Vector2(6, 6)), C_CURSOR)
		if _dragging:
			draw_rect(Rect2(_pointer.round() - Vector2(2, 2), Vector2(4, 4)), C_CURSOR)
