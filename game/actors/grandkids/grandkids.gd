class_name Grandkids
extends Node2D
## FESTIVAL · Mia and Leo visit the garden on festival day (the garden calls Grandkids.attach(self) on a festival save).
## They run about the lawn, play tag, chase the hens, birds and the cat, kick up the fallen leaves, wave when Granny
## comes near and say a line (again when tapped). Paths are BFS over the garden's open lawn; the children never
## block Granny. Cosmetic only: no state, nothing saved; the visual randomness has its own RandomNumberGenerator.

const FX := "res://scenes/wild/wild_fx.gd"  ## loaded when used: it reaches the Audio autoload
const Layout := preload("res://scenes/garden/garden_layout.gd")
const KIDS := ["mia", "leo"]
const STARTS := [Vector2i(16, 7), Vector2i(12, 8)]  ## by the door and the first bed: they ran out to meet her
const NEAR := 3  ## cells (Chebyshev): Granny is near
const WAVE_COOLDOWN := 9.0
const TALK_GAP := 2.4  ## seconds between the two children's lines
const LINES := 3
const LEAF_EVERY := 3  ## steps on the leaves between two little leaf bursts
const HEN_NEAR_PX := 30.0  ## a child this close to a hen (across the run's fence): the hens scatter
const HEN_COOLDOWN := 4.0

var garden: Node2D
var kids: Array[Grandkid] = []
var _rng := RandomNumberGenerator.new()
var _think := {}  ## kid -> seconds until the next idea
var _cool := {}  ## kid -> seconds until the next wave
var _near := {}  ## kid -> Granny was near last frame
var _steps := {}
var _last_line := {}
var _hen_cool := 0.0
var _greeted := {}  ## kid -> has waved at Granny once (the first wave comes as soon as nothing covers the garden)


## Adds the two children to the garden's y-sorted objects. Returns the layer (null without a garden).
static func attach(p_garden: Node2D) -> Grandkids:
	var objects: Node2D = p_garden.get("objects")
	if objects == null:
		return null
	var g := Grandkids.new()
	g.name = "Grandkids"
	g.garden = p_garden
	objects.add_child(g)
	return g


func _ready() -> void:
	var gs := get_node_or_null("/root/GameState")
	var d: Dictionary = gs.data if gs != null else {}
	_rng.seed = hash([int(d.get("save_seed", 1)), int(d.get("day", 1)), "grandkids"])
	var parent := get_parent()
	for i in KIDS.size():
		var k := Grandkid.new()
		parent.add_child.call_deferred(k)
		k.setup(KIDS[i], _free_near(STARTS[i]), _rng.randi())
		kids.append(k)
		_think[k] = 0.6 + i * 0.9
		_cool[k] = 0.0
		_near[k] = false
		_greeted[k] = false
		_steps[k] = 0
		_last_line[k] = 0


func _exit_tree() -> void:
	for k in kids:
		if is_instance_valid(k):
			k.queue_free()


func _process(delta: float) -> void:
	var granny: Node2D = garden.get("granny") if garden != null else null
	_hen_cool = maxf(_hen_cool - delta, 0.0)
	for k in kids:
		if not is_instance_valid(k) or not k.is_inside_tree():
			continue
		_cool[k] = maxf(float(_cool[k]) - delta, 0.0)
		var near := granny != null and _chebyshev(k.cell, _cell_of(granny.position - Vector2(0, 1))) <= NEAR
		if near and (not bool(_near[k]) or not bool(_greeted[k])) and float(_cool[k]) <= 0.0 and not _covered():
			_greet(k)
		_near[k] = near
		if k.is_running() or k.is_waving():
			continue
		_think[k] = float(_think[k]) - delta
		if float(_think[k]) <= 0.0:
			_idea(k)


## A tap on a child: a hop and a line (before the garden turns the tap into a walk).
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch and event.pressed) or garden == null:
		return
	if bool(garden.get("_leaving")) or garden.get("menu") != null:
		return
	var p: Vector2 = get_canvas_transform().affine_inverse() * event.position
	for k in kids:
		if is_instance_valid(k) and k.hit_rect().has_point(p):
			get_viewport().set_input_as_handled()
			k.stop()
			k.hop()
			_say(k)
			var other := _other(k)
			if other != null:
				_cool[other] = maxf(float(_cool[other]), TALK_GAP)
			return


## A festival card (or the garden's menu or letters) is over the garden: no waving into it.
func _covered() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and TodoRules.is_festival(gs.data) and not bool(TodoRules.festival(gs.data).get("started", false)):
		return true  # the start card is about to show
	var f := get_tree().get_first_node_in_group("festival")
	var card: Variant = f.get("_card") if f != null else null
	if card is Node and is_instance_valid(card):
		return true
	return garden.get("menu") != null


func _greet(k: Grandkid) -> void:
	_greeted[k] = true
	_cool[k] = WAVE_COOLDOWN
	var other := _other(k)
	if other != null:
		_cool[other] = maxf(float(_cool[other]), TALK_GAP)  # one line at a time: the other child speaks next
	k.wave()
	_say(k)
	_think[k] = 1.8


func _say(k: Grandkid) -> void:
	var n := _rng.randi_range(1, LINES)
	if n == int(_last_line[k]):
		n = n % LINES + 1
	_last_line[k] = n
	var fx: Node = garden.get("fx")
	if fx != null:
		load(FX).bubble(fx, k.top(), _line(k.kid, n), 1.8)


