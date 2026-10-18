extends SceneTree
## QA-WEEK · One-week play-through bot (spec §8.4-8.5, tech-spec §7). A new game (seed 452) played from day 1 to day 8
## through the real scenes with clicks, taps, drags and key presses, the way a player would: Granny's To-Do of days 1
## and 2, shaking trees and foraging, cooking at every station it can reach (stove, counter, and from day 3, after the
## dev panel's "Unlock P1", the fruit press and the dough board), jars into the pantry, orders and buying in town
## (CUT-CLUTTER: no grocer's Sell; coins come from orders and the market, and they must never stop a jam), heart
## gifts, letters from the mailbox (read, pack, send), the day-7 market, the bed every night, day 8's harvest calendar
## and weather (HUD, morning card, the wild).
## Records every SCRIPT ERROR and engine error (an OS logger), warnings and warning floods, soft-locks (no progress for
## 10 s), scenes that fail to load and coin/energy anomalies (each action's cost or gain checked against the rules,
## plus coins/energy moving outside an action). One screenshot per scene visit in user://week_bot/.
## Writes the problem table to docs/qa/week_bot.md (everything from "## Triage notes" on is kept) and exits 1 when a
## high-severity problem was found. The player's save is backed up first and restored at the end.
## Mini-games run on the kitchen's QA autoplay (Kitchen.debug_ctx). The jar packer has none: its own demo packer stacks
## the pieces, the bot pours the brine by holding the mouse and twists the lid with three clicks.
##   perl -e 'alarm shift; exec @ARGV' 900 godot --path game --audio-driver Dummy -s res://tests/smoke/week_bot.gd -- --locale=en
##   [-- --speed 1]   default 2 (Engine.time_scale, so the week fits in 10 minutes). Windowed, not headless.
## QA-02 soak run: `-- --days N` plays N whole days (the bed every night) and stops on the morning of day N + 1. On top
## of the week it buys upgrades as coins allow (the press instead of the dev panel), batch-cooks Mastered variants,
## fills the big pot, takes turns between the open wild biomes, runs day 8's calendar and weather checks on the way,
## and records frame-time spikes (> 50 ms), memory and object/node counts per day (flagging growth that does not level
## off). It writes docs/qa/soak.md (screenshots in user://soak/); the time budget grows with N.
##   perl -e 'alarm shift; exec @ARGV' 2400 godot --path game --audio-driver Dummy -s res://tests/smoke/week_bot.gd -- --days 20
## Scene and UI scripts are reached by path or duck typing (a SceneTree script cannot name classes that use autoloads).

const SEED := 452
const LAST_DAY := 8
const DIR := "user://week_bot"
const SAVE_PATH := "user://save.json"  ## Save.PATH
const BAK_PATH := "user://save.bak"  ## the atomic save's backup: restored too, the user's profile is never touched
const REPORT := "../docs/qa/week_bot.md"  ## next to res://
const NOTES := "## Triage notes"
const STALL_MS := 10000  ## no progress this long = soft-lock
const MG_STALL_MS := 45000  ## a mini-game may sit in one phase this long
const BUDGET_MS := 570000  ## the run must end within 10 minutes
const FLOOD_SAME := 10  ## the same warning this often = warning flood
const FLOOD_VISIT := 30  ## this many warnings in one scene visit = warning flood
const KEEP_ENERGY := 28  ## energy kept for the kitchen while foraging
const SUPPLIES := {"jar": 4, "sugar": 3, "salt": 2, "vinegar": 2}
const P1_SUPPLIES := {"bottle": 2, "flour": 4}
const AUTOPLAY := {"autoplay": true, "duration": 4.0, "knead_time": 3.0, "trace_time": 2.0}
## Stations in the order the bot cooks, each with its recipes in order of preference.
const STATIONS := {
	"stove": ["jam", "fruit_butter", "chutney", "syrup"],
	"counter": ["brined_mushroom", "pickle", "kraut"],
	"press": ["juice", "fruit_vinegar"],
	"board": ["bread", "pie"],
}
const STATION_UNLOCK := {"press": "press", "board": "knead"}
const USE_COST := {"fruit_tree": "shake_tree", "bush": "pick_bush", "ground": "pick_ground"}
const SEVERITY := ["high", "medium", "low", "info"]
const TITLE := "res://scenes/title/title.tscn"
const NIGHT_GD := "res://ui/transition/night.gd"
const TRANSITION_GD := "res://ui/transition/transition.gd"
const TODO_GD := "res://ui/tutorial/granny_todo.gd"
const WEATHER_GD := "res://scenes/wild/wild_weather.gd"
## Pack jar phases (PackJar.Phase).
const PACK := 1
const BRINE := 2
const LID := 3
## Soak run (QA-02).
const SOAK_DIR := "user://soak"
const SOAK_REPORT := "../docs/qa/soak.md"
const SOAK_MS_PER_DAY := 100000  ## time budget per soak day (the week needs about 50 s a day at x2)
const SPIKE_MS := 50.0  ## a frame longer than this is a spike
const SCENE_SPIKE_FRAMES := 3  ## a spike this many frames after the route or the scene changed belongs to the change
## Upgrades in the order a soak run saves up for them (the press first: its mini-game and the juice recipes).
const SOAK_UPGRADES := ["press", "beds", "bag", "pantry_row", "boots", "big_pot"]
const SOAK_RESERVE := 100  ## coins kept for supplies after an upgrade
## Least-squares growth per day over the second half of the soak that counts as "does not level off" (orphans: any
## steady growth, nothing should be left outside the tree).
const GROWTH_LIMIT := {"nodes": 3.0, "objects": 40.0, "orphans": 0.1, "resources": 10.0, "static_kb": 512.0}

var _log := Capture.new()
var _gs: Node
var _router: Node
var _save: Node
var _speed := 2.0
var _t0 := 0
var _dt := 0.016
var _had_save := false
var _backup := ""
var _had_bak := false
var _backup_bak := ""
var _aborted := ""
var _problems: Array = []
var _keys := {}
var _warns := {}
var _visit_warns := 0
var _visit_flooded := false
var _trail: Array[String] = []
var _shots := 0
var _visits: Array[String] = []
var _mask := 0
var _last_coins := -1
var _last_energy := -1
var _last_earned := 0
var _allow_coins := false
var _allow_energy := false
var _days: Array = []  ## one row per day: {"day", "weather", "coins", "energy", "energy_max", "cooked", "orders", "sold", "notes"}
var _mg_count := {}
var _morning: Array[String] = []  ## the last morning card's lines
var _notes: Array[String] = []  ## coverage lines for the report
var _seen_unlocks := {}
var _recipe_count := {}
var _first_letter := 0
var _soak_days := 0  ## --days N (0 = the classic week)
var _budget_ms := BUDGET_MS
var _dir := DIR
var _frame_us := 0  ## real time at the last frame
var _skip_frames := 0  ## frames the bot itself made slow (a screenshot reads the GPU back)
var _spikes: Array = []  ## {"day", "scene", "ms", "act", "kind"}: kind "fade" (behind a transition or the night), "cut", "play"
var _scene_key := ""  ## route + scene instance, to time spikes against the last scene change
var _scene_frames := 0
var _act_us := 0
var _root_base := {}  ## the root's children at start (autoloads), so a stall report lists only what came on top
var _batch_count := 0
var _mastered: Array[String] = []
var _bought_upgrades: Array[String] = []
var _biomes := {}
var _gifts_seen := {}  ## CUT-CLUTTER: neighbours whose heart gift was seen on their page
var _low_coins := -1  ## the smallest purse after shopping, and its day
var _low_day := 0


## Logger that queues engine and script errors (any thread); the bot drains it every frame.
class Capture extends Logger:
	var _m := Mutex.new()
	var _queue: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var where := "%s:%d" % [file, line]
		var fn := function
		for bt in script_backtraces:
			if bt != null and bt.get_frame_count() > 0:
				where = "%s:%d" % [bt.get_frame_file(0), bt.get_frame_line(0)]
				fn = bt.get_frame_function(0)
				for j in range(1, bt.get_frame_count()):  # the first caller outside that file (a shared helper says little)
					if bt.get_frame_file(j) != bt.get_frame_file(0):
						where += " via %s:%d" % [bt.get_frame_file(j), bt.get_frame_line(j)]
						break
				break
		var text := code if rationale == "" else "%s (%s)" % [rationale, code]
		_m.lock()
		_queue.append({"type": error_type, "where": where.replace("res://", "game/"), "fn": fn, "text": text})
		_m.unlock()

	func take() -> Array:
		_m.lock()
		var out := _queue
		_queue = []
		_m.unlock()
		return out


func _initialize() -> void:
	OS.add_logger(_log)
	_gs = root.get_node("GameState")
	_router = root.get_node("Router")
	_save = root.get_node("Save")
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--speed" and i + 1 < args.size():
			_speed = clampf(args[i + 1].to_float(), 1.0, 4.0)
		if args[i] == "--days" and i + 1 < args.size():
			_soak_days = clampi(args[i + 1].to_int(), 1, 60)
	if _soak_days > 0:
		_dir = SOAK_DIR
		_budget_ms = SOAK_MS_PER_DAY * _soak_days + 60000
	_run()


func _process(delta: float) -> bool:
	_dt = delta
	_drain_log()
	_watch()
	_frame_time()
	return false


## Real time between two frames (Engine.time_scale does not change it); a soak run records every spike.
func _frame_time() -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _frame_us) / 1000.0
	_frame_us = now
	# Router.goto sets the route before change_scene_to_file loads the scene, so the slow frame already sees the new route
	var key := "%s|%d" % [_router.current, current_scene.get_instance_id() if current_scene != null else 0]
	_scene_frames += 1
	if key != _scene_key:
		_scene_key = key
		_scene_frames = 0
	if _skip_frames > 0:
		_skip_frames -= 1
		return
	if _soak_days == 0 or _t0 == 0 or ms <= SPIKE_MS or _days.is_empty():
		return
	var row := _day_row()
	row.spikes = int(row.get("spikes", 0)) + 1
	row.max_ms = maxf(float(row.get("max_ms", 0.0)), ms)
	var kind := "play"
	if _busy() or bool(load(NIGHT_GD).is_running()):
		kind = "fade"
	elif _scene_frames <= SCENE_SPIKE_FRAMES:
		kind = "cut"
	var act := _trail[_trail.size() - 1] if not _trail.is_empty() else ""
	_spikes.append({"day": _day(), "scene": String(_router.current), "ms": ms, "act": act, "kind": kind})
	print("SPIKE d%d %s %d ms (%s) %d ms after '%s'" % [_day(), _router.current, roundi(ms), kind, (now - _act_us) / 1000, act])


# ================================================================ the week

func _run() -> void:
	await process_frame
	for c in root.get_children():
		_root_base[String(c.name)] = true
	_t0 = Time.get_ticks_msec()
	Engine.time_scale = _speed
	_prepare_dir()
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_backup = FileAccess.get_file_as_string(SAVE_PATH)
	_had_bak = FileAccess.file_exists(BAK_PATH)
	if _had_bak:
		_backup_bak = FileAccess.get_file_as_string(BAK_PATH)
	if await _new_game():
		for n in range(1, (_soak_days + 1 if _soak_days > 0 else LAST_DAY) + 1):
			if _aborted != "":
				break
			await _play_day(n)
	_finish()


