extends Control
## GD-KITCHEN · Kitchen (spec §5, §7.2, §11; tech-spec §7-8): one 480x270 click scene.
## Stove = stir_pot recipes, jar counter = pack_jar recipes, P1 fruit press = press recipes and dough board = knead
## recipes (shown once Economy.unlocked "press" / "knead"), cupboard counts, recipe book, waiting jars on the
## window sill, doors to the garden and the pantry, the bed nook (Night). Cooking: CookPanel picks -> the
## recipe's mini-game -> Kitchen.cook_n (x2 with the big pot) -> result card; a Mastered variant may skip the
## mini-game (Batch cook -> Kitchen.batch_cook). Mastering plays jgl_level. Rules stay in res://sim; this scene
## shows and routes.
## KITCHEN-P1C: the grandkids' reply drawings hang on the wall left of the window (WallDrawings, click to see one
## big); on days 90-99 (Farewell hint days) Granny nods off in a rocking chair after DOZE_AFTER idle seconds and any
## input wakes her (Doze; looks only, nothing in the save changes).
## Run alone it starts a throwaway game (GameState.start_temp, never saved) with a debug inventory.

const HUD := "res://ui/hud/hud.tscn"
const RESULT_CARD := "res://ui/result_card/result_card.tscn"
const ReactView := preload("res://scenes/market/react_view.gd")
const NIGHT_GD := "res://ui/transition/night.gd"
const BOOK_GD := "res://ui/book/book.gd"
const TRANSITION_GD := "res://ui/transition/transition.gd"
const TODO_GD := "res://ui/tutorial/granny_todo.gd"
const MINIGAME := "res://minigames/%s/%s.tscn"
const BACKGROUNDS := ["res://assets/sprites/backgrounds/bg_kitchen.png", "res://assets/sprites/scenes/bg_kitchen.png"]
## Granny at the painting's own pixel density (2 frames 44x88: idle, blink), standing on the floor between the
## stove and the bench's left end, feet at (94, 182); she blinks every BLINK_EVERY seconds.
const GRANNY_KITCHEN := "res://assets/sprites/granny/granny_kitchen.png"
const GRANNY_SIZE := Vector2(44, 88)
const GRANNY_AT := Vector2(72, 96)
const BLINK_EVERY := 3.4
const BLINK_SEC := 0.14
const PANEL_POS := Vector2(8, 30)
const STICKY_MS := 4000
## Granny's To-Do steps that happen at a kitchen object; steps elsewhere light the door that leads there.
const STEP_SPOT := {"d1_jam": "stove", "d1_bed": "bed", "d2_brine": "counter", "f_jam": "stove", "f_juice": "press"}
const NAV := [["move_left", SIDE_LEFT], ["move_right", SIDE_RIGHT], ["move_up", SIDE_TOP], ["move_down", SIDE_BOTTOM]]
const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const Hotspot := preload("res://scenes/kitchen/hotspot.gd")
const REVEAL_SEC := 2.5  ## every caption shows this long when Granny walks in
const CookPanel := preload("res://scenes/kitchen/cook_panel.gd")
const Shelf := preload("res://scenes/kitchen/waiting_shelf.gd")
const Wall := preload("res://scenes/kitchen/wall_drawings.gd")
const Doze := preload("res://scenes/kitchen/doze.gd")
const FormulaPanel := preload("res://scenes/kitchen/formula_panel.gd")  ## FORMULA-KITCHEN: the Invent panel
## Idle seconds before Granny dozes off on a hint day, and where her chair stands (by the stove, where she waits;
## rockers on the floor at y 186, same scale as her).
const DOZE_AFTER := 10.0
const DOZE_AT := Vector2(64, 102)

## QA hook: merged into every mini-game ctx (e.g. {"autoplay": true, "duration": 4.0} makes stir_pot play itself).
var debug_ctx: Dictionary = {}

