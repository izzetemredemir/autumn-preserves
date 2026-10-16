extends "res://tests/_runner/test_case.gd"
## MARKET: procedural villagers (PCG showcase). Same look seed -> same pixels; palette-only, hard alpha, feet on the
## ground row, and the crowd of a market day really varies.

const Villager := preload("res://scenes/market/villager.gd")


## The 31 colours of tools/palettes/autumn.hex (JarIcon keeps the same list).
func _palette() -> Dictionary:
	var out := {}
	for hex in JarIcon.PALETTE:
		out[String(hex)] = true
	return out


func test_same_seed_same_villager() -> void:
	for look in [1, 77, 123456, 2147483647]:
		var a: Array = Villager.make_images(look, false)
		var b: Array = Villager.make_images(look, false)
		assert_eq(a.size(), 4)
		for f in 4:
			assert_eq((a[f] as Image).get_data(), (b[f] as Image).get_data(), "seed %d frame %d" % [look, f])


func test_palette_hard_alpha_and_feet() -> void:
	var pal := _palette()
	assert_eq(pal.size(), 31)
	for i in 24:
		var look := Hash.fnv1a31("villager %d" % i)
		for img: Image in Villager.make_images(look, i % 5 == 0):
			assert_eq(img.get_size(), Vector2i(Villager.W, Villager.H))
			var feet := false
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					assert_true(c.a == 0.0 or c.a == 1.0, "hard alpha")
					if c.a == 1.0:
						assert_true(pal.has(c.to_html(false)), "palette colour %s" % c.to_html(false))
						if y == Villager.H - 1:
							feet = true
			assert_true(feet, "outline under the shoes on the last row")


func test_crowd_varies() -> void:
	var seen := {}
	for c in Market.customers(7, 7, 3, 1.5):
		seen[Marshalls.raw_to_base64((Villager.make_images(int(c.look), bool(c.fancy))[0] as Image).get_data())] = true
	assert_true(seen.size() >= 10, "%d different villagers" % seen.size())
