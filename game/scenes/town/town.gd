extends Control
## Town square (GD-TOWN): grocer (buy / sell), order board, neighbours (talk / gift). One 480x270 click scene.
## All rules come from Economy / Orders; this scene only lists, asks and shows results.
## The backdrop is a separate TextureRect ("Background") so ART can swap its texture.

const ICONS_JSON := "res://assets/sprites/icons/icons.json"
const ICONS_PNG := "res://assets/sprites/icons/icons.png"
const NPC_IDS := ["grocer", "baker", "postman"]

var _tab := "grocer"
var _sub := "buy"
var _npc := "grocer"
var _picker: Dictionary = {}  # {} or {"kind": "order"|"gift", "id": order id or npc id}
var _content: VBoxContainer
var _tab_buttons: Dictionary = {}
var _icon_sheet: Texture2D
var _icon_cells: Dictionary = {}
var _icon_size := Vector2(16, 16)


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_temp(1)
		_debug_fill()
	Forage.empty_bag_to_inbox(GameState.data)
	_load_icons()
	_paint_background()
	_build()
	GameState.changed.connect(func(_k: PackedStringArray) -> void: _render())
	Audio.play_music("mus_town")
	Audio.play_ambient("amb_town")
	_render()


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
	return holder


func _paint_background() -> void:
	var img := Image.create(480, 270, false, Image.FORMAT_RGBA8)
	img.fill(Color("415c5d"))  # dusk sky
	var rects := [
		[Rect2i(0, 0, 480, 40), Color("567c7d")],
		[Rect2i(0, 150, 480, 120), Color("53612e")],  # grass
		[Rect2i(0, 196, 480, 74), Color("83571e")],  # cobbles
		[Rect2i(24, 70, 120, 90), Color("62272c")],  # shop
		[Rect2i(24, 60, 120, 14), Color("a22512")],
		[Rect2i(40, 96, 24, 64), Color("3d1f29")],
		[Rect2i(80, 90, 48, 30), Color("e5bd7f")],
		[Rect2i(200, 90, 100, 70), Color("50361e")],  # board
		[Rect2i(206, 96, 88, 58), Color("c58845")],
		[Rect2i(340, 60, 100, 100), Color("b66813")],  # bakery
		[Rect2i(340, 52, 100, 12), Color("c94d2e")],
		[Rect2i(368, 100, 28, 60), Color("3d1f29")],
	]
	for r in rects:
		img.fill_rect(r[0], r[1])
	$Background.texture = ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ frame

func _build() -> void:
	var x := 8
	for t in [["grocer", tr("TOWN_TAB_GROCER")], ["orders", tr("TOWN_TAB_ORDERS")], ["neighbours", tr("TOWN_TAB_NEIGHBOURS")]]:
		var b := Button.new()
		b.text = t[1]
		b.position = Vector2(x, 52)
		b.size = Vector2(96, 20)
		b.pressed.connect(_on_tab.bind(t[0]))
		add_child(b)
		_tab_buttons[t[0]] = b
		x += 100
	var back := Button.new()
	back.text = tr("TOWN_BACK_GARDEN")
	back.position = Vector2(372, 52)
	back.size = Vector2(100, 20)
	back.pressed.connect(_on_back)
	add_child(back)
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 76)
	panel.size = Vector2(464, 186)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 2)
	scroll.add_child(_content)


func _on_tab(id: String) -> void:
	_tab = id
	_picker = {}
	_render()


func _on_back() -> void:
	Router.goto("garden" if Router.exists("garden") else "kitchen")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		if _picker.is_empty():
			_on_back()
		else:
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
		(_tab_buttons[id] as Button).disabled = id == _tab
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


## Everything the grocer would take: inbox first, then the pantry.
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
			return "%s x%d" % [d.varieties.get(item.variety, {}).get("name", item.variety), int(item.count)]
		"nut":
			return "%s x%d" % [String(item.type).capitalize(), int(item.count)]
	return "?"


func _item_icon(item: Dictionary) -> Control:
	if item.kind == "product":
		var ji := JarIcon.new()
		ji.view = "icon"
		ji.show_product(ProductGen.describe(item.key, GameState.data.varieties))
		return ji
	return _icon(State.item_type(item))


# ------------------------------------------------------------------ grocer

func _render_grocer() -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(_button(tr("TOWN_BUY"), _set_sub.bind("buy"), _sub == "buy"))
	head.add_child(_button(tr("TOWN_SELL"), _set_sub.bind("sell"), _sub == "sell"))
	head.add_child(_label(tr("TOWN_GROCER_HELLO")))
	_content.add_child(head)
	if _sub == "buy":
		_render_buy()
	else:
		_render_sell()


