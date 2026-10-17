extends Control
## Seed Lab (GD-WILD, spec §10): type a seed, pick a biome, generate the day-1 map and pan over all of it.
## A number is used as the save seed as is; any other text is hashed. Empty = random.
## "Walk" opens the wild scene with that seed (it starts a test game when none is running).
## Uses the same renderer as the wild scene, with clearings and the special place outlined.
## P1-SEEDLAB: "Watch it grow" (G) replays the generation step by step over the whole map (GrowView); tap, E or Enter
## jumps to the next step, Esc or the button skips to the end. "A | B" (C) puts the seed next to the previous one
## (same rules, different seed). Maps are generated with record_steps, so the replay works in release builds too.

const BIOMES := ["forest", "vineyard", "creek"]  ## the lab shows every biome, locked or not
const PAN_SPEED := 240.0
const DAY := 1
const LABEL_H := 18  ## step banner row above the overview (the banner overlaps the frame's top edge)
const FRAME_PX := 5  ## width of the paper frame around the map (UI kit 9-slice margin)
const FONT := preload("res://assets/fonts/m6x11plus.ttf")
const BG_TEX := preload("res://assets/sprites/scenes/bg_title.png")
const PANEL_PAPER := preload("res://assets/sprites/ui/ui_panel_paper.png")
const PANEL_CARD := preload("res://assets/sprites/ui/ui_panel_card.png")
const DITHER_DARK := Color("23282a")  ## palette colour of the dither overlay
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]  ## 4x4 ordered-dither matrix
const CAPTION_H := 18  ## seed caption under each A | B map (one map: the caption goes to the info bar)
const GAP := 8  ## between the A and B maps

var save_seed := 0
var seed_b := -1  ## the previously generated seed, B of the comparison (-1: none yet, B = seed + 1)
var map: Dictionary = {}
var map_b: Dictionary = {}
var _vars: Dictionary = {}
var _vars_b: Dictionary = {}
var _info := ""  ## map stats line of the info bar
var _pan := Vector2.ZERO
var _dragging := false
var _overview := false
var _playing := false
var _grow_t := 0.0
var _phase := -1
var _built_a := ""  ## "<seed>|<ts>" the GrowViews were last set up for
var _built_b := ""
var _box: Control
var _grow_a: GrowView
var _grow_b: GrowView
var _cap_a: Label
var _cap_b: Label
var _step_panel: PanelContainer
var _step_label: Label
var _frame: Panel

@onready var seed_edit: LineEdit = %SeedEdit
@onready var biome_pick: OptionButton = %Biome
@onready var area: Control = %MapArea
@onready var view: WildMapView = %Map
@onready var info: Label = %Info
@onready var hint: Label = %Hint
@onready var grow_btn: Button = %Grow
@onready var compare_btn: Button = %Compare


func _ready() -> void:
	for b in BIOMES:
		biome_pick.add_item(tr("WILD_BIOME_" + String(b).to_upper()))
	biome_pick.visible = BIOMES.size() > 1  # one biome so far: no choice to offer, more room for the buttons
	# slimmer bars (3 px instead of 6 above and below) so the whole-map overview gets 6 px tiles
	for bar: PanelContainer in [$Layout/Top, $Layout/Bottom]:
		var sb := bar.get_theme_stylebox("panel").duplicate() as StyleBox
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		bar.add_theme_stylebox_override("panel", sb)
	_style_title()
	%Bg.texture = dithered_bg()
	_build_overview()
	_build_frame()
	%Generate.pressed.connect(_generate)
	biome_pick.item_selected.connect(func(_i: int) -> void: _generate())
	%Random.pressed.connect(_random)
	%Walk.pressed.connect(_walk)
	%Back.pressed.connect(func() -> void: Router.goto("title"))
	grow_btn.pressed.connect(_grow_pressed)
	compare_btn.toggled.connect(_compare_toggled)
	seed_edit.text_submitted.connect(func(_t: String) -> void: _generate())
	area.resized.connect(_on_area_resized)
	view.show_marks = true
	if Router.params.has("seed"):
		seed_edit.text = str(int(Router.params.seed))
	_generate()
	Audio.play_music("mus_seedlab")


## The painted title scene, darkened by an ordered dither of one palette colour (no alpha, whole pixels).
static func dithered_bg() -> ImageTexture:
	var img := BG_TEX.get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			if BAYER[(y & 3) * 4 + (x & 3)] < 11:  # 11 of 16 pixels covered
				img.set_pixel(x, y, DITHER_DARK)
	return ImageTexture.create_from_image(img)


