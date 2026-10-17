class_name Data
extends RefCounted
## Read-only game tables from res://data/*.json (tech-spec §3), cached after the first read.
## JSON numbers arrive as floats: wrap with int() where an int is needed.

static var _cache: Dictionary = {}
## SPECIES-GEN: generated ingredient rows (SpeciesGen), id -> row, and the merged view ingredients() hands out.
static var _generated: Dictionary = {}
static var _merged: Dictionary = {}


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


## ingredients.json rows plus the generated species registered this session (register_generated). ids_up_to() and
## table("ingredients") stay the base rows only, so variety, garden and forest generation never see a species.
static func ingredients() -> Dictionary:
	if _generated.is_empty():
		return table("ingredients")
	if _merged.is_empty():
		_merged = table("ingredients").duplicate()
		_merged.merge(_generated)
	return _merged


## SPECIES-GEN runtime registry: adds (or replaces) a generated ingredient row. A row's "display_name_tr" also becomes
## grammar tr.types[id] (VarietyGen.type_name), and the id joins tr.compound_types when that name is already a
## compound ("Kor Eriği"). Ids are unique per save (SpeciesGen), so rows of several saves can live side by side.
static func register_generated(id: String, row: Dictionary) -> void:
	_generated[id] = row
	_merged = {}
	var gtr: Dictionary = grammar().get("tr", {})
	if gtr.is_empty():
		return
	if row.has("display_name_tr"):
		gtr.get("types", {})[id] = String(row.display_name_tr)
	var ct: Array = gtr.get("compound_types", [])
	if bool(row.get("compound_tr", false)) and not ct.has(id):
		ct.append(id)


static func generated() -> Dictionary:
	return _generated


## Drops every generated row (tests).
static func clear_generated() -> void:
	var gtr: Dictionary = grammar().get("tr", {})
	for id in _generated:
		gtr.get("types", {}).erase(id)
		gtr.get("compound_types", []).erase(id)
	_generated.clear()
	_merged = {}


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
