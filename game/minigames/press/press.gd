class_name Press
extends MiniGame
## MG-PRESS: fruit press rhythm (design 11.4). Press the lever (click/tap, Space, `stir`) on the beat.
## Beats are scheduled on the Time.get_ticks_usec() clock, never frame counts. Only emits finished().

const BEATS := 8
const INTERVAL := 0.75  ## seconds between beats: 8 beats in about 7 s (the human found 18 s too long)
const LEAD_IN := 1.5  ## seconds before the first beat
const RESULT_HOLD := 2.0
const HIT_X := 110.0
const PX_PER_SEC := 120.0
const TRACK_Y := 46.0
const IGNORE_MS := 450.0  ## presses earlier than this before a beat are ignored

const T_BG := preload("res://assets/sprites/minigames/press/press_bg.png")
const T_FRAME := preload("res://assets/sprites/minigames/press/press_frame.png")
const T_LEVER := preload("res://assets/sprites/minigames/press/press_lever.png")
const T_BOTTLE := preload("res://assets/sprites/minigames/press/press_bottle.png")
const T_BEAT := preload("res://assets/sprites/minigames/press/press_beat.png")
const T_HIT := preload("res://assets/sprites/minigames/press/press_hit.png")
const T_PANEL := preload("res://assets/sprites/ui/ui_panel_dark.png")
const PRESS_POS := Vector2(170, 72)  ## top-left of the 72x120 press frame
const BOTTLE_POS := Vector2(250, 140)

const C_BG := Color("23282a")
const C_TEXT := Color("f2d9c5")
const C_BAR_BG := Color("111010")
const C_JUICE := Color("c94d2e")
const C_PERFECT := Color("dbcc83")
const C_GOOD := Color("b7b768")
const C_MISS := Color("62272c")
const C_GRID := Color("81746a")
const C_ZONE := Color("3d1f29")

enum Phase { IDLE, PLAY, DONE }

var phase := Phase.IDLE
var autoplay := false
var fill_color := C_JUICE
## Juice tones dark, mid, light (ProductGen.describe() fill): shade at the bottom, body, surface.
var fill_tones: Array[Color] = [C_JUICE, C_JUICE, C_JUICE]
var grades: Array[String] = []  ## per beat, "" while unresolved
var counts := {"perfect": 0, "good": 0, "miss": 0}
var juice := 0.0
var stars := 0

var _t0_usec := 0
var _paused_usec := 0
var _lever := 0.0  ## 1 = fully down
var _flash := ""
var _flash_t := 0.0
var _result_t := 0.0
var _emitted := false
var _last_click := -1
var _l_msg: Label
var _l_hint: Label
var _l_juice: Label
var _combo: Juice.Combo  ## FUN-MG: Perfect/Good in a row


func _ready() -> void:
	_label(Vector2(12, 8), "MG_PRESS_TITLE")
	_l_hint = _label(Vector2(12, 252), "MG_PRESS_HINT")
	_l_juice = _label(Vector2(BOTTLE_POS.x + 26, BOTTLE_POS.y - 2), "MG_PRESS_JUICE")  # JURY-MG: names the bottle meter
	_l_juice.z_index = 2
	_l_msg = _label(Vector2(0, 143), "")
	_l_msg.size = Vector2(480, 30)
	_l_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_l_msg.z_index = 10
	_combo = Juice.combo(self, Vector2(BOTTLE_POS.x + 56, 112))
	await get_tree().create_timer(0.2).timeout
	if phase == Phase.IDLE:
		var ctx := {"seed": 7, "recipe": "juice", "desc": {"appearance": {"fill": ["a22512", "c94d2e", "e19064"]}}}
		if "--autoplay" in OS.get_cmdline_user_args():
			ctx["autoplay"] = true
		start(ctx)


func start(ctx: Dictionary) -> void:
	autoplay = bool(ctx.get("autoplay", false))
	var app: Variant = ctx.get("desc", {}).get("appearance", {})
	var fill: Variant = app.get("fill") if app is Dictionary else null
	fill_tones = PressRules.fill_tones(fill, C_JUICE)
	fill_color = fill_tones[1]
	_l_juice.visible = true
	grades.clear()
	for i in BEATS:
		grades.append("")
	counts = {"perfect": 0, "good": 0, "miss": 0}
	juice = 0.0
	_last_click = -1
	if _combo != null:
		_combo.broke()
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


