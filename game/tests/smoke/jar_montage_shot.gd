extends SceneTree
## MONTAGE: ~40 generated products of save seed 452, each a JarIcon at 4x (bottles 3x) with its generated English name
## under it, one PNG per product: builds/media/montage/jars/NN.png + jars.json [{file, name, key}].
## tools/publish/make_gifs.py turns the list into jar_wall.gif.
## FIX-JURY-B: only jars the game can make. A base recipe takes a variety only when its slot does (as Kitchen._fits:
## the slot's types or groups; syrup's main is a juice, so a fruit; bread has no fruit slot), chutney its vegetable
## second, any add-in (family recipes are left out: they take one fixed add-in). Then a few jars of the save's
## generated species (known by day SPECIES_DAY, in recipes whose groups take them) and FormulaGen inventions of 2-3
## distinct parts (fresh varieties, nuts, now and then a finished jar of the wall) with 0-1 add-in, inside the
## component count and nesting depth Kitchen.check_formula allows.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/jar_montage_shot.gd     (windowed: shots need a GPU)
const SEED := 452
const COUNT := 40
const SPECIES := 4
const FORMULAS := 8
const SPECIES_DAY := 14
const CELL := Vector2i(120, 214)  ## the name gets three lines ("Tart Ember Crabapple Chutney" wraps)
const OUT := "../builds/media/montage/jars"
const PAPER := Color("f2d9c5")
const INK := Color("50361e")


func _initialize() -> void:
	_run.call_deferred()


## The varieties a player of seed SEED has on SPECIES_DAY: P0 and P1 types, plus the species met so far.
func _varieties() -> Dictionary:
	var s := State.new_game(SEED)
	VarietyGen.ensure_types(s.varieties, SEED)
	s.day = SPECIES_DAY
	SpeciesGen.sync(s)
	return s.varieties


## Varieties (sorted ids) a recipe slot takes; `species` false leaves the generated species out.
static func fitting(varieties: Dictionary, slot: Variant, species: bool = true) -> Array:
	var out: Array = []
	if typeof(slot) != TYPE_DICTIONARY:
		return out
	var ings := Data.ingredients()
	for id: String in varieties:
		var v: Dictionary = varieties[id]
		if bool(v.get("species", false)) and not species:
			continue
		var type := String(v.type)
		var ok := false
		if slot.has("types"):
			ok = (slot.types as Array).has(type)
		elif slot.has("groups"):
			ok = (slot.groups as Array).has(String(ings.get(type, {}).get("group", "")))
		elif slot.has("recipe"):  # syrup: boiled from a juice, so the juice's own slot decides
			ok = fitting({id: v}, Data.recipes()[String(slot.recipe)].get("main"), species).size() == 1
		if ok:
			out.append(id)
	out.sort()
	return out


## A key the cook panel can make from `mains` (the main slot's choices), or "" when a slot has nothing to take.
## Only the slots the recipe has count (Kitchen.product_key: bread -> "bread|<add-in>").
static func recipe_key(rid: String, varieties: Dictionary, r: RandomNumberGenerator, addins: Array, mains: Array) -> String:
	var rec: Dictionary = Data.recipes()[rid]
	var seconds := fitting(varieties, rec.get("second"), false)
	if typeof(rec.get("main")) == TYPE_DICTIONARY and mains.is_empty():
		return ""
	if typeof(rec.get("second")) == TYPE_DICTIONARY and seconds.is_empty():
		return ""
	var main := String(mains[r.randi() % mains.size()]) if not mains.is_empty() else ""
	var second := String(seconds[r.randi() % seconds.size()]) if not seconds.is_empty() else ""
	return Kitchen.product_key(rid, main, second, String(addins[r.randi() % addins.size()]))


func _keys(varieties: Dictionary) -> Array:
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
	# base recipes, round robin
	var tries := 0
	while keys.size() < COUNT - SPECIES - FORMULAS and tries < 4000:
		var rid: String = recipes[tries % recipes.size()]
		tries += 1
		if rid == "bread" and keys.any(func(k: String) -> bool: return k.begins_with("bread|")):
			continue  # every loaf looks the same: one on the wall
		_add(recipe_key(rid, varieties, r, addins, fitting(varieties, Data.recipes()[rid].get("main"), false)), varieties,
			keys, names)
	# the generated species, each in a recipe whose slot takes its group
	var sp_ids: Array = []
	for id: String in varieties:
		if bool(varieties[id].get("species", false)):
			sp_ids.append(id)
	sp_ids.sort()
	var made := 0
	tries = 0
	while made < SPECIES and not sp_ids.is_empty() and tries < 400:
		var vid := String(sp_ids[tries % sp_ids.size()])
		tries += 1
		var rid: String = recipes[r.randi() % recipes.size()]
		if fitting(varieties, Data.recipes()[rid].get("main")).has(vid) \
				and _add(recipe_key(rid, varieties, r, addins, [vid]), varieties, keys, names):
			made += 1
	# inventions: 2-3 distinct parts, sometimes a finished jar of the wall
	var vids: Array = varieties.keys()
	vids.sort()
	var jars := keys.duplicate()
	var methods: Array = FormulaGen.methods()
	var nuts := ["walnut", "hazelnut", "chestnut"]
	var cfg := FormulaGen.cfg()
	tries = 0
	made = 0
	while made < FORMULAS and tries < 500:
		tries += 1
		var comps: Array = [vids[r.randi() % vids.size()], vids[r.randi() % vids.size()]]
		match r.randi() % 3:
			0:
				comps.append(nuts[r.randi() % nuts.size()])
			1:
				comps.append(String(jars[r.randi() % jars.size()]))
		var ads: Array = [] if r.randi() % 3 == 0 else [ad_ids[r.randi() % ad_ids.size()]]
		var key := FormulaGen.make_key(methods[r.randi() % methods.size()], comps, ads)
		var parts: Array = FormulaGen.parse(key).get("components", [])
		if parts.size() < int(cfg.components_min) or parts.size() > int(cfg.components_max) \
				or FormulaGen.depth(key) > int(cfg.max_depth):
			continue
		if _add(key, varieties, keys, names):
			made += 1
	return keys


## Appends `key` when its English name is new on the wall.
static func _add(key: String, varieties: Dictionary, keys: Array, names: Dictionary) -> bool:
	if key == "":
		return false
	var nm := ProductGen.product_name(key, varieties)
	if nm == "" or names.has(nm):
		return false
	names[nm] = true
	keys.append(key)
	return true


func _run() -> void:
	await process_frame
	GameSettings.apply_language("en")
	var varieties := _varieties()
	var keys := _keys(varieties)
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
		jar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # FIX-JURY-B: a SubViewport filters linearly by default
		jar.position = Vector2((CELL.x - jar.size.x) / 2.0, 148 - jar.size.y)
		bg.add_child(jar)
		var l := Label.new()
		l.text = nm
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(4, 152)
		l.size = Vector2(CELL.x - 8, CELL.y - 154)
		l.add_theme_color_override("font_color", INK)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		bg.add_child(l)
		await process_frame
		await process_frame
		RenderingServer.force_draw(false)
		var img := vp.get_texture().get_image()
		var file := "%02d.png" % i
		img.save_png(dir.path_join(file))
		list.append({"file": file, "name": nm, "key": String(keys[i])})
		vp.queue_free()
	var jf := FileAccess.open(dir.get_base_dir().path_join("jars.json"), FileAccess.WRITE)
	jf.store_string(JSON.stringify(list, "\t"))
	jf.close()
	print("jar_montage_shot: %d jars -> %s" % [list.size(), dir])
	quit(0 if list.size() >= 36 else 1)
