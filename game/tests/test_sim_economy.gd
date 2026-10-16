extends "res://tests/_runner/test_case.gd"
## SIM-04: economy, orders, garden. VarietyGen/ProductGen may still be stubs, so tests inject varieties and a
## test-only taste function; product values are compared through ProductGen calls, never hard-coded.

const TIERS := ["common", "common", "uncommon", "rare"]


## Four varieties per P0 ingredient type with a taste: <type>_1.._4 in tier order.
static func fake_varieties() -> Dictionary:
	var out := {}
	var ings := Data.ingredients()
	for t in Data.ids_up_to("ingredients", 0):
		if ings[t].taste == null:
			continue
		for i in TIERS.size():
			var id := "%s_%d" % [t, i + 1]
			out[id] = {"id": id, "type": t, "name": id, "rarity": TIERS[i], "tier": i, "color_shift": 0,
				"taste_delta": [0, 0, 0, 0, 0], "size": "medium"}
	return out


## Test-only taste: recipe effect + base taste of each variety's type + add-in effect, clamped 0..9.
static func fake_taste(key: String, _varieties: Dictionary) -> Array:
	var p := ProductGen.parse_key(key)
	var parts: Array = [Data.recipes()[p.recipe].effect]
	for v in p.varieties:
		parts.append(Data.ingredients()[State.type_of_variety(v)].taste)
	if p.addin != "":
		parts.append(Data.addins()[p.addin].effect)
	var t := [0, 0, 0, 0, 0]
	for e in parts:
		for i in 5:
			t[i] += int(e[i])
	for i in 5:
		t[i] = clampi(t[i], 0, 9)
	return t


static func fake_taste_fn() -> Callable:
	return func(key: String, varieties: Dictionary) -> Array: return fake_taste(key, varieties)


static func make_state(save_seed: int = 4242) -> Dictionary:
	var s := State.new_game(save_seed)
	s.varieties = fake_varieties()
	return s


# --- Economy ---------------------------------------------------------------

func test_energy_spend() -> void:
	var s := make_state()
	assert_eq(Economy.energy_cost("stir_pot"), 7)
	assert_eq(Economy.energy_cost("walk"), 0)
	s.energy = 5
	assert_false(Economy.spend(s, "stir_pot"), "not enough energy")
	assert_eq(int(s.energy), 5, "nothing spent on failure")
	assert_true(Economy.spend(s, "shake_tree"))
	assert_eq(int(s.energy), 2)


func test_buy_cupboard_seed_and_upgrade() -> void:
	var s := make_state()
	var r := Economy.buy(s, "jar", 2)
	assert_true(r.ok)
	assert_eq(int(s.coins), 90)
	assert_eq(int(s.cupboard.jar), 7)
	r = Economy.buy(s, "seed_cucumber")
	assert_true(r.ok)
	assert_eq(int(s.cupboard.seed_cucumber), 1)
	assert_eq(int(r.coins_left), 80)
	r = Economy.buy(s, "pantry_row")
	assert_eq(r.reason, "UI_NO_COINS")
	assert_eq(int(s.coins), 80)
	s.coins = 1000
	r = Economy.buy(s, "pantry_row")
	assert_true(r.ok)
	assert_eq(int(s.coins), 750)
	assert_eq(int(s.upgrades.pantry_row), 1)
	assert_eq(int(s.pantry.rows_extra), 1)
	assert_eq(Economy.price(s, "pantry_row"), int(Data.shop().upgrades.pantry_row.prices[1]), "next shelf level")
	for id in ["nothing", "seed_pumpkin", "cellar"]:  # P1 rows outside Economy.LIVE, P2
		assert_eq(Economy.buy(s, id).reason, "UI_NOT_AVAILABLE", id)
	assert_eq(Economy.buy(s, "jar", 0).reason, "UI_NOT_AVAILABLE")