## PAUSE-MENU: the beat clock stands still while the game is paused (the in-game menu), so no beat is missed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_paused_usec = Time.get_ticks_usec()
	elif what == NOTIFICATION_UNPAUSED and _paused_usec > 0:
		_t0_usec += Time.get_ticks_usec() - _paused_usec
		_paused_usec = 0


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
		Audio.play_sfx("sfx_piece_rotate", false)  # a light wooden tick on each beat
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
	_feel(grade)


## FUN-MG: every beat has a voice. Hits squirt juice from the spout into the bottle (Perfect splashes more, with a
## glug a beat later); the streak counter climbs on Perfect/Good and lets go softly on a miss.
func _feel(grade: String) -> void:
	if grade == "miss":
		Audio.play_sfx("sfx_press_miss")
		_combo.broke()
		return
	Audio.play_sfx("sfx_press_perfect" if grade == "perfect" else "sfx_press_hit")
	_combo.hit()
	var perfect := grade == "perfect"
	var spout := Vector2(PRESS_POS.x + 73, 174)
	var tones: Array = [fill_tones[1], fill_tones[2], fill_tones[0]]
	Juice.droplets(self, spout, Vector2(46, -36), tones, 9 if perfect else 5, 12.0, 240.0, 0.4)
	get_tree().create_timer(0.14).timeout.connect(_glug.bind(perfect, tones))


func _glug(perfect: bool, tones: Array) -> void:
	if not is_inside_tree():
		return
	Juice.sfx_pitched(self, "sfx_spoon_scoop", -5.0 if perfect else -8.0, -4.0)
	var top := BOTTLE_POS.y + 55.0 - roundf(34.0 * juice)  # the surface in the bottle
	var at := Vector2(BOTTLE_POS.x + 12, top)
	if perfect:  # a splash that jumps up out of the neck
		Juice.droplets(self, at, Vector2(0, -62), tones, 8, 20.0, 300.0, 0.45)
	else:
		Juice.droplets(self, at, Vector2(0, -26), tones, 3, 9.0, 220.0, 0.3)


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
	_l_juice.visible = false  # the result strip sits where the meter label is
	_l_msg.text = tr("MG_PRESS_RESULT") % [stars, counts["perfect"], counts["good"], counts["miss"]]
	_result_t = 0.0
	if stars >= 3:
		Juice.star_burst(self, Rect2(BOTTLE_POS.x - 20, BOTTLE_POS.y - 20, 70, 80), 50)
	print("PRESS RESULT stars=%d perfect=%d good=%d miss=%d" % [stars, counts["perfect"], counts["good"], counts["miss"]])


func _emit() -> void:
	if _emitted:
		return
	_emitted = true
	finished.emit({"stars": stars, "perfect": counts["perfect"], "good": counts["good"], "miss": counts["miss"]})


var _panel: StyleBoxTexture


func _box(r: Rect2) -> void:
	if _panel == null:
		_panel = StyleBoxTexture.new()
		_panel.texture = T_PANEL
		for m in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			_panel.set_texture_margin(m, 5.0)
	draw_style_box(_panel, r)


func _draw() -> void:
	draw_texture(T_BG, Vector2.ZERO)
	_box(Rect2(0, -6, 480, 32))  # title strip
	_box(Rect2(0, 248, 480, 28))  # hint strip
	_draw_press()
	_draw_track()
	if phase == Phase.DONE:
		_box(Rect2(14, 134, 452, 36))


