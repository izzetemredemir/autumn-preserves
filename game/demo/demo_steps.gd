extends Node
## DEMO-02 · Route steps for the scripted demos (res://demo/*.json, `{"do": "<method>", "args": [...]}`), added by
## DemoDirector as its child "Steps" only when a timeline runs. Each step calls the scenes' own methods (what a
## click or key would call), so a demo plays the real game, never a mock. Steps that need a moment (typing, a
## drag, the mini-game) run on by themselves after the call.
## The demo save is loaded as a temporary game (flags.temp): a recording never writes the player's save.

const STIR_PLAY := 2  ## stir_pot Phase.PLAY
const STIR_DONE := 3  ## stir_pot Phase.DONE
## Loaded when used (like kitchen.gd does), so this script also compiles where autoloads are not registered.
const TRANSITION := "res://ui/transition/transition.gd"
const TODO := "res://ui/tutorial/granny_todo.gd"
const LETTERS_UI := "res://ui/letters/letters_ui.gd"
const BOOK := "res://ui/book/book.gd"

var _recording := false
var _book: Node = null


func _ready() -> void:
	_recording = OS.get_cmdline_args().has("--write-movie")


## Movie Maker runs while another window may have focus: Audio pauses music on focus loss, the recording should not.
func _process(_delta: float) -> void:
	if not _recording:
		return
	var audio := get_node_or_null("/root/Audio")
	var music: Variant = audio.get("_music") if audio != null else null
	if music is Array:
		for p: Variant in music:
			if p is AudioStreamPlayer and (p as AudioStreamPlayer).stream_paused:
				(p as AudioStreamPlayer).stream_paused = false


func _scene() -> Node:
	return get_tree().current_scene


func _gs() -> Node:
	return get_node("/root/GameState")


# ---------------------------------------------------------------- flow

## Scene change with the game's dither transition.
func go(id: String, params: Dictionary = {}) -> void:
	load(TRANSITION).go(id, params)


## Focus, then press a button of the current scene ("%SeedLab"), as a click would.
func press(path: String) -> void:
	var b := _scene().get_node_or_null(NodePath(path)) as BaseButton
	if b == null:
		push_warning("demo: no button %s" % path)
		return
	b.grab_focus()
	b.pressed.emit()


## The jury demo save (seed 452, day 3, rainy) as a temporary game, then `to` ("" = stay: a recording that starts
## inside a scene loads it at t = 0, before the scene's _ready).
func load_demo(to: String = "garden", params: Dictionary = {}) -> void:
	var d := DevTools.load_demo()
	if d.is_empty():
		push_warning("demo: no demo save")
		return
	if typeof(d.get("flags")) != TYPE_DICTIONARY:
		d["flags"] = {}
	d.flags["temp"] = true
	_gs().data = d
	_gs().notify(PackedStringArray(["*"]))
	load(TODO).ensure()
	if to != "":
		load(TRANSITION).go(to, params)


# ---------------------------------------------------------------- Seed Lab

## Types `text` into the seed field one letter at a time, then generates (Enter).
func lab_type(text: String, per_char: float = 0.12) -> void:
	var lab := _scene()
	var edit: LineEdit = lab.seed_edit
	edit.text = ""
	for i in text.length():
		edit.text = text.substr(0, i + 1)
		edit.caret_column = edit.text.length()
		await get_tree().create_timer(per_char).timeout
	if is_instance_valid(lab):
		lab._generate()


## Picks a biome in the drop-down ("forest", "vineyard", "creek"); the lab generates again, as on a pick.
func lab_biome(biome: String) -> void:
	var lab := _scene()
	var biomes: Array = lab.get_script().BIOMES
	var i := biomes.find(biome)
	if i >= 0:
		lab.biome_pick.select(i)
		lab._generate()


## Pans the map view by (dx, dy) px over `sec` (what WASD or a drag does).
func lab_pan(dx: float, dy: float, sec: float = 1.5) -> void:
	var lab := _scene()
	lab._set_overview(false)
	var from: Vector2 = lab._pan
	create_tween().tween_method(_set_pan.bind(lab), from, from + Vector2(dx, dy), sec) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_pan(v: Vector2, lab: Node) -> void:
	if is_instance_valid(lab):
		lab._pan = v
		lab._apply_pan()


func lab_grow() -> void:
	_scene()._grow_pressed()


## A tap during "Watch it grow": the next step.
func lab_next() -> void:
	var lab := _scene()
	if lab._playing:
		lab._next_step()


func lab_compare(on: bool) -> void:
	_scene().compare_btn.button_pressed = on


# ---------------------------------------------------------------- forest

