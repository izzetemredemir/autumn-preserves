class_name Farewell
extends RefCounted
## P2-FAREWELL · The hidden day-100 ending (spec §7.12). Pure rules, no autoloads, no disk:
## the trigger, the quiet hints on days 90-99, Tonty's last letter and the credits as i18n lines [{"key", "args"}]
## (the view translates with tr(key) % args), and the jars the farewell shows.
## Save keys (old saves lack them: always get(key, default)):
##   flags.completed (bool) · flags.completed_day (int) · flags.farewell_seen (bool, the first viewing is over)
##   flags.memory (bool, in memory only: the save was opened in Memory mode and is never written back)

## Going to bed on this day (or later, for saves that are already past it) starts the farewell night.
const LAST_DAY := 99
const FINAL_DAY := 100
## Days HINT_FROM..LAST_DAY show the hints: slower walk, worried letters, a shorter morning note.
const HINT_FROM := 90
const WALK_SCALE := 0.8
## Worried grandchild notes FAREWELL_WORRY_<KID>_1..WORRY_COUNT replace request notes on hint days.
const WORRY_COUNT := 3
## Hint days: notable morning lines kept (MorningText order), the energy line is dropped.
const MORNING_NOTABLE := 2
const NOTABLE := ["matured", "grown", "tree_refilled", "order_new", "spoiled", "fertilizer"]
const RARITY_RANK := {"common": 0, "uncommon": 1, "rare": 2}
const TOP_JARS := 3
## The pantry pan shows at most this many jars, in shelf order.
const MAX_PAN_JARS := 12


static func flags(state: Dictionary) -> Dictionary:
	var f: Variant = state.get("flags", {})
	return f if typeof(f) == TYPE_DICTIONARY else {}


static func is_completed(state: Dictionary) -> bool:
	return bool(flags(state).get("completed", false))


static func completed_day(state: Dictionary) -> int:
	return int(flags(state).get("completed_day", maxi(int(state.get("day", FINAL_DAY)), FINAL_DAY)))


static func seen(state: Dictionary) -> bool:
	return bool(flags(state).get("farewell_seen", false))


static func is_memory(state: Dictionary) -> bool:
	return bool(flags(state).get("memory", false))


## Does tonight end the game? Only from day LAST_DAY on, never twice.
static func triggers(state: Dictionary) -> bool:
	return not is_completed(state) and int(state.get("day", 1)) >= LAST_DAY


## What GameState.end_day does tonight: "memory" (no new day, nothing saved), "farewell" or "normal".
static func night_kind(state: Dictionary) -> String:
	if is_memory(state) or is_completed(state):
		return "memory"
	return "farewell" if triggers(state) else "normal"


## The night as GameState.end_day runs it (the caller saves; sim code never touches the disk):
##   "memory":   nothing changes, no events (Memory mode, or a completed save)
##   "farewell": "backup" = the day-99 state before the night, then DayEnd runs and the save is closed; no events
##   "normal":   DayEnd, events trimmed by morning_events
## {"kind", "events", "backup" (farewell only)}
static func night(state: Dictionary) -> Dictionary:
	var kind := night_kind(state)
	match kind:
		"memory":
			return {"kind": kind, "events": []}
		"farewell":
			var backup := state.duplicate(true)
			DayEnd.run(state)
			complete(state)
			return {"kind": kind, "events": [], "backup": backup}
	return {"kind": kind, "events": morning_events(DayEnd.run(state), int(state.day))}


## Closes the save after the farewell night (DayEnd already moved the day on).
static func complete(state: Dictionary) -> void:
	if typeof(state.get("flags")) != TYPE_DICTIONARY:
		state["flags"] = {}
	state.flags["completed"] = true
	state.flags["completed_day"] = maxi(int(state.get("day", FINAL_DAY)), FINAL_DAY)
	state.flags["farewell_seen"] = false


static func is_hint_day(day: int) -> bool:
	return day >= HINT_FROM and day <= LAST_DAY


## Granny's walk speed and step animation multiplier (looks only: energy and rules never change).
static func walk_scale(day: int) -> float:
	return WALK_SCALE if is_hint_day(day) else 1.0


## Request note key of a grandchild letter written on `day`; `n` is the note the letter stream drew (1..).
static func note_key(kid: String, n: int, day: int) -> String:
	if is_hint_day(day):
		return "FAREWELL_WORRY_%s_%d" % [kid.to_upper(), (maxi(n, 1) - 1) % WORRY_COUNT + 1]
	return "LET_NOTE_%s_%d" % [kid.to_upper(), n]


