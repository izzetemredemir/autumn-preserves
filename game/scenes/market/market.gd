extends Control
## Market day (MARKET, MARKET-LIVE; spec §7.7). The market square (ART-MARKET's background, layout and stall) with the
## five neighbours at their stalls, Granny in her nook, pigeons, sparrows, the dog, the fiddler, leaves and bunting.
## Setup: ready jars from the pantry and inbox go onto Granny's 6x2 counter (ArrangeBoard, rules from Market); the sign
## card shows the stall appeal live. "Open stall" runs Market.run once (sold jars leave the save, coins, reputation +1,
## saved), then a 30-45 s parade plays MarketCrowd: buyers and lookers walk the square over the walk graph, browse the
## stalls, stop at Granny's counter where their jar hops into their basket, strollers chat and kids chase the pigeons.
## An end card sums it up and goes back to town. Keyboard: Tab/arrows + Enter on the buttons, Esc = back (setup) /
## skip (parade). A click on a passer-by during the parade gets a hello.

const InboxView := preload("res://scenes/pantry/inbox_view.gd")
const Villager := preload("res://scenes/market/villager.gd")
const ML := preload("res://scenes/market/market_layout.gd")
const Life := preload("res://scenes/market/market_life.gd")
const Bubbles := preload("res://scenes/market/market_bubbles.gd")
const CrowdView := preload("res://scenes/market/crowd_view.gd")
const RAIN := "res://ui/hud/rain.tscn"
const COIN_ICON := "res://assets/sprites/ui/icon_coin.png"
const GRANNY := "res://assets/sprites/granny/granny_market.png"
const GRANNY_OLD := "res://assets/sprites/granny/granny_idle.png"
const CELL := 24
const SOUNDS := {"pick": "sfx_pantry_pick", "place": "sfx_pantry_place", "wrong": "sfx_pantry_wrong", "rotate": "sfx_piece_rotate"}
const FAST := 3.0
const HELLOS := 4
const HUD_RECTS: Array[Rect2] = [Rect2(4, 4, 150, 24), Rect2(400, 4, 76, 22)]
const C_PAPER_INK := Color("50361e")
const C_GOLD := Color("e5bd7f")
const C_BAR := Color("747c37")
const C_BAR_BG := Color("b9a697")

enum Phase { SETUP, PARADE, DONE }

var _phase := Phase.SETUP
var _layout: Dictionary = {}
var _counter := Rect2i(159, 156, 144, 48)
var _source: Array = []
var _entries: Array = []
var _board: ArrangeBoard
var _source_view: InboxView
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
var _world: Node2D
var _stall: Node2D
var _jar_layer: Node2D
var _granny: Sprite2D
var _granny_frames: Array[Texture2D] = []
var _vendors: Dictionary = {}
var _life: Node2D
var _bubbles: Control
var _crowd_view: Node
var _fx_layer: Control
# parade state
var _plan: Dictionary = {}
var _crowd: Dictionary = {}
var _jar_views: Dictionary = {}
var _sold_ids: Dictionary = {}
var _lines_done := 0
var _t := 0.0
var _t_end := 0.0
var _speed := 1.0
var _clock := 0.0
var _wave_until := -1.0
var _coins_target := 0
var _coins_shown := 0.0
var _sold := 0


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_temp(1)
		GameState.data.day = Market.EVERY
		GameState.data.inbox.append_array(sample_items())
	_layout = ML.load_layout()
	_counter = ML.rect((_layout.get("granny_stall", {}) as Dictionary).get("counter", [159, 156, 144, 48]))
	var bg := TextureRect.new()
	bg.texture = ML.background(_layout)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build_world()
	_build_board()
	_build_setup()
	_build_parade()
	for s in Market.sources(_data()):
		_source.append(s.item)
	_board.setup(Market.board(), _entries, {
		"item_size": PantryRules.item_size, "can_place": Market.can_place, "can_rotate": PantryRules.can_rotate,
	}, {"cell": CELL, "zone_colors": {Market.ZONE: ["00000000", "e19064"]}})
	_board.position = Vector2(_counter.position)
	_source_view.setup(_source, _board, _make_view)
	_refresh()
	if _rainy() and ResourceLoader.exists(RAIN):
		add_child((load(RAIN) as PackedScene).instantiate())
	Audio.play_music("mus_town")
	Audio.play_ambient("amb_market")
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


func _rainy() -> bool:
	return String(_data().get("weather", "sunny")) == "rainy"


func _exit_tree() -> void:
	Audio.stop_ambient("amb_market")


