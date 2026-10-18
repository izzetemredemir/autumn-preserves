extends Control
## Town square (GD-TOWN): grocer (buy), order board, neighbours (talk / gift). One 480x270 click scene.
## CUT-CLUTTER: the grocer only sells to Granny; jars turn into coins through orders and the weekly market, where
## people react to them.
## All rules come from Economy / Orders; this scene only lists, asks and shows results.
## The backdrop is a separate TextureRect ("Background") so ART can swap its texture.

const ICONS_JSON := "res://assets/sprites/icons/icons.json"
const ICONS_PNG := "res://assets/sprites/icons/icons.png"
const PANEL_Y := 146  # the panel covers the lower ~44%; the painted shopfront stays visible above it
const TAB_Y := 38
const TAB_START := 8
const TAB_END := 322  # the To-Do note covers x >= 326 at the top
const NPC_PANEL_H := 80  # UI-COMPACT: the neighbours tab's panel (names, portrait, two lines, Gift), under a third
const ROWS := 3
const GROUPS := ["supplies", "seeds", "upgrades"]
const NPC_IDS := ["grocer", "baker", "postman", "vintner", "librarian"]
const RV := preload("res://scenes/market/react_view.gd")
const REACT_AT := Vector2(10, 64)  # FUN-REACT delivery card: over the square, between the tab row and the panel

var _tab := "grocer"
var _react_card: Control
var _react_undo: Array[Callable] = []  # what the delivery card changed, undone when it goes
var _banner: Control  # MARKET's "Market today!" banner (market days only)
var _group := "supplies"
var _npc := "grocer"
var _page := 0
var _picker: Dictionary = {}  # {} or {"kind": "order"|"gift", "id": order id or npc id}
var _content: VBoxContainer
var _panel: PanelContainer
var _tab_buttons: Dictionary = {}
var _icon_sheet: Texture2D
var _icon_cells: Dictionary = {}
var _icon_size := Vector2(16, 16)
var _back_btn: Button
var _story_npc := ""  # STORY-03: the neighbour whose Teo line is on show
var _gift: Dictionary = {}  # CUT-CLUTTER: the heart gift on show on its neighbour's page (a take_rewards entry)


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_temp(1)
		_debug_fill()
	Forage.empty_bag_to_inbox(GameState.data)
	Economy.sync_neighbours(GameState.data)  # old saves: new neighbours and rewards already earned
	_load_icons()
	_paint_background()
	_build()
	_add_square()
	GameState.changed.connect(func(_k: PackedStringArray) -> void: _render())
	Audio.play_music("mus_town")
	Audio.play_ambient("amb_town")
	_render()
	_show_rewards(0.4)
	GuideArrow.attach(self, _guide_at)  # ONBOARD-GUIDE: arrow and Granny's hint


## Run-alone helper: coins, a few fresh items and real jars so the board and the neighbours can be tested.
func _debug_fill() -> void:
	var d: Dictionary = GameState.data
	d.coins = 300
	var seen := {}
	for c in Orders.candidates(d, ProductGen.taste):
		if seen.size() >= 6:
			break
		if not seen.has(c.recipe):
			seen[c.recipe] = true
			d.inbox.append(State.product(c.key, 2, 0))
	var n := 0
	for v in d.varieties:
		if n >= 2:
			break
		d.inbox.append(State.fresh(v, 3, 5))
		n += 1
	d.inbox.append(State.nut("walnut", 4))
	if d.orders.is_empty():
		Orders.refill(d)
	GameState.notify(PackedStringArray(["*"]))


# ------------------------------------------------------------------ icons and backdrop

