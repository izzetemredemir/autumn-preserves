class_name MorningText
extends RefCounted
## Night events (DayEnd.run) -> plain-word lines for the morning card. Pure: returns [{"key", "args"}],
## the view translates with tr(key) % args. Notable events first (at most MAX_NOTABLE), then weather and energy.

const MAX_NOTABLE := 6
const NOTABLE := ["matured", "grown", "tree_refilled", "order_new", "spoiled", "fertilizer"]
const MANY := ["UI_NIGHT_GROWN", "UI_NIGHT_MATURED"]


static func lines(events: Array, state: Dictionary) -> Array:
	var notable: Array = []
	var tail: Array = []
	for type in NOTABLE:
		for e in events:
			if typeof(e) == TYPE_DICTIONARY and e.get("type", "") == type:
				var l := line(e, state)
				if not l.is_empty():
					notable.append(l)
	for e in events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if e.get("type", "") in ["weather", "energy"]:
			var l := line(e, state)
			if not l.is_empty():
				tail.append(l)
	notable = merge(notable)
	var out: Array = []
	if notable.is_empty():
		out.append({"key": "UI_NIGHT_QUIET", "args": []})
	else:
		out.append_array(notable.slice(0, MAX_NOTABLE))
		if notable.size() > MAX_NOTABLE:
			out.append({"key": "UI_NIGHT_MORE", "args": [notable.size() - MAX_NOTABLE]})
	out.append_array(tail)
	return out


## One event -> {"key", "args"}; {} for events the card does not show (e.g. "day").
static func line(e: Dictionary, state: Dictionary) -> Dictionary:
	var varieties: Dictionary = state.get("varieties", {})
	match String(e.get("type", "")):
		"matured":
			return _l("UI_NIGHT_MATURED", [_product_name(String(e.get("key", "")), varieties)])
		"spoiled":
			return _l("UI_NIGHT_SPOILED", [item_name(e.get("item", {}), varieties)])
		"grown":
			return _l("UI_NIGHT_GROWN", [type_name(String(e.get("crop", ""))).to_lower()])
		"tree_refilled":
			return _l("UI_NIGHT_TREE", [type_name(String(e.get("tree_type", ""))).to_lower()])
		"order_new":
			var npc := String(e.get("order", {}).get("npc", ""))
			return _l("UI_NIGHT_ORDER", [npc_name(npc)])
		"fertilizer":
			var made := int(e.get("made", 0))
			return _l("UI_NIGHT_FERTILIZER", [made]) if made > 0 else {}
		"weather":
			var w := String(e.get("weather", "sunny")).to_upper()
			return _l("UI_NIGHT_WEATHER_" + w, [])
		"energy":
			var stars := int(e.get("stars", 0))
			if stars > 0:
				return _l("UI_NIGHT_ENERGY_STARS", [stars, int(e.get("energy", 0))])
			return _l("UI_NIGHT_ENERGY", [int(e.get("energy", 0))])
	return {}


## Identical lines become one; repeated beds and matured jars get a counted "_MANY" line.
static func merge(lines_in: Array) -> Array:
	var order: Array = []
	var counts := {}
	for l in lines_in:
		var id := "%s|%s" % [l.key, str(l.args)]
		if not counts.has(id):
			counts[id] = 0
			order.append(l)
		counts[id] += 1
	var out: Array = []
	for l in order:
		var n: int = counts["%s|%s" % [l.key, str(l.args)]]
		if n > 1 and l.key in MANY:
			out.append(_l(l.key + "_MANY", [n] + l.args))
		else:
			out.append(l)
	return out


static func _l(key: String, args: Array) -> Dictionary:
	return {"key": key, "args": args}


static func _product_name(key: String, varieties: Dictionary) -> String:
	if key == "":
		return "?"
	var n := ProductGen.product_name(key, varieties)
	if n == "" or n == "?":
		var recipe := key.split("|")[0]
		return String(Data.recipes().get(recipe, {}).get("name", recipe.capitalize()))
	return n


static func item_name(item: Dictionary, varieties: Dictionary) -> String:
	match String(item.get("kind", "")):
		"fresh":
			var id := String(item.get("variety", ""))
			var v: Dictionary = varieties.get(id, {})
			return String(v.get("name", type_name(State.type_of_variety(id))))
		"nut":
			return type_name(String(item.get("type", "")))
		"product":
			return _product_name(String(item.get("key", "")), varieties)
	return "?"


static func type_name(type: String) -> String:
	var ing: Dictionary = Data.ingredients().get(type, {})
	return String(ing.get("display_name", type.capitalize()))


static func npc_name(npc_id: String) -> String:
	var row: Variant = Data.npcs().get(npc_id, {})
	if typeof(row) == TYPE_DICTIONARY and row.has("name"):
		return String(row.name)
	return npc_id.capitalize()
