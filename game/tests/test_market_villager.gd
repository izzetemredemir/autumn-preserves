extends "res://tests/_runner/test_case.gd"
## MARKET / MARKET-LIVE: procedural villagers v2 (PCG showcase). Same look seed -> same pixels; palette-only, hard
## alpha, feet on the pivot row in every view and pose; vendors match their portraits; a market crowd really varies.

const Villager := preload("res://scenes/market/villager.gd")
const POSES := [["walk", 0], ["walk", 1], ["walk", 2], ["walk", 3], ["idle", 0], ["idle", 1], ["look", 0], ["look", 1],
	["talk", 0], ["talk", 1], ["wave", 0], ["wipe", 1]]


## The 31 colours of tools/palettes/autumn.hex (JarIcon keeps the same list).
func _palette() -> Dictionary:
	var out := {}
	for hex in JarIcon.PALETTE:
		out[String(hex)] = true
	return out


func test_same_seed_same_villager() -> void:
	for look in [1, 77, 123456, 2147483647]:
		var a := Villager.look_for(look, false, true)
		var b := Villager.look_for(look, false, true)
		assert_eq(a, b, "look %d" % look)
		for f in 4:
			var ia := Villager.compose(a, "front", "walk", f)
			var ib := Villager.compose(b, "front", "walk", f)
			assert_eq(ia.get_data(), ib.get_data(), "seed %d frame %d" % [look, f])


func test_palette_hard_alpha_and_feet() -> void:
	var pal := _palette()
	assert_eq(pal.size(), 31)
	for i in 16:
		var l := Villager.look_for(Hash.fnv1a31("villager %d" % i), i % 5 == 0, i % 3 == 0)
		for view in ["front", "side", "back"]:
			for p in POSES:
				var img := Villager.compose(l, view, String(p[0]), int(p[1]))
				assert_eq(img.get_size(), Vector2i(Villager.W, Villager.H))
				var feet := false
				var any := false
				for y in img.get_height():
					for x in img.get_width():
						var c := img.get_pixel(x, y)
						assert_true(c.a == 0.0 or c.a == 1.0, "hard alpha")
						if c.a == 1.0:
							any = true
							assert_true(pal.has(c.to_html(false)), "palette colour %s" % c.to_html(false))
							if y == Villager.PIVOT.y:
								feet = true
				assert_true(any, "%s %s drawn" % [view, p[0]])
				assert_true(feet, "outline under the shoes on the pivot row (%s %s %d)" % [view, p[0], i])


func test_archetypes_and_parts_vary() -> void:
	var arches := {}
	var hairs := {}
	var hats := {}
	for i in 200:
		var l := Villager.look_for(Hash.fnv1a31("mix %d" % i))
		arches[l.arch] = true
		hairs[l.hair] = true
		hats[l.hat] = true
	for a in ["man", "woman", "elder", "child"]:
		assert_true(arches.has(a), "archetype %s" % a)
	assert_true(hairs.size() >= 6, "%d hair styles" % hairs.size())
	assert_true(hats.size() >= 5, "%d hats" % hats.size())


func test_children_are_small_elders_shorter() -> void:
	var child := {}
	var elder := {}
	var adult := {}
	for i in 300:
		var l := Villager.look_for(Hash.fnv1a31("h %d" % i))
		l.hat = "none"
		l.umbrella = false
		var top := _top(Villager.compose(l, "front", "idle", 0))
		match String(l.arch):
			"child": child[top] = true
			"elder": elder[top] = true
			_: adult[top] = true
	for t: int in child:
		assert_true(Villager.PIVOT.y - t <= 34, "children about 32 px tall (%d)" % (Villager.PIVOT.y - t))
	for t: int in elder:
		assert_true(Villager.PIVOT.y - t <= 44, "elders about 42 px tall (%d)" % (Villager.PIVOT.y - t))
	for t: int in adult:
		assert_true(Villager.PIVOT.y - t <= 48, "adults about 46 px tall (%d)" % (Villager.PIVOT.y - t))


func test_vendors_match_their_portraits() -> void:
	assert_eq(String(Villager.vendor_look("grocer").hat), "cap")
	assert_eq(String(Villager.vendor_look("grocer").outfit), "apron")
	assert_eq(String(Villager.vendor_look("baker").colors.hair[1]), "c94d2e")
	assert_eq(String(Villager.vendor_look("postman").hat), "postcap")
	assert_eq(String(Villager.vendor_look("postman").outfit), "satchel")
	assert_true(bool(Villager.vendor_look("vintner").moustache))
	assert_eq(String(Villager.vendor_look("vintner").colors.coat[1]), "62272c")
	assert_true(bool(Villager.vendor_look("librarian").glasses))
	assert_eq(String(Villager.vendor_look("librarian").outfit), "shawl")


func test_crowd_varies() -> void:
	var seen := {}
	for c in Market.customers(7, 7, 3, 1.5):
		var img := Villager.compose(Villager.look_for(int(c.look), bool(c.fancy)), "front", "idle", 0)
		seen[Marshalls.raw_to_base64(img.get_data())] = true
	assert_true(seen.size() >= 10, "%d different villagers" % seen.size())


func _top(img: Image) -> int:
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				return y
	return img.get_height()
