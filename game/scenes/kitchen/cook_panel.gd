extends Panel
## GD-KITCHEN · Cook panel (spec §7.2) for one station. JURY-STOVE: it reads in five seconds, left to right, under the
## recipe tabs (name + one plain line of what it needs):
##   what goes in | what you make | the action.
##   Left: one slot per ingredient ("Fruit ×3 ... you have 5" over the chosen variety; a click opens the Change picker),
##   "Also:" the cupboard staples, "Extra (optional)": None or an add-in, one line about it on hover or focus.
##   Middle: the jar at 2x, its name ("Something new..." until the book has it), New!, ~value, five taste bars.
##   Right: the reason in words when it cannot cook, Cook! (energy icon + cost); x1/x2 and Batch cook under it.
## Opening a station picks for the player (CookPick: the first recipe that can cook now, a variant not in the book
## first), so the first press of Cook just works; a choice made by hand is kept while it can still cook.
## Keys: Enter cooks (focus starts on Cook), left / right switch recipes, up / down walk slots, extras and Cook.
## Rules stay in Kitchen/ProductGen: this panel only routes picks and shows what Kitchen.check_n() answers.
## P1: stations "press" and "knead"; a recipe slot (syrup: 2 juices) lists matured products of that recipe by their
## fruit variety (Kitchen.product_stock); a recipe without slots (bread) only needs the cupboard.
## KITCHEN-P1B: x1/x2 (big pot, stove recipes once "big_pot" is bought; `mult`) and "Batch cook" once the recipe has
## a Mastered variant (ready only when the picked variant is Mastered), both under Cook.
## KITCHEN-P1C: once a family recipe of this station is unlocked, a gold "Family recipes" button by Back swaps the tabs
## between the base recipes and the family ones (`family`); a family recipe's add-in row holds only its fixed add-in.
## FORMULA-KITCHEN: an "Invent" button left of them asks the kitchen for the invent panel (invent_requested).

signal cook_requested(recipe_id: String, main_variety: String, second_variety: String, addin_id: String)
signal batch_requested(recipe_id: String, main_variety: String, second_variety: String, addin_id: String)
signal close_requested
signal invent_requested(station_id: String)

const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const CookPick := preload("res://scenes/kitchen/cook_pick.gd")
const W := 464
const H := 236
const TAB_H := 38
const SLOTS := ["main", "second"]
const MULT_W := 20
const FAMILY_W := 112
## Three columns under the tabs: what goes in | what you make | the action.
const TOP := 74
const LEFT_X := 8
const LEFT_W := 220
const MID_X := 234
const MID_W := 100
const RIGHT_X := 340
const RIGHT_W := 116
const SLOT_H := 36
const JAR_Y := 112
const TASTE_Y := 166
const PICK_ROW_H := 20
const ICON_ENERGY := "res://assets/sprites/ui/icon_energy.png"
const ICON_COIN := "res://assets/sprites/ui/icon_coin.png"

var station := ""
var recipe := ""
var picks := {"main": "", "second": ""}
var addin := ""
var home := Vector2(8, 30)
## Pots per cook: 2 once the big pot is bought and x2 is picked (stove recipes only).
var mult := 1
## True while the tabs show this station's unlocked family recipes instead of the base ones.
var family := false

var _recipes: Array = []
var _hand := false  ## the player changed something by hand: kept on the next open while it can still cook
var _hand_slots := {}  ## slot -> true once the player chose its variety: it stays when the recipe changes
var _title: Label
var _back: Button
var _family_btn: Button
var _tab_box: Control
var _tabs: Dictionary = {}  # recipe id -> Button
var _inputs: Control  # left column
var _slots: Dictionary = {}  # "main"/"second" -> {"button", "caption", "have", "icon", "name"}
var _no_slots: Label
var _also: Label
var _addin_label: Label
var _addin_box: Control
var _addin_desc: Label
var _addin_buttons: Dictionary = {}  # add-in id ("" = none) -> Button
var _preview: Control  # middle column
var _preview_name: Label
var _preview_jar: JarIcon
var _preview_unknown: Label
var _new_tag: Label
var _value_icon: TextureRect
var _value: Label
var _taste: TasteBars
var _feedback: Label
var _missing_row: HBoxContainer
var _cook: Button
var _cook_word: Label
var _cook_cost: Label
var _extras: Control
var _mult_buttons: Dictionary = {}  # 1 / 2 -> Button
var _batch: Button
var _picker: Panel
var _picker_slot := ""
var _picker_title: Label
var _picker_back: Button
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Dictionary = {}  # variety id -> Button (picker rows)
var _batch_ok := false
var _ok := false
var _tween: Tween
var _product_icons := {}  # product key -> 16x16 JarIcon texture
var _invent: Button
var _invent_arrow: InventArrow


func _ready() -> void:
	add_to_group("modal_card")  # the To-Do note hides while this is open
	_build()


# ---------------------------------------------------------------- pure helpers (state in, plain data out)

## Recipes this save can cook with `method` (Kitchen.recipes_at): P0 first, then unlocked P1, then family.
static func recipes_for(method: String) -> Array:
	return Kitchen.recipes_at(GameState.data, method)


## The tab set: `method`'s base recipes, or its unlocked family recipes when `family_set`.
static func tab_recipes(method: String, family_set: bool) -> Array:
	return recipes_for(method).filter(func(id: String) -> bool: return Kitchen.is_family(id) == family_set)


## Fresh units per variety id in the inbox and the pantry.
static func fresh_stock(d: Dictionary) -> Dictionary:
	return CookPick.fresh_stock(d)


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


## Add-ins the picker offers, in data order: every add-in the player has in hand, whatever its priority (shop
## spices, P1 nuts, Edith's gifted mint). Unowned ones stay hidden; the grocer hint covers buying more.
static func available_addins(d: Dictionary) -> Array:
	var out: Array = []
	for id: String in Data.addins():
		if addin_count(d, id) > 0:
			out.append(id)
	return out


static func _all_items(d: Dictionary) -> Array:
	var out: Array = d.inbox.duplicate()
	for e: Dictionary in d.pantry.items:
		out.append(e.item)
	return out


## True when the book holds a Mastered variant of `recipe_id` (Batch cook belongs on its tab).
static func recipe_has_mastered(d: Dictionary, recipe_id: String) -> bool:
	var vs: Dictionary = d.get("book", {}).get("variants", {})
	for key: String in vs:
		if key.begins_with(recipe_id + "|") and Kitchen.entry_mastered(vs[key]):
			return true
	return false


# ---------------------------------------------------------------- open / refresh