var _spots: Dictionary = {}  # kind -> Hotspot
var _room: Control
var _shelf: Control
var _bar: PanelContainer
var _message: Label
var _blocker: Control
var _panel: Panel
var _fx_panel: Panel  ## FORMULA-KITCHEN: Invent panel (in place of the cook panel while it is open)
var _dialog: PanelContainer
var _sleep_btn: Button
var _overlay: CanvasLayer
var _hud: CanvasLayer
var _todo: CanvasLayer
var _todo_was_visible := false
var _mg: Node = null
var _card: Node = null
var _card_up := false  ## a result card was shown and has not given the room back yet (QA-FIX watchdog)
var _cooking: Dictionary = {}
var _after_card := "KITCHEN_JAR_INBOX"  ## message-bar key once the result card closes
var _last_spot := "stove"
var _sticky_until := 0
var _glow := ""
var _room_active := true
var _wall: Control
var _viewer: Control = null  ## a drawing seen big (WallDrawings.Viewer)
var _granny: TextureRect
var _doze: Control
var _idle := 0.0  ## seconds without any input (the doze clock)


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
	GuideArrow.attach(self, _guide_at)  # ONBOARD-GUIDE: arrow, Granny's hint, first-time key caps
	_focus_spot()
	_reveal_captions(true)  # touch players cannot hover: name every object for a moment on entry
	get_tree().create_timer(REVEAL_SEC).timeout.connect(func() -> void: _reveal_captions(false))


## Every hotspot caption on (entry, Tab held) or back to hover/focus/glow only.
func _reveal_captions(on: bool) -> void:
	if not is_inside_tree():
		return
	for k in _spots:
		_spots[k].reveal = on


# ---------------------------------------------------------------- build

func _setup_background() -> void:
	var bg := %Background as TextureRect
	if bg.texture == null:
		for p: String in BACKGROUNDS:
			if ResourceLoader.exists(p):
				bg.texture = load(p)
				break
	Art.painted = bg.texture != null
	if bg.texture == null:
		bg.texture = Art.background()


func _build_room() -> void:
	_room = Control.new()
	_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.size = Vector2(480, 270)
	add_child(_room)
	# Granny and her doze chair go in before the hotspots: captions, hover frames and the P1 press (it stands
	# nearer the viewer) draw over her, and clicks pass through her to the objects behind.
	if Art.painted and ResourceLoader.exists(GRANNY_KITCHEN):  # Granny by the stove, for life
		var g := TextureRect.new()
		var at := AtlasTexture.new()  # idle frame; the blink frame sits right of it
		at.atlas = load(GRANNY_KITCHEN)
		at.region = Rect2(Vector2.ZERO, GRANNY_SIZE)
		g.texture = at
		g.stretch_mode = TextureRect.STRETCH_KEEP
		g.position = GRANNY_AT
		g.size = GRANNY_SIZE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_room.add_child(g)
		_granny = g
		var blink := create_tween().set_loops()
		blink.tween_interval(BLINK_EVERY)
		blink.tween_callback(func() -> void: at.region.position.x = GRANNY_SIZE.x)
		blink.tween_interval(BLINK_SEC)
		blink.tween_callback(func() -> void: at.region.position.x = 0.0)
	_doze = Doze.new()
	_doze.position = DOZE_AT
	_doze.visible = false
	_room.add_child(_doze)
	var captions := {
		"garden": tr("KITCHEN_TO_GARDEN"), "stove": tr("KITCHEN_STOVE"), "counter": tr("KITCHEN_COUNTER"),
		"cupboard": tr("KITCHEN_CUPBOARD"), "pantry": tr("KITCHEN_TO_PANTRY"), "bed": tr("KITCHEN_BED_CAPTION"),
		"press": tr("KITCHEN_PRESS"), "board": tr("KITCHEN_BOARD"),
	}
	var rects: Dictionary = Art.OBJECTS.duplicate()
	rects.merge(Art.P1_OBJECTS)
	for kind: String in rects:
		var h: Button = Hotspot.new()
		_room.add_child(h)
		h.setup(kind, rects[kind], captions.get(kind, ""))
		h.pressed.connect(_on_spot.bind(kind))
		h.mouse_entered.connect(_on_spot_hover.bind(kind, true))
		h.focus_entered.connect(_on_spot_hover.bind(kind, false))
		h.mouse_exited.connect(_on_spot_leave)
		h.focus_exited.connect(_on_spot_leave)
		_spots[kind] = h
	_shelf = Shelf.new()
	_room.add_child(_shelf)
	_shelf.hovered.connect(_on_shelf_hover)
	_wall = Wall.new()
	_room.add_child(_wall)
	_wall.hovered.connect(_on_shelf_hover)
	_wall.open_requested.connect(func(letter: Dictionary) -> void: _open_drawing.call_deferred(letter))


