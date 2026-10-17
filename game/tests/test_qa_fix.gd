extends "res://tests/_runner/test_case.gd"
## QA-FIX (docs/qa/soak.md findings 2, 4, 5), pure (no scene tree): Granny re-plans round a blocked step and keeps
## her tapped action, the cat waits to go home while she walks through; jar textures are shared per look and the
## arrange views are kept across refreshes; the market's pose list covers every pose the parade shows.
## The result card, the garden, the town pager and the timings: res://tests/smoke/qa_fix_probe.gd (windowed).

const CrowdView := preload("res://scenes/market/crowd_view.gd")
const InboxView := preload("res://scenes/pantry/inbox_view.gd")
const LAYOUT := "res://assets/sprites/market/market_layout.json"
const KEYS := ["jam|apple_1|-", "jam|quince_1|ginger", "pickle|cucumber_1|-", "brined_mushroom|chanterelle_1|-",
	"fruit_butter|pear_2|honey", "pie|apple_1|-", "juice|apple_2|-", "jam|blackberry_1|-", "bread|-"]


# ---------------------------------------------------------------- 2. Granny's tapped walk and the cat

func _granny(blocked: Dictionary, size := Vector2i(8, 6)) -> Granny:
	var g := Granny.new()
	g.body = Node2D.new()
	g.input_enabled = false
	g.setup(size, func(c: Vector2i) -> bool: return not blocked.has(c), Vector2i(0, 0))
	return g


## Runs Granny's frames until `done` or `max_steps` frames of `dt` seconds.
func _walk(g: Granny, done: Callable, max_steps := 400, dt := 0.05) -> void:
	for i in max_steps:
		if bool(done.call()):
			return
		g._process(dt)


func _free_granny(g: Granny) -> void:
	g.body.free()
	g.free()


func test_granny_repaths_round_a_blocked_step_and_keeps_the_action() -> void:
	var blocked := {}
	var g := _granny(blocked)
	var arrived := [false]
	assert_true(g.walk_to(Vector2i(5, 0), func() -> void: arrived[0] = true))
	assert_true(g.on_path(Vector2i(3, 0)), "the cells ahead are on her path")
	_walk(g, func() -> bool: return g.current_cell() == Vector2i(1, 0))
	blocked[Vector2i(3, 0)] = true  # the cat steps into the way
	_walk(g, func() -> bool: return arrived[0])
	assert_true(arrived[0], "the tapped action still runs")
	assert_eq(g.current_cell(), Vector2i(5, 0), "she went round to the same goal")
	_free_granny(g)


func test_granny_approach_picks_another_side_when_hers_is_taken() -> void:
	var blocked := {Vector2i(5, 3): true}  # the thing she walks up to
	var g := _granny(blocked)
	var used := [false]
	assert_true(g.approach(Vector2i(5, 3), func() -> void: used[0] = true))
	var path: Array = g._path
	var side: Vector2i = path.back()
	_walk(g, func() -> bool: return g.current_cell() == Vector2i(2, 0) or g.current_cell() == Vector2i(0, 2))
	blocked[side] = true  # the cat sits down on the side she was heading for
	_walk(g, func() -> bool: return used[0])
	assert_true(used[0], "she still uses the thing")
	assert_ne(g.current_cell(), side, "from another side")
	assert_eq(g.current_cell() + g.facing, Vector2i(5, 3), "facing it")
	_free_granny(g)


func test_granny_waits_with_her_plan_when_there_is_no_way_yet() -> void:
	var blocked := {}
	for y in 6:
		if y != 2:
			blocked[Vector2i(3, y)] = true  # a wall with one gap at (3, 2)
	var g := _granny(blocked)
	var arrived := [false]
	assert_true(g.walk_to(Vector2i(6, 2), func() -> void: arrived[0] = true))
	_walk(g, func() -> bool: return g.current_cell() != Vector2i(0, 0))
	blocked[Vector2i(3, 2)] = true  # the cat in the gap, a few cells ahead: no way round
	_walk(g, func() -> bool: return arrived[0], 20)
	assert_false(arrived[0], "no way yet")
	assert_true(g.is_moving(), "but the plan is kept")
	blocked.erase(Vector2i(3, 2))  # the cat moves on
	OS.delay_msec(Granny.RETRY_MS + 20)
	_walk(g, func() -> bool: return arrived[0])
	assert_true(arrived[0], "she carries on and arrives")
	_free_granny(g)


func test_cat_goes_home_later_while_granny_walks_through() -> void:
	var cat := Cat.new()
	cat.setup(7, Vector2i(10, 10))
	cat.cell = Vector2i(12, 10)
	cat.wander_walkable = func(_c: Vector2i) -> bool: return true
	cat.may_enter = func(c: Vector2i) -> bool: return c != Vector2i(10, 10)  # home is on Granny's path
	cat._wander()
	assert_eq(cat.cell, Vector2i(12, 10), "stays put while home is on Granny's path")
	assert_near(cat._wander_in, Cat.HOME_RETRY_SEC, 0.001, "and tries again soon")
	cat.free()


# ---------------------------------------------------------------- 4. jar textures and kept views

