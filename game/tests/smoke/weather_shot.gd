extends SceneTree
## Smoke shot (CALENDAR-WEATHER): windy and foggy forests and the morning card of a market day -> user://shots/
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/weather_shot.gd
## weather_windy.png: day 9 (Grape Harvest), windy: leaves blowing, a fallen fruit under every fruit tree, the week's
## name in the HUD. weather_foggy.png: day 16 (Apple Moon), foggy: the dithered fog closing in around Granny.
## weather_morning.png: the morning card of day 14 (week line, "Market today!", weather, energy).
## Throwaway games only (GameState.start_temp): nothing is saved. Exit code 1 on a failed check.

const SEED := 20261017
const DIR := "user://shots"
const FOG := Color("f2d9c5")

var _gs: Node
var _router: Node
var _failed := false


func _initialize() -> void:
	_gs = root.get_node("GameState")
	_router = root.get_node("Router")
	_run()


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(DIR)
	await _windy()
	await _foggy()
	await _morning()
	print("weather_shot: ", "FAILED" if _failed else "ok")
	quit(1 if _failed else 0)


func _start(day: int, weather: String) -> void:
	_gs.start_temp(SEED)
	_gs.data.day = day
	_gs.data.weather = weather
	_gs.notify(PackedStringArray(["*"]))
	_router.params = {"biome": "forest"}


func _windy() -> void:
	_start(9, "windy")
	_gs.data.coins = 99999  # widest HUD row: the longest week name with five-digit coins
	_gs.data.energy_max = 95
	_gs.data.energy = 95
	var scene := _open()
	await _frames(30)
	var m: Dictionary = scene.map
	var fallen: Array = []
	for o in scene.view.objects.get_children():
		if o is WildObject and o.kind == "ground" and bool(o.info.get("windfall", false)):
			fallen.append(o)
	_check(fallen.size() >= (m.fruit_trees as Array).size() - 1 and fallen.size() > 0,
		"windy: %d fallen fruit for %d trees" % [fallen.size(), (m.fruit_trees as Array).size()])
	var fx: WildWeather = _weather_layer(scene)
	_check(fx != null and fx.leaf_count() > 0 and not fx.is_foggy(), "windy: leaves blow")
	var hud: Node = scene.get_node("Hud")
	var week: Label = hud.get("_week_label")
	_check(week.visible and week.text == "Grape Harvest", "HUD names the week: '%s'" % week.text)
	var panel := week.get_parent().get_parent() as Control
	_check(panel.get_global_rect().end.x <= 478.0, "HUD fits the screen (%d px)" % int(panel.get_global_rect().end.x))
	var with_wind := _shot("weather_windy")
	if with_wind != null and fx != null:
		fx.visible = false
		var calm := _shot("weather_windy_calm")
		fx.visible = true
		var moved := 0
		for y in with_wind.get_height():
			for x in with_wind.get_width():
				moved += 1 if with_wind.get_pixel(x, y) != calm.get_pixel(x, y) else 0
		_check(moved > 80, "leaves and gusts drawn over the forest (%d px)" % moved)
	if not fallen.is_empty():
		var bag0: int = Forage.bag_count(_gs.data)
		scene._use(fallen[0])
		await _frames(3)
		_check(Forage.bag_count(_gs.data) == bag0 + 1, "a fallen fruit goes into the bag")
	scene.queue_free()
	await _frames(2)


func _foggy() -> void:
	_start(16, "foggy")
	var scene := _open()
	await _frames(20)
	var fx: WildWeather = _weather_layer(scene)
	_check(fx != null and fx.is_foggy() and fx.leaf_count() == 0, "foggy: fog layer")
	var hud: Node = scene.get_node("Hud")
	_check(String((hud.get("_week_label") as Label).text) == "Apple Moon", "HUD: Apple Moon")
	var img := _shot("weather_foggy")
	if img != null:
		var g: Vector2 = scene.granny.get_global_transform_with_canvas().origin + Vector2(0, -12)
		var near := _fog_share(img, Rect2i(Vector2i(g) - Vector2i(20, 20), Vector2i(40, 40)))
		var corner := _fog_share(img, Rect2i(2, 200, 40, 40) if g.x > 240 else Rect2i(430, 200, 40, 40))
		_check(near < 0.02, "fog leaves Granny clear (%.2f fog pixels)" % near)
		_check(corner > 0.5, "fog hides the far corner (%.2f fog pixels, exact palette colour)" % corner)
	scene.queue_free()
	await _frames(2)


func _morning() -> void:
	_gs.start_temp(SEED)
	_gs.data.day = 13
	_gs.notify(PackedStringArray(["*"]))
	var bg := ColorRect.new()
	bg.color = Color("747c37")
	bg.size = Vector2(480, 270)
	root.add_child(bg)
	# loaded at run time: Night uses autoloads, which a SceneTree script cannot name at compile time
	var night: Node = load("res://ui/transition/night.gd").start()
	_check(night != null, "the night starts")
	if night == null:
		return
	var t0 := Time.get_ticks_msec()
	while not night.get("_accepting") and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	await _frames(10)
	var texts: Array = []
	for l in (night.get("_lines") as Node).get_children():
		if l is Label:
			texts.append(l.text)
	_check(int(_gs.data.day) == 14, "slept into day 14")
	_check(texts.any(func(s: String) -> bool: return s.begins_with("This week: Grape Harvest")), "week line: %s" % str(texts))
	_check(texts.has("Market today!"), "market line")
	var card := (night.get("_card") as Control).get_global_rect()
	_check(card.position.y >= 0.0 and card.end.y <= 270.0, "the card fits the screen (%d..%d)" % [card.position.y, card.end.y])
	_shot("weather_morning")
	night._button.pressed.emit()
	t0 = Time.get_ticks_msec()
	while is_instance_valid(night) and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	bg.queue_free()
	await _frames(2)


func _open() -> Node:
	var scene := (load("res://scenes/wild/wild.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	return scene


func _weather_layer(scene: Node) -> WildWeather:
	for c in scene.get_children():
		if c is WildWeather:
			return c
	return null


func _fog_share(img: Image, r: Rect2i) -> float:
	var n := 0
	var fog := 0
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			n += 1
			fog += 1 if img.get_pixel(x, y).to_html(false) == FOG.to_html(false) else 0
	return float(fog) / maxi(n, 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> Image:
	RenderingServer.force_draw(false)  # macOS skips drawing a covered window; the shot must show this frame
	var img := root.get_texture().get_image()
	if img == null:
		print("no image for ", shot_name, " (headless: run windowed for the shots)")
		return null
	var path := "%s/%s.png" % [DIR, shot_name]
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
	return img


func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		_failed = true
		printerr("FAIL ", what)
