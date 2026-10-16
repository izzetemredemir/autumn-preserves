class_name Economy
extends RefCounted
## SIM-04 · Energy, grocer buy/sell, friendship (spec §4, §7.8, §8). All numbers from Data.rules()/Data.shop().

## Highest shop/seed/upgrade priority on sale by default (P0 = 0).
const MAX_PRIORITY := 0
## P1 rows go on sale one by one as their feature lands (tech-spec §16): shop.json buy/seed/upgrade id -> true.
## Seeds use their bare id ("cabbage"). One line per id so parallel cards merge cleanly.
const LIVE := {
	"boots": true,
	"press": true,
	"bottle": true,
	"flour": true,
	"cabbage": true,
	"pumpkin": true,
	"bag": true,
	"beds": true,
}


static func energy_cost(action: String) -> int:
	return int(Data.rules().energy.costs.get(action, 0))


## Spends energy if enough is left. Returns false (and spends nothing) otherwise.
static func spend(state: Dictionary, action: String) -> bool:
	var cost := energy_cost(action)
	if int(state.energy) < cost:
		return false
	state.energy = int(state.energy) - cost
	return true


## Coins for `qty` of a shop id with the grocer's heart discount, or -1 when it is not on sale.
## Upgrades price their next level and ignore qty.
static func price(state: Dictionary, shop_id: String, qty: int = 1) -> int:
	var shop := Data.shop()
	var total := -1
	if shop.buy.has(shop_id):
		var row: Variant = shop.buy[shop_id]
		if typeof(row) == TYPE_DICTIONARY:
			if not on_sale(shop_id, row):
				return -1
			total = int(row.price) * qty
		else:
			total = int(row) * qty
	elif shop_id.begins_with("seed_") and shop.seeds.has(shop_id.substr(5)):
		var seed_row: Dictionary = shop.seeds[shop_id.substr(5)]
		if not on_sale(shop_id.substr(5), seed_row):
			return -1
		total = int(seed_row.price) * qty
	elif shop.upgrades.has(shop_id):
		var up: Dictionary = shop.upgrades[shop_id]
		var level := int(state.upgrades.get(shop_id, 0))
		var prices: Array = up.prices if up.has("prices") else [up.price]
		if not on_sale(shop_id, up) or level >= prices.size():
			return -1
		total = int(prices[level])
	if total < 0:
		return -1
	return floori(total * (1.0 - discount(state)) + 0.000001)


## Grocer heart reward (npcs.json reward kind "shop_discount"), 0.0 until earned.
static func discount(state: Dictionary) -> float:
	var npcs := Data.npcs()
	for npc_id in npcs:
		var reward: Variant = npcs[npc_id].get("reward")
		if typeof(reward) == TYPE_DICTIONARY and reward.kind == "shop_discount" and hearts(state, npc_id) >= int(reward.hearts):
			return float(reward.value)
	return 0.0


## {"ok", "reason", "coins_left"} · shop_id is a shop.json buy/seed/upgrade id ("jar", "seed_cucumber", "pantry_row").
static func buy(state: Dictionary, shop_id: String, qty: int = 1) -> Dictionary:
	var cost := price(state, shop_id, qty) if qty > 0 else -1
	if cost < 0:
		return {"ok": false, "reason": "UI_NOT_AVAILABLE", "coins_left": int(state.coins)}
	if int(state.coins) < cost:
		return {"ok": false, "reason": "UI_NO_COINS", "coins_left": int(state.coins)}
	state.coins = int(state.coins) - cost
	if Data.shop().upgrades.has(shop_id):
		state.upgrades[shop_id] = int(state.upgrades.get(shop_id, 0)) + 1
		if shop_id == "pantry_row":
			PantryRules.add_shelf(state.pantry)
		else:
			unlock(state, shop_id)
			if shop_id == "beds":
				Garden.ensure_beds(state)
	else:
		state.cupboard[shop_id] = int(state.cupboard.get(shop_id, 0)) + qty
	return {"ok": true, "reason": "", "coins_left": int(state.coins), "spent": cost}


