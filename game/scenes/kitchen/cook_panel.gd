extends Panel
## GD-KITCHEN · Cook panel (spec §7.2) for one station: recipe picker, variety slots filled by clicking or dragging
## stacks from the inbox + pantry list, add-in picker (cupboard add-ins + nut stacks), Kitchen.check feedback in
## words, name preview only for variants already in the book, Cook button. Rules stay in Kitchen/ProductGen:
## this panel only routes picks into the slot they belong to and shows what Kitchen.check() answers.

signal cook_requested(recipe_id: String, main_variety: String, second_variety: String, addin_id: String)
signal close_requested

const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const W := 464
const H := 236
const TAB_W := 146
const TAB_H := 38
const SLOT_W := 264
const SLOT_H := 24
const ROW_W := 168
const RIGHT_X := 280
const DRAG_KEY := "kitchen_variety"
const SLOTS := ["main", "second"]

var station := ""
var recipe := ""
var picks := {"main": "", "second": ""}
var addin := ""
var home := Vector2(8, 30)

var _recipes: Array = []
var _title: Label
var _back: Button
var _tab_box: Control
var _tabs: Dictionary = {}  # recipe id -> Button
var _slots: Dictionary = {}  # "main"/"second" -> {"button", "caption", "need", "icon", "name"}
var _addin_label: Label
var _addin_box: Control
var _addin_buttons: Dictionary = {}  # add-in id ("" = none) -> Button
var _preview_frame: Panel
var _preview_jar: JarIcon
var _preview_unknown: Label
var _preview_name: Label
var _feedback: Label
var _missing_row: HBoxContainer
var _cook: Button
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Dictionary = {}  # variety id -> Button
var _ok := false
var _tween: Tween


func _ready() -> void:
	_build()


# ---------------------------------------------------------------- pure helpers (state in, plain data out)

## P0 recipes cooked with `method`, cheapest first (jam, butter, chutney / pickles, brine).
static func recipes_for(method: String) -> Array:
	var all := Data.recipes()
	var out: Array = []
	for id in Data.ids_up_to("recipes", 0):
		if String(all[id].method) == method:
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return int(all[a].base_value) < int(all[b].base_value))
	return out


## Fresh units per variety id in the inbox and the pantry.
static func fresh_stock(d: Dictionary) -> Dictionary:
	var out := {}
	for item: Dictionary in _all_items(d):
		if item.kind == "fresh":
			out[item.variety] = int(out.get(item.variety, 0)) + int(item.count)
	return out


## Units per nut type in the inbox and the pantry.
static func nut_stock(d: Dictionary) -> Dictionary:
	var out := {}
	for item: Dictionary in _all_items(d):
		if item.kind == "nut":
			out[item.type] = int(out.get(item.type, 0)) + int(item.count)
	return out


## How many of an add-in the player has: cupboard for shop add-ins, inbox + pantry stacks for nuts.
static func addin_count(d: Dictionary, id: String) -> int:
	var a: Dictionary = Data.addins().get(id, {})
	if a.get("kind", "") == "nut":
		return int(nut_stock(d).get(id, 0))
	return int(d.cupboard.get(id, 0))


static func available_addins(d: Dictionary) -> Array:
	var out: Array = []
	for id in Data.ids_up_to("addins", 0):
		if addin_count(d, id) > 0:
			out.append(id)
	return out


static func _all_items(d: Dictionary) -> Array:
	var out: Array = d.inbox.duplicate()
	for e: Dictionary in d.pantry.items:
		out.append(e.item)
	return out


# ---------------------------------------------------------------- open / refresh

func open(station_id: String) -> void:
	if station_id != station or _tabs.is_empty():
		station = station_id
		recipe = ""
		picks = {"main": "", "second": ""}
		addin = ""
		_build_tabs()
	if recipe == "" and not _recipes.is_empty():
		recipe = _recipes[0]
	var d := GameState.data
	var stock := fresh_stock(d)
	for which in SLOTS:
		if picks[which] != "" and int(stock.get(picks[which], 0)) == 0:
			picks[which] = ""
	if addin != "" and addin_count(d, addin) == 0:
		addin = ""
	_title.text = tr("KITCHEN_STOVE") if station == "stir_pot" else tr("KITCHEN_COUNTER")
	visible = true
	refresh()
	_slide_in()
	if _tabs.has(recipe):
		_tabs[recipe].grab_focus()


