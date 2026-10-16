extends Control
## Market day (MARKET, spec §7.7). Setup: ready jars from the pantry and inbox go onto a 6x2 stall (ArrangeBoard,
## rules from Market); the sign card shows the stall appeal live. "Open stall" runs Market.run once (sold jars leave
## the save, coins, reputation +1, saved), then a 30-45 s accelerated parade of procedural villagers plays the
## result: buyers stop at their jar, say a line, the jar hops into their basket and the coins tick up. An end card
## sums it up and goes back to town. Keyboard: Tab/arrows + Enter on the buttons, Esc = back (setup) / skip (parade).

const InboxView := preload("res://scenes/pantry/inbox_view.gd")
const Villager := preload("res://scenes/market/villager.gd")
const StallArt := preload("res://scenes/market/stall_art.gd")
const BG := "res://assets/sprites/scenes/bg_town.png"
const COIN_ICON := "res://assets/sprites/ui/icon_coin.png"
const CELL := 24
const BOARD_POS := Vector2i(168, 140)
const SOUNDS := {"pick": "sfx_pantry_pick", "place": "sfx_pantry_place", "wrong": "sfx_pantry_wrong", "rotate": "sfx_piece_rotate"}
## Parade: walking speed (px/s), buyer stop, path ends, three walking lanes (feet y), total length.
const WALK := 46.0
const PAUSE := 1.7
const PATH_X0 := -12.0
const PATH_X1 := 492.0
const LANES := [250, 256, 262]
const T_MIN := 30.0
const T_MAX := 45.0
const FAST := 3.0
const C_PAPER_INK := Color("50361e")
const C_GOLD := Color("e5bd7f")
const C_BAR := Color("747c37")
const C_BAR_BG := Color("b9a697")

enum Phase { SETUP, PARADE, DONE }

var _phase := Phase.SETUP
var _source: Array = []
var _entries: Array = []
var _board: ArrangeBoard
var _source_view: InboxView
var _stall: StallArt
var _setup_ui: Control
var _parade_ui: Control
var _fill_btn: Button
var _open_btn: Button
var _back_btn: Button
var _speed_btn: Button
var _mult: Label
var _bars: Array[Control] = []
var _visitors: Label
var _hint: Label
var _no_jars: Label
var _coins_label: Label
var _sold_label: Label
var _end_card: PanelContainer
var _crowd_layer: Node2D
var _fx_layer: Control
# parade state
var _plan: Dictionary = {}
var _walkers: Array = []
var _t := 0.0
var _t_end := 0.0
var _speed := 1.0
var _coins_target := 0
var _coins_shown := 0.0
var _sold := 0


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_temp(1)
		GameState.data.day = Market.EVERY
		GameState.data.inbox.append_array(sample_items())
	var bg := TextureRect.new()
	bg.texture = load(BG) as Texture2D
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_stall()
	_build_setup()
	_build_parade()
	for s in Market.sources(_data()):
		_source.append(s.item)
	_board.setup(Market.board(), _entries, {
		"item_size": PantryRules.item_size, "can_place": Market.can_place, "can_rotate": PantryRules.can_rotate,
	}, {"cell": CELL, "zone_colors": {Market.ZONE: ["00000000", "e19064"]}})
	_board.position = Vector2(BOARD_POS)
	_source_view.setup(_source, _board, _make_view)
	_refresh()
	Audio.play_music("mus_town")
	Audio.play_ambient("amb_town")
	(_fill_btn if not _fill_btn.disabled else _back_btn).grab_focus.call_deferred()


## Run-alone and smoke content: a dozen ready jars of every vessel.
static func sample_items() -> Array:
	var out: Array = []
	for k in ["jam|apple_1|-", "jam|quince_1|ginger", "jam|crabapple_1|cinnamon", "pickle|cucumber_1|-",
			"chutney|pear_1|pepper_1|chili", "brined_mushroom|chanterelle_1|-", "fruit_butter|pear_2|honey",
			"pie|apple_1|-", "juice|apple_2|-", "pickle|cucumber_2|clove", "jam|blackberry_1|-", "jam|pear_1|-",
			"fruit_butter|apple_2|-", "pickle|cucumber_3|-"]:
		out.append(State.product(k, 2, 0))
	return out


