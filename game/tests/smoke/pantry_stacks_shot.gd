extends SceneTree
## Smoke shot (PANTRY-STACKS): a bag of apples picked over two days (different days_left) is emptied into the inbox
## and the pantry tray shows one stack with the total. In-memory seed-1 game, no save.
##   godot --audio-driver Dummy --path game -s res://tests/smoke/pantry_stacks_shot.gd -- --out=<png path>


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var s := State.new_game(1)
	s.bag = [State.fresh("apple_1", 6, 6), State.fresh("apple_1", 6, 5), State.fresh("pear_1", 3, 4)]
	Forage.empty_bag_to_inbox(s)
	var apples := 0
	for it in s.inbox:
		if it.variety == "apple_1":
			apples += 1
	print("apple stacks in inbox: ", apples, " inbox size ", s.inbox.size())
	gs.set("data", s)
	var scene: Control = (load("res://scenes/pantry/pantry.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 4:
		await process_frame
	RenderingServer.force_draw(false)
	var out := "/tmp/pantry_stacks.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	root.get_texture().get_image().save_png(out)
	quit(0 if apples == 1 else 1)
