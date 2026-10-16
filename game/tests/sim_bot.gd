extends SceneTree
## QA-01 / QA-BALANCE-P1 · 100-day greedy bot. Plays through the sim API only (no autoloads) and writes docs/qa/balance.md.
##   godot --headless --path game -s res://tests/sim_bot.gd              (writes the report)
##   godot --headless --path game -s res://tests/sim_bot.gd -- --no-report   (prints the summary line only: experiments)
## Not a unit test (file name does not start with test_). Assumes a cooking quality of QUALITY stars (minigames are not run).
## P1 policy: buys upgrades in BUY_ORDER (+SHELF_MARGIN coins left), gifts neighbours until knead / vineyard / discount,
## cooks every available recipe (big pot x2, family recipes), forages the best open biomes, answers grandchild letters with
## matching jars (straw + one surprise jar for the care bonus) and runs the weekly market with Market.auto_stall.

const SEEDS := [1, 7, 42, 4242, 90210]
const DAYS := 100
const QUALITY := 2            # average mini-game result assumed for every cook
const COOK_RESERVE := 35      # energy kept for cooking (five 7-energy cooks)
const KEEP_PRODUCTS := 3      # finished jars kept in stock for future orders
const BASE_STOCK := 4         # target for jar/sugar/salt/vinegar
const SHELF_MARGIN := 40      # coins left after buying a shelf
const NOTES_HEADING := "## P1 proposed number changes"
const P0_HEADING := "# Balance report - 100-day greedy bot (QA-01)"
## Upgrade purchase order (a repeated id is its next level). Strict: the bot saves for the first one it can still buy.
const BUY_ORDER := ["press", "pantry_row", "beds", "bag", "boots", "pantry_row", "big_pot", "bag", "pantry_row"]
const KEEP_MARKET := 14       # jars kept (not sold to the grocer) on the two days before a market
const MIN_NET_PER_ENERGY := 2.5  # a cook must clear this many coins per energy after its grocer bases
const PARTIAL_AFTER := 5      # days before a letter is answered with a partial parcel
const FRESH_CAP := 100        # stop foraging at this many fresh units in hand (about the bag size; 40 halves the income)
const GIFT_NPCS := ["baker", "vintner", "grocer", "postman"]
const UPGRADE_COLS := ["press#1", "pantry_row#1", "beds#1", "bag#1", "boots#1", "pantry_row#2", "big_pot#1", "bag#2", "pantry_row#3"]


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var write := not OS.get_cmdline_user_args().has("--no-report")
	var results: Array = []
	for sd in SEEDS:
		results.append(_play(int(sd)))
	print(_summary(results))
	if write:
		var md := _report(results)
		var dir := ProjectSettings.globalize_path("res://").path_join("../docs/qa")
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(dir.path_join("balance.md"), FileAccess.WRITE)
		if f != null:
			f.store_string(md)
			f.close()
	print("sim_bot: done in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)


# ---------------------------------------------------------------- one run

func _play(sd: int) -> Dictionary:
	var s := State.new_game(sd)
	Economy.ensure_neighbours(s)
	var r := {"seed": sd, "earned": [], "net": [], "bank": [], "orders_done": 0, "sat_days": 0, "done_days": 0, "unused": 0,
		"composted": 0, "stars": [0, 0, 0, 0], "buy_day": {}, "unlock_day": {}, "variants": 0, "found": 0, "total_varieties": s.varieties.size(),
		"kinds": {}, "order_coins": 0, "sell_coins": 0, "market_coins": 0, "market_days": 0, "market_sold": 0, "jar_value": 0,
		"no_cook_days": 0, "cook_days": 0, "spent_up": 0, "spent_stock": 0, "letters_sent": 0, "letters_hearts": 0,
		"family_days": [], "gifts": 0, "biome_days": {}, "stale": 0, "big_pot_cooks": 0}
	for day in range(1, DAYS + 1):
		var earned0 := int(s.stats.coins_earned)
		var coins0 := int(s.coins)
		var orders0 := int(s.stats.orders_done)
		var sat := false
		for o in s.orders:
			if Orders.satisfiable(s, o):
				sat = true
		if sat:
			r.sat_days += 1
		_fulfil(s, r)
		_buy_stock(s, r)
		_garden(s)
		if day >= 2:
			_forage(s, r)
		Forage.empty_bag_to_inbox(s)
		var jars0 := int(s.stats.jars_made)
		_cook_loop(s, r)
		if int(s.stats.jars_made) > jars0:
			r.cook_days += 1
		_fulfil(s, r)
		_letters(s, r)
		_gifts(s, r)
		_market(s, r)
		_sell_surplus(s, r)
		_arrange(s)
		_buy_upgrades(s, r, day)
		_note_unlocks(s, r, day)
		if int(s.stats.orders_done) > orders0:
			r.done_days += 1
		r.unused += int(s.energy)
		r.earned.append(int(s.stats.coins_earned) - earned0)
		r.net.append(int(s.coins) - coins0)
		r.bank.append(int(s.coins))
		var ev := DayEnd.run(s)
		for e in ev:
			if e.type == "spoiled":
				r.composted += int(e.item.get("count", 1))
				if e.item.kind == "product":
					r.stale += 1
			elif e.type == "energy":
				r.stars[clampi(int(e.stars), 0, 3)] += 1
	r.orders_done = int(s.stats.orders_done)
	r.variants = s.book.variants.size()
	r.found = s.found_varieties.size()
	r.final_coins = int(s.coins)
	r.jars = int(s.stats.jars_made)
	r.recipes_made = r.kinds.size()
	r.family_unlocked = Letters.ensure(s).unlocked_recipes.size()
	if OS.get_cmdline_user_args().has("--dbg"):
		for lt in Letters.ensure(s).inbox:
			print(sd, lt.kind, lt.from, lt.day, lt.get("done"), lt.get("request"))
		print(sd, "love", Letters.ensure(s).love, "kid dislikes", Letters.kid_info("mia").get("dislikes_group"), Letters.kid_info("leo").get("dislikes_group"))
	return r


func _note_unlocks(s: Dictionary, r: Dictionary, day: int) -> void:
	for id in ["knead", "vineyard"]:
		if Economy.unlocked(s, id) and not r.unlock_day.has(id):
			r.unlock_day[id] = day
	var n: int = Letters.ensure(s).unlocked_recipes.size()
	while r.family_days.size() < n:
		r.family_days.append(day)


# ---------------------------------------------------------------- orders / selling

func _ready_product(item: Dictionary) -> bool:
	return item.kind == "product" and int(item.get("wait_left", 0)) <= 0


func _find_items(s: Dictionary) -> Array:
	var out: Array = []
	for where in ["inbox", "pantry"]:
		var list: Array = s.pantry.items if where == "pantry" else s.inbox
		for i in list.size():
			var item: Dictionary = list[i].item if where == "pantry" else list[i]
			if item.kind == "product":
				out.append({"ref": {"where": where, "index": i}, "item": item})
	return out


func _value(s: Dictionary, item: Dictionary) -> int:
	return ProductGen.value(item.key, s.varieties, int(item.q))


func _fulfil(s: Dictionary, r: Dictionary) -> void:
	var again := true
	while again:
		again = false
		var items := _find_items(s)
		for o in s.orders:
			var best := {}
			var best_v := 1 << 30
			for c in items:
				if Orders.matches(o, c.item, s.varieties):
					var v := _value(s, c.item)
					if v < best_v:
						best_v = v
						best = c
			if not best.is_empty():
				var res := Orders.fulfill(s, int(o.id), best.ref)
				if res.ok:
					r.order_coins += int(res.coins)
					again = true
					break


## Days until the next market (0 on a market day).
func _days_to_market(s: Dictionary) -> int:
	return (Market.EVERY - int(s.day) % Market.EVERY) % Market.EVERY


func _sell_surplus(s: Dictionary, r: Dictionary) -> void:
	# Keep the best jars (waiting ones count), sell the rest of the inbox. Before a market keep many.
	var keep_n := KEEP_MARKET if _days_to_market(s) in [1, 2] else KEEP_PRODUCTS
	var prods := _find_items(s)
	var vals: Array = []
	for c in prods:
		vals.append(_value(s, c.item))
	vals.sort()
	vals.reverse()
	var cut := int(vals[keep_n - 1]) if vals.size() >= keep_n else -1
	var kept := 0
	for i in range(s.inbox.size() - 1, -1, -1):
		var item: Dictionary = s.inbox[i]
		var sell := false
		match item.kind:
			"product":
				var v := _value(s, item)
				if int(item.get("wait_left", 0)) > 0:
					pass  # still maturing: it goes to the pantry, never to the grocer
				elif v >= cut and kept < keep_n and cut >= 0:
					kept += 1
				else:
					sell = true
			"fresh":
				sell = int(item.days_left) < 3
			"nut":
				sell = int(item.count) > 6
		if sell:
			var res := Economy.sell(s, {"where": "inbox", "index": i})
			if res.ok:
				r.sell_coins += int(res.coins)
	# Pies and bread go stale in a day or two: sell them rather than compost them.
	for where in ["pantry", "inbox"]:
		var list: Array = s.pantry.items if where == "pantry" else s.inbox
		for i in range(list.size() - 1, -1, -1):
			var item: Dictionary = list[i].item if where == "pantry" else list[i]
			if item.kind == "product" and _ready_product(item) and int(item.get("days_left", -1)) >= 0 and int(item.days_left) <= 1:
				var res := Economy.sell(s, {"where": where, "index": i})
				if res.ok:
					r.sell_coins += int(res.coins)


## Re-shelves the whole pantry every evening: maturing jars first (they only count down in their own zone), then ready
## jars, nuts and fresh food (kinds together). Whatever does not fit is sold to the grocer.
func _arrange(s: Dictionary) -> void:
	var all: Array = s.inbox.duplicate(true)
	for e in s.pantry.items:
		all.append(e.item)
	var rank := func(it: Dictionary) -> int:
		if it.kind == "product":
			return 0 if int(it.get("wait_left", 0)) > 0 else 1
		return 2 if it.kind == "nut" else 3
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: int = rank.call(a)
		var rb: int = rank.call(b)
		if ra != rb:
			return ra < rb
		return State.item_type(a) < State.item_type(b))
	s.inbox = []
	s.pantry.items = []
	var left := PantryRules.auto_arrange(s.pantry, all)
	for item in left:
		s.inbox.append(item)
		Economy.sell(s, {"where": "inbox", "index": s.inbox.size() - 1})