func _set_sub(s: String) -> void:
	_sub = s
	_render()


func _shop_ids() -> Array:
	var shop: Dictionary = Data.shop()
	var ids: Array = shop.buy.keys()
	for s in shop.seeds:
		ids.append("seed_" + s)
	ids.append("pantry_row")
	return ids


func _shop_name(id: String) -> String:
	return tr("TOWN_ITEM_" + id.to_upper())


func _render_buy() -> void:
	var d: Dictionary = GameState.data
	for id in _shop_ids():
		var price := Economy.price(d, id)
		if price < 0:
			continue
		var text := _shop_name(id)
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


func _render_sell() -> void:
	var d: Dictionary = GameState.data
	var list := _sellables()
	if list.is_empty():
		_content.add_child(_label(tr("TOWN_NOTHING_TO_SELL")))
		return
	for e in list:
		var price := Economy.sell_price(e.item, d.varieties)
		var text := "%s  -  %s" % [_item_name(e.item), tr("TOWN_PRICE") % price]
		_row(_item_icon(e.item), text, tr("TOWN_SELL"), _on_sell.bind(e.ref))


func _on_sell(ref: Dictionary) -> void:
	var res := Economy.sell(GameState.data, ref)
	if not res.ok:
		Hud.toast(res.reason)
		return
	_save_and_notify(["coins", "inbox", "pantry", "stats"])
	Hud.toast("TOWN_SOLD", [int(res.coins)])


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
		var recipe: String = Data.recipes().get(o.recipe, {}).get("name", o.recipe)
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
	for o in d.orders:
		var left := int(o.expires_day) - int(d.day)
		var days := tr("TOWN_LAST_DAY") if left <= 1 else tr("TOWN_DAYS_LEFT") % left
		var face := Bust.new()
		face.npc_id = o.npc
		face.custom_minimum_size = Vector2(16, 16)
		_row(face, "%s\n%s" % [_order_text(o), days], tr("TOWN_DELIVER"), _on_deliver.bind(int(o.id)))


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
			_render()
			return
	Hud.toast("UI_ORDER_NO_MATCH")


# ------------------------------------------------------------------ neighbours

func _render_neighbours() -> void:
	var d: Dictionary = GameState.data
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 10)
	_content.add_child(split)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 110
	split.add_child(list)
	for id in NPC_IDS:
		var b := Button.new()
		b.text = Data.npcs()[id].name
		b.custom_minimum_size = Vector2(104, 22)
		b.disabled = id == _npc
		b.pressed.connect(_select_npc.bind(id))
		list.add_child(b)
	var npc: Dictionary = Data.npcs()[_npc]
	var hearts := Economy.hearts(d, _npc)
	var bust := Bust.new()
	bust.npc_id = _npc
	bust.custom_minimum_size = Vector2(64, 64)
	bust.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	split.add_child(bust)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(info)
	info.add_child(_label("%s  -  %s" % [npc.name, tr("TOWN_ROLE_" + String(npc.role).to_upper())]))
	var hr := HeartRow.new()
	hr.filled = hearts
	hr.custom_minimum_size = Vector2(80, 12)
	info.add_child(hr)
	info.add_child(_label(tr("TOWN_LIKES") % _axis_text(npc.likes)))
	info.add_child(_label(tr("NPC_%s_%d" % [_npc.to_upper(), clampi(hearts / 2, 0, 2)])))
	var gift := _button(tr("TOWN_GIFT"), _on_gift)
	gift.custom_minimum_size = Vector2(72, 20)
	info.add_child(gift)


func _select_npc(id: String) -> void:
	_npc = id
	_render()


func _on_gift() -> void:
	var gifted: Dictionary = GameState.data.flags.get("gifted", {})
	if int(gifted.get(_npc, 0)) == int(GameState.data.day):
		Hud.toast("UI_GIFTED_TODAY")
		return
	if _products().is_empty():
		Hud.toast("TOWN_NO_JARS")
		return
	_picker = {"kind": "gift", "id": _npc}
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
	head.add_child(_button(tr("UI_CANCEL"), _close_picker))
	_content.add_child(head)
	var order: Dictionary = _order_by_id(int(_picker.id)) if _picker.kind == "order" else {}
	var shown := 0
	for e in _products():
		if _picker.kind == "order":
			if not Orders.matches(order, e.item, d.varieties):
				continue
			var coins := floori(ProductGen.value(e.item.key, d.varieties, int(e.item.q)) * float(Data.rules().orders.reward_mult))
			var text := "%s  -  %s" % [_item_name(e.item), tr("TOWN_REWARD") % coins]
			_row(_item_icon(e.item), text, tr("TOWN_GIVE"), _do_fulfill.bind(e.ref))
		else:
			_row(_item_icon(e.item), _item_name(e.item), tr("TOWN_GIVE"), _do_gift.bind(e.ref))
		shown += 1
	if shown == 0:
		_content.add_child(_label(tr("UI_ORDER_NO_MATCH")))


