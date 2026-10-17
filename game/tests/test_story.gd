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
