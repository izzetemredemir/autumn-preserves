class_name WildGen
extends RefCounted
## SIM-02 · Daily wild map (spec §7.1). Pure: same inputs -> same map. Seed: Seeds.seed_for(save_seed, "wild:<biome>", day).
## Map: {"seed", "biome", "w", "h", "ground": PackedByteArray (w*h, row-major, T_* ids),
##  "decor_trees": [{"x","y","kind"}], "fruit_trees": [{"id","x","y","type","variety"}],
##  "pickups": [{"id","x","y","kind": "bush"|"ground","type","variety"}], "special": {} or {"kind","x","y","w","h"},
##  "entrance": Vector2i, "clearings": [Vector2i], "steps": {} (P1: per-step layers for the Seed Lab)}
## Ids are stable indices assigned after validation. Coordinates are tiles (16 px).

const T_GRASS := 0
const T_LEAVES := 1
const T_DIRT := 2
const T_WATER := 3
const T_PATH := 4
const T_STONE := 5


static func generate(_save_seed: int, _day: int, _biome: String, _weather: String, _varieties: Dictionary) -> Dictionary:
	return {}  # TODO SIM-02


static func is_walkable(_map: Dictionary, _cell: Vector2i) -> bool:
	return true  # TODO SIM-02
