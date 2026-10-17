class_name TodoRules
extends RefCounted
## Granny's To-Do steps (spec §8.5) and when each one counts as done. Pure: no autoloads, testable.
## Progress lives in state.flags.tutorial as bits: one per step, plus CLOSED_BIT once the player closes the note.
## ctx (from the overlay): {"scene": Router.current, "sold": true when coins came in without an order}.
## FESTIVAL: a save with state.flags.festival ({"day", "tree", "rare", "jams", "juice0", "letter"}, written by
## tools/scripts/make_festival.gd) shows the Harvest Festival checklist instead of a day list: six steps, each a
## different system, ticked by the same bits machinery (bits 16-21).

const DAYS := {
	1: ["d1_shake", "d1_jam", "d1_pantry", "d1_order", "d1_bed"],
	2: ["d2_forest", "d2_mushroom", "d2_brine", "d2_sell"],
}
const FESTIVAL := ["f_shake", "f_jam", "f_juice", "f_pantry", "f_market", "f_letter"]
const BITS := {
	"d1_shake": 0, "d1_jam": 1, "d1_pantry": 2, "d1_order": 3, "d1_bed": 4,
	"d2_forest": 8, "d2_mushroom": 9, "d2_brine": 10, "d2_sell": 11,
	"f_shake": 16, "f_jam": 17, "f_juice": 18, "f_pantry": 19, "f_market": 20, "f_letter": 21,
}
const CLOSED_BIT := 15
## Scene each step happens in, so scenes can make the step's object glow (spec §8.5).
const SCENE_OF := {
	"d1_shake": "garden", "d1_jam": "kitchen", "d1_pantry": "pantry", "d1_order": "town", "d1_bed": "kitchen",
	"d2_forest": "wild", "d2_mushroom": "wild", "d2_brine": "kitchen", "d2_sell": "town",
	"f_shake": "wild", "f_jam": "kitchen", "f_juice": "kitchen", "f_pantry": "pantry", "f_market": "town",
	"f_letter": "garden",
}


static func steps_for_day(day: int) -> Array:
	return DAYS.get(day, [])


## The list the note shows for this save: the festival checklist on festival day, else today's day list.
static func steps_for(state: Dictionary) -> Array:
	return FESTIVAL if festival_today(state) else steps_for_day(int(state.get("day", 1)))


## The festival's facts (flags.festival), {} for every other save.
static func festival(state: Dictionary) -> Dictionary:
	var f: Variant = state.get("flags", {}).get("festival")
	return f if typeof(f) == TYPE_DICTIONARY else {}


static func is_festival(state: Dictionary) -> bool:
	return not festival(state).is_empty()


## The festival lasts one day: after a night (keep playing, then bed) the checklist and the visitors are gone.
static func festival_today(state: Dictionary) -> bool:
	var f := festival(state)
	return not f.is_empty() and int(f.get("day", -1)) == int(state.get("day", 1))


static func key_of(step: String) -> String:
	return "TUT_" + step.to_upper()


## ONBOARD-GUIDE: Granny's one-line hint when the step becomes current (GuideArrow's bubble).
static func hint_key_of(step: String) -> String:
	return "TODO_HINT_" + step.to_upper()


static func bits_of(state: Dictionary) -> int:
	return int(state.get("flags", {}).get("tutorial", 0))


static func is_done(bits: int, step: String) -> bool:
	return bits & (1 << int(BITS[step])) != 0


static func is_closed(bits: int) -> bool:
	return bits & (1 << CLOSED_BIT) != 0


static func close(bits: int) -> int:
	return bits | (1 << CLOSED_BIT)


## Bits with every step of today's (and yesterday's) list that is now done switched on. Bits never switch off.
## Yesterday's list counts too, so the last step of a day ("go to bed") ticks once the new day starts.
static func evaluate(state: Dictionary, bits: int, ctx: Dictionary = {}) -> int:
	var out := bits
	var day := int(state.get("day", 1))
	var steps := steps_for_day(day) + steps_for_day(day - 1)
	if festival_today(state):
		steps = FESTIVAL
	for step in steps:
		if not is_done(out, step) and step_done(state, step, ctx):
			out |= 1 << int(BITS[step])
	return out