func _play_day(n: int) -> void:
	_trail.clear()
	var d: Dictionary = _gs.data
	if _day() != n:
		_problem("high", "day", "expected day %d, the save is on day %d" % [n, _day()])
	_days.append({"day": n, "weather": String(d.get("weather", "")), "coins": int(d.coins), "energy": int(d.energy),
		"energy_max": int(d.get("energy_max", 0)), "cooked": [], "orders": 0, "sold": 0, "notes": []})
	_act("morning of day %d in the %s" % [n, _router.current])
	if _router.current == "parlor" and current_scene != null:  # waking up: the bed is in the parlor, the day starts in the kitchen
		_act("parlor: click the door to the kitchen")
		await _click_ctrl((current_scene.get("_spots") as Dictionary).door)
		if not await _arrive("kitchen"):
			return
	if _soak_days > 0:
		await _sample()
		if n > _soak_days:  # the morning after the last day: the overnight checks ran, the run ends here
			return
	var unlocks: Dictionary = d.get("unlocks", {})
	for id in unlocks:
		if bool(unlocks[id]) and not _seen_unlocks.has(id):
			_seen_unlocks[id] = n
			_notes.append("Day %d: '%s' is unlocked (%s)." % [n, id, "dev panel" if n == 3 and id in ["press", "knead"] else "in play"])
	if n == 1 and _open_biomes() >= 1:
		_problem("low", "spec", "the garden gate opens the forest on day 1; spec 8.4 opens it on day 2 (To-Do day 2, step 1)", "game/scenes/garden/garden.gd:282")
	if n == LAST_DAY and _soak_days == 0:
		await _day_eight()
		return
	if n == LAST_DAY:
		_day8_checks()
	var ok := true
	if n == 3 and _soak_days == 0:
		ok = await _dev_unlock()
	if ok and _router.current == "kitchen":
		ok = await _kitchen_door("garden")
	if ok:
		ok = await _garden_round(n)
	if ok and n == 1 and _pick_cook({}, _home_state()).is_empty():
		var got: Array[String] = []
		for it in _gs.data.bag:
			got.append(_item_label(it))
		_problem("medium", "tutorial", "To-Do day 1 'make jam' cannot be done from the garden: after shaking every tree the bag holds %s and jam needs 3 of one fruit (tree_yield 2-3); only the forest (step 1 of day 2) helps" % ", ".join(got),
			"game/data/rules.json:5 (forage.tree_yield) / game/sim/garden.gd:19")
	if ok and (n >= 2 or _pick_cook({}, _home_state()).is_empty()):
		ok = await _wild_trip(false)
	if ok:
		ok = await _garden_leave("door", "kitchen")
	if ok:
		ok = await _kitchen_round()
	if ok:
		ok = await _kitchen_door("pantry")
	if ok:
		ok = await _pantry_round()
	if ok:
		ok = await _kitchen_door("garden")
	if ok:
		ok = await _garden_leave("town_sign", "town")
	if ok:
		ok = await _town_round(n)
	if ok and Letters.unread_count(_gs.data) > 0:
		ok = await _mailbox()
	if ok:
		ok = await _garden_leave("door", "kitchen")
	_check_todo(n)
	if not ok:
		await _recover()
	if _aborted == "":
		await _sleep()


## New Game from the title: seed typed into the field, Enter, premise tapped through, the garden.
func _new_game() -> bool:
	change_scene_to_file(TITLE)
	if not await _arrive("title"):
		return false
	var title := current_scene
	# first launch / clean profile: the language card covers the menu; pick English (the title reloads)
	var layer: Variant = title.get("_lang_layer")
	if layer is Control and is_instance_valid(layer) and (layer as Control).is_visible_in_tree():
		_act("title: pick English on the language card")
		var en := (layer as Control).find_child("Lang_en", true, false) as Control
		await _click_ctrl(en)
		await _frames(10)
		if not await _arrive("title"):
			return false
		title = current_scene
	_act("title: click New Game (a save exists: %s)" % str(_had_save))
	await _click_ctrl(title.get_node("%NewGame") as Control)
	var edit: LineEdit = title.get("_seed_edit")
	# the seed field sits behind a small link on the New Game panel (with or without a save under it)
	var link: Variant = title.get("_seed_link")
	if link is Button and not await _wait(func() -> bool: return (link as Button).is_visible_in_tree(), "the New Game panel"):
		return false
	_act("title: open the seed field")
	await _click_ctrl(link as Control)
	if not await _wait(func() -> bool: return edit.is_visible_in_tree() and edit.has_focus(), "the New Game panel"):
		return false
	_act("title: type the seed %d and press Enter" % SEED)
	await _type(str(SEED))
	await _frames(4)
	_shot("title_new_game")
	_key(KEY_ENTER)
	if not await _wait(func() -> bool: return _premise(title) != null, "the premise after New Game"):
		return false
	await _frames(20)
	_shot("premise")
	_act("premise: tap twice")
	await _click(Vector2(240, 135))
	await _frames(4)
	await _click(Vector2(240, 135))
	if not await _arrive("garden"):
		return false
	var d: Dictionary = _gs.data
	_expect(int(d.get("save_seed", -1)) == SEED, "high", "new game", "the typed seed %d was not used (save_seed %s)" % [SEED, d.get("save_seed")])
	_expect(FileAccess.file_exists(SAVE_PATH), "high", "save", "New Game wrote no save file")
	_expect(get_first_node_in_group("granny_todo") != null, "medium", "tutorial", "Granny's To-Do note missing on day 1")
	return true


func _premise(title: Node) -> Node:
	for c in title.get_children():
		if c.has_method("_skip_or_leave"):
			return c
	return null


# ================================================================ garden

func _garden_round(n: int) -> bool:
	var d: Dictionary = _gs.data
	var trees: Array = d.garden.trees
	var order: Array = []
	for i in trees.size():
		if String(trees[i].type) == "apple":
			order.push_front(i)  # the first To-Do step
		else:
			order.append(i)
	for i in order:
		if not await _shake(int(i)):
			return false
	for i in d.garden.beds.size():
		var bed: Dictionary = d.garden.beds[i]
		if String(bed.crop) != "" and int(bed.days_left) <= 0 and not await _harvest(i):
			return false
	for i in d.garden.beds.size():
		if String(d.garden.beds[i].crop) == "" and int(d.cupboard.get("seed_cucumber", 0)) > 0 and int(d.energy) > KEEP_ENERGY:
			if not await _plant(i, "cucumber"):
				return false
	if n == 1:
		_expect(TodoRules.is_done(TodoRules.bits_of(d), "d1_shake"), "medium", "tutorial", "To-Do step 'shake the apple tree' did not tick after shaking it")
	if Letters.unread_count(d) > 0:
		return await _mailbox()
	return true


func _shake(i: int) -> bool:
	var d: Dictionary = _gs.data
	var t: Dictionary = d.garden.trees[i]
	if not bool(t.fruit) or int(d.energy) < KEEP_ENERGY or Garden.bag_free(d) < int(Data.rules().bag.shake_needs_free):
		return true
	var s: Node = current_scene.find_spot("tree", i)
	if s == null:
		_problem("medium", "garden", "no spot for garden tree %d (%s)" % [i, t.type])
		return true
	var e0 := int(d.energy)
	var b0 := Forage.bag_count(d)
	_act("garden: tap the %s tree" % t.type)
	_allow_energy = true
	_garden_tap(current_scene, s)
	var ok: bool = await _wait(func() -> bool: return not bool(t.fruit), "Granny to shake the %s tree" % t.type)
	await _frames(2)
	_allow_energy = false
	if not ok:
		return false
	var cost := e0 - int(d.energy)
	_expect(cost == Economy.energy_cost("shake_tree"), "medium", "energy anomaly",
		"shaking the %s tree cost %d energy (rule %d)" % [t.type, cost, Economy.energy_cost("shake_tree")])
	var got := Forage.bag_count(d) - b0
	var y: Array = Data.rules().forage.tree_yield
	_expect(got >= int(y[0]) and got <= int(y[1]), "medium", "garden", "the %s tree gave %d (rule %d-%d)" % [t.type, got, y[0], y[1]])
	return true


func _harvest(i: int) -> bool:
	var d: Dictionary = _gs.data
	var bed: Dictionary = d.garden.beds[i]
	var s: Node = current_scene.find_spot("bed", i)
	if s == null:
		return true
	var need := int(Data.shop().seeds.get(String(bed.crop), {}).get("yield", 1))
	if Garden.bag_free(d) < need or int(d.energy) < Economy.energy_cost("bed_harvest"):
		return true
	var e0 := int(d.energy)
	_act("garden: tap the ripe %s bed" % bed.crop)
	_allow_energy = true
	_garden_tap(current_scene, s)
	var ok: bool = await _wait(func() -> bool: return String(_gs.data.garden.beds[i].crop) == "", "Granny to harvest bed %d" % i)
	await _frames(2)
	_allow_energy = false
	if ok:
		_expect(e0 - int(d.energy) == Economy.energy_cost("bed_harvest"), "medium", "energy anomaly",
			"harvesting cost %d energy (rule %d)" % [e0 - int(d.energy), Economy.energy_cost("bed_harvest")])
	return ok


func _plant(i: int, crop: String) -> bool:
	var g := current_scene
	var s: Node = g.find_spot("bed", i)
	if s == null:
		return true
	var d: Dictionary = _gs.data
	var e0 := int(d.energy)
	_act("garden: tap the empty bed %d" % i)
	_garden_tap(g, s)
	if not await _wait(func() -> bool: return g.get("menu") != null, "the plant menu"):
		return false
	await _frames(6)
	_shot("garden_plant_menu")
	_act("garden: plant %s" % crop)
	_allow_energy = true
	g.get("menu").choose(crop)
	var ok: bool = await _wait(func() -> bool: return String(_gs.data.garden.beds[i].crop) == crop, "the %s to be planted" % crop)
	await _frames(2)
	_allow_energy = false
	if ok:
		_expect(e0 - int(d.energy) == Economy.energy_cost("bed_plant"), "medium", "energy anomaly",
			"planting cost %d energy (rule %d)" % [e0 - int(d.energy), Economy.energy_cost("bed_plant")])
	await _wait(func() -> bool: return g.get("menu") == null, "the plant menu to close")
	return ok


## Walks to a garden exit ("door", "gate", "town_sign") and arrives in `target`.
func _garden_leave(kind: String, target: String) -> bool:
	var g := current_scene
	var s: Node = g.find_spot(kind)
	if s == null:
		_problem("high", "garden", "the garden has no '%s'" % kind)
		return false
	_act("garden: tap the %s" % kind)
	_garden_tap(g, s)
	if target == "wild" and _open_biomes() > 1:
		if await _wait(func() -> bool: return g.get("menu") != null, "the biome picker"):
			await _frames(6)
			_shot("biome_picker")
			var biome := _pick_biome()
			_act("garden: pick the %s" % biome)
			g.get("menu").chosen.emit(biome)
			_biomes[biome] = int(_biomes.get(biome, 0)) + 1
	elif target == "wild":
		_biomes["forest"] = int(_biomes.get("forest", 0)) + 1
	return await _arrive(target)


## The forest in the week and on To-Do days; a soak run takes turns between the open biomes from day 3 on.
func _pick_biome() -> String:
	if _soak_days == 0 or _day() < 3:
		return "forest"
	var open: Array[String] = []
	for c in WildGen.biome_choices(_gs.data):
		if bool(c.open):
			open.append(String(c.id))
	return open[_day() % open.size()] if not open.is_empty() else "forest"


## Taps a garden spot where neither the cat nor another spot covers it (a tap on the cat pets it).
func _garden_tap(g: Node, s: Node) -> void:
	var r: Rect2 = s.hit_rect()
	var cat: Node = g.get("cat")
	for f: Vector2 in [Vector2(0.5, 0.5), Vector2(0.5, 0.8), Vector2(0.25, 0.5), Vector2(0.75, 0.5), Vector2(0.5, 0.25)]:
		var p := (r.position + r.size * f).floor()
		if (cat == null or not cat.hit_rect().has_point(p)) and (g.spot_at_point(p) == s or s.get("kind") in ["door", "gate"]):
			g.tap_world(p)
			return
	g.tap_world(r.get_center())


func _open_biomes() -> int:
	var n := 0
	for c in WildGen.biome_choices(_gs.data):
		if bool(c.open):
			n += 1
	return n


func _mailbox() -> bool:
	var g := current_scene
	var s: Node = g.find_spot("mailbox")
	if s == null:
		return true
	_act("garden: tap the mailbox (flag up)")
	_garden_tap(g, s)
	if not await _wait(func() -> bool: return get_first_node_in_group("letters_ui") != null, "the letters to open"):
		return false
	var ok: bool = await _letters()
	if ok:
		ok = await _wait(func() -> bool: return g.get("menu") == null, "the garden after the letters")
		_expect(Letters.unread_count(_gs.data) == 0, "low", "letters", "letters still unread after reading the newest")
	return ok


