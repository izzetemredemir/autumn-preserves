extends "res://tests/_runner/test_case.gd"
## NPC5: Vito and Edith, heart rewards fire once at their threshold, old saves get the new neighbours lazily.


func _state() -> Dictionary:
	var s := State.new_game(77)
	s.flags.erase("rewards")
	return s


func test_each_reward_fires_once_at_threshold() -> void:
	var s := _state()
	Economy.ensure_neighbours(s)
	var pts := int(Data.rules().friendship.points_per_heart)
	var cases := [["baker", 2, "knead", "UI_REWARD_KNEAD"], ["vintner", 2, "vineyard", "UI_REWARD_VINEYARD"],
		["librarian", 1, "hints", "UI_REWARD_HINTS"]]
	for c in cases:
		var id: String = c[0]
		Economy.add_friendship(s, id, pts * (int(c[1]) - 1) + (pts - 1 if c[1] == 1 else 0))
		assert_false(Economy.unlocked(s, c[2]), "%s not before %d hearts" % [id, c[1]])
		assert_true(Economy.take_rewards(s).is_empty(), "no reward below threshold")
		Economy.add_friendship(s, id, pts)
		assert_true(Economy.unlocked(s, c[2]), "%s unlocks %s" % [id, c[2]])
		var got := Economy.take_rewards(s)
		assert_eq(got.size(), 1, "one reward for %s" % id)
		assert_eq(got[0].key, c[3])
		Economy.add_friendship(s, id, 1)
		assert_true(Economy.take_rewards(s).is_empty(), "%s reward is not repeated" % id)


func test_librarian_rare_addin_at_three_hearts_once() -> void:
	var s := _state()
	Economy.ensure_neighbours(s)
	Economy.add_friendship(s, "librarian", 9)
	var got := Economy.take_rewards(s)
	assert_eq(got.size(), 2, "hints (1 heart) plus add-in (3 hearts) are both new")
	assert_eq(int(s.cupboard.get("mint", 0)), 3)
	Economy.add_friendship(s, "librarian", 3)
	assert_eq(int(s.cupboard.get("mint", 0)), 3, "not granted twice")


func test_derived_rewards_are_toasted_once() -> void:
	var s := _state()
	Economy.add_friendship(s, "grocer", 9)
	assert_eq(Economy.take_rewards(s)[0].key, "UI_REWARD_SHOP_DISCOUNT")
	assert_true(Economy.discount(s) > 0.0)
	Economy.add_friendship(s, "postman", 6)
	assert_eq(Economy.take_rewards(s)[0].key, "UI_REWARD_LETTERS_MORE_OFTEN")


func test_old_save_upgrade() -> void:
	var s := _state()
	s.friendship.erase("vintner")
	s.friendship.erase("librarian")
	s.friendship.baker = 7  # 2 hearts earned before the reward existed
	var fresh := Economy.sync_neighbours(s)
	assert_true(s.friendship.has("vintner") and s.friendship.has("librarian"), "new keys added")
	assert_eq(int(s.friendship.baker), 7, "existing friendship untouched")
	assert_true(Economy.unlocked(s, "knead"), "earned reward claimed")
	assert_eq(fresh.size(), 1)
	assert_true(Economy.sync_neighbours(s).is_empty(), "second sync changes nothing")
	var old := {"friendship": {"grocer": 0}, "flags": {}, "unlocks": {}, "cupboard": {}}
	Economy.ensure_neighbours(old)
	assert_true(old.friendship.has("librarian"))


func test_new_neighbours_place_orders() -> void:
	var s := State.new_game(5)
	s.day = 3
	s.friendship.erase("vintner")
	var pool := Orders.npc_pool(s)
	assert_true(pool.has("vintner") and pool.has("librarian"), "pool %s" % [pool])
	for id in ["vintner", "librarian"]:
		var o := Orders.generate(s, id, Seeds.rng(1, "t", 1))
		assert_eq(o.npc, id)
