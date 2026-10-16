class_name StirPot
extends MiniGame
## MG-STIR: stove stirring (design 11.1). Circle the pot with mouse/touch or tap Space; keep the needle in the
## green band; skim foam (click or E). Never touches GameState: only emits finished({"stars", "bar"}).

const DURATION := 40.0
const READY_TIME := 3.0
const RESULT_HOLD := 2.5
const CENTER := Vector2(150, 148)
const POT_R := 78
const GAUGE_X := 330
const GAUGE_TOP := 60
const GAUGE_H := 150
const FILL_RATE := 1.0 / 36.0  ## bar per second spent in the band
const SKIM_BONUS := 0.03
const MAX_FOAM := 6

const C_BG := Color("23282a")
const C_STOVE := Color("3d1f29")
const C_POT := Color("567c7d")
const C_RIM := Color("b9a697")
const C_FILL := Color("c94d2e")
const C_BAND := Color("4e7664")
const C_NEEDLE := Color("f2d9c5")
const C_FOAM := Color("f2d9c5")
const C_BAR := Color("e19064")
const C_BAR_BG := Color("111010")
const C_SPOON := Color("83571e")
const C_TEXT := Color("f2d9c5")

enum Phase { IDLE, READY, PLAY, DONE }

var phase := Phase.IDLE
var duration := DURATION
var autoplay := false
var fill_color := C_FILL
var rng := RandomNumberGenerator.new()
var needle := 0.45
var bar := 0.0
var time_left := DURATION
var ready_left := READY_TIME
var stir_speed := 0.0
var spoon_angle := 0.0
var foam: Array[Vector2] = []
var foam_timer := 2.0
var tap_times: Array[float] = []
var stars := 0

var _clock := 0.0
var _prev_mouse_angle := NAN
var _mouse_speed := 0.0
var _ph: Array[float] = [0.0, 0.0, 0.0]
var _result_t := 0.0
var _emitted := false
var _auto_t := 0.0

var _l_time: Label
var _l_msg: Label
var _l_hint: Label


func _ready() -> void:
	_label(Vector2(12, 8), "MG_STIR_TITLE")
	_l_time = _label(Vector2(12, 24), "")
	_label(Vector2(GAUGE_X - 6, GAUGE_TOP - 16), "MG_STIR_CONSISTENCY")
	_l_hint = _label(Vector2(12, 252), "MG_STIR_HINT")
	_l_msg = _label(Vector2(0, 118), "")
	_l_msg.size = Vector2(480, 30)
	_l_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_msg.z_index = 10
	await get_tree().create_timer(0.2).timeout
	if phase == Phase.IDLE:
		var ctx := {"seed": 7, "recipe": "jam", "desc": {"appearance": {"fill": "c94d2e"}}}
		if "--autoplay" in OS.get_cmdline_user_args():
			ctx["autoplay"] = true
			ctx["duration"] = 6.0
		start(ctx)


func start(ctx: Dictionary) -> void:
	rng.seed = int(ctx.get("seed", 1))
	duration = float(ctx.get("duration", DURATION))
	autoplay = bool(ctx.get("autoplay", false))
	var desc: Dictionary = ctx.get("desc", {})
	var app = desc.get("appearance", {})
	if app is Dictionary and app.has("fill"):
		var f = app["fill"]
		if f is Color:
			fill_color = f
		elif f is String and Color.html_is_valid(f):
			fill_color = Color(f)
	for i in 3:
		_ph[i] = rng.randf() * TAU
	time_left = duration
	ready_left = READY_TIME
	needle = 0.45
	bar = 0.0
	foam.clear()
	foam_timer = 2.0
	phase = Phase.READY
	queue_redraw()


func _label(pos: Vector2, key: String) -> Label:
	var l := Label.new()
	l.text = key  # Label auto-translates keys
	l.position = pos
	l.add_theme_color_override("font_color", C_TEXT)
	l.add_theme_font_size_override("font_size", 18)
	add_child(l)
	return l