## What the grocer pays for the whole item (stack): products value * product_ratio, fresh and nuts a fixed price
## per piece * rarity multiplier (spec §7.8).
static func sell_price(item: Dictionary, varieties: Dictionary) -> int:
	var sell: Dictionary = Data.shop().sell
	match item.get("kind", ""):
		"product":
			return floori(ProductGen.value(item.key, varieties, int(item.q)) * float(sell.product_ratio))
		"nut":
			return int(sell.fresh.nut) * int(item.count)
		"fresh":
			var type := State.item_type(item)
			var ing: Dictionary = Data.ingredients().get(type, {})
			var base := int(sell.fresh_overrides.get(type, sell.fresh.get(ing.get("group", ""), 0)))
			var rarity := "common"
			if varieties.has(item.variety):
				rarity = String(varieties[item.variety].get("rarity", "common"))
			var each := floori(base * float(sell.rarity_mult.get(rarity, 1.0)))
			return each * int(item.count)
	return 0


## Sells the referenced item (whole stack) to the grocer. No energy. {"ok", "reason", "coins", "coins_left"}
static func sell(state: Dictionary, item_ref: Dictionary) -> Dictionary:
	if not valid_ref(state, item_ref):
		return {"ok": false, "reason": "UI_NOT_AVAILABLE"}
	var coins := sell_price(State.get_item(state, item_ref), state.varieties)
	State.take(state, item_ref)
	earn(state, coins)
	return {"ok": true, "reason": "", "coins": coins, "coins_left": int(state.coins)}


static func earn(state: Dictionary, coins: int) -> void:
	state.coins = int(state.coins) + coins
	state.stats.coins_earned = int(state.stats.get("coins_earned", 0)) + coins


static func hearts(state: Dictionary, npc_id: String) -> int:
	var f: Dictionary = Data.rules().friendship
	var points := int(state.friendship.get(npc_id, 0))
	return mini(int(f.max_hearts), floori(float(points) / int(f.points_per_heart)))


## Adds friendship points, capped at max_hearts. Returns the points actually added.
## Heart rewards crossed by this change are applied once and queued for the scene: see take_rewards().
static func add_friendship(state: Dictionary, npc_id: String, points: int) -> int:
	var f: Dictionary = Data.rules().friendship
	var cap := int(f.max_hearts) * int(f.points_per_heart)
	var before := int(state.friendship.get(npc_id, 0))
	var after := clampi(before + points, 0, cap)
	state.friendship[npc_id] = after
	claim_rewards(state, npc_id)
	return after - before


## Rewards beyond the single npcs.json `reward` (tech-spec §16 keeps that field one dict per neighbour).
const EXTRA_REWARDS := {
	"librarian": [{"hearts": 3, "kind": "addin", "value": "mint", "count": 3}],
}


## Every heart reward of a neighbour: the npcs.json one first, then EXTRA_REWARDS.
static func rewards_of(npc_id: String) -> Array:
	var out: Array = []
	var reward: Variant = Data.npcs().get(npc_id, {}).get("reward")
	if typeof(reward) == TYPE_DICTIONARY:
		out.append(reward)
	out.append_array(EXTRA_REWARDS.get(npc_id, []))
	return out


## Toast key of a reward, e.g. UI_REWARD_KNEAD, UI_REWARD_VINEYARD, UI_REWARD_SHOP_DISCOUNT.
static func reward_key(reward: Dictionary) -> String:
	var tail := String(reward.value) if String(reward.kind).begins_with("unlock") else String(reward.kind)
	return "UI_REWARD_" + tail.to_upper()


## Adds friendship keys of neighbours an old save lacks (vintner, librarian ...). Never lowers anything.
static func ensure_neighbours(state: Dictionary) -> void:
	var npcs := Data.npcs()
	for id in npcs:
		if npcs[id].has("likes") and not state.friendship.has(id):
			state.friendship[id] = 0


## Applies every reward of `npc_id` whose heart threshold is reached and was not claimed yet.
## Queues each one in state.flags.reward_queue and returns the new ones ({"npc","hearts","kind","value","key"}).
static func claim_rewards(state: Dictionary, npc_id: String) -> Array:
	var fresh: Array = []
	var claimed: Dictionary = state.flags.get("rewards", {})
	var h := hearts(state, npc_id)
	for r: Dictionary in rewards_of(npc_id):
		var tag := "%s:%d:%s" % [npc_id, int(r.hearts), r.kind]
		if h < int(r.hearts) or claimed.has(tag):
			continue
		claimed[tag] = true
		_apply_reward(state, r)
		fresh.append({"npc": npc_id, "hearts": int(r.hearts), "kind": r.kind, "value": r.value, "key": reward_key(r)})
	state.flags.rewards = claimed
	if not fresh.is_empty():
		var q: Array = state.flags.get("reward_queue", [])
		q.append_array(fresh)
		state.flags.reward_queue = q
	return fresh


