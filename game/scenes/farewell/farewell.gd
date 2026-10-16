extends Control
## P2-FAREWELL · The hidden day-100 farewell and Memory mode (spec §7.12). Router.params:
##   {"mode": "play"} (default; GameState.end_day opens it on the farewell night, under the night's morning card):
##     about 90 s, then the title. The first viewing cannot be skipped; once flags.farewell_seen is set, holding
##     E / Space / Enter, the mouse button or a finger for HOLD_SEC skips it.
##   {"mode": "memory"}: the closed save's keepsake screen over the snowy garden: browse the pantry shelf, open the
##     recipe book, watch the farewell again, back to the title. No day ever starts here (GameState.end_day guards too).
## Timeline (farewell_shots.gd): kitchen -> letter -> pantry -> snow -> credits -> last, each fading in and out in
## dither steps. It runs on _process time, so seek(t) jumps anywhere and Engine.time_scale speeds it up (smoke test).
## The texts come from the save through Farewell (sim/farewell.gd); this scene only lays them out.

const Shots := preload("res://scenes/farewell/farewell_shots.gd")
const ORDER := ["kitchen", "letter", "pantry", "snow", "credits", "last"]
const KITCHEN_SEC := 8.0
const FADE := 1.0
const HOLD_SEC := 1.2
const GLIDE_PX := 900.0
const COVER := Color("23282a")
const GOLD := Color("e5bd7f")
const MUSIC := "mus_farewell"
const WIND := "amb_wind"
const WIND_DB := -14.0
const CREDIT_HEADS := ["TITLE_GAME", "FAREWELL_CREDIT_CAST", "FAREWELL_CREDIT_NEIGHBOURS", "FAREWELL_CREDIT_YOU"]

var mode := "play"
var skippable := false
## The farewell is running (false while it waits for the night card, and in the Memory screen).
var playing := false
var section := ""
var _t := 0.0
var _timeline: Array = []  ## [{"id", "start", "dur"}]
var _shots := {}
var _from_memory := false
var _waiting_night := false
var _hold := 0.0
var _pointer := false
var _leaving := false
var _stage: Control
var _memory_root: Control
var _cover: DitherCover
var _hint: PanelContainer
var _hint_bar: HoldBar
# Memory mode
var _memory_t := 0.0
var _memory_snow: Shots.SnowShot
var _menu: Control
var _menu_first: Button
var _browse: Control
var _shelf: Shots.PantryShot
var _count: Label
var _target := 0.0
var _dragging := false


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_temp(1)  # the scene run alone
	mode = String(Router.params.get("mode", "play"))
	_stage = _layer()
	_memory_root = _layer()
	_cover = DitherCover.new()
	_cover.color = COVER
	_cover.level = DitherCover.LEVELS
	add_child(_cover)
	_build_hint()
	if mode == "memory":
		open_memory()
	else:
		start_play(false)


func _layer() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


# ---------------------------------------------------------------- the farewell

## Starts the farewell from the top. `from_memory`: it returns to the Memory screen instead of the title.
func start_play(from_memory: bool) -> void:
	_build_shots()
	_from_memory = from_memory
	mode = "play"
	skippable = Farewell.seen(GameState.data)
	_t = 0.0
	_hold = 0.0
	_pointer = false
	section = ""
	_memory_root.visible = false
	_cover.level = DitherCover.LEVELS
	playing = true
	_waiting_night = _night_running()
	get_viewport().gui_release_focus()
	Audio.stop_ambient(WIND, 1.0)
	Audio.play_music(MUSIC, 2.0)
	if not _waiting_night:
		_apply()


func total_time() -> float:
	var last: Dictionary = _timeline.back()
	return float(last.start) + float(last.dur)


## Jumps to `t` seconds into the farewell (smoke shots).
func seek(t: float) -> void:
	_waiting_night = false
	_t = t
	_apply()


func shot(id: String) -> Control:
	return _shots.get(id)


