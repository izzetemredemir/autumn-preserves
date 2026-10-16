extends "res://tests/_runner/test_case.gd"
## CALENDAR-WEATHER: the harvest calendar (spec §7.11) and the P1 weather (spec §7.10), both from day 8.

const SEEDS := [1000, 452, 7919, 31, 20261016]
## Taken before the calendar existed (0a9df33), per save seed: [md5 over every map (forest, vineyard, creek) of days
## 1-7 with that day's weather, the weather of days 1-7 of a save played from State.new_game]. Must never change.
const DAYS_1_7 := {
	1000: ["27defa453ae11d9e001194fcdfd57ec8", "sunny,rainy,sunny,sunny,rainy,sunny,rainy"],
	452: ["0102cbdc13d838aff84a8f4d77a04595", "sunny,rainy,rainy,rainy,rainy,sunny,sunny"],
	7919: ["feced07256d734f587373afe0c0e899d", "sunny,sunny,sunny,sunny,sunny,sunny,rainy"],
	31: ["3ca115b64e2772d3f2cb02cca8dd4a36", "sunny,rainy,sunny,rainy,sunny,sunny,sunny"],
	20261016: ["16925fdd9c7c0cef56cefd3ca0ddcd00", "sunny,sunny,sunny,sunny,sunny,sunny,sunny"],
}
const MAPS := 40
const GRAPE_DAY := 9  # Grape Harvest (days 8-14)
const APPLE_DAY := 16  # Apple Moon (15-21)
const FROST_DAY := 23  # First Frost (22-28)

var _v: Dictionary = {}


func before_each() -> void:
	if _v.is_empty():
		_v = _vars(4242)


func _vars(sd: int) -> Dictionary:
	var v := VarietyGen.generate_all(sd, 0)
	VarietyGen.ensure_types(v, sd)
	return v


static func _fp(m: Dictionary) -> String:
	var d := {"seed": m.seed, "biome": m.biome, "ground": m.ground, "decor": m.decor_trees, "fruit": m.fruit_trees,
		"pickups": m.pickups, "special": m.special, "entrance": m.entrance, "clearings": m.clearings, "solid": m.solid}
	return var_to_str(d).md5_text()


func _week_one(sd: int) -> String:
	var v := _vars(sd)
	var parts: Array = []
	for day in range(1, 8):
		var w := DayEnd.weather_for(sd, day)
		for b in WildGen.BIOMES:
			parts.append(_fp(WildGen.generate(sd, day, b, w, v)))
	return ",".join(parts).md5_text()


func _played_weather(sd: int) -> String:
	var s := State.new_game(sd)
	var out: Array = [String(s.weather)]
	while int(s.day) < 7:
		DayEnd.run(s)
		out.append(String(s.weather))
	return ",".join(out)


# ---------------- the tutorial week stays as it was ----------------

func test_days_1_to_7_unchanged() -> void:
	for sd: int in DAYS_1_7:
		assert_eq(_week_one(sd), DAYS_1_7[sd][0], "maps of days 1-7, seed %d" % sd)
		assert_eq(_played_weather(sd), DAYS_1_7[sd][1], "weather of days 1-7, seed %d" % sd)
	for d in range(1, 8):
		assert_false(Calendar.active(d), "no calendar on day %d" % d)
		assert_eq(Calendar.week_key(d), "")
		assert_eq(Calendar.weather_table(d), "p0")
		assert_eq(Calendar.type_mult(d, "pear"), 1.0)
	assert_eq(Calendar.start_day(), 8)


# ---------------- weeks, names, abundance ----------------

func test_cycle_names() -> void:
	var expect := {8: "grape_harvest", 14: "grape_harvest", 15: "apple_moon", 21: "apple_moon", 22: "first_frost",
		28: "first_frost", 29: "grape_harvest", 36: "apple_moon", 50: "grape_harvest", 71: "grape_harvest"}
	for d: int in expect:
		assert_eq(Calendar.week_id(d), expect[d], "day %d" % d)
	assert_eq(Calendar.week_key(15), "UI_WEEK_APPLE_MOON")
	for d in [8, 15, 22, 29]:
		assert_true(Calendar.first_day_of_week(d), "day %d starts a week" % d)
	for d in [7, 9, 14, 21, 28]:
		assert_false(Calendar.first_day_of_week(d), "day %d" % d)
	assert_eq([Calendar.cycle(7), Calendar.cycle(8), Calendar.cycle(28), Calendar.cycle(29), Calendar.cycle(50)],
		[0, 1, 1, 2, 3], "Autumn 1, 2, 3 ...")
	assert_eq(MorningText.week_name(3), "")
	assert_ne(MorningText.week_name(9), "")
	assert_ne(MorningText.week_name(29), MorningText.week_name(8), "the second round names its autumn")
	assert_eq(MorningText.week_name(29, false), MorningText.week_name(8, false), "the HUD's short name")
	for d in range(8, 200):
		assert_eq(Calendar.weather_table(d), "p1")


