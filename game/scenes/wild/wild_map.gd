class_name WildMapView
extends Node2D
## Draws one WildGen map (GD-WILD): a ground TileMapLayer plus a WildObject per tree, bush, pickup and the exit.
## Shared by the wild scene and the Seed Lab. `objects` is y-sorted so Granny (added by the wild scene) walks
## behind canopies; `fx` sits above for bubbles and particles. Ground tiles come from ART-01's
## forest_tiles.png when it exists, else from flat palette placeholders (one per WildGen.T_*). Stepping stones
## (T_STONE) are water tiles with ART-FOREST's prop_stepping_stone sprite drawn on the Marks layer, under objects.
## Readability (INT-WILD): a decor tree whose canopy would hide a path, clearing or special-place tile is drawn as
## a stump (prop_stump; its tile stays solid, as in the map). Also on the Marks layer: the mushroom_ring sprite in
## the middle of a mushroom-ring special place, and a few mossy rocks on free grass from the map seed
## (scatter_rocks). Those two are ground decoration only and never block, like the stepping stones; wood (trees,
## stumps) always blocks.
## BIOMES: the ground atlas follows map.biome (tileset_for: <biome>_tiles.png/json, rows = WildGen.T_* ids incl.
## T_BANK; the forest atlas when a biome has none). Vines (decor kind "vine") are never cut to stumps.

const TILE := 16
const FOREST_TILES := "res://assets/sprites/tiles/forest_tiles.png"
const FOREST_TILES_JSON := "res://assets/sprites/tiles/forest_tiles.json"
const BIOME_TILES := "res://assets/sprites/tiles/%s_tiles.png"
const BIOME_TILES_JSON := "res://assets/sprites/tiles/%s_tiles.json"
const STEPPING_STONE := "res://assets/sprites/forest/prop_stepping_stone.png"
const MUSHROOM_RING := "res://assets/sprites/forest/mushroom_ring.png"
const MOSSY_ROCK := "res://assets/sprites/forest/prop_mossy_rock.png"
const ROCK_COUNT := [5, 8]  ## mossy rocks per map, inclusive (fewer when there is no room)
const ROCK_MIN_D2 := 16  ## squared tile distance between two rocks
## Granny within this many tiles (straight line): things with something to take show their outline.
const NEAR_TILES := 5
## Tiles a 48x64 decor canopy mostly covers, relative to its trunk tile (measured on the ART-FOREST sprites).
const DECOR_CANOPY := [Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2), Vector2i(-1, -1), Vector2i(0, -1),
	Vector2i(1, -1), Vector2i(0, -3)]
## WildGen clears dx²+dy² <= 6 around a clearing centre (Builder.CLEARING_R2).
const CLEARING_R := 2
const CLEARING_R2 := 6
## Placeholder colours per T_* id (GRASS, LEAVES, DIRT, WATER, PATH, STONE): [base, speckle], art-bible §1.
const FLAT_COLORS := [["747c37", "b1a13d"], ["b66813", "c94d2e"], ["83571e", "50361e"], ["415c5d", "567c7d"],
	["c58845", "9b8039"], ["b4b3a0", "81746a"]]
const C_MARK := Color("e5bd7f")
const C_SPECIAL := Color("c94d2e")

static var _tileset: TileSet
static var _variants: Array = []  ## per T_* id: Array of atlas coords
static var _biome_sets := {}  ## biome -> {"ts": TileSet, "variants": per T_* id Array of atlas coords}

var map: Dictionary = {}
var show_marks := false:  ## Seed Lab: clearings, entrance and the special place outlined
	set(v):
		show_marks = v
		if is_node_ready():
			$Marks.queue_redraw()

var _objects: Array[WildObject] = []
var _blocked := {}
var _steps: Array[Vector2i] = []  ## T_STONE cells that get the stepping-stone sprite
var _step_tex: Texture2D
var _ring_tex: Texture2D
var _rock_tex: Texture2D
var _rocks: Array[Vector2i] = []  ## scatter_rocks(map)
var _near_cell := Vector2i(-1000, -1000)

