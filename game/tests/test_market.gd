extends "res://tests/_runner/test_case.gd"
## MARKET: weekly market rules (spec §7.7): market days, stall score, customers, sales, reputation, unsold items.

const SEEDS := [1, 2, 3, 7, 42, 99, 314, 2026, 31337]
const KEYS := [
	"jam|apple_1|-", "jam|quince_1|ginger", "jam|crabapple_1|cinnamon", "pickle|cucumber_1|-",
	"chutney|pear_1|pepper_1|chili", "brined_mushroom|chanterelle_1|-", "fruit_butter|pear_2|honey",
	"pie|apple_1|-", "juice|apple_2|-", "pickle|cucumber_2|clove", "jam|blackberry_1|-", "bread|-",
]


## A market-day save (day 7) with the KEYS products in the inbox.
func _state(sd: int, day := 7) -> Dictionary:
	var s := State.new_game(sd)
	s.day = day
	for k in KEYS:
		s.inbox.append(State.product(k, 2, 0))
	return s


func _stall(s: Dictionary) -> Array:
	return Market.auto_stall(s.inbox, s.varieties)


func _sales_sig(sales: Array) -> Array:
	var out: Array = []
	for v in sales:
		out.append("%d|%s|%d|%s" % [int(v.customer.id), String(v.item.key), int(v.price), String(v.line_key)])
	return out


func _has_item(s: Dictionary, item: Dictionary) -> bool:
	for it in s.inbox:
		if is_same(it, item):
			return true
	for e in s.pantry.items:
		if is_same(e.item, item):
			return true
	return false


func test_market_every_seventh_day() -> void:
	for d in [7, 14, 21, 70]:
		assert_true(Market.is_market_day(d), "day %d" % d)
	for d in [0, 1, 2, 6, 8, 13, 15]:
		assert_false(Market.is_market_day(d), "day %d" % d)
	var s := _state(1, 6)
	assert_false(Market.can_open(s))
	s.day = 7
	assert_true(Market.can_open(s))


func test_old_save_without_market_key() -> void:
	var s := _state(1)
	s.erase("market")
	assert_eq(Market.info(s), {"reputation": 0, "last_day": 0})
	assert_false(s.has("market"), "info does not write")
	assert_true(Market.run(s, _stall(s)).size() > 0)
	assert_eq(int(s.market.reputation), 1)


func test_score_range_and_parts() -> void:
	assert_near(Market.stall_score([]), 1.0)
	var same: Array = []
	for i in 12:
		same.append({"item": State.product("jam|apple_1|-", 2, 0), "x": i % 6, "y": floori(i / 6.0), "rot": 0})
	var p := Market.stall_parts(same)
	assert_near(float(p.fill), 1.0)
	assert_near(float(p.colour), 1.0, 0.0001, "one colour: every pair matches")
	assert_near(float(p.variety), 0.25)
	assert_near(float(p.mult), 1.0 + 0.5 * 2.25 / 3.0)
	for sd in SEEDS:
		var s := _state(sd)
		var r := Seeds.rng(sd, "test_market", 0)
		var mixed: Array = []
		for it in s.inbox:
			var c := Vector2i(r.randi_range(0, 5), r.randi_range(0, 1))
			if PantryRules.can_place(Market.board(), mixed, it, c, 0):
				mixed.append({"item": it, "x": c.x, "y": c.y, "rot": 0})
		for st in [mixed, _stall(s), mixed.slice(0, 1)]:
			var m := Market.stall_score(st, s.varieties)
			assert_true(m >= Market.MULT_MIN and m <= Market.MULT_MAX, "seed %d: %f" % [sd, m])
		assert_true(Market.stall_score(_stall(s), s.varieties) >= Market.stall_score(mixed.slice(0, 2), s.varieties))


func test_auto_stall_fits_and_mixes() -> void:
	var s := _state(3)
	s.inbox.append(State.product("jam|pear_1|-", 2, 4))  # still waiting: never on the stall
	s.inbox.append(State.fresh("apple_1", 3, 5))
	var st := _stall(s)
	var b := Market.board()
	var cells := 0
	for i in st.size():
		var e: Dictionary = st[i]
		assert_true(Market.sellable(e.item))
		assert_true(PantryRules.can_place(b, st, e.item, Vector2i(int(e.x), int(e.y)), int(e.rot), i), "entry %d fits" % i)
		cells += PantryRules.entry_cells(e).size()
	assert_true(cells <= 12)
	assert_true(Market.stall_parts(st, s.varieties).variety >= 1.0, "four recipes or more")
	assert_false(Market.can_place(b, [], State.product("jam|pear_1|-", 2, 4), Vector2i.ZERO, 0))
	assert_false(Market.can_place(b, [], State.fresh("apple_1", 3, 5), Vector2i.ZERO, 0))


func test_customers_deterministic_and_shaped() -> void:
	for sd in SEEDS:
		var a := Market.customers(sd, 7, 0, 1.0)
		assert_eq(a, Market.customers(sd, 7, 0, 1.0), "seed %d" % sd)
		assert_eq(a.size(), Market.BASE_CUSTOMERS)
		var big := Market.customers(sd, 7, 0, 1.5)
		assert_eq(big.slice(0, a.size()), a, "a bigger crowd only appends")
		assert_ne(a, Market.customers(sd, 14, 0, 1.0), "another market day, other people")
		for c in big:
			var w: Array = c.wants
			assert_true(w.size() >= 1 and w.size() <= 2)
			if w.size() == 2:
				assert_ne(w[0], w[1])
			for axis in w:
				assert_has(ProductGen.AXES, axis)
			var cap := Market.BUDGET_MAX * (Market.FANCY_MULT if bool(c.fancy) else 1)
			assert_true(int(c.budget) >= Market.BUDGET_MIN and int(c.budget) <= cap)
			assert_true(int(c.look) >= 0)
	assert_true(Market.customer_count(1, 1.0) > Market.customer_count(0, 1.0), "reputation brings more people")
	assert_eq(Market.customer_count(0, 1.5), 12)
	assert_eq(Market.customer_count(99, 1.0), Market.customer_count(Market.REPUTATION_CAP, 1.0))


