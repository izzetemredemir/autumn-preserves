class_name TodoRules
extends RefCounted
## Granny's To-Do steps (spec §8.5) and when each one counts as done. Pure: no autoloads, testable.
## Progress lives in state.flags.tutorial as bits: one per step, plus CLOSED_BIT once the player closes the note.
## ctx (from the overlay): {"scene": Router.current, "sold": true when coins came in without an order}.

const DAYS := {
	1: ["d1_shake", "d1_jam", "d1_pantry", "d1_order", "d1_bed"],
	2: ["d2_forest", "d2_mushroom", "d2_brine", "d2_sell"],
}
const BITS := {
	"d1_shake": 0, "d1_jam": 1, "d1_pantry": 2, "d1_order": 3, "d1_bed": 4,
	"d2_forest": 8, "d2_mushroom": 9, "d2_brine": 10, "d2_sell": 11,
}
const CLOSED_BIT := 15
## Scene each step happens in, so scenes can make the step's object glow (spec §8.5).
const SCENE_OF := {
	"d1_shake": "garden", "d1_jam": "kitchen", "d1_pantry": "pantry", "d1_order": "town", "d1_bed": "kitchen",
	"d2_forest": "wild", "d2_mushroom": "wild", "d2_brine": "kitchen", "d2_sell": "town",
}


static func steps_for_day(day: int) -> Array:
	return DAYS.get(day, [])


static func key_of(step: String) -> String:
	return "TUT_" + step.to_upper()


static func bits_of(state: Dictionary) -> int:
	return int(state.get("flags", {}).get("tutorial", 0))


static func is_done(bits: int, step: String) -> bool:
	return bits & (1 << int(BITS[step])) != 0


static func is_closed(bits: int) -> bool:
	return bits & (1 << CLOSED_BIT) != 0


static func close(bits: int) -> int:
	return bits | (1 << CLOSED_BIT)


## Bits with every step of today's list that is now done switched on. Bits never switch off.
static func evaluate(state: Dictionary, bits: int, ctx: Dictionary = {}) -> int:
	var out := bits
	for step in steps_for_day(int(state.get("day", 1))):
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
	return false


## First step of today's list that is not done yet ("" when the list is finished or there is none).
static func current_step(state: Dictionary, bits: int) -> String:
	for step in steps_for_day(int(state.get("day", 1))):
		if not is_done(bits, step):
			return step
	return ""


static func day_finished(state: Dictionary, bits: int) -> bool:
	return current_step(state, bits) == ""


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
