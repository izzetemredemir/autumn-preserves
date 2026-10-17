extends Panel
## FORMULA-KITCHEN · Invent panel (opened by the cook panel's Invent button): method tabs (unlocked stations only),
## 4 component slots and 2 add-in slots filled by clicking the grid of what Granny has (fresh stacks, nuts and
## finished products from the inbox and pantry, add-ins from the cupboard), and a live preview of the invention:
## jar, name, taste bars, notes, harmony stars, value range and "New!" while it was never made. Cook -> the method's
## mini-game (the kitchen routes it). Rules stay in Kitchen.check_formula / FormulaGen; this panel only holds picks.
## Click a filled slot (or the picked cell again) to take it out. Keyboard: arrows move focus, Enter picks, Esc closes.

signal cook_requested(method: String, components: Array, addins: Array)
signal close_requested

const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const CookPanel := preload("res://scenes/kitchen/cook_panel.gd")
const FONT := preload("res://assets/fonts/m6x11plus.ttf")
const FS := 18
const W := 464
const H := 236
const TAB_X := 80
const TAB_W := 72
const SLOT_W := 130
const SLOT_H := 24
const RIGHT_X := 280
const CELL := Vector2(43, 22)
const COLS := 4
const GRID_H := 116
const METHOD_KEYS := {"stir_pot": "UI_FORMULA_M_STIR_POT", "pack_jar": "UI_FORMULA_M_PACK_JAR", "press": "UI_FORMULA_M_PRESS",
	"knead": "UI_FORMULA_M_KNEAD"}

var method := ""
## Picked component ids (variety id, nut type or product key) and add-in ids, in pick order.
var components: Array = []
var addins: Array = []
var home := Vector2(8, 30)

var _built := false
var _title: Label
var _back: Button
var _tabs: Dictionary = {}  # method -> Button
var _slots: Array = []  # {"button", "icon", "name", "addin": bool}
var _scroll: ScrollContainer
var _grid: GridContainer
var _cells: Dictionary = {}  # entry id -> Button
var _entries: Dictionary = {}  # entry id -> entry
var _hover: Label
var _jar: JarIcon
var _unknown: Label
var _name: Label
var _notes: Label
var _new_tag: Label
var _chart: Bars
var _stars: ResultCard.StarRow
var _value: Label
var _profile: Label
var _feedback: Label
var _cook: Button
var _ok := false
var _key := ""
var _icons := {}  # product key -> icon texture
var _tween: Tween


func _ready() -> void:
	_build()


# ---------------------------------------------------------------- pure helpers (state in, plain data out)

## Everything Granny could mix in, grid order: fresh stacks (ingredient order, then id), nuts, matured products
## (by key), then cupboard add-ins (add-in order). [{"id", "kind": "fresh"|"nut"|"product"|"addin", "count",
## "usable": enough for one use}]
static func owned(d: Dictionary) -> Array:
	var fresh := {}
	var nuts := {}
	var products := {}
	for item: Dictionary in CookPanel._all_items(d):
		match String(item.get("kind", "")):
			"fresh":
				fresh[item.variety] = int(fresh.get(item.variety, 0)) + int(item.get("count", 1))
			"nut":
				nuts[item.type] = int(nuts.get(item.type, 0)) + int(item.get("count", 1))
			"product":
				if int(item.get("wait_left", 0)) <= 0:
					products[item.key] = int(products.get(item.key, 0)) + int(item.get("count", 1))
	var use: Dictionary = FormulaGen.cfg().use
	var types: Array = Data.ingredients().keys()
	var fids: Array = fresh.keys()
	fids.sort_custom(func(a: String, b: String) -> bool:
		var ta := types.find(State.type_of_variety(a))
		var tb := types.find(State.type_of_variety(b))
		return ta < tb or (ta == tb and a < b))
	var out: Array = []
	for id: String in fids:
		out.append({"id": id, "kind": "fresh", "count": int(fresh[id]), "usable": int(fresh[id]) >= int(use.fresh)})
	var nids: Array = nuts.keys()
	nids.sort_custom(func(a: String, b: String) -> bool: return types.find(a) < types.find(b))
	for id: String in nids:
		out.append({"id": id, "kind": "nut", "count": int(nuts[id]), "usable": int(nuts[id]) >= int(use.nut)})
	var pids: Array = products.keys()
	pids.sort()
	for id: String in pids:
		out.append({"id": id, "kind": "product", "count": int(products[id]), "usable": int(products[id]) >= int(use.product)})
	for id: String in Data.addins():
		if String(Data.addins()[id].get("kind", "")) != "nut" and int(d.get("cupboard", {}).get(id, 0)) > 0:
			out.append({"id": id, "kind": "addin", "count": int(d.cupboard[id]), "usable": true})
	return out