func _process(delta: float) -> void:
	_clock += delta
	match phase:
		Phase.READY:
			ready_left -= delta
			_l_msg.text = str(maxi(1, ceili(ready_left)))
			if ready_left <= 0.0:
				phase = Phase.PLAY
				_l_msg.text = tr("MG_STIR_GO")
				get_tree().create_timer(0.7).timeout.connect(_clear_msg)
		Phase.PLAY:
			_play(delta)
		Phase.DONE:
			_result_t += delta
			if _result_t >= RESULT_HOLD or (_result_t > 0.4 and Input.is_action_just_pressed("interact")):
				_emit()
	queue_redraw()


func _clear_msg() -> void:
	if phase == Phase.PLAY:
		_l_msg.text = ""


func _play(dt: float) -> void:
	time_left -= dt
	_l_time.text = tr("MG_STIR_TIME") % ceili(maxf(time_left, 0.0))
	if autoplay:
		_run_autoplay(dt)
	_update_stir(dt)
	var wobble := 0.05 * (sin(_clock * 1.3 + _ph[0]) + sin(_clock * 2.9 + _ph[1]) * 0.6 + sin(_clock * 0.7 + _ph[2]) * 0.8)
	needle = StirScoring.needle_step(needle, stir_speed, wobble, dt)
	if StirScoring.in_band(needle):
		bar = minf(1.0, bar + FILL_RATE * dt)
	_update_foam(dt)
	if Input.is_action_just_pressed("skim") and not foam.is_empty():
		_skim(0)
	Audio.set_loop_sfx("sfx_stir_loop", stir_speed > 0.05, lerpf(0.8, 1.4, clampf(stir_speed, 0.0, 1.0)))
	if time_left <= 0.0:
		_finish()


func _update_stir(dt: float) -> void:
	# keyboard: taps in the last second, ~3 taps/s = speed 1.0
	if Input.is_action_just_pressed("stir"):
		tap_times.append(_clock)
	while not tap_times.is_empty() and _clock - tap_times[0] > 1.0:
		tap_times.pop_front()
	var key_speed := float(tap_times.size()) / 3.0
	# mouse / touch: angular speed around the pot centre (one revolution per second = 1.0)
	var mouse_speed := 0.0
	var m := get_global_mouse_position() - CENTER
	if not autoplay and m.length() > 10.0 and m.length() < POT_R * 1.4:
		var a := m.angle()
		if not is_nan(_prev_mouse_angle):
			var d := angle_difference(_prev_mouse_angle, a)
			spoon_angle += d
			mouse_speed = absf(d) / maxf(dt, 0.0001) / TAU
		_prev_mouse_angle = a
	else:
		_prev_mouse_angle = NAN
	_mouse_speed = lerpf(_mouse_speed, mouse_speed, minf(1.0, dt * 12.0))
	var target := maxf(_mouse_speed, key_speed)
	stir_speed = clampf(lerpf(stir_speed, target, minf(1.0, dt * 8.0)), 0.0, 1.5)
	if key_speed > mouse_speed:
		spoon_angle += key_speed * TAU * 0.5 * dt


func _update_foam(dt: float) -> void:
	foam_timer -= dt
	if foam_timer <= 0.0:
		var hot := needle > 0.78
		foam_timer = rng.randf_range(0.8, 1.5) if hot else rng.randf_range(3.0, 5.0)
		if foam.size() < MAX_FOAM:
			var ang := rng.randf() * TAU
			var r := rng.randf_range(10.0, POT_R - 14.0)
			foam.append(Vector2(roundf(cos(ang) * r), roundf(sin(ang) * r)))


func _skim(i: int) -> void:
	foam.remove_at(i)
	bar = minf(1.0, bar + SKIM_BONUS)
	Audio.play_sfx("sfx_foam_skim")


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.PLAY:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = get_global_mouse_position() - CENTER
		for i in foam.size():
			if p.distance_to(foam[i]) <= 9.0:
				_skim(i)
				return