## Rebuilds everything that depends on the save (stock, add-ins, check). Keeps keyboard focus where it was.
func refresh() -> void:
	if recipe == "" or GameState.data.is_empty():
		return
	var fk := _focus_key()
	_update_tabs()
	_update_slots()
	_build_addins()
	_build_list()
	_update_check()
	_restore_focus(fk)


# ---------------------------------------------------------------- build

func _build() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# recipe card: dark card with a cream paper edge
	var card := _box(Art.PLUM, Art.CREAM_LO, 2, 6)
	add_theme_stylebox_override("panel", card)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.position = Vector2(8, 3)
	add_child(_title)
	_back = Button.new()
	_back.text = tr("UI_BACK")
	_back.position = Vector2(W - 58, 3)
	_back.size = Vector2(50, 26)
	_back.pressed.connect(func() -> void: close_requested.emit())
	add_child(_back)

	_tab_box = Control.new()
	_tab_box.position = Vector2(8, 32)
	_tab_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tab_box)

	for i in SLOTS.size():
		_make_slot(SLOTS[i], Vector2(8, 74 + i * (SLOT_H + 2)))

	_addin_label = _label(self, Vector2(8, 103), 42)
	_addin_label.text = tr("KITCHEN_ADDIN")
	_addin_box = Control.new()
	_addin_box.position = Vector2(52, 100)
	_addin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_addin_box)

	_preview_frame = Panel.new()
	_preview_frame.position = Vector2(8, 130)
	_preview_frame.size = Vector2(36, 36)
	_preview_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_frame.add_theme_stylebox_override("panel", _box(Art.IRON_DK, Art.BROWN, 1))
	add_child(_preview_frame)
	_preview_jar = JarIcon.new()
	_preview_jar.view = "icon"
	_preview_jar.zoom = 2
	_preview_jar.position = Vector2(2, 2)
	_preview_frame.add_child(_preview_jar)
	_preview_unknown = Label.new()
	_preview_unknown.theme_type_variation = &"Heading"
	_preview_unknown.text = "?"
	_preview_unknown.size = Vector2(36, 36)
	_preview_unknown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_unknown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_frame.add_child(_preview_unknown)
	_preview_name = _label(self, Vector2(50, 128), 222)
	_feedback = _label(self, Vector2(50, 146), 222)
	_feedback.size.y = 36
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_missing_row = HBoxContainer.new()
	_missing_row.position = Vector2(50, 184)
	_missing_row.add_theme_constant_override("separation", 1)
	_missing_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_missing_row)

	var stock_label := _label(self, Vector2(RIGHT_X, 74), 176)
	stock_label.text = tr("KITCHEN_STOCK")
	_cook = Button.new()
	_cook.position = Vector2(RIGHT_X, 198)
	_cook.size = Vector2(176, 26)
	_cook.pressed.connect(_on_cook)
	add_child(_cook)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(RIGHT_X - 2, 94)
	_scroll.size = Vector2(180, 98)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bar := _scroll.get_v_scroll_bar()
	bar.add_theme_stylebox_override("scroll", _box(Art.IRON_DK, Art.IRON_DK, 0, 3))
	bar.add_theme_stylebox_override("scroll_focus", _box(Art.IRON_DK, Art.IRON_DK, 0, 3))
	bar.add_theme_stylebox_override("grabber", _box(Art.BROWN, Art.BROWN, 0, 3))
	bar.add_theme_stylebox_override("grabber_highlight", _box(Art.TAN, Art.TAN, 0, 3))
	bar.add_theme_stylebox_override("grabber_pressed", _box(Art.AMBER, Art.AMBER, 0, 3))
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 1)
	_list.custom_minimum_size = Vector2(ROW_W, 0)
	_scroll.add_child(_list)


