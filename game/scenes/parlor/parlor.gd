extends Control
## PARLOR · Granny's parlour, the third room of the house (next to the kitchen): one 480x270 click scene on the
## painted bg_parlor.png. The bookshelf opens the recipe book (as the B key does), the side table the grandchildren's
## letters (LettersUI, as the garden mailbox does), the bed nook asks and then runs the Night (Granny's To-Do bed step
## glows here, TodoRules.SCENE_OF), the cat naps in her basket and purrs when petted (a heart, nothing in the save),
## and the plank door leads back to the kitchen. Granny stands just in from that door. Same hotspots, captions,
## message bar, keyboard focus and music as the kitchen; rules stay in res://sim and the overlays, this only routes.
## Run alone it starts a throwaway game (GameState.start_temp, never saved).

const HUD := "res://ui/hud/hud.tscn"
const NIGHT_GD := "res://ui/transition/night.gd"
const BOOK_GD := "res://ui/book/book.gd"
const TRANSITION_GD := "res://ui/transition/transition.gd"
const TODO_GD := "res://ui/tutorial/granny_todo.gd"
const GRANNY_KITCHEN := "res://assets/sprites/granny/granny_kitchen.png"
const GRANNY_SIZE := Vector2(44, 88)
const BLINK_EVERY := 3.4
const BLINK_SEC := 0.14
const STICKY_MS := 4000
const REVEAL_SEC := 1.5  ## every caption shows this long when Granny walks in (as in the kitchen)
const NAV := [["move_left", SIDE_LEFT], ["move_right", SIDE_RIGHT], ["move_up", SIDE_TOP], ["move_down", SIDE_BOTTOM]]
const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const Hotspot := preload("res://scenes/kitchen/hotspot.gd")
const PArt := preload("res://scenes/parlor/parlor_art.gd")
const HEART := preload("res://assets/sprites/cat/cat_heart.png")
const STORY_SEC := 3.0  ## each memory bubble stays this long

var _spots: Dictionary = {}  # kind -> Hotspot
var _props: Dictionary = {}  # kind -> PArt.Prop (the STORY-02 drawings)
var _story_chunks: Array = []  ## bubbles still to show for the object Granny is talking about
var _story_kind := ""
var _story_gen := 0
var _room: Control
var _bar: PanelContainer
var _message: Label
var _blocker: Control
var _dialog: PanelContainer
var _sleep_btn: Button
var _overlay: CanvasLayer
var _hud: CanvasLayer
var _granny: TextureRect
var _cat: Cat
var _tag: Control
var menu: Node = null  ## the open letters overlay (GuideArrow hides while it is set)
var _last_spot := "door"
var _sticky_until := 0
var _glow := ""
var _room_active := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not GameState.has_game():
		GameState.start_temp(1)
	var bg := %Background as TextureRect
	if bg.texture == null and ResourceLoader.exists(PArt.BACKGROUND):
		bg.texture = load(PArt.BACKGROUND)
	_build_room()
	_build_bar()
	_overlay = CanvasLayer.new()
	_overlay.layer = 12  # above the HUD (10) and the To-Do note (11), like the kitchen's
	add_child(_overlay)
	_build_dialog()
	if ResourceLoader.exists(HUD):
		_hud = load(HUD).instantiate()
		add_child(_hud)
	GameState.changed.connect(_on_state_changed)
	Audio.set_indoor(true)
	Audio.play_music("mus_kitchen")
	Audio.play_ambient("amb_hearth")
	_refresh()
	_connect_todo.call_deferred()
	GuideArrow.attach(self, _guide_at)
	Hotspot.kb_mode = false  # KITCHEN-FOCUS: no frame until the mouse really moves or a key is pressed
	Hotspot.mouse_moved = false
	_focus_spot()
	_reveal_captions(true)  # touch players cannot hover: name every object for a moment on entry
	get_tree().create_timer(REVEAL_SEC).timeout.connect(func() -> void: _reveal_captions(false))


func _reveal_captions(on: bool) -> void:
	if not is_inside_tree():
		return
	for k in _spots:
		_spots[k].reveal = on


# ---------------------------------------------------------------- build

