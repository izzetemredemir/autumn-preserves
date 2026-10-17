extends SceneTree
## FIRST-60 smoke shots -> user://shots/first60_*.png, and a few runtime checks (prints FIRST60 OK / FIRST60 FAIL).
##   godot --path game --audio-driver Dummy -s res://tests/smoke/first60_shot.gd [-- --locale=tr]
## title_a / title_b: the living title at two moments (smoke, birds over the valley, river glints, leaves in front).
## intro_<beat>: each beat of the premise intro with its line typed; intro_fade: the valley dithering into the cottage.
## grow_mid / grow_fade: the world-grow overlay over today's forest (temp game, seed 452) half-way and fading out.
## The player's settings.cfg is not touched (the intro is shown, never finished).

const TITLE := "res://scenes/title/title.tscn"
const PREMISE := "res://ui/premise/premise.tscn"
const WILD := "res://scenes/wild/wild.tscn"
const BEATS := "res://ui/premise/intro_beats.gd"
const GROW := "res://ui/transition/world_grow.gd"
const DIR := "user://shots"

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
	await _title()
	await _intro()
	await _grow()
	print("FIRST60 OK" if _fails.is_empty() else "FIRST60 FAIL: %s" % ", ".join(_fails))
	quit(1 if not _fails.is_empty() else 0)


func _title() -> void:
	var title := (load(TITLE) as PackedScene).instantiate()
	root.add_child(title)
	await _frames(4)
	var bg: Node = title.get_node("Backdrop")
	var fx: TitleFx = bg.get("_fx")
	var menu := Rect2i(180, 96, 120, 100)
	var front_t := -1.0  # a moment with a front leaf over the buttons, after the flock has come in
	for k in 400:
		var t := 8.0 + k * 0.05
		for l in fx.get("_front"):
			if menu.has_point(TitleFx.leaf_pos(l, t)):
				front_t = t
		if front_t > 0.0:
			break
	_check(front_t > 0.0, "a front leaf crosses the menu (t %.2f)" % front_t)
	for m in [["a", 4.0], ["b", front_t if front_t > 0.0 else 13.2]]:
		bg.seek(float(m[1]))
		await _frames(2)
		_shot("title_" + String(m[0]))
	# Frame time with the painting's life on and off (vsync off, uncapped).
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var on := await _frame_ms(240)
	for part in ["leaves", "front", "smoke", "birds", "glints", "motes"]:
		fx.set(part, false)
	var off := await _frame_ms(240)
	print("title frame: %.3f ms with life, %.3f ms without" % [on, off])
	_check(on - off < 0.5, "the title's life costs under 0.5 ms a frame (%.3f)" % (on - off))
	title.queue_free()
	await _frames(2)


func _intro() -> void:
	var beats: GDScript = load(BEATS)
	var premise: Node = (load(PREMISE) as PackedScene).instantiate()
	root.add_child(premise)
	premise.set_process(false)  # driven by seek only
	await _frames(3)
	for i in beats.count():
		premise.seek(beats.start(i) + float(beats.BEATS[i][2]) * 0.8)
		await _frames(2)
		_shot("intro_" + String(beats.BEATS[i][0]))
	premise.seek(beats.start(1) + beats.FADE * 0.5)
	await _frames(2)
	_shot("intro_fade")
	_check(absf(beats.total() - 19.8) < 0.01, "intro lasts about 20 s (%.1f)" % beats.total())
	premise.queue_free()
	await _frames(2)


func _grow() -> void:
	var gs := root.get_node("GameState")
	var router := root.get_node("Router")
	gs.start_temp(452)
	router.params = {"biome": "forest", "grow": true}
	var wild := (load(WILD) as PackedScene).instantiate()
	root.add_child(wild)
	await _frames(3)
	var grow: Node = null
	for c in wild.get_children():
		if c.get_script() == load(GROW):
			grow = c
	_check(grow != null, "the overlay opens with params.grow")
	_check(wild.granny != null and not wild.granny.input_enabled, "Granny waits while the forest grows")
	_check(int(gs.data.flags.get("wild_grow_day", 0)) == int(gs.data.day), "the save remembers the day it played")
	if grow != null:
		grow.set_process(false)
		grow.seek(1.6)
		await _frames(2)
		_shot("grow_mid")
		grow.seek(3.65)
		await _frames(2)
		_shot("grow_fade")
		grow.set_process(true)
		grow.seek(load(GROW).duration() - 0.01)
		await _frames(4)
		_check(not is_instance_valid(grow), "the overlay is gone after the fade")
		_check(wild.granny.input_enabled, "Granny walks again")
	router.params = {}
	wild.queue_free()
	await _frames(2)


func _shot(name: String) -> void:
	RenderingServer.force_draw(false)
	var file := "%s/first60_%s%s.png" % [DIR, name, _suffix]
	root.get_texture().get_image().save_png(file)
	print("saved ", ProjectSettings.globalize_path(file))


func _frame_ms(n: int) -> float:
	await _frames(10)
	var t0 := Time.get_ticks_usec()
	await _frames(n)
	return (Time.get_ticks_usec() - t0) / 1000.0 / n


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)
