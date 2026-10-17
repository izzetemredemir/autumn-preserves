extends "res://tests/_runner/test_case.gd"
## FESTIVAL: res://dev/festival_save.json is the Harvest Festival day (a market day inside the harvest calendar, sunny,
## a rare tree near the forest entrance and a special place, everything unlocked, Mia's letter waiting, the pantry one
## jar short of 3 stars) and the six checklist steps tick when each system is used once.
## Rebuild the save: godot --headless --path game -s <absolute path>/tools/scripts/make_festival.gd

const MAX_DIST := 14.0
const UNLOCKS := ["press", "knead", "vineyard", "boots", "big_pot"]
const GAP := Vector2i(2, 3)


func _load() -> Dictionary:
	var s := FestivalFacts.load_save()
	assert_false(s.is_empty(), "festival save missing or not a festival save")
	return s


func test_the_save_is_a_temporary_festival_game() -> void:
	var s := _load()
	if s.is_empty():
		return
	assert_true(bool(s.flags.get("temp", false)), "loaded as a temporary game (never saved)")
	assert_true(TodoRules.is_festival(s))
	assert_eq(TodoRules.steps_for(s), TodoRules.FESTIVAL)
	assert_false(TodoRules.is_closed(TodoRules.bits_of(s)), "the note is open")


func test_market_day_in_the_harvest_calendar_and_sunny() -> void:
	var s := _load()
	if s.is_empty():
		return
	var day := int(s.day)
	assert_true(day >= Calendar.start_day(), "day %d is inside the harvest calendar" % day)
	assert_true(Market.is_market_day(day), "day %d is a market day" % day)
	assert_true(Market.can_open(s), "the stall has not opened yet")
	assert_eq(String(s.weather), "sunny")
	assert_eq(int(s.flags.festival.day), day)


func test_forest_has_the_rare_tree_near_the_entrance_and_a_special_place() -> void:
	var s := _load()
	if s.is_empty():
		return
	var f: Dictionary = s.flags.festival
	var map := WildGen.generate(int(s.save_seed), int(s.day), "forest", String(s.weather), s.varieties)
	assert_true(String(map.special.get("kind", "")) in ["mushroom_ring", "abandoned_orchard"], "special place")
	var tree := {}
	for t in map.fruit_trees:
		if int(t.id) == int(f.tree):
			tree = t
	assert_false(tree.is_empty(), "festival tree on today's map")
	if tree.is_empty():
		return
	assert_eq(String(tree.variety), String(f.rare))
	assert_eq(String(s.varieties[String(f.rare)].rarity), "rare")
	assert_true(Vector2(int(tree.x) - map.entrance.x, int(tree.y) - map.entrance.y).length() <= MAX_DIST, "near the entrance")
	assert_false(s.found_varieties.has(String(f.rare)), "the rare variety is still to be found")


func test_everything_is_unlocked_and_lived_in() -> void:
	var s := _load()
	if s.is_empty():
		return
	for id in UNLOCKS:
		assert_true(Economy.unlocked(s, id), "unlocked " + id)
	assert_eq(s.garden.beds.size(), 6)
	var ripe := 0
	var growing := 0
	for b in s.garden.beds:
		if String(b.crop) != "":
			if int(b.days_left) <= 0:
				ripe += 1
			else:
				growing += 1
	assert_true(ripe >= 2 and growing >= 1, "beds partly ripe (%d ripe, %d growing)" % [ripe, growing])
	for npc in ["grocer", "baker", "postman", "vintner", "librarian"]:
		assert_true(Economy.hearts(s, npc) >= 1, "hearts with " + npc)
	assert_true(int(s.coins) >= 100, "coins for the market")
	assert_true(Kitchen.unlocked_family(s).size() >= 2, "a few family recipes")
	assert_true(s.book.variants.size() >= 15, "a lived-in recipe book")
	for id in ["bottle", "jar", "sugar"]:
		assert_true(int(s.cupboard.get(id, 0)) > 0, "cupboard has " + id)
	var matured := 0
	var waiting := 0
	for e in s.pantry.items:
		if String(e.item.kind) == "product" and Data.recipes().get(State.item_type(e.item), {}).get("wait_days", 0) > 0:
			if int(e.item.wait_left) > 0:
				waiting += 1
			else:
				matured += 1
	assert_true(matured >= 3 and waiting >= 1, "matured %d and waiting %d jars" % [matured, waiting])


func test_mias_thank_you_letter_waits() -> void:
	var s := _load()
	if s.is_empty():
		return
	var letter := Letters.find_letter(s, int(s.flags.festival.letter))
	assert_false(letter.is_empty(), "Mia's letter")
	if letter.is_empty():
		return
	assert_eq(String(letter.from), "mia")
	assert_eq(String(letter.kind), "reply")
	assert_false(bool(letter.read))
	assert_eq(Letters.unread_count(s), 1)
	assert_false(Letters.parcel_for(s, int(letter.re)).get("keys", []).is_empty(), "a drawing of Granny's jars")


