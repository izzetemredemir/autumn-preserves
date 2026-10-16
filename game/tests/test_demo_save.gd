extends "res://tests/_runner/test_case.gd"
## DEMO-01: res://dev/demo_save.json still gives the jury demo (rainy day, rare crabapple near the entrance,
## mushroom ring, baker order the demo jar satisfies). Rebuild with: godot --headless --path game -s res://tests/make_demo_save.gd

const SAVE := "res://dev/demo_save.json"
const MAX_DIST := 12.0
const DEMO_KEY_PARTS := ["jam", "cinnamon"]


func _load() -> Dictionary:
	var s := DevTools.load_demo(SAVE)
	assert_false(s.is_empty(), "demo save missing or not a save")
	return s


func test_demo_day_is_rainy_and_matches_the_weather_stream() -> void:
	var s := _load()
	if s.is_empty():
		return
	var day := int(s.day)
	assert_true(day >= 2 and day <= 4, "demo day %d" % day)
	assert_eq(s.weather, "rainy")
	assert_eq(DayEnd.weather_for(int(s.save_seed), day), "rainy", "weather stream")


func test_forest_has_the_rare_crabapple_near_the_entrance_and_a_mushroom_ring() -> void:
	var s := _load()
	if s.is_empty():
		return
	var v: Dictionary = s.varieties
	var rare := _rare_crabapple(v)
	assert_ne(rare, "", "no rare crabapple variety")
	var map := WildGen.generate(int(s.save_seed), int(s.day), "forest", "rainy", v)
	assert_eq(String(map.special.get("kind", "")), "mushroom_ring", "special place")
	var near := false
	for t in map.fruit_trees:
		if t.type == "crabapple" and t.variety == rare:
			if Vector2(t.x - map.entrance.x, t.y - map.entrance.y).length() <= MAX_DIST:
				near = true
	assert_true(near, "rare crabapple tree within %d tiles of the entrance" % int(MAX_DIST))


func test_demo_jar_satisfies_the_baker_order() -> void:
	var s := _load()
	if s.is_empty():
		return
	var rare := _rare_crabapple(s.varieties)
	var order := {}
	for o in s.orders:
		if o.npc == "baker" and o.axes.has("sweet") and o.axes.has("spicy"):
			order = o
	assert_false(order.is_empty(), "baker sweet + spicy order on the board")
	var key := ProductGen.make_key(DEMO_KEY_PARTS[0], [rare], DEMO_KEY_PARTS[1])
	var jar := State.product(key, 3, 0)
	assert_true(Orders.matches(order, jar, s.varieties), "demo jar matches the order")
	assert_false(s.book.variants.has(key), "the demo variant is still to be discovered")


func test_demo_state_is_lived_in() -> void:
	var s := _load()
	if s.is_empty():
		return
	assert_true(int(s.coins) >= 250 and int(s.coins) <= 350, "coins about 300")
	assert_eq(int(s.cupboard.cinnamon), 2)
	for id in ["sugar", "jar", "vinegar", "salt"]:
		assert_true(int(s.cupboard.get(id, 0)) > 0, "cupboard has " + id)
	var n: int = s.book.variants.size()
	assert_true(n >= 6 and n <= 10, "book has %d variants" % n)
	assert_true(s.pantry.items.size() >= 3, "a few jars in the pantry")
	assert_true(TodoRules.is_closed(TodoRules.bits_of(s)), "tutorial finished")


func _rare_crabapple(varieties: Dictionary) -> String:
	for id in varieties:
		if varieties[id].type == "crabapple" and varieties[id].rarity == "rare":
			return id
	return ""