## The night's events as the morning card gets them: on hint days only the first MORNING_NOTABLE notable
## events stay and the energy line goes, so the note is shorter. Other days: unchanged.
static func morning_events(events: Array, day: int) -> Array:
	if not is_hint_day(day):
		return events
	var keep := {}
	var n := 0
	for type in NOTABLE:
		for i in events.size():
			var e: Variant = events[i]
			if n < MORNING_NOTABLE and typeof(e) == TYPE_DICTIONARY and String(e.get("type", "")) == type:
				keep[i] = true
				n += 1
	var out: Array = []
	for i in events.size():
		var e: Variant = events[i]
		var type := String(e.get("type", "")) if typeof(e) == TYPE_DICTIONARY else ""
		if type == "energy" or (type in NOTABLE and not keep.has(i)):
			continue
		out.append(e)
	return out


# --- the letter --------------------------------------------------------------------------------------------------

## Tonty's last letter, built from the save: days in Everfall, jars made, the 3 most valuable jars in the pantry,
## the rarest variety found and the neighbour with the most hearts. Every part has a fallback line.
static func letter(state: Dictionary) -> Array:
	var out: Array = []
	var kids := kid_names()
	if kids.size() == 2:
		out.append(_l("FAREWELL_LETTER_DEAR_TWO", kids))
	else:
		out.append(_l("FAREWELL_LETTER_DEAR", []))
	out.append(_l("FAREWELL_LETTER_DAYS", [int(state.get("day", FINAL_DAY))]))
	var made := int(state.get("stats", {}).get("jars_made", 0))
	if made > 1:
		out.append(_l("FAREWELL_LETTER_JARS", [made]))
	elif made == 1:
		out.append(_l("FAREWELL_LETTER_JARS_ONE", []))
	else:
		out.append(_l("FAREWELL_LETTER_JARS_NONE", []))
	var top: Array = top_jars(state)
	var names: Array = top.map(func(j: Dictionary) -> String: return String(j.name))
	match names.size():
		0:
			out.append(_l("FAREWELL_LETTER_TOP_NONE", []))
		1:
			out.append(_l("FAREWELL_LETTER_TOP_1", names))
		2:
			out.append(_l("FAREWELL_LETTER_TOP_2", names))
		_:
			out.append(_l("FAREWELL_LETTER_TOP_3", names.slice(0, 3)))
	var rare := rarest_variety(state)
	if rare.is_empty():
		out.append(_l("FAREWELL_LETTER_RARE_NONE", []))
	else:
		out.append(_l("FAREWELL_LETTER_RARE", [VarietyGen.display_name(rare)]))
	var friend := best_neighbour(state)
	if friend == "":
		out.append(_l("FAREWELL_LETTER_FRIEND_NONE", []))
	else:
		out.append(_l("FAREWELL_LETTER_FRIEND", [npc_name(friend)]))
	out.append(_l("FAREWELL_LETTER_TEO", []))  # STORY-03: answers Teo's letter in the recipe book
	out.append(_l("FAREWELL_LETTER_LOVE", []))
	out.append(_l("FAREWELL_LETTER_SIGN", []))
	return out


## The pantry's most valuable jars, one per product key: [{"key", "q", "name", "value"}], best first
## (ties: name, then key). Waiting jars count too: they are on the shelf.
static func top_jars(state: Dictionary, n: int = TOP_JARS) -> Array:
	var best := {}
	for j in pantry_jars(state):
		if not best.has(j.key) or int(j.value) > int(best[j.key].value):
			best[j.key] = j
	var list: Array = best.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.value) != int(b.value):
			return int(a.value) > int(b.value)
		if String(a.name) != String(b.name):
			return String(a.name) < String(b.name)
		return String(a.key) < String(b.key))
	return list.slice(0, n)


## Every product in the pantry in shelf order (row, then column): [{"key", "q", "name", "value"}].
static func pantry_jars(state: Dictionary) -> Array:
	var varieties: Dictionary = state.get("varieties", {})
	var entries: Array = []
	var pantry: Variant = state.get("pantry", {})
	if typeof(pantry) == TYPE_DICTIONARY:
		for e in pantry.get("items", []):
			if typeof(e) == TYPE_DICTIONARY and String(e.get("item", {}).get("kind", "")) == "product":
				entries.append(e)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("y", 0)) != int(b.get("y", 0)):
			return int(a.get("y", 0)) < int(b.get("y", 0))
		return int(a.get("x", 0)) < int(b.get("x", 0)))
	var out: Array = []
	for e in entries:
		var key := String(e.item.get("key", ""))
		var q := int(e.item.get("q", 1))
		out.append({"key": key, "q": q, "name": ProductGen.product_name(key, varieties),
			"value": ProductGen.value(key, varieties, q)})
	return out


