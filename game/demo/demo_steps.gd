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
const FESTIVAL := "res://ui/festival/festival.gd"
const FESTIVAL_FACTS := "res://ui/festival/festival_facts.gd"

var _recording := false
var _book: Node = null


func _ready() -> void:
	# OS.get_cmdline_args() leaves out engine flags such as --write-movie; the movie path is what tells.
	_recording = Engine.get_write_movie_path() != ""


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


## DEMO-02B · The Harvest Festival save (seed 24, day 14) as a temporary game, as the title's button loads it, with
## its director (the rare tree's marker, the cards); then `to`. With to = "" (a recording that starts inside a scene,
## at t = 0) `params` become Router.params for that first scene, e.g. {"biome": "forest", "grow": true} for the
## forest growing from its seed. `skip_start`: no start card in the garden (the trailer).
func festival_load(to: String = "", params: Dictionary = {}, skip_start: bool = false) -> void:
	var d: Dictionary = load(FESTIVAL_FACTS).load_save()
	if d.is_empty():
		push_warning("demo: no festival save")
		return
	if skip_start:
		d.flags.festival["started"] = true
	_gs().data = d
	_gs().notify(PackedStringArray(["*"]))
	load(TODO).ensure()
	load(FESTIVAL).ensure()
	if to != "":
		load(TRANSITION).go(to, params)
	else:
		get_node("/root/Router").params = params


## A button of the festival's start or end card ("go", "keep", "title"), as a click would.
func festival_choose(id: String) -> void:
	var f := get_tree().get_first_node_in_group("festival")
	var card: Variant = f.get("_card") if f != null else null
	if card is Node and is_instance_valid(card):
		card._choose(id)
	else:
		push_warning("demo: no festival card")


## The title without its menu: the painting, the name and the slogan (the trailer's last card). Called with the
## go("title") that leads there, it waits (up to 3 s) for the title to load behind the transition.
func title_card() -> void:
	for i in 180:
		var scene := _scene()
		var menu: CanvasItem = null
		if scene != null:
			menu = scene.get_node_or_null("%Menu") as CanvasItem
		if menu != null:
			menu.visible = false
			return
		await get_tree().process_frame


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


## FIX-JURY-B · Day - / + in the Forest Lab: the same seed's forest `delta` days on (A moves to B).
func lab_day(delta: int = 1) -> void:
	_scene().step_day(delta)


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


## Granny picks the nearest pickup with something to take ("ground" or "bush"; "" = either).
func wild_pick_near(kind: String = "") -> void:
	var w := _scene()
	var at: Vector2i = w.granny.current_cell()
	var best: Node = null
	var best_d := INF
	for p: Dictionary in w.map.pickups:
		if kind != "" and String(p.kind) != kind:
			continue
		var o: Node = w.view.find(String(p.kind), int(p.id))
		if o == null or not o.has_take():
			continue
		var d := Vector2(o.cell - at).length()
		if d < best_d:
			best_d = d
			best = o
	_approach(w, best)


## FIX-JURY-B · Granny picks the festival's new species beside the rare tree (else the nearest species pickup).
func wild_pick_species() -> void:
	var w := _scene()
	var want: Array = TodoRules.festival(_gs().data).get("species", [])
	var at: Vector2i = w.granny.current_cell()
	var best: Node = null
	var best_d := INF
	for p: Dictionary in w.map.pickups:
		if not bool(p.get("species", false)):
			continue
		var o: Node = w.view.find(String(p.kind), int(p.id))
		if o == null or not o.has_take():
			continue
		var d := Vector2(o.cell - at).length()
		for e: Dictionary in want:
			if String(e.get("type", "")) == String(p.type):
				d -= 1000.0  # the festival's own first
		if d < best_d:
			best_d = d
			best = o
	_approach(w, best)


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


