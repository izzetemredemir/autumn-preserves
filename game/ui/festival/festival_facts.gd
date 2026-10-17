class_name FestivalFacts
extends RefCounted
## FESTIVAL · The facts on the festival's end card, read from the save and today's map. Pure: no autoloads, testable.
## The festival save keeps its start in state.flags.festival ({"day", "biome", "jams", "juice0"}; load_save adds
## "coins0" and "book0", the coins earned and the recipe count when the festival began).

const SAVE := "res://dev/festival_save.json"


## The festival save as a state dictionary (a temporary game: flags.temp), {} when missing or not a festival save.
static func load_save(path: String = SAVE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("save_seed") or not TodoRules.is_festival(parsed):
		return {}
	var d: Dictionary = parsed
	d.flags["temp"] = true  # never written to disk: the player's own save stays as it was
	var f: Dictionary = d.flags.festival
	f["coins0"] = int(d.get("stats", {}).get("coins_earned", 0))
	f["book0"] = d.get("book", {}).get("variants", {}).size()
	return d


## {"seed", "day", "tiles", "trees", "found", "new_recipes", "coins", "recipes"} for the end card. Today's map is
## generated again (same seed, same map), so the numbers are the very forest Granny walked.
static func summary(state: Dictionary) -> Dictionary:
	var f := TodoRules.festival(state)
	var day := int(state.get("day", 1))
	var map := WildGen.generate(int(state.get("save_seed", 0)), day, String(f.get("biome", "forest")),
		String(state.get("weather", "sunny")), state.get("varieties", {}))
	var tiles := 0
	var trees := 0
	if not map.is_empty():
		tiles = int(map.w) * int(map.h)
		trees = map.get("decor_trees", []).size() + map.get("fruit_trees", []).size()
	var variants: Dictionary = state.get("book", {}).get("variants", {})
	return {
		"seed": int(state.get("save_seed", 0)),
		"day": day,
		"tiles": tiles,
		"trees": trees,
		"found": state.get("found_varieties", []).size(),
		"new_recipes": maxi(variants.size() - int(f.get("book0", variants.size())), 0),
		"coins": maxi(int(state.get("stats", {}).get("coins_earned", 0)) - int(f.get("coins0", 0)), 0),
		"recipes": variants.size(),
	}


## 1440 -> "1,440" (sep ","), "1.440" (sep ".").
static func thousands(n: int, sep: String) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = sep + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