func _make_slot(which: String, pos: Vector2) -> void:
	var b := Button.new()
	b.position = pos
	b.size = Vector2(SLOT_W, SLOT_H)
	_style(b, false)
	b.pressed.connect(_on_slot_pressed.bind(which))
	b.set_drag_forwarding(Callable(), _can_drop.bind(which), _drop.bind(which))
	add_child(b)
	var cap := _label(b, Vector2(5, 3), 44)
	cap.add_theme_color_override("font_color", Art.GOLD)
	var need := _label(b, Vector2(4, 3), SLOT_W - 10)
	need.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var ic := TextureRect.new()
	ic.position = Vector2(52, 4)
	ic.size = Vector2(16, 16)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var nm := _label(b, Vector2(72, 3), 150)
	_slots[which] = {"button": b, "caption": cap, "need": need, "icon": ic, "name": nm}


func _build_tabs() -> void:
	for c in _tab_box.get_children():
		_tab_box.remove_child(c)
		c.queue_free()
	_tabs.clear()
	_recipes = recipes_for(station)
	var all := Data.recipes()
	for i in _recipes.size():
		var id: String = _recipes[i]
		var r: Dictionary = all[id]
		var b := Button.new()
		b.position = Vector2(i * (TAB_W + 5), 0)
		b.size = Vector2(TAB_W, TAB_H)
		b.pressed.connect(_select_recipe.bind(id))
		_tab_box.add_child(b)
		var nm := _label(b, Vector2(6, 1), TAB_W - 12)
		nm.text = String(r.name)
		var row := HBoxContainer.new()
		row.position = Vector2(6, 19)
		row.add_theme_constant_override("separation", 1)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var two := typeof(r.get("second")) == TYPE_DICTIONARY
		for which in SLOTS:
			var spec: Variant = r.get(which)
			if typeof(spec) != TYPE_DICTIONARY:
				continue
			_icon_text(row, str(int(spec.count)), Art.CREAM)
			for ic in Art.slot_icon_ids(spec, 2 if two else 3):
				_icon(row, ic)
		_icon_text(row, "+", Art.CREAM_LO)
		for base_id in r.get("base", {}):
			_icon(row, base_id)
		_tabs[id] = b


func _build_addins() -> void:
	for c in _addin_box.get_children():
		_addin_box.remove_child(c)
		c.queue_free()
	_addin_buttons.clear()
	var d := GameState.data
	var ids: Array = [""]
	ids.append_array(available_addins(d))
	if addin != "" and not ids.has(addin):
		ids.append(addin)
	var x := 0
	for id: String in ids:
		var b := Button.new()
		var w := 36 if id == "" else 26
		b.position = Vector2(x, 0)
		b.size = Vector2(w, 24)
		if id == "":
			b.text = tr("KITCHEN_NONE")
		else:
			b.icon = Art.icon(id)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var n := _label(b, Vector2(11, 8), 13)
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			n.text = str(addin_count(d, id))
		_style(b, id == addin)
		b.pressed.connect(_select_addin.bind(id))
		_addin_box.add_child(b)
		_addin_buttons[id] = b
		x += w + 2


func _build_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	var d := GameState.data
	var stock := fresh_stock(d)
	var ids: Array = stock.keys()
	var fit := {}
	for vid in ids:
		fit[vid] = _fits("main", vid) or _fits("second", vid)
	ids.sort_custom(func(a: String, b: String) -> bool:
		if fit[a] != fit[b]:
			return fit[a]
		return _variety_name(a) < _variety_name(b))
	if ids.is_empty():
		var empty := Label.new()
		empty.text = tr("KITCHEN_LIST_EMPTY")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(ROW_W, 72)
		_list.add_child(empty)
	for vid: String in ids:
		var b := Button.new()
		b.custom_minimum_size = Vector2(ROW_W, 20)
		b.icon = Art.icon(State.type_of_variety(vid))
		b.text = _variety_name(vid)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var picked: bool = vid == picks.main or vid == picks.second
		_style_row(b, picked, fit[vid])
		var cnt := _label(b, Vector2(ROW_W - 30, 1), 26)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.text = "x%d" % int(stock[vid])
		b.pressed.connect(_pick.bind(vid, b))
		b.set_drag_forwarding(_row_drag.bind(vid, b), Callable(), Callable())
		_list.add_child(b)
		_rows[vid] = b