## FIX-JURY-B · The cook panel's Invent button: the Invent panel opens (on the festival's Invent step with two stacks
## already picked); `ids` (variety ids or ingredient types: the first stack of that type) replace the picks when given.
func kitchen_invent(ids: Array = []) -> void:
	var k := _scene()
	k._panel.invent_button().pressed.emit()
	if ids.is_empty():
		return
	var fx: Node = k._fx_panel
	fx.components = []
	for want: String in ids:
		for e: Dictionary in fx.owned(_gs().data):
			if e.kind == "fresh" and (String(e.id) == want or State.type_of_variety(String(e.id)) == want):
				fx._on_cell(String(e.id))
				break


## Cook the invention: its mini-game plays itself, as kitchen_cook does for a recipe.
func kitchen_invent_cook(speed: float = 4.0, duration: float = 36.0, fast_all: bool = false) -> void:
	var k := _scene()
	k.debug_ctx = {"autoplay": true, "duration": duration}
	k._fx_panel._on_cook()
	await _fast_stir(k._mg, speed, fast_all)


## Cook: the mini-game plays itself (autoplay) for `duration` seconds, fast-forwarded `speed` times while it
## plays; the countdown and the result run at normal speed unless `fast_all` (then until the result card).
func kitchen_cook(speed: float = 4.0, duration: float = 36.0, fast_all: bool = false) -> void:
	var k := _scene()
	k.debug_ctx = {"autoplay": true, "duration": duration}
	k._panel._on_cook()
	await _fast_stir(k._mg, speed, fast_all)


## Fast-forwards a running stir mini-game while it plays (and, with `fast_all`, until it closes).
func _fast_stir(mg: Node, speed: float, fast_all: bool) -> void:
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


## DEMO-02B · Cook with the mini-game playing itself, without waiting for it (the press keeps its own wall clock, so
## a recording shows a few beats and ends it with kitchen_finish).
func kitchen_start(duration: float = 30.0) -> void:
	var k := _scene()
	k.debug_ctx = {"autoplay": true, "duration": duration}
	k._panel._on_cook()


## Ends the running mini-game with `stars` (what its last beat would send); the kitchen shows the result card.
func kitchen_finish(stars: int = 2) -> void:
	var mg: Variant = _scene().get("_mg")
	if mg is Node and is_instance_valid(mg) and mg.has_signal("finished"):
		mg.finished.emit({"stars": stars})


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


