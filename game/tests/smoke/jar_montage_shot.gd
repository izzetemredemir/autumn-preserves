extends SceneTree
## MONTAGE: ~40 generated products (base recipes x varieties x add-ins, plus FormulaGen inventions) of save seed 452,
## each a JarIcon at 4x (bottles 3x) with its generated English name under it, one PNG per product:
## builds/media/montage/jars/NN.png + jars.json [{file, name}]. tools/publish/make_gifs.py turns the list into jar_wall.gif.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/jar_montage_shot.gd     (windowed: shots need a GPU)
const SEED := 452
const COUNT := 40
const FORMULAS := 8
const CELL := Vector2i(120, 190)
const OUT := "../builds/media/montage/jars"
const PAPER := Color("f2d9c5")
const INK := Color("50361e")


func _initialize() -> void:
	_run.call_deferred()


func _keys() -> Array:
	var varieties: Dictionary = State.new_game(SEED).varieties
	var vids: Array = varieties.keys()
	vids.sort()
	var recipes: Array = []
	for rid: String in Data.recipes():
		if not Data.recipes()[rid].has("family_of"):
			recipes.append(rid)
	recipes.sort()
	var addins: Array = [""]
	var ad_ids: Array = Data.addins().keys()
	ad_ids.sort()
	addins.append_array(ad_ids)
	var r := RandomNumberGenerator.new()
	r.seed = SEED
	var keys: Array = []
	var names := {}
	var tries := 0
	while keys.size() < COUNT - FORMULAS and tries < 2000:
		tries += 1
		var rid: String = recipes[keys.size() % recipes.size()]
		var key := ProductGen.make_key(rid, [vids[r.randi() % vids.size()]], addins[r.randi() % addins.size()])
		var nm := ProductGen.product_name(key, varieties)
		if not names.has(nm):
			names[nm] = true
			keys.append(key)
	var methods: Array = FormulaGen.methods()
	var nuts := ["walnut", "hazelnut"]
	tries = 0
	var fx := 0
	while fx < FORMULAS and tries < 500:
		tries += 1
		var comps: Array = [vids[r.randi() % vids.size()], vids[r.randi() % vids.size()]]
		if r.randi() % 2 == 0:
			comps.append(nuts[r.randi() % nuts.size()])
		var key := FormulaGen.make_key(methods[r.randi() % methods.size()], comps, [addins[1 + r.randi() % (addins.size() - 1)]])
		var nm := ProductGen.product_name(key, varieties)
		if not names.has(nm):
			names[nm] = true
			keys.append(key)
			fx += 1
	return [keys, varieties]


func _run() -> void:
	await process_frame
	GameSettings.apply_language("en")
	var made := _keys()
	var keys: Array = made[0]
	var varieties: Dictionary = made[1]
	var dir := ProjectSettings.globalize_path("res://").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var list: Array = []
	for i in keys.size():
		var desc := ProductGen.describe(keys[i], varieties)
		var nm := String(desc.name)
		var vp := SubViewport.new()
		vp.size = CELL
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var bg := ColorRect.new()
		bg.color = PAPER
		bg.size = Vector2(CELL)
		bg.theme = load("res://ui/theme/theme.tres")
		vp.add_child(bg)
		var jar := JarIcon.new()
		jar.zoom = 3 if String(desc.vessel) == "bottle" else 4
		jar.show_product(desc)
		jar.position = Vector2((CELL.x - jar.size.x) / 2.0, 144 - jar.size.y)
		bg.add_child(jar)
		var l := Label.new()
		l.text = nm
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(4, 150)
		l.size = Vector2(CELL.x - 8, 36)
		l.add_theme_color_override("font_color", INK)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		bg.add_child(l)
		await process_frame
		await process_frame
		RenderingServer.force_draw(false)
		var img := vp.get_texture().get_image()
		var file := "%02d.png" % i
		img.save_png(dir.path_join(file))
		list.append({"file": file, "name": nm})
		vp.queue_free()
	var jf := FileAccess.open(dir.get_base_dir().path_join("jars.json"), FileAccess.WRITE)
	jf.store_string(JSON.stringify(list, "\t"))
	jf.close()
	print("jar_montage_shot: %d jars -> %s" % [list.size(), dir])
	quit(0 if list.size() >= 36 else 1)