func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.theme_type_variation = &"PaperPanel"
	_bar.position = Vector2(8, 240)
	_bar.custom_minimum_size = Vector2(464, 0)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_message = Label.new()
	_message.theme_type_variation = &"BodyPaper"  # UI-COMPACT: hints in the body font
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
	_panel.batch_requested.connect(_on_batch_requested)
	_panel.close_requested.connect(_close_panel)
	_panel.invent_requested.connect(_open_formula)
	_fx_panel = FormulaPanel.new()
	_fx_panel.visible = false
	_overlay.add_child(_fx_panel)
	_fx_panel.position = PANEL_POS
	_fx_panel.home = PANEL_POS
	_fx_panel.cook_requested.connect(_on_formula_cook)
	_fx_panel.close_requested.connect(_close_formula)


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
	for kind: String in Art.UNLOCK_OF:  # P1 stations appear once bought / given
		_spots[kind].visible = Economy.unlocked(d, String(Art.UNLOCK_OF[kind]))
	_shelf.show_items(_waiting(d))
	_wall.show_letters(d)
	if _panel.visible and _mg == null:
		_panel.refresh()
	if _fx_panel.visible and _mg == null:
		_fx_panel.refresh()
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


## ONBOARD-GUIDE: what Granny's guide asks the kitchen (GuideArrow header): the glowing object of the To-Do step
## (or the door towards it), Granny by the stove, the station under the mouse or the keyboard focus.
func _guide_at(what: String) -> Variant:
	if not _room_active or _mg != null:
		return null
	match what:
		"granny":
			return _granny.get_global_rect() if _granny != null else null
		"bubble":
			return null
		"near":
			for k in ["stove", "counter", "press", "board"]:
				var h: Control = _spots.get(k)
				if h != null and h.is_visible_in_tree() and (h.has_focus() or h.is_hovered()):
					return {"kind": "station", "at": _guide_top(h)}
			return {}
	return _guide_top(_spots[_glow]) if _spots.has(_glow) else null


## Just above a hotspot's glow frame, in the middle (above its caption when the caption sits over the object).
func _guide_top(h: Control) -> Vector2:
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
		"press":
			return tr("KITCHEN_PRESS_HINT")
		"board":
			return tr("KITCHEN_BOARD_HINT")
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
		"press":
			_open_panel("press")
		"board":
			_open_panel("knead")
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
	if _wall != null:
		_wall.set_active(on)


func _on_blocker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _dialog.visible:
			_close_dialog()
		elif _panel.visible:
			_close_panel()
		elif _fx_panel.visible:
			_close_formula()


# ---------------------------------------------------------------- cook panel and mini-game

func _open_panel(station: String) -> void:
	Audio.play_ui("ui_click")
	GuideArrow.used("station")
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
	if _mg != null or _card != null:
		return
	var d := GameState.data
	var mult: int = _panel.mult
	if not Kitchen.check_n(d, recipe_id, main_v, second_v, addin_id, mult).ok:
		return
	_cooking = {"recipe": recipe_id, "main": main_v, "second": second_v, "addin": addin_id, "mult": mult}
	var key := Kitchen.product_key(recipe_id, main_v, second_v, addin_id)
	var varieties: Array = ProductGen.parse_key(key).varieties  # bread has none, syrup the juice's fruit
	var types: Array = []
	for v: String in varieties:
		types.append(State.type_of_variety(v))
	var ctx := {"seed": Seeds.seed_for(int(d.save_seed), "appearance", int(d.day), key), "recipe": recipe_id,
		"varieties": varieties, "addin": addin_id, "desc": ProductGen.describe(key, d.varieties), "ingredient_types": types}
	_play_minigame(String(Data.recipes()[recipe_id].method), ctx)