## Buys upgrades in BUY_ORDER; strict, so the bot saves for the first one still on the list. Margin SHELF_MARGIN.
func _buy_upgrades(s: Dictionary, r: Dictionary, day: int) -> void:
	var seen := {}
	for id in BUY_ORDER:
		seen[id] = int(seen.get(id, 0)) + 1
		var level := int(s.upgrades.get(id, 0))
		if level >= int(seen[id]):
			continue
		var p := Economy.price(s, id)
		if p < 0:
			continue
		if int(s.coins) < p + SHELF_MARGIN:
			return
		if Economy.buy(s, id).ok:
			r.spent_up += p
			r.buy_day["%s#%d" % [id, level + 1]] = day


func _buy_stock(s: Dictionary, r: Dictionary) -> void:
	var targets := {"jar": BASE_STOCK + (4 if Economy.unlocked(s, "big_pot") else 2), "sugar": BASE_STOCK, "salt": BASE_STOCK, "vinegar": BASE_STOCK}
	if Economy.unlocked(s, "press"):
		targets["bottle"] = 6
	if Economy.unlocked(s, "knead"):
		targets["flour"] = 8
	for id in targets:
		var need := int(targets[id]) - int(s.cupboard.get(id, 0))
		if need > 0:
			var p := Economy.price(s, id, need)
			if p > 0 and int(s.coins) - p >= 15:
				if Economy.buy(s, id, need).ok:
					r.spent_stock += p