func _data() -> Dictionary:
	return GameState.data


func _process(delta: float) -> void:
	if _phase != Phase.PARADE:
		return
	_t += delta * _speed
	_step_parade()
	var target := float(_coins_target)
	if _coins_shown < target:
		_coins_shown = minf(target, _coins_shown + maxf(40.0, (target - _coins_shown) * 3.0) * delta * _speed)
		_coins_label.text = "+%d" % floori(_coins_shown)
	if _t >= _t_end:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("cancel"):
		return
	get_viewport().set_input_as_handled()
	match _phase:
		Phase.SETUP:
			_on_back()
		Phase.PARADE:
			_t = _t_end
			_step_parade()
			_finish()
		Phase.DONE:
			_on_back()


# --- setup -------------------------------------------------------------------------------------------------------

func _refresh() -> void:
	var d := _data()
	var parts := Market.stall_parts(_entries, d.varieties)
	_mult.text = tr("UI_MARKET_MULT") % ("%.2f" % float(parts.mult))
	var vals := [float(parts.variety), float(parts.colour), float(parts.fill)]
	for i in _bars.size():
		_bars[i].set_meta("value", vals[i])
		_bars[i].queue_redraw()
	_visitors.text = tr("UI_MARKET_VISITORS") % Market.customer_count(int(Market.info(d).reputation), float(parts.mult))
	var can := Market.can_open(d)
	_open_btn.disabled = _entries.is_empty() or not can
	_hint.text = tr("UI_MARKET_HINT") if can else tr("UI_MARKET_CLOSED")
	_no_jars.visible = _source.is_empty() and _entries.is_empty() and not _board.is_holding()
	_fill_btn.text = tr("UI_MARKET_FILL") if _room_for_more() else tr("UI_MARKET_CLEAR")
	_fill_btn.disabled = _source.is_empty() and _entries.is_empty()


func _room_for_more() -> bool:
	var b := Market.board()
	for it in _source:
		if not Market.first_spot(b, _entries, it).is_empty():
			return true
	return false


func _on_fill() -> void:
	_board.cancel_hold()
	var d := _data()
	if _room_for_more():
		var all: Array = _source.duplicate()
		for e in _entries:
			all.append(e.item)
		_entries.clear()
		_entries.append_array(Market.auto_stall(all, d.varieties))
		_source.clear()
		for it in all:
			if not _on_stall(it):
				_source.append(it)
		Audio.play_sfx("sfx_pantry_auto")
		_open_btn.grab_focus.call_deferred()
	else:
		for e in _entries:
			_source.append(e.item)
		_entries.clear()
		Audio.play_sfx("sfx_pantry_pick")
	_board.notify_changed()
	_board.pop_all()
	_source_view.refresh()
	_refresh()


func _on_stall(item: Dictionary) -> bool:
	for e in _entries:
		if is_same(e.item, item):
			return true
	return false


func _on_entry_added(_index: int, from: Dictionary) -> void:
	if String(from.get("where", "")) != "inbox":
		return
	var i := int(from.get("index", -1))
	if i >= 0 and i < _source.size():
		_source.remove_at(i)
	_source_view.refresh()


## A jar dragged off the stall goes back to the jar column.
func _on_released_outside(item: Dictionary, from: Dictionary, _global_pos: Vector2) -> void:
	if String(from.get("where", "")) != "board":
		return
	_board.remove_entry(int(from.index))
	_source.append(item)
	_source_view.refresh()
	_refresh()