func test_pantry_is_one_jar_short_of_three_stars() -> void:
	var s := _load()
	if s.is_empty():
		return
	assert_eq(PantryRules.state_stars(s).rules, [true, true, false])
	var key := ProductGen.make_key("jam", [String(s.flags.festival.rare)], "")
	assert_true(PantryRules.place(s.pantry, State.product(key, 3, 0), GAP, 0), "the gap is free")
	assert_eq(int(PantryRules.state_stars(s).stars), 3)


func test_the_six_steps_tick_one_by_one() -> void:
	var s := _load()
	if s.is_empty():
		return
	var f: Dictionary = s.flags.festival
	var bits := TodoRules.evaluate(s, TodoRules.bits_of(s))
	assert_eq(TodoRules.current_step(s, bits), "f_shake", "nothing done at the start")
	# 1. the rare tree in today's forest
	var map := WildGen.generate(int(s.save_seed), int(s.day), "forest", String(s.weather), s.varieties)
	var shake := Forage.shake_tree(s, map, int(f.tree))
	assert_true(bool(shake.ok), "shake the rare tree")
	assert_true(Forage.bag_count(s) >= 3, "three fruit for a jam")
	Forage.empty_bag_to_inbox(s)
	bits = TodoRules.evaluate(s, bits)
	assert_true(TodoRules.is_done(bits, "f_shake"))
	# 2. a jam never made: the rare fruit
	var jam := Kitchen.cook(s, "jam", String(f.rare), "", "", 3)
	assert_true(bool(jam.ok) and bool(jam.is_new), "new jam of the rare fruit")
	bits = TodoRules.evaluate(s, bits)
	assert_true(TodoRules.is_done(bits, "f_jam"))
	assert_false(TodoRules.is_done(bits, "f_juice"))
	# 3. a juice from the inbox apples
	var apple := ""
	for it in s.inbox:
		if String(it.kind) == "fresh" and State.type_of_variety(String(it.variety)) == "apple" and int(it.count) >= 4:
			apple = String(it.variety)
	var juice := Kitchen.cook(s, "juice", apple, "", "", 2)
	assert_true(bool(juice.ok), "press a juice (%s)" % juice.get("reason", ""))
	bits = TodoRules.evaluate(s, bits)
	assert_true(TodoRules.is_done(bits, "f_juice"))
	# 4. the new jam into the room shelf's gap
	var idx: int = s.inbox.find(jam.item)
	var item := State.take(s, {"where": "inbox", "index": idx})
	assert_true(PantryRules.place(s.pantry, item, GAP, 0), "jam into the gap")
	bits = TodoRules.evaluate(s, bits)
	assert_true(TodoRules.is_done(bits, "f_pantry"))
	# 5. the market
	var items: Array = []
	for src in Market.sources(s):
		items.append(src.item)
	var sales := Market.run(s, Market.auto_stall(items, s.varieties))
	assert_false(sales.is_empty(), "something sold")
	bits = TodoRules.evaluate(s, bits)
	assert_true(TodoRules.is_done(bits, "f_market"))
	# 6. Mia's letter
	assert_eq(TodoRules.current_step(s, bits), "f_letter")
	Letters.mark_read(s, int(f.letter))
	bits = TodoRules.evaluate(s, bits)
	assert_true(TodoRules.day_finished(s, bits), "all six done")
	var facts := FestivalFacts.summary(s)
	assert_eq(int(facts.tiles), int(map.w) * int(map.h))
	assert_true(int(facts.trees) > 10, "trees counted")
	assert_true(int(facts.new_recipes) >= 1, "the new jam counts as a new recipe")
	assert_true(int(facts.coins) > 0, "coins from the market")


func test_the_festival_lasts_one_day() -> void:
	var s := _load()
	if s.is_empty():
		return
	assert_true(TodoRules.festival_today(s))
	s.day = int(s.day) + 1
	assert_false(TodoRules.festival_today(s), "after a night the festival is over")
	assert_eq(TodoRules.steps_for(s), [], "no checklist the day after")
	assert_eq(TodoRules.current_step(s, TodoRules.bits_of(s)), "")


func test_day_lists_are_unchanged_for_other_saves() -> void:
	var s := State.new_game(7)
	assert_false(TodoRules.is_festival(s))
	assert_eq(TodoRules.steps_for(s), TodoRules.DAYS[1])
	assert_eq(TodoRules.current_step(s, 0), "d1_mail")


func test_thousands() -> void:
	assert_eq(FestivalFacts.thousands(1440, ","), "1,440")
	assert_eq(FestivalFacts.thousands(452, "."), "452")
	assert_eq(FestivalFacts.thousands(1234567, "."), "1.234.567")