# ---------------------------------------------------------------- gifts, letters, market

## Gift the cheapest liked jar (not one an open order wants) to each neighbour whose reward is still ahead.
func _gifts(s: Dictionary, r: Dictionary) -> void:
	for npc in GIFT_NPCS:
		var want := false
		match npc:
			"baker":
				want = not Economy.unlocked(s, "knead")
			"vintner":
				want = not Economy.unlocked(s, "vineyard")
			"grocer":
				want = Economy.hearts(s, "grocer") < 3
			"postman":
				want = Economy.hearts(s, "postman") < 2
		if not want:
			continue
		var best := {}
		var best_v := 1 << 30
		for c in _find_items(s):
			if not _ready_product(c.item) or Economy.gift_points(npc, ProductGen.taste(c.item.key, s.varieties)) <= 0:
				continue
			var wanted := false
			for o in s.orders:
				if Orders.matches(o, c.item, s.varieties):
					wanted = true
			var v := _value(s, c.item)
			if not wanted and v < best_v:
				best_v = v
				best = c
		if not best.is_empty() and Economy.gift(s, npc, best.ref).ok:
			r.gifts += 1


## First free {"cell","rot"} in the 3x2 parcel box, {} when the item does not fit.
func _box_spot(entries: Array, item: Dictionary) -> Dictionary:
	var b := Letters.box_board()
	for x in Letters.BOX_COLS:
		for y in Letters.BOX_ROWS:
			for rot in ([0, 1] if PantryRules.can_rotate(item) else [0]):
				if PantryRules.can_place(b, entries, item, Vector2i(x, y), rot):
					return {"cell": Vector2i(x, y), "rot": rot}
	return {}


