extends "res://tests/_runner/test_case.gd"
## P2-FAREWELL: the hidden day-100 ending (spec §7.12): trigger, Memory mode, Tonty's letter, the day 90-99 hints.

const SEEDS := [1, 7, 42, 2026]


func _keys() -> Dictionary:
	var keys := {}
	var f := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > 1:
			keys[row[0]] = row[1]
	return keys


## Every line's key exists and its template takes exactly its args (tr(key) % args never fails).
func _check_lines(lines: Array, what: String) -> void:
	var keys := _keys()
	for l in lines:
		var key := String(l.key)
		if key == "":
			continue
		assert_has(keys, key, what)
		var tpl := String(keys.get(key, ""))
		var holes := tpl.count("%s") + tpl.count("%d")
		assert_eq(holes, (l.args as Array).size(), "%s: %s placeholders" % [what, key])
		if holes == (l.args as Array).size() and holes > 0:
			assert_false((tpl % l.args).contains("%"), "%s: %s formats" % [what, key])


func _jar_keys(s: Dictionary, n: int) -> Array:
	var out: Array = []
	for c in Orders.candidates(s, Orders.product_taste()):
		if not String(c.key) in out:
			out.append(String(c.key))
		if out.size() == n:
			break
	return out


func _put_jar(s: Dictionary, key: String, q: int, x: int, y: int) -> void:
	s.pantry.items.append({"item": State.product(key, q, 0), "x": x, "y": y, "rot": 0})


# ---------------------------------------------------------------- trigger

func test_ending_cannot_trigger_before_the_night_of_day_99() -> void:
	var s := State.new_game(1)
	for day in range(1, Farewell.LAST_DAY):
		s.day = day
		assert_false(Farewell.triggers(s), "day %d" % day)
		assert_eq(Farewell.night_kind(s), "normal", "day %d" % day)
	s.day = Farewell.LAST_DAY
	assert_true(Farewell.triggers(s), "bedtime on day 99")
	assert_eq(Farewell.night_kind(s), "farewell")


func test_normal_nights_never_close_the_save() -> void:
	var s := State.new_game(42)
	while int(s.day) < Farewell.LAST_DAY:
		assert_eq(Farewell.night_kind(s), "normal", "night after day %d" % int(s.day))
		DayEnd.run(s)
	assert_eq(int(s.day), Farewell.LAST_DAY)
	assert_false(Farewell.is_completed(s), "98 nights later the save is still open")


func test_farewell_night_closes_the_save_on_day_100() -> void:
	var s := State.new_game(7)
	s.day = Farewell.LAST_DAY
	DayEnd.run(s)
	Farewell.complete(s)
	assert_eq(int(s.day), Farewell.FINAL_DAY)
	assert_true(Farewell.is_completed(s))
	assert_eq(Farewell.completed_day(s), 100)
	assert_false(Farewell.seen(s), "the first viewing cannot be skipped")
	assert_false(Farewell.triggers(s), "never twice")
	assert_eq(Farewell.night_kind(s), "memory")


func test_old_saves_without_the_new_flags() -> void:
	var s := {"day": 12}
	assert_false(Farewell.is_completed(s))
	assert_false(Farewell.seen(s))
	assert_false(Farewell.is_memory(s))
	assert_eq(Farewell.night_kind(s), "normal")


## Farewell.night is what GameState.end_day runs (it only adds the disk and the scene change).
func test_memory_mode_never_advances_the_day() -> void:
	var s := State.new_game(1)
	s.day = 100
	Farewell.complete(s)
	s.flags["memory"] = true
	var before := JSON.stringify(s)
	for i in 3:
		var n := Farewell.night(s)
		assert_eq(n.kind, "memory")
		assert_eq(n.events, [], "no night events in Memory mode")
	assert_eq(int(s.day), 100, "the day never moves on")
	assert_eq(JSON.stringify(s), before, "nothing in the save changes")
	s.flags.erase("memory")
	assert_eq(Farewell.night(s).kind, "memory", "a completed save never starts a new day either")
	assert_eq(int(s.day), 100)


