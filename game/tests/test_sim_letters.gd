extends "res://tests/_runner/test_case.gd"
## P1-LETTERS: grandchild letters, requests, care parcels, replies and love (spec §6.7, §7.6).

const SEEDS := [1, 2, 3, 5, 7, 11, 42, 99, 314, 777, 1234, 4242, 90210, 123456, 2026, 31337, 65535, 1000003]


func _kid_product(s: Dictionary, kid: String, req: Dictionary) -> Dictionary:
	for c in Letters.kid_candidates(s, kid):
		if Letters.meets(req, String(c.recipe), c.taste):
			return State.product(String(c.key), 2, 0)
	return {}


func _any_product(s: Dictionary, recipe: String) -> Dictionary:
	for c in Orders.candidates(s, Orders.product_taste()):
		if String(c.recipe) == recipe:
			return State.product(String(c.key), 2, 0)
	return {}


func _letter(s: Dictionary, kid: String, request: Array) -> Dictionary:
	var l := Letters.ensure(s)
	var letter := {"id": int(l.next_id), "kind": "request", "from": kid, "day": int(s.day), "note": "LET_NOTE_MIA_1",
		"request": request, "done": false, "read": false}
	l.next_id = int(l.next_id) + 1
	l.inbox.append(letter)
	return letter


## Puts the items into the inbox (so pack can find them) and lays them left to right, top to bottom.
func _box(s: Dictionary, items: Array) -> Array:
	var entries: Array = []
	for i in items.size():
		s.inbox.append(items[i])
		entries.append({"item": items[i], "x": i % Letters.BOX_COLS, "y": floori(i / float(Letters.BOX_COLS)), "rot": 0})
	return entries


func test_letter_arrives_within_four_days_on_every_seed() -> void:
	for opened_on_day_one in [false, true]:
		for sd in SEEDS:
			var s := State.new_game(sd)
			if opened_on_day_one:
				Letters.ensure(s)  # the post office was visited before the first night
			var got := false
			for n in 4:
				for e in DayEnd.run(s):
					if e.type == "letter" and String(e.letter.kind) == "request":
						got = true
			assert_true(got, "seed %d (ensure on day 1: %s)" % [sd, opened_on_day_one])
			assert_eq(Letters.open_requests(s).size(), 1, "one letter so far, seed %d" % sd)


func test_old_save_without_letters_key_still_works() -> void:
	var s := State.new_game(5)
	s.erase("letters")
	DayEnd.run(s)
	assert_true(s.has("letters"))
	for k in ["inbox", "sent", "love", "unlocked_recipes"]:
		assert_has(s.letters, k)
	assert_eq(s.letters.love, {"leo": 0, "mia": 0})


func test_letters_come_every_three_to_four_days_while_answered() -> void:
	for sd in SEEDS:
		var s := State.new_game(sd)
		var days: Array = []
		for n in 40:
			for e in DayEnd.run(s):
				if e.type == "letter":
					days.append(int(s.day))
			for letter in Letters.open_requests(s):
				letter.done = true  # answered at once
		assert_true(days.size() >= 9, "seed %d: %d letters in 40 days" % [sd, days.size()])
		for i in range(1, days.size()):
			var g: int = days[i] - days[i - 1]
			assert_true(g >= 3 and g <= 4, "seed %d gap %d" % [sd, g])


func test_unanswered_letters_wait_and_alternate_kids() -> void:
	var s := State.new_game(7)
	for n in 30:
		DayEnd.run(s)
	var open := Letters.open_requests(s)
	assert_eq(open.size(), 2, "one waiting letter per kid, never more")
	assert_ne(open[0].from, open[1].from)