## Answers every open request letter it can fully meet: cheapest matching jars, plus the cheapest surprise jar and
## straw for the care bonus when that jar is worth no more than 60 coins.
func _letters(s: Dictionary, r: Dictionary) -> void:
	var l := Letters.ensure(s)
	for letter in l.inbox:
		if String(letter.kind) != "request" or bool(letter.get("done", false)):
			continue
		var kid := String(letter.from)
		var cands: Array = []
		for c in _find_items(s):
			if Letters.giftable(kid, c.item):
				cands.append(c)
		cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _value(s, a.item) < _value(s, b.item))
		var entries: Array = []
		var used: Array = []
		var ok := true
		for req in letter.request:
			var hit := {}
			for c in cands:
				if used.has(c) or not Letters.item_meets(kid, req, c.item, s.varieties):
					continue
				var spot := _box_spot(entries, c.item)
				if spot.is_empty():
					continue
				entries.append({"item": c.item, "x": spot.cell.x, "y": spot.cell.y, "rot": spot.rot})
				hit = c
				break
			if hit.is_empty():
				ok = false
			else:
				used.append(hit)
		# A stuck letter blocks the next one from that kid: after PARTIAL_AFTER days send whatever matches.
		if not ok and (used.is_empty() or int(s.day) - int(letter.day) < PARTIAL_AFTER):
			continue
		if ok:
			for c in cands:
				if used.has(c) or _value(s, c.item) > 60 or not Letters.is_surprise(kid, c.item, s.varieties):
					continue
				var spot := _box_spot(entries, c.item)
				if not spot.is_empty():
					entries.append({"item": c.item, "x": spot.cell.x, "y": spot.cell.y, "rot": spot.rot})
					used.append(c)
					break
		if ok:
			Letters.fill_straw(entries)
		var res := Letters.pack(s, int(letter.id), entries)
		if res.ok:
			r.letters_sent += 1
			r.letters_hearts += int(res.hearts)


## Weekly market: everything ready goes on the stall through Market.auto_stall.
func _market(s: Dictionary, r: Dictionary) -> void:
	if not Market.can_open(s):
		return
	var items: Array = []
	for src in Market.sources(s):
		items.append(src.item)
	var stall := Market.auto_stall(items, s.varieties)
	var sales := Market.run(s, stall)
	var total := 0
	for sale in sales:
		total += int(sale.price)
	if not stall.is_empty():
		r.market_days += 1
	r.market_coins += total
	r.market_sold += sales.size()


# ---------------------------------------------------------------- garden

func _garden(s: Dictionary) -> void:
	for i in s.garden.trees.size():
		if bool(s.garden.trees[i].fruit) and Garden.bag_free(s) >= 3 and int(s.energy) > COOK_RESERVE + 3:
			Garden.shake_tree(s, i)
	for i in s.garden.beds.size():
		var bed: Dictionary = s.garden.beds[i]
		if String(bed.crop) != "" and int(bed.days_left) <= 0:
			Garden.harvest(s, i)
	var crops: Array = ["cucumber", "pepper"]
	if Economy.price(s, "seed_cabbage") > 0:
		crops.append("cabbage")
	for i in s.garden.beds.size():
		if String(s.garden.beds[i].crop) != "":
			continue
		var crop: String = crops[(i + int(s.day)) % crops.size()]
		if int(s.cupboard.get("seed_" + crop, 0)) < 1:
			var p := Economy.price(s, "seed_" + crop)
			if p < 0 or int(s.coins) - p < 30:
				continue
			Economy.buy(s, "seed_" + crop)
		Garden.plant(s, i, crop, int(s.garden.fertilizer) > 0)


# ---------------------------------------------------------------- forage

## Sources of one map: {variety, kind, id, items, cost}; hives are returned apart (ids).
func _map_sources(map: Dictionary) -> Dictionary:
	var sources: Array = []
	var hives: Array = []
	for p in map.pickups:
		if p.kind == "hive":
			hives.append(int(p.id))
			continue
		if String(p.variety) == "":
			continue
		var bush: bool = p.kind == "bush"
		sources.append({"variety": p.variety, "kind": "pick", "id": int(p.id), "items": 2 if bush else 1, "cost": 2 if bush else 1})
	for t in map.fruit_trees:
		sources.append({"variety": t.variety, "kind": "tree", "id": int(t.id), "items": int(t.get("yield", 2)), "cost": 3})
	return {"sources": sources, "hives": hives}


func _held_supply(s: Dictionary) -> Dictionary:
	var supply := {}
	for list in [s.inbox, s.pantry.items]:
		for e in list:
			var it: Dictionary = e.item if e.has("item") else e
			if it.kind == "fresh":
				supply[it.variety] = float(supply.get(it.variety, 0)) + float(it.count)
	return supply


func _held_fresh(s: Dictionary) -> int:
	var n := 0
	for v in _held_supply(s).values():
		n += int(v)
	return n


func _rare_weight(s: Dictionary, v: String) -> float:
	return 1.0 + (0.5 if s.varieties.get(v, {}).get("rarity", "") != "common" else 0.0)


## How good a map is for the greedy forager: stacks of 3+ of one variety (rare ones weigh more), plus hives.
func _map_score(s: Dictionary, map: Dictionary) -> float:
	var ms := _map_sources(map)
	var supply := _held_supply(s)
	for src in ms.sources:
		supply[src.variety] = float(supply.get(src.variety, 0)) + float(src.items)
	var scores: Array = []
	for v in supply:
		if float(supply[v]) >= 3.0:
			scores.append(minf(float(supply[v]), 8.0) * _rare_weight(s, v))
	scores.sort()
	scores.reverse()
	var total: float = 4.0 * ms.hives.size()
	for i in mini(6, scores.size()):
		total += float(scores[i])
	return total