## Upgrades an old save: adds missing neighbours and claims rewards already earned. Returns the new rewards.
static func sync_neighbours(state: Dictionary) -> Array:
	ensure_neighbours(state)
	var fresh: Array = []
	var ids: Array = state.friendship.keys()
	ids.sort()
	for id in ids:
		fresh.append_array(claim_rewards(state, id))
	return fresh


## Pops the rewards earned since the last call; the scene toasts them and plays the level jingle.
static func take_rewards(state: Dictionary) -> Array:
	var q: Array = state.flags.get("reward_queue", [])
	state.flags.reward_queue = []
	return q


static func _apply_reward(state: Dictionary, r: Dictionary) -> void:
	match String(r.kind):
		"unlock", "unlock_biome":
			unlock(state, String(r.value))
		"hints":
			unlock(state, "hints")
		"addin":
			state.cupboard[r.value] = int(state.cupboard.get(r.value, 0)) + int(r.get("count", 1))
		# "shop_discount" (discount()) and "letters_more_often" (Letters.gap) are derived from hearts.


## Points a gift earns: gift_points when one of the neighbour's liked axes is >= gift_like_min.
static func gift_points(npc_id: String, taste: Array) -> int:
	var f: Dictionary = Data.rules().friendship
	var npc: Dictionary = Data.npcs().get(npc_id, {})
	for axis in npc.get("likes", []):
		var i := ProductGen.AXES.find(axis)
		if i >= 0 and i < taste.size() and int(taste[i]) >= int(f.gift_like_min):
			return int(f.gift_points)
	return 0


## Gift a product to a neighbour (once a day each). {"ok","points","hearts"}
## The day of each neighbour's last gift lives in state.flags.gifted = {npc_id: day}.
static func gift(state: Dictionary, npc_id: String, item_ref: Dictionary) -> Dictionary:
	if not state.friendship.has(npc_id) or not valid_ref(state, item_ref):
		return {"ok": false, "reason": "UI_NOT_AVAILABLE"}
	var item := State.get_item(state, item_ref)
	if item.get("kind", "") != "product":
		return {"ok": false, "reason": "UI_NOT_AVAILABLE"}
	var gifted: Dictionary = state.flags.get("gifted", {})
	if int(gifted.get(npc_id, 0)) == int(state.day):
		return {"ok": false, "reason": "UI_GIFTED_TODAY"}
	var pts := gift_points(npc_id, ProductGen.taste(item.key, state.varieties))
	State.take(state, item_ref)
	gifted[npc_id] = int(state.day)
	state.flags.gifted = gifted
	var added := add_friendship(state, npc_id, pts)
	return {"ok": true, "reason": "", "points": added, "hearts": hearts(state, npc_id)}


## True when `ref` points at an existing item.
static func valid_ref(state: Dictionary, ref: Dictionary) -> bool:
	var i := int(ref.get("index", -1))
	match ref.get("where", ""):
		"bag":
			return i >= 0 and i < state.bag.size()
		"inbox":
			return i >= 0 and i < state.inbox.size()
		"pantry":
			return i >= 0 and i < state.pantry.items.size()
	return false


## A shop row is on sale when it is P0 content or its id is in LIVE.
static func on_sale(row_id: String, row: Dictionary) -> bool:
	return int(row.get("priority", 0)) <= MAX_PRIORITY or LIVE.has(row_id)


## P1 feature gates (tech-spec §16): "press", "knead", "vineyard", "boots" ... set by a purchase or a heart reward.
static func unlocked(state: Dictionary, id: String) -> bool:
	return bool(state.get("unlocks", {}).get(id, false))


static func unlock(state: Dictionary, id: String) -> void:
	var u: Dictionary = state.get("unlocks", {})
	u[id] = true
	state["unlocks"] = u
