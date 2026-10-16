extends SceneTree
## Smoke shot: HUD + toast + rain over a palette background -> user://shots/hud.png
## godot --path game -s res://tests/smoke/hud_shot.gd


func _initialize() -> void:
	var gs := root.get_node("GameState")
	gs.start_new(1)
	gs.data.weather = "rainy"
	gs.data.energy = 57
	gs.notify(PackedStringArray(["*"]))
	var bg := ColorRect.new()
	bg.color = Color("747c37")
	bg.size = Vector2(480, 270)
	root.add_child(bg)
	var rain := (load("res://ui/hud/rain.tscn") as PackedScene).instantiate()
	root.add_child(rain)
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	_run(hud)


func _run(hud: Node) -> void:
	await process_frame
	hud._seed_btn.set_pressed_no_signal(true)
	hud._refresh()
	hud.show_toast("UI_TIRED")
	for i in 14:
		await process_frame
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir + "/hud.png")
	print("saved ", ProjectSettings.globalize_path(dir + "/hud.png"))
	quit()