## Visits every open biome, best map first, until the energy is down to the cooking reserve.
func _forage(s: Dictionary, r: Dictionary) -> void:
	var maps: Array = []
	for b in WildGen.biome_choices(s):
		if not b.open:
			continue
		var map := WildGen.generate(int(s.save_seed), int(s.day), String(b.id), String(s.weather), s.varieties)
		if not map.is_empty():
			maps.append({"biome": String(b.id), "map": map, "score": _map_score(s, map)})
	maps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	for m in maps:
		if int(s.energy) <= COOK_RESERVE or _held_fresh(s) >= FRESH_CAP:
			break
		var e0 := int(s.energy)
		var full := _forage_map(s, m.map)
		if e0 != int(s.energy):
			r.biome_days[m.biome] = int(r.biome_days.get(m.biome, 0)) + 1
		if full:
			break


## Returns true when the bag filled up.
func _forage_map(s: Dictionary, map: Dictionary) -> bool:
	var ms := _map_sources(map)
	var sources: Array = ms.sources
	for id in ms.hives:
		if int(s.energy) - 2 >= COOK_RESERVE:
			Forage.pick(s, map, int(id))
	var supply := _held_supply(s)
	for src in sources:
		supply[src.variety] = float(supply.get(src.variety, 0)) + float(src.items)
	var order: Array = supply.keys()
	order.sort_custom(func(a: String, b: String) -> bool: return supply[a] * _rare_weight(s, a) > supply[b] * _rare_weight(s, b))
	var targets := 0
	for v in order:
		if int(s.energy) <= COOK_RESERVE or _held_fresh(s) >= FRESH_CAP:
			break
		if targets >= 6 or float(supply[v]) < 3.0:
			break
		targets += 1
		var mine := sources.filter(func(x: Dictionary) -> bool: return x.variety == v)
		mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.items) / a.cost > float(b.items) / b.cost)
		for src in mine:
			if int(s.energy) - int(src.cost) < COOK_RESERVE or _held_fresh(s) >= FRESH_CAP:
				continue
			var res: Dictionary
			if src.kind == "tree":
				res = Forage.shake_tree(s, map, int(src.id))
			else:
				res = Forage.pick(s, map, int(src.id))
			if not res.ok and res.reason == "UI_BAG_FULL":
				return true
	return false


# ---------------------------------------------------------------- cooking

func _stock_counts(s: Dictionary) -> Dictionary:
	var c := {}
	for list in [s.inbox, s.pantry.items]:
		for e in list:
			var it: Dictionary = e.item if e.has("item") else e
			if it.kind == "fresh":
				c[it.variety] = int(c.get(it.variety, 0)) + int(it.count)
			elif it.kind == "nut":
				c[it.type] = int(c.get(it.type, 0)) + int(it.count)
	return c


func _slot_ok(slot: Dictionary, vid: String, s: Dictionary) -> bool:
	var type := String(s.varieties[vid].type)
	if slot.has("types"):
		return slot.types.has(type)
	if slot.has("groups"):
		return slot.groups.has(String(Data.ingredients().get(type, {}).get("group", "")))
	return false


func _cook_loop(s: Dictionary, r: Dictionary) -> void:
	for guard in 12:
		_buy_stock(s, r)
		var pick := _best_cook(s)
		if pick.is_empty():
			return
		var mult := int(pick.mult)
		if pick.addin != "" and Data.addins()[pick.addin].kind != "nut":
			var short := mult - int(s.cupboard.get(pick.addin, 0))
			if short > 0:
				var p := Economy.price(s, pick.addin, short)
				if p < 0 or not Economy.buy(s, pick.addin, short).ok:
					return
				r.spent_stock += p
		var res := Kitchen.cook_n(s, pick.recipe, pick.main, pick.second, pick.addin, QUALITY, mult)
		if not res.ok:
			return
		r.kinds[pick.recipe] = int(r.kinds.get(pick.recipe, 0)) + mult
		if mult > 1:
			r.big_pot_cooks += 1
		r.jar_value += ProductGen.value(res.item.key, s.varieties, QUALITY) * mult
		_fulfil(s, r)


## Request items of the open letters that no held jar meets yet: [{kid, req}].
func _open_requests(s: Dictionary, held: Array) -> Array:
	var out: Array = []
	var l := Letters.ensure(s)
	for letter in l.inbox:
		if String(letter.kind) != "request" or bool(letter.get("done", false)):
			continue
		for req in letter.request:
			var covered := false
			for h in held:
				if Letters.meets(req, State.item_type(h.item), ProductGen.taste(String(h.item.key), s.varieties)) \
						and not Letters.dislikes(String(letter.from), String(h.item.key)):
					covered = true
			if not covered:
				out.append({"kid": String(letter.from), "req": req})
	return out