# ---------------------------------------------------------------- updates

func _update_tabs() -> void:
	for id in _tabs:
		_style(_tabs[id], id == recipe)


func _update_slots() -> void:
	var stock := fresh_stock(GameState.data)
	# Everything under the slots moves up one row when the recipe has no second slot.
	var y0 := 100 if _spec("second") == null else 126
	_addin_label.position = Vector2(8, y0 + 3)
	_addin_box.position = Vector2(52, y0)
	_preview_frame.position = Vector2(8, y0 + 30)
	_preview_name.position = Vector2(50, y0 + 28)
	_feedback.position = Vector2(50, y0 + 46)
	_missing_row.position = Vector2(50, y0 + 84)
	for which in SLOTS:
		var s: Dictionary = _slots[which]
		var spec: Variant = _spec(which)
		s.button.visible = spec != null
		if spec == null:
			continue
		var vid: String = picks[which]
		var need := int(spec.count)
		s.caption.text = tr("KITCHEN_SLOT_MAIN") if which == "main" else tr("KITCHEN_SLOT_SECOND")
		if vid == "":
			s.need.text = "x%d" % need
			s.need.add_theme_color_override("font_color", Art.CREAM)
			s.icon.texture = null
			s.name.text = tr("KITCHEN_EMPTY_SLOT")
			s.name.add_theme_color_override("font_color", Art.MUTED)
		else:
			var have := int(stock.get(vid, 0))
			s.need.text = "%d/%d" % [mini(have, 99), need]
			s.need.add_theme_color_override("font_color", Art.CREAM if have >= need else Art.PEACH)
			s.icon.texture = Art.icon(State.type_of_variety(vid))
			s.name.text = _variety_name(vid)
			s.name.add_theme_color_override("font_color", Art.CREAM)


func _update_check() -> void:
	var d := GameState.data
	var r: Dictionary = Data.recipes()[recipe]
	_cook.text = tr("KITCHEN_COOK_COST") % Kitchen.energy_cost(String(r.method))
	for c in _missing_row.get_children():
		_missing_row.remove_child(c)
		c.queue_free()
	_preview_jar.visible = false
	_preview_unknown.visible = true
	_preview_name.text = ""
	if picks.main == "" or (_spec("second") != null and picks.second == ""):
		_ok = false
		var any_fit := false
		for vid in fresh_stock(d):
			any_fit = any_fit or _fits("main", vid) or _fits("second", vid)
		_set_feedback(tr("KITCHEN_FILL_SLOTS") if any_fit else tr("KITCHEN_NOTHING_FITS"), Art.CREAM_LO)
		_set_cook_look()
		return
	var c := Kitchen.check(d, recipe, picks.main, _second(), addin)
	var key := ProductGen.make_key(recipe, _pick_list(), addin)
	var known: bool = d.book.variants.has(key)
	if known:
		_preview_jar.show_product(ProductGen.describe(key, d.varieties))
		_preview_jar.visible = true
		_preview_unknown.visible = false
	_preview_name.text = ProductGen.product_name(key, d.varieties) if known else tr("KITCHEN_NEW_VARIANT")
	_preview_name.add_theme_color_override("font_color", Art.GOLD_PALE if known else Art.GOLD)
	_ok = bool(c.ok)
	if _ok:
		_set_feedback(tr("KITCHEN_READY"), Art.CREAM_LO)
	else:
		var line := tr(String(c.reason))
		var extra := _hint_for(c)
		_set_feedback(line if extra == "" else "%s. %s" % [line, extra], Art.PEACH)
		for id: String in c.missing:
			_icon(_missing_row, State.type_of_variety(id) if d.varieties.has(id) else id)
			_icon_text(_missing_row, "x%d" % int(c.missing[id]), Art.PEACH)
	_set_cook_look()