func _load_icons() -> void:
	var f := FileAccess.open(ICONS_JSON, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_icon_cells = parsed.get("icons", {})
	var cell: Array = parsed.get("cell", [16, 16])
	_icon_size = Vector2(cell[0], cell[1])
	_icon_sheet = load(ICONS_PNG) as Texture2D


func _icon(id: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(16, 16)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _icon_sheet != null and _icon_cells.has(id):
		var at := AtlasTexture.new()
		at.atlas = _icon_sheet
		var rc: Array = _icon_cells[id]
		at.region = Rect2(Vector2(rc[0], rc[1]) * _icon_size, _icon_size)
		var pic := TextureRect.new()
		pic.texture = at
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.stretch_mode = TextureRect.STRETCH_KEEP
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pic)
	else:
		var tex := _icon_file(id)
		if tex != null:
			var pic2 := TextureRect.new()
			pic2.texture = tex
			pic2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			pic2.stretch_mode = TextureRect.STRETCH_KEEP
			pic2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(pic2)
	return holder


## Icons the atlas lacks: a single file icons/<id>.png (press, boots, bag, beds ...) or JarIcon's drawn supplies (bottle, flour).
func _icon_file(id: String) -> Texture2D:
	if IconLib.is_generated(id):  # SPECIES-GEN: generated species icons
		return IconLib.ingredient(id)
	var path := "res://assets/sprites/icons/%s.png" % id
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return JarIcon.supply_icon(id)


func _paint_background() -> void:
	$Background.texture = load("res://assets/sprites/scenes/bg_town.png") as Texture2D


## LIVING-TOWN: the living square right above the backdrop (every panel stays on top); a click on a neighbour there
## opens their page in the Neighbours tab.
func _add_square() -> void:
	var square: Control = load("res://scenes/town/town_square.gd").new()
	add_child(square)
	move_child(square, $Background.get_index() + 1)
	square.connect("neighbour_clicked", func(id: String) -> void:
		_npc = id
		_on_tab("neighbours"))


# ------------------------------------------------------------------ frame

func _build() -> void:
	# TOWN-NAV: four tabs share x 8..322 (the To-Do note owns the top right), sized by their labels
	var tabs := [["grocer", tr("TOWN_TAB_GROCER")], ["orders", tr("TOWN_TAB_ORDERS")],
			["neighbours", tr("TOWN_TAB_NEIGHBOURS")], ["post", tr("LET_POST_OFFICE")]]
	var btns: Array[Button] = []
	var need := 0
	for t in tabs:
		var b := Button.new()
		b.text = t[1]
		add_child(b)
		if t[0] == "post":
			b.pressed.connect(_on_post_office)
		else:
			_style_toggle(b)
			b.pressed.connect(_on_tab.bind(t[0]))
			_tab_buttons[t[0]] = b
		btns.append(b)
		need += ceili(b.get_minimum_size().x)
	var gap := 2
	var room := TAB_END - TAB_START - gap * (tabs.size() - 1)
	var extra := maxi(0, room - need) / tabs.size()
	var shrink := maxi(0, need - room)  # labels wider than the room: padding gives way
	var x := TAB_START
	for i in btns.size():
		var w := ceili(btns[i].get_minimum_size().x) + extra
		if shrink > 0:
			w -= ceili(float(shrink) / tabs.size())
			var pad := maxi(0, 4 - ceili(float(shrink) / tabs.size() / 2.0))
			for k in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
				var sb := btns[i].get_theme_stylebox(k).duplicate() as StyleBox
				sb.content_margin_left = pad
				sb.content_margin_right = pad
				btns[i].add_theme_stylebox_override(k, sb)
		btns[i].position = Vector2(x, TAB_Y)
		btns[i].size = Vector2(w, 20)
		x += w + gap
	var back: Button = load("res://scenes/town/town_sign.gd").new()
	back.text = tr("TOWN_BACK_GARDEN")
	add_child(back)
	back.fit()
	back.position = Vector2(8, PANEL_Y - 24)
	back.pressed.connect(_on_back)
	_back_btn = back
	if Market.can_open(GameState.data):  # MARKET: "Market today!" banner on market days, until the stall opens
		_banner = load("res://scenes/market/market_banner.gd").new()
		add_child(_banner)
	_panel = PanelContainer.new()
	_panel.clip_contents = true
	add_child(_panel)
	_fit_panel(false)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 1)
	_panel.add_child(_content)


