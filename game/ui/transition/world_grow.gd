class_name WorldGrow
extends CanvasLayer
## FIRST-60 · "The world grows from your seed". The first time a wild opens each day (always on the first visit of a
## save, after that while Settings > Show the forest grow is on), the map's generation replays over the whole screen
## with GrowView, sped up to about 3 s (noise -> stream -> trees -> paths -> pickups), under "Today's forest, grown
## from seed N"; then the overlay dithers away into the real map. Any key, click or tap skips to the fade.
## Wild hook: `WorldGrow.open_if_due(self, map, biome)` once the map is drawn. Router.params "grow" (bool) forces it on
## or off (demo timelines); demo runs (--demo) and wild scenes not opened through the Router (smoke scripts) skip it.
## The day it last played is kept in the save as flags.wild_grow_day (old saves: missing = never played).

signal done

const LAYER := 20  ## over the HUD (10), under scene transitions (90)
const PLAY_SEC := 3.0
const HOLD_SEC := 0.45
const FADE_SEC := 0.45
const BG := Color("23282a")
const CAPTION := Color("f2d9c5")
const STEP := Color("e5bd7f")
const FLAG := "wild_grow_day"
const CAPTION_KEYS := {"forest": "WORLD_GROW_FOREST", "vineyard": "WORLD_GROW_VINEYARD", "creek": "WORLD_GROW_CREEK"}
const MASK := preload("res://ui/transition/dither_mask.gdshader")
const PAPER := preload("res://assets/sprites/ui/ui_panel_paper.png")  ## the Seed Lab's frame around the map
const FRAME_PX := 5

var _t := 0.0
var _view: GrowView
var _root: Control
var _caption: Label
var _step: Label
var _mat := ShaderMaterial.new()
var _finished := false


## Whether the overlay plays for `state` today: always when it never played on this save, else once a day while
## the setting is on.
static func is_due(state: Dictionary, setting_on: bool) -> bool:
	var flags: Variant = state.get("flags")
	if typeof(flags) != TYPE_DICTIONARY or not (flags as Dictionary).has(FLAG):
		return true
	return setting_on and int(flags[FLAG]) != int(state.get("day", 1))


static func mark(state: Dictionary) -> void:
	if typeof(state.get("flags")) != TYPE_DICTIONARY:
		state["flags"] = {}
	state.flags[FLAG] = int(state.get("day", 1))


## Seconds from the start until the map is fully back.
static func duration() -> float:
	return PLAY_SEC + HOLD_SEC + FADE_SEC


## GrowView time at overlay time `t`: noise..pickups squeezed into PLAY_SEC, then held (the flood check is left out).
static func view_time(t: float) -> float:
	return clampf(t / PLAY_SEC, 0.0, 1.0) * GrowView.start(GrowView.PHASES.size() - 1)


## Dither level of the overlay at `t`: whole until the fade, then gone over FADE_SEC.
static func level_at(t: float) -> int:
	var f := t - PLAY_SEC - HOLD_SEC
	return 16 if f <= 0.0 else clampi(16 - int(16.0 * f / FADE_SEC), 0, 16)


## Tile size that fits a w x h map (and its paper frame) on a screen of `screen` px with a caption row above and a
## step row below.
static func tile_px(w: int, h: int, screen: Vector2i) -> int:
	if w <= 0 or h <= 0:
		return 2
	return clampi(mini(floori((screen.x - 40) / float(w)), floori((screen.y - 58) / float(h))), 2, 10)


## The wild's hook: adds the overlay to `host` and returns it when it is due, else null.
static func open_if_due(host: Node, map: Dictionary, biome: String) -> WorldGrow:
	var tree := host.get_tree()
	var router: Node = tree.root.get_node_or_null("Router") if tree != null else null
	var gs: Node = tree.root.get_node_or_null("GameState") if tree != null else null
	if router == null or gs == null or map.is_empty() or typeof(gs.get("data")) != TYPE_DICTIONARY:
		return null
	var state: Dictionary = gs.get("data")
	var forced: Variant = (router.get("params") as Dictionary).get("grow")
	if typeof(forced) == TYPE_BOOL:
		if not forced:
			return null
	elif String(router.get("current")) != "wild" or OS.get_cmdline_user_args().has("--demo"):
		return null
	elif not is_due(state, GameSettings.show_grow()):
		return null
	mark(state)
	var g := WorldGrow.new()
	g.setup(map, state, biome)
	host.add_child(g)
	return g


## Builds the overlay for `map` (generated again with its steps when the map has none, as in release builds).
func setup(map: Dictionary, state: Dictionary, biome: String) -> void:
	layer = LAYER
	var m := map
	if typeof(map.get("steps")) != TYPE_DICTIONARY or (map.get("steps") as Dictionary).is_empty():
		m = WildGen.generate(int(state.get("save_seed", 0)), int(state.get("day", 1)), biome,
			String(state.get("weather", "sunny")), state.get("varieties", {}), true)
	var screen := Vector2i(480, 270)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		screen = Vector2i(tree.root.get_visible_rect().size)
	_mat.shader = MASK
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.material = _mat
	_root.draw.connect(func() -> void: _root.draw_rect(Rect2(Vector2.ZERO, _root.size), BG))
	add_child(_root)
	_view = GrowView.new()
	var w := int(m.get("w", 0))
	var h := int(m.get("h", 0))
	var ts := tile_px(w, h, screen)
	_view.setup(m, state.get("varieties", {}), ts)
	var frame_y := floori((screen.y - h * ts - FRAME_PX * 2) / 2.0)
	_view.position = Vector2(floori((screen.x - w * ts) / 2.0), frame_y + FRAME_PX)
	var frame := NinePatchRect.new()
	frame.texture = PAPER
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		frame.set_patch_margin(side, FRAME_PX)
	frame.position = _view.position - Vector2(FRAME_PX, FRAME_PX)
	frame.size = Vector2(w * ts + FRAME_PX * 2, h * ts + FRAME_PX * 2)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_adopt(frame)
	_adopt(_view)
	_caption = _label(CAPTION)
	_caption.text = tr(String(CAPTION_KEYS.get(biome, "WORLD_GROW_FOREST"))) % int(m.get("seed", 0))
	_caption.offset_top = frame_y - 22
	_caption.offset_bottom = frame_y - 4
	_step = _label(STEP)
	_step.offset_top = frame_y + h * ts + FRAME_PX * 2 + 4
	_step.offset_bottom = _step.offset_top + 18
	_apply()


func _label(color: Color) -> Label:
	var l := Label.new()
	l.anchor_right = 1.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # set already translated
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_adopt(l)
	return l


func _adopt(n: CanvasItem) -> void:
	n.use_parent_material = true
	_root.add_child(n)


func _process(delta: float) -> void:
	_t += delta
	_apply()
	if _t >= duration() and not _finished:
		_finished = true
		done.emit()
		queue_free()


## Overlay time in seconds (smoke shots).
func seek(t: float) -> void:
	_t = t
	_apply()


## Jumps to the finished map and its fade.
func skip() -> void:
	_t = maxf(_t, PLAY_SEC + HOLD_SEC)
	_apply()


func _apply() -> void:
	if _view == null:
		return
	var vt := view_time(_t)
	_view.set_time(vt)
	var phase := mini(GrowView.phase_at(vt), GrowView.PHASES.size() - 2)
	_step.text = tr(String(GrowView.STEP_KEYS[phase]))
	_mat.set_shader_parameter("level", level_at(_t))


func _input(event: InputEvent) -> void:
	if _finished or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch \
			or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		skip()
