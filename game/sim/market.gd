class_name Market
extends RefCounted
## MARKET · Weekly market (spec §7.7, §4, §8.4). Pure rules: no autoloads, no scenes.
## Every 7th day Granny sets up a 6x2 stall: placement entries {"item","x","y","rot"} whose items are the very product
## Dictionaries of state.inbox / state.pantry (found again by identity). Stream "market" draws the customers; each
## wishes for 1-2 taste axes, carries a budget and a look seed (the scene builds a pixel villager from it).
## Sold products leave the save at full value (ProductGen.value); unsold ones never left the pantry.
## state.market = {"reputation": int, "last_day": int} (missing in old saves: read through info()).

const EVERY := 7
const COLS := 6
const ROWS := 2
const ZONE := "stall"
const MULT_MIN := 1.0
const MULT_MAX := 1.5
## Distinct recipes for the full variety part of the stall score.
const VARIETY_FULL := 4
## Two touching products "go together" when their fill luminance differs by at most this much.
const COLOUR_NEAR := 0.12
const BASE_CUSTOMERS := 8
## Extra customers per reputation point (counted up to REPUTATION_CAP), before the stall multiplier.
const PER_REPUTATION := 1
const REPUTATION_CAP := 8
## A wished axis is met at taste >= WISH_MIN (the order board's axis threshold).
const WISH_MIN := 3
## Wish weights in ProductGen.AXES order: sweet, sour, spicy, salty, earthy.
const AXIS_WEIGHTS := [3, 2, 1, 2, 2]
const TWO_WISH_CHANCE := 0.35
const BUDGET_MIN := 45
const BUDGET_MAX := 125
const BUDGET_PER_REPUTATION := 5
## A fancy customer (top hat in the parade) brings FANCY_MULT times the budget.
const FANCY_CHANCE := 0.15
const FANCY_MULT := 2
## Add-ins with their own "Ooh, <add-in>!" line (MARKET_OOH_<ID>); others fall back to the taste lines.
const OOH_ADDINS := ["honey", "cinnamon", "clove", "ginger", "chili", "walnut", "hazelnut", "chestnut", "thyme", "mint"]
## MARKET_LIKE_<AXIS>_1 .. _N
const LINE_VARIANTS := 2


static func is_market_day(day: int) -> bool:
	return day > 0 and day % EVERY == 0


## {"reputation", "last_day"} without touching the save (old saves have no "market").
static func info(state: Dictionary) -> Dictionary:
	var m: Variant = state.get("market", {})
	if typeof(m) != TYPE_DICTIONARY:
		m = {}
	return {"reputation": int(m.get("reputation", 0)), "last_day": int(m.get("last_day", 0))}


static func ensure(state: Dictionary) -> Dictionary:
	var m: Variant = state.get("market")
	if typeof(m) != TYPE_DICTIONARY:
		m = {}
		state["market"] = m
	if not m.has("reputation"):
		m["reputation"] = 0
	if not m.has("last_day"):
		m["last_day"] = 0
	return m


## Market day and the stall has not opened yet today.
static func can_open(state: Dictionary) -> bool:
	var day := int(state.get("day", 0))
	return is_market_day(day) and int(info(state).last_day) < day


## The 6x2 stall as an ArrangeBoard / PantryRules board.
static func board() -> Dictionary:
	var zones: Array = []
	for i in COLS * ROWS:
		zones.append(ZONE)
	return {"name": "stall", "cols": COLS, "rows": ROWS, "zones": zones}


## Only ready products go on the stall.
static func sellable(item: Dictionary) -> bool:
	return String(item.get("kind", "")) == "product" and int(item.get("wait_left", 0)) <= 0


static func can_place(b: Dictionary, entries: Array, item: Dictionary, cell: Vector2i, rot: int, ignore_index: int = -1) -> bool:
	return sellable(item) and PantryRules.can_place(b, entries, item, cell, rot, ignore_index)