func _line(kid: String, n: int) -> String:
	if kid == "leo":
		match n:
			1:
				return tr("FESTIVAL_LEO_1")
			2:
				return tr("FESTIVAL_LEO_2")
			_:
				return tr("FESTIVAL_LEO_3")
	match n:
		1:
			return tr("FESTIVAL_MIA_1")
		2:
			return tr("FESTIVAL_MIA_2")
		_:
			return tr("FESTIVAL_MIA_3")


## What to do next: run somewhere on the lawn, chase the other child (tag), chase an animal, or look about.
func _idea(k: Grandkid) -> void:
	var roll := _rng.randf()
	var goal := Vector2i(-1, -1)
	if roll < 0.3:
		var other := _other(k)
		if other != null:
			goal = other.cell
	elif roll < 0.5:
		goal = _animal_cell()
	elif roll < 0.85:
		goal = _random_lawn()
	if goal.x < 0:
		_think[k] = _rng.randf_range(0.8, 2.2)
		var granny: Node2D = garden.get("granny")
		if granny != null and _rng.randf() < 0.5:
			k.face_towards(granny.position)
		return
	var path := _path(k.cell, goal)
	if path.size() > 12:
		path = path.slice(0, 12)
	if path.is_empty():
		_think[k] = 0.5
		return
	if not k.arrived.is_connected(_on_arrived.bind(k)):
		k.arrived.connect(_on_arrived.bind(k))
	k.run(path)
	_think[k] = _rng.randf_range(0.3, 1.4)


func _on_arrived(k: Grandkid) -> void:
	_steps[k] = int(_steps[k]) + 1
	_chase_hens(k)
	if garden.has_method("_leaf_pile"):
		garden.call("_leaf_pile", k.cell)  # the garden's leaf piles fly up under a child's feet too
	if Layout.ground(k.cell) == Layout.T_LEAVES:
		var fx: Node = garden.get("fx")
		if fx != null:
			var fxs: GDScript = load(FX)
			if int(_steps[k]) % LEAF_EVERY == 0:
				fxs.leaf_burst(fx, k.position + Vector2(0, -2), 4, Vector2i(5, 1))
			else:
				fxs.kick_leaf(fx, k.position, k.dir())


## A child at the run's fence: the hens flap away from them (GARDEN-LIFE's scatter) with a cluck.
func _chase_hens(k: Grandkid) -> void:
	if _hen_cool > 0.0:
		return
	var hens: Array = _hens()
	for h in hens:
		if k.position.distance_to(h.position) <= HEN_NEAR_PX:
			for h2 in hens:
				if h2.has_method("scatter"):
					h2.scatter(k.position)
			_hen_cool = HEN_COOLDOWN
			var audio := get_node_or_null("/root/Audio")
			if audio != null:
				audio.play_sfx("sfx_hen_cluck")
			k.hop()
			return


func _hens() -> Array:
	var out: Array = []
	var list: Variant = garden.get("hens")
	if list is Array:
		for h in list:
			if is_instance_valid(h):
				out.append(h)
	return out


func _other(k: Grandkid) -> Grandkid:
	for o in kids:
		if o != k and is_instance_valid(o):
			return o
	return null


## The lawn next to a hen (GARDEN-LIFE: the run is fenced), a bird or the cat, (-1, -1) when none is out.
func _animal_cell() -> Vector2i:
	var cands: Array[Node2D] = []
	for h in _hens():
		cands.append(h)
		cands.append(h)  # the hens are the favourite
	var crit: Node = get_parent().get_node_or_null("Critters")
	if crit != null and "critters" in crit:
		for c in crit.critters:
			if is_instance_valid(c) and c.visible:
				cands.append(c)
	var cat: Node2D = garden.get("cat")
	if cat != null:
		cands.append(cat)
	if cands.is_empty():
		return Vector2i(-1, -1)
	var pick: Node2D = cands[_rng.randi_range(0, cands.size() - 1)]
	return _free_near(_cell_of(pick.position - Vector2(0, 1)))


func _random_lawn() -> Vector2i:
	for _i in 20:
		var c := Vector2i(_rng.randi_range(1, Layout.W - 2), _rng.randi_range(Layout.HEDGE_ROWS, Layout.H - 2))
		if _lawn(c):
			return c
	return Vector2i(-1, -1)


## Open lawn a child may stand on: walkable for Granny, no bed, tree or sign there, not an exit.
func _lawn(c: Vector2i) -> bool:
	if not Layout.in_map(c) or Layout.is_gate(c) or Layout.is_road_exit(c) or c.y >= Layout.H - 1:
		return false
	if garden.has_method("_walkable") and not bool(garden.call("_walkable", c)):
		return false
	return not (garden.has_method("spot_blocks") and bool(garden.call("spot_blocks", c)))


## `c` when it is lawn, else the nearest lawn cell around it.
func _free_near(c: Vector2i) -> Vector2i:
	if _lawn(c):
		return c
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := c + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == r and _lawn(q):
					return q
	return c


## Shortest 4-neighbour path over the lawn from `a` to `b` (without `a`), [] when none.
func _path(a: Vector2i, b: Vector2i) -> Array:
	if a == b or not _lawn(b):
		return []
	var prev := {a: a}
	var queue: Array[Vector2i] = [a]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == b:
			break
		for d in dirs:
			var n: Vector2i = c + d
			if not prev.has(n) and _lawn(n):
				prev[n] = c
				queue.append(n)
	if not prev.has(b):
		return []
	var out: Array = []
	var c := b
	while c != a:
		out.push_front(c)
		c = prev[c]
	return out


static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## The cell under a feet position (Granny, a hen, a bird, the cat): one pixel up, so the feet line counts as inside.
static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / Layout.TILE), floori(p.y / Layout.TILE))
