extends SceneTree
## Smoke shot (PARLOR): Granny's parlour alone (throwaway game, day 1 with every To-Do step but the bed done).
## Checks the painted room, Granny by the kitchen door and the cat in her basket, the bed glowing for the To-Do bed
## step, the bookshelf opening the recipe book, the side table (no letters yet: a line; one letter: its tag and the
## letters overlay, the room back after closing), petting the cat (purr, nothing in the save changes), the bed's
## question and the night (day 1 -> 2), and the door back to the kitchen, where the parlour doormat is captioned.
## Saves user://shots/parlor_<locale>.png (entry, captions), parlor_cat_<locale>.png, parlor_kitchen_<locale>.png.
##   godot --path game --rendering-driver opengl3 --audio-driver Dummy -s res://tests/smoke/parlor_shot.gd [-- --locale=tr]
## (not headless; wrap it in a timeout). Exit code 1 on a failed check.

const PARLOR := "res://scenes/parlor/parlor.tscn"
const TODO_GD := "res://ui/tutorial/granny_todo.gd"

var _p: Control
var _fail := 0
var _locale := "en"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--locale="):
			_locale = a.substr(9)
	_run()


func _run() -> void:
	GameSettings.apply_language(_locale)
	await process_frame
	var gs: Node = root.get_node("GameState")
	var router: Node = root.get_node("Router")
	gs.start_temp(1)
	var d: Dictionary = gs.data
	d.flags["tutorial"] = 111  # day 1: mail, shake, pick (FIRST-60B), jam, pantry and order done; the bed is next
	router.current = "parlor"  # the To-Do note hides outside game scenes
	load(TODO_GD).ensure()  # in the game the note is already there when Granny walks in
	await _frames(2)
	_p = (load(PARLOR) as PackedScene).instantiate()
	root.add_child(_p)
	current_scene = _p  # the door's scene change frees the parlour
	await _frames(12)
	_check(_p._message.text != "", "the message bar says something on entry")

	# --- the room
	var bg: TextureRect = _p.get_node("%Background")
	_check(bg.texture != null and bg.texture.resource_path.ends_with("bg_parlor.png"), "painted parlour")
	for k in ["door", "shelf", "letters", "cat", "bed"]:
		var h: Control = _p._spots.get(k)
		_check(h != null and h.size.x >= 16 and h.size.y >= 16 and h.caption != null, "hotspot %s (>=16 px, captioned)" % k)
	var g: TextureRect = _p._granny
	_check(g != null and g.size == Vector2(44, 88) and g.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Granny at kitchen scale")
	_check(g != null and g.get_rect().position.x < 110, "Granny stands just in from the kitchen door")
	_check(_p._cat != null and _p._spots.cat.get_rect().has_point(_p._cat.position - Vector2(0, 6)), "the cat in her basket")
	_check(_p._spots.bed.glow and not _p._spots.door.glow, "the To-Do bed step glows on the bed")
	_shot("parlor_" + _locale)

	# --- the bookshelf: the recipe book
	_p._on_spot("shelf")
	await _frames(6)
	var book: Node = get_first_node_in_group("book")
	_check(book != null, "the bookshelf opens the recipe book")
	if book != null:
		book.close_book()
	await _frames(20)

	# --- the side table: no letters yet, then one letter
	Letters.ensure(d).inbox.clear()  # a new game starts with Nora's story letter in the inbox
	_p._on_spot("letters")
	await _frames(2)
	_check(_p._message.text == tr("GARDEN_NO_MAIL") and get_first_node_in_group("letters_ui") == null, "no letters: a line")
	var l: Dictionary = Letters.ensure(d)
	l.inbox.append(Letters.make_request(d, String(Letters.kids()[0]), Seeds.rng(int(d.save_seed), "letters", 1)))
	gs.notify(PackedStringArray(["letters"]))
	await _frames(2)
	_check(_p._tag.count == 1, "the side table's tag: 1 unread letter")
	_p._sticky_until = 0
	_p._on_spot("letters")
	await _frames(8)
	var ui: Node = get_first_node_in_group("letters_ui")
	_check(ui != null and not _p._room_active, "the letters open")
	if ui != null:
		ui.close()
	await _frames(8)
	_check(_p._room_active and _p.menu == null, "closing the letters gives the room back")

	# --- the cat: purr and a heart, the save unchanged
	var before := var_to_str(d)
	_p._on_spot("cat")
	await _frames(20)
	_check(_p._cat.is_purring() and _p._message.text == tr("PARLOR_CAT_PURR"), "petting: purr and a line")
	_check(var_to_str(d) == before, "petting changes nothing in the save")
	_shot("parlor_cat_" + _locale)

	# --- STORY-02: the seven memories (heart + record on the first look, a bubble in Granny's voice)
	for k in Story.OBJECTS:
		var h: Control = _p._spots.get(k)
		_check(h != null and h.size.x >= 16 and h.size.y >= 16 and h.caption != null, "memory hotspot %s (>=16 px, captioned)" % k)
	_check(not Story.seen(d, "teo") and _p._spots.teo.caption.text == tr("STORY_OBJ_CAP_PHOTO"), "Teo's photo: captioned, not seen yet")
	_p._on_spot("teo")
	await _frames(14)
	var bubbles: Array = _p._room.get_children().filter(func(n: Node) -> bool: return n is SpeechBubble)
	_check(bubbles.size() == 1 and bubbles[0].line_count() <= 2, "one bubble of at most 2 lines")
	_check(bubbles.size() == 1 and bubbles[0].label.text.begins_with(tr("STORY_OBJ_TEO").substr(0, 12)), "Teo's line (%s)" % _locale)
	_check(Story.seen(d, "teo") and "teo" in Story.flags(d).seen, "the first look is recorded in flags.story.seen")
	_shot("story02_memory_" + _locale)
	var seen_n: int = Story.flags(d).seen.size()
	_p._on_spot("teo")  # the same key again skips; no second heart, no second record
	_p._story_chunks.clear()
	await _frames(2)
	_check(Story.flags(d).seen.size() == seen_n, "looking again records nothing new")
	for k in Story.OBJECTS:
		var long_ok := true
		for c: String in _p.chunks(tr(Story.object_key(d, k))):
			long_ok = long_ok and _p._bubble_lines(c) <= 3
		_check(long_ok, "memory %s fits its bubbles" % k)
	_p._on_spot("jar")
	await _frames(2)
	_p._story_chunks.clear()  # skip the rest of the empty jar's line
	_check(not _p._props.jar.filled and Story.object_key(d, "jar") == "STORY_OBJ_JAR", "the sill jar is empty before a first jar")
	d.pantry.items.append({"item": {}, "where": "shelf"})  # the first jar stands on the shelf
	gs.notify(PackedStringArray(["pantry"]))
	await _frames(2)
	_check(_p._props.jar.filled and Story.object_key(d, "jar") == "STORY_OBJ_JAR_FILLED", "the sill jar is full after the first jar")
	_p._on_spot("jar")
	await _frames(14)
	_check(_p._message != null and _p._room.get_children().any(func(n: Node) -> bool: return n is SpeechBubble and n.label.text == tr("STORY_OBJ_JAR_FILLED")), "the 'Filled.' line")
	_shot("story02_jar_" + _locale)
	d.pantry.items.clear()

	# --- STORY-04: the knife is the 8th memory, hidden until it is found in the forest
	_check(not _p._spots.knife.visible and not _p._props.knife.visible, "no knife on the ledge before the find")
	Story.mark_knife_found(d)
	gs.notify(PackedStringArray(["flags"]))
	await _frames(2)
	_check(_p._spots.knife.visible and _p._spots.knife.caption.text == tr("CAP_KNIFE"), "the found knife: captioned hotspot")
	_check(_p._spots.knife.size.x >= 16 and _p._spots.knife.size.y >= 16, "knife hotspot >= 16 px")
	_p._story_chunks.clear()
	_p._on_spot("knife")
	await _frames(14)
	_check(Story.seen(d, "knife"), "the first look at the knife is recorded")
	_check(_p._room.get_children().any(func(n: Node) -> bool: return n is SpeechBubble and n.label.text.begins_with(tr("STORY_OBJ_KNIFE").substr(0, 12))), "the knife's line")
	_p._spots.knife._on_state()
	_p._reveal_captions(false)  # the captions would cover the little knife
	await _frames(2)
	_shot("story04_knife_" + _locale)

	# --- the bed: ask, Night, day 2
	var day0 := int(d.day)
	_p._on_spot("bed")
	await _frames(2)
	_check(_p._dialog.visible, "the bed asks first")
	_p._on_sleep()
	await _frames(2)
	var night: Node = null
	for n in root.get_children():
		if n.has_signal("finished") and n.get("after_scene") != null:
			night = n
	_check(night != null, "Night started")
	var t0 := Time.get_ticks_msec()
	while night != null and is_instance_valid(night) and not night.get("_accepting") and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	if night != null and is_instance_valid(night):
		night._button.pressed.emit()
	t0 = Time.get_ticks_msec()
	while not _p._room_active and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_check(int(gs.data.day) == day0 + 1 and _p._room_active, "slept in the parlour: day %d -> %d" % [day0, int(gs.data.day)])

	# --- the door: back to the kitchen, where the parlour doormat waits
	_p._on_spot("door")
	t0 = Time.get_ticks_msec()
	while String(router.current) != "kitchen" and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_check(String(router.current) == "kitchen", "the door leads to the kitchen")
	var transition: GDScript = load("res://ui/transition/transition.gd")
	t0 = Time.get_ticks_msec()
	while transition.is_busy() and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	await _frames(10)
	var k: Node = current_scene
	var door: Control = k._spots.get("parlor") if k != null and "_spots" in k else null
	_check(door != null and door.caption != null and door.caption.text == tr("KITCHEN_TO_PARLOR"), "the kitchen's parlour door")
	if door != null:
		k._reveal_captions(true)
		await _frames(2)
	_shot("parlor_kitchen_" + _locale)
	print("PARLOR SMOKE ", "OK" if _fail == 0 else "FAILED (%d)" % _fail)
	quit(1 if _fail > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fail += 1
	return ok


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)  # macOS skips frames while the window is covered; draw this one anyway
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("saved ", ProjectSettings.globalize_path("%s/%s.png" % [dir, name]))
