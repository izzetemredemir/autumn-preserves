extends SceneTree
## QA-01 · 100-day greedy bot. Plays through the sim API only (no autoloads) and writes docs/qa/balance.md.
##   godot --headless --path game -s res://tests/sim_bot.gd
## Not a unit test (file name does not start with test_). Assumes a cooking quality of QUALITY stars (minigames are not run).

const SEEDS := [1, 7, 42, 4242, 90210]
const DAYS := 100
const QUALITY := 2            # average mini-game result assumed for every cook
const COOK_RESERVE := 21      # energy kept for cooking (three 7-energy cooks)
const KEEP_PRODUCTS := 3      # finished jars kept in stock for future orders
const BASE_STOCK := 4         # target for jar/sugar/salt/vinegar
const SHELF_MARGIN := 40      # coins left after buying a shelf
const NOTES_HEADING := "## Proposed number changes"


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var results: Array = []
	for sd in SEEDS:
		results.append(_play(int(sd)))
	var md := _report(results)
	print(md)
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
	var r := {"seed": sd, "earned": [], "net": [], "orders_done": 0, "sat_days": 0, "done_days": 0, "unused": 0,
		"composted": 0, "stars": [0, 0, 0, 0], "shelf_day": [0, 0, 0], "variants": 0, "found": 0, "total_varieties": s.varieties.size(),
		"kinds": {}, "order_coins": 0, "sell_coins": 0, "jar_value": 0, "no_cook_days": 0, "cook_days": 0}
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
		_buy_stock(s)
		_garden(s)
		if day >= 2:
			_forage(s)
		Forage.empty_bag_to_inbox(s)
		var jars0 := int(s.stats.jars_made)
		_cook_loop(s, r)
		if int(s.stats.jars_made) > jars0:
			r.cook_days += 1
		_fulfil(s, r)
		_sell_surplus(s, r)
		_arrange(s)
		_buy_shelf(s, r, day)
		if int(s.stats.orders_done) > orders0:
			r.done_days += 1
		r.unused += int(s.energy)
		r.earned.append(int(s.stats.coins_earned) - earned0)
		r.net.append(int(s.coins) - coins0)
		var ev := DayEnd.run(s)
		for e in ev:
			if e.type == "spoiled":
				r.composted += int(e.item.get("count", 1))
			elif e.type == "energy":
				r.stars[clampi(int(e.stars), 0, 3)] += 1
	r.orders_done = int(s.stats.orders_done)
	r.variants = s.book.variants.size()
	r.found = s.found_varieties.size()
	r.final_coins = int(s.coins)
	r.jars = int(s.stats.jars_made)
	return r


# ---------------------------------------------------------------- orders / selling

func _find_items(s: Dictionary) -> Array:
	var out: Array = []
	for where in ["inbox", "pantry"]:
		var list: Array = s.pantry.items if where == "pantry" else s.inbox
		for i in list.size():
			var item: Dictionary = list[i].item if where == "pantry" else list[i]
			if item.kind == "product":
				out.append({"ref": {"where": where, "index": i}, "item": item})
	return out


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
					var v := ProductGen.value(c.item.key, s.varieties, int(c.item.q))
					if v < best_v:
						best_v = v
						best = c
			if not best.is_empty():
				var res := Orders.fulfill(s, int(o.id), best.ref)
				if res.ok:
					r.order_coins += int(res.coins)
					again = true
					break


func _sell_surplus(s: Dictionary, r: Dictionary) -> void:
	# Keep the KEEP_PRODUCTS most valuable products (waiting ones count), sell the rest of the inbox.
	var prods := _find_items(s)
	var vals: Array = []
	for c in prods:
		vals.append(ProductGen.value(c.item.key, s.varieties, int(c.item.q)))
	vals.sort()
	vals.reverse()
	var cut := int(vals[KEEP_PRODUCTS - 1]) if vals.size() >= KEEP_PRODUCTS else -1
	var kept := 0
	for i in range(s.inbox.size() - 1, -1, -1):
		var item: Dictionary = s.inbox[i]
		var sell := false
		match item.kind:
			"product":
				var v := ProductGen.value(item.key, s.varieties, int(item.q))
				if v >= cut and kept < KEEP_PRODUCTS and cut >= 0:
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