func test_abundance_weights() -> void:
	var mult := float(Data.rules().calendar.abundance_mult)
	assert_eq(mult, 2.0)
	assert_eq(Calendar.type_mult(GRAPE_DAY, "pear"), mult)
	assert_eq(Calendar.type_mult(GRAPE_DAY, "apple"), 1.0)
	assert_eq(Calendar.type_mult(APPLE_DAY, "apple"), mult)
	assert_eq(Calendar.type_mult(FROST_DAY, "chestnut"), mult)
	assert_eq(Calendar.wild_types(GRAPE_DAY), ["grape", "pear", "blackberry"], "no bed-only crops in season lists")
	assert_eq(Calendar.wild_types(FROST_DAY), ["rosehip", "chestnut", "elderberry"])
	# ground weights: First Frost doubles chestnut among the forest's P1 nuts, never drops a type
	var flat := WildGen.ground_type_weights("forest", "sunny", 1, 3)
	var frost := WildGen.ground_type_weights("forest", "sunny", 1, FROST_DAY)
	assert_eq(frost.types, flat.types)
	for k in (flat.types as Array).size():
		var m := mult if flat.types[k] == "chestnut" else 1.0
		assert_near(float(frost.weights[k]), float(flat.weights[k]) * m, 0.0001, String(flat.types[k]))
		assert_true(float(frost.weights[k]) > 0.0)
	# rain still doubles mushrooms on top of the week
	var rain := WildGen.ground_type_weights("forest", "rainy", -1, APPLE_DAY)
	var k := (rain.types as Array).find("chanterelle")
	assert_near(float(rain.weights[k]), mult * float(Data.rules().weather.rain_mushroom_mult), 0.0001)


## Pear trees in the forest: about 1/3 in First Frost (flat), about 1/2 in Grape Harvest (pear x2). Every tree type
## still grows in every week.
func test_abundance_in_forests() -> void:
	var share := {}
	for day in [GRAPE_DAY, FROST_DAY]:
		var n := 0
		var pear := 0
		var seen := {}
		for i in MAPS:
			var m := WildGen.generate(700 + i * 131, day, "forest", "sunny", _v)
			for t in m.fruit_trees:
				if bool(t.get("special", false)):
					continue
				n += 1
				pear += 1 if t.type == "pear" else 0
				seen[t.type] = true
		share[day] = float(pear) / maxi(n, 1)
		assert_eq(seen.size(), 3, "apple, crabapple and pear all grow on day %d" % day)
	assert_true(share[GRAPE_DAY] > 0.42 and share[GRAPE_DAY] < 0.6, "pear share in Grape Harvest %.2f" % share[GRAPE_DAY])
	assert_true(share[FROST_DAY] > 0.22 and share[FROST_DAY] < 0.42, "pear share in First Frost %.2f" % share[FROST_DAY])


static func _cells(list: Array) -> Dictionary:
	var out := {}
	for it in list:
		out[Vector2i(int(it.x), int(it.y))] = true
	return out


# ---------------- weather ----------------

func test_p1_weather_from_day_8_and_no_fog_twice() -> void:
	for sd in [55, 4242]:
		var s := State.new_game(sd)
		var prev := String(s.weather)
		var seen := {}
		while int(s.day) < 120:
			DayEnd.run(s)
			var w := String(s.weather)
			if int(s.day) < 8:
				assert_has(["sunny", "rainy"], w, "tutorial week, day %d" % int(s.day))
			seen[w] = true
			assert_false(prev == "foggy" and w == "foggy", "fog twice in a row on day %d, seed %d" % [int(s.day), sd])
			prev = w
		assert_true(seen.has("windy") and seen.has("foggy"), "seed %d meets wind and fog: %s" % [sd, str(seen.keys())])
	var counts := {}
	var prev := ""
	for d in range(8, 4008):
		var w := DayEnd.weather_for(9, d, prev)
		assert_false(prev == "foggy" and w == "foggy", "day %d" % d)
		counts[w] = int(counts.get(w, 0)) + 1
		prev = w
	assert_true(int(counts.windy) > 680 and int(counts.windy) < 920, "windy about 20%%: %d / 4000" % counts.windy)
	assert_true(int(counts.foggy) > 260 and int(counts.foggy) < 440, "foggy about 10%% (less after fog): %d" % counts.foggy)


