class_name Book
extends CanvasLayer
## Recipe book overlay (GD-BOOK, spec §7.9). Open with `Book.open()` (static, finds or creates the overlay).
## Tabs: Recipes (base recipes + discovered variants) and Varieties (found / "???"). Closes on cancel, B or the X button.

const SCENE := "res://ui/book/book.tscn"
const PAPER := Color("f2d9c5")
const PAPER_DK := Color("b9a697")
const FRAME := Color("83571e")
const TEXT := Color("50361e")
const GOLD := Color("e5bd7f")
const GOLD_DK := Color("b66813")
const INK := Color("111010")
const GREEN := Color("4e7664")
const RED := Color("a22512")
const SILHOUETTE := Color("49423d")
const FONT_BODY := preload("res://assets/fonts/m5x7.ttf")
const FONT_TITLE := preload("res://assets/fonts/m6x11plus.ttf")
const MILESTONES := [5, 15, 30, 60]
const VARIANTS_PER_PAGE := 3
const TYPES_PER_PAGE := 3
const ROW_H := 52
const PAGE_W := 206
const PAGE_H := 176
const RECIPE_ORDER := ["jam", "fruit_butter", "chutney", "pickle", "brined_mushroom"]

var _tab := 0
var _page := 0
var _built := false
var _dim: TextureRect
var _panel: PanelContainer
var _tab_btns: Array[Button] = []
var _left: VBoxContainer
var _right: VBoxContainer
var _milestone: Label
var _prev: Button
var _next: Button
var _page_label: Label
var _close: Button
var _icon_names := {}


## Finds the open book or creates one under the scene root. Returns it.
static func open() -> Book:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var b := tree.get_first_node_in_group("book") as Book
	if b == null:
		b = (load(SCENE) as PackedScene).instantiate() as Book
		tree.root.add_child(b)  # _ready() shows it
	else:
		b.show_book()
	return b


## GameState.data (looked up by path so the script also compiles where autoloads are not registered yet).
func _data() -> Dictionary:
	var gs := get_node_or_null("/root/GameState")
	return gs.data if gs != null else {}


func _ready() -> void:
	layer = 20
	add_to_group("book")
	show_book()


func show_book(tab := 0) -> void:
	_build()
	visible = true
	_tab = tab
	_page = 0
	_refresh()
	_close.grab_focus()


func close_book() -> void:
	visible = false
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("cancel") or event.is_action("ui_cancel") or event.is_action("book"):
		get_viewport().set_input_as_handled()
		close_book()
	elif event.is_action("ui_left"):
		get_viewport().set_input_as_handled()
		_flip(-1)
	elif event.is_action("ui_right"):
		get_viewport().set_input_as_handled()
		_flip(1)


# --- build -------------------------------------------------------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/icons/icons.json"))
	if typeof(meta) == TYPE_DICTIONARY:
		_icon_names = meta.get("icons", {})

	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(holder)

	var di := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	di.fill(Color(0, 0, 0, 0))
	di.set_pixel(0, 0, INK)
	di.set_pixel(1, 1, INK)
	_dim = TextureRect.new()
	_dim.texture = ImageTexture.create_from_image(di)
	_dim.stretch_mode = TextureRect.STRETCH_TILE
	_dim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_dim)

	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 7)
	_panel.custom_minimum_size = Vector2(456, 256)
	_panel.size = Vector2(456, 256)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = FRAME
	sb.set_border_width_all(3)
	sb.set_content_margin_all(6)
	sb.anti_aliasing = false
	_panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	_panel.add_child(vb)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	vb.add_child(top)
	for i in 2:
		var b := _button(tr("BOOK_TAB_RECIPES") if i == 0 else tr("BOOK_TAB_VARIETIES"))
		b.toggle_mode = true
		b.pressed.connect(_set_tab.bind(i))
		top.add_child(b)
		_tab_btns.append(b)
	var title := _label(FONT_TITLE, 18, TEXT)
	title.text = tr("BOOK_TITLE")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	_close = _button(tr("BOOK_CLOSE"))
	_close.pressed.connect(close_book)
	top.add_child(_close)

	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 4)
	vb.add_child(pages)
	_left = _page_box()
	pages.add_child(_left)
	var spine := ColorRect.new()
	spine.color = PAPER_DK
	spine.custom_minimum_size = Vector2(2, 0)
	pages.add_child(spine)
	_right = _page_box()
	pages.add_child(_right)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 4)
	vb.add_child(bottom)
	_milestone = _label(FONT_BODY, 16, TEXT)
	_milestone.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_milestone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_milestone)
	_prev = _button("<")
	_prev.pressed.connect(_flip.bind(-1))
	bottom.add_child(_prev)
	_page_label = _label(FONT_BODY, 16, TEXT)
	_page_label.custom_minimum_size.x = 36
	bottom.add_child(_page_label)
	_next = _button(">")
	_next.pressed.connect(_flip.bind(1))
	bottom.add_child(_next)