func open(station_id: String) -> void:
	if station_id != station:
		station = station_id
		recipe = ""
		picks = {"main": "", "second": ""}
		addin = ""
		family = false
		_hand = false
		_hand_slots = {}
	_close_picker(false)
	_build_tabs()  # every time: a new unlock can add a tab (syrup once the press is bought, a family recipe)
	if not _recipes.has(recipe):
		recipe = _recipes[0] if not _recipes.is_empty() else ""
	var d := GameState.data
	for which in SLOTS:
		if picks[which] != "" and int(_slot_stock(which).get(picks[which], 0)) == 0:
			picks[which] = ""
	if addin != "" and addin_count(d, addin) == 0:
		addin = ""
	if not (_hand and _can_cook_now()):
		_auto_pick()
	var titles := {"stir_pot": "KITCHEN_STOVE", "pack_jar": "KITCHEN_COUNTER", "press": "KITCHEN_PRESS", "knead": "KITCHEN_BOARD"}
	_title.text = tr(String(titles.get(station, "KITCHEN_STOVE")))
	visible = true
	refresh()
	_slide_in()
	_cook.grab_focus()


## Rebuilds everything that depends on the save (stock, add-ins, check). Keeps keyboard focus where it was.
func refresh() -> void:
	if recipe == "" or GameState.data.is_empty():
		return
	var fixed: Variant = Kitchen.fixed_addin(recipe)
	if fixed != null:
		addin = String(fixed)
	var fk := _focus_key()
	_update_tabs()
	_update_extras()
	_update_slots()
	_build_addins()
	_update_check()
	if _picker.visible:
		_build_list()
	_link_focus()
	_restore_focus(fk)


## CookPick's choice: the first recipe that can cook now, best varieties, a variant not in the book first.
func _auto_pick() -> void:
	if family:
		family = false
		_build_tabs()
	var best := CookPick.best_recipe(GameState.data, _recipes, mult)
	if best.is_empty():
		return
	recipe = String(best.recipe)
	picks = {"main": String(best.main), "second": String(best.second)}
	addin = String(best.addin)
	if Kitchen.max_mult(GameState.data, recipe) > 1:
		mult = int(best.mult)
	_hand = false
	_hand_slots = {}


func _can_cook_now() -> bool:
	if recipe == "":
		return false
	return bool(Kitchen.check_n(GameState.data, recipe, _main(), _second(), addin, mult).ok)


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
	_family_btn = Button.new()
	_family_btn.position = Vector2(W - 58 - 6 - FAMILY_W, 3)
	_family_btn.size = Vector2(FAMILY_W, 26)
	_family_btn.tooltip_text = tr("UI_FAMILY_TIP")
	_family_btn.visible = false
	_family_btn.pressed.connect(_toggle_family)
	add_child(_family_btn)
	var invent := Button.new()  # FORMULA-KITCHEN
	_invent = invent
	invent.text = tr("UI_FORMULA_INVENT")
	invent.tooltip_text = tr("UI_FORMULA_INVENT_TIP")
	invent.position = Vector2(W - 58 - 6 - FAMILY_W - 6 - 80, 3)
	invent.size = Vector2(80, 26)
	invent.pressed.connect(func() -> void: invent_requested.emit(station))
	add_child(invent)
	_invent_arrow = InventArrow.new()  # FIX-JURY-B
	add_child(_invent_arrow)

	_tab_box = Control.new()
	_tab_box.position = Vector2(8, 32)
	_tab_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tab_box)

	_build_inputs()
	_build_preview()
	_build_action()
	_build_extras()
	_build_picker()


## Left column: the slots, the cupboard line, the Extra row and its one-line description.
func _build_inputs() -> void:
	_inputs = _layer()
	for which: String in SLOTS:
		_make_slot(which)
	_no_slots = _label(_inputs, Vector2(LEFT_X, TOP), LEFT_W)
	_no_slots.size.y = 36
	_no_slots.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_also = _label(_inputs, Vector2(LEFT_X, TOP), LEFT_W)
	_also.add_theme_color_override("font_color", Art.CREAM_LO)
	_addin_label = _label(_inputs, Vector2(LEFT_X, TOP), LEFT_W)
	_addin_label.text = tr("UI_COOK_EXTRA")
	_addin_label.add_theme_color_override("font_color", Art.GOLD)
	_addin_box = Control.new()
	_addin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inputs.add_child(_addin_box)
	_addin_desc = _label(_inputs, Vector2(LEFT_X, TOP), LEFT_W)
	_addin_desc.add_theme_color_override("font_color", Art.CREAM_LO)


func _make_slot(which: String) -> void:
	var b := Button.new()
	b.size = Vector2(LEFT_W, SLOT_H)
	b.tooltip_text = tr("UI_COOK_CHANGE_TIP")
	_style(b, false)
	b.pressed.connect(_on_slot_pressed.bind(which))
	_inputs.add_child(b)
	var cap := _label(b, Vector2(5, 0), LEFT_W - 10)
	cap.add_theme_color_override("font_color", Art.GOLD)
	var have := _label(b, Vector2(5, 0), LEFT_W - 10)
	have.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var ic := TextureRect.new()
	ic.position = Vector2(5, 18)
	ic.size = Vector2(16, 16)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var nm := _label(b, Vector2(24, 18), LEFT_W - 40)
	# a little chevron at the right: this opens a choice
	var chev := Control.new()
	chev.position = Vector2(LEFT_W - 12, 22)
	chev.size = Vector2(4, 7)
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chev.draw.connect(func() -> void:
		for i in 4:
			chev.draw_rect(Rect2(i, i, 1, 7 - 2 * i), Art.GOLD))
	b.add_child(chev)
	_slots[which] = {"button": b, "caption": cap, "have": have, "icon": ic, "name": nm}