## The panel at the bottom: PANEL_Y down for the lists, NPC_PANEL_H tall for a neighbour's page (UI-COMPACT).
func _fit_panel(compact: bool) -> void:
	var h := NPC_PANEL_H if compact else 270 - PANEL_Y - 4
	_panel.position = Vector2(8, 270 - 4 - h)
	_panel.size = Vector2(464, h)


## Selected tabs are shown pressed (not disabled) with a bright label.
func _style_toggle(b: Button) -> void:
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	var cream := Color(0.949, 0.851, 0.7725)
	for k in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, cream)


func _mark(b: Button, on: bool) -> void:
	_style_toggle(b)
	b.set_pressed_no_signal(on)


func _on_tab(id: String) -> void:
	_tab = id
	_page = 0
	_picker = {}
	_gift = {}
	_render()


func _on_back() -> void:
	Router.goto("garden" if Router.exists("garden") else "kitchen")


## ONBOARD-GUIDE: what Granny's guide asks the town (GuideArrow header): the Orders tab, then Deliver, for the order
## steps of day 1 and day 2 (CUT-CLUTTER: day 2 delivers an order, no grocer's Sell); the market banner on festival
## day; else the way back. No Granny here: her hint sits over the square, above the panel.
func _guide_at(what: String) -> Variant:
	match what:
		"granny":
			return null
		"near":
			return {}
		"bubble":
			return Vector2(240, PANEL_Y - 6)
	if not _picker.is_empty():
		return null
	var target: Control = _back_btn
	match what:
		"d1_order", "d2_sell":
			target = _tab_buttons.orders if _tab != "orders" else _guide_button(tr("TOWN_DELIVER"), 0)
		"f_market":
			target = get_node_or_null("MarketToday") as Control
	if target == null or not target.is_visible_in_tree():
		return null
	return target.get_global_rect().position + Vector2(roundf(target.size.x / 2.0), -1)


## The first enabled button saying `text` in the tab's content, from child row `skip` on.
func _guide_button(text: String, skip: int) -> Control:
	for row in _content.get_children().slice(skip):
		for b in row.find_children("*", "Button", true, false):
			if (b as Button).text == text and not (b as Button).disabled and (b as Button).is_visible_in_tree():
				return b
	return null


## Post office (P1-LETTERS): grandchild letters and the parcel screen, as an overlay.
func _on_post_office() -> void:
	LettersUI.open()


## Esc closes the jar picker; with nothing open it is left to the in-game menu (PAUSE-MENU; Back leaves the square).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and not _picker.is_empty():
		_picker = {}
		_render()
		get_viewport().set_input_as_handled()


func _render() -> void:
	if _content == null or GameState.data.is_empty():
		return
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	for id in _tab_buttons:
		(_tab_buttons[id] as Button).set_pressed_no_signal(id == _tab)
	_fit_panel(_tab == "neighbours" and _picker.is_empty())
	if not _picker.is_empty():
		_render_picker()
		return
	match _tab:
		"grocer":
			_render_grocer()
		"orders":
			_render_orders()
		"neighbours":
			_render_neighbours()