## The letters overlay: reads the newest letter; a request gets a parcel (jars dragged into the box, straw, Send).
func _letters() -> bool:
	var ui: Node = get_first_node_in_group("letters_ui")
	await _frames(10)
	_shot("letters")
	var d: Dictionary = _gs.data
	var letter: Dictionary = Letters.find_letter(d, int(ui.get("_letter_id")))
	if _first_letter == 0:
		_first_letter = _day()
		if _first_letter < 7:
			_problem("low", "spec", "the first grandchild letter comes on day %d; spec 8.4 brings it on day 7 (Letters.FIRST_DAY)" % _first_letter, "game/sim/letters.gd:46")
	_note_day("letter from %s (%s)" % [letter.get("from", "?"), letter.get("kind", "?")])
	_notes.append("Day %d: a %s letter from %s came; read in the mailbox." % [_day(), letter.get("kind", "?"), letter.get("from", "?")])
	_expect(not letter.is_empty() and bool(letter.get("read", false)), "medium", "letters", "the opened letter is not marked read")
	var pack_btn: Button = ui.get("_pack_btn")
	if String(letter.get("kind", "")) == "request" and pack_btn.visible:
		_act("letters: click Pack a parcel")
		await _click_ctrl(pack_btn)
		if not await _wait(func() -> bool: return (ui.get("_pack_page") as Control).visible, "the parcel page"):
			return false
		await _frames(4)
		var source: Array = ui.get("_source")
		var view: Control = ui.get("_source_view")
		var board: Control = ui.get("_board")
		var entries: Array = ui.get("_entries")
		var box: Dictionary = Letters.box_board()
		var cell := 0
		var tries := 0
		while not source.is_empty() and entries.size() < 3 and tries < 12 and cell < int(box.cols) * int(box.rows):
			var c := Vector2i(cell % int(box.cols), floori(cell / float(box.cols)))
			var pick := _parcel_pick(d, letter, source, entries)
			_act("letters: drag %s into the box" % _item_label(source[pick]))
			await _drag(_slot_pos(view, pick), board.get_global_rect().position + Vector2(board.cell_rect(c).position) + Vector2(12, 12))
			await _frames(3)
			cell += 1
			tries += 1
		_expect(not entries.is_empty() or source.is_empty(), "medium", "letters", "dragging jars into the parcel box placed none (%d jars offered)" % source.size())
		_act("letters: click Straw")
		await _click_ctrl(ui.get("_straw_btn"))
		await _frames(6)
		_shot("letters_parcel")
		var send: Button = ui.get("_send_btn")
		if send.disabled:
			_problem("low", "letters", "Send stays disabled with %d items in the box" % entries.size())
		else:
			_act("letters: click Send")
			await _click_ctrl(send)
			await _frames(6)
			var after: Dictionary = Letters.find_letter(_gs.data, int(letter.get("id", -1)))
			_expect(bool(after.get("done", false)), "medium", "letters", "the parcel was sent but the request is not done")
			_notes.append("Day %d: packed a parcel for %s (%s)." % [_day(), letter.get("from", "?"), "sent" if bool(after.get("done", false)) else "not sent"])
	_act("letters: click Close")
	var close: Button = ui.get("_close_btn")
	if close != null and close.is_visible_in_tree():
		await _click_ctrl(close)
	else:
		_key(KEY_ESCAPE)
	return await _wait(func() -> bool: return get_first_node_in_group("letters_ui") == null, "the letters to close")


## The jar in the column that ticks one more request line, else the first one.
func _parcel_pick(d: Dictionary, letter: Dictionary, source: Array, entries: Array) -> int:
	var base := _ticks(Letters.evaluate(d, letter, entries))
	for i in source.size():
		var trial := entries.duplicate()
		trial.append({"item": source[i], "x": 0, "y": 0, "rot": 0})
		if _ticks(Letters.evaluate(d, letter, trial)) > base:
			return i
	return 0


func _ticks(ev: Dictionary) -> int:
	var n := 0
	for t in ev.get("ticks", []):
		n += 1 if bool(t) else 0
	return n


# ================================================================ wild

func _wild_trip(day8: bool) -> bool:
	if not await _garden_leave("gate", "wild"):
		return false
	var w := current_scene
	var view: Node = w.get("view")
	var granny: Node = w.get("granny")
	if view == null or granny == null:
		_problem("high", "wild", "the wild scene has no map or no Granny")
		return false
	if day8 or (_soak_days > 0 and _day() == LAST_DAY):
		_check_wild_weather(w)
	var tried := {}
	var uses := 0
	while uses < (4 if day8 else 9) and _aborted == "":
		var d: Dictionary = _gs.data
		if int(d.energy) <= KEEP_ENERGY or Garden.bag_free(d) < int(Data.rules().bag.shake_needs_free):
			break
		var o: Node2D = _next_object(view, granny, tried)
		if o == null:
			break
		tried[o.get_instance_id()] = true
		var kind := String(o.get("kind"))
		var info: Dictionary = o.get("info")
		var e0 := int(d.energy)
		_act("wild: tap a %s (%s) at %s" % [kind, info.get("type", ""), o.get("cell")])
		_allow_energy = true
		var p: Vector2 = o.hit_rect().get_center()
		if view.object_at_point(p) == o:
			w._tap(p)
		else:  # another object is drawn over it: walk up to it the way a tap on its free part would
			granny.approach(o.get("cell"), Callable(w, "_use").bind(o))
		var t_tap := Time.get_ticks_msec()
		var cell: Vector2i = o.get("cell")
		var oid := o.get_instance_id()  # a picked ground thing vanishes (FEEL): never hold the freed node in the lambda
		var used := func() -> bool:
			var obj := instance_from_id(oid)
			return obj == null or bool(obj.get("done"))
		var cond := func() -> bool:
			return bool(used.call()) or (Time.get_ticks_msec() - t_tap > 700 and not granny.is_moving())
		var ok: bool = await _wait(cond, "Granny to reach a %s" % kind)
		await _frames(2)
		_allow_energy = false
		if not ok:
			return false
		if not bool(used.call()):
			_problem("low", "wild", "Granny could not use a %s at %s (map seed %d)" % [kind, cell, int(w.get("map").get("seed", 0))])
			continue
		uses += 1
		var rule := String(USE_COST.get(kind, ""))
		if rule != "":
			var cost := e0 - int(d.energy)
			_expect(cost == Economy.energy_cost(rule), "medium", "energy anomaly", "using a %s cost %d energy (rule %d)" % [kind, cost, Economy.energy_cost(rule)])
	await _frames(4)
	_shot("wild_foraged")
	var exit: Node2D = null
	for o in view.get("objects").get_children():
		if is_instance_valid(o) and o.get("kind") == "exit":
			exit = o
	_act("wild: tap the way home")
	if exit != null and view.object_at_point(exit.hit_rect().get_center()) == exit:
		w._tap(exit.hit_rect().get_center())
	else:
		granny.walk_to(w.get("map").entrance)
	return await _arrive("garden")


## Nearest usable thing (mushrooms first: To-Do day 2 and the brine jar), not tried yet.
func _next_object(view: Node, granny: Node, tried: Dictionary) -> Node2D:
	var from: Vector2i = granny.current_cell()
	var best: Node2D = null
	var best_score := INF
	var ingredients := Data.ingredients()
	var fruit_first := Economy.unlocked(_gs.data, "press") and _station_uses("press") == 0
	for o in view.get("objects").get_children():
		if not is_instance_valid(o) or not o.has_method("usable") or tried.has(o.get_instance_id()):
			continue
		var kind := String(o.get("kind"))
		if not USE_COST.has(kind) or o.get("done") == true or o.usable() != true:
			continue
		var c: Vector2i = o.get("cell")
		var score := float(absi(c.x - from.x) + absi(c.y - from.y))
		var info: Variant = o.get("info")
		var type := String((info as Dictionary).get("type", "")) if info is Dictionary else ""
		if String(ingredients.get(type, {}).get("group", "")) == "mushroom":
			score -= 25.0
		if kind == "fruit_tree":
			score -= 30.0 if fruit_first else 8.0
		if score < best_score:
			best_score = score
			best = o
	return best


# ================================================================ kitchen

func _kitchen_door(target: String) -> bool:
	var k := current_scene
	var spots: Dictionary = k.get("_spots")
	_act("kitchen: click the door to the %s" % target)
	await _click_ctrl(spots[target])
	return await _arrive(target)


## Cooks once at each station that has a recipe it can make (stove, counter, then press and board once unlocked).
func _kitchen_round() -> bool:
	var used := {}
	for i in STATIONS.size():
		var plan := _pick_cook(used)
		if plan.is_empty():
			break
		used[plan.station] = true
		if not await _cook(plan):
			return false
	return true


func _pick_cook(used: Dictionary, state: Dictionary = {}) -> Dictionary:
	var d: Dictionary = state if not state.is_empty() else _gs.data
	var order: Array = STATIONS.keys()
	order.sort_custom(func(a: String, b: String) -> bool: return _station_uses(a) < _station_uses(b))  # every mini-game gets played
	for station: String in order:
		if used.has(station):
			continue
		if STATION_UNLOCK.has(station) and not Economy.unlocked(d, String(STATION_UNLOCK[station])):
			continue
		for recipe: String in STATIONS[station]:
			if not Kitchen.available(d, recipe):
				continue
			var c := _candidate(d, recipe)
			if not c.is_empty():
				c["station"] = station
				c["recipe"] = recipe
				return c
	return {}


## The save as it will be indoors: the bag empties into the inbox at the house door.
func _home_state() -> Dictionary:
	var sim: Dictionary = _gs.data.duplicate(true)
	Forage.empty_bag_to_inbox(sim)
	return sim


func _station_uses(station: String) -> int:
	var n := 0
	for recipe: String in STATIONS[station]:
		n += int(_recipe_count.get(recipe, 0))
	return n


func _candidate(d: Dictionary, recipe: String) -> Dictionary:
	var r: Dictionary = Data.recipes()[recipe]
	var mains: Array = [""]
	var seconds: Array = [""]
	if typeof(r.get("main")) == TYPE_DICTIONARY:
		mains = _stock_ids(d, r.main)
	if typeof(r.get("second")) == TYPE_DICTIONARY:
		seconds = _stock_ids(d, r.second)
	for m in mains:
		for s2 in seconds:
			if m != "" and m == s2:
				continue
			if bool(Kitchen.check_n(d, recipe, m, s2, "", 1).ok):
				return {"main": m, "second": s2}
	return {}


## Variety ids a slot could draw from, biggest stack first.
func _stock_ids(d: Dictionary, slot: Dictionary) -> Array:
	var counts := {}
	if slot.has("recipe"):
		counts = Kitchen.product_stock(d, String(slot.recipe))
	else:
		var items: Array = d.inbox.duplicate()
		for e in d.pantry.items:
			items.append(e.item)
		for it in items:
			if String(it.kind) == "fresh":
				counts[String(it.variety)] = int(counts.get(String(it.variety), 0)) + int(it.count)
	var ids: Array = counts.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]) or (int(counts[a]) == int(counts[b]) and a < b))
	return ids


func _cook(plan: Dictionary) -> bool:
	var k := current_scene
	var panel: Control = k.get("_panel")
	var station := String(plan.station)
	var recipe := String(plan.recipe)
	var spots: Dictionary = k.get("_spots")
	_act("kitchen: click the %s" % station)
	await _click_ctrl(spots[station])
	if not await _wait(func() -> bool: return panel.visible, "the cook panel at the %s" % station):
		return false
	await _frames(4)
	if String(panel.get("recipe")) != recipe:
		var tabs: Dictionary = panel.get("_tabs")
		if not tabs.has(recipe):
			_problem("medium", "kitchen", "no %s tab at the %s (tabs %s)" % [recipe, station, tabs.keys()])
			await _close_panel(k)
			return true
		_act("kitchen: click the %s tab" % recipe)
		await _click_ctrl(tabs[recipe])
		if not await _wait(func() -> bool: return String(panel.get("recipe")) == recipe, "the %s tab" % recipe):
			return false
	for which: String in ["main", "second"]:
		var vid := String(plan[which])
		if vid == "":
			continue
		if panel.has_method("open_picker"):  # JURY-STOVE: the rows live in the slot's Change picker
			panel.call("open_picker", which)
			await _frames(2)
		var rows: Dictionary = panel.get("_rows")
		if not rows.has(vid):
			_problem("medium", "kitchen", "%s: no row for %s in the %s list" % [recipe, vid, station])
			await _close_panel(k)
			return true
		(panel.get("_scroll") as ScrollContainer).ensure_control_visible(rows[vid])
		await _frames(2)
		_act("kitchen: click the %s row" % vid)
		await _click_ctrl(rows[vid])
		await _frames(2)
	var picks: Dictionary = panel.get("picks")
	if String(picks.main) != String(plan.main) or String(picks.second) != String(plan.second):
		_problem("medium", "kitchen", "%s: clicking the rows filled main '%s' second '%s' (wanted '%s' / '%s')" % [recipe, picks.main, picks.second, plan.main, plan.second])
	if _soak_days > 0:
		await _pick_pot(panel, plan)
	if not bool(panel.get("_ok")):
		var fb: Label = panel.get("_feedback")
		_problem("medium", "kitchen", "Cook stays locked for %s (%s) although Kitchen.check_n allows it: '%s'" % [recipe, plan.main, fb.text if fb != null else ""])
		await _close_panel(k)
		return true
	await _frames(6)
	_shot("cook_" + recipe)
	var d: Dictionary = _gs.data
	var method := String(Data.recipes()[recipe].method)
	var e0 := int(d.energy)
	var made0 := int(d.stats.jars_made)
	var mult := int(panel.get("mult"))
	var key := Kitchen.product_key(recipe, String(plan.main), String(plan.second), "")
	var was_mastered := Kitchen.is_mastered(d, key)
	var batch := _soak_days > 0 and bool(panel.get("_batch_ok"))
	k.set("debug_ctx", AUTOPLAY.duplicate())
	_allow_energy = true
	if batch:
		_act("kitchen: click Batch cook (%s, %s%s)" % [recipe, plan.main, " x2" if mult > 1 else ""])
		await _click_ctrl(panel.get("_batch"))
		if not await _wait(func() -> bool: return k.get("_card") != null or k.get("_mg") != null, "the batch cook card for %s" % recipe):
			_allow_energy = false
			return false
		_expect(k.get("_mg") == null, "medium", "mastery", "Batch cook of a Mastered %s opened the mini-game" % key)
	else:
		_act("kitchen: click Cook (%s, %s%s)" % [recipe, plan.main, " x2" if mult > 1 else ""])
		await _click_ctrl(panel.get("_cook"))
		if not await _wait(func() -> bool: return k.get("_mg") != null, "the %s mini-game" % method):
			_allow_energy = false
			return false
		var mg: Node = k.get("_mg")
		await _frames(24)
		_shot("mg_" + method)
		if method == "pack_jar":
			await _play_pack(mg)
	var ok: bool = await _wait(func() -> bool: return k.get("_card") != null, "the result card after %s" % recipe, MG_STALL_MS)
	await _frames(2)
	_allow_energy = false
	if not ok:
		return false
	if batch:
		_batch_count += 1
		_note_day("batch %s" % key)
	else:
		_mg_count[method] = int(_mg_count.get(method, 0)) + 1
	_recipe_count[recipe] = int(_recipe_count.get(recipe, 0)) + 1
	var cost := e0 - int(d.energy)
	_expect(cost == Economy.energy_cost(method), "medium", "energy anomaly", "cooking %s%s cost %d energy (rule %d)" % [recipe, " (batch)" if batch else "", cost, Economy.energy_cost(method)])
	_expect(int(d.stats.jars_made) == made0 + mult, "medium", "kitchen", "jars_made went %d -> %d after one %s x%d" % [made0, int(d.stats.jars_made), recipe, mult])
	_day_row().cooked.append(recipe + (" x%d" % mult if mult > 1 else "") + (" (batch)" if batch else ""))
	await _frames(20)
	_shot("card_" + recipe)
	var card: Node = k.get("_card")
	if not was_mastered and Kitchen.is_mastered(_gs.data, key):
		_mastered.append("%s (day %d)" % [key, _day()])
		_note_day("mastered %s" % key)
		var banner: Variant = card.get("_banner")
		_expect(banner is Label and (banner as Label).visible and (banner as Label).text == tr("UI_MASTERY_BANNER"), "low", "mastery",
			"the result card that made %s Mastered shows no Mastered banner" % key)
	_act("kitchen: close the result card")
	await _click_ctrl(card.get("_button"))
	return await _wait(func() -> bool: return k.get("_card") == null, "the result card to close")


