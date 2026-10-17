class_name PantryRules
extends RefCounted
## SIM-03 · Pantry grid rules (spec §7.4). Board: {"name", "cols", "rows", "zones": Array (row-major zone per cell,
## "" = no cell)}. Shelves are 6 cols x 2 rows: dry (rows 0-1), room (2-3), cool (4-5); floor 4x2 below (rows 6-7).
## Each pantry_row upgrade adds a 6x2 shelf, zones in order room, cool, dry. state.pantry = {"rows_extra", "items": [{"item","x","y","rot"}]}.
## Extra keys on the board: "shelves": [{"zone", "y", "rows"}] top to bottom, "floor_y": first floor row.
## Extra shelves sit under the base shelves and push the floor down (use add_shelf to keep floor items on the floor).

## Zone of each bought shelf, in purchase order.
const EXTRA_SHELVES := ["room", "cool", "dry"]
## Placement size per product vessel, w x h in cells (spec §6.5).
const VESSEL_SIZE := {
	"jam_jar": Vector2i(1, 1), "pickle_jar": Vector2i(1, 1), "bottle": Vector2i(1, 2),
	"pie": Vector2i(2, 1), "bread": Vector2i(2, 1), "pumpkin": Vector2i(2, 2),
}
## Vessels the player may turn (pie and bread). Bottles always stand upright.
const ROTATABLE_VESSELS := ["pie", "bread"]
## Vessels that count as jars for the colour-order star.
const JAR_VESSELS := ["jam_jar", "pickle_jar"]
const NEIGHBOURS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func board(rows_extra: int = 0) -> Dictionary:
	var p: Dictionary = Data.rules().pantry
	var cols := int(p.cols)
	var shelf_rows := int(p.shelf_rows)
	var fl: Dictionary = p.floor
	var fcols := int(fl.cols)
	var frows := int(fl.rows)
	var shelf_zones: Array = []
	for z in p.shelves:
		shelf_zones.append(String(z))
	for i in maxi(rows_extra, 0):
		shelf_zones.append(EXTRA_SHELVES[i % EXTRA_SHELVES.size()])
	var width := maxi(cols, fcols)
	var zones: Array = []
	var shelves: Array = []
	var y := 0
	for z in shelf_zones:
		shelves.append({"zone": z, "y": y, "rows": shelf_rows})
		for _r in shelf_rows:
			for x in width:
				zones.append(z if x < cols else "")
		y += shelf_rows
	for _r in frows:
		for x in width:
			zones.append(String(fl.zone) if x < fcols else "")
	return {"name": "pantry", "cols": width, "rows": y + frows, "zones": zones, "shelves": shelves, "floor_y": y}


## Board of a saved pantry.
static func board_of(pantry: Dictionary) -> Dictionary:
	return board(int(pantry.get("rows_extra", 0)))


## Zone of a cell, "" when the cell is off the board or not a placement cell.
static func zone_at(b: Dictionary, cell: Vector2i) -> String:
	var cols := int(b.cols)
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= int(b.rows):
		return ""
	return String(b.zones[cell.y * cols + cell.x])


## Number of placement cells (44 at start, +12 per extra shelf).
static func cell_count(b: Dictionary) -> int:
	var n := 0
	for z in b.zones:
		if String(z) != "":
			n += 1
	return n


## Cells covered by an item: product size from its vessel, fresh/nut 1x1; rot 1 swaps w/h.
## Fresh items use the ingredient's "size" when it has one (pumpkin 2x2). Only pie and bread turn (can_rotate).
static func item_size(item: Dictionary, rot: int = 0) -> Vector2i:
	var s := _base_size(item)
	if posmod(rot, 2) == 1 and can_rotate(item):
		return Vector2i(s.y, s.x)
	return s


static func can_rotate(item: Dictionary) -> bool:
	return vessel_of(item) in ROTATABLE_VESSELS


## Recipe vessel of a product, "" for fresh items and nuts.
static func vessel_of(item: Dictionary) -> String:
	if String(item.get("kind", "")) != "product":
		return ""
	if FormulaGen.is_formula(String(item.get("key", ""))):  # FORMULA-KITCHEN: an invention's vessel
		return ProductGen.vessel(String(item.key))
	var recipe: Dictionary = Data.recipes().get(State.item_type(item), {})
	return String(recipe.get("vessel", ""))