func test_windy_drops_one_fruit_under_each_tree() -> void:
	var total := 0
	var dropped := 0
	for b in WildGen.BIOMES:
		for i in 8:
			var sd := 300 + i * 977
			var calm := WildGen.generate(sd, GRAPE_DAY, b, "sunny", _v)
			var windy := WildGen.generate(sd, GRAPE_DAY, b, "windy", _v)
			var tag := "%s seed %d" % [b, sd]
			assert_eq(var_to_str(windy.fruit_trees), var_to_str(calm.fruit_trees), tag + ": trees unchanged")
			var n0: int = (calm.pickups as Array).size()
			assert_eq(var_to_str((windy.pickups as Array).slice(0, n0)), var_to_str(calm.pickups), tag + ": pickups kept")
			var fallen: Array = (windy.pickups as Array).slice(n0)
			total += (windy.fruit_trees as Array).size()
			dropped += fallen.size()
			assert_true(fallen.size() >= (windy.fruit_trees as Array).size() - 1, tag + ": a fruit under (almost) every tree")
			var cells := _cells(calm.pickups)
			var trees := {}
			for j in fallen.size():
				var p: Dictionary = fallen[j]
				var t: Dictionary = windy.fruit_trees[int(p.tree)]
				assert_false(trees.has(int(p.tree)), tag + ": one fruit per tree")
				trees[int(p.tree)] = true
				assert_eq(int(p.id), n0 + j)
				assert_eq([p.kind, p.type, p.variety, bool(p.windfall)], ["ground", t.type, t.variety, true], tag)
				var c := Vector2i(int(p.x), int(p.y))
				var d := c - Vector2i(int(t.x), int(t.y))
				assert_true(absi(d.x) <= 1 and d.y >= 0 and d.y <= 2, tag + ": next to its tree")
				assert_false(cells.has(c), tag + ": a free tile")
				cells[c] = true
				assert_true(WildGen.is_walkable(windy, c) and c != windy.entrance, tag + ": walkable, not the exit")
	assert_true(dropped >= total * 0.95, "windfalls %d for %d trees" % [dropped, total])
	assert_eq(Calendar.windfall({}), 0)


func test_windfall_is_picked_like_a_ground_point() -> void:
	var s := State.new_game(77)
	VarietyGen.ensure_types(s.varieties, 77)
	s.day = GRAPE_DAY
	s.weather = "windy"
	var m := WildGen.generate(77, GRAPE_DAY, "forest", "windy", s.varieties)
	var fallen: Dictionary = {}
	for p in m.pickups:
		if bool(p.get("windfall", false)):
			fallen = p
			break
	assert_false(fallen.is_empty(), "a windfall on the map")
	var e0 := int(s.energy)
	var r := Forage.pick(s, m, int(fallen.id))
	assert_true(bool(r.ok))
	assert_eq(e0 - int(s.energy), int(Data.rules().energy.costs.pick_ground))
	assert_eq(r.items[0].variety, fallen.variety)
	assert_eq(int(r.items[0].count), int(Data.rules().forage.ground_yield))


func test_fog_favours_rare_varieties() -> void:
	assert_eq(WildGen.weather_rare_mult("foggy"), float(Data.rules().weather.fog_rare_mult))
	assert_eq(WildGen.weather_rare_mult("windy"), 1.0)
	var flat := VarietyGen.spawn_weights(_v, "apple", 1.0)
	var fog := VarietyGen.spawn_weights(_v, "apple", WildGen.weather_rare_mult("foggy"))
	var boosted := 0
	for i in (flat.ids as Array).size():
		var rare: bool = _v[flat.ids[i]].rarity == "rare"
		assert_near(float(fog.weights[i]), float(flat.weights[i]) * (1.5 if rare else 1.0), 0.0001)
		boosted += 1 if rare else 0
	assert_true(boosted >= 1, "apple has a rare variety")


# ---------------- morning card ----------------

func test_morning_lines_name_the_week_and_the_market() -> void:
	var s := State.new_game(3)
	s.day = 3
	assert_eq(MorningText.calendar_lines(s), [])
	s.day = 7
	assert_eq(_keys(MorningText.calendar_lines(s)), ["UI_MARKET_TODAY"], "the tutorial week's market")
	s.day = 8
	var l := MorningText.calendar_lines(s)
	assert_eq(_keys(l), ["UI_WEEK_BEGINS"])
	assert_eq(l[0].args[1], "grape, pear, blackberry")
	s.day = 14
	assert_eq(_keys(MorningText.calendar_lines(s)), ["UI_WEEK_NOW", "UI_MARKET_TODAY"])
	var lines := MorningText.lines([{"type": "weather", "weather": "foggy"}, {"type": "energy", "stars": 0, "energy": 80}], s)
	assert_eq(_keys(lines), ["UI_NIGHT_QUIET", "UI_WEEK_NOW", "UI_MARKET_TODAY", "UI_NIGHT_WEATHER_FOGGY", "UI_NIGHT_ENERGY"])
	# a busy night: the calendar lines take room from the notable ones, the card keeps its height
	var events: Array = []
	for i in 9:
		events.append({"type": "order_new", "order": {"npc": "npc_%d" % i}})
	lines = MorningText.lines(events, s)
	assert_eq(lines.size(), MorningText.MAX_NOTABLE + 1, "same number of lines as a busy tutorial-week night")
	assert_eq(lines[MorningText.MAX_NOTABLE - 2].key, "UI_NIGHT_MORE")
	assert_eq(lines[MorningText.MAX_NOTABLE - 2].args, [5])


static func _keys(lines: Array) -> Array:
	var out: Array = []
	for l in lines:
		out.append(l.key)
	return out