@onready var ground: TileMapLayer = $Ground
@onready var objects: Node2D = $Objects
@onready var fx: Node2D = $Fx


func _ready() -> void:
	ground.tile_set = tileset()
	_step_tex = _load_tex(STEPPING_STONE)
	_ring_tex = _load_tex(MUSHROOM_RING)
	_rock_tex = _load_tex(MOSSY_ROCK)
	$Marks.draw.connect(_draw_steps)
	$Marks.draw.connect(_draw_ring)
	$Marks.draw.connect(_draw_rocks)
	$Marks.draw.connect(_draw_marks)


static func _load_tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func size_px() -> Vector2i:
	return Vector2i(int(map.get("w", 0)) * TILE, int(map.get("h", 0)) * TILE)


## Rebuilds everything from a full map (WildGen.generate output).
func show_map(m: Dictionary, varieties: Dictionary = {}) -> void:
	map = m
	for o in _objects:
		if is_instance_valid(o):
			o.queue_free()
	_objects.clear()
	_blocked.clear()
	_steps.clear()
	_rocks.clear()
	_near_cell = Vector2i(-1000, -1000)
	ground.clear()
	if m.is_empty():
		$Marks.queue_redraw()
		return
	_rocks = scatter_rocks(m)
	var w := int(m.w)
	var h := int(m.h)
	var biome := String(m.get("biome", "forest"))
	ground.tile_set = tileset_for(biome)
	for y in h:
		for x in w:
			var t := int(m.ground[y * w + x])
			if t == WildGen.T_STONE and _step_tex != null:
				_steps.append(Vector2i(x, y))
				t = WildGen.T_WATER
			ground.set_cell(Vector2i(x, y), 0, atlas_in(biome, t, x, y))
	var open := open_cells(m)
	for d in m.get("decor_trees", []):
		var info: Dictionary = d
		if String(d.get("kind", "")) != "vine" and canopy_covers(Vector2i(int(d.x), int(d.y)), open):
			info = d.duplicate()
			info["cut"] = true  # drawn as a stump: same solid cell, but the path or clearing stays in view
		_add("decor", info, Color.WHITE)
	for t in m.get("fruit_trees", []):
		_add("fruit_tree", t, fruit_color(String(t.get("type", "")), String(t.get("variety", "")), varieties))
	for p in m.get("pickups", []):
		_add(String(p.get("kind", "ground")), p, fruit_color(String(p.get("type", "")), String(p.get("variety", "")), varieties))
	var e: Vector2i = m.get("entrance", Vector2i(floori(w * 0.5), h - 1))
	_add("exit", {"x": e.x, "y": e.y}, Color.WHITE)
	$Marks.queue_redraw()


## Applies Forage.visible_map(): trees get their "shaken" flag, pickups missing from it count as collected.
func apply_visible(vis: Dictionary) -> void:
	if vis.is_empty():
		return
	var shaken := {}
	for t in vis.get("fruit_trees", []):
		shaken[int(t.id)] = bool(t.get("shaken", false))
	var present := {}
	for p in vis.get("pickups", []):
		present[int(p.id)] = true
	for o in _objects:
		if not is_instance_valid(o):
			continue
		if o.kind == "fruit_tree":
			o.set_done(bool(shaken.get(o.id, false)))
		elif o.kind == "bush" or o.kind == "ground" or o.kind == "hive":
			o.set_done(not present.has(o.id))


func blocks(cell: Vector2i) -> bool:
	return _blocked.has(cell)


func find(kind: String, id: int) -> WildObject:
	for o in _objects:
		if is_instance_valid(o) and o.kind == kind and o.id == id:
			return o
	return null


## The usable object on `cell` (trees before things on the ground), or null.
func object_at_cell(cell: Vector2i) -> WildObject:
	var best: WildObject = null
	for o in _objects:
		if is_instance_valid(o) and o.cell == cell and o.usable():
			if best == null or o.blocks():
				best = o
	return best


## The usable object drawn front-most under a world point, or null.
func object_at_point(p: Vector2) -> WildObject:
	var best: WildObject = null
	for o in _objects:
		if is_instance_valid(o) and o.usable() and o.hit_rect().has_point(p):
			if best == null or o.position.y > best.position.y or (o.position.y == best.position.y and not o.blocks()):
				best = o
	return best


