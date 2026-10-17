class_name PressRules
extends RefCounted
## Pure scoring helpers for the press mini-game (unit-tested in tests/test_mg_press.gd).

const PERFECT_MS := 100.0  ## wide, forgiving windows: the press should feel easy
const GOOD_MS := 200.0
const STAR3_PERFECT := 0.60
const STAR2_HIT := 0.50


## Judge a hit by its offset (ms, signed) from the beat: "perfect", "good" or "miss".
static func judge(offset_ms: float) -> String:
	var a := absf(offset_ms)
	if a <= PERFECT_MS:
		return "perfect"
	if a <= GOOD_MS:
		return "good"
	return "miss"


## Stars from {"perfect", "good", "miss"} counts: Perfect >= 60% -> 3, Perfect+Good >= 50% -> 2, else 1.
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


## The three fill tones (dark, mid, light) from ctx.desc.appearance.fill: ProductGen.describe() gives three palette
## hex strings dark -> light. A single hex / Color (old sample ctx) fills all three; anything else gives `fallback`.
static func fill_tones(fill: Variant, fallback: Color) -> Array[Color]:
	var src: Array = []
	if fill is Array:
		src = fill
	elif fill is String or fill is Color:
		src = [fill]
	var out: Array[Color] = []
	for v in src:
		if v is Color:
			out.append(v)
		elif v is String and Color.html_is_valid(v):
			out.append(Color.html(v))
	if out.is_empty():
		out.append(fallback)
	while out.size() < 3:  # one tone -> [c, c, c]; two -> [dark, light, light]
		out.append(out[out.size() - 1])
	return out.slice(0, 3)


## Juice added to the bottle per hit (fraction of the bottle, 24 beats).
static func juice_for(grade: String) -> float:
	match grade:
		"perfect":
			return 1.0 / 7.0  # 8 beats: the bottle fills even with one miss
		"good":
			return 1.0 / 11.0
	return 0.0