## Display name of a pick in the current language.
static func pick_name(d: Dictionary, id: String, kind: String) -> String:
	match kind:
		"fresh":
			return VarietyGen.display_name(d.get("varieties", {}).get(id, {"type": State.type_of_variety(id)}))
		"nut":
			return VarietyGen.type_name(id)
		"product":
			return ProductGen.product_name(id, d.get("varieties", {}))
		"addin":
			return ProductGen.addin_name(id)
	return id


## A slot's words: the full name when it fits, else the shorter form (a variety's type, a product's type + dish).
static func slot_text(d: Dictionary, id: String, kind: String, width: float) -> String:
	var full := pick_name(d, id, kind)
	if FONT.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x <= width:
		return full
	var short := full
	match kind:
		"fresh":
			short = VarietyGen.type_name(State.type_of_variety(id))
		"product":
			var parts := ProductGen.name_parts(id, d.get("varieties", {}))
			short = ProductGen._join([parts.get("type", ""), parts.get("short", "")])
	return fit(short, width)


## `text` cut (with a trailing ".") until it fits `width` px in the panel font.
static func fit(text: String, width: float) -> String:
	if FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x <= width:
		return text
	var t := text
	while t.length() > 1 and FONT.get_string_size(t + ".", HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x > width:
		t = t.left(t.length() - 1).strip_edges()
	return t + "."


# ---------------------------------------------------------------- open / refresh

## Opens on `station` (a cooking method) when it can invent there, else on the first method that can.
func open(station: String) -> void:
	_build()
	var ms := Kitchen.formula_methods(GameState.data)
	method = station if ms.has(station) else (String(ms[0]) if not ms.is_empty() else station)
	_build_tabs()
	_drop_missing()
	visible = true
	refresh()
	_slide_in()
	if _tabs.has(method):
		_tabs[method].grab_focus()


## Rebuilds the grid, slots and preview from the save. Keeps keyboard focus on the same thing.
func refresh() -> void:
	if GameState.data.is_empty():
		return
	var fk := _focus_key()
	_update_tabs()
	_build_grid()
	_update_slots()
	_update_preview()
	_restore_focus(fk)


## Picks the save no longer has (cooked away, sold) leave their slots.
func _drop_missing() -> void:
	var have := {}
	for e: Dictionary in owned(GameState.data):
		have[e.id] = true
	components = components.filter(func(id: String) -> bool: return have.has(id))
	addins = addins.filter(func(id: String) -> bool: return have.has(id))


# ---------------------------------------------------------------- build

func _build() -> void:
	if _built:
		return
	_built = true
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", CookPanel._box(Art.PLUM, Art.CREAM_LO, 2, 6))
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.position = Vector2(8, 3)
	_title.size = Vector2(TAB_X - 12, 26)
	_title.text = tr("UI_FORMULA_TITLE")
	add_child(_title)
	_back = Button.new()
	_back.text = tr("UI_BACK")
	_back.position = Vector2(W - 58, 3)
	_back.size = Vector2(50, 26)
	_back.pressed.connect(func() -> void: close_requested.emit())
	add_child(_back)
	for i in 4:
		_make_slot(Vector2(8 + (i % 2) * (SLOT_W + 4), 34 + int(i / 2.0) * (SLOT_H + 2)), false)
	for i in 2:
		_make_slot(Vector2(8 + i * (SLOT_W + 4), 88), true)
	var frame := Panel.new()
	frame.position = Vector2(8, 118)
	frame.size = Vector2(36, 36)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", CookPanel._box(Art.IRON_DK, Art.BROWN, 1))
	add_child(frame)
	_jar = JarIcon.new()
	_jar.view = "icon"
	_jar.zoom = 2
	_jar.position = Vector2(2, 2)
	frame.add_child(_jar)
	_unknown = Label.new()
	_unknown.theme_type_variation = &"Heading"
	_unknown.text = "?"
	_unknown.size = Vector2(36, 36)
	_unknown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unknown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(_unknown)
	_name = _label(Vector2(50, 116), 222)
	_name.add_theme_color_override("font_color", Art.GOLD)
	_notes = _label(Vector2(50, 136), 160)
	_new_tag = _label(Vector2(214, 136), 58)
	_new_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_new_tag.add_theme_color_override("font_color", Art.PEACH)
	_new_tag.text = tr("UI_FORMULA_NEW_TAG")
	_chart = Bars.new()
	_chart.position = Vector2(8, 158)
	add_child(_chart)
	_stars = ResultCard.StarRow.new()
	_stars.position = Vector2(128, 160)
	add_child(_stars)
	_value = _label(Vector2(128, 176), 144)
	_profile = _label(Vector2(128, 194), 144)
	_feedback = _label(Vector2(8, 214), 264)
	var stock := _label(Vector2(RIGHT_X, 32), 176)
	stock.text = tr("UI_FORMULA_STOCK")
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(RIGHT_X - 2, 52)
	_scroll.size = Vector2(180, GRID_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bar := _scroll.get_v_scroll_bar()
	bar.add_theme_stylebox_override("scroll", CookPanel._box(Art.IRON_DK, Art.IRON_DK, 0, 3))
	bar.add_theme_stylebox_override("grabber", CookPanel._box(Art.BROWN, Art.BROWN, 0, 3))
	bar.add_theme_stylebox_override("grabber_highlight", CookPanel._box(Art.TAN, Art.TAN, 0, 3))
	bar.add_theme_stylebox_override("grabber_pressed", CookPanel._box(Art.AMBER, Art.AMBER, 0, 3))
	add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 1)
	_grid.add_theme_constant_override("v_separation", 1)
	_scroll.add_child(_grid)
	_hover = _label(Vector2(RIGHT_X, 172), 176)
	_cook = Button.new()
	_cook.text = tr("KITCHEN_COOK")
	_cook.position = Vector2(RIGHT_X, 198)
	_cook.size = Vector2(176, 26)
	_cook.pressed.connect(_on_cook)
	add_child(_cook)


func _make_slot(pos: Vector2, addin: bool) -> void:
	var b := Button.new()
	b.position = pos
	b.size = Vector2(SLOT_W, SLOT_H)
	_style(b, false)
	add_child(b)
	var ic := TextureRect.new()
	ic.position = Vector2(4, 4)
	ic.size = Vector2(16, 16)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var nm := _label(Vector2(22, 3), SLOT_W - 26, b)
	var i := _slots.size()
	b.pressed.connect(_on_slot.bind(i))
	b.mouse_entered.connect(_on_slot_hover.bind(i))
	b.focus_entered.connect(_on_slot_hover.bind(i))
	_slots.append({"button": b, "icon": ic, "name": nm, "addin": addin})


func _build_tabs() -> void:
	for b: Button in _tabs.values():
		b.queue_free()
	_tabs.clear()
	var ms := Kitchen.formula_methods(GameState.data)
	for i in ms.size():
		var m := String(ms[i])
		var b := Button.new()
		b.text = tr(String(METHOD_KEYS.get(m, m)))
		b.position = Vector2(TAB_X + i * (TAB_W + 2), 3)
		b.size = Vector2(TAB_W, 26)
		b.pressed.connect(_select_method.bind(m))
		add_child(b)
		_tabs[m] = b


func _build_grid() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_cells.clear()
	_entries.clear()
	var d := GameState.data
	var list := owned(d)
	for e: Dictionary in list:
		var b := Button.new()
		b.custom_minimum_size = CELL
		b.icon = _entry_icon(e)
		b.text = "x%d" % int(e.count)
		b.add_theme_constant_override("h_separation", 2)
		b.expand_icon = false
		var picked := components.has(e.id) or addins.has(e.id)
		_style(b, picked)
		if not bool(e.usable):
			for k in ["font_color", "font_hover_color", "font_focus_color"]:
				b.add_theme_color_override(k, Art.MUTED)
		b.tooltip_text = pick_name(d, e.id, e.kind)
		b.pressed.connect(_on_cell.bind(String(e.id)))
		b.mouse_entered.connect(_on_cell_hover.bind(String(e.id)))
		b.focus_entered.connect(_on_cell_hover.bind(String(e.id)))
		_grid.add_child(b)
		_cells[e.id] = b
		_entries[e.id] = e
	if list.is_empty():
		_hover.text = fit(tr("UI_FORMULA_EMPTY"), _hover.size.x)
	elif _hover.text == "":
		_hover.text = fit(tr("UI_FORMULA_PICK_HINT"), _hover.size.x)


# ---------------------------------------------------------------- updates

func _update_tabs() -> void:
	for m: String in _tabs:
		_style(_tabs[m], m == method)


func _update_slots() -> void:
	var d := GameState.data
	var ci := 0
	var ai := 0
	for s: Dictionary in _slots:
		var id := ""
		var kind := "addin"
		if s.addin:
			id = String(addins[ai]) if ai < addins.size() else ""
			ai += 1
		else:
			id = String(components[ci]) if ci < components.size() else ""
			ci += 1
			kind = FormulaGen.component_kind(id)
		var nm: Label = s.name
		var ic: TextureRect = s.icon
		_style(s.button, id != "")
		if id == "":
			ic.texture = null
			nm.text = fit(tr("UI_FORMULA_ADDIN_SLOT") if s.addin else tr("UI_FORMULA_SLOT"), nm.size.x)
			nm.add_theme_color_override("font_color", Art.MUTED)
		else:
			var e: Dictionary = _entries.get(id, {"id": id, "kind": kind})
			ic.texture = _entry_icon(e)
			nm.text = slot_text(d, id, kind, nm.size.x)
			nm.add_theme_color_override("font_color", Art.CREAM)


func _update_preview() -> void:
	var d := GameState.data
	var chk := Kitchen.check_formula(d, method, components, addins)
	_key = String(chk.get("key", ""))
	var n := components.size()
	var show := n >= int(FormulaGen.cfg().components_min) and _key != ""
	_jar.visible = show
	_unknown.visible = not show
	_name.visible = show
	_chart.visible = show
	_stars.visible = show
	_value.visible = show
	_profile.visible = show
	_notes.visible = show
	_new_tag.visible = show and not d.get("formulas", {}).has(_key)
	if show:
		var desc := ProductGen.describe(_key, d.varieties)
		_jar.show_product(desc)
		_name.text = fit(String(desc.name), _name.size.x)
		_name.tooltip_text = String(desc.name)
		var words: PackedStringArray = []
		for id in desc.get("notes", []):
			words.append(tr("FX_NOTE_" + String(id).to_upper()))
		_notes.text = fit(", ".join(words), _notes.size.x)
		_chart.set_taste(desc.taste)
		_stars.set_stars(0, int(desc.harmony))
		var lo := ProductGen.value(_key, d.varieties, 1)
		var hi := ProductGen.value(_key, d.varieties, 3)
		_value.text = fit(tr("UI_FORMULA_VALUE") % [lo, hi], _value.size.x)
		_profile.text = fit(String(desc.profile_label), _profile.size.x)
	_ok = bool(chk.ok)
	var reason := "KITCHEN_READY" if _ok else String(chk.reason)
	if n < int(FormulaGen.cfg().components_min) and reason in ["", Kitchen.R_FX_COUNT]:
		reason = "UI_FORMULA_COUNT"
	_feedback.text = fit(tr(reason), _feedback.size.x)
	_feedback.add_theme_color_override("font_color", Art.GOLD_PALE if _ok else Art.PEACH)
	_cook.modulate = Color.WHITE if _ok else Color(1, 1, 1, 0.55)


# ---------------------------------------------------------------- picking

func _select_method(m: String) -> void:
	if m == method:
		return
	method = m
	Audio.play_ui("ui_click")
	refresh()
	if _tabs.has(m):
		_pop(_tabs[m])


func _on_cell(id: String) -> void:
	var e: Dictionary = _entries.get(id, {})
	if e.is_empty():
		return
	var c: Dictionary = FormulaGen.cfg()
	if components.has(id):
		components.erase(id)
	elif addins.has(id):
		addins.erase(id)
	elif e.kind == "addin":
		if addins.size() >= int(c.addins_max):
			_reject(_cells[id])
			return
		addins.append(id)
	elif not bool(e.usable):
		_reject(_cells[id])
		_hover.text = fit(tr("UI_KITCHEN_MISSING"), _hover.size.x)
		return
	elif components.size() < int(c.components_max):
		components.append(id)
	elif e.kind == "nut" and addins.size() < int(c.addins_max):
		addins.append(id)  # a nut fits the add-in row too once the four component slots are full
	else:
		_reject(_cells[id])
		return
	Audio.play_ui("ui_click")
	refresh()
	if _cells.has(id):
		_pop(_cells[id])


func _on_slot(i: int) -> void:
	var s: Dictionary = _slots[i]
	var list: Array = addins if s.addin else components
	var j := _slot_index(i)
	if j >= list.size():
		_reject(s.button)
		return
	list.remove_at(j)
	Audio.play_ui("ui_back")
	refresh()


## Index into components / addins of slot `i`.
func _slot_index(i: int) -> int:
	var j := 0
	for k in i:
		if _slots[k].addin == _slots[i].addin:
			j += 1
	return j


func _on_cell_hover(id: String) -> void:
	var e: Dictionary = _entries.get(id, {})
	if not e.is_empty():
		_hover.text = fit("%s x%d" % [pick_name(GameState.data, id, e.kind), int(e.count)], _hover.size.x)


func _on_slot_hover(i: int) -> void:
	var s: Dictionary = _slots[i]
	var list: Array = addins if s.addin else components
	var j := _slot_index(i)
	if j < list.size():
		var id := String(list[j])
		_hover.text = fit(pick_name(GameState.data, id, "addin" if s.addin else FormulaGen.component_kind(id)), _hover.size.x)


func _on_cook() -> void:
	if not _ok:
		_reject(_cook)
		_update_preview()
		return
	cook_requested.emit(method, components.duplicate(), addins.duplicate())


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close_requested.emit()


# ---------------------------------------------------------------- icons

func _entry_icon(e: Dictionary) -> Texture2D:
	var id := String(e.get("id", ""))
	match String(e.get("kind", "")):
		"fresh":
			return _type_icon(State.type_of_variety(id))
		"product":
			if not _icons.has(id):
				var desc := ProductGen.describe(id, GameState.data.varieties)
				_icons[id] = ImageTexture.create_from_image(JarIcon.render(desc, "icon"))
			return _icons[id]
	return Art.icon(id)


## The atlas icon of an ingredient type; a type without one (pumpkin today, generated species) gets a round fruit in
## its own ramp tones (palette colours) so the grid never shows an empty cell.
func _type_icon(type: String) -> Texture2D:
	var key := "type:" + type
	if _icons.has(key):
		return _icons[key]
	var tex := Art.icon(type)
	if tex == null or tex.get_image() == null or tex.get_image().is_invisible():
		var ramp: Variant = Data.ingredients().get(type, {}).get("ramp")
		if typeof(ramp) == TYPE_ARRAY and ramp.size() >= 4:
			var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
			for y in 16:
				for x in 16:
					var dist := Vector2(x - 7.5, y - 8.5).length()
					if dist <= 6.0:
						var tone := 0 if dist > 5.0 else (3 if x < 7 and y < 7 else (1 if x + y > 18 else 2))
						img.set_pixel(x, y, Color.html(String(ramp[tone])))
			img.set_pixel(8, 2, Color.html(String(ramp[0])))
			img.set_pixel(8, 1, Color.html(String(ramp[0])))
			tex = ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


## The five taste axes on the dark panel: name, then 9 cells per axis (the result card's chart, light text).
class Bars extends Control:
	const CELLS_W := 9 * 7
	const MAX_W := 118  ## leaves the star row at x 128 its room
	var taste: Array = [0, 0, 0, 0, 0]
	var label_w := 40

	func _init() -> void:
		for a: String in ResultCard.AXES:
			label_w = maxi(label_w, ceili(FONT.get_string_size(tr("UI_TASTE_" + a.to_upper()), HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x) + 3)
		label_w = mini(label_w, MAX_W - CELLS_W)
		custom_minimum_size = Vector2(label_w + CELLS_W, 54)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_taste(t: Array) -> void:
		taste = t
		queue_redraw()

	func _draw() -> void:
		for i in 5:
			var y := i * 11
			draw_string(FONT, Vector2(0, y + 8), tr("UI_TASTE_" + String(ResultCard.AXES[i]).to_upper()), HORIZONTAL_ALIGNMENT_LEFT,
				-1, FS, Art.CREAM_LO)
			var v := clampi(int(taste[i]) if i < taste.size() else 0, 0, 9)
			for c in 9:
				draw_rect(Rect2(label_w + c * 7, y + 1, 6, 7), ResultCard.AXIS_COLORS[i] if c < v else Art.STONE)


# ---------------------------------------------------------------- focus

func _focus_key() -> String:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f == null:
		return ""
	for id in _cells:
		if _cells[id] == f:
			return "cell:" + String(id)
	for i in _slots.size():
		if _slots[i].button == f:
			return "slot:%d" % i
	for m in _tabs:
		if _tabs[m] == f:
			return "tab:" + String(m)
	return "cook:" if f == _cook else ""


func _restore_focus(key: String) -> void:
	if not is_inside_tree():
		return
	var f := get_viewport().gui_get_focus_owner()
	if key == "" or (f != null and f.is_inside_tree()):
		return
	var parts := key.split(":", true, 1)
	var target: Control = null
	match parts[0]:
		"cell":
			target = _cells.get(parts[1])
		"slot":
			target = _slots[int(parts[1])].button
		"tab":
			target = _tabs.get(parts[1])
		"cook":
			target = _cook
	if target == null and not _cells.is_empty():
		target = _cells.values()[0]
	if target != null and target.is_visible_in_tree():
		target.grab_focus()


# ---------------------------------------------------------------- look and juice

func _label(pos: Vector2, w: int, parent: Control = null) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(w, 18)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(l)
	return l


func _style(b: Button, selected: bool) -> void:
	b.add_theme_stylebox_override("normal", CookPanel._box(Art.PLUM if selected else Art.IRON_DK, Art.GOLD if selected else Art.BROWN, 2 if selected else 1))
	b.add_theme_stylebox_override("hover", CookPanel._box(Art.PLUM if selected else Art.BARK, Art.GOLD if selected else Art.TAN, 2 if selected else 1))
	b.add_theme_stylebox_override("pressed", CookPanel._box(Art.WINE, Art.GOLD, 2))
	b.add_theme_stylebox_override("hover_pressed", CookPanel._box(Art.WINE, Art.GOLD, 2))
	b.add_theme_stylebox_override("focus", CookPanel._box(Art.IRON_DK, Art.GOLD_PALE, 1, 2, false))
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Art.CREAM)


func _slide_in() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	position = home + Vector2(0, 10)
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void: position = Vector2(home.x, roundf(v)), home.y + 10.0, home.y, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pop(c: Control) -> void:
	if not is_instance_valid(c):
		return
	c.pivot_offset = (c.size / 2.0).floor()
	c.scale = Vector2(1.1, 1.1)
	c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _reject(c: Control) -> void:
	Audio.play_ui("ui_error")
	if not is_instance_valid(c) or c.get_parent() is Container:  # grid cells: their container owns the position
		return
	if not c.has_meta("shake_x"):
		c.set_meta("shake_x", c.position.x)
	var x0: float = c.get_meta("shake_x")
	var t := c.create_tween()
	for dx in [2, -2, 2, -1, 0]:
		t.tween_property(c, "position:x", x0 + dx, 0.04)