## The jars the pantry pan shows: at most MAX_PAN_JARS (the most valuable when there are more), in shelf order.
static func pan_jars(state: Dictionary) -> Array:
	var all := pantry_jars(state)
	if all.size() <= MAX_PAN_JARS:
		return all
	var idx: Array = range(all.size())
	idx.sort_custom(func(a: int, b: int) -> bool:
		if int(all[a].value) != int(all[b].value):
			return int(all[a].value) > int(all[b].value)
		return a < b)
	var keep: Array = idx.slice(0, MAX_PAN_JARS)
	keep.sort()
	return keep.map(func(i: int) -> Dictionary: return all[i])


## The rarest variety found (uncommon or rare; the first found of the best rank), {} when only common ones were.
static func rarest_variety(state: Dictionary) -> Dictionary:
	var varieties: Dictionary = state.get("varieties", {})
	var best: Dictionary = {}
	var best_rank := 0
	for id in state.get("found_varieties", []):
		var v: Variant = varieties.get(id, {})
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var rank := int(RARITY_RANK.get(String(v.get("rarity", "common")), 0))
		if rank > best_rank:
			best_rank = rank
			best = v
	return best


## The neighbour with the most hearts (ties: more points, then id), "" when nobody has a heart yet.
static func best_neighbour(state: Dictionary) -> String:
	var best := ""
	var best_hearts := 0
	var best_points := 0
	var friendship: Variant = state.get("friendship", {})
	if typeof(friendship) != TYPE_DICTIONARY:
		return ""
	var ids: Array = friendship.keys()
	ids.sort()
	for id in ids:
		var points := int(friendship[id])
		var hearts := Economy.hearts(state, String(id))
		if hearts > best_hearts or (hearts == best_hearts and hearts > 0 and points > best_points):
			best = String(id)
			best_hearts = hearts
			best_points = points
	return best


# --- credits -----------------------------------------------------------------------------------------------------

## Credits lines; "FAREWELL_CREDIT_NAME" is a bare "%s", "" key is an empty line.
static func credits(state: Dictionary) -> Array:
	var out: Array = [_l("TITLE_GAME", []), _l("FAREWELL_CREDIT_MADE_BY", []), _l("FAREWELL_CREDIT_JAM", []),
		_l("FAREWELL_CREDIT_CAST", []), _l("FAREWELL_CREDIT_TONTY", [])]
	var kids := kid_names()
	if kids.size() == 2:
		out.append(_l("FAREWELL_CREDIT_KIDS", kids))
	out.append(_l("", []))
	out.append(_l("FAREWELL_CREDIT_NEIGHBOURS", []))
	for id in neighbour_ids():
		out.append(_l("FAREWELL_CREDIT_NAME", [npc_name(id)]))
	out.append_array([_l("", []), _l("FAREWELL_CREDIT_FONTS", []), _l("FAREWELL_CREDIT_PALETTE", []), _l("", [])])
	var made := int(state.get("stats", {}).get("jars_made", 0))
	var found := int(state.get("book", {}).get("variants", {}).size())
	out.append(_l("FAREWELL_CREDIT_YOU", []))
	out.append(_l("FAREWELL_CREDIT_JARS", [made]))
	out.append(_l("FAREWELL_CREDIT_RECIPES", [found]))
	return out


## Discovered recipe-book variants, in the order they were found (first_day, then key).
static func book_variants(state: Dictionary) -> Array:
	var variants: Variant = state.get("book", {}).get("variants", {})
	if typeof(variants) != TYPE_DICTIONARY:
		return []
	var keys: Array = variants.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var da := int(variants[a].get("first_day", 0))
		var db := int(variants[b].get("first_day", 0))
		return da < db if da != db else a < b)
	return keys


# --- names -------------------------------------------------------------------------------------------------------

static func kid_names() -> Array:
	var out: Array = []
	var kids: Dictionary = Data.npcs().get("grandkids", {})
	var ids: Array = kids.keys()
	ids.sort()
	for id in ids:
		out.append(String(kids[id].get("name", String(id).capitalize())))
	return out


## Neighbour ids from npcs.json (not the grandchildren), by priority then id.
static func neighbour_ids() -> Array:
	var npcs := Data.npcs()
	var ids: Array = []
	for id in npcs:
		if String(id).begins_with("_") or id == "grandkids" or typeof(npcs[id]) != TYPE_DICTIONARY:
			continue
		ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var pa := int(npcs[a].get("priority", 0))
		var pb := int(npcs[b].get("priority", 0))
		return pa < pb if pa != pb else a < b)
	return ids


static func npc_name(npc_id: String) -> String:
	var row: Variant = Data.npcs().get(npc_id, {})
	if typeof(row) == TYPE_DICTIONARY and row.has("name"):
		return String(row.name)
	return npc_id.capitalize()


static func _l(key: String, args: Array) -> Dictionary:
	return {"key": key, "args": args}
