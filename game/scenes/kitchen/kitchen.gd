extends Control
## GD-KITCHEN · Kitchen (spec §5, §7.2, §11; tech-spec §7-8): one 480x270 click scene.
## Stove = stir_pot recipes, jar counter = pack_jar recipes, cupboard counts, recipe book, waiting jars on the
## window sill, doors to the garden and the pantry, the bed nook (Night). Cooking: CookPanel picks -> the
## recipe's mini-game -> Kitchen.cook -> result card. Rules stay in res://sim; this scene shows and routes.
## Run alone it starts a throwaway game (GameState.start_temp, never saved) with a debug inventory.

const HUD := "res://ui/hud/hud.tscn"
const RESULT_CARD := "res://ui/result_card/result_card.tscn"
const NIGHT_GD := "res://ui/transition/night.gd"
const BOOK_GD := "res://ui/book/book.gd"
const TRANSITION_GD := "res://ui/transition/transition.gd"
const TODO_GD := "res://ui/tutorial/granny_todo.gd"
const MINIGAME := "res://minigames/%s/%s.tscn"
const BACKGROUNDS := ["res://assets/sprites/backgrounds/bg_kitchen.png", "res://assets/sprites/scenes/bg_kitchen.png"]
const PANEL_POS := Vector2(8, 30)
const STICKY_MS := 4000
## Granny's To-Do steps that happen at a kitchen object; steps elsewhere light the door that leads there.
const STEP_SPOT := {"d1_jam": "stove", "d1_bed": "bed", "d2_brine": "counter"}
const NAV := [["move_left", SIDE_LEFT], ["move_right", SIDE_RIGHT], ["move_up", SIDE_TOP], ["move_down", SIDE_BOTTOM]]
const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const Hotspot := preload("res://scenes/kitchen/hotspot.gd")
const CookPanel := preload("res://scenes/kitchen/cook_panel.gd")
const Shelf := preload("res://scenes/kitchen/waiting_shelf.gd")

## QA hook: merged into every mini-game ctx (e.g. {"autoplay": true, "duration": 4.0} makes stir_pot play itself).
var debug_ctx: Dictionary = {}

var _spots: Dictionary = {}  # kind -> Hotspot
var _room: Control
var _shelf: Control
var _bar: PanelContainer
var _message: Label
var _blocker: Control
var _panel: Panel
var _dialog: PanelContainer
var _sleep_btn: Button
var _overlay: CanvasLayer
var _hud: CanvasLayer
var _todo: CanvasLayer
var _todo_was_visible := false
var _mg: Node = null
var _card: Node = null
var _cooking: Dictionary = {}
var _last_spot := "stove"
var _sticky_until := 0
var _glow := ""
var _room_active := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not GameState.has_game():
		GameState.start_temp(1)
		_debug_fill()
	Forage.empty_bag_to_inbox(GameState.data)
	_setup_background()
	_build_room()
	_build_bar()
	_overlay = CanvasLayer.new()
	_overlay.layer = 12  # above HUD (10) and the To-Do note (11): panel, dialog, mini-game and card cover them
	add_child(_overlay)
	_build_panel()
	_build_dialog()
	if ResourceLoader.exists(HUD):
		_hud = load(HUD).instantiate()
		add_child(_hud)
	GameState.changed.connect(_on_state_changed)
	GameState.notify(PackedStringArray(["bag", "inbox"]))
	Audio.set_indoor(true)
	Audio.play_music("mus_kitchen")
	Audio.play_ambient("amb_hearth")
	_refresh()
	_connect_todo.call_deferred()
	_focus_spot()


# ---------------------------------------------------------------- build

func _setup_background() -> void:
	var bg := %Background as TextureRect
	if bg.texture == null:
		for p: String in BACKGROUNDS:
			if ResourceLoader.exists(p):
				bg.texture = load(p)
				break
	if bg.texture == null:
		bg.texture = Art.background()


