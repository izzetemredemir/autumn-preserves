extends RefCounted
## JURY-PANTRY · What the pantry's goal panel and shelf signs say. Presentation only: it reads PantryRules (the
## star flags, zones, cells) and picks the words; the star rules themselves stay in game/sim/pantry_rules.gd.
## Tips come back as {"key": String, "kind": String, "zone": String, "n": int} for pantry.gd to translate.

## Kinds named under a shelf sign.
const NOTE_NAMES := 2
## A shelf with at most this many free cells gets "Fill the X shelf (n left)" instead of the general star-3 tip.
const FILL_TIP_MAX := 4


## Name of an item's kind: recipe name for products ("Pickles"), type name for fresh items and nuts ("Apple").
## `short` gives the recipe's one-word name ("Brine") for tight spots.
static func kind_name(item: Dictionary, short := false) -> String:
	var type := State.item_type(item)
	if String(item.get("kind", "")) == "product":
		return ProductGen.recipe_short(type) if short else ProductGen.recipe_name(type)
	return VarietyGen.type_name(type)


## The next step for the first unmet star rule. `flags` = PantryRules.stars(...).rules.
static func tip(pantry: Dictionary, flags: Array, inbox_size: int) -> Dictionary:
	var entries: Array = pantry.get("items", [])
	if entries.is_empty():
		return {"key": "PANTRY_TIP_START"} if inbox_size > 0 else {}
	var b := PantryRules.board_of(pantry)
	if flags.size() > 0 and not bool(flags[0]):
		for e in entries:
			if not PantryRules.in_correct_zone(b, e):
				return zone_tip(e.item)
	if flags.size() > 1 and not bool(flags[1]):
		var split := split_entry(entries)
		if split >= 0:
			var item: Dictionary = entries[split].item
			return {"key": "PANTRY_TIP_GROUP", "kind": kind_name(item), "short": kind_name(item, true)}
		return {"key": "PANTRY_TIP_GROUP_MORE", "n": int(Data.rules().pantry.stars.min_group)}
	if flags.size() > 2 and not bool(flags[2]):
		var best := fullest_shelf(b, entries)
		if not best.is_empty() and int(best.free) <= FILL_TIP_MAX:
			return {"key": "PANTRY_TIP_FILL", "zone": String(best.zone), "n": int(best.free)}
		return {"key": "PANTRY_TIP_PRETTY", "n": int(Data.rules().pantry.stars.sorted_row_min)}
	return {"key": "PANTRY_TIP_DONE"}


## Where `item` belongs: "Put the Jam on the Room shelf" (or "... on the floor").
static func zone_tip(item: Dictionary) -> Dictionary:
	var zone := PantryRules.zone_for(item)
	var floor_zone := String(Data.rules().pantry.floor.zone)
	return {"key": "PANTRY_TIP_FLOOR" if zone == floor_zone else "PANTRY_TIP_ZONE", "kind": kind_name(item),
		"short": kind_name(item, true), "zone": zone}


## Index of an entry whose kind stands in two or more separate groups (the first entry of its second group), -1
## when every kind is one side-by-side group.
static func split_entry(entries: Array) -> int:
	var taken := PantryRules.occupancy(entries)
	var kinds: Array = []
	for e in entries:
		kinds.append(State.item_type(e.item))
	var seen := {}
	var groups := {}
	for i in entries.size():
		if seen.has(i):
			continue
		seen[i] = true
		var queue: Array = [i]
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for c in PantryRules.entry_cells(entries[cur]):
				for d in PantryRules.NEIGHBOURS:
					var j: int = taken.get(c + d, -1)
					if j >= 0 and not seen.has(j) and kinds[j] == kinds[cur]:
						seen[j] = true
						queue.append(j)
		groups[kinds[i]] = int(groups.get(kinds[i], 0)) + 1
		if int(groups[kinds[i]]) == 2:
			return i
	return -1


## The shelf with the fewest free cells that still has one: {"zone", "free"}, {} when every shelf is full or empty.
static func fullest_shelf(b: Dictionary, entries: Array) -> Dictionary:
	var taken := PantryRules.occupancy(entries)
	var best := {}
	for sh in b.get("shelves", []):
		var free := 0
		var used := 0
		for r in int(sh.rows):
			for x in int(b.cols):
				var c := Vector2i(x, int(sh.y) + r)
				if PantryRules.zone_at(b, c) == "":
					continue
				if taken.has(c):
					used += 1
				else:
					free += 1
		if free > 0 and used > 0 and (best.is_empty() or free < int(best.free)):
			best = {"zone": String(sh.zone), "free": free}
	return best


## Kinds a zone holds, for its shelf sign: the ones the player has (shelves, then inbox) first, then the data's
## (recipes, fresh groups, big items) until NOTE_NAMES. Short names ("Pickles", "Brine", "Fruit").
static func zone_kinds(zone: String, entries: Array, inbox: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var items: Array = []
	for e in entries:
		items.append(e.item)
	items.append_array(inbox)
	for item in items:
		if out.size() >= NOTE_NAMES:
			return out
		if PantryRules.zone_for(item) != zone:
			continue
		var n := _note_name(item)
		if n != "" and not out.has(n):
			out.append(n)
	for n in data_kinds(zone):
		if out.size() >= NOTE_NAMES:
			break
		if not out.has(n):
			out.append(n)
	return out


## What the data puts in a zone: base recipes (not the grandkids' family ones), then fresh groups, then
## ingredients with a zone of their own (pumpkin on the floor).
static func data_kinds(zone: String) -> PackedStringArray:
	var out := PackedStringArray()
	var recipes: Dictionary = Data.recipes()
	for id in recipes:
		var r: Variant = recipes[id]
		if typeof(r) == TYPE_DICTIONARY and String(r.get("zone", "")) == zone and not r.has("family_of"):
			out.append(ProductGen.recipe_short(String(id)))
	var gz: Dictionary = Data.rules().pantry.group_zone
	for g in gz:
		if String(gz[g]) == zone:
			out.append(_group_word(String(g)))
	var ings: Dictionary = Data.ingredients()
	for id in ings:
		var ing: Variant = ings[id]
		if typeof(ing) == TYPE_DICTIONARY and String(ing.get("zone", "")) == zone:
			out.append(VarietyGen.type_name(String(id)))
	return out


static func _note_name(item: Dictionary) -> String:
	match String(item.get("kind", "")):
		"product":
			return kind_name(item, true)
		"nut":
			return _group_word("nut")
		"fresh":
			var ing: Dictionary = Data.ingredients().get(State.item_type(item), {})
			if ing.has("zone") or PantryRules.item_size(item) != Vector2i.ONE:
				return kind_name(item)
			return _group_word(String(ing.get("group", "")))
	return ""


static func _group_word(group: String) -> String:
	var key := "LET_GROUP_" + group.to_upper()
	var w := String(TranslationServer.translate(key))
	return group.capitalize() if w == key or w == "" else w.capitalize()