func _build_shots() -> void:
	if not _shots.is_empty():
		return
	var d: Dictionary = GameState.data
	var varieties: Dictionary = d.get("varieties", {})
	var kitchen := Shots.KitchenShot.new()
	var letter := Shots.LetterShot.new()
	letter.setup(_texts(Farewell.letter(d)))
	var pantry := Shots.PantryShot.new()
	pantry.setup(Farewell.pan_jars(d), varieties, tr("FAREWELL_PAN_EMPTY"))
	var snow := Shots.SnowShot.new()
	snow.setup(tr("FAREWELL_SNOW_LINE"))
	var credit_lines := Farewell.credits(d)
	var heads: Array = []
	for i in credit_lines.size():
		if String(credit_lines[i].key) in CREDIT_HEADS:
			heads.append(i)
	var credits := Shots.CreditsShot.new()
	credits.setup(Farewell.book_variants(d), varieties, _texts(credit_lines), heads, tr("FAREWELL_BOOK_HEAD"),
		tr("FAREWELL_BOOK_EMPTY"))
	var last := Shots.LastShot.new()
	last.setup(tr("FAREWELL_THANKS"), tr("FAREWELL_FOR_TONTY"))
	var list := [kitchen, letter, pantry, snow, credits, last]
	var start := 0.0
	for i in ORDER.size():
		var s: Control = list[i]
		s.visible = false
		_stage.add_child(s)
		_shots[ORDER[i]] = s
		var dur := KITCHEN_SEC if i == 0 else float(s.call("duration"))
		_timeline.append({"id": ORDER[i], "start": start, "dur": dur})
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
	if playing:
		if _waiting_night:
			_waiting_night = _night_running()
			return
		_t += delta
		_update_hold(delta)
		if playing:
			_apply()
	elif mode == "memory":
		_memory_t += delta
		_memory_snow.at(_memory_t)
		if _browse.visible:
			_glide(delta)
		elif get_viewport().gui_get_focus_owner() == null and get_tree().get_first_node_in_group("book") == null:
			_menu_first.grab_focus()


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
	_shots[section].call("at", lt)
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


func _finish() -> void:
	if _leaving or not playing:
		return
	playing = false
	section = ""
	_hint.visible = false
	_cover.level = DitherCover.LEVELS
	Audio.stop_ambient(WIND, 1.0)
	Audio.stop_music(2.0)
	GameState.save_farewell_seen()
	if _from_memory:
		open_memory()
		_cover.level = DitherCover.LEVELS
		_cover.fade(0, 0.6)
		return
	_leaving = true
	Transition.go("title")


func _night_running() -> bool:
	return Night.is_running()


# ---------------------------------------------------------------- hold to skip

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
	_hint_bar = HoldBar.new()
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
	_hint_bar.ratio = clampf(_hold / HOLD_SEC, 0.0, 1.0)
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
	if playing:
		if event.is_action_pressed("book"):
			get_viewport().set_input_as_handled()  # nothing opens over the farewell
		return
	if mode != "memory" or not _browse.visible:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel"):
		_close_browse()
	elif event.is_action_pressed("move_left", true) or event.is_action_pressed("ui_left", true):
		_step(-1)
	elif event.is_action_pressed("move_right", true) or event.is_action_pressed("ui_right", true):
		_step(1)
	else:
		return
	get_viewport().set_input_as_handled()


class HoldBar:
	extends Control
	var ratio := 0.0:
		set(v):
			ratio = v
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), COVER)
		draw_rect(Rect2(0, 0, floorf(size.x * ratio), size.y), GOLD)


# ---------------------------------------------------------------- Memory mode

## The keepsake screen of a completed save (spec §7.12): pantry, recipe book, the farewell again, the title.
func open_memory() -> void:
	mode = "memory"
	playing = false
	for k in _shots:
		_shots[k].visible = false
	if _menu == null:
		_build_memory()
	_memory_root.visible = true
	_menu.visible = true
	_browse.visible = false
	_cover.level = 0
	_menu_first.grab_focus()
	Audio.play_ambient(WIND, 2.0, WIND_DB)


