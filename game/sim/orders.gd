class_name Orders
extends RefCounted
## SIM-04 · Neighbour orders (spec §7.8). Order: {"id","npc","recipe" ("" = any),"axes": [axis ids],"min_stars","made_day","expires_day"}.
## Uses stream "orders" with the current day.


## Drops expired orders and fills empty slots (rules.orders.slots), keeping the "one satisfiable order" guarantee.
static func refill(_state: Dictionary) -> void:
	pass  # TODO SIM-04


static func generate(_state: Dictionary, _npc_id: String, _r: RandomNumberGenerator) -> Dictionary:
	return {}  # TODO SIM-04


## True when the product item satisfies the order (recipe, every axis >= threshold, quality + harmony >= min_stars).
static func matches(_order: Dictionary, _product_item: Dictionary, _varieties: Dictionary) -> bool:
	return false  # TODO SIM-04


## Removes the item, pays value * reward_mult, adds friendship. {"ok","coins","hearts_before","hearts_after"}
static func fulfill(_state: Dictionary, _order_id: int, _item_ref: Dictionary) -> Dictionary:
	return {"ok": false}  # TODO SIM-04


## Can this order be met with unlocked recipes, common varieties and shop add-ins?
static func satisfiable(_state: Dictionary, _order: Dictionary) -> bool:
	return false  # TODO SIM-04
