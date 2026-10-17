class_name Story
extends RefCounted
## STORY-03 · The small story pieces about Teo (docs/story.md §4.4-4.7). Pure rules, no RNG, no economy.
## state.flags.story (always read with get(key, default), so older saves load):
##   {"npc_said": [neighbour ids who told their Teo line], "teo_letter_seen": bool}
## The grandchildren's P.S. lines are picked by letter index (Letters.make_request: letter.ps_story = 1..PS_COUNT).

const PS_COUNT := 4
## Who writes each story P.S. (line n is by PS_KIDS[n-1]); a line waits for the next letter of that child.
const PS_KIDS := ["leo", "mia", "leo", "mia"]
const TEO_LINES := 7
## Neighbours' Teo lines: shown from this many hearts (Rosie's only on festival day).
const NPC_HEARTS := 2
const FESTIVAL_NPC := "baker"


static func flags(state: Dictionary) -> Dictionary:
	var f: Dictionary = state.get("flags", {})
	if typeof(f.get("story")) != TYPE_DICTIONARY:
		f["story"] = {}
		state["flags"] = f
	return f.story


## Next story P.S. index for a letter from `kid` (0: none due). Advances the counter when it hands one out.
static func take_ps(state: Dictionary, kid: String) -> int:
	var s := flags(state)
	var n := int(s.get("ps_next", 1))
	if n > PS_COUNT or PS_KIDS[n - 1] != kid:
		return 0
	s["ps_next"] = n + 1
	return n


## The neighbour's Teo line key, "" when there is none to show now (not yet at 2 hearts, already said, Rosie off festival day).
static func npc_line_due(state: Dictionary, npc_id: String, hearts: int, festival_today: bool) -> String:
	if npc_id in flags(state).get("npc_said", []):
		return ""
	if npc_id == FESTIVAL_NPC:
		if not festival_today:
			return ""
	elif hearts < NPC_HEARTS:
		return ""
	return "STORY_NPC_" + _npc_key(npc_id)


static func mark_npc_said(state: Dictionary, npc_id: String) -> void:
	var s := flags(state)
	var said: Array = s.get("npc_said", [])
	if not npc_id in said:
		said.append(npc_id)
	s["npc_said"] = said


static func _npc_key(npc_id: String) -> String:
	return npc_id.to_upper()


## Teo's letter exists once the first family recipe is unlocked.
static func teo_letter_open(state: Dictionary) -> bool:
	var l: Variant = state.get("letters")
	return typeof(l) == TYPE_DICTIONARY and not l.get("unlocked_recipes", []).is_empty()


## True once, on the first book opening after the letter appeared (marks it seen).
static func teo_letter_new(state: Dictionary) -> bool:
	if not teo_letter_open(state) or bool(flags(state).get("teo_letter_seen", false)):
		return false
	flags(state)["teo_letter_seen"] = true
	return true


## STORY-02 · The seven things the parlour remembers (docs/story.md §4.3). `flags.story.seen` lists those looked at
## once (the first look gets a small heart); `jar_filled` latches once the first jar stood on the shelf.
const OBJECTS := ["teo", "hat", "chair", "nora", "toys", "window", "jar", "knife"]


static func seen(state: Dictionary, id: String) -> bool:
	return id in flags(state).get("seen", [])


## Records the first look at `id`; true only that first time.
static func mark_seen(state: Dictionary, id: String) -> bool:
	var s := flags(state)
	var list: Array = s.get("seen", [])
	if id in list or not id in OBJECTS:
		return false
	list.append(id)
	s["seen"] = list
	return true


## True once a first jar is shelved (the pantry holds something); stays true afterwards.
static func jar_filled(state: Dictionary) -> bool:
	var s := flags(state)
	if bool(s.get("jar_filled", false)):
		return true
	var p: Variant = state.get("pantry")
	if typeof(p) == TYPE_DICTIONARY and not p.get("items", []).is_empty():
		s["jar_filled"] = true
		return true
	return false


## The string key of the line for `id` now.
static func object_key(state: Dictionary, id: String) -> String:
	if id == "jar" and jar_filled(state):
		return "STORY_OBJ_JAR_FILLED"
	return "STORY_OBJ_" + id.to_upper()


## STORY-04 · Teo's knife in the forest (docs/story.md §7). Once per save (`flags.story.knife_found`, read with get so
## older saves load): from day 2 on, the first forest visit finds a sparkle at the foot of the map's first fruit tree.
## No RNG: the cell is derived from the finished map, so no pickup list or surprise plan shifts. Picking it up puts
## nothing in the bag (no coins, no energy); it becomes the parlour's 8th memory object.
const KNIFE_FIRST_DAY := 2
## The 8 cells around a tree foot, nearest the viewer first.
const _KNIFE_RING := [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1)]


static func knife_found(state: Dictionary) -> bool:
	return bool(flags(state).get("knife_found", false))


## True while the knife still waits for this save (forest, day 2 or later).
static func knife_due(state: Dictionary) -> bool:
	return int(state.get("day", 1)) >= KNIFE_FIRST_DAY and not knife_found(state)


## Records the find; true only the first time.
static func mark_knife_found(state: Dictionary) -> bool:
	if knife_found(state):
		return false
	flags(state)["knife_found"] = true
	return true


## The knife's cell on a finished forest map, (-1, -1) when there is none. Plain walkable ground that the entrance
## reaches, beside the first fruit tree that is not part of the special place, off every tree and pickup.
static func knife_cell(map: Dictionary) -> Vector2i:
	if map.is_empty() or String(map.get("biome", "")) != "forest":
		return Vector2i(-1, -1)
	var w := int(map.w)
	var h := int(map.h)
	var taken := {}
	for key in ["decor_trees", "fruit_trees", "pickups"]:
		for t in map.get(key, []):
			taken[Vector2i(int(t.x), int(t.y))] = true
	var sp_rect := Rect2i()
	var special: Dictionary = map.get("special", {})
	if special.has("x"):
		sp_rect = Rect2i(int(special.x), int(special.y), int(special.get("w", 1)), int(special.get("h", 1))).grow(1)
	var reach := SpeciesGen.reach_map(map)
	for tree: Dictionary in map.get("fruit_trees", []):
		if tree.get("special", false):
			continue
		var base := Vector2i(int(tree.x), int(tree.y))
		for d: Vector2i in _KNIFE_RING:
			var c := base + d
			if c.x < 1 or c.y < 1 or c.x >= w - 1 or c.y >= h - 1 or taken.has(c):
				continue
			var g := int(map.ground[c.y * w + c.x])
			if g != WildGen.T_GRASS and g != WildGen.T_LEAVES and g != WildGen.T_DIRT:
				continue
			if reach[c.y * w + c.x] != 1 or (sp_rect.size != Vector2i.ZERO and sp_rect.has_point(c)):
				continue
			return c
	return Vector2i(-1, -1)