## Middle column: what the pot will make.
func _build_preview() -> void:
	_preview = _layer()
	var frame := Panel.new()
	frame.position = Vector2(MID_X - 3, TOP - 2)
	frame.size = Vector2(MID_W + 6, H - TOP - 2)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _box(Art.IRON_DK, Art.BROWN, 1))
	_preview.add_child(frame)
	_preview_name = _label(_preview, Vector2(MID_X, TOP), MID_W)
	_preview_name.size.y = 36
	_preview_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_name.max_lines_visible = 2
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_jar = JarIcon.new()
	_preview_jar.view = "shelf"
	_preview_jar.zoom = 2
	_preview_jar.position = Vector2(MID_X + 2, JAR_Y)
	_preview.add_child(_preview_jar)
	_preview_unknown = Label.new()
	_preview_unknown.theme_type_variation = &"Heading"
	_preview_unknown.text = "?"
	_preview_unknown.position = Vector2(MID_X + 2, JAR_Y)
	_preview_unknown.size = Vector2(48, 48)
	_preview_unknown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_unknown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_unknown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.add_child(_preview_unknown)
	_new_tag = _label(_preview, Vector2(MID_X + 54, JAR_Y + 2), 40)
	_new_tag.text = tr("UI_COOK_NEW")
	_new_tag.size = Vector2(_text_w(_new_tag.text) + 6, 18)
	_new_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_new_tag.add_theme_color_override("font_color", Art.INK)
	_new_tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))  # no ink shadow on the gold pill
	_new_tag.add_theme_stylebox_override("normal", _box(Art.GOLD, Art.GOLD, 0, 0))
	_new_tag.tooltip_text = tr("UI_COOK_NEW_TIP")
	_new_tag.mouse_filter = Control.MOUSE_FILTER_PASS
	_value_icon = TextureRect.new()
	_value_icon.texture = load(ICON_COIN)
	_value_icon.position = Vector2(MID_X + 54, JAR_Y + 27)
	_value_icon.size = Vector2(16, 16)
	_value_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.add_child(_value_icon)
	_value = _label(_preview, Vector2(MID_X + 71, JAR_Y + 26), MID_W - 71)
	_value.mouse_filter = Control.MOUSE_FILTER_PASS
	_taste = TasteBars.new()
	_taste.position = Vector2(MID_X, TASTE_Y)
	_taste.size = Vector2(MID_W, 5 * TasteBars.ROW)
	_preview.add_child(_taste)


## Right column: why it cannot cook (in words), then Cook!, the biggest and warmest button.
func _build_action() -> void:
	_feedback = _label(self, Vector2(RIGHT_X, TOP), RIGHT_W)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_missing_row = HBoxContainer.new()
	_missing_row.add_theme_constant_override("separation", 1)
	_missing_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_missing_row)
	_cook = Button.new()
	_cook.position = Vector2(RIGHT_X, 184)
	_cook.size = Vector2(RIGHT_W, 48)
	_cook.pressed.connect(_on_cook)
	add_child(_cook)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cook.add_child(row)
	_cook_word = Label.new()
	_cook_word.text = tr("UI_COOK_GO")
	_cook_word.add_theme_font_size_override("font_size", 36)
	_cook_word.add_theme_color_override("font_shadow_color", Art.INK)
	_cook_word.add_theme_constant_override("shadow_offset_x", 2)
	_cook_word.add_theme_constant_override("shadow_offset_y", 2)
	_cook_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_cook_word)
	var bolt := TextureRect.new()
	bolt.texture = load(ICON_ENERGY)
	bolt.custom_minimum_size = Vector2(16, 16)
	bolt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bolt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bolt)
	_cook_cost = Label.new()
	_cook_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cook_cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_cook_cost)


## Under Cook: x1 / x2 (big pot) and Batch cook (Mastered variants). Shown by _update_extras().
func _build_extras() -> void:
	_extras = Control.new()
	_extras.size = Vector2(RIGHT_W, 24)
	_extras.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_extras.visible = false
	add_child(_extras)
	for n in [1, 2]:
		var b := Button.new()
		b.text = tr("UI_BATCH_TIMES") % n
		b.position = Vector2((n - 1) * (MULT_W + 2), 0)
		b.size = Vector2(MULT_W, 24)
		b.tooltip_text = tr("UI_BATCH_POT_TIP")
		b.pressed.connect(_select_mult.bind(n))
		_extras.add_child(b)
		_mult_buttons[n] = b
	_batch = Button.new()
	_batch.text = tr("UI_BATCH_COOK")
	_batch.size = Vector2(RIGHT_W, 24)
	_batch.tooltip_text = tr("UI_MASTERY_TIP")
	_batch.pressed.connect(_on_batch)
	_extras.add_child(_batch)


## The Change picker: over the left and middle columns, the varieties one slot can take, best first.
func _build_picker() -> void:
	_picker = Panel.new()
	_picker.position = Vector2(LEFT_X - 2, TOP - 2)
	_picker.size = Vector2(MID_X + MID_W + 4 - LEFT_X, H - TOP)
	_picker.add_theme_stylebox_override("panel", _box(Art.IRON_DK, Art.GOLD, 1, 2))
	_picker.visible = false
	add_child(_picker)
	_picker_title = _label(_picker, Vector2(6, 3), int(_picker.size.x) - 66)
	_picker_title.add_theme_color_override("font_color", Art.GOLD)
	_picker_back = Button.new()
	_picker_back.text = tr("UI_BACK")
	_picker_back.position = Vector2(_picker.size.x - 56, 2)
	_picker_back.size = Vector2(52, 22)
	_picker_back.pressed.connect(_close_picker.bind(true))
	_picker.add_child(_picker_back)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(4, 27)
	_scroll.size = Vector2(_picker.size.x - 8, _picker.size.y - 31)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bar := _scroll.get_v_scroll_bar()
	bar.add_theme_stylebox_override("scroll", _box(Art.PLUM, Art.PLUM, 0, 3))
	bar.add_theme_stylebox_override("scroll_focus", _box(Art.PLUM, Art.PLUM, 0, 3))
	bar.add_theme_stylebox_override("grabber", _box(Art.BROWN, Art.BROWN, 0, 3))
	bar.add_theme_stylebox_override("grabber_highlight", _box(Art.TAN, Art.TAN, 0, 3))
	bar.add_theme_stylebox_override("grabber_pressed", _box(Art.AMBER, Art.AMBER, 0, 3))
	_picker.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 1)
	_list.custom_minimum_size = Vector2(_row_w(), 0)
	_scroll.add_child(_list)


func _build_tabs() -> void:
	for c in _tab_box.get_children():
		_tab_box.remove_child(c)
		c.queue_free()
	_tabs.clear()
	var has_family := not tab_recipes(station, true).is_empty()
	if not has_family:
		family = false
	_recipes = tab_recipes(station, family)
	_family_btn.visible = has_family
	_family_btn.text = tr("UI_FAMILY_BASE") if family else tr("UI_FAMILY_TAB")
	_style(_family_btn, family)
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		_family_btn.add_theme_color_override(k, Art.GOLD)
	var widths := _tab_widths(_recipes)
	var x := 0
	for i in _recipes.size():
		var id: String = _recipes[i]
		var w: int = widths[i]
		var b := Button.new()
		b.position = Vector2(x, 0)
		b.size = Vector2(w, TAB_H)
		b.clip_contents = true
		b.focus_mode = Control.FOCUS_NONE  # keys: left / right switch recipes from anywhere, Enter cooks
		b.pressed.connect(_select_recipe.bind(id))
		_tab_box.add_child(b)
		x += w + 5
		_tabs[id] = b
		if Kitchen.is_family(id):
			_family_tab(b, id, w)
			continue
		var nm := _label(b, Vector2(6, 1), w - 12)
		nm.text = ProductGen.recipe_name(id)
		var need := _label(b, Vector2(6, 19), w - 12)
		need.text = _need_line(id)
		need.add_theme_color_override("font_color", Art.CREAM_LO)
		b.tooltip_text = "%s: %s" % [nm.text, need.text]


