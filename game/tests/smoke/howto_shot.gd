extends SceneTree
## Smoke shot (ONBOARD-HOWTO): the How to Play book.
##   1. the title's How to Play button (a real click): the five pages in English, then the title again in Turkish and
##      the five pages in Turkish; Right / Left, a click on a dot, Esc and "Got it!" (Enter) on the way;
##   2. New Game -> intro (skipped) -> How to Play over the intro's last picture -> Enter through it -> the garden;
##   3. there, Esc -> How to Play in the pause menu over the paused game; Esc closes the book, the menu stays.
## Shots: user://shots/howto_title.png, howto_1..5.png (and _tr for both), howto_after_intro.png, howto_pause.png.
## The player's save.json and settings.cfg are put back byte for byte (the New Game's save is real only for the one
## frame New Game takes, then a temporary game).
##   godot --path game --audio-driver Dummy -s res://tests/smoke/howto_shot.gd   (exit 1 on a failed check)
##
## `-- --pictures` renders the book's pictures instead: 1x crops of the real game (the Harvest Festival save, a
## temporary game) into res://assets/howto/<id>.png, the whole frames as user://shots/howto_src_<id>.png. Check
## them with pixel_cleanup.py --check --palette tools/palettes/autumn.hex before committing.

const TITLE := "res://scenes/title/title.tscn"
const SAVE := "user://save.json"
const SETTINGS := "user://settings.cfg"
const TRANSITION := "res://ui/transition/transition.gd"
const OUT := "res://assets/howto/"
const PIC := Vector2i(200, 110)

var _gs: Node
var _fail := 0
var _backup := {}


func _initialize() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_gs = root.get_node("GameState")
	_backup[SAVE] = _bytes(SAVE)
	_backup[SETTINGS] = _bytes(SETTINGS)
	if "--pictures" in OS.get_cmdline_user_args():
		_run_pictures()
	else:
		_run()


func _run() -> void:
	await process_frame
	var lang: Variant = GameSettings.get_value("game", "language")
	_language("en")
	await _pages("")
	_language("tr")
	await _pages("_tr")
	_language("en")
	await _new_game()
	_language(lang)
	_finish()


# ---------------------------------------------------------------- 1. the title's button, every page

func _pages(suffix: String) -> void:
	var title := _title()
	await _frames(6)
	var btn := title.get_node("%Menu").get_node_or_null("HowTo") as Button
	_check(btn != null and btn.is_visible_in_tree(), "title%s: a How to Play button in the menu" % suffix)
	if btn == null:
		return
	_check(btn.text == TranslationServer.translate("HOWTO_TITLE"), "title%s: the button says %s" % [suffix, btn.text])
	_shot("howto_title%s" % suffix)
	await _click(btn)
	var h := _howto()
	_check(h != null and h.page == 0, "the button opens the book on page 1")
	_check(not title.get_node("%Menu").visible, "the menu hides under the book")
	if h == null:
		return
	_check(root.gui_get_focus_owner() == h._next, "Next has the focus")
	for i in HowToPlay.page_count():
		await _seconds(0.2)  # after the picture's slide
		_shot("howto_%d%s" % [i + 1, suffix])
		_check(h._picture.texture != null and h._picture.texture.get_size() == Vector2(PIC), "page %d: a %dx%d picture" % [i + 1, PIC.x, PIC.y])
		_check(h._lines.get_child_count() >= 2 and h._lines.get_child_count() <= 3, "page %d: two or three lines" % (i + 1))
		if i < HowToPlay.page_count() - 1:
			_key(KEY_RIGHT)
			await _frames(2)
			_check(h.page == i + 1, "Right: page %d" % (i + 2))
	_check(h._done.visible and not h._next.visible and root.gui_get_focus_owner() == h._done, "last page: Got it! has the focus")
	_key(KEY_RIGHT)
	await _frames(2)
	_check(h.page == HowToPlay.page_count() - 1, "Right on the last page stays")
	_key(KEY_LEFT)
	await _frames(2)
	_check(h.page == HowToPlay.page_count() - 2 and root.gui_get_focus_owner() == h._next, "Left: one page back")
	await _click_at(h._dots.get_global_rect().position + Vector2(HowToPlay.Dots.STEP * 0.5, 8))
	_check(h.page == 0 and h._back.disabled, "a click on the first dot: page 1, Back disabled")
	_key(KEY_ESCAPE)
	await _frames(2)
	_check(not is_instance_valid(h) and _howto() == null, "Esc closes the book")
	_check(title.get_node("%Menu").visible and root.gui_get_focus_owner() == btn, "the menu is back, focus on How to Play")
	await _click(btn)
	h = _howto()
	h.show_page(HowToPlay.page_count() - 1)
	await _frames(2)
	_key(KEY_ENTER)
	await _frames(2)
	_check(_howto() == null, "Enter on Got it! closes the book")
	title.queue_free()
	await _frames(2)


