extends "res://tests/_runner/test_case.gd"
## MG-PRESS: judge and star helpers.


func test_judge_windows() -> void:
	assert_eq(PressRules.judge(0.0), "perfect")
	assert_eq(PressRules.judge(80.0), "perfect")
	assert_eq(PressRules.judge(-80.0), "perfect")
	assert_eq(PressRules.judge(80.1), "good")
	assert_eq(PressRules.judge(-160.0), "good")
	assert_eq(PressRules.judge(160.1), "miss")
	assert_eq(PressRules.judge(-400.0), "miss")


func test_stars() -> void:
	assert_eq(PressRules.stars_for({"perfect": 17, "good": 3, "miss": 4}), 3)  # 70.8%
	assert_eq(PressRules.stars_for({"perfect": 16, "good": 0, "miss": 8}), 2)  # 66.7% perfect, 66.7% hit
	assert_eq(PressRules.stars_for({"perfect": 5, "good": 10, "miss": 9}), 2)  # 62.5% hit
	assert_eq(PressRules.stars_for({"perfect": 4, "good": 10, "miss": 10}), 1)  # 58% hit
	assert_eq(PressRules.stars_for({"perfect": 0, "good": 0, "miss": 24}), 1)
	assert_eq(PressRules.stars_for({}), 1)


func test_juice() -> void:
	assert_true(PressRules.juice_for("perfect") > PressRules.juice_for("good"))
	assert_eq(PressRules.juice_for("miss"), 0.0)