func _close_panel(k: Node) -> void:
	_act("kitchen: Esc closes the panel")
	var panel: Node = k.get("_panel")
	if panel.has_method("_close_picker"):  # an open Change picker would take this Esc
		panel.call("_close_picker", false)
	_key(KEY_ESCAPE)
	await _wait(func() -> bool: return not (k.get("_panel") as Control).visible, "the cook panel to close")


## Soak: x2 on the big pot's toggle when the stock covers two pots, x1 when it does not (the toggle keeps its state).
func _pick_pot(panel: Control, plan: Dictionary) -> void:
	var buttons: Dictionary = panel.get("_mult_buttons")
	if not buttons.has(2) or not (buttons[2] as Control).is_visible_in_tree():
		return
	var two := bool(Kitchen.check_n(_gs.data, String(plan.recipe), String(plan.main), String(plan.second), "", 2).ok)
	var want := 2 if two else 1
	if int(panel.get("mult")) == want:
		return
	_act("kitchen: click x%d (big pot)" % want)
	await _click_ctrl(buttons[want])
	await _frames(3)
	_expect(int(panel.get("mult")) == want, "medium", "kitchen", "the big pot's x%d toggle did not take (mult %d)" % [want, int(panel.get("mult"))])


## Jar packing: the game's own demo packer stacks the pieces; the brine is poured by holding the mouse button down to
## the fill line; three clicks twist the lid.
func _play_pack(mg: Node) -> void:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(mg) and int(mg.get("phase")) <= PACK and Time.get_ticks_msec() - t0 < 30000:
		if int(mg.get("phase")) == PACK:
			mg.call("_bot", _dt)
		await process_frame
	if not is_instance_valid(mg) or int(mg.get("phase")) != BRINE:
		return
	await _frames(4)
	_shot("mg_pack_jar_brine")
	var line := float(mg.get_script().get_script_constant_map().get("LINE_ROWS", 7))
	var jar := Vector2(240, 160)
	_act("pack jar: hold the mouse to pour the brine")
	_move(jar)
	_button(jar, MOUSE_BUTTON_LEFT, true)
	t0 = Time.get_ticks_msec()
	while is_instance_valid(mg) and float(mg.get("_brine")) < line - 0.15 and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	var poured := float(mg.get("_brine")) if is_instance_valid(mg) else 0.0
	_button(jar, MOUSE_BUTTON_LEFT, false)
	await _frames(3)
	if not is_instance_valid(mg):
		return
	if poured <= 0.0:
		_problem("medium", "mini-game", "pack jar: holding the mouse button poured no brine")
		while is_instance_valid(mg) and int(mg.get("phase")) == BRINE:
			mg.call("_bot", _dt)
			await process_frame
	await _wait(func() -> bool: return not is_instance_valid(mg) or int(mg.get("phase")) >= LID, "the lid after the brine")
	_act("pack jar: click the lid three times")
	for i in 3:
		if not is_instance_valid(mg) or int(mg.get("phase")) != LID:
			break
		await _click(Vector2(240, 98))
		await _frames(2)


func _pantry_round() -> bool:
	var p := current_scene
	var d: Dictionary = _gs.data
	var board: Control = p.get_node("%Board")
	var inbox: Control = p.get_node("%Inbox")
	var idx := -1
	for i in d.inbox.size():
		if String(d.inbox[i].kind) == "product":
			idx = i
			break
	if idx >= 0:
		var item: Dictionary = d.inbox[idx]
		var b := PantryRules.board_of(d.pantry)
		var spot := PantryRules.first_free(b, d.pantry.items, item, PantryRules.zone_for(item))
		var n0: int = d.pantry.items.size()
		if spot.is_empty():
			_note_day("no free %s shelf" % PantryRules.zone_for(item))
		else:
			var c: Vector2i = spot.cell
			var turn := int(spot.get("rot", 0)) == 1  # first_free may only fit a loaf or a pie turned: R while holding it
			_act("pantry: drag %s onto the %s shelf%s" % [item.key, PantryRules.zone_for(item), " (R turns it)" if turn else ""])
			await _drag(_slot_pos(inbox, idx), board.get_global_rect().position + Vector2(board.cell_rect(c).position) + Vector2(12, 12), turn)
			await _frames(4)
			_expect(d.pantry.items.size() > n0, "medium", "pantry", "dragging %s from the inbox onto free cell %s (rot %d) placed nothing" % [item.key, c, int(spot.get("rot", 0))])
	if not d.inbox.is_empty():
		var before: int = d.inbox.size()
		_act("pantry: click Auto-arrange")
		await _click_ctrl(p.get_node("%AutoArrange") as Control)
		await _frames(6)
		_expect(d.inbox.size() < before, "low", "pantry", "Auto-arrange placed none of %d waiting items" % before)
	await _frames(10)
	_shot("pantry_arranged")
	if _day() == 1:
		_expect(TodoRules.is_done(TodoRules.bits_of(d), "d1_pantry"), "medium", "tutorial", "To-Do step 'put the jar in the pantry' did not tick")
	_act("pantry: click Back")
	await _click_ctrl(p.get_node("%Back") as Control)
	return await _arrive("kitchen")


func _dev_unlock() -> bool:
	var dev: Node = get_first_node_in_group("dev_panel")
	if dev == null:
		_problem("medium", "dev panel", "no dev panel in the tree (F1); P1 stations stay locked")
		return true
	_act("F1: open the dev panel")
	_action("dev_panel")
	if not await _wait(func() -> bool: return (dev.get("_panel") as Control).visible, "the dev panel"):
		return false
	await _frames(6)  # the panel's grid lays its buttons out after it shows
	var btn: Button = null
	for b in _buttons(dev):
		if b.text == "UI_DEV_UNLOCK_P1":
			btn = b
	if btn == null:
		_problem("medium", "dev panel", "no Unlock P1 button")
		return true
	var d: Dictionary = _gs.data
	for attempt in 2:
		_act("dev panel: click Unlock P1")
		await _click_ctrl(btn)
		await _frames(4)
		if Economy.unlocked(d, "press") and Economy.unlocked(d, "knead"):
			break
	await _frames(4)
	_shot("dev_panel")
	_act("F1: close the dev panel")
	_action("dev_panel")
	await _frames(6)
	_expect(Economy.unlocked(d, "press") and Economy.unlocked(d, "knead"), "medium", "dev panel", "Unlock P1 did not unlock the press and the dough board")
	var spots: Dictionary = current_scene.get("_spots")
	_expect((spots.press as Control).visible and (spots.board as Control).visible, "medium", "kitchen", "press and dough board not shown after Unlock P1")
	for id in ["press", "knead"]:
		if not _seen_unlocks.has(id):
			_seen_unlocks[id] = _day()
	_notes.append("Day %d: dev panel (F1) > Unlock P1 > the press and the dough board appear in the kitchen." % _day())
	return true


# ================================================================ town

func _town_round(n: int) -> bool:
	if Market.can_open(_gs.data):
		if not await _market():
			return false
	elif Market.is_market_day(n):
		_problem("medium", "market", "day %d is a market day but the market cannot open" % n)
	var t := current_scene
	if not await _deliver(t):
		return false
	if not await _buy(t):
		return false
	_check_jam_money(n)
	if _soak_days > 0 and not await _upgrades(t):
		return false
	_act("town: click Back to the garden")
	await _click_ctrl(_text_button(t, tr("TOWN_BACK_GARDEN")))
	return await _arrive("garden")


func _deliver(t: Node) -> bool:
	await _tab_to(t, "orders")
	await _frames(1)
	_shot("town_orders")
	var delivered := 0
	for attempt in 8:
		var d: Dictionary = _gs.data
		if String(t.get("_tab")) != "orders":  # CUT-CLUTTER: a neighbour's gift opens their page; back to the board
			_gift_seen(t)
			await _tab_to(t, "orders")
		var btn: Button = null
		for b in _buttons(t):
			var args := _bound(b)
			if b.text == tr("TOWN_DELIVER") and not args.is_empty() and _matchable(int(args[0])):
				btn = b
				break
		if btn == null:
			var nxt := _text_button(t, ">")
			if nxt != null and not nxt.disabled and _any_matchable():
				_act("town: next order page")
				await _click_ctrl(nxt)
				await _frames(3)
				continue
			break
		var order := _order(int(_bound(btn)[0]))
		_act("town: Deliver the %s order" % order.npc)
		await _click_ctrl(btn)
		await _frames(3)
		var give: Button = null
		for b in _buttons(t):
			if b.text == tr("TOWN_GIVE") and not _bound(b).is_empty():
				give = b
				break
		if give == null:
			_problem("medium", "town", "Deliver opened no jar list although a jar matches the %s order" % order.npc)
			break
		var item := _item_at(d, _bound(give)[0])
		var expect := floori(ProductGen.value(String(item.key), d.varieties, int(item.q)) * float(Data.rules().orders.reward_mult))
		var c0 := int(d.coins)
		var done0 := int(d.stats.orders_done)
		_allow_coins = true
		_act("town: Give %s" % item.key)
		await _click_ctrl(give)
		await _frames(4)
		_allow_coins = false
		_expect(int(d.coins) - c0 == expect, "high", "coin anomaly", "an order paid %d coins (rule: value x reward_mult = %d)" % [int(d.coins) - c0, expect])
		_expect(int(d.stats.orders_done) == done0 + 1, "medium", "town", "orders_done did not count the delivery")
		_day_row().orders += 1
		delivered += 1
	if delivered > 0:  # a heart gift comes 1.6 s after the delivery (town._show_rewards): let it play, then look
		await _secs(2.0)
		_gift_seen(t)
	if _day() == 1:
		_expect(TodoRules.is_done(TodoRules.bits_of(_gs.data), "d1_order"), "medium", "tutorial", "To-Do step 'take the baker's order to town' did not tick (orders_done %d)" % int(_gs.data.stats.orders_done))
	if _day() == 2 and delivered > 0:
		_expect(TodoRules.is_done(TodoRules.bits_of(_gs.data), "d2_sell"), "medium", "tutorial", "To-Do step 'deliver an order' did not tick after %d deliveries" % delivered)
	return true