func _run_autoplay(dt: float) -> void:
	_auto_t += dt
	if needle > 0.5:
		var gap := 0.3 if needle > 0.55 else 0.6
		if int(_auto_t / gap) != int((_auto_t - dt) / gap):
			tap_times.append(_clock)
	if not foam.is_empty() and int(_auto_t * 2.0) != int((_auto_t - dt) * 2.0):
		_skim(0)


func _finish() -> void:
	phase = Phase.DONE
	stars = StirScoring.stars_for_bar(bar)
	Audio.set_loop_sfx("sfx_stir_loop", false)
	_l_time.text = ""
	_l_msg.text = tr("MG_STIR_RESULT") % [stars, roundi(bar * 100.0)]
	_l_hint.text = ""
	_result_t = 0.0
	print("STIR RESULT stars=%d bar=%.3f" % [stars, bar])


func _emit() -> void:
	if _emitted:
		return
	_emitted = true
	finished.emit({"stars": stars, "bar": bar})


func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), C_BG)
	draw_rect(Rect2(20, 50, 260, 200), C_STOVE)
	_draw_pot()
	_draw_gauge()
	if phase == Phase.DONE:
		draw_rect(Rect2(90, 106, 300, 44), C_BAR_BG)
		draw_rect(Rect2(90, 106, 300, 44), C_RIM, false, 1.0)


func _draw_pot() -> void:
	draw_circle(CENTER, POT_R + 5, C_RIM)
	draw_circle(CENTER, POT_R + 1, C_POT)
	draw_circle(CENTER, POT_R - 4, fill_color)
	for k in 3:
		var a := spoon_angle - 0.5 - k * 0.45
		var rr := 26.0 + k * 14.0
		var p0 := CENTER + Vector2(cos(a), sin(a)) * rr
		var p1 := CENTER + Vector2(cos(a - 0.3), sin(a - 0.3)) * rr
		draw_line(p0.round(), p1.round(), fill_color.lightened(0.25), 1.0)
	for f in foam:
		var c := (CENTER + f).round()
		draw_circle(c, 6, C_FOAM)
		draw_circle(c + Vector2(-2, -2), 2, Color.WHITE.lerp(C_FOAM, 0.5))
	var dir := Vector2(cos(spoon_angle), sin(spoon_angle))
	var head := (CENTER + dir * 40.0).round()
	var tail := (CENTER + dir * (POT_R + 30.0)).round()
	draw_line(head, tail, C_SPOON, 3.0)
	draw_circle(head, 5, C_SPOON)


func _draw_gauge() -> void:
	var gx := GAUGE_X
	draw_rect(Rect2(gx, GAUGE_TOP, 16, GAUGE_H), C_BAR_BG)
	var by := roundf(GAUGE_TOP + GAUGE_H * (1.0 - StirScoring.BAND_HI))
	draw_rect(Rect2(gx, by, 16, roundf(GAUGE_H * (StirScoring.BAND_HI - StirScoring.BAND_LO))), C_BAND)
	var ny := roundf(GAUGE_TOP + GAUGE_H * (1.0 - needle))
	draw_line(Vector2(gx - 6, ny), Vector2(gx + 22, ny), C_NEEDLE, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(gx - 8, ny - 4), Vector2(gx - 8, ny + 4), Vector2(gx - 1, ny)]), C_NEEDLE)
	var bx := GAUGE_X + 48
	draw_rect(Rect2(bx, GAUGE_TOP, 16, GAUGE_H), C_BAR_BG)
	var h := roundf(GAUGE_H * bar)
	draw_rect(Rect2(bx, GAUGE_TOP + GAUGE_H - h, 16, h), C_BAR)
	for t in [StirScoring.STAR2, StirScoring.STAR3]:
		var ty := roundf(GAUGE_TOP + GAUGE_H * (1.0 - t))
		draw_line(Vector2(bx - 3, ty), Vector2(bx + 19, ty), C_NEEDLE, 1.0)
	draw_rect(Rect2(bx, GAUGE_TOP, 16, GAUGE_H), C_RIM, false, 1.0)
	draw_rect(Rect2(gx, GAUGE_TOP, 16, GAUGE_H), C_RIM, false, 1.0)
