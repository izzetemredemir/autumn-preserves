extends "res://tests/_runner/test_case.gd"
## ENDING: the visit on day 30 (docs/story.md §6): trigger, once per save, old saves, Tonty's note, Nora's second
## letter, the P.S. lines by day, the week of grandchildren in the garden. No RNG draw changes.

const SEEDS := [1, 7, 42, 2026]


func _keys(path := "res://i18n/strings.csv") -> Dictionary:
	var keys := {}
	var f := FileAccess.open(path, FileAccess.READ)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > 1:
			keys[row[0]] = row[1]
	return keys


## Every line's key exists in EN and TR and its template takes exactly its args.
func _check_lines(lines: Array, what: String) -> void:
	for path in ["res://i18n/strings.csv", "res://i18n/strings_tr.csv"]:
		var keys := _keys(path)
		for l in lines:
			var key := String(l.key)
			assert_has(keys, key, "%s (%s)" % [what, path])
			var tpl := String(keys.get(key, ""))
			var holes := tpl.count("%s") + tpl.count("%d")
			assert_eq(holes, (l.args as Array).size(), "%s: %s placeholders" % [what, key])
			if holes == (l.args as Array).size() and holes > 0:
				assert_false((tpl % l.args).contains("%"), "%s: %s formats" % [what, key])


func test_the_visit_is_due_only_on_day_30_and_once() -> void:
	var s := State.new_game(7)
	for day in range(1, 60):
		s.day = day
		assert_eq(FinaleRules.due(s), day == FinaleRules.DAY, "day %d" % day)
	s.day = FinaleRules.DAY
	FinaleRules.mark_seen(s)
	assert_false(FinaleRules.due(s), "never twice")
	assert_true(FinaleRules.visited(s), "the title badge")


func test_old_saves_past_day_30_just_go_on() -> void:
	var s := State.new_game(42)
	s.erase("flags")  # a save from before flags.story
	s.day = 41
	assert_false(FinaleRules.due(s))
	assert_false(FinaleRules.seen(s))
	assert_false(FinaleRules.visited(s), "no badge without the visit")
	assert_false(FinaleRules.kids_visiting(s))
	s.day = FinaleRules.DAY
	assert_true(FinaleRules.due(s), "an old save on day 30 gets it")


func test_a_closed_or_memory_save_never_gets_the_visit() -> void:
	var s := State.new_game(1)
	s.day = FinaleRules.DAY
	s.flags["completed"] = true
	assert_false(FinaleRules.due(s))
	s.flags.erase("completed")
	s.flags["memory"] = true
	assert_false(FinaleRules.due(s))


func test_nights_reach_the_visit_day_and_the_farewell_is_unchanged() -> void:
	var s := State.new_game(2026)
	var due_days: Array = []
	while int(s.day) < Farewell.LAST_DAY:
		assert_eq(Farewell.night_kind(s), "normal", "night after day %d" % int(s.day))
		Farewell.night(s)
		if FinaleRules.due(s):
			due_days.append(int(s.day))
			FinaleRules.mark_seen(s)
	assert_eq(due_days, [FinaleRules.DAY], "the visit comes once, on the morning of day 30")
	assert_eq(Farewell.night_kind(s), "farewell", "day 99 still ends with the farewell")


func test_grandchildren_play_in_the_garden_for_a_week_after_the_visit() -> void:
	var s := State.new_game(7)
	s.day = FinaleRules.DAY
	FinaleRules.mark_seen(s)
	for day in range(25, 45):
		s.day = day
		var want := day > FinaleRules.DAY and day <= FinaleRules.DAY + FinaleRules.VISIT_DAYS
		assert_eq(FinaleRules.kids_visiting(s), want, "day %d" % day)


func test_note_is_built_from_the_save_with_fallbacks() -> void:
	for sd in SEEDS:
		var s := State.new_game(sd)
		s.day = FinaleRules.DAY
		s.pantry.items.clear()
		s.stats["jars_made"] = 0
		var lines := FinaleRules.note(s, "en")
		_check_lines(lines, "empty pantry seed %d" % sd)
		var keys: Array = lines.map(func(l: Dictionary) -> String: return String(l.key))
		assert_eq(keys, ["FINALE_NOTE_DEAR_TWO", "FINALE_NOTE_DAYS", "FAREWELL_LETTER_JARS_NONE",
			"FAREWELL_LETTER_TOP_NONE", "FAREWELL_LETTER_RARE_NONE", "FINALE_NOTE_TEO", "FINALE_NOTE_BOOTS",
			"FINALE_NOTE_SIGN"], "seed %d" % sd)
		assert_eq(lines[1].args, [30])
		assert_true(lines.size() <= 8, "a letter is at most 8 lines (story.md §2.3)")