## Clicks a town tab until it is open (3 tries). A click that did not switch the tab is logged (low): it was lost
## while nothing covered the button (seen now and then on day 2, not reproduced by hand).
func _tab_to(t: Node, id: String) -> void:
	for i in 3:
		if String(t.get("_tab")) == id and t.get("_picker").is_empty():
			return
		if i > 0:
			_problem("low", "town", "a click on the %s tab did not open it; clicked again" % id)
		_act("town: click the %s tab" % id)
		await _click_ctrl((t.get("_tab_buttons") as Dictionary)[id])
		await _frames(3)


## CUT-CLUTTER: a neighbour's heart gift on show (their page, the Teo line, "+3 [jar]"): one screenshot and a note.
func _gift_seen(t: Node) -> void:
	var g: Dictionary = t.get("_gift")
	if g.is_empty() or _gifts_seen.has(String(g.get("npc", ""))):
		return
	_gifts_seen[String(g.npc)] = true
	_shot("town_gift")
	_notes.append("Day %d: %s's heart gift on their page: +%d %s and the Teo line." % [_day(), String(g.npc),
		int(g.get("count", 0)), String(g.get("value", ""))])


## CUT-CLUTTER: the grocer buys nothing, so coins come from orders and the market only. After shopping, a jam must
## still be possible: a jar and sugar in the cupboard, or the coins for them.
func _check_jam_money(n: int) -> void:
	var d: Dictionary = _gs.data
	if _low_coins < 0 or int(d.coins) < _low_coins:
		_low_coins = int(d.coins)
		_low_day = n
	for id in ["jar", "sugar"]:
		if int(d.cupboard.get(id, 0)) < 1 and int(d.coins) < Economy.price(d, id):
			_problem("high", "economy", "coins block jam-making on day %d: no %s in the cupboard and %d coins (price %d)" % [
				n, id, int(d.coins), Economy.price(d, id)])


func _buy(t: Node) -> bool:
	var d: Dictionary = _gs.data
	_act("town: Grocer tab, Supplies")
	await _tab_to(t, "grocer")
	await _click_ctrl(_bound_button(t, "supplies"))
	await _frames(3)
	var needs := SUPPLIES.duplicate()
	if Economy.unlocked(d, "press") or Economy.unlocked(d, "knead"):
		needs.merge(P1_SUPPLIES)
	var bought := 0
	for id: String in needs:
		var guard := 0
		while int(d.cupboard.get(id, 0)) < int(needs[id]) and guard < 6:
			guard += 1
			var price := Economy.price(d, id)
			if price < 0:
				_problem("medium", "town", "%s is needed for a P1 recipe but not on sale" % id)
				break
			if int(d.coins) < price + 15:
				break
			var b: Button = await _page_to(t, id)
			if b == null:
				_problem("low", "town", "no Buy row for %s in Supplies" % id)
				break
			var c0 := int(d.coins)
			var have := int(d.cupboard.get(id, 0))
			_allow_coins = true
			_act("town: Buy %s" % id)
			await _click_ctrl(b)
			await _frames(3)
			_allow_coins = false
			_expect(c0 - int(d.coins) == price and int(d.cupboard.get(id, 0)) == have + 1, "high", "coin anomaly",
				"buying %s cost %d (price %d), cupboard %d -> %d" % [id, c0 - int(d.coins), price, have, int(d.cupboard.get(id, 0))])
			bought += 1
	var empty_beds := 0
	for bed in d.garden.beds:
		if String(bed.crop) == "":
			empty_beds += 1
	if empty_beds > 0 and int(d.cupboard.get("seed_cucumber", 0)) == 0 and int(d.coins) >= 60:
		await _click_ctrl(_bound_button(t, "seeds"))
		await _frames(3)
		var sb: Button = await _page_to(t, "seed_cucumber")
		if sb != null:
			var c1 := int(d.coins)
			_allow_coins = true
			_act("town: Buy a cucumber seed")
			await _click_ctrl(sb)
			await _frames(3)
			_allow_coins = false
			_expect(c1 - int(d.coins) == Economy.price(d, "seed_cucumber"), "high", "coin anomaly", "a cucumber seed cost %d" % (c1 - int(d.coins)))
			bought += 1
	if bought > 0:
		_shot("town_bought")
	return true


## The Buy button of shop id `id`, paging through the list from its first page.
func _page_to(t: Node, id: String) -> Button:
	for i in 6:
		var prev := _text_button(t, "<")
		if prev == null or prev.disabled:
			break
		await _click_ctrl(prev)
		await _frames(2)
	for i in 8:
		for b in _buttons(t):
			var args := _bound(b)
			if b.text == tr("TOWN_BUY") and not args.is_empty() and String(args[0]) == id:
				return b
		var nxt := _text_button(t, ">")
		if nxt == null or nxt.disabled:
			return null
		await _click_ctrl(nxt)
		await _frames(2)
	return null


func _market() -> bool:
	var t := current_scene
	var banner := t.find_child("MarketToday", true, false) as Control
	if banner == null or not banner.visible:
		_problem("medium", "market", "no 'Market today!' banner in town on day %d" % _day())
		return true
	_act("town: click Market today!")
	await _click_ctrl(banner)
	if not await _arrive("market"):
		return false
	var m := current_scene
	var fill: Button = m.get("_fill_btn")
	if fill.disabled:
		_notes.append("Day %d market: no ready jars to put on the stall." % _day())
		_act("market: click Back")
		await _click_ctrl(m.get("_back_btn"))
		return await _arrive("town")
	_act("market: click Fill stall")
	await _click_ctrl(fill)
	await _frames(4)
	var entries: Array = m.get("_entries")
	_expect(not entries.is_empty(), "medium", "market", "Fill stall put nothing on the stall")
	await _frames(8)
	_shot("market_stall")
	var d: Dictionary = _gs.data
	var c0 := int(d.coins)
	var stall := entries.size()
	_allow_coins = true
	_act("market: click Open stall")
	await _click_ctrl(m.get("_open_btn"))
	if not await _wait(func() -> bool: return int(m.get("_phase")) >= 1, "the parade"):
		_allow_coins = false
		return false
	await _frames(3)
	_allow_coins = false
	var plan: Dictionary = m.get("_plan")
	var earned := 0
	for v in plan.get("sales", []):
		earned += int(v.price)
	_expect(int(d.coins) == c0 + earned, "high", "coin anomaly", "the market paid %d coins, its sales add up to %d" % [int(d.coins) - c0, earned])
	_day_row().sold += plan.get("sales", []).size()  # CUT-CLUTTER: the market is the only place jars are sold
	await _secs(3.0)
	_shot("market_parade")
	_act("market: Esc skips the parade")
	_key(KEY_ESCAPE)
	if not await _wait(func() -> bool: return int(m.get("_phase")) == 2, "the market end card"):
		return false
	await _frames(12)
	_shot("market_end")
	_notes.append("Day %d market: %d jars on the stall, %d sold, +%d coins, reputation %d." % [_day(), stall, plan.get("sales", []).size(), earned, int(Market.info(d).reputation)])
	_act("market: Enter, back to town")
	_key(KEY_ENTER)
	if not await _arrive("town"):
		return false
	_expect(current_scene.find_child("MarketToday", true, false) == null, "medium", "market", "the 'Market today!' banner is still up after the market")
	return true


# ================================================================ night and day 8

func _sleep() -> bool:
	var k := current_scene
	if _router.current == "kitchen" and k != null:
		# the bed lives in the parlor (PARLOR): walk through the door next to the stove
		if not await _kitchen_door("parlor"):
			return await _force_night()
		k = current_scene
	if _router.current != "parlor" or k == null or not k.has_method("_on_sleep"):
		_problem("high", "night", "not in the parlor at bedtime (%s)" % _router.current)
		return await _force_night()
	var d: Dictionary = _gs.data
	var day0 := int(d.day)
	var c0 := int(d.coins)
	var spots: Dictionary = k.get("_spots")
	_act("parlor: click the bed")
	await _click_ctrl(spots.bed)
	if not await _wait(func() -> bool: return (k.get("_dialog") as Control).visible, "the bed dialog"):
		return await _force_night()
	await _frames(6)
	_shot("bed")
	_act("kitchen: click Sleep")
	_allow_energy = true
	await _click_ctrl(k.get("_sleep_btn"))
	if not await _wait(func() -> bool: return _night() != null, "the night to start"):
		_allow_energy = false
		return await _force_night()
	var night := _night()
	var card_up := func() -> bool: return is_instance_valid(night) and (night.get("_card") as Control).visible and bool(night.get("_accepting"))
	var ok: bool = await _wait(card_up, "the morning card")
	_allow_energy = false
	if not ok:
		return false
	await _secs(0.3)  # the card pops in with a short scale tween
	# 480 x 270, taller when the window is not 16:9 (stretch aspect "expand"); the card must fit 270 px either way
	var screen := root.get_visible_rect()
	var card_rect := (night.get("_card") as Control).get_global_rect()
	var cont_rect := (night.get("_button") as Control).get_global_rect()
	_expect(card_rect.size.y <= 270.0 and screen.encloses(card_rect) and screen.encloses(cont_rect), "medium", "morning card",
		"the day-%d morning card (%d lines) is %d px tall and does not fit the 270 px screen (viewport %s, card %s, Continue %s): the line cap counts lines, not wrapped height" % [
			int(_gs.data.day), (night.get("_lines") as Node).get_child_count(), int(card_rect.size.y), screen.size, card_rect, cont_rect],
		"game/ui/transition/morning_text.gd:30 / game/ui/transition/night.gd:122")
	d = _gs.data
	var stars := int(PantryRules.state_stars(d).get("stars", 0))
	var e: Dictionary = Data.rules().energy
	var want_max := int(e.base) + int(e.pantry_bonus_per_star) * stars
	_expect(int(d.day) == day0 + 1, "high", "night", "the night went from day %d to day %d" % [day0, int(d.day)])
	_expect(int(d.coins) == c0, "high", "coin anomaly", "coins changed overnight (%d -> %d)" % [c0, int(d.coins)])
	_expect(int(d.energy_max) == want_max and int(d.energy) == want_max, "medium", "energy anomaly",
		"morning energy %d / %d, rule base + %d x %d pantry stars = %d" % [int(d.energy), int(d.energy_max), int(e.pantry_bonus_per_star), stars, want_max])
	_expect(int(_save.load_game().get("day", 0)) == int(d.day), "high", "save", "the night did not autosave day %d" % int(d.day))
	_morning.clear()
	for l in (night.get("_lines") as Node).get_children():
		if l is Label and not l.is_queued_for_deletion():
			_morning.append((l as Label).text)
	for l in MorningText.calendar_lines(d):
		var text := tr(String(l.key))
		if not (l.args as Array).is_empty():
			text = text % l.args
		_expect(_morning.has(text), "medium", "morning card", "day %d card lacks the calendar line '%s' (card: %s)" % [int(d.day), text, _morning])
	if Market.is_market_day(int(d.day)):
		_expect(_morning.has(tr("UI_MARKET_TODAY")), "medium", "morning card", "no 'Market today!' line on the day-%d card" % int(d.day))
	await _frames(6)
	_shot("morning")
	if int(d.day) == 2:
		_expect(TodoRules.is_done(TodoRules.bits_of(d), "d1_bed"), "low", "tutorial",
			"To-Do step 'go to bed' never ticks (and day 1's list never shows 'all done'): TodoRules.evaluate only checks today's list, and the day is 2 by the time it is true",
			"game/ui/tutorial/todo_rules.gd:48")
	_act("night: click Continue")
	await _click_ctrl(night.get("_button"))
	ok = await _wait(func() -> bool: return not bool(load(NIGHT_GD).is_running()), "the morning card to close")
	await _frames(8)
	_shot("kitchen_morning")
	return ok


func _night() -> Node:
	var script: Script = load(NIGHT_GD)
	for c in root.get_children():
		if c.get_script() == script and not c.is_queued_for_deletion():
			return c
	return null


## Bedtime failed: the bot ends the day itself so the week can go on (recorded as a problem already).
func _force_night() -> bool:
	_act("recover: GameState.end_day()")
	_allow_energy = true
	_gs.end_day()
	_allow_energy = false
	await _recover()
	return false


func _day_eight() -> void:
	_day8_checks()
	if _router.current == "kitchen" and await _kitchen_door("garden"):
		if await _wild_trip(true):
			_shot("garden_day8")