func _style_title() -> void:
	var t: Label = %Title
	t.add_theme_font_override("font", FONT)
	t.add_theme_font_size_override("font_size", 36)
	t.add_theme_color_override("font_color", Color("e5bd7f"))
	t.add_theme_color_override("font_shadow_color", Color("3d1f29"))
	t.add_theme_constant_override("shadow_offset_x", 2)
	t.add_theme_constant_override("shadow_offset_y", 2)
	t.add_theme_constant_override("line_spacing", 0)
	t.custom_minimum_size = Vector2(0, 26)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.text = tr("TITLE_SEED_LAB")
	$Layout/TitleRow.add_theme_constant_override("separation", 4)
	var pad := Control.new()  # left margin
	pad.custom_minimum_size = Vector2(6, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Layout/TitleRow.add_child(pad)
	$Layout/TitleRow.move_child(pad, 0)


## Wooden/paper UI-kit frame (border only) around the map, on top of it; follows the overview rect or the pan area.
func _build_frame() -> void:
	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxTexture.new()
	sb.texture = PANEL_PAPER
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_texture_margin(side, FRAME_PX)
	sb.draw_center = false
	_frame.add_theme_stylebox_override("panel", sb)
	area.add_child(_frame)
	area.move_child(_frame, 1)  # above the pan view, under the overview box
	_frame.size = area.size


func _place_frame(r: Rect2i) -> void:
	if _frame == null:
		return
	_frame.position = Vector2(r.position - Vector2i(FRAME_PX, FRAME_PX))
	_frame.size = Vector2(r.size + Vector2i(FRAME_PX * 2, FRAME_PX * 2))


func _build_overview() -> void:
	_box = Control.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false
	area.add_child(_box)
	_grow_a = GrowView.new()
	_grow_b = GrowView.new()
	_cap_a = _caption_label()
	_cap_b = _caption_label()
	for n in [_grow_a, _grow_b, _cap_a, _cap_b]:
		_box.add_child(n)
	_step_panel = PanelContainer.new()
	_step_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxTexture.new()  # gold-trimmed card banner
	sb.texture = PANEL_CARD
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_texture_margin(side, 5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_step_panel.add_theme_stylebox_override("panel", sb)
	_step_label = Label.new()
	_step_label.add_theme_color_override("font_color", Color("50361e"))
	_step_panel.add_child(_step_label)
	_box.add_child(_step_panel)


func _caption_label() -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	if _playing:
		_grow_t += delta
		if _grow_t >= GrowView.total():
			_finish_grow()
		else:
			_apply_time()
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if v != Vector2.ZERO:
		if _overview:
			if compare_btn.button_pressed:
				return
			_set_overview(false)
		_pan += v * PAN_SPEED * delta
		_apply_pan()


## Mouse arrives as emulated touch (project: emulate_touch_from_mouse), so drag works the same on phones.
## A press that no button took starts the drag; the drag itself is read here, before the GUI, because
## drag events are routed by their own position, which can land on the bars.
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventScreenDrag:
		_pan -= event.relative
		_apply_pan()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not event.pressed:
		_dragging = false


## A tap during the replay jumps to the next step; on the finished single overview it goes back to panning.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch and event.pressed):
		return
	get_viewport().gui_release_focus()
	if _playing:
		_next_step()
		get_viewport().set_input_as_handled()
		return
	if _overview:
		if compare_btn.button_pressed:
			return
		_set_overview(false)
	_dragging = true


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).physical_keycode if event is InputEventKey else KEY_NONE
	if _playing and (event.is_action("interact") or event.is_action("ui_accept")):
		_next_step()
	elif _playing and (event.is_action("cancel") or event.is_action("ui_cancel")):
		_finish_grow()
	elif key == KEY_G:
		_grow_pressed()
	elif key == KEY_C:
		compare_btn.button_pressed = not compare_btn.button_pressed
	else:
		return
	get_viewport().set_input_as_handled()


static func seed_from_text(text: String) -> int:
	var t := text.strip_edges()
	if t.is_empty():
		return Seeds.random_save_seed()
	if t.is_valid_int():
		return absi(t.to_int()) & 0x7FFFFFFF
	return Hash.fnv1a31(t)


func biome() -> String:
	return String(BIOMES[maxi(biome_pick.selected, 0)])


func _generate() -> void:
	var s := seed_from_text(seed_edit.text)
	if not map.is_empty():
		seed_b = save_seed  # the same seed again makes an identical twin in A | B (generation is deterministic)
	save_seed = s
	seed_edit.text = str(save_seed)
	_vars = VarietyGen.generate_all(save_seed, 0)
	VarietyGen.ensure_types(_vars, save_seed)  # P1 types, exactly as a real save gets them
	map = WildGen.generate(save_seed, DAY, biome(), "sunny", _vars, true)
	view.show_map(map, _vars)
	_pan = Vector2.ZERO
	_apply_pan()
	_built_a = ""
	_stop_grow()
	if compare_btn.button_pressed:
		_ensure_b()
	_set_overview(compare_btn.button_pressed)
	_info = ""
	if map.is_empty():
		info.text = ""
		return
	var bushes := 0
	for p in map.pickups:
		if String(p.get("kind", "")) == "bush":
			bushes += 1
	# the seed is in the field above; a special place replaces the ground count so the line fits the bar
	var text := tr("WILD_LAB_STATS") % [map.fruit_trees.size(), bushes, map.pickups.size() - bushes]
	var sp: Dictionary = map.get("special", {})
	if not sp.is_empty():
		text = tr("WILD_LAB_STATS_SPECIAL") % [map.fruit_trees.size(), bushes, tr("WILD_SPECIAL_" + String(sp.get("kind", "")).to_upper())]
	_info = text
	_update_labels()


func _random() -> void:
	seed_edit.text = str(Seeds.random_save_seed())
	_generate()


func _walk() -> void:
	Router.goto("wild", {"biome": biome(), "seed": save_seed})


## Integer pan, clamped to the map; a map smaller than the area is centred.
func _apply_pan() -> void:
	var view_size := area.size
	var map_size := Vector2(view.size_px())
	var lim := (map_size - view_size).max(Vector2.ZERO)
	_pan = _pan.clamp(Vector2.ZERO, lim)
	var centre := ((view_size - map_size) * 0.5).max(Vector2.ZERO).floor()
	view.position = (centre - _pan).round()
	if not _overview:
		_place_frame(Rect2i(FRAME_PX, FRAME_PX, int(view_size.x) - FRAME_PX * 2, int(view_size.y) - FRAME_PX * 2))


func _on_area_resized() -> void:
	_apply_pan()
	_layout_overview()


# ---------- step-by-step replay and A | B (P1-SEEDLAB) ----------

func b_seed() -> int:
	return seed_b if seed_b >= 0 else (save_seed + 1) & 0x7FFFFFFF


func _ensure_b() -> void:
	var s := b_seed()
	if not map_b.is_empty() and int(map_b.get("save_seed", -1)) == s:
		return
	_vars_b = VarietyGen.generate_all(s, 0)
	VarietyGen.ensure_types(_vars_b, s)
	map_b = WildGen.generate(s, DAY, biome(), "sunny", _vars_b, true)
	map_b["save_seed"] = s
	_built_b = ""


func _grow_pressed() -> void:
	if _playing:
		_finish_grow()
		return
	get_viewport().gui_release_focus()
	_set_overview(true)
	_playing = true
	_grow_t = 0.0
	_phase = -1
	grow_btn.text = tr("WILD_LAB_SKIP")
	_apply_time()
	_update_hint()


func _compare_toggled(on: bool) -> void:
	if on:
		_ensure_b()
		_set_overview(true)
	elif not _playing:
		_set_overview(false)
	else:
		_layout_overview()


## Jumps to the start of the next step (or the end).
func _next_step() -> void:
	var p := GrowView.phase_at(_grow_t)
	_grow_t = GrowView.start(p + 1)
	if _grow_t >= GrowView.total():
		_finish_grow()
	else:
		_apply_time()


func _finish_grow() -> void:
	_playing = false
	_grow_t = GrowView.total()
	grow_btn.text = tr("WILD_LAB_GROW")
	_apply_time()
	_update_hint()


func _stop_grow() -> void:
	_playing = false
	_grow_t = GrowView.total()
	_phase = -1
	grow_btn.text = tr("WILD_LAB_GROW")


## Holds the replay at `at` seconds (smoke shots and tests): the overview shows that moment and stays there.
func seek_grow(at: float) -> void:
	_set_overview(true)
	_playing = false
	_grow_t = clampf(at, 0.0, GrowView.total())
	_apply_time()


func _set_overview(on: bool) -> void:
	_overview = on
	view.visible = not on
	_box.visible = on
	if not on:
		_apply_pan()
	if on:
		_layout_overview()
		_apply_time()
	_update_labels()
	_update_hint()


## Whole map(s) at the largest whole tile size that fits under the step label; A | B side by side.
func _layout_overview() -> void:
	if _box == null or not _overview or map.is_empty():
		return
	var two := compare_btn.button_pressed and not map_b.is_empty()
	var aw := int(area.size.x)
	var ah := int(area.size.y)
	var mw := int(map.w)
	var mh := int(map.h)
	var avail_h := ah - LABEL_H - (CAPTION_H if two else 0)
	var fit_w := floori((aw - GAP) / 2.0 / mw) if two else floori(float(aw) / mw)
	var ts := clampi(mini(fit_w, floori(float(avail_h) / mh)), 2, 16)
	var pw := mw * ts
	var ph := mh * ts
	var total_w := pw * 2 + GAP if two else pw
	var x0 := floori((aw - total_w) * 0.5)
	var y0 := LABEL_H + maxi(floori((avail_h - ph) * 0.5), 0)
	var key_a := "%d|%d" % [save_seed, ts]
	if key_a != _built_a:
		_grow_a.setup(map, _vars, ts)
		_built_a = key_a
	_place_frame(Rect2i(x0, y0, total_w, ph))
	_place(_grow_a, _cap_a, Vector2i(x0, y0), Vector2i(pw, ph))
	_grow_b.visible = two
	_cap_a.visible = two
	_cap_b.visible = two
	if two:
		var key_b := "%d|%d" % [b_seed(), ts]
		if key_b != _built_b:
			_grow_b.setup(map_b, _vars_b, ts)
			_built_b = key_b
		_place(_grow_b, _cap_b, Vector2i(x0 + pw + GAP, y0), Vector2i(pw, ph))
	_update_labels()


func _place(g: GrowView, cap: Label, at: Vector2i, size_px: Vector2i) -> void:
	g.position = Vector2(at)
	cap.position = Vector2(at.x, at.y + size_px.y + FRAME_PX + 1)
	cap.size = Vector2(size_px.x, CAPTION_H)


func _apply_time() -> void:
	if not _overview:
		return
	_grow_a.set_time(_grow_t)
	if _grow_b.visible:
		_grow_b.set_time(_grow_t)
	var p := GrowView.phase_at(_grow_t)
	if p != _phase:
		_phase = p
		if _playing and p < GrowView.PHASES.size():
			Audio.play_sfx("sfx_star_pop")
	_update_labels()


func _update_labels() -> void:
	if not _overview:
		info.text = _info
		return
	var n := GrowView.PHASES.size()
	var p := GrowView.phase_at(_grow_t)
	var two := _grow_b.visible
	if p < n:
		_step_label.text = (tr("WILD_STEP_COUNT") % [p + 1, n]) + "  " + tr(String(GrowView.STEP_KEYS[p]))
	elif two:
		_step_label.text = tr("WILD_LAB_SAME_SEED") if b_seed() == save_seed else tr("WILD_LAB_SAME_RULES")
	else:
		_step_label.text = tr("WILD_STEP_DONE")
	_step_panel.reset_size()
	# a 2-px drop when a step starts (whole pixels only)
	var age := _grow_t - GrowView.start(p)
	var hop := 2 if _playing and age < 0.06 else (1 if _playing and age < 0.12 else 0)
	_step_panel.position = Vector2(floori((area.size.x - _step_panel.size.x) * 0.5), maxi(floori((LABEL_H - _step_panel.size.y) * 0.5), 0) + hop)
	var note_a := _grow_a.note(p)
	var note_b := _grow_b.note(p)
	if two:
		_cap_a.text = _with_note(tr("WILD_LAB_CAPTION_A") % save_seed, note_a)
		_cap_b.text = _with_note(tr("WILD_LAB_CAPTION_B") % b_seed(), note_b)
		info.text = ""  # both seeds are under their maps
	else:
		info.text = _with_note(tr("WILD_LAB_CAPTION") % save_seed, note_a)


static func _with_note(text: String, note: String) -> String:
	return text if note == "" else text + "   " + note


func _update_hint() -> void:
	if _playing:
		hint.text = tr("WILD_LAB_GROW_HINT")
	elif _overview and compare_btn.button_pressed:
		hint.text = tr("WILD_LAB_COMPARE_HINT")
	else:
		hint.text = tr("WILD_LAB_PAN")
