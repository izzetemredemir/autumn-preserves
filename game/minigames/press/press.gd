class_name Press
extends MiniGame
## MG-PRESS: fruit press rhythm (design 11.4). Press the lever (click/tap, Space, `stir`) on the beat.
## Beats are scheduled on the Time.get_ticks_usec() clock, never frame counts. Only emits finished().

const BEATS := 24
const INTERVAL := 1.2  ## seconds between beats (24 beats ~ 29 s)
const LEAD_IN := 2.5  ## seconds before the first beat
const RESULT_HOLD := 2.5
const HIT_X := 110.0
const PX_PER_SEC := 120.0
const TRACK_Y := 60.0
const IGNORE_MS := 450.0  ## presses earlier than this before a beat are ignored

const C_BG := Color("23282a")
const C_WOOD := Color("83571e")
const C_WOOD_D := Color("50361e")
const C_METAL := Color("81746a")
const C_RIM := Color("b9a697")
const C_TEXT := Color("f2d9c5")
const C_BAR_BG := Color("111010")
const C_JUICE := Color("c94d2e")
const C_PERFECT := Color("dbcc83")
const C_GOOD := Color("b7b768")
const C_MISS := Color("62272c")

enum Phase { IDLE, PLAY, DONE }

var phase := Phase.IDLE
var autoplay := false
var fill_color := C_JUICE
var grades: Array[String] = []  ## per beat, "" while unresolved
var counts := {"perfect": 0, "good": 0, "miss": 0}
var juice := 0.0
var stars := 0

var _t0_usec := 0
var _lever := 0.0  ## 1 = fully down
var _flash := ""
var _flash_t := 0.0
var _result_t := 0.0
var _emitted := false
var _last_click := -1
var _l_msg: Label
var _l_hint: Label


func _ready() -> void:
	_label(Vector2(12, 8), "MG_PRESS_TITLE")
	_l_hint = _label(Vector2(12, 252), "MG_PRESS_HINT")
	_l_msg = _label(Vector2(0, 150), "")
	_l_msg.size = Vector2(480, 30)
	_l_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_msg.z_index = 10
	await get_tree().create_timer(0.2).timeout
	if phase == Phase.IDLE:
		var ctx := {"seed": 7, "recipe": "juice", "desc": {"appearance": {"fill": "c94d2e"}}}
		if "--autoplay" in OS.get_cmdline_user_args():
			ctx["autoplay"] = true
		start(ctx)


func start(ctx: Dictionary) -> void:
	autoplay = bool(ctx.get("autoplay", false))
	var app = ctx.get("desc", {}).get("appearance", {})
	if app is Dictionary and app.has("fill"):
		var f = app["fill"]
		if f is Color:
			fill_color = f
		elif f is String and Color.html_is_valid(f):
			fill_color = Color(f)
	grades.clear()
	for i in BEATS:
		grades.append("")
	counts = {"perfect": 0, "good": 0, "miss": 0}
	juice = 0.0
	_last_click = -1
	_t0_usec = Time.get_ticks_usec()
	phase = Phase.PLAY
	queue_redraw()


func _label(pos: Vector2, key: String) -> Label:
	var l := Label.new()
	l.text = key  # Label auto-translates keys
	l.position = pos
	l.add_theme_color_override("font_color", C_TEXT)
	l.add_theme_font_size_override("font_size", 18)
	add_child(l)
	return l


## Song time in ms since start.
func _now_ms() -> float:
	return float(Time.get_ticks_usec() - _t0_usec) / 1000.0


## Time of beat i in song ms.
static func beat_ms(i: int) -> float:
	return (LEAD_IN + i * INTERVAL) * 1000.0


func _process(delta: float) -> void:
	_lever = maxf(0.0, _lever - delta * 5.0)
	_flash_t = maxf(0.0, _flash_t - delta)
	match phase:
		Phase.PLAY:
			_play()
		Phase.DONE:
			_result_t += delta
			if _result_t >= RESULT_HOLD or (_result_t > 0.4 and Input.is_action_just_pressed("interact")):
				_emit()
	queue_redraw()


func _play() -> void:
	var now := _now_ms()
	if autoplay:
		for i in BEATS:
			if grades[i] == "" and now >= beat_ms(i):
				_press(beat_ms(i))
				break
	elif Input.is_action_just_pressed("stir"):
		_press(now)
	# beats that slipped past the good window are misses
	for i in BEATS:
		if grades[i] == "" and now - beat_ms(i) > PressRules.GOOD_MS:
			_resolve(i, "miss")
	# soft click on each beat, from the same clock
	var k := int(floor((now / 1000.0 - LEAD_IN) / INTERVAL))
	if k >= 0 and k < BEATS and k > _last_click:
		_last_click = k
		Audio.play_sfx("sfx_press_beat", false)
	if grades[BEATS - 1] != "" and phase == Phase.PLAY:
		_finish()