## Day 8's harvest calendar and weather: HUD week label and weather icon, the morning card's calendar lines.
func _day8_checks() -> void:
	var d: Dictionary = _gs.data
	var w := String(d.get("weather", ""))
	var hud: Node = get_first_node_in_group("hud")
	_note_day("weather %s" % w)
	if not ResourceLoader.exists("res://sim/calendar.gd"):
		_notes.append("Day 8 calendar: not present.")
	else:
		var wk := MorningText.week_name(8, false)
		_expect(Calendar.active(8) and wk != "", "medium", "calendar", "no harvest week on day 8")
		var week: Label = hud.get("_week_label") if hud != null else null
		if week == null:
			_notes.append("Day 8 calendar: the HUD has no week label (not present).")
		else:
			_expect(week.visible and week.text == wk, "medium", "calendar", "HUD week label '%s' (visible %s), expected '%s'" % [week.text, week.visible, wk])
		_notes.append("Day 8 calendar: week '%s' (%s in season); morning card: %s." % [wk, ", ".join(Calendar.wild_types(8)), " / ".join(_morning)])
	_expect(w in ["sunny", "rainy", "windy", "foggy"], "medium", "weather", "day 8 weather '%s' is not a known weather" % w)
	_expect(Calendar.weather_table(8) == "p1", "low", "weather", "day 8 still draws from the tutorial weather table")
	if hud != null:
		var icon: TextureRect = hud.get("_weather")
		var icons: Dictionary = hud.get_script().get_script_constant_map().get("WEATHER_ICONS", {})
		_expect(icon != null and icon.texture != null and icon.texture.resource_path.contains(String(icons.get(w, "?"))), "medium", "weather",
			"HUD weather icon %s does not match the '%s' weather" % [icon.texture.resource_path if icon != null and icon.texture != null else "none", w])
		_expect(icon != null and icon.tooltip_text == tr("UI_WEATHER_" + w.to_upper()), "low", "weather", "HUD weather tooltip '%s'" % (icon.tooltip_text if icon != null else ""))
	var weathers: Array = []
	for row in _days:
		weathers.append("%d %s" % [int(row.day), row.weather])
	if _soak_days == 0:
		_notes.append("Weather by day: %s." % ", ".join(weathers))


func _check_wild_weather(w: Node) -> void:
	var d: Dictionary = _gs.data
	var weather := String(d.weather)
	var layer: Node = null
	for c in w.get_children():
		if c.get_script() != null and String(c.get_script().resource_path) == WEATHER_GD:
			layer = c
	if weather in ["windy", "foggy"]:
		_expect(layer != null, "medium", "weather", "no weather layer in the wild on a %s day" % weather)
	var map: Dictionary = w.get("map")
	var falls := 0
	for p in map.get("pickups", []):
		if bool(p.get("windfall", false)):
			falls += 1
	if weather == "windy":
		_expect(falls > 0, "medium", "weather", "windy day 8 but no windfall under the %d fruit trees" % map.fruit_trees.size())
	else:
		_expect(falls == 0, "medium", "weather", "%d windfall pickups on a %s day" % [falls, weather])
	_notes.append("Day 8 wild (%s): %d fruit trees, %d windfalls, weather layer %s." % [weather, map.fruit_trees.size(), falls, "on" if layer != null else "none"])
	_shot("wild_day8_" + weather)


## Granny's To-Do of days 1 and 2: every step the bot did must have ticked (the bed is checked the next morning).
func _check_todo(n: int) -> void:
	var bits := TodoRules.bits_of(_gs.data)
	for step: String in TodoRules.steps_for_day(n):
		if step == "d1_bed":
			continue
		if not TodoRules.is_done(bits, step):
			_problem("medium", "tutorial", "day %d To-Do step '%s' not ticked at bedtime" % [n, tr(TodoRules.key_of(step))])


## After a failed step: closes overlays and goes back to the kitchen (the bed is there).
func _recover() -> void:
	_act("recover: back to the kitchen")
	var ui: Node = get_first_node_in_group("letters_ui")
	if ui != null:
		ui.close()
	await _wait(func() -> bool: return not bool(load(NIGHT_GD).is_running()) and not _busy(), "running transitions to end")
	var path := "res://scenes/kitchen/kitchen.tscn"
	if current_scene == null or current_scene.scene_file_path != path:
		_router.goto("kitchen")
	if not await _arrive("kitchen"):
		_aborted = "could not get back to the kitchen"
		return
	var k := current_scene
	if k.get("_card") != null:
		k.get("_card")._on_close()
	if (k.get("_panel") as Control).visible:
		k.call("_close_panel")
	if (k.get("_dialog") as Control).visible:
		k.call("_close_dialog")
	await _frames(4)


# ================================================================ scenes, waits, checks

func _arrive(id: String) -> bool:
	var path := "res://scenes/%s/%s.tscn" % [id, id]
	var cond := func() -> bool: return current_scene != null and current_scene.scene_file_path == path and not _busy()
	if not await _wait(cond, "the %s scene" % id):
		_problem("high", "scene load", "'%s' did not open (current scene: %s)" % [id, current_scene.scene_file_path if current_scene != null else "none"])
		return false
	_visit_warns = 0
	_visit_flooded = false
	await _frames(10)
	_visits.append("d%d %s" % [_day(), id])
	_shot(id)
	_check_hud(id)
	return true


func _busy() -> bool:
	return bool(load(TRANSITION_GD).is_busy())


func _check_hud(id: String) -> void:
	if not id in ["garden", "wild", "town", "kitchen"]:
		return
	var hud: Node = get_first_node_in_group("hud")
	if hud == null or not (hud as CanvasLayer).visible:
		_problem("medium", "hud", "no HUD in the %s" % id)
		return
	var d: Dictionary = _gs.data
	var day_l: Label = hud.get("_day_label")
	var coins_l: Label = hud.get("_coins_label")
	if day_l != null and not day_l.text.ends_with(" %d" % int(d.day)):
		_problem("low", "hud", "HUD day '%s' on day %d in the %s" % [day_l.text, int(d.day), id])
	if coins_l != null and coins_l.text != str(int(d.coins)):
		_problem("medium", "hud", "HUD shows %s coins, the save has %d (%s)" % [coins_l.text, int(d.coins), id])


## Waits for `cond`; a soft-lock when nothing moves (scene, Granny, coins, energy, bag, inbox) for `stall_ms`.
func _wait(cond: Callable, what: String, stall_ms := STALL_MS) -> bool:
	var last := _fingerprint()
	var since := Time.get_ticks_msec()
	while not bool(cond.call()):
		await process_frame
		var fp := _fingerprint()
		if fp != last:
			last = fp
			since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - since > stall_ms:
			var info := _stall_info()
			_shot("softlock")
			_problem("high", "soft-lock", "no progress for %d s waiting for %s (%s)" % [stall_ms / 1000, what, info])
			return false
		if Time.get_ticks_msec() - _t0 > _budget_ms:
			if _aborted == "":
				_aborted = "time budget"
				_problem("high", "time budget", "the run passed %d s while waiting for %s" % [_budget_ms / 1000, what])
			return false
	return true


## What the screen holds when a wait stalls: overlays on the root, the scene's own overlays, Granny and the cat, the
## control under the mouse and the focus.
func _stall_info() -> String:
	var vr := root.get_visible_rect()
	var out: Array[String] = ["viewport %dx%d" % [int(vr.size.x), int(vr.size.y)]]
	var top: Array[String] = []
	for c in root.get_children():
		if c != current_scene and not _root_base.has(String(c.name)):
			top.append(_node_name(c))
	if not top.is_empty():
		out.append("on the root: " + ", ".join(top))
	var cs := current_scene
	if cs != null:
		out.append("%d nodes in the tree" % cs.get_tree().get_node_count())
		var g: Variant = cs.get("granny")
		if is_instance_valid(g) and g is Node2D and (g as Node).has_method("current_cell"):
			out.append("Granny at %s, moving %s, input %s" % [g.current_cell(), g.is_moving(), g.get("input_enabled")])
		var cat: Variant = cs.get("cat")
		if is_instance_valid(cat) and cat is Node:
			out.append("cat at %s" % cat.get("cell"))
		for prop in ["menu", "_mg", "_card", "_viewer"]:
			var v: Variant = cs.get(prop)
			if v is Node and is_instance_valid(v):
				out.append("%s = %s" % [prop, _node_name(v)])
		var overlay: Variant = cs.get("_overlay")
		if overlay is Node and is_instance_valid(overlay):
			var ov: Array[String] = []
			for c in (overlay as Node).get_children():
				ov.append(_node_name(c))
			out.append("overlay: %s" % ", ".join(ov))
	var hov: Control = root.gui_get_hovered_control() if root.has_method("gui_get_hovered_control") else null
	if hov != null:
		out.append("under the mouse: %s" % _node_name(hov))
	var f := root.gui_get_focus_owner()
	if f != null:
		out.append("focus: %s" % _node_name(f))
	out.append("mouse mask %d" % _mask)
	return "; ".join(out)


func _node_name(n: Node) -> String:
	var s: Script = n.get_script()
	return "%s %s%s" % [n.get_class(), n.name, " (%s)" % s.resource_path.get_file() if s != null else ""]


func _fingerprint() -> String:
	var parts: Array = [_router.current, current_scene.get_instance_id() if current_scene != null else 0]
	var d: Dictionary = _gs.data
	if d.has("coins"):
		parts.append_array([d.day, d.coins, d.energy, d.bag.size(), d.inbox.size()])
	if current_scene != null:
		var g: Variant = current_scene.get("granny")
		if is_instance_valid(g) and g is Node2D:
			parts.append((g as Node2D).position.round())
	return str(parts)


func _drain_log() -> void:
	for e: Dictionary in _log.take():
		var t := int(e.type)
		var where := String(e.where)
		var text := String(e.text)
		if t == 1:
			_visit_warns += 1
			var k := where + "|" + text
			_warns[k] = int(_warns.get(k, 0)) + 1
			_problem("low", "warning", text, where)
			if int(_warns[k]) == FLOOD_SAME:
				_problem("medium", "warning flood", "the same warning %d times: %s" % [FLOOD_SAME, text], where)
			if _visit_warns >= FLOOD_VISIT and not _visit_flooded:
				_visit_flooded = true
				_problem("medium", "warning flood", "%d warnings in one visit of the %s" % [_visit_warns, _router.current])
			continue
		var kind := "SCRIPT ERROR" if t == 2 else ("shader error" if t == 3 else "error")
		_problem("high", kind, text, where)


## Coins and energy may only move during an action that spends or earns them; never below zero or above the max.
func _watch() -> void:
	var d: Dictionary = _gs.data
	if not d.has("coins") or not d.has("energy"):
		return
	var coins := int(d.coins)
	var energy := int(d.energy)
	var emax := int(d.get("energy_max", energy))
	var earned := int(d.get("stats", {}).get("coins_earned", 0))
	if coins < 0:
		_problem("high", "coin anomaly", "coins below zero (%d)" % coins, "", "coins<0")
	if energy < 0:
		_problem("high", "energy anomaly", "energy below zero (%d)" % energy, "", "energy<0")
	if energy > emax:
		_problem("medium", "energy anomaly", "energy %d above energy_max %d" % [energy, emax], "", "energy>max")
	if _last_coins >= 0 and coins != _last_coins and not _allow_coins:
		_problem("medium", "coin anomaly", "coins changed by %+d outside a buy, sale, order or market" % (coins - _last_coins), "", "coins-unexplained|" + String(_router.current))
	if _last_energy >= 0 and energy != _last_energy and not _allow_energy:
		_problem("medium", "energy anomaly", "energy changed by %+d outside foraging, the garden, cooking or the night" % (energy - _last_energy), "", "energy-unexplained|" + String(_router.current))
	if earned < _last_earned:
		_problem("medium", "coin anomaly", "stats.coins_earned went down (%d -> %d)" % [_last_earned, earned], "", "earned-down")
	_last_coins = coins
	_last_energy = energy
	_last_earned = earned


func _problem(sev: String, kind: String, what: String, where := "", key := "") -> void:
	var k := key if key != "" else "%s|%s|%s" % [kind, where, what]
	if _keys.has(k):
		_problems[int(_keys[k])].count += 1
		return
	_keys[k] = _problems.size()
	_problems.append({"sev": sev, "kind": kind, "what": what, "where": where, "day": _day(), "scene": String(_router.current),
		"repro": _repro(), "count": 1})
	print("PROBLEM [%s] %s: %s %s" % [sev, kind, what, where])


func _expect(ok: bool, sev: String, kind: String, what: String, where := "") -> bool:
	if not ok:
		_problem(sev, kind, what, where)
	return ok


func _act(s: String) -> void:
	_trail.append(s)
	_act_us = Time.get_ticks_usec()
	print("[d%d %ds] %s" % [_day(), (Time.get_ticks_msec() - _t0) / 1000, s])


func _repro() -> String:
	var tail := _trail.slice(maxi(0, _trail.size() - 3))
	return "New Game, seed %d, day %d: %s" % [SEED, _day(), " > ".join(tail)]