func _build_room() -> void:
	_room = Control.new()
	_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.size = Vector2(480, 270)
	add_child(_room)
	# Granny and the cat go in before the hotspots: hover frames and captions draw over them, clicks pass through.
	if ResourceLoader.exists(GRANNY_KITCHEN):
		var g := TextureRect.new()
		var at := AtlasTexture.new()  # idle frame; the blink frame sits right of it
		at.atlas = load(GRANNY_KITCHEN)
		at.region = Rect2(Vector2.ZERO, GRANNY_SIZE)
		g.texture = at
		g.stretch_mode = TextureRect.STRETCH_KEEP
		g.position = PArt.GRANNY_AT
		g.size = GRANNY_SIZE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_room.add_child(g)
		_granny = g
		var blink := create_tween().set_loops()
		blink.tween_interval(BLINK_EVERY)
		blink.tween_callback(func() -> void: at.region.position.x = GRANNY_SIZE.x)
		blink.tween_interval(BLINK_SEC)
		blink.tween_callback(func() -> void: at.region.position.x = 0.0)
	_cat = Cat.new()
	_room.add_child(_cat)
	_cat.setup(int(GameState.data.get("save_seed", 1)), Vector2i.ZERO)  # home = its cell: it naps there
	_cat.position = PArt.CAT_AT
	for kind: String in ["teo", "nora", "hat", "toys", "jar", "knife"]:  # STORY-02/04 props under the hotspots
		var p := PArt.Prop.new(kind)
		p.position = Vector2(PArt.OBJECTS[kind].position)
		p.size = Vector2(PArt.OBJECTS[kind].size)
		_room.add_child(p)
		_props[kind] = p
	var captions := {
		"door": tr("PARLOR_TO_KITCHEN"), "shelf": tr("PARLOR_BOOK"), "letters": tr("PARLOR_LETTERS"),
		"cat": tr("PARLOR_CAT"), "bed": tr("KITCHEN_BED_CAPTION"),
	}
	for k: String in PArt.MEMORY_CAPTIONS:
		captions[k] = tr(PArt.MEMORY_CAPTIONS[k])
	for kind: String in PArt.OBJECTS:
		var h: Button = Hotspot.new()
		_room.add_child(h)
		h.setup(kind, PArt.OBJECTS[kind], captions.get(kind, ""))
		h.pressed.connect(_on_spot.bind(kind))
		h.mouse_entered.connect(_on_spot_hover.bind(kind, true))
		h.focus_entered.connect(_on_spot_hover.bind(kind, false))
		h.mouse_exited.connect(_on_spot_leave)
		h.focus_exited.connect(_on_spot_leave)
		_spots[kind] = h
	_tag = PArt.Tag.new()
	_tag.position = Vector2(PArt.TAG_AT)
	_spots.letters.add_child(_tag)


func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.theme_type_variation = &"PaperPanel"
	_bar.position = Vector2(8, 240)
	_bar.custom_minimum_size = Vector2(464, 0)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_message = Label.new()
	_message.theme_type_variation = &"BodyPaper"
	_message.clip_text = true
	_bar.add_child(_message)


## The bed's question (the kitchen's words): Sleep or Not yet, over a click-away blocker.
func _build_dialog() -> void:
	_blocker = Control.new()
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.visible = false
	_blocker.gui_input.connect(_on_blocker_input)
	_overlay.add_child(_blocker)
	_dialog = PanelContainer.new()
	_dialog.visible = false
	_dialog.position = Vector2(130, 96)
	_dialog.custom_minimum_size = Vector2(220, 0)
	_overlay.add_child(_dialog)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_dialog.add_child(vb)
	var ask := Label.new()
	ask.text = tr("KITCHEN_BED_ASK")
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ask.custom_minimum_size = Vector2(206, 0)
	vb.add_child(ask)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	_sleep_btn = Button.new()
	_sleep_btn.text = tr("KITCHEN_SLEEP")
	_sleep_btn.pressed.connect(_on_sleep)
	row.add_child(_sleep_btn)
	var later := Button.new()
	later.text = tr("KITCHEN_NOT_YET")
	later.pressed.connect(_close_dialog)
	row.add_child(later)


# ---------------------------------------------------------------- state -> view

func _on_state_changed(_keys: PackedStringArray) -> void:
	_refresh()


func _refresh() -> void:
	if GameState.data.is_empty():
		return
	_tag.count = Letters.unread_count(GameState.data)
	if _props.has("jar"):
		_props.jar.filled = Story.jar_filled(GameState.data)
	var kf := Story.knife_found(GameState.data)  # STORY-04: the 8th memory shows once found
	if _props.has("knife"):
		_props.knife.visible = kf
	if _spots.has("knife"):
		_spots.knife.visible = kf
	_update_glow()