## Tab widths: each base tab as wide as its name or need line, the rest of the row shared out; equal widths when
## that does not fit (family tabs wrap their names, so they share equally).
func _tab_widths(ids: Array) -> Array:
	var n := maxi(ids.size(), 1)
	var avail := W - 16 - 5 * (n - 1)
	var mins: Array = []
	var total := 0
	var all_base := true
	for id: String in ids:
		if Kitchen.is_family(id):
			all_base = false
			mins.append(0)
			continue
		var m := ceili(maxf(_text_w(ProductGen.recipe_name(id)), _text_w(_need_line(id)))) + 12
		mins.append(m)
		total += m
	var out: Array = []
	if not all_base or total > avail:
		for id in ids:
			out.append(floori(avail / float(n)))
		return out
	var extra := floori((avail - total) / float(n))
	for m: int in mins:
		out.append(m + extra)
	return out


## A family recipe tab: its letter name in gold over up to two lines, and its gold-label jar in the top right corner
## (first lines stay short of it: "Granny's", "Blackberry", "Pepper Relish"; the slots and the add-in row below say
## what goes in).
func _family_tab(b: Button, id: String, tab_w: int) -> void:
	var nm := _label(b, Vector2(5, 1), tab_w - 21)
	nm.size.y = TAB_H - 2
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.text = tr("LET_RECIPE_" + id.to_upper())
	nm.add_theme_color_override("font_color", Art.GOLD)
	var r: Dictionary = Data.recipes()[id]
	var types: Array = r.main.get("types", [])
	var jar := JarIcon.new()
	jar.view = "icon"
	jar.position = Vector2(tab_w - 18, 3)
	b.add_child(jar)
	jar.show_product(ProductGen.describe(ProductGen.make_key(id, types.slice(0, 1), String(r.get("fixed_addin", ""))), {}))
	b.tooltip_text = "%s: %s" % [nm.text, _need_line(id)]


## The add-in row: None, then an icon per add-in in hand. Each says what it does on hover or focus.
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
	var fixed: Variant = Kitchen.fixed_addin(recipe)
	if fixed != null:  # a family recipe: its own add-in (or none), shown even when the cupboard has none
		ids = [String(fixed)]
	var none_w := ceili(_text_w(tr("KITCHEN_NONE"))) + 10
	var icons := ids.size() - (1 if ids.has("") else 0)
	var each := clampi(floori((LEFT_W - none_w - 2) / float(maxi(icons, 1))) - 2, 16, 24)
	var x := 0
	for id: String in ids:
		var b := Button.new()
		var w := none_w if id == "" else each
		b.position = Vector2(x, 0)
		b.size = Vector2(w, 24)
		if id == "":
			b.text = tr("KITCHEN_NONE")
		else:
			b.icon = Art.icon(id)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.expand_icon = false
		b.tooltip_text = _addin_line(id)
		_style(b, id == addin)
		b.pressed.connect(_select_addin.bind(id))
		b.mouse_entered.connect(_show_addin_line.bind(id))
		b.focus_entered.connect(_show_addin_line.bind(id))
		b.mouse_exited.connect(_show_addin_line.bind(null))
		b.focus_exited.connect(_show_addin_line.bind(null))
		_addin_box.add_child(b)
		_addin_buttons[id] = b
		x += w + 2
	_show_addin_line(null)


## The Change picker's rows: what fits the open slot, best first (a new variant, rarer, worth more, more of it).
func _build_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	var which := _picker_slot
	var spec: Variant = _spec(which)
	if spec == null:
		return
	var d := GameState.data
	var need := int(spec.count) * mult
	var other := "second" if which == "main" else "main"
	var pin := {}
	if _spec(other) != null and picks[other] != "":
		pin[other] = picks[other]
	var seen := {}
	var rw := _row_w()
	for f: Dictionary in CookPick.fills(d, recipe, addin, mult, pin):
		var vid := String(f[which])
		if vid == "" or seen.has(vid):
			continue
		seen[vid] = true
		var have := int(f.have.get(which, 0))
		var enough := have >= need
		var b := Button.new()
		b.custom_minimum_size = Vector2(rw, PICK_ROW_H)
		_style_row(b, vid == picks[which])
		b.pressed.connect(_choose.bind(vid))
		_list.add_child(b)
		var ic := TextureRect.new()
		ic.texture = _row_icon(vid, which)
		ic.position = Vector2(3, 2)
		ic.size = Vector2(16, 16)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		var nm := _label(b, Vector2(22, 1), rw - 140)
		nm.text = _variety_name(vid)
		nm.add_theme_color_override("font_color", Art.CREAM if enough else Art.MUTED)
		if bool(f.new):
			var tag := _label(b, Vector2(rw - 114, 1), 34)
			tag.text = tr("UI_COOK_NEW")
			tag.add_theme_color_override("font_color", Art.GOLD)
		var cnt := _label(b, Vector2(rw - 80, 1), 76)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.text = tr("UI_COOK_HAVE") % have
		cnt.add_theme_color_override("font_color", Art.CREAM_LO if enough else Art.PEACH)
		_rows[vid] = b
	if _rows.is_empty():
		var empty := Label.new()
		empty.text = tr(_empty_list_key())
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(rw, 54)
		_list.add_child(empty)
	var rows: Array = _rows.values()
	for i in rows.size():  # up / down walk the rows; the ends stop
		var b: Button = rows[i]
		b.focus_neighbor_top = b.get_path_to(rows[i - 1] if i > 0 else _picker_back)
		b.focus_neighbor_bottom = b.get_path_to(rows[i + 1] if i < rows.size() - 1 else b)
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)


# ---------------------------------------------------------------- updates

func _update_tabs() -> void:
	for id in _tabs:
		var b: Button = _tabs[id]
		_style(b, id == recipe)
		if not Kitchen.is_family(id) and b.get_child_count() > 0:
			(b.get_child(0) as Label).add_theme_color_override("font_color", Art.GOLD if id == recipe else Art.CREAM)


