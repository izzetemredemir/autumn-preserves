extends "res://tests/_runner/test_case.gd"
## CORE-03: hash, seed streams, data tables, save model skeleton.


func test_fnv1a31_vectors() -> void:
	assert_eq(Hash.fnv1a31(""), 18652613)
	assert_eq(Hash.fnv1a31("a"), 1678518572)
	assert_eq(Hash.fnv1a31("jam|crabapple_3|cinnamon"), 1614915306)


func test_seed_streams() -> void:
	assert_eq(Seeds.seed_for(12345, "wild:forest", 1), 1337579212)
	assert_ne(Seeds.seed_for(12345, "wild:forest", 1), Seeds.seed_for(12345, "weather", 1))
	var a := Seeds.rng(7, "orders", 3)
	var b := Seeds.rng(7, "orders", 3)
	assert_eq(a.randi(), b.randi(), "same stream, same draws")


func test_pick_weighted_bounds() -> void:
	var r := Seeds.rng(1, "t", 0)
	for i in 200:
		var k := Seeds.pick_weighted(r, [35, 35, 25, 5])
		assert_true(k >= 0 and k < 4)


func test_data_tables_load() -> void:
	for t in ["ingredients", "recipes", "addins", "grammar", "npcs", "shop", "rules"]:
		assert_false(Data.table(t).is_empty(), t + " loads")
	assert_eq(int(Data.rules().energy.base), 80)
	assert_eq(Data.ids_up_to("recipes", 0), ["brined_mushroom", "chutney", "fruit_butter", "jam", "pickle"])


func test_new_game_skeleton() -> void:
	var s := State.new_game(424242)
	assert_eq(int(s.day), 1)
	assert_eq(int(s.coins), 100)
	assert_eq(int(s.cupboard.jar), 5)
	assert_eq(s.garden.trees.size(), 3)
	assert_eq(s.garden.beds.size(), 4)
	assert_eq(s.orders[0].npc, "baker")


func test_key_roundtrip() -> void:
	var k := ProductGen.make_key("chutney", ["pear_1", "pepper_2"], "")
	assert_eq(k, "chutney|pear_1|pepper_2|-")
	var p := ProductGen.parse_key(k)
	assert_eq(p.recipe, "chutney")
	assert_eq(p.varieties, ["pear_1", "pepper_2"])
	assert_eq(p.addin, "")


func test_item_helpers() -> void:
	assert_eq(State.type_of_variety("oyster_mushroom_2"), "oyster_mushroom")
	var s := {"bag": [State.fresh("pear_1", 4, 4)], "inbox": [], "pantry": {"items": []}}
	var part := State.take(s, {"where": "bag", "index": 0}, 1)
	assert_eq(int(part.count), 1)
	assert_eq(int(s.bag[0].count), 3)
