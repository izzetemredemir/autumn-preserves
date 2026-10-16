class_name Data
extends RefCounted
## Read-only game tables from res://data/*.json (tech-spec §3), cached after the first read.
## JSON numbers arrive as floats: wrap with int() where an int is needed.

static var _cache: Dictionary = {}


static func table(table_name: String) -> Dictionary:
	if not _cache.has(table_name):
		var path := "res://data/%s.json" % table_name
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Data: cannot parse " + path)
			parsed = {}
		parsed.erase("_doc")
		_cache[table_name] = parsed
	return _cache[table_name]


static func ingredients() -> Dictionary:
	return table("ingredients")


static func recipes() -> Dictionary:
	return table("recipes")


static func addins() -> Dictionary:
	return table("addins")


static func grammar() -> Dictionary:
	return table("grammar")


static func npcs() -> Dictionary:
	return table("npcs")


static func shop() -> Dictionary:
	return table("shop")


static func rules() -> Dictionary:
	return table("rules")


## Ids of a table whose "priority" is <= max_priority (P0 = 0).
static func ids_up_to(table_name: String, max_priority: int) -> Array:
	var out: Array = []
	var t := table(table_name)
	for id in t:
		var row: Variant = t[id]
		if typeof(row) == TYPE_DICTIONARY and int(row.get("priority", 0)) <= max_priority:
			out.append(id)
	out.sort()
	return out