func test_grocer_discount_at_three_hearts() -> void:
	var s := make_state()
	assert_eq(Economy.price(s, "jar", 10), 50)
	s.friendship.grocer = 9
	assert_eq(Economy.hearts(s, "grocer"), 3)
	assert_eq(Economy.price(s, "jar", 10), 45)


func test_sell_fresh_rare_porcini_gives_24() -> void:
	var s := make_state()
	s.bag = [State.fresh("porcini_4", 1, 2)]
	assert_eq(s.varieties.porcini_4.rarity, "rare")
	assert_eq(Economy.sell_price(s.bag[0], s.varieties), 24)
	var r := Economy.sell(s, {"where": "bag", "index": 0})
	assert_true(r.ok)
	assert_eq(int(r.coins), 24)
	assert_eq(int(s.coins), 124)
	assert_eq(s.bag.size(), 0)
	assert_eq(int(s.stats.coins_earned), 24)


func test_sell_prices_fresh_nut_product() -> void:
	var v := fake_varieties()
	assert_eq(Economy.sell_price(State.fresh("apple_1", 2, 5), v), 6, "common fruit 3 each")
	assert_eq(Economy.sell_price(State.fresh("apple_3", 2, 5), v), 8, "uncommon 3 * 1.5 = 4 each")
	assert_eq(Economy.sell_price(State.fresh("chanterelle_4", 1, 2), v), 12, "rare mushroom 4 * 3")
	assert_eq(Economy.sell_price(State.nut("walnut", 3), v), 12)
	var p := State.product("jam|apple_1|-", 2, 0)
	assert_eq(Economy.sell_price(p, v), floori(ProductGen.value(p.key, v, 2) * float(Data.shop().sell.product_ratio)), "product_ratio of the value")
	assert_false(Economy.sell(make_state(), {"where": "bag", "index": 3}).ok, "bad ref")


func test_hearts_and_gift_once_a_day() -> void:
	var s := make_state()
	s.friendship.baker = 14
	assert_eq(Economy.hearts(s, "baker"), 4)
	assert_eq(Economy.add_friendship(s, "baker", 5), 1, "capped at 5 hearts")
	assert_eq(Economy.hearts(s, "baker"), 5)
	assert_eq(Economy.gift_points("baker", [4, 0, 0, 0, 0]), 1, "liked sweet >= 4")
	assert_eq(Economy.gift_points("baker", [3, 0, 3, 0, 0]), 0)
	assert_eq(Economy.gift_points("grocer", [9, 0, 0, 0, 0]), 0, "sweet is not a grocer like")
	s.friendship.baker = 0
	var key := "jam|apple_1|cinnamon"
	s.inbox = [State.product(key, 2, 0), State.product(key, 2, 0)]
	var expect := Economy.gift_points("baker", ProductGen.taste(key, s.varieties))
	var g := Economy.gift(s, "baker", {"where": "inbox", "index": 0})
	assert_true(g.ok)
	assert_eq(int(g.points), expect)
	assert_eq(s.inbox.size(), 1)
	assert_eq(Economy.gift(s, "baker", {"where": "inbox", "index": 0}).reason, "UI_GIFTED_TODAY")
	assert_true(Economy.gift(s, "postman", {"where": "inbox", "index": 0}).ok, "other neighbour same day")
	s.inbox = [State.fresh("apple_1", 1, 3)]
	assert_false(Economy.gift(s, "grocer", {"where": "inbox", "index": 0}).ok, "fresh items are not gifts")


# --- Orders ----------------------------------------------------------------

func test_meets_rule() -> void:
	var o := {"recipe": "", "axes": ["sweet", "spicy"], "min_stars": 2}
	assert_true(Orders.meets(o, "jam", 2, [6, 0, 3, 0, 0], 0))
	assert_false(Orders.meets(o, "jam", 2, [6, 0, 2, 0, 0], 0), "spicy below 3")
	assert_false(Orders.meets(o, "jam", 1, [6, 0, 3, 0, 0], 0), "1 star")
	assert_true(Orders.meets(o, "jam", 1, [6, 0, 3, 0, 0], 1), "harmony adds a star")
	o.recipe = "pickle"
	assert_false(Orders.meets(o, "jam", 3, [9, 9, 9, 9, 9], 2), "wrong recipe")
	assert_true(Orders.meets(o, "pickle", 3, [9, 9, 9, 9, 9], 2))