## Ready products Granny can bring: [{"ref", "item"}], inbox first, then the pantry.
static func sources(state: Dictionary) -> Array:
	var out: Array = []
	for i in state.inbox.size():
		if sellable(state.inbox[i]):
			out.append({"ref": {"where": "inbox", "index": i}, "item": state.inbox[i]})
	for i in state.pantry.items.size():
		if sellable(state.pantry.items[i].item):
			out.append({"ref": {"where": "pantry", "index": i}, "item": state.pantry.items[i].item})
	return out


# --- stall score -------------------------------------------------------------------------------------------------

## {"variety", "colour", "fill": 0..1, "mult": MULT_MIN..MULT_MAX}
## variety: distinct recipes / VARIETY_FULL · colour: share of touching product pairs whose fill luminance is within
## COLOUR_NEAR (a sorted, colour-grouped display) · fill: covered cells / 12. mult = 1 + 0.5 * mean of the three.
static func stall_parts(placements: Array, varieties: Dictionary = {}) -> Dictionary:
	var b := board()
	var recipes := {}
	var cells := 0
	var lum: Array = []
	var taken := {}
	for i in placements.size():
		var e: Dictionary = placements[i]
		recipes[State.item_type(e.item)] = true
		lum.append(PantryRules.fill_luminance(ProductGen.describe(String(e.item.get("key", "")), varieties)))
		for c in PantryRules.entry_cells(e):
			if PantryRules.zone_at(b, c) != "" and not taken.has(c):
				taken[c] = i
				cells += 1
	var pairs := {}
	for c: Vector2i in taken:
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = c + d
			if taken.has(n) and int(taken[n]) != int(taken[c]):
				var a := mini(int(taken[c]), int(taken[n]))
				var z := maxi(int(taken[c]), int(taken[n]))
				pairs[Vector2i(a, z)] = true
	var near := 0
	for p: Vector2i in pairs:
		if float(lum[p.x]) >= 0.0 and float(lum[p.y]) >= 0.0 and absf(float(lum[p.x]) - float(lum[p.y])) <= COLOUR_NEAR:
			near += 1
	var variety := minf(1.0, float(recipes.size()) / VARIETY_FULL)
	var colour := float(near) / pairs.size() if not pairs.is_empty() else 0.0
	var fill := float(cells) / (COLS * ROWS)
	var mult := MULT_MIN + (MULT_MAX - MULT_MIN) * (variety + colour + fill) / 3.0
	return {"variety": variety, "colour": colour, "fill": fill, "mult": clampf(mult, MULT_MIN, MULT_MAX)}


## Customer multiplier of a stall, MULT_MIN..MULT_MAX.
static func stall_score(placements: Array, varieties: Dictionary = {}) -> float:
	return float(stall_parts(placements, varieties).mult)


# --- customers ---------------------------------------------------------------------------------------------------

static func customer_count(reputation: int, mult: float) -> int:
	var base := BASE_CUSTOMERS + PER_REPUTATION * clampi(reputation, 0, REPUTATION_CAP)
	return floori(base * clampf(mult, MULT_MIN, MULT_MAX) + 0.000001)


## [{"id", "wants": [1-2 axis ids], "budget", "look": seed, "fancy": bool, "chat": 0..99}] from stream "market".
## Every customer takes the same 7 draws, so a bigger crowd only appends customers (the first ones never change).
static func customers(save_seed: int, day: int, reputation: int, mult: float) -> Array:
	var r := Seeds.rng(save_seed, "market", day)
	var rep := clampi(reputation, 0, REPUTATION_CAP)
	var out: Array = []
	for i in customer_count(reputation, mult):
		var first := Seeds.pick_weighted(r, AXIS_WEIGHTS)
		var two := r.randf() < TWO_WISH_CHANCE
		var rest := AXIS_WEIGHTS.duplicate()
		rest[first] = 0
		var second := Seeds.pick_weighted(r, rest)
		var fancy := r.randf() < FANCY_CHANCE
		var budget := r.randi_range(BUDGET_MIN, BUDGET_MAX) + rep * BUDGET_PER_REPUTATION
		var look := int(r.randi() & 0x7FFFFFFF)
		var chat := r.randi_range(0, 99)
		var wants: Array = [ProductGen.AXES[first]]
		if two:
			wants.append(ProductGen.AXES[second])
		out.append({"id": i, "wants": wants, "budget": budget * (FANCY_MULT if fancy else 1), "look": look,
			"fancy": fancy, "chat": chat})
	return out