func test_requests_are_always_satisfiable_and_avoid_dislikes() -> void:
	for sd in SEEDS:
		var s := State.new_game(sd)
		for kid in Letters.kids():
			var cands := Letters.kid_candidates(s, kid)
			assert_false(cands.is_empty(), "candidates seed %d %s" % [sd, kid])
			for day in range(1, 41):
				var letter := Letters.make_request(s, kid, Seeds.rng(sd, "letters", day))
				var reqs: Array = letter.request
				assert_true(reqs.size() >= 2 and reqs.size() <= 3, "size seed %d" % sd)
				for req in reqs:
					assert_true(String(req.recipe) != "" or String(req.taste) != "", "not empty")
					assert_true(Letters.satisfiable(req, cands), "seed %d day %d %s %s" % [sd, day, kid, str(req)])
					var p := _kid_product(s, kid, req)
					assert_true(Letters.item_meets(kid, req, p, s.varieties), "real jar meets %s" % str(req))
					assert_false(Letters.dislikes(kid, String(p.key)))


func test_letters_are_deterministic() -> void:
	var a := State.new_game(31337)
	var b := State.new_game(31337)
	for n in 12:
		DayEnd.run(a)
		DayEnd.run(b)
	assert_eq(a.letters, b.letters)


func test_care_needs_request_straw_and_a_liked_surprise() -> void:
	var s := State.new_game(42)
	var req := [{"recipe": "pickle", "taste": ""}, {"recipe": "", "taste": "sweet"}]
	var pickle := _kid_product(s, "mia", req[0])
	var sweet := _kid_product(s, "mia", req[1])
	var surprise := _kid_product(s, "mia", {"recipe": "jam", "taste": ""})
	var shroom := _any_product(s, "brined_mushroom")
	assert_false(pickle.is_empty() or sweet.is_empty() or surprise.is_empty() or shroom.is_empty())
	assert_true(Letters.is_surprise("mia", surprise, s.varieties), "jam is sweet >= 4")
	assert_true(Letters.dislikes("mia", String(shroom.key)), "Mia dislikes mushrooms")
	assert_false(Letters.is_surprise("mia", shroom, s.varieties))
	var letter := _letter(s, "mia", req)
	# Request + surprise, gaps left empty: no care.
	var entries := _box(s, [pickle, sweet, surprise])
	var ev := Letters.evaluate(s, letter, entries)
	assert_eq(ev.ticks, [true, true])
	assert_true(ev.met and ev.surprise)
	assert_false(ev.straw)
	assert_false(ev.care)
	assert_eq(ev.hearts, 2)
	# Straw fills the three gaps: care.
	assert_eq(Letters.fill_straw(entries), 3)
	assert_true(Letters.fits_box(entries))
	ev = Letters.evaluate(s, letter, entries)
	assert_true(ev.care)
	assert_eq(ev.hearts, 4)
	# The surprise must be something Mia likes: mushrooms do not count, and the request alone is not a surprise.
	var no_surprise := [entries[0], entries[1], {"item": shroom, "x": 2, "y": 0, "rot": 0}, entries[3], entries[4], entries[5]]
	ev = Letters.evaluate(s, letter, no_surprise)
	assert_true(ev.met and ev.straw)
	assert_false(ev.surprise)
	assert_false(ev.care)
	# One jar counts once: pickle + jam meet the request, but then nothing is left over as a surprise.
	var two := [entries[0], entries[2], entries[3], entries[4], entries[5]]
	Letters.fill_straw(two)
	ev = Letters.evaluate(s, letter, two)
	assert_eq(ev.matched, 2)
	assert_true(ev.straw)
	assert_false(ev.surprise)
	assert_false(ev.care)
	# Missing a request item: no care even with straw and a surprise.
	var partial := [entries[1], entries[2], entries[3], entries[4], entries[5]]
	Letters.fill_straw(partial)
	ev = Letters.evaluate(s, letter, partial)
	assert_eq(ev.ticks, [false, true])
	assert_false(ev.met)
	assert_false(ev.care)
	assert_eq(ev.hearts, 1)