func _process(delta: float) -> void:
	var dt := delta * (_speed if _phase == Phase.PARADE else 1.0)
	_clock += dt
	if _phase == Phase.PARADE:
		_t += dt
		_step_parade()
		var target := float(_coins_target)
		if _coins_shown < target:
			_coins_shown = minf(target, _coins_shown + maxf(40.0, (target - _coins_shown) * 3.0) * dt)
			_coins_label.text = "+%d" % floori(_coins_shown)
		if _t >= _t_end:
			_finish()
	_step_vendors()
	_step_granny()
	_life.call("step", dt, _crowd_view.call("positions"))
	_bubbles.call("step", dt)


func _unhandled_input(event: InputEvent) -> void:
	if _phase == Phase.PARADE and event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p: Dictionary = _crowd_view.call("person_at", (event as InputEventMouseButton).position)
		if not p.is_empty():
			var id := int(p.id)
			_bubbles.call("say", "p%d" % id, "MARKET_HELLO_%d" % (1 + id % HELLOS), _head_of.bind(id), 4, 1.6)
			get_viewport().set_input_as_handled()
		return
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


## Builds the crowd from _plan (also used by the smoke test with a ready plan).
func start_parade() -> void:
	_phase = Phase.PARADE
	_setup_ui.visible = false
	_parade_ui.visible = true
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.set_process_unhandled_input(false)
	var d := _data()
	_crowd = MarketCrowd.build(int(d.save_seed), int(d.day), _plan.get("visits", []), _layout,
		int(Market.info(d).reputation), _rainy())
	_t_end = float(_crowd.length)
	# the jars move onto the stall itself (y-sorted with the crowd) and stay there until sold
	_board.visible = false
	_jar_views.clear()
	for i in _entries.size():
		var r := _board.entry_rect(i)
		var v := _make_view(_entries[i].item, int(_entries[i].get("rot", 0)), r.size)
		v.position = Vector2(_counter.position + r.position)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_jar_layer.add_child(v)
		_jar_views[i] = v
	_crowd_view.call("setup", _world, _crowd, _rainy())
	_sold_ids.clear()
	_lines_done = 0
	_t = 0.0
	_speed = 1.0
	_speed_btn.text = tr("UI_MARKET_SPEED")
	_coins_label.text = "+0"
	_sold_label.text = tr("UI_MARKET_SOLD") % 0
	_crowd_view.call("step", _t)
	_speed_btn.grab_focus.call_deferred()


func _entry_index(entry: Dictionary) -> int:
	for i in _entries.size():
		if is_same(_entries[i], entry):
			return i
	return -1


## Places the crowd for time _t, fires the sales they reach and the lines they say.
func _step_parade() -> void:
	_crowd_view.call("step", _t)
	for p in _crowd.people:
		if float(p.buy_t) >= 0.0 and _t >= float(p.buy_t) and not _sold_ids.has(int(p.id)):
			_sell(p)
	var lines: Array = _crowd.lines
	while _lines_done < lines.size() and float(lines[_lines_done].t) <= _t:
		var l: Dictionary = lines[_lines_done]
		_lines_done += 1
		if _t - float(l.t) > 1.0:
			continue
		var who := String(l.who)
		var head: Callable
		if who.begins_with("v"):
			head = _vendor_head.bind(who.substr(1))
		else:
			head = _head_of.bind(int(who.substr(1)))
		_bubbles.call("say", who, String(l.key), head, int(l.prio), float(l.dur))


func _head_of(id: int) -> Vector2:
	return _crowd_view.call("head", id)


func _vendor_head(id: String) -> Vector2:
	var n: Node2D = _vendors.get(id)
	if n == null:
		return Vector2.INF
	return n.position - Vector2(0, int(n.call("head_height")))


