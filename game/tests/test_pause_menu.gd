extends "res://tests/_runner/test_case.gd"
## PAUSE-MENU: the menu's gear is palette pixel art (no font glyph, no partial alpha), Quit hides on web, and the menu
## belongs to the play scenes only (never the title, the farewell or the Forest Lab screen).


func test_gear_is_on_palette_with_hard_alpha() -> void:
	var hexes := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../tools/palettes/autumn.hex"))
	var palette := {}
	for h in hexes.split("\n", false):
		palette[h.strip_edges().to_lower()] = true
	assert_true(palette.size() >= 16, "palette read")
	for state in PauseMenu.GEAR_COLORS:
		var img := PauseMenu.gear(state).get_image()
		assert_eq(img.get_size(), Vector2i(16, 16))
		var solid := 0
		for y in 16:
			for x in 16:
				var c := img.get_pixel(x, y)
				if c.a == 0.0:
					continue
				solid += 1
				assert_eq(c.a, 1.0, "%s (%d,%d) is fully opaque" % [state, x, y])
				assert_true(palette.has(c.to_html(false)), "%s (%d,%d) %s is a palette colour" % [state, x, y, c.to_html(false)])
		assert_true(solid > 100, "%s gear has a body (%d px)" % [state, solid])


func test_quit_hidden_on_web() -> void:
	PauseMenu.web_override = 1
	assert_false(PauseMenu.quit_allowed(), "web build: no Quit")
	PauseMenu.web_override = 0
	assert_true(PauseMenu.quit_allowed(), "desktop build: Quit")
	PauseMenu.web_override = -1


func test_menu_only_in_play_scenes() -> void:
	for id in ["garden", "wild", "kitchen", "pantry", "town", "market"]:
		assert_has(PauseMenu.PLAY_SCENES, id)
	for id in ["", "title", "farewell", "seed_lab"]:
		assert_false(id in PauseMenu.PLAY_SCENES, "no menu in '%s'" % id)
