extends SceneTree
## PLAIN-WORDS smoke shots -> user://shots/plain_words_*.png (+ checks; prints PLAINWORDS OK / FAIL).
##   godot --path game --audio-driver Dummy -s res://tests/smoke/plain_words_shot.gd [-- --locale=tr]
## grow_first: the overlay on a save's first forest entry (Teo's line, Granny's line per phase); grow_short: the 2 s
## form of later entries; how_made: the recipe book card; festival_end; lab: the Forest Lab
## (still shows its step names). Seeds and fnv lines appear only with Show seed.

const WILD := "res://scenes/wild/wild.tscn"
const LAB := "res://scenes/seed_lab/seed_lab.tscn"
const DIR := "user://shots"
const HOW_KEY := "jam|crabapple_4|cinnamon"

var _fails: Array[String] = []
var _suffix := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--locale="):
			_suffix = "_" + a.substr(9)
	GameSettings.apply_language()
	_run()


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(DIR)
	await _grow()
	await _how()
	await _festival()
	await _lab()
	print("PLAINWORDS OK" if _fails.is_empty() else "PLAINWORDS FAIL: %s" % ", ".join(_fails))
	quit(1 if not _fails.is_empty() else 0)


func _grow() -> void:
	var gs := root.get_node("GameState")
	var router := root.get_node("Router")
	gs.start_temp(452)
	_check(WorldGrow.is_first(gs.data), "a new save has not seen the narrated entry")
	router.params = {"biome": "forest", "grow": true}
	var wild := (load(WILD) as PackedScene).instantiate()
	root.add_child(wild)
	await _frames(3)
	var grow := _find_grow(wild)
	_check(grow != null, "the overlay opens")
	_check(not WorldGrow.is_first(gs.data), "grow_seen is set after the first entry")
	if grow != null:
		grow.set_process(false)
		grow.seek(1.7)
		await _frames(2)
		_shot("grow_first")
		grow.set_process(true)
		grow.seek(WorldGrow.duration() - 0.01)
		await _frames(4)
	wild.queue_free()
	await _frames(2)
	# later entry: the short form
	router.params = {"biome": "forest", "grow": true}
	wild = (load(WILD) as PackedScene).instantiate()
	root.add_child(wild)
	await _frames(3)
	grow = _find_grow(wild)
	_check(grow != null, "the short form opens")
	if grow != null:
		grow.set_process(false)
		grow.seek(0.8)
		await _frames(2)
		_shot("grow_short")
		grow.set_process(true)
		grow.seek(WorldGrow.duration(true) - 0.01)
		await _frames(4)
		_check(not is_instance_valid(grow), "the short overlay ends")
	router.params = {}
	wild.queue_free()
	await _frames(2)


func _find_grow(wild: Node) -> Node:
	for c in wild.get_children():
		if c is WorldGrow:
			return c
	return null


func _how() -> void:
	var gs := root.get_node("GameState")
	gs.start_new(7)
	gs.data.found_varieties = ["crabapple_4"]
	gs.data.book.variants[HOW_KEY] = {"best_q": 3, "best_stars": 5, "count": 2, "first_day": 1}
	var book := Book.open()
	await _frames(4)
	book.open_how(HOW_KEY)
	await _frames(6)
	_shot("how_made")
	book.close_book()
	await _frames(2)


func _festival() -> void:
	var d := FestivalFacts.load_save()
	if d.is_empty():
		_check(false, "festival save loads")
		return
	root.get_node("GameState").data = d
	var facts := FestivalFacts.summary(d)
	_check(int(facts.clearings) > 0 and int(facts.paths) > 0, "festival facts count clearings and paths")
	var c := FestivalCard.new()
	root.add_child(c)
	c.show_end(facts)
	await create_timer(0.6).timeout
	_shot("festival_end")
	c.queue_free()
	await _frames(2)


func _lab() -> void:
	root.get_node("Router").params = {"seed": 20261016}
	var lab := (load(LAB) as PackedScene).instantiate()
	root.add_child(lab)
	await _frames(10)
	lab.seek_grow(GrowView.start(2) + 1.0)
	await _frames(3)
	_shot("lab")
	lab.queue_free()
	await _frames(2)


func _shot(name: String) -> void:
	RenderingServer.force_draw(false)
	var file := "%s/plain_words_%s%s.png" % [DIR, name, _suffix]
	root.get_texture().get_image().save_png(file)
	print("saved ", ProjectSettings.globalize_path(file))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
