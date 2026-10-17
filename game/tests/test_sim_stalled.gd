extends "res://tests/_runner/test_case.gd"
## A waiting jar that cannot count down (still in the inbox, or on the wrong shelf) gets one morning hint.


func test_inbox_jar_that_waits_is_reported_once() -> void:
	var s := State.new_game(452)
	s.inbox.append(State.product(ProductGen.make_key("pickle", ["cucumber_1"], ""), 2, 3))
	var stalled := DayEnd.run(s).filter(func(e: Dictionary) -> bool: return e.type == "stalled")
	assert_eq(stalled.size(), 1, "one stalled event")
	assert_eq(int(stalled[0].count), 1)
	var lines := MorningText.lines([stalled[0]], s)
	assert_eq(String(lines[0].key), "UI_NIGHT_STALLED_ONE")


func test_no_hint_when_nothing_waits() -> void:
	var s := State.new_game(452)
	var stalled := DayEnd.run(s).filter(func(e: Dictionary) -> bool: return e.type == "stalled")
	assert_eq(stalled.size(), 0)