func _arrange(s: Dictionary) -> void:
	var incoming: Array = s.inbox.duplicate(true)
	s.inbox = []
	var left := PantryRules.auto_arrange(s.pantry, incoming)
	for item in left:
		s.inbox.append(item)
		Economy.sell(s, {"where": "inbox", "index": s.inbox.size() - 1})


func _buy_shelf(s: Dictionary, r: Dictionary, day: int) -> void:
	var lvl := int(s.upgrades.pantry_row)
	var p := Economy.price(s, "pantry_row")
	if p > 0 and int(s.coins) >= p + SHELF_MARGIN:
		if Economy.buy(s, "pantry_row").ok:
			r.shelf_day[lvl] = day


func _buy_stock(s: Dictionary) -> void:
	for id in ["jar", "sugar", "salt", "vinegar"]:
		var need := BASE_STOCK - int(s.cupboard.get(id, 0))
		if need > 0:
			var p := Economy.price(s, id, need)
			if p > 0 and int(s.coins) - p >= 15:
				Economy.buy(s, id, need)


# ---------------------------------------------------------------- garden

func _garden(s: Dictionary) -> void:
	for i in s.garden.trees.size():
		if bool(s.garden.trees[i].fruit) and Garden.bag_free(s) >= 3 and int(s.energy) > COOK_RESERVE + 3:
			Garden.shake_tree(s, i)
	for i in s.garden.beds.size():
		var bed: Dictionary = s.garden.beds[i]
		if String(bed.crop) != "" and int(bed.days_left) <= 0:
			Garden.harvest(s, i)
	for i in s.garden.beds.size():
		if String(s.garden.beds[i].crop) != "":
			continue
		var crop := "cucumber" if (i + int(s.day)) % 2 == 0 else "pepper"
		if int(s.cupboard.get("seed_" + crop, 0)) < 1:
			var p := Economy.price(s, "seed_" + crop)
			if p < 0 or int(s.coins) - p < 30:
				continue
			Economy.buy(s, "seed_" + crop)
		Garden.plant(s, i, crop, int(s.garden.fertilizer) > 0)


# ---------------------------------------------------------------- forage

func _forage(s: Dictionary) -> void:
	var map := WildGen.generate(int(s.save_seed), int(s.day), "forest", String(s.weather), s.varieties)
	if map.is_empty():
		return
	var sources: Array = []  # {variety, kind, id, items, cost}
	for p in map.pickups:
		var bush: bool = p.kind == "bush"
		sources.append({"variety": p.variety, "kind": "pick", "id": int(p.id), "items": 2 if bush else 1, "cost": 2 if bush else 1})
	for t in map.fruit_trees:
		sources.append({"variety": t.variety, "kind": "tree", "id": int(t.id), "items": int(t.get("yield", 2)), "cost": 3})
	# Supply per variety (+ what we already hold); gather the best-supplied varieties first, rare ones weigh more.
	var supply := {}
	for src in sources:
		supply[src.variety] = float(supply.get(src.variety, 0)) + float(src.items)
	for list in [s.inbox, s.pantry.items]:
		for e in list:
			var it: Dictionary = e.item if e.has("item") else e
			if it.kind == "fresh":
				supply[it.variety] = float(supply.get(it.variety, 0)) + float(it.count)
	var order: Array = supply.keys()
	order.sort_custom(func(a: String, b: String) -> bool:
		var ra := 1.0 + (0.5 if s.varieties.get(a, {}).get("rarity", "") != "common" else 0.0)
		var rb := 1.0 + (0.5 if s.varieties.get(b, {}).get("rarity", "") != "common" else 0.0)
		return supply[a] * ra > supply[b] * rb)
	var targets := 0
	for v in order:
		if int(s.energy) <= COOK_RESERVE:
			break
		if targets >= 6 or float(supply[v]) < 3.0:
			break
		targets += 1
		var mine := sources.filter(func(x: Dictionary) -> bool: return x.variety == v)
		mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.items) / a.cost > float(b.items) / b.cost)
		for src in mine:
			if int(s.energy) - int(src.cost) < COOK_RESERVE:
				continue
			var res: Dictionary
			if src.kind == "tree":
				res = Forage.shake_tree(s, map, int(src.id))
			else:
				res = Forage.pick(s, map, int(src.id))
			if not res.ok and res.reason == "UI_BAG_FULL":
				return


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
		var pick := _best_cook(s)
		if pick.is_empty():
			return
		if pick.addin != "" and Data.addins()[pick.addin].kind != "nut" and int(s.cupboard.get(pick.addin, 0)) < 1:
			if not Economy.buy(s, pick.addin).ok:
				return
		var res := Kitchen.cook(s, pick.recipe, pick.main, pick.second, pick.addin, QUALITY)
		if not res.ok:
			return
		r.kinds[pick.recipe] = int(r.kinds.get(pick.recipe, 0)) + 1
		r.jar_value += ProductGen.value(res.item.key, s.varieties, QUALITY)
		_fulfil(s, r)