static func _base_size(item: Dictionary) -> Vector2i:
	match String(item.get("kind", "")):
		"product":
			return VESSEL_SIZE.get(vessel_of(item), Vector2i.ONE)
		"fresh":
			var ing: Dictionary = Data.ingredients().get(State.item_type(item), {})
			var sz: Variant = ing.get("size", null)
			if sz is Array and sz.size() == 2:
				return Vector2i(int(sz[0]), int(sz[1]))
	return Vector2i.ONE


## Products: recipe zone. Fresh: ingredient "zone" if set, else floor for big items (pumpkin), else
## rules.pantry.group_zone by group. Nuts: group_zone.nut (dry).
static func zone_for(item: Dictionary) -> String:
	var p: Dictionary = Data.rules().pantry
	var gz: Dictionary = p.group_zone
	match String(item.get("kind", "")):
		"product":
			if FormulaGen.is_formula(String(item.get("key", ""))):  # FORMULA-KITCHEN: an invention's zone
				return ProductGen.zone(String(item.key))
			var recipe: Dictionary = Data.recipes().get(State.item_type(item), {})
			return String(recipe.get("zone", "room"))
		"nut":
			return String(gz.get("nut", "dry"))
		"fresh":
			var ing: Dictionary = Data.ingredients().get(State.item_type(item), {})
			if ing.has("zone"):
				return String(ing.zone)
			if _base_size(item) != Vector2i.ONE:
				return String(p.floor.zone)
			return String(gz.get(String(ing.get("group", "")), "cool"))
	return "room"


## Cells an item would cover with its top-left at `cell`.
static func cells_of(item: Dictionary, cell: Vector2i, rot: int = 0) -> Array:
	var s := item_size(item, rot)
	var out: Array = []
	for dy in s.y:
		for dx in s.x:
			out.append(cell + Vector2i(dx, dy))
	return out


static func entry_cells(entry: Dictionary) -> Array:
	return cells_of(entry.item, Vector2i(int(entry.x), int(entry.y)), int(entry.get("rot", 0)))


## {Vector2i cell: entry index} for every covered cell.
static func occupancy(entries: Array, ignore_index: int = -1) -> Dictionary:
	var taken := {}
	for i in entries.size():
		if i == ignore_index:
			continue
		for c in entry_cells(entries[i]):
			taken[c] = i
	return taken


static func can_place(b: Dictionary, entries: Array, item: Dictionary, cell: Vector2i, rot: int, ignore_index: int = -1) -> bool:
	return _fits(b, occupancy(entries, ignore_index), item, cell, rot, "")


## Every covered cell is on the board, free, and (when zone != "") in that zone.
static func _fits(b: Dictionary, taken: Dictionary, item: Dictionary, cell: Vector2i, rot: int, zone: String) -> bool:
	for c in cells_of(item, cell, rot):
		var z := zone_at(b, c)
		if z == "" or taken.has(c) or (zone != "" and z != zone):
			return false
	return true


static func _norm_rot(item: Dictionary, rot: int) -> int:
	return posmod(rot, 2) if can_rotate(item) else 0


static func place(pantry: Dictionary, item: Dictionary, cell: Vector2i, rot: int) -> bool:
	var r := _norm_rot(item, rot)
	if not can_place(board_of(pantry), pantry.items, item, cell, r):
		return false
	pantry.items.append({"item": item, "x": cell.x, "y": cell.y, "rot": r})
	return true


## Moves pantry entry `index` (drag inside the board). False and unchanged when it does not fit.
static func move(pantry: Dictionary, index: int, cell: Vector2i, rot: int) -> bool:
	var entry: Dictionary = pantry.items[index]
	var r := _norm_rot(entry.item, rot)
	if not can_place(board_of(pantry), pantry.items, entry.item, cell, r, index):
		return false
	entry.x = cell.x
	entry.y = cell.y
	entry.rot = r
	return true