func _page_box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(PAGE_W, PAGE_H)
	v.add_theme_constant_override("separation", 2)
	v.clip_contents = true
	return v


func _label(font: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", FONT_BODY)
	b.add_theme_font_size_override("font_size", 16)
	for c in ["font_color", "font_focus_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, PAPER if c != "font_hover_color" else Color("dbcc83"))
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var bs := StyleBoxFlat.new()
		bs.bg_color = FRAME if st != "pressed" else TEXT
		if st == "disabled":
			bs.bg_color = PAPER_DK
		bs.border_color = TEXT if st != "focus" else GOLD
		bs.set_border_width_all(2 if st == "focus" else 1)
		bs.content_margin_left = 6
		bs.content_margin_right = 6
		bs.content_margin_top = 1
		bs.content_margin_bottom = 1
		bs.anti_aliasing = false
		b.add_theme_stylebox_override(st, bs)
	return b


# --- state -------------------------------------------------------------------------------------------------------

func _set_tab(i: int) -> void:
	_tab = i
	_page = 0
	_refresh()


func _flip(d: int) -> void:
	var n := _page_count()
	var np := clampi(_page + d, 0, maxi(n - 1, 0))
	if np != _page:
		_page = np
		_refresh()


func _variant_keys() -> Array:
	var vs: Dictionary = _data().get("book", {}).get("variants", {})
	var keys: Array = vs.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var da := int(vs[a].get("first_day", 0))
		var db := int(vs[b].get("first_day", 0))
		return da < db or (da == db and a < b))
	return keys


func _types() -> Array:
	var ings := Data.ingredients()
	var out: Array = []
	for t: String in Data.ids_up_to("ingredients", 0):
		if ings[t].group != "nut":
			out.append(t)
	var order := _icon_names.keys()
	out.sort_custom(func(a: String, b: String) -> bool: return order.find(a) < order.find(b))
	return out


func _page_count() -> int:
	if _tab == 0:
		return maxi(ceili(_variant_keys().size() / float(VARIANTS_PER_PAGE)), 1)
	return maxi(ceili(_types().size() / float(TYPES_PER_PAGE * 2)), 1)


func _refresh() -> void:
	for i in 2:
		_tab_btns[i].set_pressed_no_signal(i == _tab)
	for pg in [_left, _right]:
		for c in pg.get_children():
			pg.remove_child(c)
			c.queue_free()
	if _tab == 0:
		_fill_recipes()
	else:
		_fill_varieties()
	var n := _page_count()
	_prev.disabled = _page <= 0
	_next.disabled = _page >= n - 1
	_prev.visible = n > 1
	_next.visible = n > 1
	_page_label.visible = n > 1
	_page_label.text = "%d/%d" % [_page + 1, n]
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_milestone()


func _update_milestone() -> void:
	var n := _variant_keys().size()
	var text := tr("BOOK_DISCOVERED") % n
	var nxt := 0
	for m: int in MILESTONES:
		if n < m:
			nxt = m
			break
	if nxt > 0:
		text += "  -  " + (tr("BOOK_NEXT_MILESTONE") % nxt)
	else:
		text += "  -  " + tr("BOOK_ALL_MILESTONES")
	_milestone.text = text


# --- recipes tab -------------------------------------------------------------------------------------------------

func _heading(box: Control, text: String) -> Label:
	var l := _label(FONT_TITLE, 18, GOLD_DK)
	l.text = text
	box.add_child(l)
	return l


func _fill_recipes() -> void:
	_heading(_left, tr("BOOK_BASE_RECIPES"))
	var recipes := Data.recipes()
	for id: String in RECIPE_ORDER:
		if recipes.has(id):
			_left.add_child(_recipe_entry(id, recipes[id]))
	_heading(_right, tr("BOOK_VARIANTS"))
	var keys := _variant_keys()
	if keys.is_empty():
		var l := _label(FONT_BODY, 16, TEXT)
		l.text = tr("BOOK_EMPTY")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_right.add_child(l)
		return
	var vs: Dictionary = _data().book.variants
	for i in range(_page * VARIANTS_PER_PAGE, mini(keys.size(), (_page + 1) * VARIANTS_PER_PAGE)):
		_right.add_child(_variant_row(keys[i], vs[keys[i]]))


func _recipe_entry(id: String, r: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var name_l := _label(FONT_BODY, 16, TEXT)
	name_l.text = "%s  (%s)" % [tr("BOOK_RECIPE_" + id.to_upper()), tr("BOOK_METHOD_" + String(r.method).to_upper())]
	v.add_child(name_l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	v.add_child(row)
	_add_slot(row, r.get("main"))
	if r.has("second"):
		_plus(row)
		_add_slot(row, r.second)
	_plus(row)
	for item: String in r.get("base", {}):
		_icon(row, item)
	return v


func _plus(row: Control) -> void:
	var l := _label(FONT_BODY, 16, GOLD_DK)
	l.text = "+"
	row.add_child(l)


func _add_slot(row: Control, slot: Variant) -> void:
	if typeof(slot) != TYPE_DICTIONARY:
		return
	var ings := Data.ingredients()
	var names: Array = []
	if slot.has("types"):
		names = slot.types
	elif slot.has("groups"):
		for t: String in _icon_names:
			if ings.has(t) and int(ings[t].get("priority", 0)) == 0 and slot.groups.has(ings[t].group):
				names.append(t)
	elif slot.has("recipe"):
		var l := _label(FONT_BODY, 16, TEXT)
		l.text = tr("BOOK_RECIPE_" + String(slot.recipe).to_upper())
		row.add_child(l)
	for t in names:
		if int(ings.get(t, {}).get("priority", 0)) == 0:
			_icon(row, t)
	var c := _label(FONT_BODY, 16, TEXT)
	c.text = "x%d" % int(slot.get("count", 1))
	row.add_child(c)


func _icon(row: Control, icon_name: String, tint := Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(16, 16)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.stretch_mode = TextureRect.STRETCH_KEEP
	t.modulate = tint
	var path := "res://assets/sprites/icons/%s.png" % icon_name
	if _icon_names.has(icon_name) and ResourceLoader.exists(path):
		t.texture = load(path)
	row.add_child(t)
	return t


func _variant_row(key: String, rec: Dictionary) -> Control:
	var vars: Dictionary = _data().get("varieties", {})
	var desc := ProductGen.describe(key, vars)
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, ROW_H)
	h.add_theme_constant_override("separation", 4)
	var jb := CenterContainer.new()
	jb.custom_minimum_size = Vector2(28, ROW_H)
	var jar := JarIcon.new()
	jar.view = "shelf"
	jb.add_child(jar)
	jar.show_product(desc)
	h.add_child(jb)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(mid)
	var nm := _label(FONT_BODY, 16, TEXT)
	nm.text = String(desc.name)
	nm.clip_text = true
	mid.add_child(nm)
	var bs := int(rec.get("best_stars", 0))
	var bq := clampi(int(rec.get("best_q", 0)), 0, 3)
	var sr := ResultCard.StarRow.new()
	sr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mid.add_child(sr)
	sr.set_stars(bq, clampi(bs - bq, 0, 2))
	var pl := _label(FONT_BODY, 16, TEXT)
	pl.text = "%s  x%d" % [desc.profile_label, int(rec.get("count", 1))]
	pl.clip_text = true
	mid.add_child(pl)
	var ch := BarChart.new()
	ch.set_taste(desc.taste)
	h.add_child(ch)
	return h


# --- varieties tab -----------------------------------------------------------------------------------------------

func _fill_varieties() -> void:
	var types := _types()
	var base := _page * TYPES_PER_PAGE * 2
	_heading(_left, tr("BOOK_TAB_VARIETIES"))
	var cnt := _heading(_right, "%d/%d" % [_found_count(), _total_count()])
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for i in TYPES_PER_PAGE * 2:
		if base + i >= types.size():
			break
		(_left if i < TYPES_PER_PAGE else _right).add_child(_type_block(types[base + i]))


func _by_type(type: String) -> Array:
	var out: Array = []
	var vs: Dictionary = _data().get("varieties", {})
	for id: String in vs:
		if vs[id].get("type", "") == type:
			out.append(vs[id])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("tier", 0)) < int(b.get("tier", 0)))
	return out


func _found_count() -> int:
	return _data().get("found_varieties", []).size()


func _total_count() -> int:
	return _data().get("varieties", {}).size()


func _type_block(type: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	v.add_child(head)
	_icon(head, type)
	var tl := _label(FONT_TITLE, 18, TEXT)
	tl.text = tr("BOOK_TYPE_" + type.to_upper())
	head.add_child(tl)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 2)
	v.add_child(cells)
	var found: Array = _data().get("found_varieties", [])
	for variety: Dictionary in _by_type(type):
		cells.add_child(_variety_cell(variety, found.has(variety.id)))
	return v


func _variety_cell(variety: Dictionary, found: bool) -> Control:
	var c := VBoxContainer.new()
	c.custom_minimum_size = Vector2(50, 0)
	c.add_theme_constant_override("separation", 0)
	var ib := HBoxContainer.new()
	ib.alignment = BoxContainer.ALIGNMENT_CENTER
	ib.add_theme_constant_override("separation", 1)
	c.add_child(ib)
	var type := String(variety.type)
	if found:
		_icon(ib, type)
		ib.add_child(SwatchBar.new().setup(ProductGen.fill_tones(variety, "")))
	else:
		_icon(ib, type, SILHOUETTE)
	var nm := _label(FONT_BODY, 16, TEXT if found else PAPER_DK)
	nm.text = _short_name(variety) if found else tr("BOOK_UNKNOWN")
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.custom_minimum_size.x = 50
	c.add_child(nm)
	var rl := _label(FONT_BODY, 16, PAPER_DK)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.custom_minimum_size.x = 50
	if found:
		var rar := String(variety.get("rarity", "common"))
		rl.text = tr("BOOK_RARITY_" + rar.to_upper())
		rl.add_theme_color_override("font_color", {"common": TEXT, "uncommon": GREEN, "rare": RED}.get(rar, TEXT))
	else:
		rl.text = " "
	c.add_child(rl)
	return c


## "Ember Apple" -> "Ember" (the type is already in the block heading).
func _short_name(variety: Dictionary) -> String:
	var n := String(variety.get("name", "?"))
	var suffix := " " + String(variety.get("type", "")).replace("_", " ")
	if n.to_lower().ends_with(suffix):
		n = n.substr(0, n.length() - suffix.length())
	return n


# --- widgets -----------------------------------------------------------------------------------------------------

## 5 vertical bars, one per taste axis (value 0..9, 2 px per step).
class BarChart extends Control:
	var taste: Array = [0, 0, 0, 0, 0]

	func _init() -> void:
		custom_minimum_size = Vector2(33, 0)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_taste(t: Array) -> void:
		taste = t
		var parts: PackedStringArray = []
		for i in 5:
			parts.append("%s %d" % [tr("UI_TASTE_" + ResultCard.AXES[i].to_upper()), int(t[i])])
		tooltip_text = ", ".join(parts)
		queue_redraw()

	func _draw() -> void:
		var base := int(size.y * 0.5) + 10
		draw_rect(Rect2(0, base, 33, 1), ResultCard.FRAME)
		for i in 5:
			var v := clampi(int(taste[i]), 0, 9)
			draw_rect(Rect2(i * 6 + 1, base - 19, 5, 19), ResultCard.EMPTY)
			if v > 0:
				draw_rect(Rect2(i * 6 + 1, base - v * 2 - 1, 5, v * 2 + 1), ResultCard.AXIS_COLORS[i])


## Three stacked fill tones of a variety (palette hex strings).
class SwatchBar extends Control:
	var tones: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(4, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(t: Array) -> SwatchBar:
		tones = t
		queue_redraw()
		return self

	func _draw() -> void:
		for i in tones.size():
			draw_rect(Rect2(0, 2 + i * 4, 4, 4), Color.html(String(tones[i])))