func _best_cook(s: Dictionary) -> Dictionary:
	var stock := _stock_counts(s)
	var recipes := Data.recipes()
	var addin_list: Array = [""]
	for a in Data.ids_up_to("addins", 0):
		var ad: Dictionary = Data.addins()[a]
		if ad.source == "shop" or (ad.kind == "nut" and int(stock.get(a, 0)) > 0):
			addin_list.append(a)
	var held := _find_items(s)
	var best := {}
	var best_score := 0.0
	var reward_mult := float(Data.rules().orders.reward_mult)
	for rid in Data.ids_up_to("recipes", 0):
		var rec: Dictionary = recipes[rid]
		if typeof(rec.get("main")) != TYPE_DICTIONARY:
			continue
		var cost := Economy.energy_cost(String(rec.method))
		if cost <= 0 or int(s.energy) < cost:
			continue
		var mains: Array = []
		for v in stock:
			if s.varieties.has(v) and _slot_ok(rec.main, v, s) and int(stock[v]) >= int(rec.main.count):
				mains.append(v)
		var seconds: Array = [""]
		if rec.has("second"):
			seconds = []
			for v in stock:
				if s.varieties.has(v) and _slot_ok(rec.second, v, s) and int(stock[v]) >= int(rec.second.count):
					seconds.append(v)
		for m in mains:
			for sec in seconds:
				for a in addin_list:
					var key := ProductGen.make_key(rid, [m] if sec == "" else [m, sec], a)
					var cost_coins := 0
					if a != "" and Data.addins()[a].kind != "nut" and int(s.cupboard.get(a, 0)) < 1:
						cost_coins = int(Data.addins()[a].price)
						if int(s.coins) < cost_coins + 10:
							continue
					var chk := Kitchen.check(s, rid, m, sec, a)
					if not chk.ok:
						continue
					var taste := ProductGen.taste(key, s.varieties)
					var harm := ProductGen.harmony(taste)
					var value := float(ProductGen.value(key, s.varieties, QUALITY))
					var score := value / float(cost)
					for o in s.orders:
						if Orders.meets(o, rid, QUALITY, taste, harm):
							var covered := false
							for h in held:
								if Orders.matches(o, h.item, s.varieties):
									covered = true
							if not covered:
								score = maxf(score, (value * reward_mult + 25.0) / float(cost) * 1.5)
					score -= float(cost_coins) / 20.0
					if score > best_score:
						best_score = score
						best = {"recipe": rid, "main": m, "second": sec, "addin": a}
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


func _shelf_avg(results: Array, i: int) -> String:
	var t := 0.0
	var c := 0
	for r in results:
		if int(r.shelf_day[i]) > 0:
			t += float(r.shelf_day[i])
			c += 1
	return "-" if c == 0 else "%.0f (%d/%d seeds)" % [t / c, c, results.size()]