func _connect_todo() -> void:
	var todo := get_tree().get_first_node_in_group("granny_todo") as CanvasLayer
	if todo == null:  # the note may still be on its way into the tree
		await get_tree().process_frame
		if not is_inside_tree():
			return
		todo = get_tree().get_first_node_in_group("granny_todo") as CanvasLayer
	if todo != null and todo.has_signal("step_changed") and not todo.is_connected("step_changed", _on_step_changed):
		todo.connect("step_changed", _on_step_changed)
	_update_glow()
	_idle_hint()


func _on_step_changed(_step: String) -> void:
	_update_glow()


func _todo_step() -> String:
	if not ResourceLoader.exists(TODO_GD):
		return ""
	return String(load(TODO_GD).current_step())


## The bed glows for Granny's bed step; any other step happens beyond the kitchen, so the door glows.
func _update_glow() -> void:
	var step := _todo_step()
	var spot := ""
	if step != "":
		spot = "bed" if String(TodoRules.SCENE_OF.get(step, "")) == "parlor" else "door"
	if spot == _glow:
		return
	_glow = spot
	for k in _spots:
		_spots[k].set_glow(k == spot)
	_idle_hint()


## ONBOARD-GUIDE (GuideArrow header): the glowing object of the To-Do step and Granny by the door.
func _guide_at(what: String) -> Variant:
	if not _room_active:
		return null
	match what:
		"granny":
			return _granny.get_global_rect() if _granny != null else null
		"bubble":
			return null
		"near":
			return {}
	if not _spots.has(_glow):
		return null
	var h: Control = _spots[_glow]
	var r := h.get_global_rect()
	var top := r.position.y - 6
	var cap: Control = h.get("caption")
	if cap != null and cap.position.y < 0:
		top = minf(top, r.position.y + cap.position.y - 1)
	return Vector2(r.position.x + roundf(r.size.x / 2.0), top)


# ---------------------------------------------------------------- message bar

func _say(text: String, sticky := false) -> void:
	var now := Time.get_ticks_msec()
	if not sticky and now < _sticky_until:
		return
	_message.text = text
	if sticky:
		_sticky_until = now + STICKY_MS


func _idle_hint() -> void:
	var step := _todo_step()
	if _glow != "" and step != "":
		_say("%s: %s" % [tr("TUT_TITLE"), tr(TodoRules.key_of(step))])
	else:
		_say(tr("PARLOR_HINT"))


func _spot_hint(kind: String) -> String:
	match kind:
		"door":
			return tr("PARLOR_KITCHEN_HINT")
		"shelf":
			return tr("KITCHEN_BOOK_HINT")
		"letters":
			var n := Letters.unread_count(GameState.data)
			return tr("PARLOR_LETTERS_NEW") % n if n > 0 else tr("PARLOR_LETTERS_HINT")
		"cat":
			return tr("PARLOR_CAT_HINT")
		"bed":
			return tr("KITCHEN_BED_HINT")
	if kind in Story.OBJECTS:
		return tr("STORY_OBJ_HINT")
	return ""


func _on_spot_hover(kind: String, by_mouse: bool) -> void:
	if not _room_active:
		return
	if by_mouse:
		if not Hotspot.mouse_moved or Hotspot.kb_mode:
			return  # stale hover after a scene change
		Audio.play_ui("ui_hover")
	elif not Hotspot.kb_mode:
		return  # focus grabbed by code, not by a key
	_say(_spot_hint(kind))


func _on_spot_leave() -> void:
	var f := get_viewport().gui_get_focus_owner()
	for k in _spots:
		if _spots[k] == f and Hotspot.kb_mode:
			_say(_spot_hint(k))
			return
	_idle_hint()


# ---------------------------------------------------------------- room actions

func _on_spot(kind: String) -> void:
	if not _room_active:
		return
	_last_spot = kind
	match kind:
		"door":
			_go_kitchen()
		"shelf":
			_open_book()
		"letters":
			_open_letters()
		"cat":
			_pet_cat()
		"bed":
			_ask_bed()
		_:
			if kind in Story.OBJECTS:
				_remember(kind)


# ---------------------------------------------------------------- memories (STORY-02)