## Granny walks up to the rare fruit tree (the demo's Sharp Crabapple) and shakes it.
func wild_shake_rare() -> void:
	var w := _scene()
	var varieties: Dictionary = _gs().data.varieties
	for t: Dictionary in w.map.fruit_trees:
		if String(varieties.get(String(t.variety), {}).get("rarity", "")) == "rare":
			_approach(w, w.view.find("fruit_tree", int(t.id)))
			return


## Granny picks the n-th pickup of today's special place (the mushroom ring).
func wild_pick_special(n: int = 0) -> void:
	var w := _scene()
	var found := 0
	for p: Dictionary in w.map.pickups:
		if bool(p.get("special", false)):
			if found == n:
				_approach(w, w.view.find(String(p.kind), int(p.id)))
				return
			found += 1


func wild_walk(x: int, y: int) -> void:
	_scene().granny.walk_to(Vector2i(x, y))


func _approach(w: Node, o: Node) -> void:
	if o == null or w.granny == null:
		push_warning("demo: nothing to walk to")
		return
	w.granny.approach(o.cell, w._use.bind(o))


# ---------------------------------------------------------------- kitchen

## Clicks a kitchen object ("stove", "counter", "pantry", ...).
func kitchen_spot(kind: String = "stove") -> void:
	_scene()._on_spot(kind)


## In the open cook panel: the recipe tab, then the first fresh stack of `type` (of `rarity` when given).
func kitchen_pick(recipe: String, type: String, rarity: String = "") -> void:
	var panel: Node = _scene()._panel
	panel._select_recipe(recipe)
	var varieties: Dictionary = _gs().data.varieties
	var ids: Array = panel.fresh_stock(_gs().data).keys()
	ids.sort()
	for vid: String in ids:
		if State.type_of_variety(vid) != type or not panel._fits("main", vid):
			continue
		if rarity == "" or String(varieties.get(vid, {}).get("rarity", "")) == rarity:
			panel._pick(vid, panel)
			return
	push_warning("demo: no %s %s to cook" % [rarity, type])


func kitchen_addin(id: String) -> void:
	_scene()._panel._select_addin(id)


## Cook: the mini-game plays itself (autoplay) for `duration` seconds, fast-forwarded `speed` times while it
## plays; the countdown and the result run at normal speed unless `fast_all` (then until the result card).
func kitchen_cook(speed: float = 4.0, duration: float = 36.0, fast_all: bool = false) -> void:
	var k := _scene()
	k.debug_ctx = {"autoplay": true, "duration": duration}
	k._panel._on_cook()
	var mg: Node = k._mg
	if mg == null or not ("phase" in mg):
		return
	if fast_all:
		Engine.time_scale = speed
	while is_instance_valid(mg) and int(mg.phase) < STIR_PLAY:
		await get_tree().process_frame
	Engine.time_scale = speed
	while is_instance_valid(mg) and int(mg.phase) < STIR_DONE:
		await get_tree().process_frame
	if fast_all:
		while is_instance_valid(mg) and mg.is_inside_tree():
			await get_tree().process_frame
	Engine.time_scale = 1.0


## Fast-forward (Engine.time_scale) for what follows, e.g. a "Watch it grow" in a trailer; 1 = normal.
func speed(scale: float) -> void:
	Engine.time_scale = scale


## Closes the result card (its button).
func card_close() -> void:
	var card: Node = _scene().get("_card")
	if card != null and is_instance_valid(card):
		card._on_close()


## The recipe book (B), on tab `tab`.
func book_open(tab: int = 0) -> void:
	_book = load(BOOK).open()
	if tab != 0 and _book != null:
		_book.show_book(tab)


## The book's "How it was made" card of the first variant whose key holds `prefer`.
func book_how(prefer: String) -> void:
	if _book == null or not is_instance_valid(_book):
		return
	for key: String in _gs().data.book.variants:
		if key.contains(prefer):
			_book.open_how(key)
			return


func book_close() -> void:
	if _book != null and is_instance_valid(_book):
		_book.close_book()
	_book = null


# ---------------------------------------------------------------- pantry