func _build_room() -> void:
	_room = Control.new()
	_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.size = Vector2(480, 270)
	add_child(_room)
	var captions := {
		"garden": tr("KITCHEN_TO_GARDEN"), "stove": tr("KITCHEN_STOVE"), "counter": tr("KITCHEN_COUNTER"),
		"cupboard": tr("KITCHEN_CUPBOARD"), "pantry": tr("KITCHEN_TO_PANTRY"), "bed": tr("KITCHEN_BED_CAPTION"),
	}
	for kind: String in Art.OBJECTS:
		var h: Button = Hotspot.new()
		_room.add_child(h)
		h.setup(kind, Art.OBJECTS[kind], captions.get(kind, ""))
		h.pressed.connect(_on_spot.bind(kind))
		h.mouse_entered.connect(_on_spot_hover.bind(kind, true))
		h.focus_entered.connect(_on_spot_hover.bind(kind, false))
		h.mouse_exited.connect(_on_spot_leave)
		h.focus_exited.connect(_on_spot_leave)
		_spots[kind] = h
	_shelf = Shelf.new()
	_room.add_child(_shelf)
	_shelf.hovered.connect(_on_shelf_hover)


func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.theme_type_variation = &"PaperPanel"
	_bar.position = Vector2(8, 240)
	_bar.custom_minimum_size = Vector2(464, 0)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_message = Label.new()
	_message.theme_type_variation = &"PaperLabel"
	_message.clip_text = true
	_bar.add_child(_message)


func _build_panel() -> void:
	_blocker = Control.new()
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.visible = false
	_blocker.gui_input.connect(_on_blocker_input)
	_overlay.add_child(_blocker)
	_panel = CookPanel.new()
	_panel.visible = false
	_overlay.add_child(_panel)
	_panel.position = PANEL_POS
	_panel.home = PANEL_POS
	_panel.cook_requested.connect(_on_cook_requested)
	_panel.close_requested.connect(_close_panel)


func _build_dialog() -> void:
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
	var d := GameState.data
	if d.is_empty():
		return
	_spots.cupboard.set_info({"cupboard": d.cupboard})
	_spots.pantry.set_info({"inbox": d.inbox.size()})
	_shelf.show_items(_waiting(d))
	if _panel.visible and _mg == null:
		_panel.refresh()
	_update_glow()


## Products still waiting (inbox + pantry), soonest first, as {"desc", "wait_left"}.
func _waiting(d: Dictionary) -> Array:
	var items: Array = d.inbox.duplicate()
	for e: Dictionary in d.pantry.items:
		items.append(e.item)
	var out: Array = []
	for item: Dictionary in items:
		if item.kind == "product" and int(item.get("wait_left", 0)) > 0:
			out.append({"desc": ProductGen.describe(String(item.key), d.varieties), "wait_left": int(item.wait_left)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.wait_left) < int(b.wait_left))
	return out


func _connect_todo() -> void:
	_todo = get_tree().get_first_node_in_group("granny_todo") as CanvasLayer
	if _todo != null and _todo.has_signal("step_changed") and not _todo.is_connected("step_changed", _on_step_changed):
		_todo.connect("step_changed", _on_step_changed)
	_update_glow()


func _on_step_changed(_step: String) -> void:
	_update_glow()


func _todo_step() -> String:
	if not ResourceLoader.exists(TODO_GD):
		return ""
	return String(load(TODO_GD).current_step())


## Makes the object of Granny's current To-Do step glow (or the door towards it).
func _update_glow() -> void:
	var step := _todo_step()
	var spot := ""
	if STEP_SPOT.has(step):
		spot = STEP_SPOT[step]
	elif step != "":
		var scene := String(TodoRules.SCENE_OF.get(step, ""))
		if scene == "pantry":
			spot = "pantry"
		elif scene != "" and scene != "kitchen":
			spot = "garden"
	if spot == _glow:
		return
	_glow = spot
	for k in _spots:
		_spots[k].set_glow(k == spot)
	_idle_hint()


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
		_say(tr("KITCHEN_HINT"))