func _hint_for(c: Dictionary) -> String:
	match String(c.reason):
		Kitchen.R_TIRED:
			return tr("KITCHEN_SLEEP_HINT")
		Kitchen.R_MISSING:
			var buy: Dictionary = Data.shop().get("buy", {})
			for id in c.missing:
				if buy.has(id):
					return tr("KITCHEN_GROCER_HINT")
			return tr("KITCHEN_FORAGE_HINT")
	return ""


func _set_feedback(s: String, col: Color) -> void:
	_feedback.text = s
	_feedback.add_theme_color_override("font_color", col)


## Not ready: the button keeps taking presses (they answer with a shake and the reason) but looks disabled.
func _set_cook_look() -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		_cook.remove_theme_stylebox_override(st)
		if not _ok:
			_cook.add_theme_stylebox_override(st, _cook.get_theme_stylebox("disabled"))
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		_cook.remove_theme_color_override(k)
		if not _ok:
			_cook.add_theme_color_override(k, Art.STONE)


# ---------------------------------------------------------------- picking

func _spec(which: String) -> Variant:
	if recipe == "":
		return null
	var s: Variant = Data.recipes()[recipe].get(which)
	if typeof(s) != TYPE_DICTIONARY or s.has("recipe"):
		return null
	return s


## Slot routing only (which slot a variety goes to); the verdict always comes from Kitchen.check().
func _fits(which: String, vid: String) -> bool:
	var spec: Variant = _spec(which)
	if spec == null:
		return false
	var v: Dictionary = GameState.data.varieties.get(vid, {})
	var type := String(v.get("type", State.type_of_variety(vid)))
	if spec.has("types"):
		return spec.types.has(type)
	return spec.has("groups") and spec.groups.has(String(Data.ingredients().get(type, {}).get("group", "")))


func _second() -> String:
	return picks.second if _spec("second") != null else ""


func _pick_list() -> Array:
	var out: Array = [picks.main]
	if _second() != "":
		out.append(picks.second)
	return out


func _variety_name(vid: String) -> String:
	return String(GameState.data.varieties.get(vid, {}).get("name", vid))


func _select_recipe(id: String) -> void:
	if id != recipe:
		recipe = id
		for which in SLOTS:
			if picks[which] != "" and not _fits(which, picks[which]):
				picks[which] = ""
		Audio.play_ui("ui_click")
	refresh()


func _select_addin(id: String) -> void:
	addin = id
	Audio.play_ui("ui_click")
	refresh()
	if _addin_buttons.has(id):
		_pop(_addin_buttons[id])


func _pick(vid: String, from: Control) -> void:
	for which in SLOTS:
		if _fits(which, vid):
			_set_pick(which, vid)
			return
	_reject(from)


func _set_pick(which: String, vid: String) -> void:
	picks[which] = vid
	Audio.play_ui("ui_click")
	refresh()
	_pop(_slots[which].button)


func _reject(node: Control) -> void:
	Audio.play_ui("ui_error")
	_set_feedback(tr(Kitchen.R_WRONG), Art.PEACH)
	_shake(node)


func _on_slot_pressed(which: String) -> void:
	if picks[which] != "":
		picks[which] = ""
		Audio.play_ui("ui_back")
		refresh()
		return
	for vid in _rows:
		if _fits(which, vid):
			_rows[vid].grab_focus()
			_scroll.ensure_control_visible(_rows[vid])
			return
	_reject(_slots[which].button)


func _on_cook() -> void:
	_update_check()
	if not _ok:
		Audio.play_ui("ui_error")
		_shake(_cook)
		return
	cook_requested.emit(recipe, picks.main, _second(), addin)


func _row_drag(_at: Vector2, vid: String, row: Button) -> Variant:
	var prev := TextureRect.new()
	prev.texture = row.icon
	prev.size = Vector2(16, 16)
	row.set_drag_preview(prev)
	return {DRAG_KEY: vid}


func _can_drop(_at: Vector2, data: Variant, which: String) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has(DRAG_KEY) and _spec(which) != null


