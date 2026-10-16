class_name PantryRules
extends RefCounted
## SIM-03 · Pantry grid rules (spec §7.4). Board: {"name", "cols", "rows", "zones": Array (row-major zone per cell,
## "" = no cell)}. Shelves are 6 cols x 2 rows: dry (rows 0-1), room (2-3), cool (4-5); floor 4x2 below (rows 6-7).
## Each pantry_row upgrade adds a 6x2 shelf, zones in order room, cool, dry. state.pantry = {"rows_extra", "items": [{"item","x","y","rot"}]}.


static func board(_rows_extra: int = 0) -> Dictionary:
	return {}  # TODO SIM-03


## Cells covered by an item: product size from its vessel, fresh/nut 1x1; rot 1 swaps w/h.
static func item_size(_item: Dictionary, _rot: int = 0) -> Vector2i:
	return Vector2i.ONE  # TODO SIM-03


static func zone_for(_item: Dictionary) -> String:
	return "room"  # TODO SIM-03 · "dry"|"room"|"cool"|"floor"


static func can_place(_board: Dictionary, _entries: Array, _item: Dictionary, _cell: Vector2i, _rot: int, _ignore_index: int = -1) -> bool:
	return false  # TODO SIM-03


static func place(_pantry: Dictionary, _item: Dictionary, _cell: Vector2i, _rot: int) -> bool:
	return false  # TODO SIM-03


static func in_correct_zone(_board: Dictionary, _entry: Dictionary) -> bool:
	return false  # TODO SIM-03


## {"stars": 0..3, "rules": [bool, bool, bool]} (spec §7.4, independent rules)
static func stars(_pantry: Dictionary) -> Dictionary:
	return {"stars": 0, "rules": [false, false, false]}  # TODO SIM-03


## Places each item in the first free cell of its zone (no grouping). Returns items that did not fit.
static func auto_arrange(_pantry: Dictionary, _incoming: Array) -> Array:
	return _incoming  # TODO SIM-03