func _spot_hint(kind: String) -> String:
	match kind:
		"stove":
			return tr("KITCHEN_STOVE_HINT")
		"counter":
			return tr("KITCHEN_COUNTER_HINT")
		"book":
			return tr("KITCHEN_BOOK_HINT")
		"cupboard":
			return tr("KITCHEN_CUPBOARD_HINT")
		"pantry":
			return tr("KITCHEN_PANTRY_HINT") % GameState.data.inbox.size()
		"garden":
			return tr("KITCHEN_GARDEN_HINT")
		"bed":
			return tr("KITCHEN_BED_HINT")
	return ""


func _on_spot_hover(kind: String, by_mouse: bool) -> void:
	if not _room_active:
		return
	if by_mouse:
		Audio.play_ui("ui_hover")
	_say(_spot_hint(kind))


func _on_spot_leave() -> void:
	var f := get_viewport().gui_get_focus_owner()
	for k in _spots:
		if _spots[k] == f:
			_say(_spot_hint(k))
			return
	_idle_hint()


func _on_shelf_hover(text: String) -> void:
	if text == "":
		_on_spot_leave()
	else:
		_say(text)


# ---------------------------------------------------------------- room actions

func _on_spot(kind: String) -> void:
	if not _room_active:
		return
	_last_spot = kind
	match kind:
		"stove":
			_open_panel("stir_pot")
		"counter":
			_open_panel("pack_jar")
		"book":
			_open_book()
		"cupboard":
			Audio.play_ui("ui_click")
			_say(tr("KITCHEN_CUPBOARD_HINT"), true)
		"pantry":
			_go("pantry")
		"garden":
			_go("garden" if Router.exists("garden") else "wild")
		"bed":
			_ask_bed()


func _go(target: String) -> void:
	if not Router.exists(target):
		Audio.play_ui("ui_error")
		_say(tr("KITCHEN_DOOR_LATER"), true)
		return
	Audio.play_sfx("sfx_door_open")
	if target != "pantry":
		Audio.set_indoor(false)
	_set_room_active(false)
	if ResourceLoader.exists(TRANSITION_GD):
		load(TRANSITION_GD).go(target)
	else:
		Router.goto(target)


func _open_book() -> void:
	if not ResourceLoader.exists(BOOK_GD):
		Audio.play_ui("ui_error")
		_say(tr("KITCHEN_BOOK_LATER"), true)
		return
	Audio.play_ui("ui_click")
	var book: Node = load(BOOK_GD).open()
	if book != null and not book.tree_exited.is_connected(_after_overlay):
		book.tree_exited.connect(_after_overlay, CONNECT_ONE_SHOT)


func _after_overlay() -> void:
	_refocus.call_deferred()


func _refocus() -> void:
	if is_inside_tree() and _room_active and _mg == null and _card == null:
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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _dialog.visible:
			_close_dialog()
		elif _panel.visible:
			_close_panel()


# ---------------------------------------------------------------- cook panel and mini-game

func _open_panel(station: String) -> void:
	Audio.play_ui("ui_click")
	_set_room_active(false)
	_blocker.visible = true
	_panel.open(station)


func _close_panel() -> void:
	if not _panel.visible:
		return
	_panel.visible = false
	_blocker.visible = false
	Audio.play_ui("ui_back")
	_set_room_active(true)
	_focus_spot()