# --- the market --------------------------------------------------------------------------------------------------

## What would happen, without changing the save: {"parts", "mult", "customers", "visits", "sales"}.
## visits: one per customer in parade order {"customer", "item" ({} = bought nothing), "price", "line_key", "entry"}.
## sales: the visits with an item. Each customer buys at most one product: the one meeting most of their wishes
## (then the highest taste on them, then the earlier stall cell) that fits the budget.
static func plan(state: Dictionary, stall: Array) -> Dictionary:
	var varieties: Dictionary = state.get("varieties", {})
	var goods := _goods(state, stall)
	var placed: Array = []
	for g in goods:
		placed.append(g.entry)
	var parts := stall_parts(placed, varieties)
	var m := info(state)
	var crowd := customers(int(state.save_seed), int(state.day), int(m.reputation), float(parts.mult))
	var sold := {}
	var visits: Array = []
	var sales: Array = []
	for c in crowd:
		var best := -1
		var best_rank := -1
		var pricey := false
		for j in goods.size():
			if sold.has(j):
				continue
			var t: Array = goods[j].taste
			var met := 0
			var sum := 0
			for a in c.wants:
				var ai := ProductGen.AXES.find(a)
				if int(t[ai]) >= WISH_MIN:
					met += 1
					sum += int(t[ai])
			if met == 0:
				continue
			if int(goods[j].price) > int(c.budget):
				pricey = true
				continue
			var rank := met * 1000 + sum
			if rank > best_rank:
				best_rank = rank
				best = j
		var v := {"customer": c, "item": {}, "price": 0, "line_key": "", "entry": {}}
		if best >= 0:
			sold[best] = true
			var g: Dictionary = goods[best]
			v.item = g.item
			v.price = int(g.price)
			v.entry = g.entry
			v.line_key = _buy_line(c, g)
			sales.append(v)
		else:
			v.line_key = "MARKET_PRICEY" if pricey else "MARKET_WISH_" + String(c.wants[0]).to_upper()
		visits.append(v)
	return {"parts": parts, "mult": float(parts.mult), "customers": crowd, "visits": visits, "sales": sales}


## Opens the stall once on a market day: sold products leave the save, coins at full value, reputation +1,
## last_day = today. Returns the sales [{"customer", "item", "price", "line_key", "entry"}]; [] and no change when
## the market cannot open or the stall holds no ready product of this save.
static func run(state: Dictionary, stall: Array) -> Array:
	if not can_open(state) or _goods(state, stall).is_empty():
		return []
	var p := plan(state, stall)
	var total := 0
	for s in p.sales:
		var ref := _locate(state, s.item)
		if ref.is_empty():
			continue
		State.take(state, ref)
		total += int(s.price)
	Economy.earn(state, total)
	var m := ensure(state)
	m.reputation = int(m.reputation) + 1
	m.last_day = int(state.day)
	return p.sales


## Fills an empty stall from `items` (ready products): recipes taken in turns (dearest first) for variety, then laid
## column by column from light to dark so neighbours match. Returns new entries; `items` is not changed.
static func auto_stall(items: Array, varieties: Dictionary) -> Array:
	var groups := {}
	for it in items:
		if sellable(it):
			var rid := State.item_type(it)
			if not groups.has(rid):
				groups[rid] = []
			groups[rid].append(it)
	var price_of := func(it: Dictionary) -> int: return ProductGen.value(String(it.key), varieties, int(it.q))
	for rid in groups:
		groups[rid].sort_custom(func(a: Dictionary, z: Dictionary) -> bool:
			var pa: int = price_of.call(a)
			var pz: int = price_of.call(z)
			return pa > pz or (pa == pz and String(a.key) < String(z.key)))
	var order: Array = groups.keys()
	order.sort_custom(func(a: String, z: String) -> bool:
		var pa: int = price_of.call(groups[a][0])
		var pz: int = price_of.call(groups[z][0])
		return pa > pz or (pa == pz and a < z))
	var queue: Array = []
	var more := true
	var turn := 0
	while more:
		more = false
		for rid in order:
			if turn < groups[rid].size():
				queue.append(groups[rid][turn])
				more = true
		turn += 1
	var chosen := _pack(queue)
	var picked: Array = []
	for e in chosen:
		picked.append(e.item)
	var lum := {}
	for it in picked:
		lum[String(it.key)] = PantryRules.fill_luminance(ProductGen.describe(String(it.key), varieties))
	var sorted := picked.duplicate()
	sorted.sort_custom(func(a: Dictionary, z: Dictionary) -> bool:
		var la: float = lum[String(a.key)]
		var lz: float = lum[String(z.key)]
		return la > lz or (la == lz and String(a.key) < String(z.key)))
	var tidy := _pack(sorted)
	return tidy if tidy.size() == chosen.size() else chosen