## Starts `method`'s mini-game with `ctx` (+ debug_ctx) over the hidden room; its result comes to _on_minigame_done.
func _play_minigame(method: String, ctx: Dictionary) -> void:
	ctx.merge(debug_ctx, true)
	Audio.play_ui("ui_confirm")
	_panel.visible = false
	_fx_panel.visible = false
	_blocker.visible = false
	_set_room_active(false)
	_set_world_visible(false)
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
	if _cooking.is_empty():  # QA-FIX: a second result for the same cook; the first one already made the jar
		return
	if is_instance_valid(_mg):
		_mg.queue_free()
	_mg = null
	_set_world_visible(true)
	var stars := clampi(int(result.get("stars", 1)), 1, 3)
	var c := _cooking
	_cooking = {}
	var res := {}
	if c.has("formula"):
		res = Kitchen.cook_formula(GameState.data, c.method, c.components, c.addins, stars)
	else:
		res = Kitchen.cook_n(GameState.data, c.recipe, c.main, c.second, c.addin, stars, int(c.get("mult", 1)))
	_show_result(res)


# --- inventions (FORMULA-KITCHEN) ---

## The cook panel's Invent button: the Invent panel takes its place on the same station.
func _open_formula(station: String) -> void:
	Audio.play_ui("ui_click")
	_panel.visible = false
	_blocker.visible = true
	_fx_panel.open(station)


## Back from the Invent panel: the station's cook panel again.
func _close_formula() -> void:
	if not _fx_panel.visible:
		return
	_fx_panel.visible = false
	Audio.play_ui("ui_back")
	_panel.open(_panel.station)


func _on_formula_cook(method: String, components: Array, addins: Array) -> void:
	if _mg != null or _card != null:
		return
	var d := GameState.data
	var chk := Kitchen.check_formula(d, method, components, addins)
	if not chk.ok:
		return
	var key := String(chk.key)
	_cooking = {"formula": true, "method": method, "components": components.duplicate(), "addins": addins.duplicate()}
	var desc := ProductGen.describe(key, d.varieties)
	var types: Array = []
	for comp: Dictionary in FormulaGen.parse(key).components:
		if comp.kind != "product":
			types.append(State.type_of_variety(String(comp.id)) if comp.kind == "fresh" else String(comp.id))
	var ctx := {"seed": Seeds.seed_for(int(d.save_seed), "appearance", int(d.day), key),
		"recipe": "bread" if String(desc.vessel) == "bread" else FormulaGen.RECIPE, "varieties": ProductGen.parse_key(key).varieties,
		"addin": String(addins[0]) if not addins.is_empty() else "", "desc": desc, "ingredient_types": types}
	_play_minigame(method, ctx)


## Batch cook (a Mastered variant): no mini-game, straight to the result card.
func _on_batch_requested(recipe_id: String, main_v: String, second_v: String, addin_id: String) -> void:
	if _mg != null or _card != null:
		return
	var res := Kitchen.batch_cook(GameState.data, recipe_id, main_v, second_v, addin_id, _panel.mult)
	if not res.get("ok", false):  # the panel stays open and says why
		Audio.play_ui("ui_error")
		_panel.refresh()
		return
	Audio.play_ui("ui_confirm")
	_panel.visible = false
	_blocker.visible = false
	_set_room_active(false)
	_show_result(res)


## Applies a cook result to the view: save, result card (Mastered banner + jgl_level when it was the third good cook).
func _show_result(res: Dictionary) -> void:
	GameState.notify(PackedStringArray(["inbox", "pantry", "cupboard", "energy", "book", "stats"]))
	if not res.get("ok", false):
		_say(tr(String(res.get("reason", "KITCHEN_COOK_FAILED"))), true)
		_set_room_active(true)
		_focus_spot()
		return
	Save.save_game(GameState.data)
	var stars := int(res.quality)
	var mastered := bool(res.get("mastered", false))
	_after_card = "UI_MASTERY_NEW" if mastered else ("UI_BATCH_TWO_JARS" if res.items.size() > 1 else "KITCHEN_JAR_INBOX")
	var desc: Dictionary = res.desc.duplicate()
	desc["value"] = ProductGen.value(String(res.item.key), GameState.data.varieties, stars)
	if mastered:
		Audio.play_jingle("jgl_level")
	if not ResourceLoader.exists(RESULT_CARD):
		_finish_card()
		return
	_drop_card()  # QA-FIX: never two cards; an older one would sit under this one with nobody listening
	var card: ResultCard = load(RESULT_CARD).instantiate()
	_card = card
	_card_up = true
	card.closed.connect(_on_card_closed.bind(card), CONNECT_ONE_SHOT)
	_overlay.add_child(card)
	# the card's "New recipe!" line announces mastery instead (set before the play-in lays the card out), and a first
	# invention "New creation!" (FORMULA-KITCHEN)
	var banner := tr("UI_MASTERY_BANNER") if mastered else ""
	if res.get("formula", false) and bool(res.is_new):
		banner = tr("UI_FORMULA_NEW")
	card.show_result(desc, stars, bool(res.is_new), banner)
	if bool(res.is_new) or bool(res.get("formula", false)):
		_granny_line(card, res)