func test_matches_needs_ready_product() -> void:
	var v := fake_varieties()
	var o := {"recipe": "", "axes": [], "min_stars": 1}
	assert_true(Orders.matches(o, State.product("pickle|cucumber_1|-", 1, 0), v))
	assert_false(Orders.matches(o, State.product("pickle|cucumber_1|-", 1, 2), v), "still waiting")
	assert_false(Orders.matches(o, State.fresh("apple_1", 4, 3), v), "fresh is not a product")


func test_generate_from_likes() -> void:
	var s := make_state()
	s.day = 4
	var r := Seeds.rng(1, "orders", 4)
	var ids := {}
	for i in 60:
		for npc in ["grocer", "baker", "postman"]:
			var o := Orders.generate(s, npc, r)
			var likes: Array = Data.npcs()[npc].likes
			assert_true(o.axes.size() >= 1 and o.axes.size() <= 2)
			for a in o.axes:
				assert_has(likes, a)
			assert_true(int(o.min_stars) >= 1 and int(o.min_stars) <= 3)
			assert_eq(int(o.expires_day), 9)
			assert_false(ids.has(int(o.id)), "unique id")
			ids[int(o.id)] = true
			if o.recipe != "":
				assert_has(Orders.unlocked_recipes(s), o.recipe)


func test_refill_fills_and_expires() -> void:
	var s := make_state()
	assert_eq(s.orders.size(), 3)
	assert_eq(int(s.orders[0].id), 0, "first order kept")
	for o in s.orders:
		assert_eq(o.npc, "baker", "day 1 orders come from the first-order neighbour")
	s.day = 6
	Orders.refill_with(s, fake_taste_fn())
	assert_eq(s.orders.size(), 3)
	for o in s.orders:
		assert_true(int(o.expires_day) > 6, "expired orders dropped")
	var a := make_state(77)
	var b := make_state(77)
	a.day = 3
	b.day = 3
	a.orders = []
	b.orders = []
	Orders.refill_with(a, fake_taste_fn())
	Orders.refill_with(b, fake_taste_fn())
	assert_eq(a.orders, b.orders, "same seed and day, same orders")


func test_guarantee_with_one_working_recipe() -> void:
	var only_pickles := func(key: String, _v: Dictionary) -> Array:
		return [0, 4, 0, 4, 0] if key.begins_with("pickle|") else [0, 0, 0, 0, 0]
	var s := make_state()
	s.day = 3
	s.orders = []
	Orders.refill_with(s, only_pickles)
	assert_eq(s.orders.size(), 3)
	assert_true(_any_ok(s, only_pickles), "empty board")
	var full: Array = []
	for i in 3:
		full.append({"id": 50 + i, "npc": "baker", "recipe": "pickle", "axes": ["sweet"], "min_stars": 1, "made_day": 3, "expires_day": 8})
	s.orders = full
	Orders.refill_with(s, only_pickles)
	assert_eq(s.orders.size(), 3)
	assert_true(_any_ok(s, only_pickles), "full board of impossible orders")
	var none := func(_k: String, _v: Dictionary) -> Array: return [0, 0, 0, 0, 0]
	s.orders = []
	Orders.refill_with(s, none)
	assert_eq(s.orders.size(), 3, "unknown taste still fills the board")


func _any_ok(s: Dictionary, taste_fn: Callable) -> bool:
	for o in s.orders:
		if Orders.satisfiable_with(s, o, taste_fn):
			return true
	return false