func _close_picker() -> void:
	_picker = {}
	_render()


func _do_fulfill(ref: Dictionary) -> void:
	var res := Orders.fulfill(GameState.data, int(_picker.id), ref)
	_picker = {}
	if not res.ok:
		Hud.toast(res.reason)
		_render()
		return
	_save_and_notify(["coins", "inbox", "pantry", "orders", "friendship", "stats"])
	if int(res.hearts_after) > int(res.hearts_before):
		Hud.toast("TOWN_DELIVERED_HEART", [int(res.coins)])
	else:
		Hud.toast("TOWN_DELIVERED", [int(res.coins)])


func _do_gift(ref: Dictionary) -> void:
	var res := Economy.gift(GameState.data, String(_picker.id), ref)
	_picker = {}
	if not res.ok:
		Hud.toast(res.reason)
		_render()
		return
	_save_and_notify(["inbox", "pantry", "friendship", "flags"])
	Hud.toast("TOWN_GIFT_LOVED" if int(res.points) > 0 else "TOWN_GIFT_OK")


# ------------------------------------------------------------------ palette-rect drawings

## Placeholder portrait bust drawn from palette rects (ART portraits replace it). Design grid 32x32.
## Boxes under 32 px draw a separate 16x16 layout, so scaling is always 1x or 2x.
class Bust:
	extends Control
	const LOOKS := {
		"grocer": {"skin": "e19064", "hair": "b9a697", "shirt": "738c7a", "extra": "f2d9c5", "bg": "275e4c"},
		"baker": {"skin": "e19064", "hair": "83571e", "shirt": "e5bd7f", "extra": "f2d9c5", "bg": "b66813"},
		"postman": {"skin": "e19064", "hair": "49423d", "shirt": "567c7d", "extra": "2e3f3f", "bg": "415c5d"},
	}
	var npc_id := "grocer"

	func _draw() -> void:
		var look: Dictionary = LOOKS.get(npc_id, LOOKS.grocer)
		var big := custom_minimum_size.x >= 32
		var u := 2 if big else 1  # pixels per design unit
		if big:
			_r(0, 0, 32, 32, look.bg, u)
			_r(6, 24, 20, 8, look.shirt, u)
			_r(12, 22, 8, 3, look.skin, u)
			_r(9, 8, 14, 15, look.skin, u)
			_r(8, 5, 16, 5, look.hair, u)
			_r(8, 8, 2, 8, look.hair, u)
			_r(22, 8, 2, 8, look.hair, u)
			_r(12, 14, 2, 2, "111010", u)
			_r(18, 14, 2, 2, "111010", u)
			_r(14, 19, 4, 1, "a22512", u)
			match npc_id:
				"grocer":
					_r(10, 26, 12, 6, look.extra, u)
				"baker":
					_r(9, 1, 14, 5, look.extra, u)
				"postman":
					_r(8, 3, 16, 4, look.extra, u)
					_r(8, 6, 18, 1, look.extra, u)
		else:
			_r(0, 0, 16, 16, look.bg, 1)
			_r(3, 12, 10, 4, look.shirt, 1)
			_r(6, 11, 4, 2, look.skin, 1)
			_r(4, 4, 8, 8, look.skin, 1)
			_r(4, 2, 8, 3, look.hair, 1)
			_r(6, 7, 1, 1, "111010", 1)
			_r(9, 7, 1, 1, "111010", 1)
			_r(7, 10, 2, 1, "a22512", 1)
			if npc_id == "baker":
				_r(4, 0, 8, 3, look.extra, 1)
			elif npc_id == "postman":
				_r(4, 1, 9, 2, look.extra, 1)

	func _r(x: int, y: int, w: int, h: int, c: String, u: int) -> void:
		draw_rect(Rect2(x * u, y * u, w * u, h * u), Color(c))


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