func test_note_names_the_best_jar_and_the_rare_find() -> void:
	var s := State.new_game(42)
	s.day = FinaleRules.DAY
	var key := ""
	for c in Orders.candidates(s, Orders.product_taste()):
		key = String(c.key)
		break
	assert_ne(key, "", "a product to put on the shelf")
	s.pantry.items.clear()
	s.pantry.items.append({"item": {"kind": "product", "key": key, "q": 2}, "x": 0, "y": 0, "rot": 0})
	s.stats["jars_made"] = 1
	var lines := FinaleRules.note(s, "en")
	_check_lines(lines, "one jar")
	assert_eq(lines[2].key, "FAREWELL_LETTER_JARS_ONE", "one jar: the farewell's line")
	assert_eq(lines[3].key, "FINALE_NOTE_TOP")
	assert_eq(lines[3].args, [ProductGen.product_name(key, s.varieties, "en")])
	s.stats["jars_made"] = 12
	for id in s.varieties:
		if String(s.varieties[id].get("rarity", "")) != "common":
			s.found_varieties.append(id)
			break
	lines = FinaleRules.note(s, "en")
	_check_lines(lines, "full")
	assert_eq(lines[2].key, "FINALE_NOTE_JARS")
	assert_eq(lines[2].args, [12])
	assert_eq(lines[4].key, "FINALE_NOTE_RARE")
	var tr_lines := FinaleRules.note(s, "tr")
	assert_eq(tr_lines[3].args[0], ProductGen.product_name(key, s.varieties, "tr"), "Turkish: the plain jar name, no suffix")
	assert_eq(tr_lines.filter(func(l): return l.key == "FINALE_NOTE_KNIFE").size(), 0, "no knife line before the find")
	Story.mark_knife_found(s)
	var knife := FinaleRules.note(s, "en").map(func(l: Dictionary) -> String: return String(l.key))
	assert_eq(knife.find("FINALE_NOTE_KNIFE"), knife.find("FINALE_NOTE_TEO") + 1, "the knife line follows Teo's")
func test_nora_writes_again_on_day_10_once() -> void:
	for sd in SEEDS:
		var s := State.new_game(sd)
		var got: Array = []
		while int(s.day) < 40:
			for e in DayEnd.run(s):
				if e.type == "letter" and int(e.letter.id) == FinaleRules.NORA2_ID:
					got.append(int(s.day))
		assert_eq(got, [FinaleRules.NORA2_DAY], "seed %d" % sd)
		var l := Letters.find_letter(s, FinaleRules.NORA2_ID)
		assert_true(Letters.is_story(l))
		assert_eq(l.lines, FinaleRules.NORA2_LINES)
		_check_lines(l.lines.map(func(k: String) -> Dictionary: return {"key": k, "args": []}), "Nora's letter")


func test_nora_letter_reaches_an_older_save_before_the_visit_only() -> void:
	var s := State.new_game(1)
	s.day = 17
	assert_false(FinaleRules.add_nora_letter(s).is_empty(), "a save past day 10 gets it the next morning")
	assert_true(FinaleRules.add_nora_letter(s).is_empty(), "once")
	var late := State.new_game(1)
	late.day = FinaleRules.DAY + 3
	assert_true(FinaleRules.add_nora_letter(late).is_empty(), "never after the visit")


func test_visit_ps_lines_by_day() -> void:
	var s := State.new_game(7)
	assert_eq(FinaleRules.visit_ps(s, 19), 0, "not before day 20")
	assert_eq(FinaleRules.visit_ps(s, 20), 5)
	assert_eq(FinaleRules.visit_ps(s, 27), 5, "line 5 first, even late")
	var letter := {"from": "leo", "day": 21}
	FinaleRules.add_ps(s, letter)
	assert_eq(int(letter.get("ps_story", 0)), 5)
	assert_eq(FinaleRules.visit_ps(s, 22), 0, "line 5 only once; line 6 waits for day 26")
	assert_eq(FinaleRules.visit_ps(s, 26), 6)
	var taken := {"from": "mia", "day": 26, "ps_story": 2}
	FinaleRules.add_ps(s, taken)
	assert_eq(int(taken.ps_story), 2, "at most one P.S. per letter")
	assert_eq(FinaleRules.visit_ps(s, 30), 0, "nothing on or after the visit")
	_check_lines([{"key": "LET_PS_STORY_5", "args": []}, {"key": "LET_PS_STORY_6", "args": []}], "P.S.")


## The P.S. lines are picked by day: the letter stream (kid, request, note, gap) is the same as without them.
func test_ps_lines_do_not_change_the_letter_stream() -> void:
	for sd in SEEDS:
		var s := State.new_game(sd)
		var seen_ps: Array = []
		var stream: Array = []
		while int(s.day) < FinaleRules.DAY:
			for e in DayEnd.run(s):
				if e.type == "letter" and not Letters.is_story(e.letter):
					stream.append([int(s.day), String(e.letter.from), String(e.letter.get("note", ""))])
					var n := int(e.letter.get("ps_story", 0))
					if n >= 5:
						seen_ps.append(n)
			for letter in Letters.open_requests(s):
				letter.done = true
		var plain := State.new_game(sd)
		var plain_stream: Array = []
		while int(plain.day) < FinaleRules.DAY:
			plain.flags["story"] = {"visit_ps": [5, 6]}  # as if both lines were already written: none added
			for e in DayEnd.run(plain):
				if e.type == "letter" and not Letters.is_story(e.letter):
					plain_stream.append([int(plain.day), String(e.letter.from), String(e.letter.get("note", ""))])
			for letter in Letters.open_requests(plain):
				letter.done = true
		assert_eq(stream, plain_stream, "seed %d" % sd)
		assert_eq(seen_ps, [5, 6], "seed %d: both visit lines before day 30" % sd)


func test_strings_exist_in_both_languages() -> void:
	var lines: Array = []
	for k in ["FINALE_KNOCK", "FINALE_SNOW_LINE", "FINALE_THANKS", "UI_DEV_DAY29", "UI_DEV_DAY29_DONE"]:
		lines.append({"key": k, "args": []})
	lines.append({"key": "UI_VISITED", "args": [30]})
	_check_lines(lines, "finale strings")
