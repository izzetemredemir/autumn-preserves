extends "res://tests/_runner/test_case.gd"
## GARDEN-LIFE: hive honey every 4th morning (Garden, DayEnd, MorningText), the props of garden_props.json (cells
## blocked, interact cells reachable, nothing of the garden covered), the hens' routes inside their run, the truck's
## load by calendar week, line picks.

const Props := preload("res://scenes/garden/garden_props.gd")
const Layout := preload("res://scenes/garden/garden_layout.gd")
const SEEDS := [1, 7, 42, 452, 4242, 90210]


# ---------------------------------------------------------------- honey

func test_honey_day_is_every_fourth_day_only() -> void:
	for day in range(1, 41):
		assert_eq(Garden.honey_day(day), day % 4 == 0, "day %d" % day)
		var n := Garden.days_to_honey(day)
		assert_true(n >= 1 and n <= 4 and (day + n) % 4 == 0, "day %d: next honey in %d" % [day, n])


func test_night_honey_fills_the_cupboard_on_honey_mornings() -> void:
	var s := State.new_game(452)
	var before := int(s.cupboard.get("honey", 0))
	var got := 0
	for _night in 12:
		var h := int(s.cupboard.get("honey", 0))
		var events := DayEnd.run(s)
		var honey_events := 0
		for e in events:
			if e.type == "honey":
				honey_events += 1
				assert_eq(int(e.count), Garden.HIVE_HONEY)
		var day := int(s.day)
		if day % 4 == 0:
			assert_eq(honey_events, 1, "honey on the morning of day %d" % day)
			assert_eq(int(s.cupboard.honey), h + Garden.HIVE_HONEY, "day %d: +1 honey" % day)
			got += 1
		else:
			assert_eq(honey_events, 0, "no honey on day %d" % day)
			assert_eq(int(s.cupboard.get("honey", 0)), h, "day %d: honey unchanged" % day)
	assert_eq(got, 3, "days 4, 8 and 12")
	assert_eq(int(s.cupboard.honey), before + 3 * Garden.HIVE_HONEY)


func test_night_honey_old_save_without_honey() -> void:
	var s := State.new_game(7)
	s.cupboard.erase("honey")
	s.day = 3
	assert_eq(Garden.night_honey(s), [], "day 3 is not a honey morning")
	assert_false(s.cupboard.has("honey"))
	s.day = 4
	assert_eq(Garden.night_honey(s), [{"type": "honey", "count": 1}])
	assert_eq(int(s.cupboard.honey), 1)


func test_night_honey_is_deterministic() -> void:
	var a := State.new_game(42)
	var b := State.new_game(42)
	for _i in 9:
		DayEnd.run(a)
		DayEnd.run(b)
	assert_eq(var_to_str(a.cupboard), var_to_str(b.cupboard))


func test_morning_card_says_honey() -> void:
	var s := State.new_game(1)
	s.day = 8
	assert_eq(MorningText.line({"type": "honey", "count": 1}, s), {"key": "UI_NIGHT_HONEY", "args": []})
	var lines := MorningText.lines([{"type": "honey", "count": 1}, {"type": "weather", "weather": "sunny"}], s)
	var keys: Array = []
	for l in lines:
		keys.append(l.key)
	assert_has(keys, "UI_NIGHT_HONEY")
	assert_false(keys.has("UI_NIGHT_QUIET"), "honey is news")


# ---------------------------------------------------------------- props

func _open(d: Dictionary) -> Callable:
	var blocked := Props.blocked(d)
	var fixed := Props.fixed_blocked()
	return func(c: Vector2i) -> bool: return Layout.is_open(c) and not blocked.has(c) and not fixed.has(c)