func _on_back() -> void:
	if _board != null:
		_board.cancel_hold()
	Audio.play_ui("ui_back")
	Router.goto("town" if Router.exists("town") else "title")


func _make_view(item: Dictionary, rot: int, px: Vector2i) -> Control:
	return ArrangeItemView.make(item, rot, px, _data().get("varieties", {}))


# --- open stall and parade -----------------------------------------------------------------------------------------

func _on_open() -> void:
	_board.cancel_hold()
	var d := _data()
	if _entries.is_empty() or not Market.can_open(d):
		Audio.play_ui("ui_error")
		return
	_plan = Market.plan(d, _entries)
	Market.run(d, _entries)
	_save(["coins", "inbox", "pantry", "market", "stats"])
	Audio.play_sfx("sfx_shop_bell")
	start_parade()


## Builds the walkers from _plan (also used by the smoke test with a ready plan).
func start_parade() -> void:
	_phase = Phase.PARADE
	_setup_ui.visible = false
	_parade_ui.visible = true
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.set_process_unhandled_input(false)
	var visits: Array = _plan.get("visits", [])
	var n := visits.size()
	var cross := (PATH_X1 - PATH_X0) / WALK
	var total := clampf(10.0 + n * 2.0, T_MIN, T_MAX)
	var gap := maxf(0.6, (total - cross - PAUSE) / maxf(1.0, n - 1.0))
	_walkers.clear()
	_t_end = 0.0
	for i in n:
		var v: Dictionary = visits[i]
		var c: Dictionary = v.customer
		var w := {"visit": v, "spawn": i * gap, "lane": int(LANES[i % LANES.size()]), "stop": -1.0,
			"sold": false, "node": null, "bubble": null}
		var exit_t: float = w.spawn + cross
		if not (v.item as Dictionary).is_empty():
			var idx := _entry_index(v.entry)
			var r := _board.entry_rect(idx) if idx >= 0 else Rect2i(60, 0, 24, 24)
			w.stop = float(BOARD_POS.x + r.position.x + floori(r.size.x / 2.0))
			w["index"] = idx
			w["arrive"] = float(w.spawn) + (float(w.stop) - PATH_X0) / WALK
			w["leave"] = float(w.arrive) + PAUSE
			exit_t = float(w.leave) + (PATH_X1 - float(w.stop)) / WALK
		else:
			w["talk"] = float(w.spawn) + (240.0 - PATH_X0) / WALK
		w["exit"] = exit_t
		_t_end = maxf(_t_end, exit_t)
		var node := Villager.new()
		node.setup(int(c.look), bool(c.fancy))
		node.visible = false
		node.z_index = int(w.lane)
		_crowd_layer.add_child(node)
		w.node = node
		_walkers.append(w)
	_t = 0.0
	_speed = 1.0
	_speed_btn.text = tr("UI_MARKET_SPEED")
	_coins_label.text = "+0"
	_sold_label.text = tr("UI_MARKET_SOLD") % 0
	_speed_btn.grab_focus.call_deferred()


func _entry_index(entry: Dictionary) -> int:
	for i in _entries.size():
		if is_same(_entries[i], entry):
			return i
	return -1


## Places every walker for time _t and fires the sales they reach.
func _step_parade() -> void:
	for w in _walkers:
		var node: Node2D = w.node
		var s: float = w.spawn
		if _t < s or _t > float(w.exit):
			node.visible = false
			_show_bubble(w, false)
			continue
		var x: float
		var walking := true
		var buyer := float(w.stop) >= 0.0
		if buyer:
			if _t < float(w.arrive):
				x = PATH_X0 + WALK * (_t - s)
			elif _t < float(w.leave):
				x = float(w.stop)
				walking = false
			else:
				x = float(w.stop) + WALK * (_t - float(w.leave))
		else:
			x = PATH_X0 + WALK * (_t - s)
		node.visible = true
		node.position = Vector2(roundi(x), int(w.lane))
		node.set_frame(floori(_t * 7.0) % 4 if walking else 1)
		if buyer:
			if not bool(w.sold) and _t >= float(w.arrive) + 0.2:
				_sell(w)
			_show_bubble(w, _t >= float(w.arrive) + 0.1 and _t < float(w.leave) + 0.6)
		else:
			_show_bubble(w, _t >= float(w.talk) - 0.3 and _t < float(w.talk) + 1.5)
		var bub: Control = w.bubble
		if bub != null and bub.visible:
			var bx := clampi(roundi(x) - floori(bub.size.x / 2.0), 2, 478 - int(bub.size.x))
			bub.position = Vector2(bx, int(w.lane) - 50 - int(bub.size.y))


