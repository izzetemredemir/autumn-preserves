class_name DevTools
extends RefCounted
## Pure helpers behind the debug panel (spec §10). No autoloads, so tests can call them.

const DEMO_SAVE := "res://dev/demo_save.json"
const ITEM_COUNT := 5
const SEED_COUNT := 3


## Into the inbox: the first variety of every P0 ingredient x5 and each P0 nut x5.
## Into the cupboard: every P0 shop item +5 and every P0 seed packet +3. Returns how many stacks were added.
static func give_items(state: Dictionary) -> int:
	var added := 0
	var ingredients := Data.ingredients()
	for type in Data.ids_up_to("ingredients", 0):
		var ing: Dictionary = ingredients[type]
		if ing.group == "nut":
			state.inbox.append(State.nut(type, ITEM_COUNT))
		else:
			var shelf: Variant = ing.get("shelf_days")
			state.inbox.append(State.fresh(first_variety(state, type), ITEM_COUNT, int(shelf) if shelf != null else -1))
		added += 1
	var shop := Data.shop()
	for id in shop.buy:
		var row: Variant = shop.buy[id]
		if typeof(row) == TYPE_DICTIONARY and int(row.get("priority", 0)) > 0:
			continue
		state.cupboard[id] = int(state.cupboard.get(id, 0)) + ITEM_COUNT
		added += 1
	for crop in shop.seeds:
		if int(shop.seeds[crop].get("priority", 0)) > 0:
			continue
		var key: String = "seed_" + crop
		state.cupboard[key] = int(state.cupboard.get(key, 0)) + SEED_COUNT
		added += 1
	return added


## "<type>_1" when the save has it, else the lowest variety id of that type, else "<type>_1".
static func first_variety(state: Dictionary, type: String) -> String:
	var varieties: Dictionary = state.get("varieties", {})
	var first := type + "_1"
	if varieties.has(first):
		return first
	var ids: Array = []
	for id in varieties:
		if State.type_of_variety(id) == type:
			ids.append(id)
	if ids.is_empty():
		return first
	ids.sort()
	return ids[0]


## The demo save as a state dictionary, {} when the file is missing or not a save.
static func load_demo(path: String = DEMO_SAVE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("save_seed") or not parsed.has("day"):
		return {}
	return parsed
