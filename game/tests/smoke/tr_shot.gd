extends SceneTree
## L10N-TR smoke shots: the demo save (in memory, never saved) in Turkish -> user://shots/tr_<view>.png
##   tr_title, tr_title_settings, tr_kitchen, tr_kitchen_panel, tr_book, tr_book_varieties, tr_book_how, tr_town_<tab>,
##   tr_market, tr_mg_<game> (stir_pot, pack_jar, press, knead), tr_night (the morning card)
## godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/tr_shot.gd
## (not headless; wrap it in a timeout). `-- --locale=en` shoots the same views in English for a side-by-side look.

const SHOTS := "user://shots"
const MINIGAMES := {
	"stir_pot": {"seed": 7, "recipe": "jam", "desc": {"appearance": {"fill": ["a22512", "c94d2e", "e19064"]}}},
	"pack_jar": {"seed": 7, "recipe": "pickle", "ingredient_types": ["cucumber"], "desc": {"appearance": {"fill": "7a9a3a"}}},
	"press": {"seed": 7, "recipe": "juice", "desc": {"appearance": {"fill": ["a22512", "c94d2e", "e19064"]}}},
	"knead": {"seed": 7, "recipe": "pie", "desc": {"appearance": {"fill": ["62272c", "a22512", "c94d2e"]}}},
}
var _locale := "tr"
var _gs: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--locale="):
			_locale = a.substr(9)
	GameSettings._file().set_value("game", "language", _locale)  # in memory only: the title applies it, nothing saves
	GameSettings.apply_language(_locale)
	_gs = root.get_node("GameState")
	_run()


## The demo save as a temporary game: nothing this script does is ever saved.
func _fresh() -> void:
	_gs.data = DevTools.load_demo()
	if not _gs.data.has("flags"):
		_gs.data["flags"] = {}
	_gs.data.flags["temp"] = true
	_gs.notify(PackedStringArray(["*"]))


func _run() -> void:
	await process_frame
	# Title and Settings (the language picker)
	_fresh()
	var title := (load("res://scenes/title/title.tscn") as PackedScene).instantiate()
	root.add_child(title)
	await _frames(8)
	_save("title")
	title._on_settings()
	await _frames(4)
	_save("title_settings")
	title.queue_free()
	await _frames(2)

	# Kitchen (a throwaway game with the debug inventory), then the stove panel with a fruit and cinnamon: the
	# preview shows the product name
	_gs.data = {}
	root.get_node("Router").current = "kitchen"
	var k: Control = (load("res://scenes/kitchen/kitchen.tscn") as PackedScene).instantiate()
	root.add_child(k)
	await _frames(12)
	_save("kitchen")
	k._on_spot("stove")
	await _frames(4)
	var panel: Control = k._panel
	var fruit := _first_fitting(panel, "main")
	if fruit != "":
		panel._pick(fruit, panel)
	panel._select_addin("cinnamon")
	await _frames(14)
	_save("kitchen_panel")
	k.queue_free()
	await _frames(2)

	# Recipe book: recipes, varieties, the "How it was made" card of the first variant
	_fresh()
	var b := Book.open()
	await _frames(12)
	_save("book")
	b.show_book(1)
	await _frames(6)
	_save("book_varieties")
	var keys: Array = _gs.data.book.variants.keys()
	if not keys.is_empty():
		b.show_book(0)
		await _frames(4)
		b.open_how(String(keys[0]))
		await _frames(8)
		_save("book_how")
	b.queue_free()
	await _frames(2)

	# Town tabs
	_fresh()
	var town := (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(town)
	await _frames(4)
	for tab in ["grocer", "orders", "neighbours"]:
		town._on_tab(tab)
		await _frames(12)
		_save("town_" + tab)
	town.queue_free()
	await _frames(2)

	# Market day setup (a day-7 game in memory with the market's sample jars)
	var s := State.new_game(1)
	s.day = 7
	s.flags["temp"] = true
	s.inbox = (load("res://scenes/market/market.gd") as GDScript).call("sample_items")
	_gs.set("data", s)
	var market := (load("res://scenes/market/market.tscn") as PackedScene).instantiate()
	root.add_child(market)
	await _frames(12)
	_save("market")
	market.queue_free()
	await _frames(2)

	# The four mini-games a few seconds in (first-impression screen with the hints)
	for id: String in MINIGAMES:
		var mg: Node = (load("res://minigames/%s/%s.tscn" % [id, id]) as PackedScene).instantiate()
		root.add_child(mg)
		mg.start(MINIGAMES[id])
		await create_timer(3.0).timeout
		_save("mg_" + id)
		mg.queue_free()
		await process_frame

	# The morning card after one night
	_fresh()
	root.add_child((load("res://ui/hud/hud.tscn") as PackedScene).instantiate())
	load("res://ui/transition/night.gd").start()
	await create_timer(3.2).timeout
	await _frames(14)
	_save("night")
	quit()


func _first_fitting(panel: Control, which: String, need := 3) -> String:
	var stock: Dictionary = panel.fresh_stock(_gs.data)
	var ids: Array = stock.keys()
	ids.sort()
	for vid in ids:
		if panel._fits(which, vid) and int(stock[vid]) >= need:
			return vid
	return ""


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(view: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var p := "%s/%s_%s.png" % [SHOTS, _locale, view]
	RenderingServer.force_draw(false)  # macOS skips drawing a covered window
	root.get_texture().get_image().save_png(p)
	print("saved ", ProjectSettings.globalize_path(p))
