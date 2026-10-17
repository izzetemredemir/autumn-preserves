extends SceneTree
## Smoke shot: town square, one shot per tab -> user://shots/town_<tab>.png
## LIVING-TOWN: the living square on a sunny, a rainy and a market day -> user://shots/town_square_<sunny|sunny2|rainy|market>.png,
## plus checks (printed as "town_square:"): people out, bubbles clear of the panels, a click on Barnaby opens his page.
## godot --path game --audio-driver Dummy -s res://tests/smoke/town_shot.gd


func _initialize() -> void:
	GameSettings.apply_language("tr" if "--locale=tr" in OS.get_cmdline_user_args() else "en")  # UI-COMPACT: shots per language
	var scene := (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node) -> void:
	for i in 3:
		await process_frame
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	for tab in ["grocer", "orders", "neighbours"]:
		scene._on_tab(tab)
		for i in 12:
			await process_frame
		RenderingServer.force_draw(false)  # macOS skips drawing a covered window
		root.get_texture().get_image().save_png("%s/town_%s.png" % [dir, tab])
		print("saved town_", tab)
	var gs: Node = root.get_node("GameState")
	gs.data.friendship.librarian = 4
	for id in ["vintner", "librarian"]:
		scene._select_npc(id)
		scene._on_tab("neighbours")
		for i in 12:
			await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("%s/town_npc_%s.png" % [dir, id])
	await _square_shots(scene, gs, dir)
	quit()


func _square_shots(old: Node, gs: Node, dir: String) -> void:
	var problems := 0
	for w in ["sunny", "rainy", "market"]:
		old.queue_free()
		await process_frame
		gs.data.weather = "rainy" if w == "rainy" else "sunny"
		gs.data.day = 7 if w == "market" else 3
		if gs.data.has("market"):
			gs.data.market.last_day = 0
		var scene := (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
		root.add_child(scene)
		old = scene
		var square: Node = scene.get_node("Square")
		var shots := ["sunny", "sunny2"] if w == "sunny" else [w]
		for shot in shots:
			for i in 200:
				await process_frame
				for b in square.bubbles():
					var r: Rect2 = b.rect
					if r.position.y < 60.0 or r.end.y > 144.0:
						problems += 1
						print("town_square: PROBLEM bubble over a panel ", b.key, " ", r)
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("%s/town_square_%s.png" % [dir, shot])
			print("town_square: %s out=%d bubbles=%d" % [shot, square.out_count(), square.bubbles().size()])
		if w == "market":
			if square.crowd.is_empty() and scene.get_node_or_null("MarketToday") != null:
				print("town_square: market day keeps the banner, the square is quiet")
			else:
				problems += 1
				print("town_square: PROBLEM market day")
		elif w == "sunny":
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			var barnaby: Node2D = square._stands.grocer
			click.position = barnaby.position - Vector2(0, 20)
			scene._on_tab("orders")
			square._gui_input(click)
			if scene._tab == "neighbours" and scene._npc == "grocer":
				print("town_square: a click on Barnaby opens his page")
			else:
				problems += 1
				print("town_square: PROBLEM click on Barnaby -> tab %s npc %s" % [scene._tab, scene._npc])
	print("town_square: %d problems" % problems)