# ---------------------------------------------------------------- 2. New Game -> intro -> How to Play -> garden

func _new_game() -> void:
	var router := root.get_node("Router")
	var title := _title()
	router.current = "title"
	await _frames(4)
	title._on_new_game()
	title._seed_edit.text = "howto"
	title._start()  # writes a fresh save: put the player's back at once, the game goes on as a temporary one
	_gs.data.flags["temp"] = true
	_write(SAVE, _backup[SAVE])
	_check(_bytes(SAVE) == _backup[SAVE], "the player's save is back right after New Game")
	var premise: Node = null
	for c in title.get_children():
		if c.has_method("_skip_or_leave"):
			premise = c
	_check(premise != null, "New Game plays the intro")
	if premise == null:
		return
	premise.skip()
	await _frames(3)
	var h := _howto()
	_check(h != null and h.page == 0, "after the intro: How to Play opens")
	_check(String(router.current) == "title" and not _busy(), "and waits there (no transition yet)")
	if h == null:
		return
	await _seconds(0.3)
	_shot("howto_after_intro")
	for i in HowToPlay.page_count():
		_key(KEY_ENTER)
		await _frames(2)
	_check(_howto() == null, "Enter through all five pages closes it")
	var home: String = load(TRANSITION).home_scene()
	var ok := await _until(func() -> bool: return String(router.current) == home and not _busy(), 8000)
	_check(ok, "then the game goes on to the %s" % home)
	await _frames(10)
	await _pause_howto()


# ---------------------------------------------------------------- 3. the pause menu's entry

func _pause_howto() -> void:
	_key(KEY_ESCAPE)
	await _frames(3)
	var m := PauseMenu.current()
	_check(m != null and paused, "Esc opens the pause menu")
	if m == null:
		return
	var b := m.get("_panel").find_child("HowTo", true, false) as Button
	_check(b != null and b.is_visible_in_tree(), "the pause menu has How to Play")
	if b == null:
		return
	await _click(b)
	var h := _howto()
	_check(h != null and paused and not (m.get("_panel") as Control).visible, "it opens the book over the paused game")
	if h != null:
		_key(KEY_RIGHT)
		await _frames(2)
		_check(h.page == 1, "the book flips while the game is paused")
		await _seconds(0.2)
		_shot("howto_pause")
	_key(KEY_ESCAPE)
	await _frames(3)
	_check(_howto() == null and PauseMenu.is_open() and (m.get("_panel") as Control).visible, "Esc closes the book, the menu stays")
	_check(root.gui_get_focus_owner() == b, "focus back on How to Play")
	_key(KEY_ESCAPE)
	await _frames(3)
	_check(not PauseMenu.is_open() and not paused, "the next Esc resumes")


# ---------------------------------------------------------------- pictures

## Five 1x crops of the real game, without the HUD and the To-Do note.
func _run_pictures() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var d := FestivalFacts.load_save()
	if not _check(not d.is_empty(), "the festival save loads"):
		_finish()
		return
	_gs.data = d
	_gs.notify(PackedStringArray(["*"]))
	var router := root.get_node("Router")

	# 1. Your autumn: Granny by her cottage in the garden
	var garden := _scene("res://scenes/garden/garden.tscn")
	await _seconds(1.0)
	_picture("autumn", garden, _around(garden.get("granny"), Vector2i(-100, -94)))
	garden.queue_free()
	await _frames(3)

	# 2. Forage: the forest, Granny shaking a fruit tree
	router.params = {"biome": "forest"}
	var wild := _scene("res://scenes/wild/wild.tscn")
	await _frames(5)
	var tree := _nearest_tree(wild)
	if tree != null and wild.granny.approach(tree.cell):
		var t0 := Time.get_ticks_msec()
		while not tree.highlighted and Time.get_ticks_msec() - t0 < 8000:
			await process_frame
		await _frames(5)
		wild._use(tree)
		await _seconds(0.25)
	_picture("forage", wild, _around(wild.granny, Vector2i(-100, -95)))
	wild.queue_free()
	router.params = {}
	await _frames(3)

	# 3. Cook: the stir-the-pot kitchen game
	var mg: Node = (load("res://minigames/stir_pot/stir_pot.tscn") as PackedScene).instantiate()
	root.add_child(mg)
	mg.start({"seed": 7, "recipe": "jam", "desc": {"appearance": {"fill": ["a22512", "c94d2e", "e19064"]}}})
	await _seconds(3.0)
	_picture("cook", mg, Rect2i(80, 62, PIC.x, PIC.y))
	mg.queue_free()
	await _frames(3)

	# 4. Pantry: the shelves after Auto-arrange
	var pantry := _scene("res://scenes/pantry/pantry.tscn")
	await _frames(10)
	pantry._on_auto()
	await _seconds(1.0)
	var notes: Array = pantry.get("_note_w")
	for i in notes.size():
		notes[i] = 0  # no wooden signs behind the (hidden) shelf notes
	pantry.queue_redraw()
	await _frames(2)
	_picture("pantry", pantry, Rect2i(280, 36, PIC.x, PIC.y))
	pantry.queue_free()
	await _frames(3)

	# 5. Share: market day, buyers at Granny's stall
	var market := _scene("res://scenes/market/market.tscn")
	await _frames(10)
	market._on_fill()
	await _frames(2)
	market._on_open()
	await _frames(2)
	market.set("_t", 12.0)
	await _seconds(1.5)
	_picture("share", market, Rect2i(140, 130, PIC.x, PIC.y))
	market.queue_free()
	await _frames(3)
	_finish()