## FUN-REACT · Granny's one short line about a new jar or an invention, under the result card's paper.
func _granny_line(card: Control, res: Dictionary) -> void:
	var d := GameState.data
	var key := String(res.item.key)
	var desc := Reactions.describe(key, d.varieties, int(res.quality))
	var seed_value := Reactions.seed_for(int(d.save_seed), int(d.day), key, "granny")
	var line := Reactions.line(desc, "granny", "", seed_value, {"max": int(Reactions.table().get("granny_max_chars", 44))})
	var panel: Control = null
	for c in card.get_children():
		if c is PanelContainer:
			panel = c
	if line == "" or panel == null:
		return
	var gl := ReactView.GrannyLine.new()
	gl.name = "GrannyLine"
	card.add_child(gl)
	gl.setup(panel, tr("REACT_GRANNY_SAYS") % line)
	_say("", true)  # the hint bar under it stays quiet while she talks; closing the card says what is next


## Continue on `card`. A stale card (one that was replaced) just goes; the current one gives the room back.
func _on_card_closed(card: Variant = null) -> void:
	if card == null:
		card = _card
	if is_instance_valid(card):
		(card as Node).queue_free()
	if is_instance_valid(_card) and card != _card:
		return
	_finish_card()


func _drop_card() -> void:
	if is_instance_valid(_card):
		_card.queue_free()
	_card = null
	_card_up = false


## The card is gone: the room, its focus and the message bar come back.
func _finish_card() -> void:
	_card = null
	_card_up = false
	Audio.play_ui("ui_click")
	_set_room_active(true)
	_focus_spot()
	_say(tr(_after_card), true)


# ---------------------------------------------------------------- drawings and the doze (KITCHEN-P1C)

## Shows one wall drawing big over the room; closing it gives the room back.
func _open_drawing(letter: Dictionary) -> void:
	if _viewer != null or not _room_active or _mg != null or _card != null:
		return
	Audio.play_sfx("sfx_page_turn")
	_set_room_active(false)
	var v: Control = Wall.Viewer.new()
	v.setup(Wall.drawing(GameState.data, letter), Letters.kid_name(String(letter.from)))
	_overlay.add_child(v)
	v.closed.connect(_close_drawing)
	_viewer = v


func _close_drawing() -> void:
	_viewer = null
	Audio.play_ui("ui_back")
	_set_room_active(true)
	var f: Button = _wall.newest()
	if f != null:
		f.grab_focus()


## True while Granny may nod off: a Farewell hint day, the room free (no panel, dialog, mini-game, card or drawing).
func _can_doze() -> bool:
	var d := GameState.data
	return not d.is_empty() and Farewell.is_hint_day(int(d.get("day", 1))) and _room_active and _mg == null \
		and _card == null and _viewer == null


func _process(delta: float) -> void:
	if _card_up and not (is_instance_valid(_card) and (_card as CanvasItem).visible):
		_finish_card()  # QA-FIX: a card that closed or went without telling the kitchen never keeps the room locked
	if _doze == null:
		return
	if not _can_doze():
		_idle = 0.0
		if _doze.visible:
			_set_dozing(false)
		return
	_idle += delta
	if _idle >= DOZE_AFTER and not _doze.visible:
		_set_dozing(true)


## Granny in her chair with closed eyes and a "z" bubble, or back at the stove. Looks only.
func _set_dozing(on: bool) -> void:
	_doze.visible = on
	if on:
		_doze.restart()
	if _granny != null:
		_granny.visible = not on


## Any input wakes her and restarts the idle clock (the event itself goes on as usual).
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) < 0.3:
		return
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_TAB and not event.is_echo():
		_reveal_captions(event.is_pressed())
	_idle = 0.0
	if _doze != null and _doze.visible:
		_set_dozing(false)


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
	DevTools.unlock_p1(d)  # press and dough board on show, bottles, flour and cabbage
