extends SceneTree
## Review sheet for the market villagers v2 (MARKET-LIVE): 24 random villagers (front, side, back), a row of special
## cases (cane, umbrella, fancy, children, glasses, beard under a hat) and the five
## vendors, x3 on a cobble colour -> tools/style/review/villagers_v2.png. With `-- --poses <png>` it also writes every
## pose of a few looks (walk 4, idle 2, look 2, talk 2, wave 2, wipe 2 in three views) for checking the animation.
##   godot --headless --path game -s res://scenes/market/villager_sheet.gd [-- --poses /tmp/poses.png]

const Villager := preload("res://scenes/market/villager.gd")
const OUT := "res://../tools/style/review/villagers_v2.png"
const BG := Color("b9a697")
const SCALE := 3


func _initialize() -> void:
	var looks: Array = []
	for i in 24:
		looks.append(Villager.look_for(Hash.fnv1a31("villager v2 %d" % i), i % 9 == 4, i % 7 == 3))
	var cell := Vector2i(Villager.W * 3 + 4, Villager.H + 4)
	var cols := 8
	var vendors := ["grocer", "baker", "postman", "vintner", "librarian"]
	var rows := ceili(looks.size() / float(cols)) + 2
	var t0 := Time.get_ticks_usec()
	for l in looks:
		Villager.compose(l, "front", "walk", 0)
	print("compose: %.2f ms per pose" % ((Time.get_ticks_usec() - t0) / 1000.0 / looks.size()))
	var sheet := Image.create(cols * cell.x, rows * cell.y, false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	for i in looks.size():
		var at := Vector2i((i % cols) * cell.x + 2, floori(i / float(cols)) * cell.y + 2)
		_put(sheet, looks[i], at)
	# the special cases: an elder with a cane, umbrellas on a rainy day, fancy buyers, a boy and a girl
	var special := [_find(func(l: Dictionary) -> bool: return l.arch == "elder" and l.cane, false, false),
		_find(func(l: Dictionary) -> bool: return l.umbrella and l.arch != "child", false, true),
		_find(func(l: Dictionary) -> bool: return l.arch == "man", true, false),
		_find(func(l: Dictionary) -> bool: return l.arch == "woman", true, false),
		_find(func(l: Dictionary) -> bool: return l.arch == "child" and not l.fem and l.carry == "basket", false, false),
		_find(func(l: Dictionary) -> bool: return l.arch == "child" and l.fem, false, true),
		_find(func(l: Dictionary) -> bool: return l.arch == "elder" and l.fem and l.glasses, false, false),
		_find(func(l: Dictionary) -> bool: return l.beard and l.hat != "none", false, false)]
	for i in special.size():
		_put(sheet, special[i], Vector2i(i * cell.x + 2, (rows - 2) * cell.y + 2))
	for i in vendors.size():
		var at := Vector2i(i * cell.x + 2, (rows - 1) * cell.y + 2)
		var l := Villager.vendor_look(vendors[i])
		var imgs := [Villager.compose(l, "front", "idle", 0), Villager.compose(l, "front", "wave", 0), Villager.compose(l, "front", "wipe", 0)]
		for k in imgs.size():
			sheet.blend_rect(imgs[k], Rect2i(0, 0, Villager.W, Villager.H), at + Vector2i(k * Villager.W, 0))
	sheet.resize(sheet.get_width() * SCALE, sheet.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	var path := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	sheet.save_png(path)
	print("saved ", path.simplify_path())
	var args := OS.get_cmdline_user_args()
	var p := args.find("--poses")
	if p >= 0 and p + 1 < args.size():
		var pick := [looks[0], looks[2], looks[5], looks[11], Villager.vendor_look("baker"), Villager.vendor_look("librarian")]
		var only := args.find("--only")
		if only >= 0 and only + 1 < args.size():
			var chosen: Array = []
			for s in args[only + 1].split(","):
				chosen.append(looks[int(s)] if not s.begins_with("v") else Villager.vendor_look(s.substr(1)))
			pick = chosen
		_poses(pick, args[p + 1], 4 if only >= 0 else 2)
	quit()


## The first look (seeds "special 0", "special 1", ...) that passes `ok`.
func _find(ok: Callable, fancy: bool, rainy: bool) -> Dictionary:
	for i in 2000:
		var l := Villager.look_for(Hash.fnv1a31("special %d" % i), fancy, rainy)
		if ok.call(l):
			return l
	return Villager.look_for(1)


func _put(sheet: Image, l: Dictionary, at: Vector2i) -> void:
	var views := ["front", "side", "back"]
	for k in 3:
		var img := Villager.compose(l, views[k], "idle", 0)
		sheet.blend_rect(img, Rect2i(0, 0, Villager.W, Villager.H), at + Vector2i(k * Villager.W, 0))


func _poses(looks: Array, out: String, zoom: int) -> void:
	var seq := [["walk", 0], ["walk", 1], ["walk", 2], ["walk", 3], ["idle", 0], ["idle", 1], ["look", 0], ["look", 1],
		["talk", 0], ["talk", 1], ["wave", 0], ["wave", 1], ["wipe", 0], ["wipe", 1]]
	var views := ["front", "side", "back"]
	var img := Image.create(seq.size() * (Villager.W + 2), looks.size() * views.size() * (Villager.H + 2), false, Image.FORMAT_RGBA8)
	img.fill(BG)
	var y := 0
	for l in looks:
		for v in views:
			for i in seq.size():
				var f := Villager.compose(l, v, String(seq[i][0]), int(seq[i][1]))
				img.blend_rect(f, Rect2i(0, 0, Villager.W, Villager.H), Vector2i(i * (Villager.W + 2), y))
			y += Villager.H + 2
	img.resize(img.get_width() * zoom, img.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	print("saved ", out)
