extends "res://tests/_runner/test_case.gd"
## FIRST-60: the world-grow overlay's rules and timing, the intro timeline, and the title painting's life
## (deterministic, whole pixels, on the painting's river and peaks).

const Beats := preload("res://ui/premise/intro_beats.gd")


func test_grow_plays_on_the_first_visit_of_a_save_even_when_the_setting_is_off() -> void:
	assert_true(WorldGrow.is_due({"day": 3, "flags": {"tutorial": 0}}, false), "never played on this save")
	assert_true(WorldGrow.is_due({"day": 1}, false), "old save without flags")


func test_grow_plays_once_a_day_while_the_setting_is_on() -> void:
	var s := {"day": 4, "flags": {}}
	WorldGrow.mark(s)
	assert_eq(int(s.flags.wild_grow_day), 4)
	assert_false(WorldGrow.is_due(s, true), "already played today")
	s.day = 5
	assert_true(WorldGrow.is_due(s, true), "a new day")
	assert_false(WorldGrow.is_due(s, false), "setting off after the first visit")


func test_mark_makes_flags_when_missing() -> void:
	var s := {"day": 2}
	WorldGrow.mark(s)
	assert_eq(int(s.flags.wild_grow_day), 2)


func test_grow_timing_fits_three_to_four_seconds() -> void:
	assert_true(WorldGrow.duration() >= 3.0 and WorldGrow.duration() <= 4.0, "%.2f s" % WorldGrow.duration())
	assert_near(WorldGrow.view_time(0.0), 0.0)
	var pickups_done := GrowView.start(GrowView.PHASES.size() - 1)
	assert_near(WorldGrow.view_time(WorldGrow.PLAY_SEC), pickups_done)
	assert_near(WorldGrow.view_time(99.0), pickups_done, 0.0001, "held at the end of the pickups")
	assert_eq(WorldGrow.level_at(0.0), 16)
	assert_eq(WorldGrow.level_at(WorldGrow.PLAY_SEC + WorldGrow.HOLD_SEC), 16)
	assert_eq(WorldGrow.level_at(WorldGrow.duration()), 0)


func test_short_form_is_two_seconds_and_first_entry_is_remembered() -> void:
	assert_near(WorldGrow.duration(true), 2.0, 0.001)
	assert_eq(WorldGrow.level_at(WorldGrow.duration(true), WorldGrow.SHORT_PLAY, WorldGrow.SHORT_HOLD, WorldGrow.SHORT_FADE), 0)
	assert_eq(WorldGrow.line_at(0.0), 0, "Granny's first line")
	assert_eq(WorldGrow.line_at(WorldGrow.PLAY_SEC), 5, "the last line once the forest is ready")
	var last := 0
	for k in 40:
		var l := WorldGrow.line_at(WorldGrow.PLAY_SEC * k / 40.0)
		assert_true(l >= last and l <= 4, "lines advance one phase at a time")
		last = l
	var s := {"day": 1}
	assert_true(WorldGrow.is_first(s), "old saves without the flag count as first")
	WorldGrow.mark(s)
	assert_false(WorldGrow.is_first(s))


func test_grow_map_fits_the_screen() -> void:
	var rules: Dictionary = Data.rules().wild
	var w := int(rules.w)
	var h := int(rules.h)
	var ts := WorldGrow.tile_px(w, h, Vector2i(480, 270))
	assert_true(ts >= 6, "tiles of %d px" % ts)
	assert_true(w * ts + 2 * WorldGrow.FRAME_PX <= 480 and h * ts + 2 * WorldGrow.FRAME_PX + 44 <= 270, "map, frame and rows fit")


func test_intro_lasts_about_twelve_seconds_in_three_beats() -> void:
	assert_true(Beats.total() >= 10.0 and Beats.total() <= 14.0, "%.1f s" % Beats.total())
	assert_true(Beats.count() == 3)
	assert_eq(String(Beats.BEATS[Beats.count() - 1][0]), "garden", "ends on the garden")


func test_intro_beats_dither_over_each_other() -> void:
	for i in Beats.count():
		var s := Beats.start(i)
		assert_eq(Beats.index_at(s + 0.01), i)
		assert_true(Beats.shown(i, s), "beat %d shows from its start" % i)
		assert_eq(Beats.level(i, s), 0, "beat %d starts hidden" % i)
		assert_eq(Beats.level(i, s + Beats.FADE), 16, "beat %d whole after the fade" % i)
		if i + 1 < Beats.count():
			assert_true(Beats.shown(i, Beats.start(i + 1) + Beats.FADE * 0.5), "beat %d stays under the next one's fade" % i)
			assert_false(Beats.shown(i, Beats.start(i + 1) + Beats.FADE), "beat %d gone once covered" % i)
	assert_eq(Beats.index_at(Beats.total() + 5.0), Beats.count() - 1)


func test_intro_lines_exist_in_english() -> void:
	var before := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	for b in Beats.BEATS:
		var key := String(b[1])
		assert_ne(String(TranslationServer.translate(key)), key, key)
	TranslationServer.set_locale(before)


func test_title_life_is_deterministic_and_whole_pixel() -> void:
	var a := TitleFx.new()
	var b := TitleFx.new()
	for t in [0.0, 3.7, 12.25]:
		for i in a.get("_back").size():
			assert_eq(TitleFx.leaf_pos(a.get("_back")[i], t), TitleFx.leaf_pos(b.get("_back")[i], t))
		for i in TitleFx.FLOCK.size():
			assert_eq(a.bird_pos(i, t), b.bird_pos(i, t))


func test_birds_fly_in_the_sky_band() -> void:
	var fx := TitleFx.new()
	var seen := 0
	for k in 220:
		var p := fx.bird_pos(0, k * 0.1)
		if p.x > -20:
			seen += 1
			assert_true(absi(p.y - fx.bird_y) <= 8, "bird at %s" % p)
	assert_true(seen > 100, "the flock crosses during the first 22 s")


func test_glints_sit_on_the_river_and_snow_on_the_peaks() -> void:
	var water := TitleFx.water_pixels()
	assert_true(water.size() > 100, "%d water pixels" % water.size())
	for p in water:
		assert_true(TitleFx.RIVER.has_point(p), "glint spot %s off the river" % p)
	var ridge := TitleFx.ridge()
	var peaks := 0
	for x in ridge.size():
		if ridge[x] >= 0:
			peaks += 1
			assert_true(ridge[x] >= TitleFx.MOUNTAIN_Y.x and ridge[x] < TitleFx.MOUNTAIN_Y.y)
	assert_true(peaks > 200, "%d ridge columns" % peaks)


func test_settings_defaults() -> void:
	assert_eq(GameSettings.DEFAULTS.game.show_grow, true, "the forest grows by default")
	assert_eq(GameSettings.DEFAULTS.game.intro_seen, false, "the first intro is watched")
