extends SceneTree
## MONTAGE: 30 generated species of save seed 452 (icon at 4x + English name), one PNG each:
## builds/media/montage/species/NN.png + species.json [{file, name}]. tools/publish/make_gifs.py makes species.gif.
##   godot --path game --audio-driver Dummy -s res://tests/smoke/species_montage_shot.gd     (windowed)
const SEED := 452
const COUNT := 30
const CELL := Vector2i(160, 104)
const OUT := "../builds/media/montage/species"
const PAPER := Color("f2d9c5")
const INK := Color("50361e")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	GameSettings.apply_language("en")
	var list := SpeciesGen.known(SEED, 200).slice(0, COUNT)
	for sp: Dictionary in list:
		SpeciesGen.register(sp)
	var dir := ProjectSettings.globalize_path("res://").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var out: Array = []
	for i in list.size():
		var sp: Dictionary = list[i]
		var vp := SubViewport.new()
		vp.size = CELL
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var bg := ColorRect.new()
		bg.color = PAPER
		bg.size = Vector2(CELL)
		bg.theme = load("res://ui/theme/theme.tres")
		vp.add_child(bg)
		var icon := TextureRect.new()
		icon.texture = IconLib.ingredient(String(sp.id))
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.size = Vector2(64, 64)
		icon.position = Vector2((CELL.x - 64) / 2.0, 8)
		bg.add_child(icon)
		var l := Label.new()
		l.text = String(sp.display_name)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(4, 76)
		l.size = Vector2(CELL.x - 8, 26)
		l.add_theme_color_override("font_color", INK)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		bg.add_child(l)
		await process_frame
		await process_frame
		RenderingServer.force_draw(false)
		var file := "%02d.png" % i
		vp.get_texture().get_image().save_png(dir.path_join(file))
		out.append({"file": file, "name": String(sp.display_name)})
		vp.queue_free()
	var jf := FileAccess.open(dir.get_base_dir().path_join("species.json"), FileAccess.WRITE)
	jf.store_string(JSON.stringify(out, "\t"))
	jf.close()
	print("species_montage_shot: %d species -> %s" % [out.size(), dir])
	quit(0 if out.size() == COUNT else 1)