## Grocer price of the cupboard bases (jar, sugar, flour ...) one cook of `mult` pots uses.
func _base_cost(rec: Dictionary, mult: int) -> float:
	var t := 0.0
	var base: Dictionary = rec.get("base", {})
	for id in base:
		var p: Variant = Data.shop().buy.get(id)
		if typeof(p) == TYPE_DICTIONARY:
			p = p.price
		t += float(p if p != null else 0) * float(base[id]) * mult
	return t


func _best_cook(s: Dictionary) -> Dictionary:
	var stock := _stock_counts(s)
	var recipes := Data.recipes()
	var held := _find_items(s)
	var open_reqs := _open_requests(s, held)
	var market_soon := _days_to_market(s) <= 3
	var best := {}
	var best_score := 0.0
	var reward_mult := float(Data.rules().orders.reward_mult)
	for rid in recipes:
		if not Kitchen.available(s, rid):
			continue
		var rec: Dictionary = recipes[rid]
		var cost := Economy.energy_cost(String(rec.method))
		if cost <= 0 or int(s.energy) < cost:
			continue
		var fixed: Variant = Kitchen.fixed_addin(rid)
		var addin_list: Array = []
		if fixed != null:
			addin_list = [String(fixed)]
		else:
			addin_list = [""]
			for a in Data.addins():
				var ad: Dictionary = Data.addins()[a]
				if ad.source == "shop" or int(s.cupboard.get(a, 0)) > 0 or (ad.kind == "nut" and int(stock.get(a, 0)) > 0):
					addin_list.append(a)
		var max_mult := Kitchen.max_mult(s, rid)
		var perishable := int(rec.get("shelf_days", -1)) >= 0
		var main_slot: Variant = rec.get("main")
		for mult in range(max_mult, 0, -1):
			var mains: Array = [""]
			if typeof(main_slot) == TYPE_DICTIONARY:
				mains = []
				if main_slot.has("recipe"):
					var ps := Kitchen.product_stock(s, String(main_slot.recipe))
					for v in ps:
						if int(ps[v]) >= int(main_slot.count) * mult:
							mains.append(v)
				else:
					for v in stock:
						if s.varieties.has(v) and _slot_ok(main_slot, v, s) and int(stock[v]) >= int(main_slot.count) * mult:
							mains.append(v)
			var seconds: Array = [""]
			if rec.has("second"):
				seconds = []
				for v in stock:
					if s.varieties.has(v) and _slot_ok(rec.second, v, s) and int(stock[v]) >= int(rec.second.count) * mult:
						seconds.append(v)
			for m in mains:
				for sec in seconds:
					for a in addin_list:
						var key := Kitchen.product_key(rid, m, sec, a)
						var cost_coins := 0
						if a != "" and Data.addins()[a].kind != "nut" and int(s.cupboard.get(a, 0)) < mult:
							cost_coins = int(Data.addins()[a].price) * (mult - int(s.cupboard.get(a, 0)))
							if int(s.coins) < cost_coins + 10:
								continue
						var taste := ProductGen.taste(key, s.varieties)
						var harm := ProductGen.harmony(taste)
						var value := float(ProductGen.value(key, s.varieties, QUALITY))
						var base_cost := _base_cost(rec, mult)
						var score := (value * mult - base_cost) / float(cost)
						var wanted := false
						if perishable and not market_soon:
							score *= 0.6
						for o in s.orders:
							if Orders.meets(o, rid, QUALITY, taste, harm):
								var covered := false
								for h in held:
									if Orders.matches(o, h.item, s.varieties):
										covered = true
								if not covered:
									wanted = true
									score = maxf(score, (value * reward_mult + 25.0) / float(cost) * 1.5)
						for q in open_reqs:
							if Letters.meets(q.req, rid, taste) and not Letters.dislikes(q.kid, key):
								wanted = true
								score = maxf(score, (value + 20.0) / float(cost) * 1.6)
						if not wanted and score < MIN_NET_PER_ENERGY:
							continue
						score -= float(cost_coins) / 20.0
						if score > best_score and Kitchen.check_n(s, rid, m, sec, a, mult).ok:
							best_score = score
							best = {"recipe": rid, "main": m, "second": sec, "addin": a, "mult": mult}
	return best


# ---------------------------------------------------------------- report

func _avg(a: Array, from: int, to: int) -> float:
	var t := 0.0
	var n := 0
	for d in range(from, mini(to, a.size()) + 1):
		t += float(a[d - 1])
		n += 1
	return t / maxf(1.0, float(n))


func _f(x: float) -> String:
	return "%.1f" % x


func _d(x: int) -> String:
	return "-" if x == 0 else str(x)


func _mean(results: Array, fn: Callable) -> float:
	var t := 0.0
	for r in results:
		t += float(fn.call(r))
	return t / float(results.size())