## Every covered cell lies in the item's zone. Bare items (inbox, no x/y) are never in their zone.
static func in_correct_zone(b: Dictionary, entry: Dictionary) -> bool:
	if not entry.has("x") or not entry.has("item"):
		return false
	var zone := zone_for(entry.item)
	for c in entry_cells(entry):
		if zone_at(b, c) != zone:
			return false
	return true


## {"stars": 0..3, "rules": [bool, bool, bool]} (spec §7.4, independent rules)
## 1. At least rules.pantry.stars.correct_zone_ratio of the placed items are in their zone.
## 2. Every kind (State.item_type: recipe or ingredient type) is one orthogonally connected group, and one group
##    has at least stars.min_group items.
## 3. A shelf is completely full, or one shelf row holds stars.sorted_row_min jars side by side, left to right
##    light to dark by fill luminance (never lighter, not all equal). The colour branch needs `varieties`
##    (state.varieties) and ProductGen.describe; it is skipped while either is missing.
static func stars(pantry: Dictionary, varieties: Dictionary = {}) -> Dictionary:
	var b := board_of(pantry)
	var entries: Array = pantry.get("items", [])
	var checks := [
		rule_zones(b, entries),
		rule_groups(entries),
		rule_shelf(b, entries) or colour_sorted(b, entries, jar_luminances(entries, varieties)),
	]
	var n := 0
	for ok in checks:
		if ok:
			n += 1
	return {"stars": n, "rules": checks}


## stars() for a whole save state.
static func state_stars(state: Dictionary) -> Dictionary:
	return stars(state.pantry, state.get("varieties", {}))


static func rule_zones(b: Dictionary, entries: Array) -> bool:
	if entries.is_empty():
		return false
	var good := 0
	for e in entries:
		if in_correct_zone(b, e):
			good += 1
	var ratio := float(Data.rules().pantry.stars.correct_zone_ratio)
	return float(good) + 0.000001 >= ratio * entries.size()


static func rule_groups(entries: Array) -> bool:
	if entries.is_empty():
		return false
	var taken := occupancy(entries)
	var kinds: Array = []
	for e in entries:
		kinds.append(State.item_type(e.item))
	var seen := {}
	var groups_per_kind := {}
	var biggest := 0
	for i in entries.size():
		if seen.has(i):
			continue
		var size := 0
		var queue: Array = [i]
		seen[i] = true
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			size += 1
			for c in entry_cells(entries[cur]):
				for d in NEIGHBOURS:
					var j: int = taken.get(c + d, -1)
					if j >= 0 and not seen.has(j) and kinds[j] == kinds[cur]:
						seen[j] = true
						queue.append(j)
		groups_per_kind[kinds[i]] = int(groups_per_kind.get(kinds[i], 0)) + 1
		biggest = maxi(biggest, size)
	for k in groups_per_kind:
		if int(groups_per_kind[k]) > 1:
			return false
	return biggest >= int(Data.rules().pantry.stars.min_group)


## A shelf with every cell covered.
static func rule_shelf(b: Dictionary, entries: Array) -> bool:
	var taken := occupancy(entries)
	for sh in b.shelves:
		var full := true
		for r in int(sh.rows):
			for x in int(b.cols):
				var c := Vector2i(x, int(sh.y) + r)
				if zone_at(b, c) != "" and not taken.has(c):
					full = false
		if full:
			return true
	return false


## Colour-order branch of star 3. `lum` = {entry index: fill luminance} for jars (see jar_luminances).
static func colour_sorted(b: Dictionary, entries: Array, lum: Dictionary) -> bool:
	if lum.is_empty():
		return false
	var need := int(Data.rules().pantry.stars.sorted_row_min)
	var taken := occupancy(entries)
	for sh in b.shelves:
		for r in int(sh.rows):
			var run: Array = []
			for x in int(b.cols) + 1:
				var i: int = taken.get(Vector2i(x, int(sh.y) + r), -1)
				if i >= 0 and lum.has(i) and (run.is_empty() or float(lum[i]) <= float(run.back())):
					run.append(float(lum[i]))
					continue
				if run.size() >= need and float(run.front()) > float(run.back()):
					return true
				run = [float(lum[i])] if i >= 0 and lum.has(i) else []
	return false