func _day() -> int:
	return int(_gs.data.get("day", 0)) if _gs != null else 0


func _day_row() -> Dictionary:
	return _days[_days.size() - 1] if not _days.is_empty() else {"cooked": [], "orders": 0, "sold": 0, "notes": []}


func _note_day(s: String) -> void:
	(_day_row().notes as Array).append(s)


# ================================================================ items and buttons

func _all_items(d: Dictionary) -> Array:
	var items: Array = d.inbox.duplicate()
	for e in d.pantry.items:
		items.append(e.item)
	return items


func _item_at(d: Dictionary, ref: Dictionary) -> Dictionary:
	var i := int(ref.get("index", -1))
	match String(ref.get("where", "")):
		"inbox":
			return d.inbox[i] if i >= 0 and i < d.inbox.size() else {}
		"pantry":
			return d.pantry.items[i].item if i >= 0 and i < d.pantry.items.size() else {}
	return {}


func _item_label(item: Dictionary) -> String:
	match String(item.get("kind", "")):
		"product":
			return String(item.key)
		"fresh":
			return "%s x%d" % [item.variety, int(item.count)]
		"nut":
			return "%s x%d" % [item.type, int(item.count)]
	return "?"


func _order(id: int) -> Dictionary:
	for o in _gs.data.orders:
		if int(o.id) == id:
			return o
	return {}


func _matchable(id: int) -> bool:
	var o := _order(id)
	if o.is_empty():
		return false
	for it in _all_items(_gs.data):
		if Orders.matches(o, it, _gs.data.varieties):
			return true
	return false


func _any_matchable() -> bool:
	for o in _gs.data.orders:
		if _matchable(int(o.id)):
			return true
	return false


func _buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for c in node.find_children("*", "Button", true, false):
		var b := c as Button
		if b != null and b.is_visible_in_tree() and not b.is_queued_for_deletion():
			out.append(b)
	return out


func _text_button(node: Node, text: String) -> Button:
	for b in _buttons(node):
		if b.text == text:
			return b
	return null


## The visible button whose pressed callback is bound to `arg` first (town toggles: "supplies", "seeds", "upgrades").
func _bound_button(node: Node, arg: String) -> Button:
	for b in _buttons(node):
		var args := _bound(b)
		if not args.is_empty() and typeof(args[0]) == TYPE_STRING and String(args[0]) == arg:
			return b
	return null


func _bound(b: BaseButton) -> Array:
	for con in b.pressed.get_connections():
		var cb: Callable = con.callable
		var args := cb.get_bound_arguments()
		if not args.is_empty():
			return args
	return []


func _slot_pos(view: Control, i: int) -> Vector2:
	var r: Rect2i = view.call("slot_rect", i)
	return view.get_global_rect().position + Vector2(r.position) + Vector2(12, 12)


# ================================================================ input

func _click_ctrl(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		_problem("medium", "ui", "a control to click is missing or hidden (%s)" % (c.name if c != null else "null"))
		return false
	await process_frame  # containers sort their children at the end of a frame: click where the control is now
	await _click(c.get_global_rect().get_center().floor())
	return true


func _click(at: Vector2) -> void:
	_move(at)
	await process_frame
	_button(at, MOUSE_BUTTON_LEFT, true)
	await process_frame
	_button(at, MOUSE_BUTTON_LEFT, false)
	await process_frame


func _drag(a: Vector2, b: Vector2, turn := false) -> void:
	_move(a)
	await process_frame
	_button(a, MOUSE_BUTTON_LEFT, true)
	await process_frame
	_move(a.lerp(b, 0.5))
	await process_frame
	if turn:
		_key(KEY_R)
		await process_frame
	_move(b)
	await process_frame
	_button(b, MOUSE_BUTTON_LEFT, false)
	await process_frame


func _button(p: Vector2, button: MouseButton, pressed: bool) -> void:
	var bit := 1 << (int(button) - 1)
	_mask = (_mask | bit) if pressed else (_mask & ~bit)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = _mask
	ev.position = p
	ev.global_position = p
	root.push_input(ev, true)


func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.button_mask = _mask
	root.push_input(ev, true)


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		root.push_input(ev, true)


func _action(name: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = name
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _type(text: String) -> void:
	for ch in text:
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = OS.find_keycode_from_string(ch)
			ev.physical_keycode = ev.keycode
			ev.unicode = ch.unicode_at(0)
			ev.pressed = pressed
			root.push_input(ev, true)
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


# ================================================================ output

func _prepare_dir() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	for f in DirAccess.get_files_at(_dir):
		if f.ends_with(".png"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir.path_join(f)))


func _shot(label: String) -> void:
	_shots += 1
	var path := "%s/d%d_%03d_%s.png" % [_dir, _day(), _shots, label]
	RenderingServer.force_draw(false)  # macOS skips drawing a covered window; the shot must show this frame
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(path)
	_skip_frames = 2  # the GPU read-back and the PNG are the bot's time, not the game's


func _finish() -> void:
	_drain_log()
	Engine.time_scale = 1.0
	if _soak_days > 0:
		_soak_checks()
		if FileAccess.file_exists(SAVE_PATH):  # the soak's last save, to load and repeat what the report says
			DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(_dir.path_join("soak_end_save.json")))
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if _had_bak:
		var fb := FileAccess.open(BAK_PATH, FileAccess.WRITE)
		fb.store_string(_backup_bak)
		fb.close()
	elif FileAccess.file_exists(BAK_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BAK_PATH))
	var md := _soak_report() if _soak_days > 0 else _report()
	var path := ProjectSettings.globalize_path("res://").path_join(SOAK_REPORT if _soak_days > 0 else REPORT).simplify_path()
	var keep := ""
	if FileAccess.file_exists(path):
		var old := FileAccess.get_file_as_string(path)
		var at := old.find(NOTES)
		if at >= 0:
			keep = old.substr(at)
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	if f2 != null:
		f2.store_string(md + ("\n" + keep if keep != "" else ""))
		f2.close()
	var high := 0
	for p in _problems:
		high += 1 if p.sev == "high" else 0
	if _gs.data.has("stats"):
		print("week_bot economy: %d coins at the end, %d earned, %d orders, smallest purse after shopping %d (day %d)" % [
			int(_gs.data.coins), int(_gs.data.stats.get("coins_earned", 0)), int(_gs.data.stats.get("orders_done", 0)), _low_coins, _low_day])
	print("%s: day %d reached in %d s, %d problems (%d high), %d screenshots in %s, report %s" % [
		"soak" if _soak_days > 0 else "week_bot", _day(), (Time.get_ticks_msec() - _t0) / 1000, _problems.size(), high, _shots, ProjectSettings.globalize_path(_dir), path])
	quit(1 if high > 0 else 0)