## "day (n/5)": average day of a per-seed day dictionary entry, "-" when never.
func _day_avg(results: Array, dict_name: String, key: String) -> String:
	var t := 0.0
	var c := 0
	for r in results:
		if r[dict_name].has(key):
			t += float(r[dict_name][key])
			c += 1
	return "-" if c == 0 else "%.0f (%d/%d)" % [t / c, c, results.size()]


func _day_only(results: Array, dict_name: String, key: String) -> String:
	return _day_avg(results, dict_name, key).split(" ")[0]


func _summary(results: Array) -> String:
	var up := ""
	for k in UPGRADE_COLS:
		up += " %s=%s" % [k.replace("pantry_row", "shelf"), _day_only(results, "buy_day", k)]
	return "SUMMARY coins/d 1-10 %s 11-30 %s 31-50 %s 51-100 %s final %s (max %s) bank30 %s |%s | knead=%s vineyard=%s | orders %s grocer %s market %s" % [
		_f(_mean(results, func(r): return _avg(r.earned, 1, 10))), _f(_mean(results, func(r): return _avg(r.earned, 11, 30))),
		_f(_mean(results, func(r): return _avg(r.earned, 31, 50))), _f(_mean(results, func(r): return _avg(r.earned, 51, 100))),
		_f(_mean(results, func(r): return r.final_coins)), str(results.map(func(r): return r.final_coins).max()),
		_f(_mean(results, func(r): return r.bank[29])), up,
		_day_only(results, "unlock_day", "knead"), _day_only(results, "unlock_day", "vineyard"),
		_f(_mean(results, func(r): return r.order_coins)), _f(_mean(results, func(r): return r.sell_coins)),
		_f(_mean(results, func(r): return r.market_coins))]