func test_props_parse_the_contract() -> void:
	var d := Props.data()
	var ids: Array = []
	for p in d.props:
		ids.append(p.id)
		assert_true(p.frame.x > 0 and p.frame.y > 0 and int(p.frames) >= 1, p.id)
		assert_true(ResourceLoader.exists(String(p.sheet)), "%s: %s exists" % [p.id, p.sheet])
		assert_has(["y", "back"], String(p.z), p.id)
	for want in ["truck", "coop", "hive_1", "hive_2", "clothesline", "scarecrow", "bench"]:
		assert_has(ids, want)
	assert_true(d.hen_run.has_area(), "hen run")
	assert_true(d.truck_bed.x >= 0 and d.chimney.x >= 0, "truck bed and chimney points")
	assert_false(d.perches.get("scarecrow", []).is_empty(), "crows sit on the scarecrow")
	# the cat's prop spots (CatRules) are seated by the json
	for s in CatRules.SPOTS:
		if s.has("prop"):
			var seat := Props.cat_spot(d, String(s.id))
			assert_false(seat.is_empty(), "%s has a seat in the json" % s.id)
			assert_eq(seat.get("cell"), s.cell, "%s: same cell as CatRules" % s.id)
			assert_has(ids, String(s.prop))
	assert_eq(Props.parse({}).props, [], "no file, no props")
	assert_eq(Props.group("run_front"), "coop", "the run is the hens'")
	assert_eq(Props.group("hive_1"), "hive_1")


func test_prop_cells_are_blocked_and_cover_nothing_of_the_garden() -> void:
	var d := Props.data()
	var blocked := Props.blocked(d)
	var fixed := Props.fixed_cells()
	var open := _open(d)
	for p in d.props:
		for c: Vector2i in p.blocked:
			assert_true(Layout.in_map(c), "%s %s in the map" % [p.id, c])
			assert_true(blocked.has(c), "%s %s is blocked" % [p.id, c])
			assert_false(bool(open.call(c)), "%s %s can't be walked" % [p.id, c])
			assert_false(fixed.has(c), "%s %s covers a path, bed, tree, sign or door" % [p.id, c])
	var run: Rect2i = d.hen_run
	for y in range(run.position.y, run.end.y):
		for x in range(run.position.x, run.end.x):
			assert_true(blocked.has(Vector2i(x, y)), "the run is the hens'")
			assert_false(fixed.has(Vector2i(x, y)), "the run covers nothing of the garden")


func test_interact_cells_are_reachable_and_next_to_their_prop() -> void:
	var d := Props.data()
	var blocked := Props.blocked(d)
	var open := _open(d)
	var reach := Props.reach(Layout.SPAWN.door[0], open)
	for p in d.props:
		for c: Vector2i in p.interact:
			assert_true(bool(open.call(c)), "%s: interact %s is open" % [p.id, c])
			assert_true(reach.has(c), "%s: interact %s is reachable from the door" % [p.id, c])
			var next_to := false
			for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var q: Vector2i = c + dir
				next_to = next_to or (blocked.has(q) and Props.group(String(blocked[q])) == Props.group(p.id))
			assert_true(next_to, "%s: interact %s faces the prop" % [p.id, c])
	for id in ["truck", "coop", "hive_1", "hive_2", "scarecrow", "bench"]:
		if not Props.prop(d, id).is_empty():
			assert_false(Props.prop(d, id).interact.is_empty(), "%s can be used" % id)


func test_the_garden_stays_reachable_with_the_props() -> void:
	var d := Props.data()
	var open := _open(d)
	var reach := Props.reach(Layout.SPAWN.door[0], open)
	for k in Layout.SPAWN:
		assert_true(reach.has(Layout.SPAWN[k][0]), "spawn %s" % k)
	for c: Vector2i in Layout.GATE + Layout.ROAD_EXIT:
		assert_true(reach.has(c), "exit %s" % c)
	# every bed, tree, sign, mailbox and the compost bin keeps a reachable side
	for c: Vector2i in Props.fixed_blocked():
		var side := false
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			side = side or reach.has(c + dir)
		assert_true(side, "%s keeps a free side" % c)


# ---------------------------------------------------------------- hens

func _run_setup(rainy: bool) -> Array:
	var d := Props.data()
	var run := Props.run_px(d)
	var coop := Rect2i()
	for c: Vector2i in Props.prop(d, "coop").get("blocked", []):
		var r := Rect2i(c * 16, Vector2i(16, 16))
		coop = r if not coop.has_area() else coop.merge(r)
	return [run, coop, GardenLifeRules.area(run, coop, rainy)]


