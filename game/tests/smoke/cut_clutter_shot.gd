extends SceneTree
## Smoke shot (CUT-CLUTTER): the three removals on a throwaway game (GameState.start_temp), with checks.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/cut_clutter_shot.gd [-- --locale=tr]
## 1. The plant menu of an empty bed with fertilizer in the garden: seed buttons and Cancel, no fertilizer toggle;
##    the compost bin's one plain line (no counts). Planting uses the fertilizer by itself.
## 2. The town's tabs and the grocer's head row: Supplies / Seeds / Upgrades, no Sell anywhere.
## 3. Pip's heart gift: his page opens with his Teo line and "+3 [jar]", the toast names the gift, 3 jars more.
## Shots in tools/style/review/cut_clutter/ (bed_menu, compost, town_tabs, gift_moment; "_tr" with --locale=tr).
## Exit code 1 on a failed check.

const SEED := 3
const OUT := "../tools/style/review/cut_clutter"

var _gs: Node
var _router: Node
var _suffix := ""
var _fails := 0


func _initialize() -> void:
	var tr_on := "--locale=tr" in OS.get_cmdline_user_args()
	GameSettings.apply_language("tr" if tr_on else "en")
	_suffix = "_tr" if tr_on else ""
	_gs = root.get_node("GameState")
	_router = root.get_node("Router")
	_run()


func _run() -> void:
	await process_frame
	await _garden()
	await _town()
	print("cut_clutter: %s" % ("OK" if _fails == 0 else "%d PROBLEMS" % _fails))
	quit(1 if _fails > 0 else 0)


func _garden() -> void:
	_router.params = {}
	_router.current = "garden"
	_gs.start_temp(SEED)
	var d: Dictionary = _gs.data
	d.cupboard["seed_cucumber"] = 2
	d.cupboard["seed_pepper"] = 1
	d.garden.fertilizer = 2
	var g := (load("res://scenes/garden/garden.tscn") as PackedScene).instantiate()
	root.add_child(g)
	current_scene = g
	await _wait(20)
	var bed: Node = null
	for i in d.garden.beds.size():
		if String(d.garden.beds[i].crop) == "":
			bed = g.find_spot("bed", i)
			break
	_check(bed != null, "an empty bed")
	if bed == null:
		return
	g._open_menu(bed)
	await _wait(12)
	var menu: Node = g.get("menu")
	_check(menu != null, "the plant menu opens")
	if menu != null:
		var texts: Array[String] = []
		for b in menu.find_children("*", "Button", true, false):
			texts.append((b as Button).text)
		for key in ["GARDEN_FERT_ON", "GARDEN_FERT_OFF"]:
			var stem := tr(key).split("(")[0].strip_edges()
			for t in texts:
				_check(not t.begins_with(stem), "no fertilizer toggle in the plant menu (%s)" % t)
		print("cut_clutter: plant menu buttons ", texts)
		_shot("bed_menu")
		menu.choose("pepper")
		await _wait(6)
		var planted: Dictionary = d.garden.beds[int(bed.index)]
		_check(String(planted.crop) == "pepper" and bool(planted.fertilized), "the bed took fertilizer by itself")
		_check(int(d.garden.fertilizer) == 1, "one sack used (%d left)" % int(d.garden.fertilizer))
	await _wait(30)
	var compost: Node = g.find_spot("compost")
	g._use(compost)
	await _wait(10)
	var line := tr("GARDEN_COMPOST_BIN")
	_check(not "%d" in line and not "/" in line, "the compost says one plain line")
	_shot("compost")
	g.queue_free()
	await _wait(4)


func _town() -> void:
	_router.current = "town"
	_gs.start_temp(SEED)
	var d: Dictionary = _gs.data
	d.day = 3
	d.coins = 120
	var t := (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(t)
	current_scene = t
	await _wait(20)
	t._on_tab("grocer")
	await _wait(12)
	for b in t.find_children("*", "Button", true, false):
		_check((b as Button).text != tr("TOWN_SELL"), "no Sell button in town")
	_shot("town_tabs")
	# Pip's second heart: his gift and his Teo line on his page
	var jars := int(d.cupboard.get("jar", 0))
	Economy.add_friendship(d, "postman", int(Data.rules().friendship.points_per_heart) * Story.NPC_HEARTS)
	t._show_rewards(0.1)
	await _secs(0.6)
	_check(String(t.get("_tab")) == "neighbours" and String(t.get("_npc")) == "postman", "Pip's page opens")
	_check(t.find_child("GiftBadge", true, false) != null, "the gift sits beside his hearts")
	_check(int(d.cupboard.get("jar", 0)) == jars + 3, "three jars in the cupboard (%d -> %d)" % [jars, int(d.cupboard.get("jar", 0))])
	var teo := tr("STORY_NPC_POSTMAN")
	var shown := false
	for l in t.find_children("*", "Label", true, false):
		shown = shown or ((l as Label).text == teo and (l as Label).is_visible_in_tree())
	_check(shown, "Pip says his Teo line")
	await _wait(10)
	_shot("gift_moment")
	t.queue_free()
	await _wait(4)


func _shot(shot_name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s%s.png" % [dir, shot_name, _suffix]
	RenderingServer.force_draw(false)  # macOS skips drawing a covered window
	root.get_texture().get_image().save_png(path)
	print("saved ", path.simplify_path())


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("cut_clutter: PROBLEM ", what)


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout
