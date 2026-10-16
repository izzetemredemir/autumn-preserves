extends "res://tests/_runner/test_case.gd"
## MG-STIR: pure scoring and needle helpers.


func test_star_thresholds() -> void:
	assert_eq(StirScoring.stars_for_bar(0.0), 1)
	assert_eq(StirScoring.stars_for_bar(0.499), 1)
	assert_eq(StirScoring.stars_for_bar(0.5), 2)
	assert_eq(StirScoring.stars_for_bar(0.849), 2)
	assert_eq(StirScoring.stars_for_bar(0.85), 3)
	assert_eq(StirScoring.stars_for_bar(1.0), 3)


func test_needle_direction() -> void:
	assert_true(StirScoring.needle_step(0.5, 0.0, 0.0, 1.0) > 0.5, "idle rises")
	assert_true(StirScoring.needle_step(0.5, 1.0, 0.0, 1.0) < 0.5, "fast stir falls")
	assert_eq(StirScoring.needle_step(0.99, 0.0, 0.5, 1.0), 1.0)
	assert_eq(StirScoring.needle_step(0.01, 1.5, -0.5, 1.0), 0.0)


func test_band() -> void:
	assert_true(StirScoring.in_band(0.5))
	assert_false(StirScoring.in_band(0.2))
	assert_false(StirScoring.in_band(0.9))