func test_disliked_jars_never_meet_a_request() -> void:
	var s := State.new_game(9)
	var shroom := _any_product(s, "brined_mushroom")
	assert_false(Letters.item_meets("mia", {"recipe": "", "taste": "salty"}, shroom, s.varieties))
	assert_true(Letters.item_meets("leo", {"recipe": "", "taste": "salty"}, shroom, s.varieties))
	var waiting := shroom.duplicate()
	waiting.wait_left = 2
	assert_false(Letters.item_meets("leo", {"recipe": "", "taste": "salty"}, waiting, s.varieties), "still waiting")


func test_pack_takes_jars_adds_love_and_reply_comes_two_days_later() -> void:
	var s := State.new_game(77)
	var req := [{"recipe": "jam", "taste": ""}, {"recipe": "", "taste": "sour"}]
	var letter := _letter(s, "mia", req)
	var a := _kid_product(s, "mia", req[0])
	var b := _kid_product(s, "mia", {"recipe": "pickle", "taste": "sour"})
	var entries := _box(s, [a])
	# a jar on a pantry shelf works too
	s.pantry.items.append({"item": b, "x": 0, "y": 4, "rot": 0})
	entries.append({"item": b, "x": 1, "y": 0, "rot": 0})
	var inbox_before: int = s.inbox.size()
	var res := Letters.pack(s, int(letter.id), entries)
	assert_true(res.ok, str(res))
	assert_eq(res.hearts, 2)
	assert_false(res.care)
	assert_eq(s.inbox.size(), inbox_before - 1)
	assert_eq(s.pantry.items.size(), 0)
	assert_true(letter.done)
	assert_eq(s.letters.love.mia, 2)
	assert_eq(Letters.pack(s, int(letter.id), entries).reason, "LET_NO_LETTER")
	var sent_day := int(s.day)
	DayEnd.run(s)
	assert_true(_reply_for(s, int(letter.id)).is_empty(), "no reply after one night")
	var got := false
	for e in DayEnd.run(s):
		if e.type == "letter" and String(e.letter.kind) == "reply":
			got = int(e.letter.re) == int(letter.id)
	assert_eq(int(s.day), sent_day + 2)
	assert_true(got, "reply event on the second night")
	var reply := _reply_for(s, int(letter.id))
	assert_eq(reply.from, "mia")
	assert_eq(reply.hearts, 2)
	assert_false(reply.read)
	assert_true(String(reply.note).begins_with("LET_REPLY_MIA_"))
	DayEnd.run(s)
	var replies := 0
	for l in s.letters.inbox:
		if String(l.kind) == "reply":
			replies += 1
	assert_eq(replies, 1, "only one reply per parcel")


func test_pack_validation() -> void:
	var s := State.new_game(3)
	var letter := _letter(s, "leo", [{"recipe": "pickle", "taste": ""}, {"recipe": "", "taste": "salty"}])
	var jar := _kid_product(s, "leo", {"recipe": "pickle", "taste": ""})
	assert_eq(Letters.pack(s, int(letter.id), []).reason, "LET_BOX_EMPTY")
	var straw_only: Array = []
	Letters.fill_straw(straw_only)
	assert_eq(straw_only.size(), 6)
	assert_eq(Letters.pack(s, int(letter.id), straw_only).reason, "LET_BOX_EMPTY")
	var outside := [{"item": jar, "x": 0, "y": 0, "rot": 0}]
	assert_eq(Letters.pack(s, int(letter.id), outside).reason, "UI_NOT_AVAILABLE", "jar is not in the inbox or pantry")
	s.inbox.append(jar)
	var twice := [{"item": jar, "x": 0, "y": 0, "rot": 0}, {"item": jar, "x": 1, "y": 0, "rot": 0}]
	assert_eq(Letters.pack(s, int(letter.id), twice).reason, "UI_NOT_AVAILABLE", "same jar twice")
	var off_box := [{"item": jar, "x": 3, "y": 0, "rot": 0}]
	assert_eq(Letters.pack(s, int(letter.id), off_box).reason, "LET_BOX_BAD")
	assert_eq(Letters.pack(s, 999, outside).reason, "LET_NO_LETTER")
	assert_false(letter.done, "failed packs change nothing")
	assert_eq(s.inbox.size(), 1)