# --- internals ---------------------------------------------------------------------------------------------------

## Valid stall entries in cell order (row by row): ready products that are still in this save, each once, fitting the
## board without overlaps. [{"entry", "item", "price", "taste", "rarity"}]
static func _goods(state: Dictionary, stall: Array) -> Array:
	var entries: Array = stall.duplicate()
	entries.sort_custom(func(a: Dictionary, z: Dictionary) -> bool:
		return int(a.y) < int(z.y) or (int(a.y) == int(z.y) and int(a.x) < int(z.x)))
	var b := board()
	var varieties: Dictionary = state.get("varieties", {})
	var kept: Array = []
	var out: Array = []
	for e in entries:
		var it: Dictionary = e.item
		if not sellable(it) or _locate(state, it).is_empty():
			continue
		var dup := false
		for k in kept:
			dup = dup or is_same(k.item, it)
		if dup or not PantryRules.can_place(b, kept, it, Vector2i(int(e.x), int(e.y)), int(e.get("rot", 0))):
			continue
		kept.append(e)
		var key := String(it.key)
		out.append({"entry": e, "item": it, "price": ProductGen.value(key, varieties, int(it.q)),
			"taste": ProductGen.taste(key, varieties), "rarity": ProductGen.rarity(key, varieties)})
	return out


static func _buy_line(c: Dictionary, g: Dictionary) -> String:
	var addin := String(ProductGen.parse_key(String(g.item.key)).addin)
	if addin in OOH_ADDINS:
		return "MARKET_OOH_" + addin.to_upper()
	if String(g.rarity) != "common":
		return "MARKET_RARE"
	var axis := String(c.wants[0])
	for a in c.wants:
		if int(g.taste[ProductGen.AXES.find(a)]) >= WISH_MIN:
			axis = String(a)
			break
	return "MARKET_LIKE_%s_%d" % [axis.to_upper(), 1 + int(c.chat) % LINE_VARIANTS]


## Ref of the exact item Dictionary in the inbox or the pantry, {} when it is not there.
static func _locate(state: Dictionary, item: Dictionary) -> Dictionary:
	for i in state.inbox.size():
		if is_same(state.inbox[i], item):
			return {"where": "inbox", "index": i}
	for i in state.pantry.items.size():
		if is_same(state.pantry.items[i].item, item):
			return {"where": "pantry", "index": i}
	return {}


## Lays `items` in order at the first free spot, column by column (top cell first), turning pies when needed.
static func _pack(items: Array) -> Array:
	var b := board()
	var entries: Array = []
	for it in items:
		var spot := first_spot(b, entries, it)
		if not spot.is_empty():
			entries.append({"item": it, "x": spot.cell.x, "y": spot.cell.y, "rot": spot.rot})
	return entries


## First free {"cell", "rot"} for `item` on the stall, column by column; {} when it does not fit.
static func first_spot(b: Dictionary, entries: Array, item: Dictionary) -> Dictionary:
	for x in COLS:
		for y in ROWS:
			for rot in ([0, 1] if PantryRules.can_rotate(item) else [0]):
				if PantryRules.can_place(b, entries, item, Vector2i(x, y), rot):
					return {"cell": Vector2i(x, y), "rot": rot}
	return {}
