extends SceneTree
## Smoke shot (P1-LETTERS): town with a letter from Mia, jars in the inbox -> user://shots/letters.png (reader),
## letters_parcel.png (box packed with care, straw in the gaps), letters_reply.png (thank-you note with the child's
## drawing of the jars), letters_many.png (long inbox that scrolls, a request from Leo with his wish drawing).
## godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/letters_shot.gd


func _initialize() -> void:
	var gs := root.get_node("GameState")
	gs.start_temp(42)
	var s: Dictionary = gs.data
	s.day = 4
	Letters.ensure(s)
	var letter := Letters.make_request(s, "mia", Seeds.rng(42, "letters", 4))
	s.letters.inbox.append(letter)
	# One ready jar per request item, a surprise jam, a waiting pickle and a mushroom jar Mia would not want.
	for req in letter.request:
		s.inbox.append(_jar(s, "mia", req))
	s.inbox.append(_jar(s, "mia", {"recipe": "jam", "taste": "sweet"}))
	s.inbox.append(_jar(s, "mia", {"recipe": "fruit_butter", "taste": ""}))
	for c in Orders.candidates(s, Orders.product_taste()):
		if c.recipe == "brined_mushroom":
			s.inbox.append(State.product(c.key, 2, 0))
			break
	var scene := (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_run()


func _jar(s: Dictionary, kid: String, req: Dictionary) -> Dictionary:
	for c in Letters.kid_candidates(s, kid):
		if Letters.meets(req, String(c.recipe), c.taste):
			return State.product(String(c.key), 3, 0)
	return {}


func _run() -> void:
	await _frames(4)
	var ui := LettersUI.open()
	await _frames(10)
	_save("letters")
	ui.open_pack()
	await _frames(4)
	# Pack like a player would: the requested jars, then the surprise (inbox order), then straw.
	var letter: Dictionary = Letters.find_letter(root.get_node("GameState").data, ui._letter_id)
	var n: int = letter.request.size() + 1
	# The first jar goes in through the board's hold API (what a drag from the jar column does).
	var before: int = ui._source.size()
	ui._board.begin_hold(ui._source[0], {"where": "inbox", "index": 0}, ui._board.get_global_transform_with_canvas() * Vector2(12, 12))
	ui._board.move_hold_to(Vector2(12, 12))
	ui._board.drop_held()
	print("drag: box %d, jars %d -> %d" % [ui._entries.size(), before, ui._source.size()])
	for i in range(1, n):
		var item: Dictionary = ui._source[0]
		ui._source.remove_at(0)
		ui._entries.append({"item": item, "x": i % Letters.BOX_COLS, "y": floori(i / float(Letters.BOX_COLS)), "rot": 0})
	ui._source_view.refresh()
	ui._on_straw()
	await _frames(12)
	_save("letters_parcel")
	ui._on_send()
	var gs := root.get_node("GameState")
	DayEnd.run(gs.data)
	DayEnd.run(gs.data)
	for l in gs.data.letters.inbox:
		if l.kind == "reply":
			ui.show_letter(int(l.id))
	await _frames(6)
	_save("letters_reply")
	print("letters: ", gs.data.letters.love, " unlocked ", gs.data.letters.unlocked_recipes)
	# A long inbox: the list scrolls on its paper sheet; the newest is a request from Leo (his wish drawing).
	var s: Dictionary = gs.data
	for i in 5:
		s.letters.inbox.append(Letters.make_request(s, "mia" if i % 2 == 1 else "leo", Seeds.rng(42, "letters", 10 + i)))
	ui.show_letter(-1)
	await _frames(6)
	_save("letters_many")
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
