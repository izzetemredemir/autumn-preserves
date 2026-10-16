class_name PressRules
extends RefCounted
## Pure scoring helpers for the press mini-game (unit-tested in tests/test_mg_press.gd).

const PERFECT_MS := 80.0
const GOOD_MS := 160.0
const STAR3_PERFECT := 0.70
const STAR2_HIT := 0.60


## Judge a hit by its offset (ms, signed) from the beat: "perfect", "good" or "miss".
static func judge(offset_ms: float) -> String:
	var a := absf(offset_ms)
	if a <= PERFECT_MS:
		return "perfect"
	if a <= GOOD_MS:
		return "good"
	return "miss"


## Stars from {"perfect", "good", "miss"} counts: Perfect >= 70% -> 3, Perfect+Good >= 60% -> 2, else 1.
static func stars_for(counts: Dictionary) -> int:
	var p := int(counts.get("perfect", 0))
	var g := int(counts.get("good", 0))
	var m := int(counts.get("miss", 0))
	var total := p + g + m
	if total <= 0:
		return 1
	if float(p) / total >= STAR3_PERFECT:
		return 3
	if float(p + g) / total >= STAR2_HIT:
		return 2
	return 1


## Juice added to the bottle per hit (fraction of the bottle, 24 beats).
static func juice_for(grade: String) -> float:
	match grade:
		"perfect":
			return 1.0 / 20.0
		"good":
			return 1.0 / 32.0
	return 0.0