func test_night_runs_the_farewell_only_from_day_99() -> void:
	var s := State.new_game(3)
	s.day = 98
	var n := Farewell.night(s)
	assert_eq(n.kind, "normal")
	assert_eq(int(s.day), 99)
	assert_false(Farewell.is_completed(s))
	n = Farewell.night(s)
	assert_eq(n.kind, "farewell")
	assert_eq(n.events, [])
	assert_eq(int(n.backup.day), 99, "the backup is the day-99 save")
	assert_false(Farewell.is_completed(n.backup))
	assert_eq(int(s.day), 100)
	assert_true(Farewell.is_completed(s))
	assert_eq(Farewell.night(s).kind, "memory")
	assert_eq(int(s.day), 100)


# ---------------------------------------------------------------- the letter

func test_letter_with_an_empty_pantry_uses_the_fallbacks() -> void:
	for sd in SEEDS:
		var s := State.new_game(sd)
		s.day = 100
		var lines := Farewell.letter(s)
		var keys: Array = lines.map(func(l: Dictionary) -> String: return String(l.key))
		assert_eq(keys, ["FAREWELL_LETTER_DEAR_TWO", "FAREWELL_LETTER_DAYS", "FAREWELL_LETTER_JARS_NONE",
			"FAREWELL_LETTER_TOP_NONE", "FAREWELL_LETTER_RARE_NONE", "FAREWELL_LETTER_FRIEND_NONE",
			"FAREWELL_LETTER_LOVE", "FAREWELL_LETTER_SIGN"], "seed %d" % sd)
		assert_eq(lines[1].args, [100])
		_check_lines(lines, "empty pantry")


func test_letter_with_one_jar() -> void:
	var s := State.new_game(1)
	s.day = 100
	var key: String = _jar_keys(s, 1)[0]
	_put_jar(s, key, 2, 0, 0)
	s.stats.jars_made = 1
	var lines := Farewell.letter(s)
	assert_eq(lines[2].key, "FAREWELL_LETTER_JARS_ONE")
	assert_eq(lines[3].key, "FAREWELL_LETTER_TOP_1")
	assert_eq(lines[3].args, [ProductGen.product_name(key, s.varieties)])
	_check_lines(lines, "one jar")


func test_letter_names_the_best_jars_the_rarest_find_and_the_dearest_neighbour() -> void:
	var s := State.new_game(2026)
	var keys := _jar_keys(s, 4)
	assert_eq(keys.size(), 4)
	for i in keys.size():
		_put_jar(s, keys[i], 1 + i % 3, i, 0)
	_put_jar(s, keys[0], 1, 0, 1)  # a second jar of the same product counts once
	s.stats.jars_made = 23
	var rare := ""
	for id in s.varieties:
		if String(s.varieties[id].get("rarity", "")) == "rare":
			rare = id
	s.found_varieties = [keys[0].split("|")[1], rare] if rare != "" else []
	s.friendship.baker = int(Data.rules().friendship.points_per_heart) * 2
	var top := Farewell.top_jars(s)
	assert_eq(top.size(), 3)
	for i in top.size() - 1:
		assert_true(int(top[i].value) >= int(top[i + 1].value), "best first")
	var lines := Farewell.letter(s)
	assert_eq(lines[2].key, "FAREWELL_LETTER_JARS")
	assert_eq(lines[2].args, [23])
	assert_eq(lines[3].key, "FAREWELL_LETTER_TOP_3")
	assert_eq(lines[3].args, top.map(func(j: Dictionary) -> String: return String(j.name)))
	if rare != "":
		assert_eq(lines[4].key, "FAREWELL_LETTER_RARE")
		assert_eq(lines[4].args, [String(s.varieties[rare].name)])
	assert_eq(lines[5].key, "FAREWELL_LETTER_FRIEND")
	assert_eq(lines[5].args, [Farewell.npc_name("baker")])
	_check_lines(lines, "full pantry")


