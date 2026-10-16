extends SceneTree
## DEMO-01 · Builds the deterministic demo save for the 3-minute jury demo. Sim classes only (no autoloads).
##   godot --headless --path game -s res://tests/make_demo_save.gd
## Searches save seeds for a rainy day 2-4 whose forest has the rare crabapple within MAX_DIST tiles of the
## entrance and a mushroom ring, plays the fresh game to that day, then edits it into a demo-friendly state.
## Not a unit test (file name does not start with test_). Writes res://dev/demo_save.json.

const OUT := "res://dev/demo_save.json"
const SEED_MAX := 5000
const MAX_DIST := 12.0       # tiles from the entrance to the rare crabapple tree
const DEMO_RECIPE := "jam"
const DEMO_ADDIN := "cinnamon"
const DEMO_QUALITY := 3
## [recipe, main type, second type, add-in, quality, put one jar in the pantry]. Variety is the first (sorted) of the type.
const BOOK := [
	["jam", "apple", "", "", 2, 1],
	["jam", "apple", "", "honey", 3, 1],
	["jam", "blackberry", "", "cinnamon", 2, 0],
	["fruit_butter", "apple", "", "", 3, 1],
	["jam", "quince", "", "ginger", 2, 0],
	["chutney", "apple", "cucumber", "", 2, 1],
	["pickle", "cucumber", "", "", 3, 1],
	["pickle", "pepper", "", "chili", 2, 0],
	["brined_mushroom", "chanterelle", "", "", 2, 1],
]


func _init() -> void:
	var hit := _search()
	if hit.is_empty():
		printerr("make_demo_save: no seed in 1..%d satisfies all three rules" % SEED_MAX)
		quit(1)
		return
	var s := _build(hit)
	if s.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://dev"))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		printerr("make_demo_save: cannot write %s" % OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(s, "\t"))
	f.close()
	quit(0)


## First seed (then day) with a rainy day 2..4, a rare crabapple tree near the entrance and a mushroom ring.
func _search() -> Dictionary:
	for sd in range(1, SEED_MAX + 1):
		var varieties := VarietyGen.generate_all(sd, 0)
		var rare := ""
		for id in varieties:
			if varieties[id].type == "crabapple" and varieties[id].rarity == "rare":
				rare = id
		if rare == "":
			continue
		for day in range(2, 5):
			if DayEnd.weather_for(sd, day, "") != "rainy":
				continue
			# The jar name must keep the variety's feature word (28-character cap), like "Cinnamon Ember Crabapple Jam".
			var jar_name := ProductGen.product_name(ProductGen.make_key(DEMO_RECIPE, [rare], DEMO_ADDIN), varieties)
			if not jar_name.contains(String(varieties[rare].name).split(" ")[0]):
				continue
			var map := WildGen.generate(sd, day, "forest", "rainy", varieties)
			if String(map.special.get("kind", "")) != "mushroom_ring":
				continue
			var best := {}
			for t in map.fruit_trees:
				if t.type == "crabapple" and t.variety == rare:
					var d := Vector2(t.x - map.entrance.x, t.y - map.entrance.y).length()
					if d <= MAX_DIST and (best.is_empty() or d < best.dist):
						best = {"x": int(t.x), "y": int(t.y), "dist": d}
			if not best.is_empty():
				return {"seed": sd, "day": day, "rare": rare, "tree": best, "entrance": map.entrance}
	return {}


func _build(hit: Dictionary) -> Dictionary:
	var s := State.new_game(int(hit.seed))
	while int(s.day) < int(hit.day):
		DayEnd.run(s)
	if s.weather != "rainy":
		printerr("make_demo_save: day %d is not rainy after the nights" % hit.day)
		return {}
	var v: Dictionary = s.varieties
	# Lived-in recipe book: cook with a full cupboard and fresh inputs, then clean the leftovers up.
	s.cupboard = {"jar": 30, "sugar": 30, "salt": 30, "vinegar": 30, "honey": 5, "cinnamon": 5, "ginger": 5, "clove": 5, "chili": 5}
	s.inbox = []
	var jars: Array = []
	for row in BOOK:
		var main := _first_of(v, row[1])
		var second := _first_of(v, row[2]) if row[2] != "" else ""
		for id in [main, second]:
			if id != "":
				s.inbox.append(State.fresh(id, 5, 5))
		s.energy = int(s.energy_max)
		var res := Kitchen.cook(s, row[0], main, second, row[3], row[4])
		if not res.ok:
			printerr("make_demo_save: cook failed %s: %s %s" % [row, res.reason, res.missing])
			return {}
		if int(row[5]) > 0:
			jars.append(State.product(res.item.key, row[4], 0, int(res.item.days_left)))
	s.inbox = []
	s.pantry = {"rows_extra": 0, "items": []}
	for item in jars:
		_shelve(s, item)
	s.cupboard = {"jar": 8, "sugar": 6, "salt": 3, "vinegar": 3, "cinnamon": 2}
	s.coins = 300
	s.energy = int(s.energy_max)
	s.flags.tutorial = _tutorial_done()
	# The demo jar and the baker's order.
	var key := ProductGen.make_key(DEMO_RECIPE, [hit.rare], DEMO_ADDIN)
	var order := {"id": int(s.next_order_id), "npc": "baker", "recipe": "", "axes": ["sweet", "spicy"], "min_stars": 1,
		"made_day": int(s.day), "expires_day": int(s.day) + 5}
	s.next_order_id = int(s.next_order_id) + 1
	var kept: Array = []
	for o in s.orders:
		if o.npc != "baker" and kept.size() < 2:
			kept.append(o)
	kept.push_front(order)
	s.orders = kept
	var demo_item := State.product(key, DEMO_QUALITY, 0)
	if not Orders.matches(order, demo_item, v):
		printerr("make_demo_save: the demo jar does not satisfy the baker order")
		return {}
	if s.book.variants.has(key):
		printerr("make_demo_save: the demo variant is already in the book")
		return {}
	var d := ProductGen.describe(key, v)
	print("seed=%d day=%d weather=%s" % [hit.seed, hit.day, s.weather])
	print("rare crabapple: %s (%s)" % [hit.rare, v[hit.rare].name])
	print("tree tile=(%d,%d) entrance=(%d,%d) distance=%.1f" % [hit.tree.x, hit.tree.y, hit.entrance.x, hit.entrance.y, hit.tree.dist])
	print("demo jar: %s taste=%s %s harmony=%d value=%d key=%s" % [d.name, d.taste, d.profile_label, d.harmony,
		ProductGen.value(key, v, DEMO_QUALITY), key])
	print("book variants=%d pantry jars=%d" % [s.book.variants.size(), s.pantry.items.size()])
	return s


func _first_of(varieties: Dictionary, type: String) -> String:
	var ids: Array = []
	for id in varieties:
		if varieties[id].type == type:
			ids.append(id)
	ids.sort()
	return ids[0]


func _shelve(s: Dictionary, item: Dictionary) -> void:
	var b := PantryRules.board_of(s.pantry)
	var zone := PantryRules.zone_for(item)
	for y in int(b.rows):
		for x in int(b.cols):
			if PantryRules.zone_at(b, Vector2i(x, y)) == zone and PantryRules.place(s.pantry, item, Vector2i(x, y), 0):
				return
	printerr("make_demo_save: no room for %s" % item.key)


## Every Granny to-do step done and the note closed, so no to-do is shown.
func _tutorial_done() -> int:
	var bits := 0
	for step in TodoRules.BITS:
		bits |= 1 << int(TodoRules.BITS[step])
	return TodoRules.close(bits)