## x1/x2 where the big pot applies and Batch cook once this recipe has a Mastered variant, under Cook; Cook and the
## reason above it make room for them.
func _update_extras() -> void:
	var d := GameState.data
	var pot := Kitchen.max_mult(d, recipe) > 1
	if not pot:
		mult = 1
	var batch := recipe_has_mastered(d, recipe)
	_extras.visible = pot or batch
	for n: int in _mult_buttons:
		_mult_buttons[n].visible = pot
		_style(_mult_buttons[n], n == mult)
	_batch.visible = batch
	_batch.position.x = 2 * (MULT_W + 2) if pot else 0
	_batch.size.x = RIGHT_W - _batch.position.x
	var cook_y := 160 if _extras.visible else 184
	_cook.position = Vector2(RIGHT_X, cook_y)
	_cook.size = Vector2(RIGHT_W, 44 if _extras.visible else 48)
	_extras.position = Vector2(RIGHT_X, H - 4 - 24)
	_feedback.position = Vector2(RIGHT_X, TOP)
	_feedback.size = Vector2(RIGHT_W, cook_y - 2 - TOP)
	_missing_row.position = Vector2(RIGHT_X, cook_y - 19)


func _update_slots() -> void:
	var y := TOP
	var n := _slot_count()
	_no_slots.visible = n == 0
	if n == 0:
		_no_slots.text = tr("KITCHEN_NO_SLOTS")
		_no_slots.position = Vector2(LEFT_X, TOP)
		y += 38
	for which in SLOTS:
		var s: Dictionary = _slots[which]
		var spec: Variant = _spec(which)
		s.button.visible = spec != null
		if spec == null:
			continue
		s.button.position = Vector2(LEFT_X, y)
		y += SLOT_H + 2
		var need := int(spec.count) * mult
		s.caption.text = tr("UI_COOK_SLOT") % [_slot_word(spec), need]
		var vid: String = picks[which]
		if vid == "":
			s.have.text = ""
			s.icon.texture = null
			s.name.text = tr("UI_COOK_SLOT_EMPTY")
			s.name.add_theme_color_override("font_color", Art.MUTED)
		else:
			var have := int(_slot_stock(which).get(vid, 0))
			s.have.text = tr("UI_COOK_HAVE") % have
			s.have.add_theme_color_override("font_color", Art.CREAM_LO if have >= need else Art.PEACH)
			s.icon.texture = _row_icon(vid, which)
			s.name.text = _variety_name(vid)
			s.name.add_theme_color_override("font_color", Art.CREAM)
	_also.text = _also_line()
	_also.visible = _also.text != ""
	_also.position = Vector2(LEFT_X, y)
	if _also.visible:
		y += 20
	_addin_label.position = Vector2(LEFT_X, y)
	_addin_box.position = Vector2(LEFT_X, y + 18)
	_addin_desc.position = Vector2(LEFT_X, y + 44)


func _update_check() -> void:
	var d := GameState.data
	var r: Dictionary = Data.recipes()[recipe]
	var cost := Kitchen.energy_cost(String(r.method))
	_cook_cost.text = str(cost)
	_cook.tooltip_text = tr("UI_BATCH_COOK_TWO") % cost if mult > 1 else tr("KITCHEN_COOK_COST") % cost
	for c in _missing_row.get_children():
		_missing_row.remove_child(c)
		c.queue_free()
	_batch_ok = false
	var filled: bool = not ((_spec("main") != null and picks.main == "") or (_spec("second") != null and picks.second == ""))
	var key := Kitchen.product_key(recipe, _main(), _second(), addin)
	_show_preview(key if filled else "")
	_feedback.size.y = _cook.position.y - 2 - TOP
	if not filled:
		_ok = false
		var any_fit := false
		for which in SLOTS:
			var stock := _slot_stock(which)
			for vid in stock:
				any_fit = any_fit or _fits(which, vid)
		_set_feedback(tr("UI_COOK_FILL") if any_fit else tr(_nothing_fits_key()), Art.CREAM_LO)
		_set_cook_look()
		return
	var c := Kitchen.check_n(d, recipe, _main(), _second(), addin, mult)
	var mastered := Kitchen.is_mastered(d, key)
	_ok = bool(c.ok)
	_batch_ok = _ok and mastered
	if _ok:
		_set_feedback(tr("UI_MASTERY_READY") if mastered else tr("KITCHEN_READY"), Art.CREAM_LO)
	else:
		for id: String in c.missing:  # what is short, as icons under the reason
			_icon(_missing_row, State.type_of_variety(id) if d.varieties.has(id) else id)
			_icon_text(_missing_row, "x%d" % int(c.missing[id]), Art.PEACH)
		if not c.missing.is_empty():
			_feedback.size.y = _cook.position.y - 20 - TOP
		var line := tr(String(c.reason))
		var extra := _hint_for(c)
		_set_feedback(line if extra == "" else "%s. %s" % [line, extra], Art.PEACH)
	_set_cook_look()


## The middle column: the jar at 2x (a bottle is already twice as tall), its name once the book has it, New!, the
## value of one jar at 2 quality stars (Mastered: its best), five taste bars. "" = nothing to show yet.
func _show_preview(key: String) -> void:
	var d := GameState.data
	var shown := key != ""
	_preview_jar.visible = shown
	_preview_unknown.visible = not shown
	_value_icon.visible = shown
	_value.visible = shown
	_new_tag.visible = false
	if not shown:
		_preview_name.text = ""
		_taste.set_taste([0, 0, 0, 0, 0])
		return
	var desc := ProductGen.describe(key, d.varieties)
	var known: bool = d.book.variants.has(key)
	var bottle := String(desc.get("vessel", "")) == "bottle"
	_preview_jar.zoom = 1 if bottle else 2
	_preview_jar.show_product(desc)
	_preview_jar.position = Vector2(MID_X + 2 + (12 if bottle else 0), JAR_Y)
	_preview_name.text = ProductGen.product_name(key, d.varieties) if known else tr("KITCHEN_NEW_VARIANT")
	_preview_name.add_theme_color_override("font_color", Art.GOLD_PALE if known else Art.GOLD)
	_new_tag.visible = not known
	var q := Kitchen.best_quality(d, key) if Kitchen.is_mastered(d, key) else CookPick.EST_Q
	var v := ProductGen.value(key, d.varieties, q)
	_value.text = tr("UI_COOK_VALUE") % v
	_value.tooltip_text = tr("UI_COOK_VALUE_TIP") % v
	_taste.set_taste(desc.taste)


func _hint_for(c: Dictionary) -> String:
	match String(c.reason):
		Kitchen.R_TIRED:
			return tr("KITCHEN_SLEEP_HINT")
		Kitchen.R_MISSING:
			if _is_product_slot("main") and c.missing.has(picks.main):
				return tr("KITCHEN_PRESS_FIRST")
			var buy: Dictionary = Data.shop().get("buy", {})
			for id in c.missing:
				if buy.has(id):
					return tr("KITCHEN_GROCER_HINT")
			return tr("KITCHEN_FORAGE_HINT")
	return ""