func test_love_unlocks_family_recipes_at_three_six_ten() -> void:
	var s := State.new_game(11)
	var req := [{"recipe": "jam", "taste": ""}, {"recipe": "", "taste": "sweet"}, {"recipe": "", "taste": "sour"}]
	var letter := _letter(s, "mia", req)
	var items: Array = []
	for r in req:
		items.append(_kid_product(s, "mia", r))
	var res := Letters.pack(s, int(letter.id), _box(s, items))
	assert_true(res.ok, str(res))
	assert_eq(res.hearts, 3)
	assert_eq(s.letters.love.mia, 3)
	assert_eq(res.unlocked, [Letters.FAMILY_RECIPES.mia[0]])
	assert_eq(s.letters.unlocked_recipes, [Letters.FAMILY_RECIPES.mia[0]])
	# 3 + 2 hearts (no care): no new recipe; then care (+2 +2) crosses 6.
	var l2 := _letter(s, "mia", [{"recipe": "jam", "taste": ""}, {"recipe": "", "taste": "sour"}])
	res = Letters.pack(s, int(l2.id), _box(s, [_kid_product(s, "mia", {"recipe": "jam", "taste": ""}),
		_kid_product(s, "mia", {"recipe": "", "taste": "sour"})]))
	assert_eq(s.letters.love.mia, 5)
	assert_eq(res.unlocked, [])
	var l3 := _letter(s, "mia", [{"recipe": "jam", "taste": ""}, {"recipe": "", "taste": "sour"}])
	var e3 := _box(s, [_kid_product(s, "mia", {"recipe": "jam", "taste": ""}),
		_kid_product(s, "mia", {"recipe": "", "taste": "sour"}), _kid_product(s, "mia", {"recipe": "jam", "taste": ""})])
	Letters.fill_straw(e3)
	res = Letters.pack(s, int(l3.id), e3)
	assert_true(res.care, str(res))
	assert_eq(s.letters.love.mia, 9)
	assert_eq(res.unlocked, [Letters.FAMILY_RECIPES.mia[1]])
	assert_eq(s.letters.love.leo, 0, "love is per grandchild")
	# The reply carries the news.
	DayEnd.run(s)
	DayEnd.run(s)
	var reply := _reply_for(s, int(l3.id))
	assert_true(reply.care)
	assert_eq(reply.unlocked, [Letters.FAMILY_RECIPES.mia[1]])
	assert_eq(reply.care_note, "LET_REPLY_CARE_MIA")


func test_postman_hearts_make_letters_come_more_often() -> void:
	var s := State.new_game(1)
	var gaps := {}
	for d in range(1, 60):
		gaps[Letters.gap(s, Seeds.rng(1, "letters", d))] = true
	assert_eq(gaps.keys().size(), 2, "3 or 4 days")
	s.friendship.postman = 99
	for d in range(1, 60):
		assert_eq(Letters.gap(s, Seeds.rng(1, "letters", d)), 3)


func test_every_text_key_exists() -> void:
	var keys := {}
	var f := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > 0:
			keys[row[0]] = true
	for kid in Letters.kids():
		var k := String(kid).to_upper()
		for i in range(1, Letters.NOTE_COUNT + 1):
			assert_has(keys, "LET_NOTE_%s_%d" % [k, i])
		for i in range(1, Letters.REPLY_COUNT + 1):
			assert_has(keys, "LET_REPLY_%s_%d" % [k, i])
		assert_has(keys, "LET_REPLY_CARE_" + k)
		for rid in Letters.FAMILY_RECIPES[kid]:
			assert_has(keys, "LET_RECIPE_" + String(rid).to_upper())
		var group := String(Letters.kid_info(kid).dislikes_group)
		assert_has(keys, "LET_GROUP_" + group.to_upper())


func _reply_for(s: Dictionary, letter_id: int) -> Dictionary:
	for l in s.letters.inbox:
		if String(l.kind) == "reply" and int(l.re) == letter_id:
			return l
	return {}
