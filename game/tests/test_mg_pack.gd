extends "res://tests/_runner/test_case.gd"
## MG-PACK: pure scoring helpers of pack_jar (spec 11.2).



func test_fill_ratio() -> void:
	assert_near(PackJarRules.fill_ratio(0), 0.0)
	assert_near(PackJarRules.fill_ratio(21), 0.5)
	assert_near(PackJarRules.fill_ratio(42), 1.0)
	assert_near(PackJarRules.fill_ratio(38), 38.0 / 42.0)


func test_stars_thresholds() -> void:
	assert_eq(PackJarRules.stars_for(0.9, true), 3)
	assert_eq(PackJarRules.stars_for(0.8999, true), 2)
	assert_eq(PackJarRules.stars_for(0.75, true), 2)
	assert_eq(PackJarRules.stars_for(0.7499, true), 1)
	assert_eq(PackJarRules.stars_for(0.0, true), 1)


func test_brine_penalty_floor_one() -> void:
	assert_eq(PackJarRules.stars_for(1.0, false), 2)
	assert_eq(PackJarRules.stars_for(0.8, false), 1)
	assert_eq(PackJarRules.stars_for(0.1, false), 1)


func test_brine_band() -> void:
	assert_true(PackJarRules.brine_in_band(7.0))
	assert_true(PackJarRules.brine_in_band(6.0))
	assert_true(PackJarRules.brine_in_band(8.0))
	assert_false(PackJarRules.brine_in_band(5.4))
	assert_false(PackJarRules.brine_in_band(0.0))


func test_piece_sizes() -> void:
	assert_eq(PackJarRules.piece_size("rings"), Vector2i(1, 1))
	assert_eq(PackJarRules.piece_size("slices"), Vector2i(1, 2))
	assert_eq(PackJarRules.piece_size("strips"), Vector2i(1, 3))
	assert_eq(PackJarRules.piece_size("caps"), Vector2i(2, 1))
	assert_eq(PackJarRules.piece_size("shreds"), Vector2i(1, 1))


func test_grid_counting_and_landing() -> void:
	var grid: Array = []
	for r in PackJarRules.ROWS:
		var row: Array = []
		row.resize(PackJarRules.COLS)
		row.fill(0)
		grid.append(row)
	grid[0][0] = 1
	grid[1][0] = 1
	grid[7][5] = 2  # above the line: not counted
	assert_eq(PackJarRules.count_below_line(grid), 2)
	var hs := PackJarRules.heights_of(grid)
	assert_eq(hs[0], 2)
	assert_eq(hs[5], 8)
	assert_eq(PackJarRules.landing_row(hs, 0, 2), 2)
	assert_eq(PackJarRules.landing_row(hs, 1, 2), 0)
