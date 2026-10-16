class_name Kitchen
extends RefCounted
## SIM-01 · Cooking rules (spec §6.3, §7.2). Fresh inputs come from inbox first, then pantry; bases from cupboard;
## nut add-ins from inbox/pantry nut stacks, shop add-ins from cupboard.


## {"ok": bool, "reason": i18n key ("" when ok), "missing": {id: count}}
static func check(_state: Dictionary, _recipe_id: String, _main_variety: String, _second_variety: String, _addin_id: String) -> Dictionary:
	return {"ok": false, "reason": "TODO", "missing": {}}  # TODO SIM-01


## Consumes inputs and energy, puts the product in the inbox, updates book and stats.
## {"ok": bool, "item": product item, "desc": ProductGen.describe(), "is_new": bool}
static func cook(_state: Dictionary, _recipe_id: String, _main_variety: String, _second_variety: String, _addin_id: String, _quality: int) -> Dictionary:
	return {"ok": false}  # TODO SIM-01
