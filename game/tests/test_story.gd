extends "res://tests/_runner/test_case.gd"
## STORY-03: story P.S. lines by letter index, the neighbours' Teo lines, Teo's letter flag (docs/story.md §4.4-4.7).


func test_parlor_objects_seen_once() -> void:
	var s := {"flags": {}}
	assert_false(Story.seen(s, "teo"))
	assert_true(Story.mark_seen(s, "teo"))
	assert_false(Story.mark_seen(s, "teo"), "first look only")
	assert_false(Story.mark_seen(s, "nope"), "unknown ids are ignored")
	assert_true(Story.seen(s, "teo"))
	assert_eq(Story.flags(s).seen, ["teo"])


func test_parlor_jar_fills_after_first_jar() -> void:
	var s := {"flags": {}, "pantry": {"items": []}}
	assert_false(Story.jar_filled(s))
	assert_eq(Story.object_key(s, "jar"), "STORY_OBJ_JAR")
	s.pantry.items.append({"item": {}})
	assert_true(Story.jar_filled(s))
	assert_eq(Story.object_key(s, "jar"), "STORY_OBJ_JAR_FILLED")
	s.pantry.items.clear()
	assert_true(Story.jar_filled(s), "stays filled")
	assert_eq(Story.object_key(s, "teo"), "STORY_OBJ_TEO")


func _kid_letter(s: Dictionary, kid: String) -> Dictionary:
	var r := Seeds.rng(int(s.save_seed), "letters", int(s.day))
	return Letters.make_request(s, kid, r)


func test_story_ps_follow_the_letter_index_and_the_writer() -> void:
	var s := State.new_game(5)
	s.day = 8
	assert_eq(int(_kid_letter(s, "mia").get("ps_story", 0)), 0, "line 1 is Leo's: Mia's letter has none")
	var got: Array = []
	for kid in ["leo", "mia", "leo", "mia", "leo", "mia"]:
		got.append(int(_kid_letter(s, kid).get("ps_story", 0)))
	assert_eq(got, [1, 2, 3, 4, 0, 0])


func test_story_ps_does_not_change_the_request_draw() -> void:
	for sd in [1, 2, 3, 99]:
		var a := State.new_game(sd)
		var b := State.new_game(sd)
		a.day = 8
		b.day = 8
		Story.flags(b)["ps_next"] = 99  # no story lines at all
		var la := _kid_letter(a, "leo")
		var lb := _kid_letter(b, "leo")
		assert_eq(la.request, lb.request, "seed %d" % sd)
		assert_eq(la.note, lb.note)


func test_neighbour_lines_once_at_two_hearts_and_rosie_on_festival_day() -> void:
	var s := State.new_game(1)
	assert_eq(Story.npc_line_due(s, "vintner", 1, false), "")
	assert_eq(Story.npc_line_due(s, "vintner", 2, false), "STORY_NPC_VINTNER")
	Story.mark_npc_said(s, "vintner")
	assert_eq(Story.npc_line_due(s, "vintner", 5, false), "", "once")
	assert_eq(Story.npc_line_due(s, "baker", 5, false), "", "Rosie waits for the festival")
	assert_eq(Story.npc_line_due(s, "baker", 0, true), "STORY_NPC_BAKER")
	assert_eq(Story.npc_line_due(s, "librarian", 3, false), "STORY_NPC_LIBRARIAN")


func test_teo_letter_opens_with_the_first_family_recipe_once() -> void:
	var s := State.new_game(1)
	s.erase("flags")  # an old save
	assert_false(Story.teo_letter_open(s))
	assert_false(Story.teo_letter_new(s))
	Letters.ensure(s).unlocked_recipes.append("pepper_relish")
	assert_true(Story.teo_letter_open(s))
	assert_true(Story.teo_letter_new(s))
	assert_false(Story.teo_letter_new(s), "shown once")
	assert_true(Story.teo_letter_open(s), "still readable from the back cover")


# ---------------------------------------------------------------- STORY-04: Teo's knife

func _knife_map(sd: int, day: int, s: Dictionary) -> Dictionary:
	var m := WildGen.generate(sd, day, "forest", "sunny", s.varieties)
	SpeciesGen.add_pickups(m, sd, day)
	return m