func _report(results: Array) -> String:
	var md := "# Balance report - 100-day greedy bot (QA-01)\n\n"
	md += "Generated by `godot --headless --path game -s res://tests/sim_bot.gd`. Seeds: %s. Assumed cook quality: %d stars (no mini-games).\n" % [str(SEEDS), QUALITY]
	md += "Policy: forage the forest (best-supplied varieties first) down to %d energy, tend the garden, cook the best order match else best value per energy, " % COOK_RESERVE
	md += "fulfil orders, sell surplus above %d jars, auto-arrange, buy a shelf when coins >= price + %d.\n\n" % [KEEP_PRODUCTS, SHELF_MARGIN]
	md += "Coins per day = coins earned (orders + sales) per day, before spending. Net = change in the purse.\n\n"
	md += "| seed | coins/d 1-10 | 11-50 | 51-100 | net/d 51-100 | orders done | days w/ satisfiable order | days w/ order done | varieties found | variants made | shelf 1 day | shelf 2 day | shelf 3 day | energy unused/day | composted | stars 0/1/2/3 (days) | final coins |\n"
	md += "|" + "---|".repeat(17) + "\n"
	for r in results:
		var row := [str(r.seed), _f(_avg(r.earned, 1, 10)), _f(_avg(r.earned, 11, 50)), _f(_avg(r.earned, 51, 100)), _f(_avg(r.net, 51, 100)),
			str(r.orders_done), _f(100.0 * r.sat_days / DAYS) + "%", _f(100.0 * r.done_days / DAYS) + "%",
			"%d/%d" % [r.found, r.total_varieties], str(r.variants),
			_d(r.shelf_day[0]), _d(r.shelf_day[1]), _d(r.shelf_day[2]), _f(float(r.unused) / DAYS), str(r.composted),
			"%d/%d/%d/%d" % r.stars, str(r.final_coins)]
		md += "| " + " | ".join(row) + " |\n"
	var star_sum := [0, 0, 0, 0]
	for r in results:
		for i in 4:
			star_sum[i] += int(r.stars[i])
	var avg_row := [
		"**avg**",
		_f(_mean(results, func(r): return _avg(r.earned, 1, 10))),
		_f(_mean(results, func(r): return _avg(r.earned, 11, 50))),
		_f(_mean(results, func(r): return _avg(r.earned, 51, 100))),
		_f(_mean(results, func(r): return _avg(r.net, 51, 100))),
		_f(_mean(results, func(r): return r.orders_done)),
		_f(_mean(results, func(r): return 100.0 * r.sat_days / DAYS)) + "%",
		_f(_mean(results, func(r): return 100.0 * r.done_days / DAYS)) + "%",
		_f(_mean(results, func(r): return r.found)),
		_f(_mean(results, func(r): return r.variants)),
		_shelf_avg(results, 0), _shelf_avg(results, 1), _shelf_avg(results, 2),
		_f(_mean(results, func(r): return float(r.unused) / DAYS)),
		_f(_mean(results, func(r): return r.composted)),
		"%d/%d/%d/%d" % star_sum,
		_f(_mean(results, func(r): return r.final_coins))]
	md += "| " + " | ".join(avg_row) + " |\n"
	md += "\nIncome split (avg per seed): orders %s coins, grocer sales %s coins. " % [
		_f(_mean(results, func(r): return r.order_coins)), _f(_mean(results, func(r): return r.sell_coins))]
	var kinds := {}
	for r in results:
		for k in r.kinds:
			kinds[k] = int(kinds.get(k, 0)) + int(r.kinds[k])
	md += "Jars per day %s, average jar value %s coins, days with at least one cook %s%%. " % [
		_f(_mean(results, func(r): return float(r.jars) / DAYS)), _f(_mean(results, func(r): return float(r.jar_value) / maxf(1.0, r.jars))),
		_f(_mean(results, func(r): return float(r.cook_days)))]
	md += "Jars cooked by recipe (all seeds): %s.\n" % str(kinds)
	md += "\n" + _kept_notes()
	return md


## The hand-written "Proposed number changes" section of the previous balance.md survives a re-run.
func _kept_notes() -> String:
	var path := ProjectSettings.globalize_path("res://").path_join("../docs/qa/balance.md")
	if FileAccess.file_exists(path):
		var old := FileAccess.get_file_as_string(path)
		var i := old.find(NOTES_HEADING)
		if i >= 0:
			return old.substr(i)
	return NOTES_HEADING + "\n\n(none yet)\n"