## Drags the newest jar from the inbox onto a free shelf cell it likes, over `sec` (a scripted drag).
func pantry_drag(sec: float = 1.2) -> void:
	var p := _scene()
	var board: Control = p.board
	var inbox: Array = _gs().data.inbox
	var index := -1
	for i in range(inbox.size() - 1, -1, -1):
		if String(inbox[i].get("kind", "")) == "product":
			index = i
			break
	if index < 0:
		return
	var item: Dictionary = inbox[index]
	var target := _free_cell(board, item)
	if target.x < 0:
		return
	var start: Vector2 = p.inbox_view.get_global_transform_with_canvas() * Vector2(p.inbox_view.slot_rect(index).get_center())
	if not board.begin_hold(item, {"where": "inbox", "index": index}, start):
		return
	var from: Vector2 = board.get_global_transform_with_canvas().affine_inverse() * start
	var to := Vector2(board.cell_rect(target).get_center())
	var t := create_tween()
	t.tween_method(_hold_at.bind(board), from, to, sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_interval(0.15)
	t.tween_callback(_drop.bind(board))


func _hold_at(v: Vector2, board: Control) -> void:
	if is_instance_valid(board):
		board.move_hold_to(v)


func _drop(board: Control) -> void:
	if is_instance_valid(board):
		board.drop_held()


## The first cell (row by row) where `item` fits in the zone it likes.
func _free_cell(board: Control, item: Dictionary) -> Vector2i:
	var b: Dictionary = board.board
	for y in int(b.rows):
		for x in int(b.cols):
			var c := Vector2i(x, y)
			if board.can_place_at(item, c, 0) and board.in_correct_zone_at(item, c, 0):
				return c
	return Vector2i(-1, -1)


func pantry_auto() -> void:
	_scene()._on_auto()


# ---------------------------------------------------------------- town and letters

func town_tab(id: String) -> void:
	_scene()._on_tab(id)


## "Deliver" on `npc`'s order: the picker lists the jars that match it.
func town_deliver(npc: String) -> void:
	for o: Dictionary in _gs().data.orders:
		if String(o.npc) == npc:
			_scene()._on_deliver(int(o.id))
			return


## "Give" in the open order picker: the matching jar whose key holds `prefer` (else the first match).
func town_give(prefer: String = "") -> void:
	var town := _scene()
	var picker: Dictionary = town._picker
	if picker.is_empty():
		return
	var order: Dictionary = town._order_by_id(int(picker.id))
	var best: Dictionary = {}
	for e: Dictionary in town._products():
		if Orders.matches(order, e.item, _gs().data.varieties):
			if best.is_empty() or (prefer != "" and String(e.item.key).contains(prefer)):
				best = e
	if not best.is_empty():
		town._do_fulfill(best.ref)


## A grandchild's thank-you letter with the drawing of Granny's jars, as two days later: a request from `kid`,
## a parcel of up to `jars` ready jars (the ones the request asks for first) packed with straw, the reply brought
## forward to today (a dev jump, like the panel's day jumps). Then the post office shows it.
func letters_reply(kid: String = "mia", jars: int = 2) -> void:
	var s: Dictionary = _gs().data
	var l := Letters.ensure(s)
	var letter := Letters.make_request(s, kid, Seeds.rng(int(s.save_seed), "letters", int(s.day)))
	l.inbox.append(letter)
	var picked: Array = []
	for req: Dictionary in letter.request:
		for src: Dictionary in Letters.parcel_sources(s):
			if picked.size() < jars and not picked.has(src.item) and Letters.item_meets(kid, req, src.item, s.varieties):
				picked.append(src.item)
				break
	for src: Dictionary in Letters.parcel_sources(s):
		if picked.size() < jars and not picked.has(src.item) and Letters.giftable(kid, src.item):
			picked.append(src.item)
	var entries: Array = []
	for it: Dictionary in picked:
		_box_place(entries, it)
	Letters.fill_straw(entries)
	var res := Letters.pack(s, int(letter.id), entries)
	if not bool(res.get("ok", false)):
		push_warning("demo: parcel not sent (%s)" % res.get("reason", ""))
		return
	for p: Dictionary in l.sent:
		if int(p.letter) == int(letter.id):
			p.reply_day = int(s.day)
	Letters.night(s)
	var reply_id := -1
	for x: Dictionary in l.inbox:
		if String(x.kind) == "reply" and int(x.get("re", -1)) == int(letter.id):
			reply_id = int(x.id)
	_gs().notify(PackedStringArray(["letters", "inbox", "pantry"]))
	load(LETTERS_UI).open(reply_id)


func _box_place(entries: Array, item: Dictionary) -> void:
	for y in Letters.BOX_ROWS:
		for x in Letters.BOX_COLS:
			var e := {"item": item, "x": x, "y": y, "rot": 0}
			if Letters.fits_box(entries + [e]):
				entries.append(e)
				return


func letters_close() -> void:
	var ui := get_tree().get_first_node_in_group("letters_ui")
	if ui != null:
		ui.close()


# ---------------------------------------------------------------- market

## Dev jump to the next market day (every 7th day), then the market scene.
func market_day() -> void:
	var d: Dictionary = _gs().data
	var day := int(d.day)
	if not Market.is_market_day(day):
		d.day = (floori(float(day) / Market.EVERY) + 1) * Market.EVERY
	_gs().notify(PackedStringArray(["day"]))
	load(TRANSITION).go("market")


func market_fill() -> void:
	_scene()._on_fill()


func market_open() -> void:
	_scene()._on_open()


func market_speed() -> void:
	_scene()._on_speed()