func test_jar_texture_shared_per_look() -> void:
	var s := State.new_game(3)
	var a := JarIcon.new()
	var b := JarIcon.new()
	var c := JarIcon.new()
	a.show_product(ProductGen.describe("jam|apple_1|-", s.varieties))
	b.show_product(ProductGen.describe("jam|apple_1|-", s.varieties))
	c.show_product(ProductGen.describe("pickle|cucumber_1|-", s.varieties))
	assert_true(a.texture() != null and a.texture() == b.texture(), "the same jar shares one texture")
	assert_ne(a.texture(), c.texture(), "another jar has its own")
	b.view = "icon"
	assert_ne(b.texture(), a.texture(), "the icon view is cached apart")
	for j in [a, b, c]:
		j.free()


func _board(entries: Array) -> ArrangeBoard:
	var b := ArrangeBoard.new()
	var rules := {
		"item_size": func(_item: Dictionary, _rot: int) -> Vector2i: return Vector2i.ONE,
		"can_place": func(_b: Dictionary, _es: Array, _i: Dictionary, _c: Vector2i, _r: int, _ig: int) -> bool: return true,
	}
	b.setup({"cols": 6, "rows": 2, "zones": []}, entries, rules, {"cell": 24})
	return b


func test_arrange_board_keeps_unchanged_views() -> void:
	var entries: Array = []
	for i in 4:
		entries.append({"item": State.product(KEYS[i], 2, 0), "x": i, "y": 0, "rot": 0})
	var b := _board(entries)
	var before: Array = []
	for i in 4:
		before.append(b.view_at(i))
	entries[0].x = 5  # a move
	entries.append({"item": State.product(KEYS[4], 2, 0), "x": 0, "y": 1, "rot": 0})  # a drop
	b.refresh()
	for i in 4:
		assert_true(b.view_at(i) == before[i], "view %d kept" % i)
	assert_eq(b.view_at(0).position, Vector2(5 * 24, 0), "the moved one moved")
	assert_true(b.view_at(4) != null and not before.has(b.view_at(4)), "the dropped one is new")
	entries.remove_at(1)
	b.refresh()
	assert_true(before[1].is_queued_for_deletion(), "a removed item's view goes")
	assert_true(b.view_at(1) == before[2], "the others keep theirs")
	b.refresh(true)
	assert_false(b.view_at(0) == before[0], "rebuild makes them new")
	b.free()


func test_inbox_view_keeps_unchanged_views() -> void:
	var b := _board([])
	var items: Array = []
	for i in 5:
		items.append(State.product(KEYS[i], 2, 0))
	var inbox: Control = InboxView.new()
	inbox.size = Vector2(130, 200)
	inbox.setup(items, b, func(it: Dictionary, rot: int, px: Vector2i) -> Control: return ArrangeItemView.make(it, rot, px))
	var before: Array = (inbox._views as Array).duplicate()
	items.remove_at(0)
	inbox.refresh()
	assert_eq(inbox._views.size(), 4)
	for i in 4:
		assert_true(inbox._views[i] == before[i + 1], "item %d keeps its view" % i)
	assert_eq(inbox._views[0].position, Vector2(inbox.slot_rect(0).position), "and moves up a slot")
	inbox.free()
	b.free()


# ---------------------------------------------------------------- 5. the parade's poses, listed ahead

## Records what CrowdView._pose asks of a villager.
class PoseLog extends Node2D:
	var seen := {}

	func show_pose(view: String, anim: String, frame: int, blink := false) -> void:
		seen["%s|%s|%d|%s" % [view, anim, frame, blink]] = true


func test_pose_jobs_cover_every_parade_pose() -> void:
	var f := FileAccess.open(LAYOUT, FileAccess.READ)
	if f == null:
		return
	var layout: Dictionary = JSON.parse_string(f.get_as_text())
	for sd in [1, 452]:
		var s := State.new_game(sd)
		s.day = 7
		for k in KEYS:
			s.inbox.append(State.product(k, 2, 0))
		var plan := Market.plan(s, Market.auto_stall(s.inbox, s.varieties))
		var crowd := MarketCrowd.build(sd, 7, plan.visits, layout, 2, false)
		var cv := CrowdView.new()
		var log := PoseLog.new()
		var missing: Array = []
		for p: Dictionary in crowd.people:
			var listed := {}
			for pose: Array in CrowdView.poses_of(p):
				listed["%s|%s|%d|%s" % pose] = true
			log.seen.clear()
			var t := maxf(0.0, float(p.spawn))  # the parade clock starts at 0 (early strollers are already out)
			while t <= float(p.end):
				var st: Dictionary = cv._step_at(p, t)
				if not st.is_empty():
					cv._pose(log, p, st, t)
				t += 0.02
			for k: String in log.seen:
				if not listed.has(k):
					missing.append("p%d %s" % [int(p.id), k])
		assert_true(missing.is_empty(), "seed %d: poses the parade shows but nobody bakes: %s" % [sd, missing.slice(0, 6)])
		var jobs := CrowdView.pose_jobs(crowd, false)
		assert_true(jobs.size() >= crowd.people.size(), "seed %d: %d jobs for %d people" % [sd, jobs.size(), crowd.people.size()])
		log.free()
		cv.free()