static func step_done(state: Dictionary, step: String, ctx: Dictionary = {}) -> bool:
	match step:
		"d1_shake":
			for t in state.get("garden", {}).get("trees", []):
				if t.get("type", "") == "apple" and not bool(t.get("fruit", true)):
					return true
			return false
		"d1_jam":
			return _made(state, ["jam"])
		"d1_pantry":
			for e in state.get("pantry", {}).get("items", []):
				if e.get("item", {}).get("kind", "") == "product":
					return true
			return false
		"d1_order":
			return int(state.get("stats", {}).get("orders_done", 0)) > 0
		"d1_bed":
			return int(state.get("day", 1)) >= 2
		"d2_forest":
			return ctx.get("scene", "") == "wild" or not state.get("wild_today", {}).is_empty()
		"d2_mushroom":
			return _has_mushroom(state)
		"d2_brine":
			return _made(state, ["brined_mushroom", "pickle"])
		"d2_sell":
			return bool(ctx.get("sold", false))
		"f_shake", "f_jam", "f_juice", "f_pantry", "f_market", "f_letter":
			return _festival_done(state, step)
	return false


## First step of today's list that is not done yet ("" when the list is finished or there is none).
static func current_step(state: Dictionary, bits: int) -> String:
	for step in steps_for(state):
		if not is_done(bits, step):
			return step
	return ""


static func day_finished(state: Dictionary, bits: int) -> bool:
	return current_step(state, bits) == ""


## Festival steps: the rare tree shaken; a jam (or family jam) that was not in the book at the start; more juice
## pressed than at the start; the pantry at 3 stars; the stall opened today; Mia's letter read.
static func _festival_done(state: Dictionary, step: String) -> bool:
	var f := festival(state)
	match step:
		"f_shake":
			var today: Dictionary = state.get("wild_today", {}).get(String(f.get("biome", "forest")), {})
			for id in today.get("shaken", []):
				if int(id) == int(f.get("tree", -1)):
					return true
			return state.get("found_varieties", []).has(String(f.get("rare", "")))
		"f_jam":
			var known: Array = f.get("jams", [])
			for key in state.get("book", {}).get("variants", {}):
				if is_jam(String(key)) and not known.has(String(key)):
					return true
			return false
		"f_juice":
			var n := 0
			var variants: Dictionary = state.get("book", {}).get("variants", {})
			for key in variants:
				if String(key).begins_with("juice|"):
					n += int(variants[key].get("count", 1))
			return n > int(f.get("juice0", 0))
		"f_pantry":
			return int(PantryRules.state_stars(state).get("stars", 0)) >= 3
		"f_market":
			var m: Variant = state.get("market", {})
			return typeof(m) == TYPE_DICTIONARY and int(m.get("last_day", 0)) >= int(f.get("day", 0)) \
				and int(f.get("day", 0)) > 0
		"f_letter":
			for l in state.get("letters", {}).get("inbox", []):
				if int(l.get("id", -1)) == int(f.get("letter", -2)):
					return bool(l.get("read", false))
			return false
	return false


## A jam or a family recipe of jam (Granny's Blackberry Honey Jam ...).
static func is_jam(key: String) -> bool:
	var rid := key.split("|")[0]
	return rid == "jam" or String(Data.recipes().get(rid, {}).get("family_of", "")) == "jam"


static func _made(state: Dictionary, recipes: Array) -> bool:
	for key in state.get("book", {}).get("variants", {}):
		if String(key).split("|")[0] in recipes:
			return true
	return false


static func _has_mushroom(state: Dictionary) -> bool:
	var ids: Array = state.get("found_varieties", []).duplicate()
	var items: Array = state.get("bag", []) + state.get("inbox", [])
	for e in state.get("pantry", {}).get("items", []):
		items.append(e.get("item", {}))
	for item in items:
		if item.get("kind", "") == "fresh":
			ids.append(item.get("variety", ""))
	var ingredients := Data.ingredients()
	for id in ids:
		var t := State.type_of_variety(String(id))
		if ingredients.has(t) and ingredients[t].get("group", "") == "mushroom":
			return true
	return false
