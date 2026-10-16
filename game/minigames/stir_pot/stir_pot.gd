class_name StirPot
extends MiniGame
## MG-STIR: stove stirring (design 11.1). Circle the pot with mouse/touch or tap Space; keep the needle in the
## green band; skim foam (click or E). Never touches GameState: only emits finished({"stars", "bar"}).

const DURATION := 40.0
const READY_TIME := 3.0
const RESULT_HOLD := 2.5
const CENTER := Vector2(171, 120)  ## centre of the pot art in stir_bg.png
const POT_R := 60  ## liquid radius of the pot art
const ART := "res://assets/sprites/minigames/stir_pot/"
const LIQUID_POS := Vector2(112, 64)  ## top-left of the liquid mask on the 480x270 screen
const SPOON_FRAMES := 16
const SPOON_SIZE := 176
const GAUGE_X := 330
const GAUGE_TOP := 60
const GAUGE_H := 150
const FILL_RATE := 1.0 / 36.0  ## bar per second spent in the band
const SKIM_BONUS := 0.03
const MAX_FOAM := 6

const C_FILL := Color("c94d2e")
const C_BAND := Color("4e7664")
const C_NEEDLE := Color("f2d9c5")
const C_BAR_BG := Color("111010")
const C_TEXT := Color("f2d9c5")

enum Phase { IDLE, READY, PLAY, DONE }

var phase := Phase.IDLE
var duration := DURATION
var autoplay := false
var fill_color := C_FILL
var tone_dark := C_FILL.darkened(0.3)
var tone_light := C_FILL.lightened(0.45)
var _has_tones := false
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
var _hint_panel: NinePatchRect
var _result_panel: NinePatchRect
var _tex := {}


