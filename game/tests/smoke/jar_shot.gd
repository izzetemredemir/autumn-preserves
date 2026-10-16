extends SceneTree
## Smoke shot (UI-JAR): >=12 sample jars + one result card -> user://shots/jars.png.
## Sample desc dicts are hand-written here (ProductGen.describe() format, see game/sim/product_gen.gd).

const PAL := ["111010", "a22512", "c94d2e", "e19064", "49423d", "81746a", "b9a697", "f2d9c5", "50361e", "b66813", "c58845", "83571e", "e5bd7f", "9b8039", "dbcc83", "b1a13d", "c5bf3f", "b4b3a0", "b7b768", "747c37", "53612e", "314524", "738c7a", "4e7664", "275e4c", "2e3f3f", "415c5d", "567c7d", "23282a", "3d1f29", "62272c"]


func _d(nm: String, vessel: String, fill: Array, chunk: String, sd: int, shape: int, lab: String, motif: String, lid: String, lid_cols: Array, taste: Array, harmony := 1) -> Dictionary:
	return {
		"name": nm, "vessel": vessel, "taste": taste, "harmony": harmony, "profile_label": "Sweet & Sour", "value": 233,
		"appearance": {"vessel": vessel, "fill": fill, "chunk": chunk, "chunk_seed": sd, "label_shape": shape, "label_color": lab, "motif": motif, "lid": lid, "lid_colors": lid_cols},
	}


func _samples() -> Array:
	var crab := ["e19064", "c94d2e", "a22512"]
	var plum := ["c94d2e", "62272c", "3d1f29"]
	var quince := ["dbcc83", "e5bd7f", "b66813"]
	var pear := ["b7b768", "b1a13d", "747c37"]
	var cuke := ["b7b768", "747c37", "275e4c"]
	var mush := ["c58845", "83571e", "50361e"]
	var green := ["c5bf3f", "747c37", "53612e"]
	var metal := ["", ""]
	return [
		_d("Cinnamon Ember Crabapple Jam", "jam_jar", crab, "seeds", 1, 0, "f2d9c5", "leaf", "metal", metal, [6, 4, 3, 0, 0], 2),
		_d("Honeyed Blackberry Jam", "jam_jar", plum, "seeds", 2, 1, "dbcc83", "star", "cloth", ["f2d9c5", "a22512"], [7, 2, 0, 0, 0], 0),
		_d("Golden Quince Butter", "jam_jar", quince, "none", 3, 2, "f2d9c5", "stripe", "cloth", ["c5bf3f", "275e4c"], [5, 0, 0, 0, 1], 1),
		_d("Tart Pear Chutney", "jam_jar", pear, "pieces", 4, 0, "e19064", "star", "metal", metal, [3, 5, 2, 0, 0], 1),
		_d("Warm Plum Chutney", "jam_jar", ["c94d2e", "83571e", "50361e"], "pieces", 5, 1, "b9a697", "leaf", "cloth", ["e19064", "62272c"], [3, 3, 5, 0, 1], 2),
		_d("Briny Cucumber Pickles", "pickle_jar", cuke, "rings", 6, 0, "f2d9c5", "leaf", "metal", metal, [0, 4, 0, 5, 0], 2),
		_d("Smoky Dusk Porcini Brine", "pickle_jar", mush, "mushroom", 7, 2, "b9a697", "stripe", "metal", metal, [0, 3, 0, 5, 3], 1),
		_d("Minted Beet Pickles", "pickle_jar", ["c94d2e", "62272c", "3d1f29"], "rings", 8, 1, "dbcc83", "star", "cloth", ["f2d9c5", "275e4c"], [1, 4, 0, 4, 2], 0),
		_d("Golden Apple Pie", "pie", ["e5bd7f", "c58845", "83571e"], "", 9, 0, "f2d9c5", "leaf", "metal", metal, [4, 2, 1, 0, 1], 1),
		_d("Smoky Chestnut Bread", "bread", ["c58845", "83571e", "50361e"], "seed", 10, 0, "f2d9c5", "leaf", "metal", metal, [0, 0, 0, 1, 5], 1),
		_d("Golden Apple Juice", "bottle", ["dbcc83", "e5bd7f", "b66813"], "none", 11, 0, "f2d9c5", "leaf", "metal", metal, [3, 2, 0, 0, 0], 0),
		_d("Honeyed Plum Syrup", "bottle", ["c94d2e", "a22512", "3d1f29"], "none", 12, 1, "dbcc83", "star", "metal", metal, [9, 1, 0, 0, 0], 0),
		_d("Tart Pear Vinegar", "bottle", green, "none", 13, 2, "f2d9c5", "stripe", "metal", metal, [0, 6, 0, 0, 0], 1),
		_d("Walnut Quince Jam", "jam_jar", quince, "seeds", 14, 1, "b9a697", "leaf", "cloth", ["b9a697", "83571e"], [5, 1, 0, 0, 3], 1),
		_d("Warm Ginger Pear Jam", "jam_jar", pear, "pieces", 15, 2, "e19064", "stripe", "metal", metal, [5, 1, 4, 0, 0], 1),
	]


func _initialize() -> void:
	var s := _samples()
	var root_ui := Control.new()
	root_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(root_ui)
	var bg := ColorRect.new()
	bg.color = Color("50361e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ui.add_child(bg)

	# shelf-view grid at x2: 5 columns, 3 rows (bottles in the last row)
	var layout := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 14, 10, 11, 12]
	for i in layout.size():
		var c := i % 5
		var r := i / 5
		var jar := JarIcon.new()
		jar.zoom = 2
		jar.position = Vector2(8 + c * 52, 6 + r * 56 + (0 if r < 2 else 2))
		root_ui.add_child(jar)
		jar.show_product(s[layout[i]])
	# icon view (16x16): first four at x1, next four at x2
	var icon_ids := [0, 5, 8, 10, 1, 6, 9, 11]
	for i in 8:
		var ic := JarIcon.new()
		ic.view = "icon"
		ic.zoom = 1 if i < 4 else 2
		ic.position = Vector2(8 + i * 34, 238) if i < 4 else Vector2(150 + (i - 4) * 36, 232)
		root_ui.add_child(ic)
		ic.show_product(s[icon_ids[i]])

	# result card (new-recipe variant) in the right strip
	var holder := Control.new()
	holder.position = Vector2(266, 0)
	holder.size = Vector2(214, 270)
	root_ui.add_child(holder)
	var card: ResultCard = load("res://ui/result_card/result_card.tscn").instantiate()
	holder.add_child(card)
	await process_frame
	card.show_result(s[0], 3, true)

	for i in 90:
		await process_frame
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/jars.png")

	# palette audit of the whole shot and every sample render
	var pal := {}
	for h in PAL:
		pal[Color.html("#" + h).to_html(false)] = true
	var off := 0
	for y in img.get_height():
		for x in img.get_width():
			if not pal.has(img.get_pixel(x, y).to_html(false)):
				off += 1
	var bad := 0
	for d in s:
		for v in ["shelf", "icon"]:
			var im := JarIcon.render(d, v)
			for y in im.get_height():
				for x in im.get_width():
					var px := im.get_pixel(x, y)
					if px.a > 0.0 and (px.a < 1.0 or not pal.has(px.to_html(false))):
						bad += 1
	print("jar_shot: %d samples, off-palette px in renders: %d, in screenshot: %d -> %s" % [s.size(), bad, off, ProjectSettings.globalize_path("user://shots/jars.png")])
	quit(1 if bad > 0 else 0)
