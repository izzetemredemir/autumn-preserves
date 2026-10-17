class_name FinaleRules
extends RefCounted
## ENDING · The visit (docs/story.md §6): Nora and the grandchildren come on the morning of day 30, the story ends,
## the save goes on. Pure rules, no autoloads, no disk, no RNG: when the finale plays, Tonty's note as i18n lines
## [{"key", "args"}] (the view translates with tr(key) % args), Nora's second letter (day 10) and the two P.S. lines
## that hint at the visit (days 20 and 26, picked by day). No countdown is ever shown.
## Save keys (old saves lack them: always get(key, default)):
##   flags.story.finale_seen (bool, the visit was watched to the end; the badge, the skip and the garden visit)
##   flags.story.visit_ps (Array of P.S. numbers already written: VISIT_PS)

## The morning of this day is the visit. A save that is already past it never gets the finale.
const DAY := 30
## After the visit the grandchildren play in the garden for this many days (DAY + 1 .. DAY + VISIT_DAYS).
const VISIT_DAYS := 7
## Nora's second letter: it arrives on the morning of this day (or the next morning of an older save, before DAY).
const NORA2_DAY := 10
const NORA2_ID := -1  ## story letters have ids <= 0 (no clash with Letters next_id)
const NORA2_LINES := ["STORY_LETTER_NORA2_DEAR", "STORY_LETTER_NORA2_1", "STORY_LETTER_NORA2_2",
	"STORY_LETTER_NORA2_3", "STORY_LETTER_NORA2_SIGN"]
## The visit's P.S. lines LET_PS_STORY_<n>: {n: from day}. Line n goes on the first request letter written on or after
## its day, whichever child writes it (the letters alternate, so it cannot slip past the visit).
const VISIT_PS := {5: 20, 6: 26}


static func flags(state: Dictionary) -> Dictionary:
	var f: Variant = state.get("flags", {})
	return f if typeof(f) == TYPE_DICTIONARY else {}


## flags.story, read only ({} for older saves).
static func story(state: Dictionary) -> Dictionary:
	var s: Variant = flags(state).get("story", {})
	return s if typeof(s) == TYPE_DICTIONARY else {}


## flags.story, created when missing (for writing).
static func story_rw(state: Dictionary) -> Dictionary:
	if typeof(state.get("flags")) != TYPE_DICTIONARY:
		state["flags"] = {}
	if typeof(state.flags.get("story")) != TYPE_DICTIONARY:
		state.flags["story"] = {}
	return state.flags.story


static func seen(state: Dictionary) -> bool:
	return bool(story(state).get("finale_seen", false))


## The title's "Visited" badge.
static func visited(state: Dictionary) -> bool:
	return seen(state)


## Does the visit play now? On day DAY exactly, once per save, never in a closed or Memory save.
static func due(state: Dictionary) -> bool:
	if state.is_empty() or Farewell.is_completed(state) or Farewell.is_memory(state):
		return false
	return int(state.get("day", 1)) == DAY and not seen(state)


static func mark_seen(state: Dictionary) -> void:
	story_rw(state)["finale_seen"] = true


## The week after the visit: Mia and Leo play in the garden (looks only).
static func kids_visiting(state: Dictionary) -> bool:
	var day := int(state.get("day", 1))
	return seen(state) and day > DAY and day <= DAY + VISIT_DAYS


# --- letters -----------------------------------------------------------------------------------------------------

## Nora's second letter into the mailbox from the morning of NORA2_DAY on (before the visit only). Once.
## Returns the letter, {} when none was added. Letters.night calls it; no RNG.
static func add_nora_letter(state: Dictionary) -> Dictionary:
	var day := int(state.get("day", 1))
	if day < NORA2_DAY or day >= DAY or typeof(state.get("letters")) != TYPE_DICTIONARY:
		return {}
	var inbox: Array = state.letters.get("inbox", [])
	for l in inbox:
		if int(l.get("id", 1)) == NORA2_ID:
			return {}
	var letter := {"id": NORA2_ID, "kind": "story", "from": "nora", "day": day, "lines": NORA2_LINES.duplicate(),
		"read": false}
	inbox.append(letter)
	return letter