func _t(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(ART + name + ".png")
	return _tex[name]


## The liquid masks are drawn in cream; recolour them with the jam surface colour (cached per colour).
func _tinted(name: String, col: Color) -> Texture2D:
	var key := "%s|%s" % [name, col.to_html(false)]
	if not _tex.has(key):
		var img: Image = _t(name).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.0:
					img.set_pixel(x, y, col)
		_tex[key] = ImageTexture.create_from_image(img)
	return _tex[key]


func _ui(name: String) -> Texture2D:
	var key := "ui/" + name
	if not _tex.has(key):
		_tex[key] = load("res://assets/sprites/ui/" + name + ".png")
	return _tex[key]


func _panel(rect: Rect2, z: int) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = _ui("ui_panel_dark")
	p.position = rect.position
	p.size = rect.size
	for m in ["left", "top", "right", "bottom"]:
		p.set("patch_margin_" + m, 5)
	p.z_index = z
	add_child(p)
	return p


func _ready() -> void:
	var bg := Sprite2D.new()
	bg.texture = _t("stir_bg")
	bg.centered = false
	bg.z_index = -10
	add_child(bg)
	_panel(Rect2(6, 4, 150, 48), 1)
	_panel(Rect2(GAUGE_X - 16, GAUGE_TOP - 26, 96, 186), -5)
	_hint_panel = _panel(Rect2(8, 226, 464, 40), 1)
	_result_panel = _panel(Rect2(90, 106, 300, 44), 9)
	_result_panel.visible = false
	_label(Vector2(14, 8), "MG_STIR_TITLE")
	_l_time = _label(Vector2(14, 28), "")
	_label(Vector2(GAUGE_X - 8, GAUGE_TOP - 22), "MG_STIR_CONSISTENCY")
	_l_hint = _label(Vector2(16, 229), "MG_STIR_HINT")
	_l_hint.size = Vector2(448, 36)
	_l_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	_has_tones = false
	var app = desc.get("appearance", {})
	if app is Dictionary and app.has("fill"):
		var f = app["fill"]
		if f is Array and f.size() >= 3:  # ProductGen: [dark, mid, light] hex strings
			var tones: Array[Color] = []
			for h in f:
				tones.append(_to_color(h, fill_color))
			tone_dark = tones[0]
			fill_color = tones[1]
			tone_light = tones[2]
			_has_tones = true
		else:
			fill_color = _to_color(f, fill_color)
	if not _has_tones:
		tone_dark = fill_color.darkened(0.3)
		tone_light = fill_color.lightened(0.45)
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


func _to_color(v, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is String and Color.html_is_valid(v):
		return Color(v)
	return fallback


func _label(pos: Vector2, key: String) -> Label:
	var l := Label.new()
	l.text = key  # Label auto-translates keys
	l.position = pos
	l.add_theme_color_override("font_color", C_TEXT)
	l.add_theme_font_size_override("font_size", 18)
	l.z_index = 2
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
	_hint_panel.visible = false
	_result_panel.visible = true
	_result_t = 0.0
	print("STIR RESULT stars=%d bar=%.3f" % [stars, bar])


func _emit() -> void:
	if _emitted:
		return
	_emitted = true
	finished.emit({"stars": stars, "bar": bar})


func _draw() -> void:
	_draw_pot()
	_draw_gauge()


func _draw_pot() -> void:
	draw_texture(_tinted("stir_liquid", fill_color), LIQUID_POS)
	draw_texture(_tinted("stir_liquid_rim", tone_dark), LIQUID_POS)
	draw_texture(_tinted("stir_liquid_glint", tone_light), LIQUID_POS)
	for k in 3:
		var a := spoon_angle - 0.5 - k * 0.45
		var rr := 26.0 + k * 10.0
		var p0 := CENTER + Vector2(cos(a), sin(a)) * rr
		var p1 := CENTER + Vector2(cos(a - 0.3), sin(a - 0.3)) * rr
		draw_line(p0.round(), p1.round(), tone_light, 1.0)
	if phase == Phase.PLAY or phase == Phase.DONE:
		_draw_bubbles()
	var foam_tex := _t("stir_foam")
	for f in foam:
		draw_texture(foam_tex, (CENTER + f).round() - Vector2(7, 7))
	var idx := posmod(roundi(spoon_angle / (TAU / SPOON_FRAMES)), SPOON_FRAMES)
	draw_texture_rect_region(_t("stir_spoon"), Rect2(CENTER - Vector2(SPOON_SIZE, SPOON_SIZE) / 2, Vector2(SPOON_SIZE, SPOON_SIZE)),
			Rect2(idx * SPOON_SIZE, 0, SPOON_SIZE, SPOON_SIZE))


## Purely visual bubbles (no RNG, no gameplay): more of them when the pot runs hot.
func _draw_bubbles() -> void:
	var tex := _t("stir_bubbles")
	var n := 2 + int(clampf(needle, 0.0, 1.0) * 5.0)
	for i in n:
		var t := fmod(_clock * 0.6 + float(i) * 0.37, 1.0)
		var ang := float(i) * 2.399
		var r := 8.0 + float((i * 17) % 34)
		var pos := (CENTER + Vector2(cos(ang), sin(ang)) * r).round() - Vector2(4, 4)
		var fr := clampi(int(t * 3.0), 0, 2)
		draw_texture_rect_region(tex, Rect2(pos, Vector2(8, 8)), Rect2(fr * 8, 0, 8, 8))


func _draw_gauge() -> void:
	var gx := GAUGE_X
	draw_rect(Rect2(gx, GAUGE_TOP, 16, GAUGE_H), C_BAR_BG)
	var by := roundf(GAUGE_TOP + GAUGE_H * (1.0 - StirScoring.BAND_HI))
	draw_rect(Rect2(gx, by, 16, roundf(GAUGE_H * (StirScoring.BAND_HI - StirScoring.BAND_LO))), C_BAND)
	var frame := _t("stir_gauge_frame")
	draw_texture(frame, Vector2(gx - 2, GAUGE_TOP - 2))
	var ny := roundf(GAUGE_TOP + GAUGE_H * (1.0 - needle))
	draw_texture(_t("stir_needle"), Vector2(gx - 8, ny - 4))
	var bx := GAUGE_X + 48
	draw_texture_rect(_ui("ui_bar_empty"), Rect2(bx, GAUGE_TOP, 16, GAUGE_H), true)
	var h := roundf(GAUGE_H * bar)
	if h > 0.0:
		draw_texture_rect(_ui("ui_bar_fill"), Rect2(bx, GAUGE_TOP + GAUGE_H - h, 16, h), true)
	draw_texture(frame, Vector2(bx - 2, GAUGE_TOP - 2))
	for t in [StirScoring.STAR2, StirScoring.STAR3]:
		var ty := roundf(GAUGE_TOP + GAUGE_H * (1.0 - t))
		draw_line(Vector2(bx - 3, ty), Vector2(bx + 19, ty), C_NEEDLE, 1.0)