func _set_feedback(s: String, col: Color) -> void:
	_feedback.text = s if _fits_feedback(s) else _first_sentence(s)
	_feedback.max_lines_visible = maxi(floori(_feedback.size.y / 18.0), 1)  # a very long reason is cut, never spills
	_feedback.add_theme_color_override("font_color", col)


## The reason fits the space above Cook (the hint after it is dropped when it would not).
func _fits_feedback(s: String) -> bool:
	return Art.FONT.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, _feedback.size.x, Art.FONT_SIZE).y <= _feedback.size.y + 0.5


func _first_sentence(s: String) -> String:
	var i := s.find(". ")
	return s.substr(0, i + 1) if i > 0 else s


## Not ready: the button keeps taking presses (they answer with a shake and the reason) but looks dull.
func _set_cook_look() -> void:
	_cook_look(_ok)
	_ready_look(_batch, _batch_ok)


## Cook!: amber with a gold edge when it can cook, iron grey when it cannot.
func _cook_look(can: bool) -> void:
	var bg := Art.AMBER if can else Art.IRON_DK
	var edge := Art.GOLD if can else Art.STONE
	_cook.add_theme_stylebox_override("normal", _box(bg, edge, 2))
	_cook.add_theme_stylebox_override("hover", _box(Art.TAN if can else Art.IRON, Art.GOLD_PALE if can else Art.STONE, 2))
	_cook.add_theme_stylebox_override("pressed", _box(Art.BROWN if can else Art.IRON_DK, edge, 2))
	_cook.add_theme_stylebox_override("hover_pressed", _box(Art.BROWN if can else Art.IRON_DK, edge, 2))
	_cook.add_theme_stylebox_override("focus", _box(bg, Art.CREAM, 1, 2, false))
	_cook_word.add_theme_color_override("font_color", Art.CREAM if can else Art.MUTED)
	_cook_cost.add_theme_color_override("font_color", Art.CREAM if can else Art.MUTED)


func _ready_look(b: Button, can: bool) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.remove_theme_stylebox_override(st)
		if not can:
			b.add_theme_stylebox_override(st, b.get_theme_stylebox("disabled"))
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.remove_theme_color_override(k)
		if not can:
			b.add_theme_color_override(k, Art.STONE)


# ---------------------------------------------------------------- plain words

## What a slot takes: "Fruit", "Apple/Pear/Quince", "Juice".
func _slot_word(spec: Dictionary) -> String:
	if spec.has("recipe"):
		return ProductGen.recipe_name(String(spec.recipe))
	var words: PackedStringArray = []
	if spec.has("types"):
		for t in spec.types:
			words.append(VarietyGen.type_name(String(t)))
	elif spec.has("groups"):
		for g in spec.groups:
			words.append(tr("UI_COOK_GROUP_" + String(g).to_upper()))
	return "/".join(words)


## A tab's one line: what goes in by count ("3 Fruit", "2 Fruit + 2 Vegetables"); the cupboard for bread ("2 Flour").
func _need_line(id: String) -> String:
	var r: Dictionary = Data.recipes().get(id, {})
	var parts: PackedStringArray = []
	for which in SLOTS:
		var spec: Variant = r.get(which)
		if typeof(spec) == TYPE_DICTIONARY:
			parts.append("%d %s" % [int(spec.count), _slot_word(spec)])
	if parts.is_empty():
		var base: Dictionary = r.get("base", {})
		for b in base:
			parts.append("%d %s" % [int(base[b]), _item_name(String(b))])
	return " + ".join(parts)


## "Also: Sugar, Jar": the cupboard staples of this cook (x mult).
func _also_line() -> String:
	var base: Dictionary = Data.recipes()[recipe].get("base", {})
	var parts: PackedStringArray = []
	for id in base:
		var n := int(base[id]) * mult
		parts.append(_item_name(String(id)) if n == 1 else "%d %s" % [n, _item_name(String(id))])
	return tr("UI_COOK_ALSO") % ", ".join(parts) if not parts.is_empty() else ""


func _item_name(id: String) -> String:
	var key := "TOWN_ITEM_" + id.to_upper()
	var s := tr(key)
	return s if s != key else id.capitalize()


## One line about an add-in: "Cinnamon (2): Spicy, Sweet" (its taste pushes, strongest first); None says so.
func _addin_line(id: String) -> String:
	if id == "":
		return tr("UI_COOK_EXTRA_NONE")
	var effect: Array = Data.addins().get(id, {}).get("effect", [])
	var axes: Array = []
	for i in mini(effect.size(), ResultCard.AXES.size()):
		if int(effect[i]) > 0:
			axes.append(i)
	axes.sort_custom(func(a: int, b: int) -> bool: return int(effect[a]) > int(effect[b]))
	var words: PackedStringArray = []
	for i: int in axes:
		words.append(tr("UI_TASTE_" + String(ResultCard.AXES[i]).to_upper()))
	return tr("UI_COOK_EXTRA_LINE") % [ProductGen.addin_name(id), addin_count(GameState.data, id), ", ".join(words)]


## The line under the add-in row: the hovered or focused add-in, else the picked one (nothing for None).
func _show_addin_line(id: Variant) -> void:
	if id == null:
		var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		for k: String in _addin_buttons:
			if _addin_buttons[k] == f:
				id = k
	if id == null:
		id = addin if addin != "" else null
	_addin_desc.text = _addin_line(String(id)) if id != null else ""


# ---------------------------------------------------------------- picking

func _spec(which: String) -> Variant:
	if recipe == "":
		return null
	return CookPick.spec(recipe, which)


## A slot that takes finished products of another recipe (syrup's juices), not fresh varieties.
func _is_product_slot(which: String) -> bool:
	var spec: Variant = _spec(which)
	return spec != null and spec.has("recipe")


func _slot_count() -> int:
	var n := 0
	for which in SLOTS:
		if _spec(which) != null:
			n += 1
	return n


## Units per variety id a slot can draw from: matured products for a recipe slot, fresh stock otherwise.
func _slot_stock(which: String) -> Dictionary:
	var spec: Variant = _spec(which)
	return CookPick.slot_stock(GameState.data, spec if spec != null else CookPick.spec(recipe, "main"))


func _empty_list_key() -> String:
	if _slot_count() == 0:
		return "KITCHEN_NO_SLOTS"
	if _is_product_slot(_picker_slot if _picker_slot != "" else "main"):
		return "KITCHEN_NO_JUICE"
	return "KITCHEN_NOTHING_FITS" if not fresh_stock(GameState.data).is_empty() else "KITCHEN_LIST_EMPTY"


func _nothing_fits_key() -> String:
	return "KITCHEN_NO_JUICE" if _is_product_slot("main") else "KITCHEN_NOTHING_FITS"


