class_name Forage
extends RefCounted
## SIM-02 · Foraging actions (spec §4, §7.1). Mutate state, return a result dict {"ok", "reason", "items", "energy"}.
## Today's progress lives in state.wild_today[biome] = {"collected": [pickup ids], "shaken": [tree ids]}.


## The map without today's collected pickups; shaken trees get "shaken": true.
static func visible_map(_state: Dictionary, _map: Dictionary) -> Dictionary:
	return {}  # TODO SIM-02


static func shake_tree(_state: Dictionary, _map: Dictionary, _tree_id: int) -> Dictionary:
	return {"ok": false, "reason": "TODO"}  # TODO SIM-02


static func pick(_state: Dictionary, _map: Dictionary, _pickup_id: int) -> Dictionary:
	return {"ok": false, "reason": "TODO"}  # TODO SIM-02


static func bag_count(_state: Dictionary) -> int:
	return 0  # TODO SIM-02


## Called when Granny enters the house: bag -> inbox, merging equal stacks.
static func empty_bag_to_inbox(_state: Dictionary) -> void:
	pass  # TODO SIM-02
