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
const OBJECTS := ["teo", "hat", "chair", "nora", "toys", "window", "jar"]


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