func _drop(_at: Vector2, data: Variant, which: String) -> void:
	var vid := String(data[DRAG_KEY])
	if _fits(which, vid):
		_set_pick(which, vid)
	else:
		_reject(_slots[which].button)


# ---------------------------------------------------------------- focus

func _focus_key() -> String:
	var f := get_viewport().gui_get_focus_owner()
	if f == null:
		return ""
	for vid in _rows:
		if _rows[vid] == f:
			return "row:" + vid
	for id in _addin_buttons:
		if _addin_buttons[id] == f:
			return "addin:" + id
	for which in SLOTS:
		if _slots[which].button == f:
			return "slot:" + which
	for id in _tabs:
		if _tabs[id] == f:
			return "tab:" + id
	return ""


func _restore_focus(key: String) -> void:
	var f := get_viewport().gui_get_focus_owner()
	if key == "" or (f != null and f.is_inside_tree()):
		return
	var parts := key.split(":", true, 1)
	var target: Control = null
	match parts[0]:
		"row":
			target = _rows.get(parts[1])
		"addin":
			target = _addin_buttons.get(parts[1])
		"slot":
			target = _slots[parts[1]].button
		"tab":
			target = _tabs.get(parts[1])
	if target == null and not _rows.is_empty():
		target = _rows.values()[0]
	if target != null:
		target.grab_focus()


# ---------------------------------------------------------------- look and juice

func _label(parent: Control, pos: Vector2, w: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(w, 18)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _icon(row: HBoxContainer, id: String) -> void:
	var t := TextureRect.new()
	t.texture = Art.icon(id)
	t.custom_minimum_size = Vector2(16, 16)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(t)


func _icon_text(row: HBoxContainer, s: String, col: Color) -> void:
	var l := Label.new()
	l.text = s
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", col)
	row.add_child(l)


static func _box(bg: Color, border: Color, bw: int, margin := 2, center := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.draw_center = center
	s.anti_aliasing = false
	s.set_content_margin_all(margin)
	return s


## Tabs, slots and add-in buttons: dark box, gold double edge when selected, gold outline on focus.
func _style(b: Button, selected: bool) -> void:
	b.add_theme_stylebox_override("normal", _box(Art.PLUM if selected else Art.IRON_DK, Art.GOLD if selected else Art.BROWN, 2 if selected else 1))
	b.add_theme_stylebox_override("hover", _box(Art.PLUM if selected else Art.BARK, Art.GOLD if selected else Art.TAN, 2 if selected else 1))
	b.add_theme_stylebox_override("pressed", _box(Art.WINE, Art.GOLD, 2))
	b.add_theme_stylebox_override("hover_pressed", _box(Art.WINE, Art.GOLD, 2))
	b.add_theme_stylebox_override("focus", _box(Art.IRON_DK, Art.GOLD_PALE, 1, 2, false))
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Art.CREAM)


func _style_row(b: Button, picked: bool, fits: bool) -> void:
	var bg := Art.WINE if picked else Art.PLUM
	b.add_theme_stylebox_override("normal", _box(bg, Art.GOLD if picked else bg, 1, 1))
	b.add_theme_stylebox_override("hover", _box(Art.BARK, Art.TAN, 1, 1))
	b.add_theme_stylebox_override("pressed", _box(Art.WINE, Art.GOLD, 1, 1))
	b.add_theme_stylebox_override("hover_pressed", _box(Art.WINE, Art.GOLD, 1, 1))
	b.add_theme_stylebox_override("focus", _box(bg, Art.GOLD_PALE, 1, 1, false))
	b.add_theme_constant_override("h_separation", 4)
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Art.CREAM if fits else Art.MUTED)


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


func _shake(c: Control) -> void:
	if not c.has_meta("shake_x"):
		c.set_meta("shake_x", c.position.x)
	var x0: float = c.get_meta("shake_x")
	var t := c.create_tween()
	for dx in [2, -2, 2, -1, 0]:
		t.tween_property(c, "position:x", x0 + dx, 0.04)
