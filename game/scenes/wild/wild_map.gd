class_name WildMapView
extends Node2D
## Draws one WildGen map (GD-WILD): a ground TileMapLayer plus a WildObject per tree, bush, pickup and the exit.
## Shared by the wild scene and the Seed Lab. `objects` is y-sorted so Granny (added by the wild scene) walks
## behind canopies; `fx` sits above for bubbles and particles. Ground tiles come from ART-01's
## forest_tiles.png when it exists, else from flat palette placeholders (one per WildGen.T_*).

const TILE := 16
const FOREST_TILES := "res://assets/sprites/tiles/forest_tiles.png"
const FOREST_TILES_JSON := "res://assets/sprites/tiles/forest_tiles.json"
## Placeholder colours per T_* id (GRASS, LEAVES, DIRT, WATER, PATH, STONE): [base, speckle], art-bible §1.
const FLAT_COLORS := [["747c37", "b1a13d"], ["b66813", "c94d2e"], ["83571e", "50361e"], ["415c5d", "567c7d"],
	["c58845", "9b8039"], ["b4b3a0", "81746a"]]
const C_MARK := Color("e5bd7f")
const C_SPECIAL := Color("c94d2e")

static var _tileset: TileSet
static var _variants: Array = []  ## per T_* id: Array of atlas coords

var map: Dictionary = {}
var show_marks := false:  ## Seed Lab: clearings, entrance and the special place outlined
	set(v):
		show_marks = v
		if is_node_ready():
			$Marks.queue_redraw()

var _objects: Array[WildObject] = []
var _blocked := {}

@onready var ground: TileMapLayer = $Ground
@onready var objects: Node2D = $Objects
@onready var fx: Node2D = $Fx


func _ready() -> void:
	ground.tile_set = tileset()
	$Marks.draw.connect(_draw_marks)


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
	ground.clear()
	if m.is_empty():
		return
	var w := int(m.w)
	var h := int(m.h)
	for y in h:
		for x in w:
			ground.set_cell(Vector2i(x, y), 0, _atlas_for(int(m.ground[y * w + x]), x, y))
	for d in m.get("decor_trees", []):
		_add("decor", d, Color.WHITE)
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
		elif o.kind == "bush" or o.kind == "ground":
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