func test_sales_deterministic_full_value() -> void:
	for sd in SEEDS:
		var a := _state(sd)
		var b := _state(sd)
		var sa := Market.run(a, _stall(a))
		var sb := Market.run(b, _stall(b))
		assert_eq(_sales_sig(sa), _sales_sig(sb), "seed %d" % sd)
		assert_eq(int(a.coins), int(b.coins))
		for v in sa:
			assert_eq(int(v.price), ProductGen.value(String(v.item.key), a.varieties, int(v.item.q)), "full value")
			assert_true(int(v.price) <= int(v.customer.budget))
			assert_true(String(v.line_key).begins_with("MARKET_"))


func test_run_sells_pays_and_keeps_the_rest() -> void:
	var sold_any := false
	for sd in SEEDS:
		var s := _state(sd)
		var st := _stall(s)
		var coins := int(s.coins)
		var earned := int(s.stats.coins_earned)
		var before: int = s.inbox.size()
		var plan := Market.plan(s, st)
		var sales := Market.run(s, st)
		assert_eq(_sales_sig(sales), _sales_sig(plan.sales), "plan matches run")
		var total := 0
		for v in sales:
			total += int(v.price)
			assert_false(_has_item(s, v.item), "sold item left the save")
		sold_any = sold_any or not sales.is_empty()
		assert_eq(int(s.coins), coins + total)
		assert_eq(int(s.stats.coins_earned), earned + total)
		assert_eq(s.inbox.size(), before - sales.size(), "only sold items leave")
		for e in st:
			var sold := false
			for v in sales:
				sold = sold or is_same(v.item, e.item)
			if not sold:
				assert_true(_has_item(s, e.item), "unsold item is still in the pantry")
		assert_eq(int(s.market.reputation), 1)
		assert_eq(int(s.market.last_day), 7)
		assert_false(Market.can_open(s), "once a market day")
		assert_eq(Market.run(s, st), [], "a second run changes nothing")
		assert_eq(int(s.market.reputation), 1)
	assert_true(sold_any)


func test_unsold_pantry_items_stay_on_their_shelf() -> void:
	var s := State.new_game(5)
	s.day = 7
	for k in KEYS:
		var item := State.product(k, 2, 0)
		var at := PantryRules.first_free(PantryRules.board_of(s.pantry), s.pantry.items, item, PantryRules.zone_for(item))
		if not at.is_empty():
			s.pantry.items.append({"item": item, "x": at.cell.x, "y": at.cell.y, "rot": at.rot})
	var spots := {}
	for e in s.pantry.items:
		spots[e.item.key] = Vector2i(int(e.x), int(e.y))
	var items: Array = []
	for e in s.pantry.items:
		items.append(e.item)
	var st := Market.auto_stall(items, s.varieties)
	var sales := Market.run(s, st)
	assert_eq(s.pantry.items.size(), spots.size() - sales.size())
	for e in s.pantry.items:
		assert_eq(Vector2i(int(e.x), int(e.y)), spots[e.item.key], "unsold %s did not move" % e.item.key)


func test_reputation_grows_the_next_market() -> void:
	var s := _state(42)
	Market.run(s, _stall(s))
	s.day = 14
	assert_true(Market.can_open(s))
	var p := Market.plan(s, _stall(s))
	assert_eq(p.customers.size(), Market.customer_count(1, float(p.mult)))
	assert_true(p.customers.size() > Market.customer_count(0, float(p.mult)) or p.customers.size() == 0)


func test_run_refuses_closed_days_and_foreign_items() -> void:
	var s := _state(1, 8)
	var coins := int(s.coins)
	assert_eq(Market.run(s, _stall(s)), [])
	assert_eq(int(s.coins), coins)
	assert_false(s.has("market"))
	s.day = 7
	var foreign: Array = [{"item": State.product("jam|apple_1|-", 2, 0), "x": 0, "y": 0, "rot": 0}]
	assert_eq(Market.run(s, foreign), [], "items that are not in the save never sell")
	assert_eq(Market.run(s, []), [])
	assert_false(s.has("market"))


func test_every_line_key_has_a_string() -> void:
	var keys := {}
	var f := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > 0:
			keys[row[0]] = true
	var lines: Array = ["MARKET_RARE", "MARKET_PRICEY"]
	for a in Market.OOH_ADDINS:
		lines.append("MARKET_OOH_" + String(a).to_upper())
	for axis in ProductGen.AXES:
		lines.append("MARKET_WISH_" + String(axis).to_upper())
		for n in Market.LINE_VARIANTS:
			lines.append("MARKET_LIKE_%s_%d" % [String(axis).to_upper(), n + 1])
	for k in lines:
		assert_true(keys.has(k), k)
	for sd in SEEDS:
		var s := _state(sd)
		for v in Market.plan(s, _stall(s)).visits:
			assert_true(keys.has(String(v.line_key)), String(v.line_key))