## Resolve the earliest unresolved beat against a press at press_ms (song clock).
func _press(press_ms: float) -> void:
	_lever = 1.0
	for i in BEATS:
		if grades[i] != "":
			continue
		var off := press_ms - beat_ms(i)
		if off < -IGNORE_MS:
			return
		_resolve(i, PressRules.judge(off))
		return


func _resolve(i: int, grade: String) -> void:
	grades[i] = grade
	counts[grade] += 1
	juice = minf(1.0, juice + PressRules.juice_for(grade))
	_flash = grade
	_flash_t = 0.5


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.PLAY or autoplay:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_press(_now_ms())
	elif event is InputEventScreenTouch and event.pressed:
		_press(_now_ms())


func _finish() -> void:
	phase = Phase.DONE
	stars = PressRules.stars_for(counts)
	_l_hint.text = ""
	_l_msg.text = tr("MG_PRESS_RESULT") % [stars, counts["perfect"], counts["good"], counts["miss"]]
	_result_t = 0.0
	print("PRESS RESULT stars=%d perfect=%d good=%d miss=%d" % [stars, counts["perfect"], counts["good"], counts["miss"]])


func _emit() -> void:
	if _emitted:
		return
	_emitted = true
	finished.emit({"stars": stars, "perfect": counts["perfect"], "good": counts["good"], "miss": counts["miss"]})


func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), C_BG)
	_draw_track()
	_draw_press()
	if phase == Phase.DONE:
		draw_rect(Rect2(90, 140, 300, 40), C_BAR_BG)
		draw_rect(Rect2(90, 140, 300, 40), C_RIM, false, 1.0)


func _draw_track() -> void:
	draw_rect(Rect2(20, TRACK_Y - 14, 440, 28), C_BAR_BG)
	var now := _now_ms() / 1000.0 if phase != Phase.IDLE else 0.0
	for i in BEATS:
		var x := roundf(HIT_X + (LEAD_IN + i * INTERVAL - now) * PX_PER_SEC)
		if x < 20 or x > 458:
			continue
		var col := C_TEXT
		match grades[i] if i < grades.size() else "":
			"perfect": col = C_PERFECT
			"good": col = C_GOOD
			"miss": col = C_MISS
		draw_rect(Rect2(x - 3, TRACK_Y - 10, 6, 20), col)
	draw_rect(Rect2(HIT_X - 1, TRACK_Y - 16, 2, 32), C_RIM)
	draw_rect(Rect2(HIT_X - 12, TRACK_Y - 16, 24, 32), C_RIM, false, 1.0)
	if _flash_t > 0.0:
		var fc := C_PERFECT if _flash == "perfect" else (C_GOOD if _flash == "good" else C_MISS)
		draw_rect(Rect2(HIT_X - 12, TRACK_Y + 20, 24, 3), fc)


func _draw_press() -> void:
	var drop := roundf(_lever * 14.0)
	draw_rect(Rect2(150, 110, 10, 130), C_WOOD_D)
	draw_rect(Rect2(250, 110, 10, 130), C_WOOD_D)
	draw_rect(Rect2(140, 100, 130, 12), C_WOOD)
	draw_rect(Rect2(130, 238, 150, 12), C_WOOD)
	draw_rect(Rect2(200, 112, 10, 40 + drop), C_METAL)
	draw_rect(Rect2(172, 152 + drop, 66, 8), C_WOOD)
	draw_rect(Rect2(205, 90 + drop, 90, 6), C_WOOD)
	draw_rect(Rect2(293, 84 + drop, 8, 18), C_WOOD_D)
	draw_rect(Rect2(172, 200, 66, 38), C_WOOD_D)
	draw_rect(Rect2(172, 200, 66, 38), C_RIM, false, 1.0)
	var bx := 340
	var by := 130
	draw_rect(Rect2(bx, by, 40, 100), C_BAR_BG)
	var h := roundf(96.0 * juice)
	draw_rect(Rect2(bx + 2, by + 98 - h, 36, h), fill_color)
	draw_rect(Rect2(bx + 12, by - 12, 16, 12), C_BAR_BG)
	draw_rect(Rect2(bx, by, 40, 100), C_RIM, false, 1.0)
	draw_rect(Rect2(238, 224, 102, 2), fill_color if juice > 0.0 else C_WOOD_D)