func _build_memory() -> void:
	var d: Dictionary = GameState.data
	var snow := Shots.SnowShot.new()
	snow.looping = true
	snow.setup("")
	_memory_root.add_child(snow)
	_memory_snow = snow
	snow.at(0.0)
	_menu = CenterContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_memory_root.add_child(_menu)
	var panel := PanelContainer.new()
	_menu.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var head := Label.new()
	head.text = tr("UI_MEMORY_TITLE")
	head.theme_type_variation = &"Heading"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var done := Label.new()
	done.text = tr("UI_MEMORY_COMPLETED") % Farewell.completed_day(d)
	done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(done)
	_menu_first = _menu_button(box, tr("UI_MEMORY_PANTRY"), _open_browse)
	_menu_button(box, tr("UI_MEMORY_BOOK"), _open_book)
	_menu_button(box, tr("UI_MEMORY_REPLAY"), func() -> void:
		Audio.play_ui("ui_confirm")
		start_play(true))
	_menu_button(box, tr("UI_MEMORY_LEAVE"), _leave_memory)
	_build_browse(d)


func _menu_button(box: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _open_book() -> void:
	Audio.play_ui("ui_click")
	get_viewport().gui_release_focus()
	Book.open()


func _leave_memory() -> void:
	if _leaving:
		return
	_leaving = true
	Audio.play_ui("ui_back")
	Audio.stop_ambient(WIND, 1.0)
	Transition.go("title")


## The pantry shelf by hand: arrows / A-D, the mouse wheel, dragging, or the Prev / Next buttons; Esc or Back leaves.
func _build_browse(d: Dictionary) -> void:
	_browse = Control.new()
	_browse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_browse.mouse_filter = Control.MOUSE_FILTER_STOP
	_browse.gui_input.connect(_on_browse_input)
	_memory_root.add_child(_browse)
	var shelf := Shots.PantryShot.new()
	shelf.setup(Farewell.pantry_jars(d), d.get("varieties", {}), tr("FAREWELL_PAN_EMPTY"))
	_browse.add_child(shelf)
	_shelf = shelf
	var back := _browse_button(tr("UI_BACK"), _close_browse)
	back.position = Vector2(4, 4)
	_count = Label.new()
	_count.anchor_left = 1.0
	_count.anchor_right = 1.0
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count.offset_left = -6
	_count.offset_right = -6
	_count.offset_top = 6
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_browse.add_child(_count)
	var prev := _browse_button(tr("UI_MEMORY_PREV"), _step.bind(-1))
	prev.position = Vector2(4, 232)
	var next := _browse_button(tr("UI_MEMORY_NEXT"), _step.bind(1))
	next.anchor_left = 1.0
	next.anchor_right = 1.0
	next.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	next.offset_left = -4
	next.offset_right = -4
	next.offset_top = 232
	_browse.visible = false


func _browse_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # the arrow keys move along the shelf
	b.pressed.connect(cb)
	_browse.add_child(b)
	return b


func _open_browse() -> void:
	Audio.play_ui("ui_click")
	_menu.visible = false
	_browse.visible = true
	get_viewport().gui_release_focus()
	_target = _shelf.offset
	_refresh_count()


func _close_browse() -> void:
	Audio.play_ui("ui_back")
	_browse.visible = false
	_menu.visible = true
	_dragging = false
	_menu_first.grab_focus()


func _step(dir: int) -> void:
	var n: int = _shelf.jar_count()
	if n <= 1:
		return
	var i := clampi(roundi(_target / Shots.PantryShot.SPACING) + dir, 0, n - 1)
	_target = float(i * Shots.PantryShot.SPACING)
	Audio.play_ui("ui_click")


func _glide(delta: float) -> void:
	if not _dragging:
		_shelf.scroll_to(move_toward(_shelf.offset, _target, GLIDE_PX * delta))
	_refresh_count()


func _refresh_count() -> void:
	var n: int = _shelf.jar_count()
	_count.text = tr("UI_MEMORY_COUNT") % [_shelf.current() + 1, n] if n > 0 else ""


## Drag along the shelf (mouse, or a finger through mouse emulation) and the wheel steps.
func _on_browse_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_step(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_step(1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if not mb.pressed:
				var sp: int = Shots.PantryShot.SPACING
				_target = float(clampi(roundi(_shelf.offset / sp), 0, maxi(_shelf.jar_count() - 1, 0)) * sp)
	elif event is InputEventMouseMotion and _dragging:
		_shelf.scroll_to(_shelf.offset - (event as InputEventMouseMotion).relative.x)
		_target = _shelf.offset
