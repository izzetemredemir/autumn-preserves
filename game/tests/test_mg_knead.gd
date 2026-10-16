extends "res://tests/_runner/test_case.gd"
## MG-KNEAD: pure rhythm, trace and star helpers.


func test_judge_windows() -> void:
	assert_eq(KneadRules.judge(0.0), "perfect")
	assert_eq(KneadRules.judge(-80.0), "perfect")
	assert_eq(KneadRules.judge(80.1), "good")
	assert_eq(KneadRules.judge(-160.0), "good")
	assert_eq(KneadRules.judge(160.1), "miss")


func test_rhythm_stars() -> void:
	assert_eq(KneadRules.rhythm_stars(18, 0, 25), 3)
	assert_eq(KneadRules.rhythm_stars(17, 5, 25), 2)
	assert_eq(KneadRules.rhythm_stars(5, 10, 25), 2)
	assert_eq(KneadRules.rhythm_stars(5, 9, 25), 1)
	assert_eq(KneadRules.rhythm_stars(0, 0, 0), 1)


func test_trace_stars() -> void:
	assert_eq(KneadRules.trace_stars(12), 3)
	assert_eq(KneadRules.trace_stars(10), 3)
	assert_eq(KneadRules.trace_stars(9), 2)
	assert_eq(KneadRules.trace_stars(7), 2)
	assert_eq(KneadRules.trace_stars(6), 1)
	assert_eq(KneadRules.trace_stars(0), 1)


func test_combine_rounds_up() -> void:
	assert_eq(KneadRules.combine_stars(3, 3), 3)
	assert_eq(KneadRules.combine_stars(3, 2), 3)
	assert_eq(KneadRules.combine_stars(2, 1), 2)
	assert_eq(KneadRules.combine_stars(1, 1), 1)
	assert_eq(KneadRules.combine_stars(3, 1), 2)


func test_point_hit_radius() -> void:
	assert_true(KneadRules.point_hit(Vector2(10, 10), Vector2(14, 10)))
	assert_false(KneadRules.point_hit(Vector2(10, 10), Vector2(14.1, 10)))
	assert_true(KneadRules.point_hit(Vector2(10, 10), Vector2(12, 12)))


func test_segment_distance() -> void:
	assert_eq(KneadRules.segment_distance(Vector2(5, 3), Vector2(0, 0), Vector2(10, 0)), 3.0)
	assert_eq(KneadRules.segment_distance(Vector2(-4, 3), Vector2(0, 0), Vector2(10, 0)), 5.0)
	assert_eq(KneadRules.segment_distance(Vector2(2, 0), Vector2(1, 0), Vector2(1, 0)), 1.0)


func test_ring_points() -> void:
	var pts := KneadRules.ring_points(Vector2(100, 100), 50.0)
	assert_eq(pts.size(), 12)
	assert_eq(pts[0], Vector2(100, 50))
	assert_eq(pts[3], Vector2(150, 100))


func test_squash_and_sides() -> void:
	assert_eq(KneadRules.squash_step(0), 0)
	assert_eq(KneadRules.squash_step(99), KneadRules.MAX_SQUASH)
	assert_eq(KneadRules.beat_side(0), -1)
	assert_eq(KneadRules.beat_side(1), 1)
