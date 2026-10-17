extends RefCounted
## GARDEN-LIFE · The garden's props (Walter's truck, the hen house and its run, the hives, the clothesline, the
## scarecrow, the bench) from assets/sprites/garden/garden_props.json (ART-GARDEN2). Pure data and lookups, no
## autoloads, like garden_layout.gd. Without the file the garden simply has no props.
## Cells are [col, row] on the 30x17 garden map; pixels are garden pixels (16 px cells).
##   prop: {"id", "sheet" (res path), "frame" (Vector2i), "frames", "cell" (bottom-left cell the sprite stands on),
##          "offset" (sprite top-left from that cell's top-left, px), "blocked", "interact" (Array[Vector2i]), "z"}
##   "hen_run": Rect2i of cells (blocked for Granny, the hens' yard), "truck_bed"/"chimney": Vector2i px,
##   "perches": {prop id: Array[Vector2i] feet px}, "cat_spots": [{"id" (CatRules spot id), "cell", "px" (cat feet)}].

const Layout := preload("res://scenes/garden/garden_layout.gd")
const PATH := "res://assets/sprites/garden/garden_props.json"
const SPRITES := "res://assets/sprites/garden/"
const TILE := 16
## The hens' things (using any of them says a hen line): the hen house and the halves of its run ("run_back", ...).
const HEN_HOUSE := "coop"

static var _cache := {}


## The garden's props from the art's json (none when it is missing or unreadable). Parsed once.
static func data() -> Dictionary:
	if _cache.is_empty():
		var raw: Variant = null
		if FileAccess.file_exists(PATH):
			raw = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cache = parse(raw if typeof(raw) == TYPE_DICTIONARY else {})
	return _cache


## Contract json -> typed lookups (JSON numbers are floats).
static func parse(raw: Dictionary) -> Dictionary:
	var props: Array = []
	for p: Dictionary in raw.get("props", []):
		props.append({
			"id": String(p.get("id", "")),
			"sheet": SPRITES + String(p.get("sheet", "")) if String(p.get("sheet", "")) != "" else "",
			"frame": Vector2i(int(p.get("frame_w", TILE)), int(p.get("frame_h", TILE))),
			"frames": maxi(1, int(p.get("frames", 1))),
			"cell": _v(p.get("cell", [0, 0])),
			"offset": _v(p.get("offset", [0, 0])),
			"blocked": _cells(p.get("blocked", [])),
			"interact": _cells(p.get("interact", [])),
			"z": String(p.get("z", "y")),
		})
	var run: Array = raw.get("hen_run", [])
	var perches := {}
	var raw_perches: Variant = raw.get("perches", {})
	if typeof(raw_perches) == TYPE_DICTIONARY:
		for k in raw_perches:
			perches[String(k)] = _cells(raw_perches[k])
	var spots: Array = []
	var cells := _cells(raw.get("cat_spots", []))
	var ids: Array = raw.get("cat_spot_ids", [])
	var px := _cells(raw.get("cat_spot_px", []))
	for i in cells.size():
		if i < ids.size() and i < px.size():
			spots.append({"id": String(ids[i]), "cell": cells[i], "px": px[i]})
	return {
		"props": props,
		"hen_run": Rect2i(int(run[0]), int(run[1]), int(run[2]), int(run[3])) if run.size() >= 4 else Rect2i(),
		"truck_bed": _v(raw.get("truck_bed", [-1, -1])),
		"chimney": _v(raw.get("chimney", [-1, -1])),
		"perches": perches,
		"cat_spots": spots,
	}


static func prop(d: Dictionary, id: String) -> Dictionary:
	for p: Dictionary in d.props:
		if p.id == id:
			return p
	return {}


## A cat spot of the json by its CatRules id ({"id", "cell", "px"}), or {}.
static func cat_spot(d: Dictionary, spot_id: String) -> Dictionary:
	for s: Dictionary in d.cat_spots:
		if s.id == spot_id:
			return s
	return {}


## Every cell Granny can't walk on because of a prop: cell -> prop id (the hen run's own cells -> "coop").
static func blocked(d: Dictionary) -> Dictionary:
	var out := {}
	var run: Rect2i = d.hen_run
	for y in range(run.position.y, run.end.y):
		for x in range(run.position.x, run.end.x):
			out[Vector2i(x, y)] = HEN_HOUSE
	for p: Dictionary in d.props:
		for c: Vector2i in p.blocked:
			out[c] = p.id
	return out


## Group of a prop id: the hens' things are one ("coop": the hen house and the run's halves), any other is its own.
static func group(id: String) -> String:
	return HEN_HOUSE if id == HEN_HOUSE or id.begins_with("run") else id


## The sprite's rectangle in garden pixels.
static func sprite_rect(p: Dictionary) -> Rect2i:
	var c: Vector2i = p.cell
	return Rect2i(c * TILE + Vector2i(p.offset), p.frame)


## Garden y of the prop's feet (the bottom of its lowest blocked row, else of its cell): its y-sort key.
static func feet_y(p: Dictionary) -> int:
	var row: int = p.cell.y
	for c: Vector2i in p.blocked:
		row = maxi(row, c.y)
	return (row + 1) * TILE


## The hen run in garden pixels.
static func run_px(d: Dictionary) -> Rect2i:
	var r: Rect2i = d.hen_run
	return Rect2i(r.position * TILE, r.size * TILE)


## Cells the garden's own things use or need clear (cottage, door, mailbox, compost, tree slots, all six beds, gate,
## signs, the path and road, the spawn cells): no prop may stand on them.
static func fixed_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(Layout.HOUSE.position.y, Layout.HOUSE.end.y):
		for x in range(Layout.HOUSE.position.x, Layout.HOUSE.end.x):
			out.append(Vector2i(x, y))
	for c: Vector2i in fixed_blocked() + Layout.GATE + Layout.ROAD_EXIT + Layout.DOOR:
		out.append(c)
	for k in Layout.SPAWN:
		out.append(Layout.SPAWN[k][0])
	for y in Layout.H:
		for x in Layout.W:
			if Layout.ground(Vector2i(x, y)) == Layout.T_PATH:
				out.append(Vector2i(x, y))
	return out


## Cells the garden's own things block (what GardenSpot.blocks() says), for walkability without a scene.
static func fixed_blocked() -> Array[Vector2i]:
	var out: Array[Vector2i] = [Layout.MAILBOX, Layout.COMPOST, Layout.GATE_SIGN, Layout.TOWN_SIGN]
	for c: Vector2i in Layout.TREE_SLOTS:
		out.append(c)
	for i in Layout.BEDS.size():
		for c: Vector2i in Layout.bed_cells(i):
			out.append(c)
	return out


## Cells reachable from `from` over `open(cell) -> bool` (4 neighbours, inside the map): cell -> true.
static func reach(from: Vector2i, open: Callable) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n := c + dir
			if Layout.in_map(n) and not seen.has(n) and bool(open.call(n)):
				seen[n] = true
				queue.append(n)
	return seen


static func _v(a: Variant) -> Vector2i:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i(-1, -1)


static func _cells(a: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if typeof(a) == TYPE_ARRAY:
		for c: Variant in a:
			out.append(_v(c))
	return out
