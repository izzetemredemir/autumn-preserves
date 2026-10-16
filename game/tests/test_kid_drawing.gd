extends "res://tests/_runner/test_case.gd"
## POLISH-LETTERS: procedural child's drawing in letters (KidDrawing, spec §7.6).

const SUBJECTS := [
	{"kind": "reply", "kid": "mia", "care": true,
		"items": [{"vessel": "jam_jar", "fill": ["a22512", "c94d2e", "e19064"], "lid": "9b8039", "label": "dbcc83"}]},
	{"kind": "reply", "kid": "leo", "care": false,
		"items": [{"vessel": "pickle_jar", "fill": ["53612e", "747c37", "b7b768"], "lid": "62272c", "label": "f2d9c5"},
			{"vessel": "bottle", "fill": ["83571e", "b66813", "e5bd7f"], "lid": "c94d2e", "label": "b9a697"}]},
	{"kind": "reply", "kid": "mia", "care": true,
		"items": [{"vessel": "pie", "fill": ["62272c", "a22512", "c94d2e"], "lid": "e5bd7f", "label": "e5bd7f"},
			{"vessel": "bread", "fill": ["83571e", "c58845", "e5bd7f"], "lid": "9b8039", "label": "e5bd7f"}]},
	{"kind": "request", "kid": "mia", "items": []},
	{"kind": "reply", "kid": "leo", "items": []},
]


func _requests() -> Array:
	return [
		{"kind": "request", "kid": "mia", "items": [KidDrawing.wish("pickle_jar", "sweet"), KidDrawing.wish("jam_jar", "")]},
		{"kind": "request", "kid": "leo", "items": [KidDrawing.wish("bottle", "spicy"), KidDrawing.wish("pie", "salty"),
			KidDrawing.wish("bread", "earthy")]},
	]


func _all_subjects() -> Array:
	return SUBJECTS + _requests()


func test_same_seed_same_image() -> void:
	for subject in _all_subjects():
		for sd in [1, 7, 4242, Hash.fnv1a31("3|mia"), Hash.fnv1a31("12|leo")]:
			var a := KidDrawing.render(sd, subject)
			var b := KidDrawing.render(sd, subject.duplicate(true))
			assert_eq(a.get_data(), b.get_data(), "seed %d %s" % [sd, subject.kind])


func test_size_is_48_and_opaque_palette_only() -> void:
	var palette := {}
	for hex in JarIcon.PALETTE:
		palette[Color(String(hex)).to_html(false)] = true
	for subject in _all_subjects():
		for sd in range(1, 41):
			var img := KidDrawing.render(sd * 7919, subject)
			assert_eq(img.get_size(), Vector2i(48, 48))
			assert_eq(img.get_format(), Image.FORMAT_RGBA8)
			var bad := 0
			for y in 48:
				for x in 48:
					var c := img.get_pixel(x, y)
					if c.a8 != 255 or not palette.has(c.to_html(false)):
						bad += 1
			assert_eq(bad, 0, "off-palette or see-through pixels, seed %d %s" % [sd * 7919, subject.kind])


func test_seeds_vary_the_drawing() -> void:
	var seen := {}
	for sd in range(1, 21):
		seen[KidDrawing.render(sd, SUBJECTS[0]).get_data()] = true
	assert_true(seen.size() >= 18, "20 seeds gave %d different drawings" % seen.size())


func test_reply_draws_the_received_jar_colours() -> void:
	var subject: Dictionary = SUBJECTS[0]
	for sd in range(1, 21):
		var img := KidDrawing.render(sd, subject)
		assert_true(_count(img, "c94d2e") > 10, "jar fill colour shows, seed %d" % sd)
		assert_true(_count(img, "9b8039") >= 4, "lid colour shows, seed %d" % sd)
		assert_true(_count(img, KidDrawing.GRANNY_HAIR) >= 5, "Granny's grey hair shows, seed %d" % sd)


func test_request_draws_the_wish_and_the_child() -> void:
	var subject: Dictionary = _requests()[1]
	for sd in range(1, 21):
		var img := KidDrawing.render(sd, subject)
		assert_true(_count(img, KidDrawing.BUBBLE) > 30, "thought bubble, seed %d" % sd)
		assert_true(_count(img, "b66813") > 3, "spicy wish colour, seed %d" % sd)
		assert_true(_count(img, KidDrawing.KIDS.leo.hair) >= 5, "Leo's hair, seed %d" % sd)


func test_wish_maps_tastes_and_unknown_vessels() -> void:
	assert_eq(KidDrawing.wish("pie", "sweet").vessel, "pie")
	assert_eq(KidDrawing.wish("cauldron", "").vessel, "jam_jar")
	assert_eq(KidDrawing.wish("jam_jar", "sour").fill, KidDrawing.TASTE_FILL.sour)
	assert_eq(KidDrawing.wish("jam_jar", "").fill, KidDrawing.PLAIN_FILL)


func _count(img: Image, hex: String) -> int:
	var want := Color(hex)
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).is_equal_approx(want):
				n += 1
	return n