func set_highlight(target: WildObject) -> void:
	for o in _objects:
		if is_instance_valid(o):
			o.highlighted = o == target


## Granny's cell: everything within NEAR_TILES gets `near` (outlined while it has something to take).
func set_near(cell: Vector2i) -> void:
	if cell == _near_cell:
		return
	_near_cell = cell
	for o in _objects:
		if is_instance_valid(o):
			var d := o.cell - cell
			o.near = d.x * d.x + d.y * d.y <= NEAR_TILES * NEAR_TILES


## Cells a decor canopy must not hide: path and stepping stones, clearings (WildGen's cleared radius) and the
## special place. Set of Vector2i.
static func open_cells(m: Dictionary) -> Dictionary:
	var open := {}
	if m.is_empty():
		return open
	var w := int(m.w)
	for i in (m.ground as PackedByteArray).size():
		var g := int(m.ground[i])
		if g == WildGen.T_PATH or g == WildGen.T_STONE:
			open[Vector2i(i % w, floori(float(i) / w))] = true
	for c in m.get("clearings", []):
		for dy in range(-CLEARING_R, CLEARING_R + 1):
			for dx in range(-CLEARING_R, CLEARING_R + 1):
				if dx * dx + dy * dy <= CLEARING_R2:
					open[(c as Vector2i) + Vector2i(dx, dy)] = true
	var sp: Dictionary = m.get("special", {})
	if not sp.is_empty():
		_reserve(open, Vector2i(int(sp.x), int(sp.y)), Rect2i(0, 0, int(sp.get("w", 1)), int(sp.get("h", 1))))
	return open


## A decor tree standing on `at` would hide one of the `open` cells under its canopy (DECOR_CANOPY).
static func canopy_covers(at: Vector2i, open: Dictionary) -> bool:
	for off in DECOR_CANOPY:
		if open.has(at + (off as Vector2i)):
			return true
	return false


