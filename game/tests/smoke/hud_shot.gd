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
	var demo := PanelContainer.new()
	demo.position = Vector2(300, 90)
	var col := VBoxContainer.new()
	demo.add_child(col)
	var b1 := Button.new()
	b1.text = "UI_SEED"
	var b2 := Button.new()
	b2.text = "UI_SEED"
	b2.disabled = true
	col.add_child(b1)
	col.add_child(b2)
	demo.theme = load("res://ui/theme/theme.tres")
	root.add_child(demo)
	_run(hud)


func _run(hud: Node) -> void:
	await process_frame
	hud._refresh()
	hud.show_toast("UI_TIRED")
	for i in 14:
		await process_frame
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(dir + "/hud.png")
	print("saved ", ProjectSettings.globalize_path(dir + "/hud.png"))
	quit()