func _report() -> String:
	var secs := (Time.get_ticks_msec() - _t0) / 1000
	var rows: Array = _problems.duplicate()
	rows.sort_custom(_by_severity)
	var lines: Array[String] = []
	lines.append("# Week bot report (QA-WEEK)")
	lines.append("")
	lines.append("Written by `game/tests/smoke/week_bot.gd` on %s. New Game with seed %d, played through the real scenes up to day %d%s in %d:%02d (Engine.time_scale x%s). Screenshots: %d in `user://week_bot/`." % [
		Time.get_datetime_string_from_system(false, true), SEED, _day(), " (stopped: %s)" % _aborted if _aborted != "" else "", secs / 60, secs % 60, _speed, _shots])
	lines.append("")
	lines.append("Run it: `perl -e 'alarm shift; exec @ARGV' 900 godot --path game --audio-driver Dummy -s res://tests/smoke/week_bot.gd` (windowed; exit 1 on a high problem).")
	lines.append("")
	lines.append("## Problems")
	lines.append("")
	lines.append("| # | Severity | Kind | Where | What | Seen | Day / scene | Repro |")
	lines.append("|---|---|---|---|---|---|---|---|")
	if rows.is_empty():
		lines.append("| - | - | - | - | No problems found | - | - | - |")
	for i in rows.size():
		var p: Dictionary = rows[i]
		lines.append("| %d | %s | %s | %s | %s | %dx | %d / %s | %s |" % [i + 1, p.sev, p.kind, _cell(String(p.where)), _cell(String(p.what)),
			int(p.count), int(p.day), p.scene, _cell(String(p.repro))])
	lines.append("")
	lines.append("## The week")
	lines.append("")
	lines.append("| Day | Weather | Coins (morning) | Energy (morning) | Cooked | Orders | Sold (market) | Notes |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for r in _days:
		lines.append("| %d | %s | %d | %d / %d | %s | %d | %d | %s |" % [int(r.day), r.weather, int(r.coins), int(r.energy), int(r.energy_max),
			_cell(", ".join(r.cooked)), int(r.orders), int(r.sold), _cell("; ".join(r.notes))])
	var d: Dictionary = _gs.data
	if not d.is_empty():
		lines.append("")
		lines.append("End: day %d, %d coins, %d jars made, %d orders done, %d coins earned, %d book variants." % [int(d.day), int(d.coins),
			int(d.stats.jars_made), int(d.stats.orders_done), int(d.stats.coins_earned), d.book.variants.size()])
	lines.append("")
	lines.append("## Coverage")
	lines.append("")
	var mg: Array[String] = []
	for k in _mg_count:
		mg.append("%s x%d" % [k, int(_mg_count[k])])
	lines.append("- Mini-games played: %s." % (", ".join(mg) if not mg.is_empty() else "none"))
	var per_scene := {}
	for v in _visits:
		var id := v.split(" ")[1]
		per_scene[id] = int(per_scene.get(id, 0)) + 1
	var sc: Array[String] = []
	for k in per_scene:
		sc.append("%s x%d" % [k, int(per_scene[k])])
	lines.append("- Scene visits: %s." % ", ".join(sc))
	if _low_coins >= 0:
		lines.append("- Economy (CUT-CLUTTER, no grocer's Sell): coins come from orders and the market only; the smallest purse after shopping was %d coins on day %d." % [_low_coins, _low_day])
	for n in _notes:
		lines.append("- " + n)
	lines.append("")
	return "\n".join(lines)


func _by_severity(a: Dictionary, b: Dictionary) -> bool:
	var sa := SEVERITY.find(String(a.sev))
	var sb := SEVERITY.find(String(b.sev))
	return sa < sb or (sa == sb and int(a.day) < int(b.day))


func _cell(s: String) -> String:
	return s.replace("|", "\\|").replace("\n", " ")


# ================================================================ soak (QA-02)

## Memory and object counts at the same moment every day: the morning in the kitchen (day 1: the garden after New Game).
func _sample() -> void:
	await _frames(30)  # queue_free and the morning card's last tweens settle
	var row := _day_row()
	row.static_kb = OS.get_static_memory_usage() / 1024
	row.objects = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	row.nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	row.orphans = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	row.resources = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	row.video_kb = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1024
	row.save_kb = JSON.stringify(_gs.data).length() / 1024.0
	row.scene = String(_router.current)
	row.orphan_list = _orphans()
	print("SAMPLE d%d %s static %d KB, objects %d, nodes %d, orphans %d, resources %d, video %d KB, save %.1f KB; orphans: %s" % [
		int(row.day), row.scene, int(row.static_kb), int(row.objects), int(row.nodes), int(row.orphans), int(row.resources),
		int(row.video_kb), float(row.save_kb), ", ".join(row.orphan_list)])


## Nodes outside the tree that nobody freed: "Class 'name' (script)" each, to point at the code that made them.
func _orphans() -> Array[String]:
	var out: Array[String] = []
	for id: int in Node.get_orphan_node_ids():
		var n := instance_from_id(id) as Node
		if n == null:
			continue
		var s: Script = n.get_script()
		out.append("%s '%s'%s" % [n.get_class(), n.name, " (%s)" % s.resource_path.replace("res://", "game/") if s != null else ""])
	out.sort()
	return out


## Soak: buys upgrades in SOAK_UPGRADES order while the coins cover the price and SOAK_RESERVE; saves up for the next
## one in the list rather than buying a cheaper one after it.
func _upgrades(t: Node) -> bool:
	var d: Dictionary = _gs.data
	var opened := false
	for id: String in SOAK_UPGRADES:
		if Economy.price(d, id) < 0:
			continue  # bought out, or not on sale
		if int(d.coins) < Economy.price(d, id) + SOAK_RESERVE:
			break
		for level in 3:
			var price := Economy.price(d, id)
			if price < 0 or int(d.coins) < price + SOAK_RESERVE:
				break
			if not opened:
				_act("town: Grocer tab, Upgrades")
				await _click_ctrl((t.get("_tab_buttons") as Dictionary).grocer)
				await _frames(2)
				await _click_ctrl(_bound_button(t, "upgrades"))
				await _frames(3)
				opened = true
			var b: Button = await _page_to(t, id)
			if b == null:
				_problem("medium", "town", "no Buy row for the %s upgrade (price %d)" % [id, price])
				break
			var c0 := int(d.coins)
			var lv := int(d.upgrades.get(id, 0))
			_allow_coins = true
			_act("town: Buy the %s upgrade (%d coins)" % [id, price])
			await _click_ctrl(b)
			await _frames(4)
			_allow_coins = false
			_expect(c0 - int(d.coins) == price and int(d.upgrades.get(id, 0)) == lv + 1, "high", "coin anomaly",
				"the %s upgrade cost %d (price %d), level %d -> %d" % [id, c0 - int(d.coins), price, lv, int(d.upgrades.get(id, 0))])
			if id != "pantry_row":
				_expect(Economy.unlocked(d, id), "medium", "upgrade", "buying the %s upgrade did not unlock it" % id)
			if id == "beds":
				_expect(d.garden.beds.size() >= int(Data.shop().upgrades.beds.beds), "medium", "upgrade", "the beds upgrade left %d garden beds" % d.garden.beds.size())
			if id == "boots":
				_expect(WildGen.biome_open(d, "creek"), "medium", "upgrade", "the boots did not open the creek")
			_bought_upgrades.append("%s %d (day %d, %d coins)" % [id, lv + 1, _day(), price])
			_note_day("upgrade %s %d" % [id, lv + 1])
	if opened:
		await _frames(4)
		_shot("town_upgrades")
	return true


## Soak: memory and counts that keep growing over the second half, and the frame-time spikes grouped by scene and step.
func _soak_checks() -> void:
	for metric: String in GROWTH_LIMIT:
		var g := _growth(metric)
		if g.is_empty():
			continue
		var limit := float(GROWTH_LIMIT[metric])
		if float(g.late) > limit:
			var sev := "medium"  # a slow leak: nothing breaks within a play session
			var what := "%s grows %.1f a day over days %d-%d (%s -> %s) and does not level off (limit %.1f a day; days %d-%d: %.1f a day)" % [
				metric, g.late, g.from, g.to, g.v_from, g.v_to, limit, g.first, g.from, g.early]
			if metric == "orphans":
				what += "; orphans on day %d: %s" % [int(g.to), _orphan_summary()]
			_add_problem(sev, "memory growth", what, "", int(g.to), "kitchen",
				"New Game, seed %d, play %d days: compare the morning samples in the kitchen" % [SEED, int(g.to)], 1)
	var groups := {}
	for s: Dictionary in _spikes:
		var k := "%s|%s|%s" % [s.scene, s.kind, _act_kind(String(s.act))]
		if not groups.has(k):
			groups[k] = {"scene": s.scene, "kind": s.kind, "act": String(s.act), "day": int(s.day), "n": 0, "max": 0.0, "days": {}}
		var gr: Dictionary = groups[k]
		gr.n = int(gr.n) + 1
		gr.max = maxf(float(gr.max), float(s.ms))
		gr.days[int(s.day)] = true
	var when := {"fade": "behind a fade (scene change or the night)", "cut": "on a scene change without a fade", "play": "in play"}
	for k in groups:
		var gr: Dictionary = groups[k]
		var sev := "low" if String(gr.kind) == "fade" or float(gr.max) < 100.0 else "medium"
		_add_problem(sev, "frame spike", "%d frame(s) over %d ms %s, worst %d ms (days %s)" % [int(gr.n), int(SPIKE_MS), when[gr.kind], roundi(float(gr.max)), _days_list(gr.days)],
			"scene " + String(gr.scene), int(gr.day), String(gr.scene), "New Game, seed %d, day %d: %s" % [SEED, int(gr.day), gr.act], int(gr.n))


## Least-squares slope of a sampled metric per day: "early" over the first half, "late" over the second half.
func _growth(metric: String) -> Dictionary:
	var pts: Array = []
	for r: Dictionary in _days:
		if r.has(metric) and int(r.day) >= 2:  # day 1 is sampled in the garden right after New Game
			pts.append(Vector2(float(r.day), float(r[metric])))
	if pts.size() < 6:
		return {}
	var mid := pts.size() / 2
	var late: Array = pts.slice(mid)
	return {"early": _slope(pts.slice(0, mid + 1)), "late": _slope(late), "first": int(pts[0].x), "from": int(late[0].x),
		"to": int(late[late.size() - 1].x), "v_from": str(int(late[0].y)), "v_to": str(int(late[late.size() - 1].y))}


func _slope(pts: Array) -> float:
	var n := float(pts.size())
	var sx := 0.0
	var sy := 0.0
	var sxy := 0.0
	var sxx := 0.0
	for p: Vector2 in pts:
		sx += p.x
		sy += p.y
		sxy += p.x * p.y
		sxx += p.x * p.x
	var den := n * sxx - sx * sx
	return 0.0 if is_zero_approx(den) else (n * sxy - sx * sy) / den


## The last sample's orphan nodes, the same ones counted: "Class 'name' (script) x3".
func _orphan_summary() -> String:
	var list: Array = []
	for r: Dictionary in _days:
		if r.has("orphan_list"):
			list = r.orphan_list
	var counts := {}
	for o: String in list:
		counts[o] = int(counts.get(o, 0)) + 1
	var out: Array[String] = []
	for o: String in counts:
		out.append(o + (" x%d" % int(counts[o]) if int(counts[o]) > 1 else ""))
	return ", ".join(out) if not out.is_empty() else "none"


## An action without its item ("pantry: drag jam|apple_3|- onto the cool shelf" -> "pantry: drag * onto the cool shelf").
func _act_kind(act: String) -> String:
	var words: Array[String] = []
	for w in act.split(" "):
		words.append("*" if w.contains("|") or w.contains("_") or w.is_valid_int() or w.begins_with("(") else w)
	return " ".join(words)


func _days_list(days: Dictionary) -> String:
	var keys: Array = days.keys()
	keys.sort()
	var out: Array[String] = []
	for k in keys:
		out.append(str(k))
	return ", ".join(out)


func _add_problem(sev: String, kind: String, what: String, where: String, day: int, scene: String, repro: String, count: int) -> void:
	_problems.append({"sev": sev, "kind": kind, "what": what, "where": where, "day": day, "scene": scene, "repro": repro, "count": count})
	print("PROBLEM [%s] %s: %s %s" % [sev, kind, what, where])


func _soak_report() -> String:
	var secs := (Time.get_ticks_msec() - _t0) / 1000
	var rows: Array = _problems.duplicate()
	rows.sort_custom(_by_severity)
	var lines: Array[String] = []
	lines.append("# Soak run report (QA-02)")
	lines.append("")
	lines.append("Written by `game/tests/smoke/week_bot.gd -- --days %d` on %s. New Game with seed %d, %d days played through the real scenes, stopped on the morning of day %d%s, in %d:%02d (Engine.time_scale x%s, windowed, viewport %dx%d). Screenshots: %d in `user://soak/`." % [
		_soak_days, Time.get_datetime_string_from_system(false, true), SEED, _soak_days, _day(), " (stopped: %s)" % _aborted if _aborted != "" else "",
		secs / 60, secs % 60, _speed, int(root.get_visible_rect().size.x), int(root.get_visible_rect().size.y), _shots])
	lines.append("")
	lines.append("Run it: `perl -e 'alarm shift; exec @ARGV' 2400 godot --path game --audio-driver Dummy -s res://tests/smoke/week_bot.gd -- --days 20` (exit 1 on a high problem). Without `--days` the same bot plays the classic week (`docs/qa/week_bot.md`).")
	lines.append("")
	lines.append("## Problems")
	lines.append("")
	lines.append("Most severe first. High: script error, soft-lock, scene load failure, coin anomaly. Medium: wrong result, growth that does not level off (a leak), a spike over 100 ms in play. Low: spikes during scene changes, warnings, spec mismatches, polish.")
	lines.append("")
	lines.append("| # | Severity | Kind | Where | What | Seen | Day / scene | Repro |")
	lines.append("|---|---|---|---|---|---|---|---|")
	if rows.is_empty():
		lines.append("| - | - | - | - | No problems found | - | - | - |")
	for i in rows.size():
		var p: Dictionary = rows[i]
		lines.append("| %d | %s | %s | %s | %s | %dx | %d / %s | %s |" % [i + 1, p.sev, p.kind, _cell(String(p.where)), _cell(String(p.what)),
			int(p.count), int(p.day), p.scene, _cell(String(p.repro))])
	lines.append("")
	lines.append("## The days")
	lines.append("")
	lines.append("Sampled every morning in the kitchen once the morning card is closed (day 1: the garden after New Game). Static = `OS.get_static_memory_usage()`; objects, nodes, orphans and resources from `Performance`; video = `RENDER_VIDEO_MEM_USED`; save = the save as JSON. Spikes = frames over %d ms of real time during that day (the frames of the bot's own screenshots are skipped)." % int(SPIKE_MS))
	lines.append("")
	lines.append("| Day | Weather | Coins | Energy | Cooked | Orders | Sold (market) | Static MB | Objects | Nodes | Orphans | Resources | Video MB | Save KB | Spikes (max ms) | Notes |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r: Dictionary in _days:
		lines.append("| %d | %s | %d | %d / %d | %s | %d | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % [int(r.day), r.weather, int(r.coins),
			int(r.energy), int(r.energy_max), _cell(", ".join(r.cooked)), int(r.orders), int(r.sold),
			"%.1f" % (float(r.get("static_kb", 0)) / 1024.0), str(r.get("objects", "-")), str(r.get("nodes", "-")), str(r.get("orphans", "-")),
			str(r.get("resources", "-")), "%.1f" % (float(r.get("video_kb", 0)) / 1024.0), "%.1f" % float(r.get("save_kb", 0.0)),
			"%d (%d)" % [int(r.get("spikes", 0)), roundi(float(r.get("max_ms", 0.0)))], _cell("; ".join(r.notes))])
	var d: Dictionary = _gs.data
	if not d.is_empty():
		lines.append("")
		lines.append("End: day %d, %d coins, %d jars made, %d orders done, %d coins earned, %d book variants." % [int(d.day), int(d.coins),
			int(d.stats.jars_made), int(d.stats.orders_done), int(d.stats.coins_earned), d.book.variants.size()])
	lines.append("")
	lines.append("## Growth")
	lines.append("")
	lines.append("Least-squares slope per day of the morning samples (day 2 on), first half against second half. A metric levels off when its second-half slope stays under the limit.")
	lines.append("")
	lines.append("| Metric | Days | First half / day | Second half / day | Limit / day | Levels off |")
	lines.append("|---|---|---|---|---|---|")
	for metric: String in GROWTH_LIMIT:
		var g := _growth(metric)
		if g.is_empty():
			lines.append("| %s | - | - | - | %.1f | not enough days |" % [metric, float(GROWTH_LIMIT[metric])])
			continue
		lines.append("| %s | %d-%d | %.1f | %.1f | %.1f | %s |" % [metric, int(g.first), int(g.to), float(g.early), float(g.late),
			float(GROWTH_LIMIT[metric]), "yes" if float(g.late) <= float(GROWTH_LIMIT[metric]) else "**no**"])
	lines.append("")
	lines.append("Orphan nodes at the last sample: %s." % _orphan_summary())
	lines.append("")
	lines.append("## Coverage")
	lines.append("")
	var mg: Array[String] = []
	for k in _mg_count:
		mg.append("%s x%d" % [k, int(_mg_count[k])])
	lines.append("- Mini-games played: %s; batch cooks (Mastered, no mini-game): %d." % [", ".join(mg) if not mg.is_empty() else "none", _batch_count])
	lines.append("- Mastered: %s." % (", ".join(_mastered) if not _mastered.is_empty() else "none"))
	lines.append("- Upgrades bought: %s." % (", ".join(_bought_upgrades) if not _bought_upgrades.is_empty() else "none"))
	var bi: Array[String] = []
	for k in _biomes:
		bi.append("%s x%d" % [k, int(_biomes[k])])
	lines.append("- Wild trips: %s." % ", ".join(bi))
	var per_scene := {}
	for v in _visits:
		var id := v.split(" ")[1]
		per_scene[id] = int(per_scene.get(id, 0)) + 1
	var sc: Array[String] = []
	for k in per_scene:
		sc.append("%s x%d" % [k, int(per_scene[k])])
	lines.append("- Scene visits: %s." % ", ".join(sc))
	var weathers: Array[String] = []
	for row in _days:
		weathers.append("%d %s" % [int(row.day), row.weather])
	lines.append("- Weather by day: %s." % ", ".join(weathers))
	for n in _notes:
		lines.append("- " + n)
	lines.append("")
	return "\n".join(lines)