func _report(results: Array) -> String:
	var md := "# Balance report - P1 economy, 100-day greedy bot (QA-BALANCE-P1)\n\n"
	md += "Generated by `godot --headless --path game -s res://tests/sim_bot.gd`. Seeds: %s. Assumed cook quality: %d stars (no mini-games).\n\n" % [str(SEEDS), QUALITY]
	md += "Policy: forage every open biome, best map first (hives, then the best-supplied varieties), down to %d energy; tend the garden (cucumber, pepper, cabbage); " % COOK_RESERVE
	md += "cook the best order or letter match, else best value per energy, over every available recipe (big pot x2, family recipes, press and dough board once unlocked); "
	md += "fulfil orders; gift the cheapest liked jar to the baker, vintner, grocer and postman until their reward; answer each grandchild letter with matching jars "
	md += "(plus a surprise jar and straw for the care bonus); on market day put every ready jar on `Market.auto_stall` (%d jars are kept on the two days before); " % KEEP_MARKET
	md += "sell the rest of the day's jars above %d to the grocer; auto-arrange; buy upgrades strictly in the order %s when coins >= price + %d.\n\n" % [KEEP_PRODUCTS, str(BUY_ORDER), SHELF_MARGIN]
	md += "Coins per day = coins earned (orders + grocer + market) per day, before spending. Bank = coins in the purse at the end of a day.\n\n"
	md += "### Economy per seed\n\n"
	md += "| seed | coins/d 1-10 | 11-30 | 31-50 | 51-100 | net/d 51-100 | bank d30 | bank d60 | final coins | orders done | letters sent | market days | variants | recipes made | energy unused/day |\n"
	md += "|" + "---|".repeat(15) + "\n"
	for r in results:
		md += "| " + " | ".join([str(r.seed), _f(_avg(r.earned, 1, 10)), _f(_avg(r.earned, 11, 30)), _f(_avg(r.earned, 31, 50)), _f(_avg(r.earned, 51, 100)),
			_f(_avg(r.net, 51, 100)), str(r.bank[29]), str(r.bank[59]), str(r.final_coins), str(r.orders_done), str(r.letters_sent),
			str(r.market_days), str(r.variants), "%d/%d" % [r.recipes_made, Data.recipes().size()], _f(float(r.unused) / DAYS)]) + " |\n"
	md += "| **avg** | " + " | ".join([_f(_mean(results, func(r): return _avg(r.earned, 1, 10))), _f(_mean(results, func(r): return _avg(r.earned, 11, 30))),
		_f(_mean(results, func(r): return _avg(r.earned, 31, 50))), _f(_mean(results, func(r): return _avg(r.earned, 51, 100))),
		_f(_mean(results, func(r): return _avg(r.net, 51, 100))), _f(_mean(results, func(r): return r.bank[29])), _f(_mean(results, func(r): return r.bank[59])),
		_f(_mean(results, func(r): return r.final_coins)), _f(_mean(results, func(r): return r.orders_done)), _f(_mean(results, func(r): return r.letters_sent)),
		_f(_mean(results, func(r): return r.market_days)), _f(_mean(results, func(r): return r.variants)), _f(_mean(results, func(r): return r.recipes_made)),
		_f(_mean(results, func(r): return float(r.unused) / DAYS))]) + " |\n"
	md += "\n### When each upgrade is bought (day; the average leaves out seeds that never bought it)\n\n"
	md += "| seed | press | shelf 1 | beds | bag 1 | boots | shelf 2 | big pot | bag 2 | shelf 3 | dough board | vineyard |\n"
	md += "|" + "---|".repeat(12) + "\n"
	for r in results:
		var row := [str(r.seed)]
		for c in UPGRADE_COLS:
			row.append(_d(int(r.buy_day.get(c, 0))))
		row.append(_d(int(r.unlock_day.get("knead", 0))))
		row.append(_d(int(r.unlock_day.get("vineyard", 0))))
		md += "| " + " | ".join(row) + " |\n"
	var avg_row := ["**avg**"]
	for c in UPGRADE_COLS:
		avg_row.append(_day_avg(results, "buy_day", c))
	avg_row.append(_day_avg(results, "unlock_day", "knead"))
	avg_row.append(_day_avg(results, "unlock_day", "vineyard"))
	md += "| " + " | ".join(avg_row) + " |\n"
	var order_c: float = _mean(results, func(r): return r.order_coins)
	var sell_c: float = _mean(results, func(r): return r.sell_coins)
	var market_c: float = _mean(results, func(r): return r.market_coins)
	var total: float = maxf(1.0, order_c + sell_c + market_c)
	md += "\n### Income split (avg per seed)\n\n"
	md += "| source | coins | share |\n|---|---|---|\n"
	md += "| orders | %s | %s%% |\n| grocer sales | %s | %s%% |\n| weekly market | %s | %s%% |\n" % [
		_f(order_c), _f(100.0 * order_c / total), _f(sell_c), _f(100.0 * sell_c / total), _f(market_c), _f(100.0 * market_c / total)]
	md += "\nSpent per seed: upgrades %s, grocer stock and add-ins %s. Market: %s jars sold over %s market days (%s coins per jar). " % [
		_f(_mean(results, func(r): return r.spent_up)), _f(_mean(results, func(r): return r.spent_stock)),
		_f(_mean(results, func(r): return r.market_sold)), _f(_mean(results, func(r): return r.market_days)),
		_f(market_c / maxf(1.0, _mean(results, func(r): return r.market_sold)))]
	md += "Letters answered %s (%s love in total), family recipes unlocked %s of %d (unlock days per seed %s). Gifts given %s.\n" % [
		_f(_mean(results, func(r): return r.letters_sent)), _f(_mean(results, func(r): return r.letters_hearts)),
		_f(_mean(results, func(r): return r.family_unlocked)), Kitchen.family_ids().size(),
		str(results.map(func(r): return r.family_days)), _f(_mean(results, func(r): return r.gifts))]
	var kinds := {}
	var biomes := {}
	for r in results:
		for k in r.kinds:
			kinds[k] = int(kinds.get(k, 0)) + int(r.kinds[k])
		for b in r.biome_days:
			biomes[b] = int(biomes.get(b, 0)) + int(r.biome_days[b])
	md += "\nJars per day %s, average jar value %s coins, days with at least one cook %s, jar stacks lost to staleness %s per seed, spoiled units %s per seed, big-pot cooks %s per seed.\n" % [
		_f(_mean(results, func(r): return float(r.jars) / DAYS)), _f(_mean(results, func(r): return float(r.jar_value) / maxf(1.0, r.jars))),
		_f(_mean(results, func(r): return float(r.cook_days))), _f(_mean(results, func(r): return r.stale)),
		_f(_mean(results, func(r): return r.composted)), _f(_mean(results, func(r): return r.big_pot_cooks))]
	md += "\nJars cooked by recipe (all seeds): %s.\n\nForaging days per biome (all seeds, 500 days): %s.\n" % [str(kinds), str(biomes)]
	md += "\n" + _kept_p1_notes()
	md += "\n---\n\n" + _kept_p0()
	return md


func _old_report() -> String:
	var path := ProjectSettings.globalize_path("res://").path_join("../docs/qa/balance.md")
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


## The hand-written P1 notes survive a re-run: from NOTES_HEADING up to the "---" that precedes the P0 report.
func _kept_p1_notes() -> String:
	var old := _old_report()
	var i := old.find(NOTES_HEADING)
	if i >= 0:
		var j := old.find("\n---\n", i)
		return (old.substr(i, j - i) if j >= 0 else old.substr(i)).strip_edges() + "\n"
	return NOTES_HEADING + "\n\n(none yet)\n"


## The P0 report (QA-01) stays below the P1 one, untouched.
func _kept_p0() -> String:
	var old := _old_report()
	var i := old.find(P0_HEADING)
	return old.substr(i) if i >= 0 else ""