func _label(text: String, min_w := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if min_w > 0:
		l.custom_minimum_size.x = min_w
	return l


func _button(text: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(56, 18)
	b.disabled = disabled
	b.pressed.connect(cb)
	return b


## "< 1/2 >" for lists longer than one page; returns the first and last index to show.
func _pager(head: HBoxContainer, total: int, per: int) -> Vector2i:
	var pages := maxi(1, ceili(float(total) / per))
	_page = clampi(_page, 0, pages - 1)
	if pages > 1:
		var prev := _button("<", _turn.bind(-1), _page == 0)
		prev.custom_minimum_size = Vector2(22, 18)
		head.add_child(prev)
		var num := Label.new()
		num.text = "%d/%d" % [_page + 1, pages]
		head.add_child(num)
		var nxt := _button(">", _turn.bind(1), _page == pages - 1)
		nxt.custom_minimum_size = Vector2(22, 18)
		head.add_child(nxt)
	return Vector2i(_page * per, mini(total, _page * per + per))


func _turn(dir: int) -> void:
	_page += dir
	_render()


func _row(icon: Control, text: String, btn_text: String, cb: Callable, disabled := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(icon)
	row.add_child(_label(text, 250))
	row.add_child(_button(btn_text, cb, disabled))
	_content.add_child(row)
	return row


func _save_and_notify(keys: Array) -> void:
	Save.save_game(GameState.data)
	GameState.notify(PackedStringArray(keys))


# ------------------------------------------------------------------ items

## Products waiting in the inbox and the pantry: [{ref, item}].
func _products() -> Array:
	var out: Array = []
	for e in _sellables():
		if e.item.kind == "product":
			out.append(e)
	return out


## Everything Granny has at home: inbox first, then the pantry.
func _sellables() -> Array:
	var out: Array = []
	var d: Dictionary = GameState.data
	for i in d.inbox.size():
		out.append({"ref": {"where": "inbox", "index": i}, "item": d.inbox[i]})
	for i in d.pantry.items.size():
		out.append({"ref": {"where": "pantry", "index": i}, "item": d.pantry.items[i].item})
	return out


func _item_name(item: Dictionary) -> String:
	var d: Dictionary = GameState.data
	match item.kind:
		"product":
			return ProductGen.product_name(item.key, d.varieties)
		"fresh":
			var v: Dictionary = d.varieties.get(item.variety, {})
			return "%s x%d" % [VarietyGen.display_name(v) if not v.is_empty() else String(item.variety), int(item.count)]
		"nut":
			return "%s x%d" % [VarietyGen.type_name(String(item.type)), int(item.count)]
	return "?"


func _item_icon(item: Dictionary) -> Control:
	if item.kind == "product":
		var ji := JarIcon.new()
		ji.view = "icon"
		ji.show_product(ProductGen.describe(item.key, GameState.data.varieties))
		return ji
	return _icon(State.item_type(item))


# ------------------------------------------------------------------ grocer

## The grocer's shop: Supplies / Seeds / Upgrades in the head row, the rows under it. CUT-CLUTTER: no Sell sub-tab.
func _render_grocer() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	for g in GROUPS:
		var gb := _button(tr("UI_UPGRADE_GROUP_" + String(g).to_upper()), _set_group.bind(g))
		_mark(gb, _group == g)
		head.add_child(gb)
	_content.add_child(head)
	_render_buy(head)


func _set_group(g: String) -> void:
	_group = g
	_page = 0
	_render()


## Shop ids of one grocer group: supplies (shop.json buy), seeds, upgrades.
func _shop_ids(group: String = "") -> Array:
	var shop: Dictionary = Data.shop()
	match group:
		"supplies":
			return shop.buy.keys()
		"seeds":
			var out: Array = []
			for s in shop.seeds:
				out.append("seed_" + s)
			return out
	var ups: Array = shop.upgrades.keys()
	return ups


func _shop_name(id: String) -> String:
	if Data.shop().upgrades.has(id):
		return tr("UI_UPGRADE_NAME_" + id.to_upper())
	return tr("TOWN_ITEM_" + id.to_upper())


## "Bag  Lv 1/2 - 200 coins" plus a second line with the effect, for an upgrade row.
func _upgrade_text(d: Dictionary, id: String, price: int) -> String:
	var up: Dictionary = Data.shop().upgrades[id]
	var levels: int = up.prices.size() if up.has("prices") else 1
	var next := int(d.upgrades.get(id, 0)) + 1
	var text := tr("UI_UPGRADE_NAME_" + id.to_upper())
	if levels > 1:
		text += "  " + tr("UI_UPGRADE_LEVEL") % [next, levels]
	text += "  -  " + tr("TOWN_PRICE") % price
	var fx := tr("UI_UPGRADE_FX_" + id.to_upper())
	if id == "bag":
		fx = fx % int(up.capacity[next - 1])
	return text + "\n" + fx


func _render_buy(head: HBoxContainer) -> void:
	var d: Dictionary = GameState.data
	var ids: Array = []
	for id in _shop_ids(_group):
		if Economy.price(d, id) >= 0:
			ids.append(id)
	var upgrades := _group == "upgrades"
	var r := _pager(head, ids.size(), 2 if upgrades else ROWS)
	for id in ids.slice(r.x, r.y):
		var price := Economy.price(d, id)
		var text := ""
		if upgrades:
			text = _upgrade_text(d, id, price)
		else:
			text = _shop_name(id)
			if d.cupboard.has(id):
				text += "  " + tr("TOWN_HAVE") % int(d.cupboard[id])
			text += "  -  " + tr("TOWN_PRICE") % price
		_row(_icon(id), text, tr("TOWN_BUY"), _on_buy.bind(id))


func _on_buy(id: String) -> void:
	var res := Economy.buy(GameState.data, id)
	if not res.ok:
		Hud.toast(res.reason)
		return
	_save_and_notify(["coins", "cupboard", "pantry", "upgrades"])
	Hud.toast("TOWN_BOUGHT", [_shop_name(id), int(res.spent)])


# ------------------------------------------------------------------ order board

func _axis_text(axes: Array) -> String:
	var names: Array = []
	for a in axes:
		names.append(tr("UI_TASTE_" + String(a).to_upper()))
	return " & ".join(names)


func _order_text(o: Dictionary) -> String:
	var who: String = Data.npcs().get(o.npc, {}).get("name", o.npc)
	var axes := _axis_text(o.axes)
	if String(o.recipe) != "":
		var recipe := ProductGen.recipe_name(String(o.recipe))
		if axes == "":
			return tr("TOWN_ORDER_RECIPE_PLAIN") % [who, recipe, int(o.min_stars)]
		return tr("TOWN_ORDER_RECIPE") % [who, recipe, axes, int(o.min_stars)]
	if axes == "":
		return tr("TOWN_ORDER_PLAIN") % [who, int(o.min_stars)]
	return tr("TOWN_ORDER_ANY") % [who, axes, int(o.min_stars)]


func _render_orders() -> void:
	var d: Dictionary = GameState.data
	if d.orders.is_empty():
		_content.add_child(_label(tr("TOWN_NO_ORDERS")))
		return
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation", 2)
	var r := _pager(pager, d.orders.size(), 2)
	var first := true
	for o in d.orders.slice(r.x, r.y):
		var left := int(o.expires_day) - int(d.day)
		var days := tr("TOWN_LAST_DAY") if left <= 1 else tr("TOWN_DAYS_LEFT") % left
		var face := Bust.new()
		face.npc_id = o.npc
		face.custom_minimum_size = Vector2(48, 48)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(face)
		row.add_child(_label("%s\n%s" % [_order_text(o), days], 250))
		var col := VBoxContainer.new()
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.add_theme_constant_override("separation", 2)
		col.add_child(_button(tr("TOWN_DELIVER"), _on_deliver.bind(int(o.id))))
		if first and pager.get_child_count() > 0:
			col.add_child(pager)
		first = false
		row.add_child(col)
		_content.add_child(row)
	if pager.get_parent() == null:  # one page: the pager stayed empty and out of the tree (QA-FIX: it leaked)
		pager.free()


func _order_by_id(id: int) -> Dictionary:
	for o in GameState.data.orders:
		if int(o.id) == id:
			return o
	return {}


func _on_deliver(order_id: int) -> void:
	var o := _order_by_id(order_id)
	for e in _products():
		if Orders.matches(o, e.item, GameState.data.varieties):
			_picker = {"kind": "order", "id": order_id}
			_page = 0
			_render()
			return
	Hud.toast("UI_ORDER_NO_MATCH")


# ------------------------------------------------------------------ neighbours

func _render_neighbours() -> void:
	var d: Dictionary = GameState.data
	var list := HBoxContainer.new()  # five neighbours: names in a row, not a column
	list.add_theme_constant_override("separation", 4)
	_content.add_child(list)
	for id in NPC_IDS:
		var b := Button.new()
		b.text = Data.npcs()[id].name
		b.custom_minimum_size = Vector2(80, 18)
		_mark(b, id == _npc)
		b.pressed.connect(_select_npc.bind(id))
		list.add_child(b)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 10)
	_content.add_child(split)
	var npc: Dictionary = Data.npcs()[_npc]
	var hearts := Economy.hearts(d, _npc)
	var bust := Bust.new()
	bust.npc_id = _npc
	bust.custom_minimum_size = Vector2(48, 48)
	bust.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	split.add_child(bust)
	# UI-COMPACT: name, hearts and Gift on one row, then two body-font lines: what they say and what they like.
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	split.add_child(info)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var who := _label("%s  -  %s" % [npc.name, tr("TOWN_ROLE_" + String(npc.role).to_upper())])
	who.autowrap_mode = TextServer.AUTOWRAP_OFF
	who.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top.add_child(who)
	var hr := HeartRow.new()
	hr.filled = hearts
	hr.custom_minimum_size = Vector2(80, 12)
	hr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(hr)
	var gift := _button(tr("TOWN_GIFT"), _on_gift)
	gift.custom_minimum_size = Vector2(72, 18)
	top.add_child(gift)
	if not _gift.is_empty() and String(_gift.npc) == _npc:
		top.add_child(_gift_badge(_gift))
	info.add_child(top)
	var says := tr("NPC_%s_%d" % [_npc.to_upper(), clampi(hearts / 2, 0, 2)])
	var story := _story_says(d, hearts, says)
	var lines: Array = [story] if story != says else [story, tr("TOWN_LIKES") % _axis_text(npc.likes)]  # the Teo line takes the likes' place
	for t in lines:
		var l := _label(t)
		l.theme_type_variation = &"Body"
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		if story != says:  # a Teo line runs to up to three wrapped lines
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 380
			l.max_lines_visible = 3
		info.add_child(l)


## STORY-03: a neighbour's one Teo line replaces the usual line, once per save (it stays while this page stays open).
func _story_says(d: Dictionary, hearts: int, says: String) -> String:
	var key := Story.npc_line_due(d, _npc, hearts, TodoRules.festival_today(d))
	if key != "":
		Story.mark_npc_said(d, _npc)
		_story_npc = _npc
		Save.save_game(d)
	elif _story_npc == _npc:
		key = "STORY_NPC_" + _npc.to_upper()
	return tr(key) if key != "" else says


func _select_npc(id: String) -> void:
	_story_npc = ""
	_npc = id
	if not _gift.is_empty() and String(_gift.npc) != id:
		_gift = {}
	_render()


## CUT-CLUTTER: a heart gift (Pip's jars, Edith's sugar) is a moment, not a hidden bonus: the neighbour's page opens
## with their Teo line (STORY-03, due at the same heart count) and what they handed over beside their hearts.
func _gift_moment(r: Dictionary) -> void:
	if not is_inside_tree() or not _picker.is_empty() or not String(r.get("npc", "")) in NPC_IDS:
		return
	_gift = r
	_npc = String(r.npc)
	_story_npc = ""
	_tab = "neighbours"
	_page = 0
	_render()
	Audio.play_sfx("sfx_sparkle")


## "+3 [jar]": the gift's count and icon, popping in beside the hearts.
func _gift_badge(r: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.name = "GiftBadge"
	box.add_theme_constant_override("separation", 2)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := Label.new()
	n.text = "+%d" % int(r.get("count", 1))
	box.add_child(n)
	box.add_child(_icon(String(r.get("value", ""))))
	if not bool(r.get("popped", false)):  # pops once; later re-renders of the page keep it still
		r["popped"] = true
		box.pivot_offset = Vector2(14, 8)
		box.scale = Vector2(0.6, 0.6)
		var tw := box.create_tween()
		tw.tween_property(box, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return box


func _on_gift() -> void:
	var gifted: Dictionary = GameState.data.flags.get("gifted", {})
	if int(gifted.get(_npc, 0)) == int(GameState.data.day):
		Hud.toast("UI_GIFTED_TODAY")
		return
	if _products().is_empty():
		Hud.toast("TOWN_NO_JARS")
		return
	_picker = {"kind": "gift", "id": _npc}
	_page = 0
	_render()


# ------------------------------------------------------------------ picker (order delivery and gifts)

func _render_picker() -> void:
	var d: Dictionary = GameState.data
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var title := tr("TOWN_PICK_FOR_ORDER")
	if _picker.kind == "gift":
		title = tr("TOWN_PICK_FOR_GIFT") % Data.npcs()[_picker.id].name
	head.add_child(_label(title))
	var order: Dictionary = _order_by_id(int(_picker.id)) if _picker.kind == "order" else {}
	var list: Array = []
	for e in _products():
		if _picker.kind != "order" or Orders.matches(order, e.item, d.varieties):
			list.append(e)
	head.add_child(_button(tr("UI_CANCEL"), _close_picker))
	var r := _pager(head, list.size(), 3)
	_content.add_child(head)
	for e in list.slice(r.x, r.y):
		if _picker.kind == "order":
			var coins := floori(ProductGen.value(e.item.key, d.varieties, int(e.item.q)) * float(Data.rules().orders.reward_mult))
			var text := "%s  -  %s" % [_item_name(e.item), tr("TOWN_REWARD") % coins]
			_row(_item_icon(e.item), text, tr("TOWN_GIVE"), _do_fulfill.bind(e.ref))
		else:
			_row(_item_icon(e.item), _item_name(e.item), tr("TOWN_GIVE"), _do_gift.bind(e.ref))
	if list.is_empty():
		_content.add_child(_label(tr("UI_ORDER_NO_MATCH")))


func _close_picker() -> void:
	_picker = {}
	_page = 0
	_render()


func _do_fulfill(ref: Dictionary) -> void:
	var npc := String(_order_by_id(int(_picker.id)).get("npc", ""))
	var item := _item_at(ref)
	var res := Orders.fulfill(GameState.data, int(_picker.id), ref)
	_picker = {}
	if not res.ok:
		Hud.toast(res.reason)
		_render()
		return
	_save_and_notify(["coins", "inbox", "pantry", "orders", "friendship", "stats", "flags", "unlocks", "cupboard"])
	show_reaction(npc, item)
	if int(res.hearts_after) > int(res.hearts_before):
		Hud.toast("TOWN_DELIVERED_HEART", [int(res.coins)])
	else:
		Hud.toast("TOWN_DELIVERED", [int(res.coins)])
	Audio.play_jingle("jgl_order_done")
	_show_rewards(1.6)


func _do_gift(ref: Dictionary) -> void:
	var npc := String(_picker.id)
	var item := _item_at(ref)
	var res := Economy.gift(GameState.data, npc, ref)
	_picker = {}
	if not res.ok:
		Hud.toast(res.reason)
		_render()
		return
	_save_and_notify(["inbox", "pantry", "friendship", "flags", "unlocks", "cupboard"])
	Hud.toast("TOWN_GIFT_LOVED" if int(res.points) > 0 else "TOWN_GIFT_OK")
	show_reaction(npc, item)
	_show_rewards(1.6)


# ------------------------------------------------------------------ reactions (FUN-REACT)

## The item at `ref` before it leaves the save ({} when the ref is stale).
func _item_at(ref: Dictionary) -> Dictionary:
	if not Economy.valid_ref(GameState.data, ref):
		return {}
	return (State.get_item(GameState.data, ref) as Dictionary).duplicate()


## The neighbour's line about the jar they just got (an order or a gift) on a small card over the square: portrait,
## the line beside it, a heart pop when the jar meets their likes. While it is up the square's bubbles keep clear and
## the "Market today!" banner steps aside; it never takes input and goes by itself.
func show_reaction(npc: String, item: Dictionary) -> void:
	if item.is_empty() or String(item.get("kind", "")) != "product" or not npc in NPC_IDS:
		return
	var d: Dictionary = GameState.data
	var key := String(item.key)
	var desc := Reactions.describe(key, d.varieties, int(item.get("q", 2)))
	var line := Reactions.line(desc, npc, "", Reactions.seed_for(int(d.save_seed), int(d.day), key, npc))
	if line == "":
		return
	_end_reaction()
	var face := Bust.new()
	face.npc_id = npc
	var card := RV.DeliveryCard.new()
	card.name = "Reaction"
	card.position = REACT_AT
	add_child(card)
	var loved := Reactions.liked(desc, npc) != ""
	card.setup(face, line, loved)
	# TOWN-NAV: inside the picture band, clear of the tab row, the To-Do note and the garden signpost
	card.position = Vector2(clampf(card.position.x, 4.0, TAB_END - card.size.x),
			clampf(card.position.y, 60.0, maxf(60.0, PANEL_Y - 26 - card.size.y)))
	card.gone.connect(_end_reaction)
	_react_card = card
	if loved:
		Audio.play_sfx("sfx_sparkle")
	var r := Rect2(card.position, card.size).grow(2.0)
	if is_instance_valid(_banner) and _banner.visible and r.intersects(_banner.get_rect()):
		_banner.visible = false
		_react_undo.append(func() -> void:
			if is_instance_valid(_banner):
				_banner.visible = true)
	var bubbles: Node = get_node_or_null("Square/Bubbles")
	if bubbles != null:
		var before: Array[Rect2] = bubbles.get("blocked")
		var keep: Array[Rect2] = before.duplicate()
		keep.append(r)
		bubbles.set("blocked", keep)
		bubbles.call("clear")
		_react_undo.append(func() -> void:
			if is_instance_valid(bubbles):
				bubbles.set("blocked", before))


## The delivery card is gone (or replaced): the banner and the square's bubble spots come back.
func _end_reaction() -> void:
	if is_instance_valid(_react_card) and _react_card.get_parent() == self:
		remove_child(_react_card)
		_react_card.queue_free()
	_react_card = null
	for f: Callable in _react_undo:
		f.call()
	_react_undo.clear()


## Toasts the heart rewards earned since last time (one by one) with the level jingle; `delay` lets the
## previous toast be read first.
func _show_rewards(delay: float) -> void:
	var earned := Economy.take_rewards(GameState.data)
	if earned.is_empty():
		return
	Save.save_game(GameState.data)  # the queue is empty now: do not toast twice after a reload
	await get_tree().create_timer(delay).timeout
	for r: Dictionary in earned:
		var gift := String(r.get("kind", "")) == "gift"
		if gift:
			_gift_moment(r)
		Hud.toast(r.key, [int(r.get("count", 1))] if gift else [])
		Audio.play_jingle("jgl_level")
		await get_tree().create_timer(2.2).timeout


# ------------------------------------------------------------------ palette-rect drawings

## Neighbour portrait (48x48): the final one if present, else the approved candidate.
class Bust:
	extends Control
	const FILES := {"grocer": "barnaby", "baker": "rosie", "postman": "pip", "vintner": "vito", "librarian": "edith"}
	var npc_id := "grocer"
	var _tex: Texture2D

	func _ready() -> void:
		custom_minimum_size = Vector2(48, 48)
		var id: String = FILES.get(npc_id, "barnaby")
		for dir in ["res://assets/sprites/portraits/", "res://assets/sprites/portraits/candidates/"]:
			var path: String = "%sportrait_%s.png" % [dir, id]
			if ResourceLoader.exists(path):
				_tex = load(path) as Texture2D
				break
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		queue_redraw()

	func _draw() -> void:
		if _tex != null:
			draw_texture(_tex, Vector2.ZERO)


## Five hearts, `filled` of them lit.
class HeartRow:
	extends Control
	const PATTERN := [".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]
	var filled := 0

	func _draw() -> void:
		for h in 5:
			var col := Color("c94d2e") if h < filled else Color("49423d")
			for y in PATTERN.size():
				for x in 7:
					if PATTERN[y][x] == "X":
						draw_rect(Rect2(h * 16 + x * 2, y * 2, 2, 2), col)