## The visit's P.S. number for a new letter written on `day` (0: none): the first line not yet written whose day has
## come, never on or after the visit. At most one per letter.
static func visit_ps(state: Dictionary, day: int) -> int:
	var given: Array = story(state).get("visit_ps", [])
	var keys: Array = VISIT_PS.keys()
	keys.sort()
	for n in keys:
		if not int(n) in given and day >= int(VISIT_PS[n]) and day < DAY:
			return int(n)
	return 0


## Puts the due visit P.S. on a new request letter (letter.ps_story, shown by the letters screen). A letter that
## already carries a story P.S. keeps it.
static func add_ps(state: Dictionary, letter: Dictionary) -> void:
	if int(letter.get("ps_story", 0)) > 0:
		return
	var n := visit_ps(state, int(letter.get("day", state.get("day", 1))))
	if n <= 0:
		return
	letter["ps_story"] = n
	var s := story_rw(state)
	var given: Array = s.get("visit_ps", [])
	given.append(n)
	s["visit_ps"] = given


# --- Tonty's note ----------------------------------------------------------------------------------------------

## Tonty's note to the grandchildren on the visit morning (story.md §6.2), built from the save: days in Everfall,
## jars made, the best jar in the pantry, the rarest variety found. Empty pantry, one jar, no rare find and other
## than two grandchildren use the farewell's fallback lines. `lang_code` "" = the current locale (product names).
static func note(state: Dictionary, lang_code: String = "") -> Array:
	var out: Array = []
	var kids := Farewell.kid_names()
	out.append(_l("FINALE_NOTE_DEAR_TWO", kids) if kids.size() == 2 else _l("FAREWELL_LETTER_DEAR", []))
	out.append(_l("FINALE_NOTE_DAYS", [int(state.get("day", DAY))]))
	var made := int(state.get("stats", {}).get("jars_made", 0))
	if made > 1:
		out.append(_l("FINALE_NOTE_JARS", [made]))
	elif made == 1:
		out.append(_l("FAREWELL_LETTER_JARS_ONE", []))
	else:
		out.append(_l("FAREWELL_LETTER_JARS_NONE", []))
	var top: Array = Farewell.top_jars(state, 1)
	if top.is_empty():
		out.append(_l("FAREWELL_LETTER_TOP_NONE", []))
	else:
		var jar_name := ProductGen.product_name(String(top[0].key), state.get("varieties", {}), lang_code)
		if ProductGen.lang(lang_code) == "tr":
			jar_name = accusative_tr(jar_name)
		out.append(_l("FINALE_NOTE_TOP", [jar_name]))
	var rare := Farewell.rarest_variety(state)
	if rare.is_empty():
		out.append(_l("FAREWELL_LETTER_RARE_NONE", []))
	else:
		out.append(_l("FINALE_NOTE_RARE", [VarietyGen.display_name(rare, lang_code)]))
	out.append(_l("FINALE_NOTE_TEO", []))
	out.append(_l("FINALE_NOTE_BOOTS", []))
	out.append(_l("FINALE_NOTE_SIGN", []))
	return out


## Turkish accusative of a name, with an apostrophe: "Elma Reçeli" -> "Elma Reçeli'ni", "Kızıl Şurup" -> "Kızıl Şurup'u".
static func accusative_tr(word: String) -> String:
	if word == "":
		return word
	var buffer := "n" if Turkish.is_vowel(word[word.length() - 1]) else ""
	return "%s'%s%s" % [word, buffer, Turkish.harmony4(word)]


static func _l(key: String, args: Array) -> Dictionary:
	return {"key": key, "args": args}