func _scene(path: String) -> Node:
	var s := (load(path) as PackedScene).instantiate()
	root.add_child(s)
	return s


## A crop with its top-left at `offset` from the node's spot on screen, kept inside the screen.
func _around(n: Node, offset: Vector2i) -> Rect2i:
	var p := Vector2i((n as CanvasItem).get_global_transform_with_canvas().origin.round())
	print("granny on screen at ", p)
	var at := p + offset
	at.x = clampi(at.x, 0, 480 - PIC.x)
	at.y = clampi(at.y, 0, 270 - PIC.y)
	return Rect2i(at, PIC)


func _picture(id: String, scene: Node, r: Rect2i) -> void:
	for n in get_nodes_in_group("hud") + get_nodes_in_group("granny_todo"):
		(n as CanvasLayer).visible = false
	_hide_text(scene)
	RenderingServer.force_draw(false)
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/howto_src_%s.png" % id)
	var crop := img.get_region(r)
	var path := ProjectSettings.globalize_path(OUT + id + ".png")
	crop.save_png(path)
	print("saved %s from %s" % [path, r])


## Labels and their small panels would carry one language into the other's book: hidden in the pictures.
func _hide_text(n: Node) -> void:
	if n is Label or n is RichTextLabel:
		var c := n as Control
		c.visible = false
		var p := c.get_parent()
		if p is PanelContainer and p.get_child_count() == 1:
			(p as Control).visible = false
		return
	for ch in n.get_children():
		_hide_text(ch)


func _nearest_tree(scene: Node) -> Node2D:
	var from: Vector2 = scene.granny.position
	var best: Node2D = null
	for t in scene.map.fruit_trees:
		var o: Node2D = scene.view.find("fruit_tree", int(t.id))
		if o != null and (best == null or o.position.distance_to(from) < best.position.distance_to(from)):
			best = o
	return best


# ---------------------------------------------------------------- helpers

## The title applies the saved language on _ready: set it in memory only (never written; null = as it was).
func _language(lang: Variant) -> void:
	GameSettings._file().set_value("game", "language", lang)
	GameSettings.apply_language(String(lang) if lang != null else "en")


func _title() -> Node:
	var title := (load(TITLE) as PackedScene).instantiate()
	root.add_child(title)
	current_scene = title
	return title


func _howto() -> HowToPlay:
	var h := get_first_node_in_group("howto") as HowToPlay
	return h if h != null and not h._closing else null


func _busy() -> bool:
	return bool(load(TRANSITION).is_busy())


func _click(c: Control) -> void:
	await _click_at(c.get_global_rect().get_center().floor())


func _click_at(p: Vector2) -> void:
	for pressed in [true, false]:
		var mv := InputEventMouseMotion.new()
		mv.position = p
		mv.global_position = p
		root.push_input(mv, true)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.button_mask = 1 if pressed else 0
		ev.position = p
		ev.global_position = p
		root.push_input(ev, true)
		await process_frame
	await _frames(2)


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		root.push_input(ev, true)


func _until(cond: Callable, ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()) and Time.get_ticks_msec() - t0 < ms:
		await process_frame
	return bool(cond.call())


func _seconds(s: float) -> void:
	await create_timer(s, true).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> bool:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fail += 1
	return ok


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("user://shots/%s.png" % shot_name)
	print("saved ", ProjectSettings.globalize_path("user://shots/%s.png" % shot_name))


func _bytes(path: String) -> Variant:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null


func _write(path: String, bytes: Variant) -> void:
	if bytes == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


func _finish() -> void:
	paused = false
	if _bytes(SAVE) != _backup[SAVE]:
		_write(SAVE, _backup[SAVE])
	if _bytes(SETTINGS) != _backup[SETTINGS]:
		_write(SETTINGS, _backup[SETTINGS])
	_check(_bytes(SAVE) == _backup[SAVE] and _bytes(SETTINGS) == _backup[SETTINGS], "the player's save and settings are as they were")
	print("HOWTO SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)