func _sell(w: Dictionary) -> void:
	w.sold = true
	var v: Dictionary = w.visit
	_sold += 1
	_coins_target += int(v.price)
	_sold_label.text = tr("UI_MARKET_SOLD") % _sold
	Audio.play_sfx("sfx_coins_gain")
	var idx := int(w.get("index", -1))
	var view := _board.view_at(idx)
	if view == null or not view.visible:
		return
	view.visible = false
	var hop := _make_view(v.item, int(v.entry.get("rot", 0)), Vector2i(view.size))
	hop.position = view.global_position.floor()
	_fx_layer.add_child(hop)
	var node: Node2D = w.node
	var to := Vector2(node.position.x - floori(hop.size.x / 2.0), node.position.y - 22 - hop.size.y)
	var tw := hop.create_tween()
	tw.set_speed_scale(_speed)
	tw.tween_property(hop, "position:y", hop.position.y - 10, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(hop, "position", to.round(), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(hop.queue_free)
	var plus := Label.new()
	plus.text = tr("UI_MARKET_COINS") % int(v.price)
	plus.add_theme_color_override("font_color", C_GOLD)
	plus.position = Vector2(roundi(node.position.x) + 10, int(node.position.y) - 44)
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(plus)
	var tp := plus.create_tween()
	tp.set_speed_scale(_speed)
	tp.tween_property(plus, "position:y", plus.position.y - 12, 0.9)
	tp.tween_callback(plus.queue_free)


func _show_bubble(w: Dictionary, on: bool) -> void:
	var bub: PanelContainer = w.bubble
	if not on:
		if bub != null:
			bub.visible = false
		return
	if bub == null:
		bub = PanelContainer.new()
		bub.theme_type_variation = &"PaperPanel"
		bub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.theme_type_variation = &"PaperLabel"
		l.text = tr(String(w.visit.line_key))
		bub.add_child(l)
		_fx_layer.add_child(bub)
		bub.reset_size()
		w.bubble = bub
		bub.visible = false
	if not bub.visible:
		bub.visible = true
		bub.pivot_offset = Vector2(floori(bub.size.x / 2.0), bub.size.y)
		bub.scale = Vector2(0.5, 0.5)
		bub.create_tween().tween_property(bub, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_speed() -> void:
	_speed = 1.0 if _speed > 1.0 else FAST
	_speed_btn.text = tr("UI_MARKET_SPEED_ON") if _speed > 1.0 else tr("UI_MARKET_SPEED")
	Audio.play_ui("ui_click")


func _finish() -> void:
	if _phase != Phase.PARADE:
		return
	_phase = Phase.DONE
	for w in _walkers:
		if float(w.stop) >= 0.0 and not bool(w.sold):
			w.sold = true
			_sold += 1
			_coins_target += int(w.visit.price)
		(w.node as Node2D).visible = false
		_show_bubble(w, false)
	_coins_shown = float(_coins_target)
	_coins_label.text = "+%d" % _coins_target
	_sold_label.text = tr("UI_MARKET_SOLD") % _sold
	_speed_btn.visible = false
	var placed := _entries.size()
	var rep := int(Market.info(_data()).reputation)
	var box := _end_card.get_node("Box") as VBoxContainer
	(box.get_node("Sold") as Label).text = tr("UI_MARKET_DONE_SOLD") % [_sold, placed]
	(box.get_node("Coins") as Label).text = tr("UI_MARKET_DONE_COINS") % _coins_target
	(box.get_node("Rep") as Label).text = tr("UI_MARKET_DONE_REP") % rep
	_end_card.visible = true
	_end_card.pivot_offset = (_end_card.size / 2.0).floor()
	_end_card.scale = Vector2(0.6, 0.6)
	_end_card.create_tween().tween_property(_end_card, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	(box.get_node("ToTown") as Button).grab_focus.call_deferred()
	Audio.play_jingle("jgl_order_done")


func _save(keys: Array) -> void:
	if not bool(_data().get("flags", {}).get("temp", false)):
		Save.save_game(_data())
	GameState.notify(PackedStringArray(keys))


# --- build -------------------------------------------------------------------------------------------------------

func _build_stall() -> void:
	_stall = StallArt.new()
	_stall.size = Vector2(480, 270)
	_stall.board_rect = Rect2i(BOARD_POS, Vector2i(Market.COLS * CELL, Market.ROWS * CELL))
	add_child(_stall)
	var sign_label := _label(tr("UI_MARKET_SIGN"), &"PaperLabel")
	var sr: Rect2i = _stall.sign_rect()
	sign_label.position = Vector2(sr.position.x, sr.position.y + 1)
	sign_label.size = Vector2(sr.size.x, sr.size.y - 2)
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(sign_label)
	_board = ArrangeBoard.new()
	_board.name = "Stall"
	_board.sounds = SOUNDS
	_board.view_factory = _make_view
	_board.changed.connect(_refresh)
	_board.entry_added.connect(_on_entry_added)
	_board.released_outside.connect(_on_released_outside)
	_board.hold_ended.connect(func(_i: Dictionary, _p: bool) -> void: _refresh())
	add_child(_board)
	_board.position = Vector2(BOARD_POS)
	_crowd_layer = Node2D.new()
	_crowd_layer.name = "Crowd"
	add_child(_crowd_layer)
	_fx_layer = Control.new()
	_fx_layer.name = "Fx"
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.size = Vector2(480, 270)
	add_child(_fx_layer)


func _build_setup() -> void:
	_setup_ui = Control.new()
	_setup_ui.name = "Setup"
	_setup_ui.size = Vector2(480, 270)
	_setup_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_setup_ui)
	move_child(_setup_ui, _board.get_index())
	var title := _label(tr("UI_MARKET_TITLE"), &"Heading")
	title.position = Vector2(160, 4)
	title.size = Vector2(160, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_setup_ui.add_child(title)
	# jar column (left)
	var left := PanelContainer.new()
	left.position = Vector2(4, 26)
	left.size = Vector2(146, 210)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_ui.add_child(left)
	var head := _label(tr("UI_MARKET_YOUR_JARS"), &"Heading")
	head.position = Vector2(12, 30)
	_setup_ui.add_child(head)
	_source_view = InboxView.new()
	_source_view.name = "Jars"
	_source_view.position = Vector2(13, 52)
	_source_view.size = Vector2(128, 176)
	_setup_ui.add_child(_source_view)
	_no_jars = _label(tr("UI_MARKET_NO_JARS"))
	_no_jars.position = Vector2(16, 70)
	_no_jars.size = Vector2(120, 100)
	_no_jars.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_jars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_setup_ui.add_child(_no_jars)
	_back_btn = _button(tr("UI_BACK"), _on_back, Vector2(4, 242), Vector2(56, 22))
	_fill_btn = _button(tr("UI_MARKET_FILL"), _on_fill, Vector2(64, 242), Vector2(86, 22))
	# sign card (right)
	var card := PanelContainer.new()
	card.theme_type_variation = &"PaperPanel"
	card.position = Vector2(330, 26)
	card.size = Vector2(146, 210)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_ui.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	box.add_child(_label(tr("UI_MARKET_APPEAL"), &"PaperLabel"))
	_mult = _label("", &"PaperLabel")
	_mult.add_theme_font_size_override("font_size", 36)
	_mult.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_mult)
	for key in ["UI_MARKET_VARIETY", "UI_MARKET_COLOURS", "UI_MARKET_FULL"]:
		box.add_child(_label(tr(key), &"PaperLabel"))
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(126, 6)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_meta("value", 0.0)
		bar.draw.connect(_draw_bar.bind(bar))
		box.add_child(bar)
		_bars.append(bar)
	_visitors = _label("", &"PaperLabel")
	box.add_child(_visitors)
	_hint = _label("", &"PaperLabel")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(130, 0)
	_hint.add_theme_color_override("font_color", Color("83571e"))
	box.add_child(_hint)
	_open_btn = _button(tr("UI_MARKET_OPEN"), _on_open, Vector2(330, 242), Vector2(146, 22))


func _build_parade() -> void:
	_parade_ui = Control.new()
	_parade_ui.name = "Parade"
	_parade_ui.size = Vector2(480, 270)
	_parade_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parade_ui.visible = false
	add_child(_parade_ui)
	var bar := PanelContainer.new()
	bar.position = Vector2(4, 4)
	bar.size = Vector2(150, 24)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parade_ui.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)
	if ResourceLoader.exists(COIN_ICON):
		var icon := TextureRect.new()
		icon.texture = load(COIN_ICON) as Texture2D
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	_coins_label = _label("+0")
	_coins_label.add_theme_color_override("font_color", C_GOLD)
	_coins_label.custom_minimum_size = Vector2(48, 0)
	row.add_child(_coins_label)
	_sold_label = _label("")
	row.add_child(_sold_label)
	_speed_btn = Button.new()
	_speed_btn.text = tr("UI_MARKET_SPEED")
	_speed_btn.position = Vector2(400, 4)
	_speed_btn.size = Vector2(76, 22)
	_speed_btn.pressed.connect(_on_speed)
	_parade_ui.add_child(_speed_btn)
	# end card
	_end_card = PanelContainer.new()
	_end_card.theme_type_variation = &"PaperPanel"
	_end_card.position = Vector2(130, 40)
	_end_card.size = Vector2(220, 150)
	_end_card.visible = false
	_parade_ui.add_child(_end_card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 3)
	_end_card.add_child(box)
	var t := _label(tr("UI_MARKET_DONE"), &"PaperLabel")
	t.add_theme_font_size_override("font_size", 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	for n in ["Sold", "Coins", "Rep"]:
		var l := _label("", &"PaperLabel")
		l.name = n
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	var next := _label(tr("UI_MARKET_DONE_NEXT"), &"PaperLabel")
	next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next.add_theme_color_override("font_color", Color("83571e"))
	box.add_child(next)
	var to_town := Button.new()
	to_town.name = "ToTown"
	to_town.text = tr("UI_MARKET_TO_TOWN")
	to_town.custom_minimum_size = Vector2(120, 22)
	to_town.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	to_town.pressed.connect(_on_back)
	box.add_child(to_town)


func _draw_bar(bar: Control) -> void:
	var w := int(bar.size.x)
	var v := clampf(float(bar.get_meta("value", 0.0)), 0.0, 1.0)
	bar.draw_rect(Rect2(0, 0, w, 6), C_PAPER_INK)
	bar.draw_rect(Rect2(1, 1, w - 2, 4), C_BAR_BG)
	var fill := roundi((w - 2) * v)
	if fill > 0:
		bar.draw_rect(Rect2(1, 1, fill, 4), C_BAR)
		bar.draw_rect(Rect2(1, 1, fill, 1), Color("b7b768"))


func _label(text: String, variation: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _button(text: String, cb: Callable, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	_setup_ui.add_child(b)
	return b
