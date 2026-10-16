extends SceneTree
## Smoke shot (GD-BOOK): new game, 7 variants inserted, book open -> user://shots/book.png (+ book_varieties, book_empty)
## godot --path game --rendering-driver opengl3 -s res://tests/smoke/book_shot.gd


func _initialize() -> void:
	var gs := root.get_node("GameState")
	gs.start_new(7)
	gs.data.found_varieties = ["crabapple_4", "apple_1", "pear_2", "porcini_3", "cucumber_1", "quince_2", "pepper_4"]
	var combos := [
		["jam", ["crabapple_4"], "cinnamon", 3, 5, 4],
		["jam", ["apple_1"], "honey", 2, 3, 2],
		["pickle", ["cucumber_1"], "", 3, 4, 1],
		["brined_mushroom", ["porcini_3"], "thyme", 2, 3, 1],
		["chutney", ["pear_2", "pepper_4"], "ginger", 3, 5, 2],
		["fruit_butter", ["quince_2"], "", 1, 2, 1],
		["jam", ["pear_2"], "", 2, 3, 3],
	]
	var day := 1
	for c in combos:
		var key := ProductGen.make_key(c[0], c[1], c[2])
		gs.data.book.variants[key] = {"best_q": c[3], "best_stars": c[4], "count": c[5], "first_day": day}
		day += 1
	_run()


func _run() -> void:
	await process_frame
	var b := Book.open()
	await _frames(12)
	_save("book")
	b.show_book(1)
	await _frames(6)
	_save("book_varieties")
	b.close_book()
	await _frames(2)
	root.get_node("GameState").data.book.variants.clear()
	Book.open()
	await _frames(6)
	_save("book_empty")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	var p := "user://shots/%s.png" % nm
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(p)
	print("saved ", ProjectSettings.globalize_path(p))
