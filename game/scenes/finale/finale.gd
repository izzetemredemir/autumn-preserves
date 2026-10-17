extends Control
## ENDING · The visit: the story ends on the morning of day 30 (docs/story.md §6.1). Router.params:
##   {"mode": "play"} (default; GameState.end_day opens it under the day-30 morning card, the title's Continue opens
##     it on a day-30 save that has not watched it to the end): about 80 s, then the visit day is over (FinaleRules
##     marks it seen, the night runs and the save goes on from the morning of day 31) and the title.
##   {"mode": "replay"} (the title's Visited badge): the same film, the save untouched, back to the title.
## The first viewing cannot be skipped; once flags.story.finale_seen is set, holding E / Space / Enter, the mouse
## button or a finger for HOLD_SEC skips it (the farewell's mechanism and hint).
## Timeline (finale_shots.gd): kitchen -> garden -> snow -> pantry -> note -> credits -> last, each fading in and out
## in dither steps. It runs on _process time, so seek(t) jumps anywhere and Engine.time_scale speeds it up.
## The farewell's shots are reused as they are (pantry rail, letter paper, snow, credits book, last card).

const Shots := preload("res://scenes/farewell/farewell_shots.gd")
const Beats := preload("res://scenes/finale/finale_shots.gd")
const Farewell_ := preload("res://scenes/farewell/farewell.gd")  ## its HoldBar
const ORDER := ["kitchen", "garden", "snow", "pantry", "note", "credits", "last"]
const FADE := 1.0
const HOLD_SEC := 1.2
const COVER := Color("23282a")
const MUSIC := "mus_title"  ## the main theme
const WIND := "amb_wind"
const WIND_DB := -16.0
## Beats played faster than the farewell plays them (film seconds per real second).
const SPEED := {"credits": 1.6}
const LAST_SEC := 6.0
## Sounds on the timeline: [beat, seconds into it, sfx id].
const CUES := [["kitchen", 1.2, "sfx_step_wood"], ["kitchen", 1.5, "sfx_step_wood"], ["kitchen", 1.8, "sfx_step_wood"],
	["kitchen", 6.7, "sfx_door_open"], ["garden", 6.9, "sfx_cat_meow_soft"]]
const CREDIT_HEADS := ["TITLE_GAME", "FAREWELL_CREDIT_CAST", "FAREWELL_CREDIT_NEIGHBOURS", "FAREWELL_CREDIT_YOU"]

var mode := "play"
var skippable := false
var playing := false
var section := ""
var _t := 0.0
var _timeline: Array = []  ## [{"id", "start", "dur", "speed"}]
var _shots := {}
var _waiting_night := false
var _hold := 0.0
var _pointer := false
var _leaving := false
var _stage: Control
var _cover: DitherCover
var _hint: PanelContainer
var _hint_bar: Control


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_temp(1)  # the scene run alone
	mode = String(Router.params.get("mode", "play"))
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_cover = DitherCover.new()
	_cover.color = COVER
	_cover.level = DitherCover.LEVELS
	add_child(_cover)
	_build_hint()
	_build_shots()
	skippable = mode == "replay" or FinaleRules.seen(GameState.data)
	playing = true
	_waiting_night = Night.is_running()
	get_viewport().gui_release_focus()
	Audio.play_music(MUSIC, 2.0)
	if not _waiting_night:
		_apply()


func total_time() -> float:
	var last: Dictionary = _timeline.back()
	return float(last.start) + float(last.dur)


## Jumps to `t` seconds into the finale (smoke shots).
func seek(t: float) -> void:
	_waiting_night = false
	_t = t
	_apply()


func shot(id: String) -> Control:
	return _shots.get(id)