func _knife_state(sd: int, day: int) -> Dictionary:
	var s := State.new_game(sd)
	VarietyGen.ensure_types(s.varieties, sd)
	s.day = day
	SpeciesGen.sync(s)
	return s


func test_knife_due_from_day_2_once_per_save() -> void:
	var s := State.new_game(5)
	s.day = 1
	assert_false(Story.knife_due(s), "not on day 1")
	s.day = 2
	assert_true(Story.knife_due(s), "from day 2")
	s.flags.erase("story")  # an old save without the flag
	assert_false(Story.knife_found(s))
	assert_true(Story.mark_knife_found(s))
	assert_false(Story.mark_knife_found(s), "only once")
	assert_false(Story.knife_due(s))
	assert_true("knife" in Story.OBJECTS and Story.mark_seen(s, "knife"), "the 8th memory can be seen")
	assert_eq(Story.object_key(s, "knife"), "STORY_OBJ_KNIFE")


func test_knife_cell_adds_no_draw_and_is_safe() -> void:
	var cases: Array = [[1, 14], [452, 14], [24, 14], [7, 2], [99, 20]]
	for i in 30:
		cases.append([500 + i * 37, 2 + i % 19])
	for c in cases:
		var s := _knife_state(c[0], c[1])
		var m := _knife_map(c[0], c[1], s)
		var before := var_to_str(m)
		var cell := Story.knife_cell(m)
		assert_eq(var_to_str(m), before, "the map is untouched (seed %d)" % c[0])
		assert_eq(Story.knife_cell(m), cell, "deterministic")
		assert_true(cell.x >= 0, "a cell exists (seed %d day %d)" % c)
		if cell.x < 0:
			continue
		assert_true(WildGen.is_walkable(m, cell), "walkable")
		assert_eq(int(SpeciesGen.reach_map(m)[cell.y * int(m.w) + cell.x]), 1, "reachable")
		for key in ["decor_trees", "fruit_trees", "pickups"]:
			for t in m[key]:
				assert_ne(Vector2i(int(t.x), int(t.y)), cell, "off every tree and pickup")
		for e: Dictionary in ForestSurprises.plan(m, c[0], c[1], s.varieties):
			assert_ne(Vector2i(int(e.x), int(e.y)), cell, "not on a surprise")


func test_knife_leaves_the_pickup_lists_a_prefix() -> void:
	for c in [[1, 14], [452, 14], [24, 14]]:
		var s := _knife_state(c[0], c[1])
		var plain := WildGen.generate(c[0], c[1], "forest", "sunny", s.varieties)
		var n_plain := (plain.pickups as Array).size()
		SpeciesGen.add_pickups(plain, c[0], c[1])
		var picks := var_to_str(plain.pickups)
		var plan_before := var_to_str(ForestSurprises.plan(plain, c[0], c[1], s.varieties))
		Story.knife_cell(plain)
		assert_eq(var_to_str(plain.pickups), picks, "wild_gen + species lists unchanged (seed %d)" % c[0])
		assert_eq(var_to_str(ForestSurprises.plan(plain, c[0], c[1], s.varieties)), plan_before, "surprises unchanged")
		var again := WildGen.generate(c[0], c[1], "forest", "sunny", s.varieties)
		assert_eq(var_to_str((plain.pickups as Array).slice(0, n_plain)), var_to_str(again.pickups), "WildGen first")
	var fs := FestivalFacts.load_save()
	if not fs.is_empty():
		VarietyGen.ensure_types(fs.varieties, int(fs.save_seed))
		var m := _knife_map(int(fs.save_seed), int(fs.day), fs)
		var cell := Story.knife_cell(m)
		assert_true(cell.x >= 0, "festival forest has a spot")
		assert_true(WildGen.is_walkable(m, cell), "and it is walkable")


func test_knife_only_in_the_forest() -> void:
	var s := _knife_state(3, 5)
	assert_eq(Story.knife_cell(WildGen.generate(3, 5, "vineyard", "sunny", s.varieties)).x, -1)
