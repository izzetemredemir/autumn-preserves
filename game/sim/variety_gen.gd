class_name VarietyGen
extends RefCounted
## SIM-01 · Ingredient varieties of a save (spec §6.2). Deterministic in save_seed (stream "variety", day 0).
## Variety: {"id": "crabapple_3", "type", "name", "rarity": "common"|"uncommon"|"rare", "tier": int,
##           "color_shift": -1|0|1, "taste_delta": [5 ints], "size": "small"|"medium"|"large"}
## Ids are "<type>_<n>", n = 1..count in tier order (rules.varieties.tiers_p0). Nut types have no varieties.


static func generate_all(_save_seed: int, _max_priority: int = 0) -> Dictionary:
	return {}  # TODO SIM-01


## Base taste of the type + taste_delta, each axis clamped to 0..9.
static func taste_of(_variety: Dictionary) -> Array:
	return [0, 0, 0, 0, 0]  # TODO SIM-01


## Spawn weights of a type's varieties, aligned with the sorted variety ids of that type.
static func spawn_weights(_varieties: Dictionary, _type: String, _rare_mult: float = 1.0) -> Dictionary:
	return {}  # TODO SIM-01 · {"ids": [..], "weights": [..]}