## Granny looks at a memory object: her line in a speech bubble (long lines in two bubbles, ~3 s each, a click or the
## same key again skips to the next), a small heart the first time, and the look recorded in flags.story.seen.
## No rewards, no rules.
func _remember(kind: String) -> void:
	if _story_kind == kind and not _story_chunks.is_empty():
		_next_chunk()  # pressed again while she talks: on to the next bubble
		return
	Audio.play_ui("ui_click")
	if Story.mark_seen(GameState.data, kind):
		_heart_pop(kind)
	_story_gen += 1
	_story_kind = kind
	_story_chunks = chunks(tr(Story.object_key(GameState.data, kind)))
	_next_chunk()


## Splits a line at sentence ends so that each piece fits a bubble in two lines (a single long sentence stays whole).
func chunks(text: String) -> Array:
	var sentences: Array = []
	var cur := ""
	for i in text.length():
		cur += text[i]
		if text[i] in ".;?!" and i + 1 < text.length() and text[i + 1] == " ":
			sentences.append(cur.strip_edges())
			cur = ""
	if cur.strip_edges() != "":
		sentences.append(cur.strip_edges())
	var out: Array = []
	var line := ""
	for s: String in sentences:
		var joined := s if line == "" else line + " " + s
		if line != "" and _bubble_lines(joined) > 2:
			out.append(line)
			line = s
		else:
			line = joined
	if line != "":
		out.append(line)
	return out


func _bubble_lines(text: String) -> int:
	var b := SpeechBubble.new()
	_room.add_child(b)
	b.say(text)
	var n := b.line_count()
	b.free()
	return n


func _next_chunk() -> void:
	_story_gen += 1
	if _story_chunks.is_empty():
		_story_kind = ""
		return
	var text: String = _story_chunks.pop_front()
	var head := Vector2(_granny.position.x + _granny.size.x / 2.0, _granny.position.y) if _granny != null else Vector2(70, 100)
	var avoid := Rect2(PArt.OBJECTS[_story_kind]) if PArt.OBJECTS.has(_story_kind) else Rect2()
	SpeechBubble.pop(_room, head, text, STORY_SEC, "granny", avoid)
	var gen := _story_gen
	get_tree().create_timer(STORY_SEC).timeout.connect(func() -> void:
		if gen == _story_gen and is_inside_tree():
			_next_chunk())


## The first look at an object: a heart (the cat's) floats up from it.
func _heart_pop(kind: String) -> void:
	var r := Rect2(PArt.OBJECTS[kind])
	var h := Sprite2D.new()
	h.texture = HEART
	h.region_enabled = true
	h.region_rect = Rect2(8, 0, 8, 8)
	h.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	h.position = Vector2(roundf(r.get_center().x), roundf(r.position.y + 4))
	h.z_index = 40
	_room.add_child(h)
	var tw := create_tween()
	tw.tween_property(h, "position:y", h.position.y - 12.0, 0.7)
	tw.tween_callback(h.queue_free)


func _go_kitchen() -> void:
	Audio.play_sfx("sfx_door_open")
	_set_room_active(false)
	if ResourceLoader.exists(TRANSITION_GD):
		load(TRANSITION_GD).go("kitchen")
	else:
		Router.goto("kitchen")


func _open_book() -> void:
	if not ResourceLoader.exists(BOOK_GD):
		Audio.play_ui("ui_error")
		_say(tr("KITCHEN_BOOK_LATER"), true)
		return
	Audio.play_ui("ui_click")
	var book: Node = load(BOOK_GD).open()
	if book != null and not book.tree_exited.is_connected(_after_overlay):
		book.tree_exited.connect(_after_overlay, CONNECT_ONE_SHOT)


## The letters overlay when any letter has come (as the garden mailbox opens it); a line while none has.
func _open_letters() -> void:
	var letters: Variant = GameState.data.get("letters")
	if typeof(letters) != TYPE_DICTIONARY or letters.get("inbox", []).is_empty():
		Audio.play_ui("ui_click")
		_say(tr("GARDEN_NO_MAIL"), true)
		return
	Audio.play_sfx("sfx_page_turn")
	var ui := LettersUI.open()
	if ui == null:
		return
	menu = ui
	_set_room_active(false)
	ui.closed.connect(_on_letters_closed, CONNECT_ONE_SHOT)


func _on_letters_closed() -> void:
	menu = null
	if not is_inside_tree():
		return
	_set_room_active(true)
	_refresh()
	_refocus.call_deferred()


