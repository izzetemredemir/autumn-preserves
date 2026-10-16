class_name Calendar
extends RefCounted
## CALENDAR-WEATHER · Harvest calendar (spec §7.11) and the P1 weather (spec §7.10). Pure; tables in rules.calendar.
## Days before rules.calendar.start_day (8) are the flat tutorial week: no week, flat type weights and the P0 weather
## table, so every day-1..7 map and weather stays exactly as it was. From day 8 the weeks of rules.calendar.weeks repeat
## forever (Grape Harvest, Apple Moon, First Frost; the second round is "Autumn 2", ...). A week's types weigh
## abundance_mult (×2) wherever the wild draws a type (WildGen); nothing ever disappears. The weather uses table "p1".
## Windy days (windfall): every fruit tree has already dropped one fruit on the ground under it.

## Windfall tiles around a fruit tree (its own tile is solid), in order of preference: straight under it first.
const WINDFALL_SPOTS := [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 2),
	Vector2i(-1, 2), Vector2i(1, 2)]


static func cfg() -> Dictionary:
	return Data.rules().get("calendar", {})


static func start_day() -> int:
	return int(cfg().get("start_day", 8))


static func week_days() -> int:
	return maxi(int(cfg().get("week_days", 7)), 1)


static func weeks() -> Array:
	return cfg().get("weeks", [])


## True from start_day on (the tutorial week has no calendar).
static func active(day: int) -> bool:
	return day >= start_day() and not weeks().is_empty()


## Index into rules.calendar.weeks, -1 before the calendar starts.
static func week_index(day: int) -> int:
	if not active(day):
		return -1
	return floori(float(day - start_day()) / week_days()) % weeks().size()


## Round of the cycle: 1 for the first three weeks, 2 for "Autumn 2", ...; 0 before the calendar starts.
static func cycle(day: int) -> int:
	if not active(day):
		return 0
	return 1 + floori(float(day - start_day()) / (week_days() * weeks().size()))


## The week's row {"id", "types"}, {} before the calendar starts.
static func week(day: int) -> Dictionary:
	var i := week_index(day)
	return weeks()[i] if i >= 0 else {}


static func week_id(day: int) -> String:
	return String(week(day).get("id", ""))


## Translation key of the week's name ("UI_WEEK_APPLE_MOON"), "" before the calendar starts.
static func week_key(day: int) -> String:
	var id := week_id(day)
	return "UI_WEEK_" + id.to_upper() if id != "" else ""


static func first_day_of_week(day: int) -> bool:
	return active(day) and (day - start_day()) % week_days() == 0


## The week's plentiful types (every source: wild, garden beds), [] before the calendar starts.
static func abundant(day: int) -> Array:
	return week(day).get("types", [])


## Weight multiplier of an ingredient type on `day`: abundance_mult for the week's types, else 1.
static func type_mult(day: int, type: String) -> float:
	return float(cfg().get("abundance_mult", 2)) if abundant(day).has(type) else 1.0


## `base` weights (1 each when empty) times type_mult, one per type.
static func type_weights(day: int, types: Array, base: Array = []) -> Array:
	var out: Array = []
	for i in types.size():
		var b := float(base[i]) if i < base.size() else 1.0
		out.append(b * type_mult(day, String(types[i])))
	return out


## The week's types a wild map can hold (no bed-only crops): what the morning card lists as in season.
static func wild_types(day: int) -> Array:
	var ing := Data.ingredients()
	var out: Array = []
	for t in abundant(day):
		var row: Dictionary = ing.get(t, {})
		for s in row.get("sources", []):
			var src := String(s)
			if src != "bed" and src != "garden_tree":
				out.append(t)
				break
	return out


## rules.weather table of `day`: "p0" in the tutorial week (sunny/rainy), "p1" from start_day (windy, foggy too).
static func weather_table(day: int) -> String:
	return "p1" if active(day) and Data.rules().weather.has("p1") else "p0"


## Windy day (spec §7.10): each fruit tree of `map` (WildGen.generate output) has dropped one fruit. Appends one ground
## pickup per tree {"kind": "ground", "type", "variety" of the tree, "windfall": true, "tree": tree id}, on the first
## free reachable tile of WINDFALL_SPOTS. No RNG: same map, same windfall. Ids continue after the last pickup, so
## nothing already on the map changes. Returns the number added.
static func windfall(map: Dictionary) -> int:
	if map.is_empty():
		return 0
	var w := int(map.w)
	var h := int(map.h)
	var taken := {}
	for p in map.pickups:
		taken[Vector2i(int(p.x), int(p.y))] = true
	var entrance: Vector2i = map.entrance
	var reach := _reach(map)
	var added := 0
	for t in map.fruit_trees:
		for off: Vector2i in WINDFALL_SPOTS:
			var c := Vector2i(int(t.x), int(t.y)) + off
			if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h or c == entrance or taken.has(c):
				continue
			var i := c.y * w + c.x
			if reach[i] == 0 or int(map.ground[i]) == WildGen.T_STONE:
				continue
			taken[c] = true
			map.pickups.append({"id": (map.pickups as Array).size(), "x": c.x, "y": c.y, "kind": "ground",
				"type": String(t.type), "variety": String(t.variety), "windfall": true, "tree": int(t.id)})
			added += 1
			break
	return added


## 1 = walkable and reachable from the entrance (4-neighbour flood over WildGen.is_walkable tiles).
static func _reach(map: Dictionary) -> PackedByteArray:
	var w := int(map.w)
	var h := int(map.h)
	var reach := PackedByteArray()
	reach.resize(w * h)
	var e: Vector2i = map.entrance
	if not WildGen.is_walkable(map, e):
		return reach
	reach[e.y * w + e.x] = 1
	var queue: Array[Vector2i] = [e]
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := p + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or reach[n.y * w + n.x] == 1:
				continue
			if WildGen.is_walkable(map, n):
				reach[n.y * w + n.x] = 1
				queue.append(n)
	return reach