## Mossy-rock tiles for a map, ROCK_COUNT of them when there is room. Same map -> same rocks (stream "wild:props"
## of the map seed); visual randomness only. They go on grass that nothing uses: off and away from the path,
## clearings, the special place and the entrance, not under a canopy, not next to a bush or a pickup.
static func scatter_rocks(m: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if m.is_empty():
		return out
	var w := int(m.w)
	var h := int(m.h)
	var keep := {}
	for d in m.get("decor_trees", []):
		_reserve(keep, Vector2i(int(d.x), int(d.y)), Rect2i(-1, -3, 3, 4))
	for t in m.get("fruit_trees", []):
		_reserve(keep, Vector2i(int(t.x), int(t.y)), Rect2i(-2, -4, 5, 5))
	for p in m.get("pickups", []):
		_reserve(keep, Vector2i(int(p.x), int(p.y)), Rect2i(-1, -1, 3, 3))
	for c in m.get("clearings", []):
		_reserve(keep, c, Rect2i(-3, -3, 7, 7))
	var sp: Dictionary = m.get("special", {})
	if not sp.is_empty():
		_reserve(keep, Vector2i(int(sp.x), int(sp.y)), Rect2i(-1, -1, int(sp.get("w", 1)) + 2, int(sp.get("h", 1)) + 2))
	var e: Vector2i = m.get("entrance", Vector2i(floori(w * 0.5), h - 1))
	_reserve(keep, e, Rect2i(-4, -4, 9, 5))
	for y in h:
		for x in w:
			var g := int(m.ground[y * w + x])
			if g == WildGen.T_PATH or g == WildGen.T_STONE:
				_reserve(keep, Vector2i(x, y), Rect2i(-1, -1, 3, 3))
	var cands: Array[Vector2i] = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := Vector2i(x, y)
			if not keep.has(c) and int(m.ground[y * w + x]) == WildGen.T_GRASS and WildGen.is_walkable(m, c):
				cands.append(c)
	var r := Seeds.rng(int(m.get("seed", 0)), "wild:props", 0)
	var want := r.randi_range(int(ROCK_COUNT[0]), int(ROCK_COUNT[1]))
	for i in range(cands.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp := cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	for c in cands:
		if out.size() >= want:
			break
		var far := true
		for o in out:
			var d := c - o
			if d.x * d.x + d.y * d.y < ROCK_MIN_D2:
				far = false
				break
		if far:
			out.append(c)
	return out


static func _reserve(keep: Dictionary, at: Vector2i, r: Rect2i) -> void:
	for dy in range(r.position.y, r.end.y):
		for dx in range(r.position.x, r.end.x):
			keep[at + Vector2i(dx, dy)] = true


## Colour for a fruit/pickup: the type's ramp middle tone, moved by the variety's colour shift (§6.2).
static func fruit_color(type: String, variety: String, varieties: Dictionary) -> Color:
	var ramp: Array = Data.ingredients().get(type, {}).get("ramp", [])
	if ramp.size() < 5:
		return Color("c94d2e")
	var shift := int(varieties.get(variety, {}).get("color_shift", 0))
	return Color(String(ramp[clampi(2 + shift, 0, 4)]))


static func tileset() -> TileSet:
	if _tileset != null:
		return _tileset
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src := TileSetAtlasSource.new()
	src.texture_region_size = Vector2i(TILE, TILE)
	_variants.clear()
	var table := _forest_tiles()
	if not table.is_empty():
		src.texture = load(FOREST_TILES)
		for t in FLAT_COLORS.size():
			var cells: Array = []
			for c in table.get(str(t), {}).get("cells", []):
				var ac := Vector2i(int(c[0]), int(c[1]))
				if not src.has_tile(ac):
					src.create_tile(ac)
				cells.append(ac)
			_variants.append(cells)
	else:
		src.texture = ImageTexture.create_from_image(_flat_image())
		for t in FLAT_COLORS.size():
			src.create_tile(Vector2i(t, 0))
			_variants.append([Vector2i(t, 0)])
	ts.add_source(src, 0)
	_tileset = ts
	return ts


## The ground TileSet of a biome: <biome>_tiles.png + .json (rows "0".."5" required, "6" = T_BANK optional), else the
## forest's tileset().
static func tileset_for(biome: String) -> TileSet:
	return _biome_set(biome).ts


## Atlas cell for a T_* id in a biome's tileset: variant by hash(x, y); an id the atlas lacks (T_BANK in the forest
## atlas) falls back to dirt.
static func atlas_in(biome: String, t: int, x: int, y: int) -> Vector2i:
	var variants: Array = _biome_set(biome).variants
	if t < 0 or t >= variants.size() or (variants[t] as Array).is_empty():
		t = WildGen.T_DIRT if t == WildGen.T_BANK else 0
	if t >= variants.size() or (variants[t] as Array).is_empty():
		t = 0
	var cells: Array = variants[t]
	var hsh := ((x * 73856093) ^ (y * 19349663)) & 0x7FFFFFFF
	return cells[hsh % cells.size()]


static func _biome_set(biome: String) -> Dictionary:
	if _biome_sets.has(biome):
		return _biome_sets[biome]
	var out := {}
	var png := BIOME_TILES % biome
	var js := BIOME_TILES_JSON % biome
	if biome != "forest" and ResourceLoader.exists(png) and FileAccess.file_exists(js):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(js))
		var tiles: Dictionary = parsed.get("tiles", {}) if typeof(parsed) == TYPE_DICTIONARY else {}
		var ok := true
		for t in FLAT_COLORS.size():
			ok = ok and tiles.has(str(t))
		if ok:
			var ts := TileSet.new()
			ts.tile_size = Vector2i(TILE, TILE)
			var src := TileSetAtlasSource.new()
			src.texture_region_size = Vector2i(TILE, TILE)
			src.texture = load(png)
			var variants: Array = []
			for t in WildGen.T_BANK + 1:
				var cells: Array = []
				for c in tiles.get(str(t), {}).get("cells", []):
					var ac := Vector2i(int(c[0]), int(c[1]))
					if not src.has_tile(ac):
						src.create_tile(ac)
					cells.append(ac)
				variants.append(cells)
			ts.add_source(src, 0)
			out = {"ts": ts, "variants": variants}
	if out.is_empty():
		out = {"ts": tileset(), "variants": _variants}
	_biome_sets[biome] = out
	return out


static func _atlas_for(t: int, x: int, y: int) -> Vector2i:
	if t < 0 or t >= _variants.size() or _variants[t].is_empty():
		t = 0
	var cells: Array = _variants[t]
	var hsh := ((x * 73856093) ^ (y * 19349663)) & 0x7FFFFFFF
	return cells[hsh % cells.size()]


static func _forest_tiles() -> Dictionary:
	if not ResourceLoader.exists(FOREST_TILES) or not FileAccess.file_exists(FOREST_TILES_JSON):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FOREST_TILES_JSON))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("tiles"):
		return {}
	for t in FLAT_COLORS.size():
		if not parsed.tiles.has(str(t)):
			return {}
	return parsed.tiles


