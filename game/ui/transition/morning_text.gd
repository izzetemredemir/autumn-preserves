class_name MorningText
extends RefCounted
## Night events (DayEnd.run) -> plain-word lines for the morning card. Pure: returns [{"key", "args"}],
## the view translates with tr(key) % args. Notable events first (at most MAX_NOTABLE), then the day's calendar lines
## (week name and what is in season from day 8, "Market today!" on market days), then weather and energy.

const MAX_NOTABLE := 6
## Text rows that fit the card on the 270 px screen; a long line (the week's "in season" list, compost lines) wraps
## onto two rows, so the notable lines are capped by rows, not by count (QA-WEEK: the day-8 card was 283 px).
const MAX_ROWS := 10
const ROW_CHARS := 32  ## about the card's 236 px at 18 px text, with room for word wrap
const NOTABLE := ["matured", "grown", "tree_refilled", "order_new", "spoiled", "fertilizer"]
const MANY := ["UI_NIGHT_GROWN", "UI_NIGHT_MATURED"]


static func lines(events: Array, state: Dictionary) -> Array:
	var notable: Array = []
	var tail: Array = calendar_lines(state)
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
	# calendar, weather and energy lines take room from the notable ones, so the card fits the 270 px screen
	var budget := MAX_ROWS - 1  # one row kept for "...and N more"
	for l in tail:
		budget -= rows(l)
	var max_n := MAX_NOTABLE - calendar_lines(state).size()  # and never more lines than before, whatever the text
	var cap := 0
	var used := 0
	while cap < mini(notable.size(), max_n) and used + rows(notable[cap]) <= budget:
		used += rows(notable[cap])
		cap += 1
	var out: Array = []
	if notable.is_empty():
		out.append({"key": "UI_NIGHT_QUIET", "args": []})
	else:
		out.append_array(notable.slice(0, cap))
		if notable.size() > cap:
			out.append({"key": "UI_NIGHT_MORE", "args": [notable.size() - cap]})
	out.append_array(tail)
	return out


## Rows a line takes on the card (its translated text wraps at about ROW_CHARS characters).
static func rows(l: Dictionary) -> int:
	var t := String(TranslationServer.translate(String(l.key)))
	var args: Array = l.get("args", [])
	if not args.is_empty() and t.contains("%"):
		t = t % args
	return maxi(1, ceili(float(t.length()) / ROW_CHARS))


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
		"letter":
			var who := String(e.get("letter", {}).get("from", ""))
			var kids: Dictionary = Data.npcs().get("grandkids", {})
			return _l("UI_NIGHT_LETTER", [String(kids.get(who, {}).get("name", who.capitalize()))])
		"energy":
			var stars := int(e.get("stars", 0))
			if stars > 0:
				return _l("UI_NIGHT_ENERGY_STARS", [stars, int(e.get("energy", 0))])
			return _l("UI_NIGHT_ENERGY", [int(e.get("energy", 0))])
	return {}


## state.day's calendar lines: the week (Calendar, from its start day) with what is plentiful in the wild
## ("UI_WEEK_BEGINS" on the week's first day, else "UI_WEEK_NOW"), then "UI_MARKET_TODAY" when Market.is_market_day.
static func calendar_lines(state: Dictionary) -> Array:
	var day := int(state.get("day", 1))
	var out: Array = []
	if Calendar.week_key(day) != "":
		var names: Array = []
		for t in Calendar.wild_types(day):
			names.append(type_name(String(t)).to_lower())
		out.append(_l("UI_WEEK_BEGINS" if Calendar.first_day_of_week(day) else "UI_WEEK_NOW",
			[week_name(day), ", ".join(names)]))
	if Market.is_market_day(day):
		out.append(_l("UI_MARKET_TODAY", []))
	return out


## The week's translated name ("Apple Moon"; with_cycle: "Apple Moon, Autumn 2" from the second round on), "" before
## the calendar starts.
static func week_name(day: int, with_cycle := true) -> String:
	var key := Calendar.week_key(day)
	if key == "":
		return ""
	var n := String(TranslationServer.translate(key))
	var c := Calendar.cycle(day)
	return String(TranslationServer.translate("UI_WEEK_CYCLE")) % [n, c] if c > 1 and with_cycle else n


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
