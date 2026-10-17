extends "res://tests/_runner/test_case.gd"
## MG-PRESS: judge and star helpers.


func test_judge_windows() -> void:
	assert_eq(PressRules.judge(0.0), "perfect")
	assert_eq(PressRules.judge(100.0), "perfect")
	assert_eq(PressRules.judge(-100.0), "perfect")
	assert_eq(PressRules.judge(100.1), "good")
	assert_eq(PressRules.judge(-200.0), "good")
	assert_eq(PressRules.judge(200.1), "miss")
	assert_eq(PressRules.judge(-400.0), "miss")


func test_stars() -> void:
	assert_eq(PressRules.stars_for({"perfect": 5, "good": 2, "miss": 1}), 3)  # 62.5% perfect
	assert_eq(PressRules.stars_for({"perfect": 4, "good": 0, "miss": 4}), 2)  # 50% perfect, 50% hit
	assert_eq(PressRules.stars_for({"perfect": 1, "good": 3, "miss": 4}), 2)  # 50% hit
	assert_eq(PressRules.stars_for({"perfect": 1, "good": 2, "miss": 5}), 1)  # 37.5% hit
	assert_eq(PressRules.stars_for({"perfect": 0, "good": 0, "miss": 8}), 1)
	assert_eq(PressRules.stars_for({}), 1)


func test_juice() -> void:
	assert_true(PressRules.juice_for("perfect") > PressRules.juice_for("good"))
	assert_eq(PressRules.juice_for("miss"), 0.0)
