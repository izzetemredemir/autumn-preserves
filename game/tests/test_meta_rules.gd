extends "res://tests/_runner/test_case.gd"
## GD-META pure helpers: To-Do step rules, seed field, morning summary lines, dev items.


func test_todo_day1_steps_tick_from_state() -> void:
	var s := State.new_game(7)
	assert_eq(TodoRules.evaluate(s, 0), 0, "fresh game: nothing done")
	assert_eq(TodoRules.current_step(s, 0), "d1_shake")
	for t in s.garden.trees:
		if t.type == "apple":
			t.fruit = false
	s.book.variants["jam|apple_1|-"] = {"best_q": 2}
	var bits := TodoRules.evaluate(s, 0)
	assert_true(TodoRules.is_done(bits, "d1_shake"))
	assert_true(TodoRules.is_done(bits, "d1_jam"))
	assert_false(TodoRules.is_done(bits, "d1_pantry"))
	assert_eq(TodoRules.current_step(s, bits), "d1_pantry")
	s.pantry.items.append({"item": State.product("jam|apple_1|-", 2, 0), "x": 0, "y": 0, "rot": 0})
	s.stats.orders_done = 1
	bits = TodoRules.evaluate(s, bits)
	assert_eq(TodoRules.current_step(s, bits), "d1_bed")


func test_todo_day2_steps_and_bits_stay_on() -> void:
	var s := State.new_game(7)
	s.day = 2.0  # JSON-loaded saves carry floats
	var bits := TodoRules.evaluate(s, 0, {"scene": "wild"})
	assert_true(TodoRules.is_done(bits, "d2_forest"))
	s.bag.append(State.fresh("chanterelle_1", 2, 2))
	bits = TodoRules.evaluate(s, bits, {"scene": "garden"})
	assert_true(TodoRules.is_done(bits, "d2_forest"), "bits never switch off")
	assert_true(TodoRules.is_done(bits, "d2_mushroom"))
	s.book.variants["brined_mushroom|chanterelle_1|-"] = {}
	bits = TodoRules.evaluate(s, bits, {"sold": true})
	assert_true(TodoRules.day_finished(s, bits))
	assert_eq(TodoRules.current_step(s, bits), "")


func test_todo_close_and_later_days() -> void:
	var bits := TodoRules.close(0)
	assert_true(TodoRules.is_closed(bits))
	assert_false(TodoRules.is_done(bits, "d1_shake"))
	assert_eq(TodoRules.steps_for_day(3), [])
	for step in TodoRules.BITS:
		assert_has(TodoRules.SCENE_OF, step)
		assert_ne(TodoRules.BITS[step], TodoRules.CLOSED_BIT)


## ONBOARD-GUIDE: every To-Do step has Granny's hint in English and Turkish, short enough for the compact bubble
## (m5x7 16 px inside GuideArrow.BUBBLE_W, at most GuideArrow.HINT_LINES lines).
func test_todo_hints_fit_the_bubble() -> void:
	for path in ["res://i18n/strings.csv", "res://i18n/strings_tr.csv"]:
		var texts := {}
		var f := FileAccess.open(path, FileAccess.READ)
		f.get_csv_line()
		while not f.eof_reached():
			var row := f.get_csv_line()
			if row.size() >= 2:
				texts[row[0]] = row[1]
		for step in TodoRules.BITS:
			var key := TodoRules.hint_key_of(step)
			assert_has(texts, key, "%s in %s" % [key, path])
			var para := TextParagraph.new()
			para.add_string(String(texts.get(key, "")), GuideArrow.HINT_FONT, GuideArrow.HINT_SIZE)
			para.width = GuideArrow.BUBBLE_W - 2 * GuideArrow.PAD.x
			assert_true(para.get_line_count() <= GuideArrow.HINT_LINES,
				"%s (%s) wraps to %d lines" % [key, path.get_file(), para.get_line_count()])


