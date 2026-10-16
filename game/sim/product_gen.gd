class_name ProductGen
extends RefCounted
## SIM-01 · Procedural preserves (spec §6.4, §7.3). Pure: same key -> same name, taste, look.
## key = "<recipe>|<variety>[|<variety2>]|<addin or ->", e.g. "jam|crabapple_3|cinnamon", "chutney|pear_1|pepper_2|-".


static func make_key(recipe_id: String, variety_ids: Array, addin_id: String) -> String:
	var parts: Array = [recipe_id]
	parts.append_array(variety_ids)
	parts.append(addin_id if addin_id != "" else "-")
	return "|".join(parts)


## {"recipe": String, "varieties": Array[String], "addin": String ("" when none)}
static func parse_key(key: String) -> Dictionary:
	var p := key.split("|")
	var addin := p[p.size() - 1]
	return {"recipe": p[0], "varieties": Array(p.slice(1, p.size() - 1)), "addin": "" if addin == "-" else addin}


static func taste(_key: String, _varieties: Dictionary) -> Array:
	return [0, 0, 0, 0, 0]  # TODO SIM-01


## Axis ids for the label, 0-2 entries, e.g. ["sweet", "sour"].
static func profile(_taste: Array) -> Array:
	return []  # TODO SIM-01


static func profile_label(_taste: Array) -> String:
	return "Mild"  # TODO SIM-01 · "Sweet & Sour" | "Sweet" | "Mild"


static func harmony(_taste: Array) -> int:
	return 0  # TODO SIM-01 · 0..2


static func product_name(_key: String, _varieties: Dictionary) -> String:
	return "?"  # TODO SIM-01


static func rarity(_key: String, _varieties: Dictionary) -> String:
	return "common"  # TODO SIM-01


## floor(base * rarity_mult * star_mult[quality + harmony]) + addin_bonus
static func value(_key: String, _varieties: Dictionary, _quality: int) -> int:
	return 0  # TODO SIM-01


## Everything a view needs: {"key","recipe","name","taste","profile","profile_label","harmony","rarity","zone",
##  "vessel","size": Vector2i, "appearance": {"vessel","fill": [3 hex],"chunk","chunk_seed","label_shape": 0..2,
##  "label_color": hex,"motif": "leaf"|"star"|"stripe","lid": "metal"|"cloth","lid_colors": [2 hex]}}
static func describe(_key: String, _varieties: Dictionary) -> Dictionary:
	return {}  # TODO SIM-01