func _draw_track() -> void:
	_box(Rect2(14, TRACK_Y - 24, 452, 48))
	if grades.size() < BEATS:
		return  # drawn once before start() filled the grades
	var now := _now_ms() / 1000.0 if phase != Phase.IDLE else 0.0
	# JURY-MG: a rhythm grid (a tick every half beat, scrolling with the song) so the lane never looks empty.
	var g0 := int(floor((now - LEAD_IN) / (INTERVAL * 0.5)))
	for k in range(g0 - 1, g0 + 12):
		var gx := roundf(HIT_X + (LEAD_IN + k * INTERVAL * 0.5 - now) * PX_PER_SEC)
		if gx < 22 or gx > 456:
			continue
		var big := k % 2 == 0
		draw_rect(Rect2(gx - 1, TRACK_Y + (14 if big else 17), 2, 4 if big else 2), C_GRID)
	# the hit zone: ink box with a lit centre line
	draw_rect(Rect2(HIT_X - 14, TRACK_Y - 22, 28, 44), C_ZONE)
	draw_rect(Rect2(HIT_X - 14, TRACK_Y - 22, 28, 2), C_TEXT)
	draw_rect(Rect2(HIT_X - 14, TRACK_Y + 20, 28, 2), C_TEXT)
	draw_rect(Rect2(HIT_X - 1, TRACK_Y - 20, 2, 40), C_GRID)
	var next := -1
	for i in BEATS:
		if grades[i] == "":
			next = i
			break
	for i in BEATS:
		var x := roundf(HIT_X + (LEAD_IN + i * INTERVAL - now) * PX_PER_SEC)
		if x < 22 or x > 456:
			continue
		var f := 0
		match grades[i] if i < grades.size() else "":
			"perfect": f = 1
			"good": f = 2
			"miss": f = 3
		var sc := 2  # drawn at 2x (16x40), whole pixels
		draw_texture_rect_region(T_BEAT, Rect2(x - 4 * sc, TRACK_Y - 10 * sc, 8 * sc, 20 * sc), Rect2(f * 8, 0, 8, 20))
		if i == next and f == 0:  # the beat to hit next gets a cream cap
			draw_rect(Rect2(x - 8, TRACK_Y - 23, 16, 2), C_TEXT)
	if _flash_t > 0.0:
		var fc := C_PERFECT if _flash == "perfect" else (C_GOOD if _flash == "good" else C_MISS)
		draw_rect(Rect2(HIT_X - 14, TRACK_Y + 22, 28, 3), fc)
		draw_rect(Rect2(HIT_X - 14, TRACK_Y - 25, 28, 3), fc)


func _draw_press() -> void:
	draw_texture_rect_region(T_FRAME, Rect2(PRESS_POS, Vector2(72, 120)), Rect2(16, 0, 72, 120))
	var lf := 0 if _lever < 0.34 else (1 if _lever < 0.67 else 2)
	draw_texture_rect_region(T_LEVER, Rect2(PRESS_POS + Vector2(30, 21), Vector2(56, 30)), Rect2(lf * 56, 0, 56, 30))
	# drips from the spout while pressing
	if juice > 0.0 and (_lever > 0.0 or _flash_t > 0.0):
		draw_rect(Rect2(PRESS_POS.x + 73, 172, 2, 5), fill_color)
	# bottle: dark inside, liquid in the three fill tones (light surface, body, dark bottom), glass on top
	var b := BOTTLE_POS
	draw_rect(Rect2(b.x + 4, b.y + 21, 16, 34), C_BAR_BG)
	draw_rect(Rect2(b.x + 9, b.y + 2, 6, 19), C_BAR_BG)
	var h := roundf(34.0 * juice)
	if h > 0.0:
		draw_rect(Rect2(b.x + 4, b.y + 55 - h, 16, h), fill_tones[1])
		if h > 3.0:
			draw_rect(Rect2(b.x + 4, b.y + 55 - h, 16, 2), fill_tones[2])
			draw_rect(Rect2(b.x + 4, b.y + 53, 16, 2), fill_tones[0])
			if h > 8.0:
				draw_rect(Rect2(b.x + 5, b.y + 57 - h, 2, h - 6), fill_tones[2])  # glint down the left side
	draw_texture(T_BOTTLE, b)
	# JURY-MG: the bottle's progress meter, a bigger gauge beside it with quarter ticks.
	var mx := b.x + 28.0
	var my := b.y + 18.0
	draw_rect(Rect2(mx - 1, my - 1, 12, 42), C_TEXT)
	draw_rect(Rect2(mx, my, 10, 40), C_BAR_BG)
	var mh := roundf(40.0 * juice)
	if mh > 0.0:
		draw_rect(Rect2(mx, my + 40 - mh, 10, mh), fill_tones[1])
		draw_rect(Rect2(mx, my + 40 - mh, 10, 2), fill_tones[2])
	for q in range(1, 4):
		draw_rect(Rect2(mx + 6, my + q * 10 - 1, 4, 1), C_TEXT)
