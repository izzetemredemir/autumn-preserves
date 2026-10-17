extends SceneTree
## Smoke shot (SPECIES-GEN) -> user://shots/: species_forest.png (a forest with today's new species, Granny beside its
## first pickup), species_card_en.png / species_card_tr.png (the "New species!" card), species_book_en.png /
## species_book_tr.png (the book's forest species page), and builds/media/species_sheet.png: 40 generated icons with
## their English and Turkish names (3x), for the human check.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/species_shot.gd     (windowed: shots need a GPU)
## Exit code 1 on a failed check.

const SEED := 1
const DAY := 14
const SHEET_SEED := 2026
const SHEET_COUNT := 40
const DIR := "user://shots"
const SHEET := "../builds/media/species_sheet.png"

var _gs: Node
var _failed := false


func _initialize() -> void:
	_gs = root.get_node("GameState")
	root.get_node("Router").params = {"biome": "forest", "grow": false}
	_run()


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(DIR)
	GameSettings.apply_language("en")
	_gs.start_temp(SEED)
	var d: Dictionary = _gs.data
	d.day = DAY
	d.weather = DayEnd.weather_for(SEED, DAY)
	SpeciesGen.sync(d)
	var today := SpeciesGen.for_day(SEED, DAY)
	_check(not today.is_empty(), "seed %d has a new species on day %d" % [SEED, DAY])
	for sp: Dictionary in SpeciesGen.known(SEED, DAY - 1).slice(0, 5):  # met before: in the book; the rest stay ???
		d.species_seen[sp.id] = int(sp.day)

	# 1. the forest, Granny next to the first pickup of today's species
	var scene: Node = (load("res://scenes/wild/wild.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(6)
	var target: Dictionary = {}
	for p: Dictionary in scene.map.pickups:
		if bool(p.get("species", false)) and (target.is_empty() or (not today.is_empty() and p.type == today[0].id)):
			target = p
			if not today.is_empty() and p.type == today[0].id:
				break
	_check(not target.is_empty(), "the forest has a species pickup")
	var type := String(target.get("type", today[0].id if not today.is_empty() else ""))
	if not target.is_empty():
		var c := Vector2i(int(target.x), int(target.y))
		for dir: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			if scene._walkable(c + dir):
				scene.granny.teleport(c + dir, -dir)
				break
		scene.camera.snap()
		var o: WildObject = scene.view.find(String(target.kind), int(target.id))
		_check(o != null and o._texture() != null, "the species pickup draws a sprite")
	await _frames(8)
	_shot("species_forest")

	# 2. the card, English then Turkish
	for lang in ["en", "tr"]:
		GameSettings.apply_language(lang)
		scene._species_card(type)
		await create_timer(0.45).timeout  # after the pop-in
		var card := _find_card(scene)
		_check(card != null and IconLib.ingredient(type) != null, "card with an icon (%s)" % lang)
		_shot("species_card_" + lang)
		if card != null:
			card.close()
		await _frames(3)
	scene.queue_free()
	await _frames(3)

	# 3. the book's species page, Turkish then English
	d.species_seen[type] = DAY
	for lang in ["tr", "en"]:
		GameSettings.apply_language(lang)
		var b := Book.open()
		await _frames(6)
		b.show_book(1)
		b._page = b._type_pages()
		b._refresh()
		await _frames(6)
		_check(b._page_count() > b._type_pages(), "the Varieties tab has a species page")
		_shot("species_book_" + lang)
		b.close_book()
		await _frames(3)

	# 4. the icon sheet for the human check
	await _sheet()
	print("species_shot: %s" % ("FAILED" if _failed else "ok"))
	quit(1 if _failed else 0)


func _find_card(scene: Node) -> SpeciesCard:
	for c in scene.get_children():
		if c is SpeciesCard and not c.is_queued_for_deletion():
			return c
	return null


## 40 species of SHEET_SEED: icon at 3x, English name, Turkish name, group and rarity, on paper, 5 columns.
func _sheet() -> void:
	var list := SpeciesGen.known(SHEET_SEED, 200).slice(0, SHEET_COUNT)
	_check(list.size() == SHEET_COUNT, "%d species for the sheet" % list.size())
	for sp: Dictionary in list:
		SpeciesGen.register(sp)
	var cols := 5
	var cell := Vector2i(192, 62)
	var vp := SubViewport.new()
	vp.size = Vector2i(cols * cell.x + 8, ceili(list.size() / float(cols)) * cell.y + 8)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color("f2d9c5")
	bg.size = Vector2(vp.size)
	bg.theme = load("res://ui/theme/theme.tres")
	vp.add_child(bg)
	for i in list.size():
		var sp: Dictionary = list[i]
		var at := Vector2(4 + (i % cols) * cell.x, 4 + floori(i / float(cols)) * cell.y)
		var icon := TextureRect.new()
		icon.texture = IconLib.ingredient(String(sp.id))
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.position = at + Vector2(4, 6)
		icon.size = Vector2(48, 48)
		bg.add_child(icon)
		var lines := [String(sp.display_name), String(sp.display_name_tr), "%s %s" % [sp.rarity, sp.group]]
		var colors := [Color("50361e"), Color("83571e"), Color("4e7664")]
		for k in 3:
			var l := Label.new()
			l.text = lines[k]
			l.position = at + Vector2(58, 2 + k * 18)
			l.add_theme_color_override("font_color", colors[k])
			l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
			bg.add_child(l)
	await _frames(4)
	RenderingServer.force_draw(false)
	var img := vp.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://").path_join(SHEET)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if img == null or img.is_empty():
		print("no image for the species sheet (headless: run windowed)")
	else:
		img.save_png(path)
		print("saved ", path)
	vp.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	RenderingServer.force_draw(false)  # macOS skips drawing a covered window; the shot must show this frame
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		print("no image for ", shot_name, " (headless: run windowed for the shots)")
		return
	img.save_png("%s/%s.png" % [DIR, shot_name])
	print("saved ", ProjectSettings.globalize_path("%s/%s.png" % [DIR, shot_name]))


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("CHECK FAILED: ", what)