## Slot and row icon: the fruit for fresh stacks, a little bottle in the juice's colour for a recipe slot.
func _row_icon(vid: String, which := "main") -> Texture2D:
	if not _is_product_slot(which):
		return Art.icon(State.type_of_variety(vid))
	var key := ProductGen.make_key(String(_spec(which).recipe), [vid], "")
	if not _product_icons.has(key):
		var img := JarIcon.render(ProductGen.describe(key, GameState.data.varieties), "icon")
		_product_icons[key] = ImageTexture.create_from_image(img)
	return _product_icons[key]


## Slot routing only (which slot a variety goes to); the verdict always comes from Kitchen.check().
func _fits(which: String, vid: String) -> bool:
	return CookPick.fits(GameState.data, _spec(which), vid)


func _main() -> String:
	return picks.main if _spec("main") != null else ""


func _second() -> String:
	return picks.second if _spec("second") != null else ""


func _variety_name(vid: String) -> String:
	var v: Dictionary = GameState.data.varieties.get(vid, {})
	return VarietyGen.display_name(v) if not v.is_empty() else vid


## Fills the slots for the recipe just picked: a variety the player chose stays when it fits and is enough, the rest
## gets CookPick's best (a new variant first).
func _fill_for_recipe() -> void:
	var keep := {}
	for which in SLOTS:
		var spec: Variant = _spec(which)
		var v: String = picks[which]
		if spec != null and _hand_slots.has(which) and _fits(which, v) and int(_slot_stock(which).get(v, 0)) >= int(spec.count) * mult:
			keep[which] = v
	var fixed: Variant = Kitchen.fixed_addin(recipe)
	var p := CookPick.best_picks(GameState.data, recipe, String(fixed) if fixed != null else addin, mult, keep)
	picks = {"main": p.main, "second": p.second}


func _select_recipe(id: String) -> void:
	if id != recipe:
		if Kitchen.fixed_addin(recipe) != null:
			addin = ""  # leaving a family recipe: its add-in was not the player's pick
		recipe = id
		_hand = true
		_fill_for_recipe()
		Audio.play_ui("ui_click")
	_close_picker(false)
	refresh()


## Left / right: the previous or next tab (ends stop).
func _step_recipe(step: int) -> void:
	var i := _recipes.find(recipe) + step
	if i < 0 or i >= _recipes.size():
		return
	_select_recipe(_recipes[i])
	if _tabs.has(recipe):
		_pop(_tabs[recipe])


func _select_addin(id: String) -> void:
	addin = id
	_hand = true
	Audio.play_ui("ui_click")
	refresh()
	if _addin_buttons.has(id):
		_pop(_addin_buttons[id])


## Routes a variety into the first slot it fits (the picker, tests and smokes).
func _pick(vid: String, from: Control) -> void:
	for which in SLOTS:
		if _fits(which, vid):
			_set_pick(which, vid)
			return
	_reject(from)


func _set_pick(which: String, vid: String) -> void:
	picks[which] = vid
	_hand = true
	_hand_slots[which] = true
	Audio.play_ui("ui_click")
	refresh()
	_pop(_slots[which].button)


func _reject(node: Control) -> void:
	Audio.play_ui("ui_error")
	_set_feedback(tr(Kitchen.R_WRONG), Art.PEACH)
	_shake(node)


## A slot press opens the Change picker for it.
func _on_slot_pressed(which: String) -> void:
	Audio.play_ui("ui_click")
	open_picker(which)


## Opens the Change picker for slot `which` (focus on the chosen variety's row).
func open_picker(which: String) -> void:
	if _spec(which) == null:
		return
	_picker_slot = which
	_picker_title.text = tr("UI_COOK_PICK") % (_slots[which].caption as Label).text
	_picker.visible = true
	_inputs.visible = false
	_preview.visible = false
	_build_list()
	var target: Control = _rows.get(picks[which], _rows.values()[0] if not _rows.is_empty() else _picker_back)
	target.grab_focus()
	if _rows.values().has(target):
		_scroll.ensure_control_visible(target)


func _close_picker(focus_slot: bool) -> void:
	if _picker == null or not _picker.visible:
		return
	var which := _picker_slot
	_picker.visible = false
	_inputs.visible = true
	_preview.visible = true
	_picker_slot = ""
	if focus_slot and _slots.has(which) and _slots[which].button.is_visible_in_tree():
		Audio.play_ui("ui_back")
		_slots[which].button.grab_focus()


## A picker row: that variety into the open slot.
func _choose(vid: String) -> void:
	var which := _picker_slot
	_close_picker(false)
	if which == "" or not _fits(which, vid):
		_reject(_cook)
		return
	_set_pick(which, vid)
	_slots[which].button.grab_focus()


func _on_cook() -> void:
	_update_check()
	if not _ok:
		Audio.play_ui("ui_error")
		_shake(_cook)
		return
	cook_requested.emit(recipe, _main(), _second(), addin)


func _on_batch() -> void:
	_update_check()
	if not _batch_ok:
		Audio.play_ui("ui_error")
		_shake(_batch)
		if _ok:  # everything is there, the picked variant is just not Mastered yet
			_set_feedback(tr(Kitchen.R_NOT_MASTERED), Art.PEACH)
		return
	batch_requested.emit(recipe, _main(), _second(), addin)


## Swaps the tabs between the base recipes and this station's family recipes.
func _toggle_family() -> void:
	family = not family
	if Kitchen.fixed_addin(recipe) != null:
		addin = ""
	_build_tabs()
	recipe = _recipes[0] if not _recipes.is_empty() else ""
	if addin != "" and addin_count(GameState.data, addin) == 0:
		addin = ""
	_hand = true
	_close_picker(false)
	if recipe != "":
		_fill_for_recipe()
	Audio.play_ui("ui_click")
	refresh()
	_pop(_family_btn)
	_family_btn.grab_focus()


func _select_mult(n: int) -> void:
	mult = clampi(n, 1, Kitchen.max_mult(GameState.data, recipe))
	_hand = true
	Audio.play_ui("ui_click")
	refresh()
	if _mult_buttons.has(mult):
		_pop(_mult_buttons[mult])


# ---------------------------------------------------------------- keys and focus

## Before the GUI: Esc closes the picker first; left / right switch recipes unless focus is in a row of its own
## (add-ins, x1/x2 and Batch, the header buttons).
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or event is InputEventMouse:
		return
	if _picker.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel"):
			_close_picker(true)
			get_viewport().set_input_as_handled()
		return
	var step := 0
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		step = -1
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		step = 1
	if step == 0:
		return
	var f := get_viewport().gui_get_focus_owner()
	if f != null and f != _cook and not _is_slot_button(f) and is_ancestor_of(f):
		return
	_step_recipe(step)
	get_viewport().set_input_as_handled()


func _is_slot_button(c: Control) -> bool:
	for which in SLOTS:
		if _slots[which].button == c:
			return true
	return false


## Up / down: header -> slots -> Extra -> Cook -> x1/x2 and Batch.
func _link_focus() -> void:
	var chain: Array = []
	for which in SLOTS:
		if _slots[which].button.visible:
			chain.append(_slots[which].button)
	var add_btn: Control = _addin_buttons.get(addin, _addin_buttons.values()[0] if not _addin_buttons.is_empty() else null)
	if add_btn != null:
		chain.append(add_btn)
	chain.append(_cook)
	var extra: Control = null
	for c: Control in [_mult_buttons[1], _mult_buttons[2], _batch]:
		if extra == null and c.visible and _extras.visible:
			extra = c
	if extra != null:
		chain.append(extra)
	var head: Control = _family_btn if _family_btn.visible else _back
	for i in chain.size():
		var c: Control = chain[i]
		var up: Control = chain[i - 1] if i > 0 else head
		var down: Control = chain[i + 1] if i < chain.size() - 1 else c
		var group: Array = [c]
		if c == add_btn:
			group = _addin_buttons.values()
		elif c == extra:
			group = [_mult_buttons[1], _mult_buttons[2], _batch]
		for g: Control in group:
			g.focus_neighbor_top = g.get_path_to(up)
			g.focus_neighbor_bottom = g.get_path_to(down if g != down else g)
	for c: Control in [_back, _family_btn]:
		c.focus_neighbor_bottom = c.get_path_to(chain[0])


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
	for n in _mult_buttons:
		if _mult_buttons[n] == f:
			return "mult:%d" % n
	if f == _cook:
		return "cook:"
	if f == _batch:
		return "batch:"
	if f == _family_btn:
		return "family:"
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
		"mult":
			target = _mult_buttons.get(int(parts[1]))
		"cook":
			target = _cook
		"batch":
			target = _batch
		"family":
			target = _family_btn
	if target != null and not target.is_visible_in_tree():
		target = null
	if target == null:
		target = _rows.values()[0] if _picker.visible and not _rows.is_empty() else _cook
	target.grab_focus()


# ---------------------------------------------------------------- look and juice

## A full-size, click-through holder for one column (hidden while the picker covers it).
func _layer() -> Control:
	var c := Control.new()
	c.size = Vector2(W, H)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _row_w() -> int:
	return int(MID_X + MID_W + 4 - LEFT_X) - 8 - 10


func _text_w(s: String) -> float:
	return Art.FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Art.FONT_SIZE).x


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


func _style_row(b: Button, picked: bool) -> void:
	var bg := Art.WINE if picked else Art.PLUM
	b.add_theme_stylebox_override("normal", _box(bg, Art.GOLD if picked else bg, 1, 1))
	b.add_theme_stylebox_override("hover", _box(Art.BARK, Art.TAN, 1, 1))
	b.add_theme_stylebox_override("pressed", _box(Art.WINE, Art.GOLD, 1, 1))
	b.add_theme_stylebox_override("hover_pressed", _box(Art.WINE, Art.GOLD, 1, 1))
	b.add_theme_stylebox_override("focus", _box(bg, Art.GOLD_PALE, 1, 1, false))


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


## Five taste rows: the axis word, then up to 9 cells in the axis colour (value 0..9). Cells narrow so the longest
## word fits (Turkish "Baharatlı").
class TasteBars extends Control:
	const ROW := 13
	var taste: Array = [0, 0, 0, 0, 0]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_taste(t: Array) -> void:
		taste = t
		var parts: PackedStringArray = []
		for i in 5:
			parts.append("%s %d" % [tr("UI_TASTE_" + String(ResultCard.AXES[i]).to_upper()), int(t[i]) if i < t.size() else 0])
		tooltip_text = ", ".join(parts)
		queue_redraw()

	func _draw() -> void:
		var words: Array = []
		var lw := 0.0
		for i in 5:
			words.append(tr("UI_TASTE_" + String(ResultCard.AXES[i]).to_upper()))
			lw = maxf(lw, Art.FONT.get_string_size(words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, Art.FONT_SIZE).x)
		var x0 := ceili(lw) + 3
		var cell := clampi(floori((size.x - x0 + 1) / 9.0), 2, 7)
		for i in 5:
			var y := i * ROW
			draw_string(Art.FONT, Vector2(0, y + 10), words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, Art.FONT_SIZE, Art.CREAM_LO)
			var v := clampi(int(taste[i]) if i < taste.size() else 0, 0, 9)
			for c in 9:
				draw_rect(Rect2(x0 + c * cell, y + 3, cell - 1, 7), ResultCard.AXIS_COLORS[i] if c < v else Art.STONE)


# ---------------------------------------------------------------- FIX-JURY-B: the festival's "Invent a dish" step

## Points Granny's arrow at the Invent button (and gives it the keyboard focus) while her To-Do step is "Invent a dish";
## the guide layer itself hides under open panels, so the panel draws the same bobbing arrow over its own button.
func point_invent(on: bool) -> void:
	if _invent == null:
		return
	_invent_arrow.target = _invent if on else null
	_invent_arrow.visible = on
	if on and visible:
		_invent.grab_focus()


func invent_pointed() -> bool:
	return _invent_arrow != null and _invent_arrow.visible


## The Invent button (smokes and the demo press it).
func invent_button() -> Button:
	return _invent


## GuideArrow's 11x11 pixel arrow, pointing right at `target`'s left edge (the HUD bar sits right above the panel's
## buttons), bobbing 2 px, whole pixels only.
class InventArrow extends Control:
	var target: Control
	var _t := 0.0
	var _bob := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _process(delta: float) -> void:
		if not visible or target == null:
			return
		_t += delta
		var b := int(_t * GuideArrow.BOB_HZ) % 2 * 2
		if b != _bob:
			_bob = b
			queue_redraw()

	## The arrow tip in the panel's coordinates.
	func tip() -> Vector2:
		if target == null:
			return Vector2.ZERO
		return Vector2(target.position.x - 2 - maxi(_bob, 0), target.position.y + roundf(target.size.y / 2.0))

	func _draw() -> void:
		if target == null:
			return
		var art: Array = GuideArrow.ARROW
		var at := tip()
		var tip_y := art.size() - 1
		for y in art.size():
			var row: String = art[y]
			for x in row.length():
				var ch := row[x]
				if ch == ".":
					continue
				var col := GuideArrow.C_INK if ch == "#" else (GuideArrow.C_PAPER if ch == "c" else GuideArrow.C_GOLD)
				draw_rect(Rect2(at + Vector2(y - tip_y, x - 5), Vector2.ONE), col)  # the down arrow turned to the right
