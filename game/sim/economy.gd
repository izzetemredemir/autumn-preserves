class_name Economy
extends RefCounted
## SIM-04 · Energy, grocer buy/sell, friendship (spec §4, §7.8, §8). All numbers from Data.rules()/Data.shop().


static func energy_cost(_action: String) -> int:
	return 0  # TODO SIM-04


## Spends energy if enough is left. Returns false (and spends nothing) otherwise.
static func spend(_state: Dictionary, _action: String) -> bool:
	return false  # TODO SIM-04


## {"ok", "reason", "coins_left"} · shop_id is a shop.json buy/seed/upgrade id ("jar", "seed_cucumber", "pantry_row").
static func buy(_state: Dictionary, _shop_id: String, _qty: int = 1) -> Dictionary:
	return {"ok": false}  # TODO SIM-04


static func sell_price(_item: Dictionary, _varieties: Dictionary) -> int:
	return 0  # TODO SIM-04


static func sell(_state: Dictionary, _item_ref: Dictionary) -> Dictionary:
	return {"ok": false}  # TODO SIM-04


static func hearts(_state: Dictionary, _npc_id: String) -> int:
	return 0  # TODO SIM-04


## Gift a product to a neighbour (once a day each). {"ok","points","hearts"}
static func gift(_state: Dictionary, _npc_id: String, _item_ref: Dictionary) -> Dictionary:
	return {"ok": false}  # TODO SIM-04