## Petting: the cat purrs with a heart (Cat.pet), a little squash and a line. Nothing in the save changes.
func _pet_cat() -> void:
	if _cat == null or _cat.is_purring():
		return
	_cat.pet()
	Juice.squash(_cat, 0.2)
	Audio.play_sfx("sfx_cat_purr", false)
	_say(tr("PARLOR_CAT_PURR"), true)


func _after_overlay() -> void:
	_refocus.call_deferred()


func _refocus() -> void:
	if is_inside_tree() and _room_active:
		_focus_spot()


func _focus_spot() -> void:
	if _spots.has(_last_spot):
		_spots[_last_spot].grab_focus()


func _set_room_active(on: bool) -> void:
	_room_active = on
	for k in _spots:
		var h: Button = _spots[k]
		h.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		h.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


func _on_blocker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _dialog.visible:
		_close_dialog()


# ---------------------------------------------------------------- bed

func _ask_bed() -> void:
	Audio.play_ui("ui_click")
	_set_room_active(false)
	_blocker.visible = true
	_dialog.visible = true
	_sleep_btn.grab_focus()


func _close_dialog() -> void:
	_dialog.visible = false
	_blocker.visible = false
	Audio.play_ui("ui_back")
	_set_room_active(true)
	_focus_spot()


func _on_sleep() -> void:
	_dialog.visible = false
	_blocker.visible = false
	Audio.play_sfx("sfx_bed_in")
	if ResourceLoader.exists(NIGHT_GD):
		var night: Node = load(NIGHT_GD).start()  # fades to night, GameState.end_day() + autosave, morning card
		if night != null:
			night.finished.connect(_on_night_done, CONNECT_ONE_SHOT)
		else:
			_set_room_active(true)
		return
	var events := GameState.end_day()
	_say(tr("KITCHEN_MORNING") % [int(GameState.data.day), events.size()], true)
	_set_room_active(true)
	_focus_spot()


func _on_night_done(_events: Array) -> void:
	if not is_inside_tree():
		return
	_set_room_active(true)
	_last_spot = "door"
	_focus_spot()
	_idle_hint()


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_TAB and not event.is_echo():
		_reveal_captions(event.is_pressed())
	_set_device(event)


## A navigation press (move_*, ui_*, interact, Tab); stray modifier or media keys do not count (as the kitchen).
func _is_nav_press(event: InputEvent) -> bool:
	if not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed():
		return false
	for a in ["move_left", "move_right", "move_up", "move_down", "ui_left", "ui_right", "ui_up", "ui_down",
			"ui_accept", "ui_focus_next", "ui_focus_prev", "interact"]:
		if InputMap.has_action(a) and event.is_action(a):
			return true
	return false


## Mouse motion -> mouse mode (frames follow the pointer); a ui/interact/Tab key -> keyboard mode (focus frame).
func _set_device(event: InputEvent) -> void:
	var kb := false
	if event is InputEventMouseMotion:
		kb = false
	elif _is_nav_press(event):
		kb = true
	else:
		return
	var was := Hotspot.kb_mode
	var had := Hotspot.mouse_moved
	Hotspot.set_device(kb)
	if was != kb or had != Hotspot.mouse_moved:
		for k in _spots:
			_spots[k]._on_state()
		if kb:
			_on_spot_leave()
		else:
			_idle_hint()


func _unhandled_input(event: InputEvent) -> void:
	if _story_kind != "" and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_next_chunk()  # a click on the room skips the bubble; the last one closes it
		if _story_chunks.is_empty():
			for b in _room.get_children():
				if b is SpeechBubble:
					b.queue_free()
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel"):
		if _dialog.visible:
			_close_dialog()
			get_viewport().set_input_as_handled()
		return
	var f := get_viewport().gui_get_focus_owner()
	if event.is_action_pressed("interact"):
		if f is BaseButton and f.is_visible_in_tree() and not (f as BaseButton).disabled:
			(f as BaseButton).pressed.emit()
			get_viewport().set_input_as_handled()
		elif f == null and _room_active:
			_focus_spot()
			get_viewport().set_input_as_handled()
		return
	for pair: Array in NAV:
		if event.is_action_pressed(pair[0]):
			if f == null:
				if _room_active:
					_focus_spot()
			else:
				var n := f.find_valid_focus_neighbor(pair[1])
				if n != null:
					n.grab_focus()
			get_viewport().set_input_as_handled()
			return