## DEMO-02B · Drags the inbox jar whose key holds `prefer` (else the newest) onto shelf cell (x, y) over `sec`: the
## festival's new jam into the room shelf's gap, which gives the pantry its third star.
func pantry_drag_to(x: int, y: int, prefer: String = "", sec: float = 1.2) -> void:
	var p := _scene()
	var board: Control = p.board
	var inbox: Array = _gs().data.inbox
	var index := -1
	for i in range(inbox.size() - 1, -1, -1):
		if String(inbox[i].get("kind", "")) != "product":
			continue
		if prefer == "" or String(inbox[i].get("key", "")).contains(prefer):
			index = i
			break
	if index < 0:
		push_warning("demo: no jar %s in the inbox" % prefer)
		return
	var item: Dictionary = inbox[index]
	var start: Vector2 = p.inbox_view.get_global_transform_with_canvas() * Vector2(p.inbox_view.slot_rect(index).get_center())
	if not board.begin_hold(item, {"where": "inbox", "index": index}, start):
		return
	var from: Vector2 = board.get_global_transform_with_canvas().affine_inverse() * start
	var to := Vector2(board.cell_rect(Vector2i(x, y)).get_center())
	var t := create_tween()
	t.tween_method(_hold_at.bind(board), from, to, sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_interval(0.15)
	t.tween_callback(_drop.bind(board))


# ---------------------------------------------------------------- town and letters

func town_tab(id: String) -> void:
	_scene()._on_tab(id)


## LIVING-TOWN: today's weather in the temp game (at t <= 0 it is set before the first scene loads).
func weather(w: String) -> void:
	_gs().data.weather = w
	_gs().notify(PackedStringArray(["weather"]))


## LIVING-TOWN: a click on a neighbour in the town square: they wave and their page opens in the Neighbours tab.
func town_neighbour(id: String) -> void:
	var square := _scene().get_node_or_null("Square")
	if square != null:
		square.poke(id)


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


## The market day without a scene change (a recording that starts in the market scene: --scene market.tscn);
## `weather` ("sunny", "rainy") sets the day's weather for the recording.
func market_prep(weather := "") -> void:
	var d: Dictionary = _gs().data
	var day := int(d.day)
	if not Market.is_market_day(day):
		d.day = (floori(float(day) / Market.EVERY) + 1) * Market.EVERY
	if weather != "":
		d.weather = weather
	_gs().notify(PackedStringArray(["day", "weather"]))


func market_fill() -> void:
	_scene()._on_fill()


func market_open() -> void:
	_scene()._on_open()


func market_speed() -> void:
	_scene()._on_speed()


## DEMO-02B · Ends the parade the way Esc does: the rest of the buyers settle at once and the end card shows.
func market_finish() -> void:
	var m := _scene()
	if int(m.get("_phase")) == 1:  # market.gd Phase.PARADE
		m._t = m._t_end
		m._step_parade()
		m._finish()


## The end card's "To town" (or Back while setting up).
func market_back() -> void:
	_scene()._on_back()


# ---------------------------------------------------------------- garden (GARDEN-LIFE)

## The day's weather before the garden scene loads (a recording that starts in it: --scene garden.tscn), so its hens,
## bees and butterflies follow it.
func garden_prep(weather := "sunny") -> void:
	_gs().data.weather = weather
	_gs().notify(PackedStringArray(["weather"]))


## Granny walks to a garden prop ("truck", "coop", "hive_1", "scarecrow", "bench") and uses it, as a click would.
func garden_use(id: String) -> void:
	var g := _scene()
	var p: Node = g.find_prop(id)
	if p == null:
		push_warning("demo: no garden prop %s" % id)
		return
	g.approach_prop(p)


## DEMO-02B · A click on a garden spot ("mailbox", "door", "compost", ...): Granny walks over and uses it.
func garden_spot(kind: String) -> void:
	var g := _scene()
	var s: Node = g.find_spot(kind)
	if s == null:
		push_warning("demo: no garden spot %s" % kind)
		return
	g.tap_world(s.hit_rect().get_center())


# ---------------------------------------------------------------- video (VIDEO-01)

## VIDEO-01 · The premise intro (FIRST-60: valley, cottage, jar, snow beyond the hills, garden) over the title, as New
## Game shows it, without starting a game: no new save, and the intro is driven here (its own _process is off), so it
## never reaches _leave() and the player's settings.cfg keeps its intro_seen. `captions` false hides its typed lines
## and the skip hint (the jury video draws its own Turkish captions). Plays to the last beat and stays there.
func intro_play(captions: bool = false) -> void:
	var title: Node = null
	for i in 180:
		title = _scene()
		if title != null and title.get_node_or_null("%Menu") != null:
			break
		await get_tree().process_frame
	if title == null or title.get_node_or_null("%Menu") == null:
		push_warning("demo: no title for the intro")
		return
	(title.get_node("%Menu") as CanvasItem).visible = false
	var premise: Control = (load("res://ui/premise/premise.tscn") as PackedScene).instantiate()
	premise.name = "VideoPremise"
	title.add_child(premise)
	premise.set_process(false)
	premise.set_process_unhandled_input(false)
	premise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var total: float = load("res://ui/premise/intro_beats.gd").total()
	var t := 0.0
	while t <= total and is_instance_valid(premise):
		premise.seek(t)
		if not captions:
			(premise.get("_caption_box") as CanvasItem).visible = false
			(premise.get("_hint") as CanvasItem).visible = false
		await get_tree().process_frame
		t += get_process_delta_time() / maxf(Engine.time_scale, 0.001)


## VIDEO-01 · Ends intro_play: the premise goes, the title painting stays without its menu (name, slogan, the valley).
func intro_end() -> void:
	var title := _scene()
	var premise: Node = title.get_node_or_null("VideoPremise") if title != null else null
	if premise != null:
		premise.queue_free()


# ---------------------------------------------------------------- video (VIDEO-02)

## VIDEO-02 · A click on a parlour object ("teo" the photo, "hat", "cat", "shelf", ...), as a click would.
func parlor_spot(kind: String) -> void:
	_scene()._on_spot(kind)


## VIDEO-02 · Granny walks to the garden cat and pets it, as a click on it would.
func garden_pet_cat() -> void:
	var g := _scene()
	g.tap_world(g.cat.hit_rect().get_center())


## VIDEO-02 · Cooks one jar of `recipe` from the first rarity-`rarity` variety of `type` in stock, straight into the
## inbox (no mini-game, no card): a recording that starts in the pantry then has a new jar to shelve.
func pantry_stock(recipe: String = "jam", type: String = "crabapple", rarity: String = "rare") -> void:
	var d: Dictionary = _gs().data
	var ids: Array = d.varieties.keys()
	ids.sort()
	for vid: String in ids:
		if State.type_of_variety(vid) != type or (rarity != "" and String(d.varieties[vid].get("rarity", "")) != rarity):
			continue
		if bool(Kitchen.cook(d, recipe, vid, "", "", 2).get("ok", false)):
			_gs().notify(PackedStringArray(["inbox", "pantry", "cupboard", "energy", "book", "stats"]))
			return
	push_warning("demo: could not stock a %s %s" % [rarity, type])


## TRAILER · Granny nods off in her rocking chair (kitchen doze, a hint day): sets a hint day in the temporary game and
## fills the idle clock, so the doze starts at once.
func kitchen_doze(hold: float = 6.0) -> void:
	var k := _scene()
	_gs().data.day = 92
	var t := 0.0
	while t < hold and is_instance_valid(k):
		if k._can_doze() and not k._doze.visible:
			k._idle = k.DOZE_AFTER
		t += get_process_delta_time()
		await get_tree().process_frame


## TRAILER · The day-30 visit film (scenes/finale): jumps to `t` seconds into it (kitchen 0-8, garden 8-18, snow 18-28).
func finale_seek(t: float) -> void:
	_scene().seek(t)


## TRAILER · The snow beat without its spoilers: no children and no line, only the snowy garden, Granny and the cat.
func finale_snow_clean() -> void:
	var snow: Node = _scene().shot("snow")
	for id in snow._figs.keys():
		snow._figs[id].free()
		snow._figs.erase(id)
	snow._snow._line_box.modulate.a = 0.0


## TRAILER · Like kitchen_start, with extra mini-game ctx (e.g. {"knead_time": 7, "trace_time": 5} for a shorter knead).
func kitchen_start_with(extra: Dictionary) -> void:
	var k := _scene()
	var ctx := {"autoplay": true, "duration": 30.0}
	ctx.merge(extra, true)
	k.debug_ctx = ctx
	k._panel._on_cook()


## TRAILER · `count` fresh units of ingredient `type` into the temporary game's inbox (and a few jars and salt in the
## cupboard), so a recipe that needs them can be cooked for the camera.
func kitchen_stock(type: String, count: int = 4) -> void:
	var d: Dictionary = _gs().data
	var dev: GDScript = load("res://ui/dev_panel/dev_tools.gd")
	d.inbox.append(State.fresh(dev.first_variety(d, type), count, int(Data.ingredients()[type].get("shelf_days", 5))))
	for id in ["jar", "salt", "vinegar"]:
		d.cupboard[id] = maxi(int(d.cupboard.get(id, 0)), 4)
	_gs().notify(PackedStringArray(["inbox", "cupboard"]))


## TRAILER · Drives a mini-game that has no autoplay ctx (pack_jar's bot is private and quits the game): calls its
## bot every frame until it closes.
func minigame_bot() -> void:
	var mg: Variant = _scene().get("_mg")
	while is_instance_valid(mg) and mg.is_inside_tree():
		mg._bot(get_process_delta_time())
		await get_tree().process_frame