func test_credits_and_book_lines_format() -> void:
	var s := State.new_game(1)
	_check_lines(Farewell.credits(s), "credits")
	var d := DevTools.load_demo()
	if not d.is_empty():
		_check_lines(Farewell.credits(d), "demo credits")
		_check_lines(Farewell.letter(d), "demo letter")
		assert_eq(Farewell.book_variants(d).size(), d.book.variants.size())
	var keys := _keys()
	for k in ["FAREWELL_PAN_EMPTY", "FAREWELL_SNOW_LINE", "FAREWELL_BOOK_HEAD", "FAREWELL_BOOK_EMPTY",
			"FAREWELL_THANKS", "FAREWELL_FOR_TONTY", "FAREWELL_HOLD_SKIP", "FAREWELL_LETTER_DEAR"]:
		assert_has(keys, k)


func test_pan_keeps_the_most_valuable_jars_in_shelf_order() -> void:
	var s := State.new_game(1)
	var keys := _jar_keys(s, 4)
	for i in 20:
		_put_jar(s, keys[i % keys.size()], 1 + i % 3, i % 5, floori(i / 5.0))
	var pan := Farewell.pan_jars(s)
	assert_eq(pan.size(), Farewell.MAX_PAN_JARS)
	var all := Farewell.pantry_jars(s)
	var values: Array = all.map(func(j: Dictionary) -> int: return int(j.value))
	values.sort()
	values.reverse()
	var pan_values: Array = pan.map(func(j: Dictionary) -> int: return int(j.value))
	pan_values.sort()
	pan_values.reverse()
	assert_eq(pan_values, values.slice(0, Farewell.MAX_PAN_JARS), "the most valuable stay")


# ---------------------------------------------------------------- days 90-99

func test_hint_days_are_90_to_99() -> void:
	assert_false(Farewell.is_hint_day(89))
	assert_true(Farewell.is_hint_day(90))
	assert_true(Farewell.is_hint_day(99))
	assert_false(Farewell.is_hint_day(100))
	assert_eq(Farewell.walk_scale(50), 1.0)
	assert_true(Farewell.walk_scale(95) < 1.0, "slower walk on day 95")


func test_worried_letters_on_hint_days_keep_the_stream() -> void:
	var keys := _keys()
	for kid in Letters.kids():
		for n in range(1, Letters.NOTE_COUNT + 1):
			assert_eq(Farewell.note_key(kid, n, 50), "LET_NOTE_%s_%d" % [String(kid).to_upper(), n])
			var worried := Farewell.note_key(kid, n, 95)
			assert_true(worried.begins_with("FAREWELL_WORRY_"), worried)
			assert_has(keys, worried)
	var s := State.new_game(1)
	s.day = 94
	var a := Letters.make_request(s, "mia", Seeds.rng(1, "letters", 94))
	s.day = 40
	var b := Letters.make_request(s, "mia", Seeds.rng(1, "letters", 94))
	assert_true(String(a.note).begins_with("FAREWELL_WORRY_MIA_"), "worried note on day 94")
	assert_true(String(b.note).begins_with("LET_NOTE_MIA_"))
	assert_eq(a.request, b.request, "same draws: only the note text changes")


func test_morning_note_is_shorter_on_hint_days() -> void:
	var events := [
		{"type": "matured", "key": "jam|apple_1|-"}, {"type": "grown", "bed": 0, "crop": "cucumber"},
		{"type": "tree_refilled", "tree": 0, "tree_type": "apple"}, {"type": "order_new", "order": {"npc": "baker"}},
		{"type": "energy", "stars": 1, "energy": 12}, {"type": "day", "day": 95}, {"type": "weather", "weather": "rainy"},
	]
	assert_eq(Farewell.morning_events(events, 50), events, "other days: unchanged")
	var short := Farewell.morning_events(events, 95)
	var types: Array = short.map(func(e: Dictionary) -> String: return String(e.type))
	assert_eq(types, ["matured", "grown", "day", "weather"])
	var s := State.new_game(1)
	assert_true(MorningText.lines(short, s).size() < MorningText.lines(events, s).size(), "fewer lines")