func _sell(p: Dictionary) -> void:
	_sold_ids[int(p.id)] = true
	var v: Dictionary = _plan.visits[int(p.visit)]
	_sold += 1
	_coins_target += int(v.price)
	_sold_label.text = tr("UI_MARKET_SOLD") % _sold
	Audio.play_sfx("sfx_coin_purse")
	_wave_until = _clock + 1.4
	var idx := _entry_index(v.entry)
	var view: Control = _jar_views.get(idx)
	var buyer: Node2D = _crowd_view.call("node_of", int(p.id))
	if view == null or not view.visible:
		return
	view.visible = false
	var hop := _make_view(v.item, int(v.entry.get("rot", 0)), Vector2i(view.size))
	hop.position = view.position
	hop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(hop)
	var to := hop.position + Vector2(0, 40)
	if buyer != null:
		# into the basket on their arm (about a third of their height up, on the left)
		var hand := buyer.position + Vector2(-6, -roundi(float(buyer.call("head_height")) * 0.32))
		to = hand - (hop.size / 2.0).floor()
	var tw := hop.create_tween()
	tw.set_speed_scale(_speed)
	tw.tween_property(hop, "position:y", hop.position.y - 10, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(hop, "position", to.round(), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(hop.queue_free)
	var plus := Label.new()
	plus.text = tr("UI_MARKET_COINS") % int(v.price)
	plus.add_theme_color_override("font_color", C_GOLD)
	plus.position = (view.position + Vector2(view.size.x, -6)).round()
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(plus)
	var tp := plus.create_tween()
	tp.set_speed_scale(_speed)
	tp.tween_property(plus, "position:y", plus.position.y - 12, 0.9)
	tp.tween_callback(plus.queue_free)


func _on_speed() -> void:
	_speed = 1.0 if _speed > 1.0 else FAST
	_speed_btn.text = tr("UI_MARKET_SPEED_ON") if _speed > 1.0 else tr("UI_MARKET_SPEED")
	Audio.play_ui("ui_click")


func _finish() -> void:
	if _phase != Phase.PARADE:
		return
	_phase = Phase.DONE
	for p in _crowd.get("people", []):
		if float(p.buy_t) >= 0.0 and not _sold_ids.has(int(p.id)):
			_sold_ids[int(p.id)] = true
			_sold += 1
			_coins_target += int(_plan.visits[int(p.visit)].price)
			var view: Control = _jar_views.get(_entry_index(_plan.visits[int(p.visit)].entry))
			if view != null:
				view.visible = false
	_crowd_view.call("clear")
	_bubbles.call("clear")
	_coins_shown = float(_coins_target)
	_coins_label.text = "+%d" % _coins_target
	_sold_label.text = tr("UI_MARKET_SOLD") % _sold
	_speed_btn.visible = false
	_speed = 1.0
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


# --- vendors and Granny --------------------------------------------------------------------------------------------

## Vendors play their acts from the crowd during the parade; before it, a calm loop of idle and tidying.
func _step_vendors() -> void:
	var acts_by := {}
	if _phase == Phase.PARADE:
		for v in _crowd.get("vendors", []):
			acts_by[String(v.id)] = v.acts
	var i := 0
	for id: String in _vendors:
		var n: Node2D = _vendors[id]
		var what := "idle"
		var t0 := 0.0
		if acts_by.has(id):
			for a in acts_by[id]:
				if _t >= float(a.t0) and _t < float(a.t1):
					what = String(a.do)
					t0 = float(a.t0)
					break
		else:
			var cyc := fmod(_clock + i * 2.3, 9.0)
			what = "wipe" if cyc > 6.5 else "idle"
		var tt := _t if _phase == Phase.PARADE else _clock
		var blink := fmod(tt + i * 0.9, 3.7) < 0.13
		match what:
			"wave":
				n.call("show_pose", "front", "wave", floori((tt - t0) * 4.0) % 2)
			"wipe":
				n.call("show_pose", "front", "wipe", floori(tt * 3.0) % 2)
			"arrange":
				n.call("show_pose", "front", "look", floori(tt / 0.7) % 2)
			_:
				n.call("show_pose", "front", "idle", floori(tt * 1.2 + i) % 2, blink)
		i += 1


func _step_granny() -> void:
	if _granny == null or _granny_frames.is_empty():
		return
	var f := floori(_clock * 1.2) % 2
	if _clock < _wave_until and _granny_frames.size() >= 4:
		f = 2 + floori(_clock * 5.0) % 2
	_granny.texture = _granny_frames[f % _granny_frames.size()]


# --- build -------------------------------------------------------------------------------------------------------

func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	_world.y_sort_enabled = true
	add_child(_world)
	var stall_def: Dictionary = _layout.get("granny_stall", {})
	var feet_y := int(stall_def.get("feet_y", int(stall_def.get("y", 110)) + int((stall_def.get("size", [180, 125]) as Array)[1])))
	# Granny's stall: sprite, sign, jars and Granny herself sort as one thing at the stall's feet
	_stall = Node2D.new()
	_stall.name = "Stall"
	_stall.position = Vector2(0, feet_y)
	_world.add_child(_stall)
	var inner := Node2D.new()
	inner.position = Vector2(0, -feet_y)
	_stall.add_child(inner)
	var stall_tex := ML.DIR + String(stall_def.get("sprite", "stall_granny.png"))
	if ResourceLoader.exists(stall_tex):
		var s := Sprite2D.new()
		s.texture = load(stall_tex) as Texture2D
		s.centered = false
		s.position = Vector2(int(stall_def.get("x", 153)), int(stall_def.get("y", 110)))
		inner.add_child(s)
	var sr := ML.rect(stall_def.get("sign", [188, 113, 111, 15]))
	var sign_label := _label(tr("UI_MARKET_SIGN"), &"PaperLabel")
	sign_label.name = "Sign"
	sign_label.position = Vector2(sr.position.x, sr.position.y - 2)
	sign_label.size = Vector2(sr.size.x, sr.size.y + 3)
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inner.add_child(sign_label)
	_jar_layer = Node2D.new()
	_jar_layer.name = "Jars"
	inner.add_child(_jar_layer)
	_build_granny(inner, ML.v(stall_def.get("granny", [316, 230])))
	for vd in _layout.get("vendors", []):
		var id := String(vd.get("id", ""))
		var v := Villager.new()
		v.name = "Vendor_" + id
		v.setup(Villager.vendor_look(id))
		v.position = ML.v(vd.get("stand", [0, 0])).round()
		_world.add_child(v)
		_vendors[id] = v
	_life = Life.new()
	_life.name = "Life"
	add_child(_life)
	var d := _data()
	_life.call("setup", _world, _layout, Seeds.seed_for(int(d.get("save_seed", 1)), "market", int(d.get("day", 7)), "life"))
	_crowd_view = CrowdView.new()
	_crowd_view.name = "Crowd"
	add_child(_crowd_view)


func _build_granny(parent: Node2D, at: Vector2) -> void:
	var path := GRANNY if ResourceLoader.exists(GRANNY) else GRANNY_OLD
	if not ResourceLoader.exists(path):
		return
	var tex := load(path) as Texture2D
	var fw := 22 if path == GRANNY else 16
	var pivot := Vector2(11, 44) if path == GRANNY else Vector2(8, 31)
	for i in floori(tex.get_width() / float(fw)):
		var a := AtlasTexture.new()
		a.atlas = tex
		a.region = Rect2(i * fw, 0, fw, tex.get_height())
		_granny_frames.append(a)
	_granny = Sprite2D.new()
	_granny.name = "Granny"
	_granny.texture = _granny_frames[0]
	_granny.centered = false
	_granny.offset = -pivot
	_granny.position = at.round()
	parent.add_child(_granny)


func _build_board() -> void:
	_board = ArrangeBoard.new()
	_board.name = "Stall"
	_board.sounds = SOUNDS
	_board.view_factory = _make_view
	_board.changed.connect(_refresh)
	_board.entry_added.connect(_on_entry_added)
	_board.released_outside.connect(_on_released_outside)
	_board.hold_ended.connect(func(_i: Dictionary, _p: bool) -> void: _refresh())
	add_child(_board)
	_board.position = Vector2(_counter.position)
	_fx_layer = Control.new()
	_fx_layer.name = "Fx"
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.size = Vector2(480, 270)
	add_child(_fx_layer)
	_bubbles = Bubbles.new()
	_bubbles.name = "Bubbles"
	add_child(_bubbles)
	var blocked: Array[Rect2] = [Rect2(_counter)]
	blocked.append_array(HUD_RECTS)
	_bubbles.set("blocked", blocked)


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
	# sign card (right, clear of the stall at x 153-333)
	var card := PanelContainer.new()
	card.theme_type_variation = &"PaperPanel"
	card.position = Vector2(338, 26)
	card.size = Vector2(138, 210)
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
		bar.custom_minimum_size = Vector2(118, 6)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_meta("value", 0.0)
		bar.draw.connect(_draw_bar.bind(bar))
		box.add_child(bar)
		_bars.append(bar)
	_visitors = _label("", &"PaperLabel")
	box.add_child(_visitors)
	_hint = _label("", &"PaperLabel")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(122, 0)
	_hint.add_theme_color_override("font_color", Color("83571e"))
	box.add_child(_hint)
	_open_btn = _button(tr("UI_MARKET_OPEN"), _on_open, Vector2(338, 242), Vector2(138, 22))


func _build_parade() -> void:
	_parade_ui = Control.new()
	_parade_ui.name = "Parade"
	_parade_ui.size = Vector2(480, 270)
	_parade_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_parade_ui.visible = false
	add_child(_parade_ui)
	var bar := PanelContainer.new()
	bar.position = HUD_RECTS[0].position
	bar.size = HUD_RECTS[0].size
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
	_speed_btn.position = HUD_RECTS[1].position
	_speed_btn.size = HUD_RECTS[1].size
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