func _build_shots() -> void:
	var d: Dictionary = GameState.data
	var varieties: Dictionary = d.get("varieties", {})
	var kitchen := Beats.KitchenBeat.new()
	kitchen.setup(tr("FINALE_KNOCK"))
	var garden := Beats.GardenBeat.new()
	garden.setup(false, "")
	var snow := Beats.GardenBeat.new()
	snow.setup(true, tr("FINALE_SNOW_LINE"))
	var pantry := Beats.PantryBeat.new()
	pantry.setup(Farewell.pan_jars(d), varieties, tr("FAREWELL_PAN_EMPTY"))
	var note := Shots.LetterShot.new()
	note.setup(_texts(FinaleRules.note(d)))
	var credit_lines := Farewell.credits(d)
	var heads: Array = []
	for i in credit_lines.size():
		if String(credit_lines[i].key) in CREDIT_HEADS:
			heads.append(i)
	var credits := Shots.CreditsShot.new()
	credits.setup(Farewell.book_variants(d), varieties, _texts(credit_lines), heads, tr("FAREWELL_BOOK_HEAD"),
		tr("FAREWELL_BOOK_EMPTY"))
	var last := Shots.LastShot.new()
	last.setup(tr("FINALE_THANKS"), "")
	var list := [kitchen, garden, snow, pantry, note, credits, last]
	var start := 0.0
	for i in ORDER.size():
		var s: Control = list[i]
		var id := String(ORDER[i])
		s.visible = false
		_stage.add_child(s)
		_shots[id] = s
		var speed := float(SPEED.get(id, 1.0))
		var dur := LAST_SEC if id == "last" else float(s.call("duration")) / speed
		_timeline.append({"id": id, "start": start, "dur": dur, "speed": speed})
		start += dur


## [{"key", "args"}] -> translated lines ("" key = empty line).
func _texts(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		var key := String(l.key)
		var text := "" if key == "" else tr(key)
		if not l.args.is_empty():
			text = text % l.args
		out.append(text)
	return out


func _process(delta: float) -> void:
	if not playing:
		return
	if _waiting_night:
		_waiting_night = Night.is_running()
		return
	var before := _t
	_t += delta
	_cues(before, _t)
	_update_hold(delta)
	if playing:
		_apply()


func _apply() -> void:
	if _t >= total_time():
		_finish()
		return
	var cur: Dictionary = _timeline[0]
	for s in _timeline:
		if _t >= float(s.start):
			cur = s
	if String(cur.id) != section:
		_enter(String(cur.id))
	var lt := _t - float(cur.start)
	_shots[section].call("at", lt * float(cur.speed))
	var a := clampf(lt / FADE, 0.0, 1.0)
	var b := clampf((float(cur.dur) - lt) / FADE, 0.0, 1.0)
	_cover.level = roundi(DitherCover.LEVELS * (1.0 - minf(a, b)))


func _enter(id: String) -> void:
	if section == "snow":
		Audio.stop_ambient(WIND, 2.0)
	section = id
	for k in _shots:
		_shots[k].visible = k == id
	if id == "snow":
		Audio.play_ambient(WIND, 3.0, WIND_DB)


## Plays the sounds whose time passed between two timeline moments (never on a seek).
func _cues(from: float, to: float) -> void:
	for c in CUES:
		for s in _timeline:
			if s.id == c[0]:
				var at := float(s.start) + float(c[1])
				if from < at and to >= at:
					Audio.play_sfx(String(c[2]))


func _finish() -> void:
	if _leaving or not playing:
		return
	playing = false
	_leaving = true
	section = ""
	_hint.visible = false
	_cover.level = DitherCover.LEVELS
	Audio.stop_ambient(WIND, 1.0)
	Audio.stop_music(2.0)
	if mode == "play" and GameState.has_game() and not FinaleRules.seen(GameState.data):
		FinaleRules.mark_seen(GameState.data)
		GameState.end_day()  # the visit day is over: the save goes on from the morning of day 31
	Transition.go("title")


# ---------------------------------------------------------------- hold to skip (as the farewell)

func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_left = -4
	_hint.offset_right = -4
	_hint.offset_top = -4
	_hint.offset_bottom = -4
	_hint.visible = false
	add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_hint.add_child(row)
	var l := Label.new()
	l.text = tr("FAREWELL_HOLD_SKIP")
	row.add_child(l)
	_hint_bar = Farewell_.HoldBar.new()
	_hint_bar.custom_minimum_size = Vector2(32, 6)
	_hint_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hint_bar)


## Holding a key, the mouse button or a finger fills the bar; a full bar skips. The first viewing ignores it.
func _update_hold(delta: float) -> void:
	var held := _pointer or Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept")
	if skippable and held:
		_hold += delta / maxf(Engine.time_scale, 0.001)  # real seconds, whatever the playback speed
	else:
		_hold = 0.0
	_hint.visible = _hold > 0.0
	_hint_bar.set("ratio", clampf(_hold / HOLD_SEC, 0.0, 1.0))
	if _hold >= HOLD_SEC:
		_finish()


func _input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer = event.pressed
	elif event is InputEventScreenTouch:
		_pointer = event.pressed


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("book"):
		get_viewport().set_input_as_handled()  # nothing opens over the finale