## {entry index: luminance} of jar products, from ProductGen.describe(...).appearance.fill. Empty when
## `varieties` is empty or describe gives no fill yet.
static func jar_luminances(entries: Array, varieties: Dictionary) -> Dictionary:
	var out := {}
	if varieties.is_empty():
		return out
	var cache := {}
	for i in entries.size():
		var item: Dictionary = entries[i].item
		if not (vessel_of(item) in JAR_VESSELS):
			continue
		var key := String(item.key)
		if not cache.has(key):
			cache[key] = fill_luminance(ProductGen.describe(key, varieties))
		if float(cache[key]) >= 0.0:
			out[i] = cache[key]
	return out


## Mean luminance (0..1) of a describe() result's appearance.fill hex colours, -1 when there is none.
static func fill_luminance(desc: Dictionary) -> float:
	var app: Variant = desc.get("appearance", {})
	if typeof(app) != TYPE_DICTIONARY:
		return -1.0
	var fill: Variant = app.get("fill", [])
	if typeof(fill) != TYPE_ARRAY or fill.is_empty():
		return -1.0
	var total := 0.0
	for hex in fill:
		total += Color.html(String(hex)).get_luminance()
	return total / fill.size()


## Places each item in the first free cell of its zone (no grouping). Returns items that did not fit.
## Scan is row-major; pie/bread also try turned. No room in the zone -> first free floor spot -> leftover.
static func auto_arrange(pantry: Dictionary, incoming: Array) -> Array:
	var b := board_of(pantry)
	var floor_zone := String(Data.rules().pantry.floor.zone)
	var left: Array = []
	for item in incoming:
		var zone := zone_for(item)
		var spot := first_free(b, pantry.items, item, zone)
		if spot.is_empty() and zone != floor_zone:
			spot = first_free(b, pantry.items, item, floor_zone)
		if spot.is_empty():
			left.append(item)
			continue
		pantry.items.append({"item": item, "x": spot.cell.x, "y": spot.cell.y, "rot": spot.rot})
	return left


## First {"cell": Vector2i, "rot": int} where the item fits wholly inside `zone`, {} when none.
static func first_free(b: Dictionary, entries: Array, item: Dictionary, zone: String) -> Dictionary:
	var taken := occupancy(entries)
	var rots := [0, 1] if can_rotate(item) else [0]
	for y in int(b.rows):
		for x in int(b.cols):
			for r in rots:
				if _fits(b, taken, item, Vector2i(x, y), r, zone):
					return {"cell": Vector2i(x, y), "rot": r}
	return {}


## Buys one shelf: rows_extra + 1 and floor entries move down with the floor.
static func add_shelf(pantry: Dictionary) -> void:
	var floor_y := int(board_of(pantry).floor_y)
	var rows := int(Data.rules().pantry.shelf_rows)
	for e in pantry.items:
		if int(e.y) >= floor_y:
			e.y = int(e.y) + rows
	pantry.rows_extra = int(pantry.get("rows_extra", 0)) + 1


## DayEnd step 2 (spec §7.4): true when tonight's 1-day decay of a fresh item is skipped. `nights` = nights the
## item has spent in its correct zone, counting tonight (DayEnd keeps it in item.nights); every
## rules.pantry.fresh_skip_every_nth_night-th one skips. With `b`, the entry must also be in its zone on that board
## (bare inbox items never skip); without it the caller has already checked in_correct_zone.
static func fresh_decay_skips(entry: Dictionary, nights: int, b: Dictionary = {}) -> bool:
	var item: Dictionary = entry.get("item", entry)
	if String(item.get("kind", "")) != "fresh":
		return false
	if not b.is_empty() and not in_correct_zone(b, entry):
		return false
	var nth := int(Data.rules().pantry.fresh_skip_every_nth_night)
	return nth > 0 and nights > 0 and nights % nth == 0


## DayEnd step 1 (spec §7.4): true when a waiting product's wait_left counts down tonight, i.e. it is a product on
## the board in its correct zone. Wrong zone or inbox (bare item) -> the wait does not count.
static func wait_counts(b: Dictionary, entry: Dictionary) -> bool:
	var item: Dictionary = entry.get("item", entry)
	if String(item.get("kind", "")) != "product":
		return false
	return in_correct_zone(b, entry)
