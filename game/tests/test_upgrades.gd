extends "res://tests/_runner/test_case.gd"
## UPGRADES: bag capacity per level, six beds after the purchase, old saves, pumpkin seeds on sale.


func _rich() -> Dictionary:
	var s := State.new_game(31)
	s.coins = 5000
	return s


func test_bag_capacity_per_level() -> void:
	var s := _rich()
	assert_eq(Forage.bag_capacity(s), 30)
	assert_true(Economy.buy(s, "bag").ok, "bag I")
	assert_eq(Forage.bag_capacity(s), 40)
	assert_eq(Garden.bag_free(s), 40)
	assert_eq(Economy.price(s, "bag"), 500, "bag II costs 500")
	assert_true(Economy.buy(s, "bag").ok, "bag II")
	assert_eq(Forage.bag_capacity(s), 50)
	assert_eq(Economy.price(s, "bag"), -1, "no bag III")
	assert_false(Economy.buy(s, "bag").ok)


func test_bag_fills_to_the_new_capacity() -> void:
	var s := _rich()
	s.bag = [State.fresh("apple_1", 30, 4)]
	assert_eq(Garden.bag_free(s), 0)
	Economy.buy(s, "bag")
	assert_eq(Garden.bag_free(s), 10, "ten more fit")


func test_six_beds_after_purchase() -> void:
	var s := _rich()
	assert_eq(s.garden.beds.size(), 4)
	s.garden.beds[0] = {"crop": "cucumber", "variety": "cucumber_1", "days_left": 2, "fertilized": false}
	var coins := int(s.coins)
	var r := Economy.buy(s, "beds")
	assert_true(r.ok)
	assert_eq(int(s.coins), coins - 150)
	assert_eq(s.garden.beds.size(), 6)
	assert_eq(s.garden.beds[0].crop, "cucumber", "growing bed untouched")
	assert_eq(s.garden.beds[5].crop, "")
	assert_eq(Economy.price(s, "beds"), -1, "bought once")


func test_old_save_keeps_beds_and_catches_up() -> void:
	var s := _rich()
	s.garden.beds[1] = {"crop": "pepper", "variety": "pepper_1", "days_left": 1, "fertilized": true}
	assert_false(Garden.ensure_beds(s), "nothing to add before the purchase")
	assert_eq(s.garden.beds.size(), 4)
	Economy.unlock(s, "beds")  # a save that holds the unlock but still the old four beds
	assert_true(Garden.ensure_beds(s))
	assert_eq(s.garden.beds.size(), 6)
	assert_eq(s.garden.beds[1].crop, "pepper")
	assert_false(Garden.ensure_beds(s), "idempotent")
	var old := {"upgrades": {}, "unlocks": {}}
	assert_eq(Forage.bag_capacity(old), 30, "save without upgrade keys")


func test_new_beds_can_be_planted() -> void:
	var s := _rich()
	Economy.buy(s, "beds")
	s.cupboard["seed_cucumber"] = 1
	assert_true(Garden.plant(s, 5, "cucumber").ok, "bed 6")


func test_pumpkin_on_sale_and_plantable() -> void:
	var s := _rich()
	assert_eq(Economy.price(s, "seed_pumpkin"), 20)
	assert_true(Economy.buy(s, "seed_pumpkin").ok)
	var pr := Garden.plant(s, 3, "pumpkin")
	assert_true(pr.ok, str(pr))
	assert_eq(PantryRules.item_size({"kind": "fresh", "variety": "pumpkin_1"}), Vector2i(2, 2))