static func _flat_image() -> Image:
	var img := Image.create(TILE * FLAT_COLORS.size(), TILE, false, Image.FORMAT_RGBA8)
	for t in FLAT_COLORS.size():
		var base := Color(FLAT_COLORS[t][0])
		var dot := Color(FLAT_COLORS[t][1])
		img.fill_rect(Rect2i(t * TILE, 0, TILE, TILE), base)
		for y in TILE:
			for x in TILE:
				if (x * 7 + y * 13 + t * 5) % 17 == 0:
					img.set_pixel(t * TILE + x, y, dot)
		if t == WildGen.T_STONE:  # a stepping stone sitting in water
			img.fill_rect(Rect2i(t * TILE, 0, TILE, TILE), Color(FLAT_COLORS[WildGen.T_WATER][0]))
			img.fill_rect(Rect2i(t * TILE + 3, 4, 10, 8), base)
			img.fill_rect(Rect2i(t * TILE + 4, 3, 8, 10), base)
			img.fill_rect(Rect2i(t * TILE + 4, 11, 8, 1), dot)
	return img


func _add(kind: String, info: Dictionary, color: Color) -> void:
	var o := WildObject.new()
	o.setup(kind, info, color)
	objects.add_child(o)
	_objects.append(o)
	if o.blocks():
		_blocked[o.cell] = true


func _draw_steps() -> void:
	for c in _steps:
		$Marks.draw_texture(_step_tex, Vector2(c * TILE))


## The ring sprite centred on the middle tile of a mushroom-ring special place, inside the ring of mushrooms.
func _draw_ring() -> void:
	var sp: Dictionary = map.get("special", {})
	if _ring_tex == null or String(sp.get("kind", "")) != "mushroom_ring":
		return
	var mid := Vector2i(int(sp.x) + floori(int(sp.get("w", 1)) * 0.5), int(sp.y) + floori(int(sp.get("h", 1)) * 0.5))
	var at := Vector2(mid * TILE) + Vector2(TILE * 0.5, TILE * 0.5) - (_ring_tex.get_size() * 0.5).floor()
	$Marks.draw_texture(_ring_tex, at)


## Each rock sits bottom-centred on its tile.
func _draw_rocks() -> void:
	if _rock_tex == null:
		return
	var off := Vector2(TILE * 0.5 - floorf(_rock_tex.get_width() * 0.5), TILE - _rock_tex.get_height())
	for c in _rocks:
		$Marks.draw_texture(_rock_tex, Vector2(c * TILE) + off)


func _draw_marks() -> void:
	if not show_marks or map.is_empty():
		return
	var m: CanvasItem = $Marks
	for c in map.get("clearings", []):
		var cv: Vector2i = c
		_frame(m, Rect2(cv.x * TILE - TILE, cv.y * TILE - TILE, TILE * 3, TILE * 3), C_MARK)
	var sp: Dictionary = map.get("special", {})
	if not sp.is_empty():
		_frame(m, Rect2(int(sp.x) * TILE, int(sp.y) * TILE, int(sp.get("w", 1)) * TILE, int(sp.get("h", 1)) * TILE), C_SPECIAL)


static func _frame(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), c)
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), c)
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), c)
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), c)