func test_fulfill_pays_and_befriends() -> void:
	var s := make_state()
	var key := "pickle|cucumber_1|-"
	s.orders = [{"id": 99, "npc": "postman", "recipe": "", "axes": [], "min_stars": 1, "made_day": 1, "expires_day": 6}]
	s.friendship.postman = 2
	s.inbox = [State.fresh("apple_1", 2, 3), State.product(key, 2, 0)]
	assert_eq(Orders.fulfill(s, 99, {"where": "inbox", "index": 0}).reason, "UI_ORDER_NO_MATCH")
	assert_eq(Orders.fulfill(s, 7, {"where": "inbox", "index": 1}).reason, "UI_NOT_AVAILABLE")
	var pay := floori(ProductGen.value(key, s.varieties, 2) * 1.5)
	var r := Orders.fulfill(s, 99, {"where": "inbox", "index": 1})
	assert_true(r.ok)
	assert_eq(int(r.coins), pay)
	assert_eq(int(s.coins), 100 + pay)
	assert_eq(int(r.hearts_before), 0)
	assert_eq(int(r.hearts_after), 1)
	assert_eq(int(s.friendship.postman), 4)
	assert_eq(s.orders.size(), 0)
	assert_eq(s.inbox.size(), 1)
	assert_eq(int(s.stats.orders_done), 1)


# --- Garden ----------------------------------------------------------------

func test_shake_tree_and_refill() -> void:
	var s := make_state()
	s.garden.trees[0].variety = "apple_1"
	var r := Garden.shake_tree(s, 0)
	assert_true(r.ok)
	var n := int(r.items[0].count)
	assert_true(n >= 2 and n <= 3, "2-3 fruit")
	assert_eq(s.bag[0].variety, "apple_1")
	assert_eq(int(s.bag[0].days_left), 6, "apple shelf days")
	assert_eq(int(s.energy), 77)
	assert_eq(Garden.shake_tree(s, 0).reason, "UI_TREE_EMPTY")
	for i in 3:
		assert_false(bool(s.garden.trees[0].fruit), "night %d" % i)
		DayEnd.grow_garden(s)
	assert_true(bool(s.garden.trees[0].fruit), "refills after 3 nights")
	var w := Garden.shake_tree(s, 2)
	assert_eq(w.items[0].kind, "nut", "walnut tree drops nuts")
	s.energy = 2
	assert_eq(Garden.shake_tree(s, 1).reason, "UI_TIRED")


func test_plant_and_harvest() -> void:
	var s := make_state()
	assert_eq(Garden.plant(s, 2, "pepper").reason, "UI_NO_SEED")
	Economy.buy(s, "seed_pepper", 2)
	assert_eq(Garden.plant(s, 0, "pepper").reason, "UI_BED_BUSY")
	assert_eq(Garden.plant(s, 2, "pepper", true).reason, "UI_NO_FERTILIZER")
	var p := Garden.plant(s, 2, "pepper")
	assert_true(p.ok)
	assert_eq(int(p.days_left), 3)
	assert_ne(s.varieties[p.variety].rarity, "rare", "garden varieties are never rare")
	s.garden.fertilizer = 1
	assert_eq(int(Garden.plant(s, 3, "pepper", true).days_left), 2, "fertilizer saves a day")
	assert_eq(int(s.garden.fertilizer), 0)
	assert_eq(int(s.cupboard.seed_pepper), 0)
	assert_eq(Garden.harvest(s, 2).reason, "UI_NOT_READY")
	assert_eq(Garden.harvest(s, 1).reason, "UI_NOT_READY", "start cucumbers ripen overnight")
	DayEnd.grow_garden(s)
	var e := int(s.energy)
	var h := Garden.harvest(s, 1)
	assert_true(h.ok)
	assert_eq(int(h.items[0].count), 3, "harvest 3")
	assert_eq(int(s.energy), e - 1)
	assert_eq(s.garden.beds[1].crop, "")
	assert_eq(Garden.harvest(s, 1).reason, "UI_NOT_READY")