func test_hen_routes_stay_inside_the_run() -> void:
	for rainy in [false, true]:
		var s := _run_setup(rainy)
		var run: Rect2i = s[0]
		var coop: Rect2i = s[1]
		var area: Rect2i = s[2]
		assert_true(area.has_area(), "the hens have room")
		assert_true(run.encloses(area), "the area is inside the run")
		for sd in SEEDS:
			for day in [1, 4, 9, 30]:
				for i in GardenLifeRules.flock().size():
					var rt := GardenLifeRules.route(sd, day, i, area, [coop])
					assert_true(rt.size() >= GardenLifeRules.ROUTE_STEPS * 2, "a long enough loop")
					var acts := {}
					for st in rt:
						acts[st.act] = true
						assert_true(GardenLifeRules.inside(st.to, area, [coop]), "seed %d day %d hen %d: %s inside" % [sd, day, i, st.to])
					assert_true(acts.has("walk") and (acts.has("peck") or acts.has("scratch")), "walks and pecks")


func test_hen_routes_are_deterministic_and_differ() -> void:
	var s := _run_setup(false)
	var area: Rect2i = s[2]
	var avoid: Array = [s[1]]
	for sd in SEEDS:
		assert_eq(GardenLifeRules.route(sd, 3, 1, area, avoid), GardenLifeRules.route(sd, 3, 1, area, avoid), "seed %d" % sd)
	assert_ne(GardenLifeRules.route(42, 3, 1, area, avoid), GardenLifeRules.route(42, 3, 2, area, avoid), "each hen its own")
	assert_ne(GardenLifeRules.route(42, 3, 1, area, avoid), GardenLifeRules.route(42, 4, 1, area, avoid), "new day, new route")


func test_rain_keeps_the_hens_by_the_coop() -> void:
	var dry: Rect2i = _run_setup(false)[2]
	var wet: Rect2i = _run_setup(true)[2]
	var coop: Rect2i = _run_setup(true)[1]
	assert_true(wet.size.x * wet.size.y < dry.size.x * dry.size.y, "a smaller patch in rain")
	assert_true(wet.position.y - coop.end.y <= 2 and wet.end.y - coop.end.y <= GardenLifeRules.RAIN_DEPTH + 2,
		"right in front of the hen house")


func test_scatter_runs_away_inside_the_run() -> void:
	var s := _run_setup(false)
	var area: Rect2i = s[2]
	var avoid: Array = [s[1]]
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for _i in 200:
		var from := Vector2i(r.randi_range(area.position.x, area.end.x - 1), r.randi_range(area.position.y, area.end.y - 1))
		if not GardenLifeRules.inside(from, area, avoid):
			continue
		var granny := Vector2(r.randf_range(area.position.x - 30, area.end.x + 30), area.end.y + r.randf_range(4, 30))
		var to := GardenLifeRules.scatter(from, granny, area, avoid)
		assert_true(GardenLifeRules.inside(to, area, avoid), "scatter %s -> %s stays inside" % [from, to])
		assert_true(Vector2(to).distance_to(granny) >= Vector2(from).distance_to(granny) - 0.01 or to == from,
			"away from Granny")


# ---------------------------------------------------------------- truck and lines

func test_truck_load_follows_the_calendar_week() -> void:
	for day in range(1, Calendar.start_day()):
		assert_eq(GardenLifeRules.truck_load(day), 0, "day %d: the hay load" % day)
	for day in range(Calendar.start_day(), 60):
		var want: int = {"grape_harvest": 1, "apple_moon": 2, "first_frost": 3}[Calendar.week_id(day)]
		assert_eq(GardenLifeRules.truck_load(day), want, "day %d" % day)
	assert_eq(GardenLifeRules.truck_load(8), 1, "Grape Harvest first")


func test_line_picks_never_repeat() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var last := 0
	var seen := {}
	for _i in 200:
		var n := GardenLifeRules.line(r, 4, last)
		assert_true(n >= 1 and n <= 4)
		assert_ne(n, last)
		seen[n] = true
		last = n
	assert_eq(seen.size(), 4, "every line comes up")