func test_seed_text() -> void:
	assert_eq(SeedText.parse(""), -1)
	assert_eq(SeedText.parse("  "), -1)
	assert_eq(SeedText.parse("1234"), 1234)
	assert_eq(SeedText.parse("granny"), SeedText.parse(" Granny "))
	assert_true(SeedText.parse("granny") >= 0)
	assert_true(SeedText.parse("99999999999") <= 0x7FFFFFFF)


func test_morning_quiet_night() -> void:
	var s := State.new_game(3)
	var lines := MorningText.lines([], s)
	assert_eq(lines.size(), 1)
	assert_eq(lines[0].key, "UI_NIGHT_QUIET")
	lines = MorningText.lines([{"type": "day", "day": 2}, {"type": "weather", "weather": "rainy"},
		{"type": "energy", "stars": 0, "energy": 80}], s)
	assert_eq(lines[0].key, "UI_NIGHT_QUIET")
	assert_eq(lines[1].key, "UI_NIGHT_WEATHER_RAINY")
	assert_eq(lines[2].key, "UI_NIGHT_ENERGY")
	assert_eq(lines[2].args, [80])


func test_morning_lines_from_night_events() -> void:
	var s := State.new_game(3)
	var events := DayEnd.run(s)
	for e in events:
		assert_true(e.has("type"))
	var lines := MorningText.lines(events, s)
	assert_true(lines.size() >= 2, "notable or quiet line + weather + energy")
	var crafted := [
		{"type": "grown", "bed": 0, "crop": "cucumber"},
		{"type": "tree_refilled", "tree": 0, "tree_type": "apple"},
		{"type": "order_new", "order": {"npc": "baker"}},
		{"type": "spoiled", "item": State.nut("walnut", 2), "where": "inbox"},
		{"type": "fertilizer", "made": 0, "fertilizer": 0},
	]
	lines = MorningText.lines(crafted, s)
	assert_eq(lines[0].key, "UI_NIGHT_GROWN")
	assert_eq(lines[0].args, ["cucumber"])
	assert_eq(lines[1].args, ["apple"])
	assert_eq(lines[2].args, ["Rosie"])
	assert_eq(lines[3].key, "UI_NIGHT_SPOILED")
	assert_eq(lines.size(), 4, "no fertilizer line when none was made")


func test_morning_merges_and_caps_lines() -> void:
	var s := State.new_game(1)
	var lines := MorningText.lines([{"type": "grown", "bed": 0, "crop": "cucumber"},
		{"type": "grown", "bed": 1, "crop": "cucumber"}], s)
	assert_eq(lines.size(), 1)
	assert_eq(lines[0].key, "UI_NIGHT_GROWN_MANY")
	assert_eq(lines[0].args, [2, "cucumber"])
	var events: Array = []
	for i in 9:
		events.append({"type": "order_new", "order": {"npc": "npc_%d" % i}})
	lines = MorningText.lines(events, s)
	assert_eq(lines.size(), MorningText.MAX_NOTABLE + 1)
	assert_eq(lines[MorningText.MAX_NOTABLE].key, "UI_NIGHT_MORE")
	assert_eq(lines[MorningText.MAX_NOTABLE].args, [3])


func test_dev_give_items() -> void:
	var s := State.new_game(11)
	var jars := int(s.cupboard.jar)
	var n := DevTools.give_items(s)
	assert_true(n > 0)
	assert_eq(int(s.cupboard.jar), jars + DevTools.ITEM_COUNT)
	assert_eq(int(s.cupboard.get("seed_cucumber", 0)), DevTools.SEED_COUNT)
	var types := {}
	for item in s.inbox:
		types[State.item_type(item)] = true
		assert_eq(int(item.count), DevTools.ITEM_COUNT)
	for t in Data.ids_up_to("ingredients", 0):
		assert_has(types, t)
	assert_false(types.has("grape"), "P1 ingredients stay out")
	assert_eq(DevTools.load_demo("res://dev/no_such_file.json"), {})