func _on_cook_requested(recipe_id: String, main_v: String, second_v: String, addin_id: String) -> void:
	if _mg != null:
		return
	var d := GameState.data
	if not Kitchen.check(d, recipe_id, main_v, second_v, addin_id).ok:
		return
	_cooking = {"recipe": recipe_id, "main": main_v, "second": second_v, "addin": addin_id}
	var varieties: Array = [main_v]
	if second_v != "":
		varieties.append(second_v)
	var key := ProductGen.make_key(recipe_id, varieties, addin_id)
	var types: Array = []
	for v: String in varieties:
		types.append(State.type_of_variety(v))
	var ctx := {"seed": Seeds.seed_for(int(d.save_seed), "appearance", int(d.day), key), "recipe": recipe_id,
		"varieties": varieties, "addin": addin_id, "desc": ProductGen.describe(key, d.varieties), "ingredient_types": types}
	ctx.merge(debug_ctx, true)
	Audio.play_ui("ui_confirm")
	_panel.visible = false
	_blocker.visible = false
	_set_room_active(false)
	_set_world_visible(false)
	var method := String(Data.recipes()[recipe_id].method)
	var path := MINIGAME % [method, method]
	if not ResourceLoader.exists(path):
		_on_minigame_done.call_deferred({"stars": 2})
		return
	_mg = load(path).instantiate()
	_overlay.add_child(_mg)
	_mg.finished.connect(_on_minigame_done, CONNECT_ONE_SHOT)
	_mg.start(ctx)


## Hides the room, HUD and To-Do note while a mini-game runs (their controls would eat its clicks).
func _set_world_visible(on: bool) -> void:
	_room.visible = on
	_bar.visible = on
	if _hud != null:
		_hud.visible = on
	if _todo == null or not is_instance_valid(_todo):
		_todo = get_tree().get_first_node_in_group("granny_todo") as CanvasLayer
	if _todo != null:
		if not on:
			_todo_was_visible = _todo.visible
			_todo.visible = false
		elif _todo_was_visible:
			_todo.visible = true


func _on_minigame_done(result: Dictionary) -> void:
	if is_instance_valid(_mg):
		_mg.queue_free()
	_mg = null
	_set_world_visible(true)
	var stars := clampi(int(result.get("stars", 1)), 1, 3)
	var c := _cooking
	var res := Kitchen.cook(GameState.data, c.recipe, c.main, c.second, c.addin, stars)
	GameState.notify(PackedStringArray(["inbox", "pantry", "cupboard", "energy", "book", "stats"]))
	if not res.get("ok", false):
		_say(tr(String(res.get("reason", "KITCHEN_COOK_FAILED"))), true)
		_set_room_active(true)
		_focus_spot()
		return
	Save.save_game(GameState.data)
	var desc: Dictionary = res.desc.duplicate()
	desc["value"] = ProductGen.value(String(res.item.key), GameState.data.varieties, stars)
	if not ResourceLoader.exists(RESULT_CARD):
		_on_card_closed()
		return
	if not res.is_new:
		Audio.play_sfx("sfx_star_pop")
	_card = load(RESULT_CARD).instantiate()
	_overlay.add_child(_card)
	_card.show_result(desc, stars, bool(res.is_new))
	_card.closed.connect(_on_card_closed, CONNECT_ONE_SHOT)


func _on_card_closed() -> void:
	if is_instance_valid(_card):
		_card.queue_free()
	_card = null
	Audio.play_ui("ui_click")
	_set_room_active(true)
	_focus_spot()
	_say(tr("KITCHEN_JAR_INBOX"), true)


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
	_last_spot = "stove"
	_focus_spot()
	_idle_hint()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if _mg != null:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel"):
		if _dialog.visible:
			_close_dialog()
			get_viewport().set_input_as_handled()
		elif _panel.visible:
			_close_panel()
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


## Debug-only sample inventory when the scene runs alone.
func _debug_fill() -> void:
	var d := GameState.data
	for v in d.varieties:
		var t := State.type_of_variety(v)
		if Data.ingredients()[t].group != "nut" and v.ends_with("_1"):
			d.inbox.append(State.fresh(v, 5, int(Data.ingredients()[t].shelf_days)))
	d.inbox.append(State.nut("walnut", 3))
	d.cupboard["cinnamon"] = 1
