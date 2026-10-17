extends Control
## LIVING-TOWN · The town square behind the shop panels (cosmetic; rules in TownCrowd, seeded per day): Barnaby at his
## stall, Rosie at her door, Pip by the post box, Vito and Edith strolling between them, villagers reading the notice
## board, stopping by the neighbours, chatting in pairs, kids playing by the pigeons; the dog, sparrows and falling
## leaves (TownLife). Rain thins the crowd and opens umbrellas. Bubbles stay between the tab row and the panel.
## On a market day, while the "Market today!" banner is up, everyone is at the market: only the birds, the dog and the
## leaves are out. The town puts this layer right above its background, so every panel and button stays on top; a
## click on a neighbour emits neighbour_clicked (the town opens their page), a click on a villager gets a hello.

signal neighbour_clicked(id: String)

const Villager := preload("res://scenes/market/villager.gd")
const ML := preload("res://scenes/market/market_layout.gd")
const Bubbles := preload("res://scenes/market/market_bubbles.gd")
const Life := preload("res://scenes/town/town_life.gd")
const View := preload("res://scenes/town/town_view.gd")
const FILE := "res://assets/sprites/town/town_layout.json"
const RAIN := "res://ui/hud/rain.tscn"
const HELLOS := 3
const TALK := 1.3
const BLOCKED: Array[Rect2] = [Rect2(0, 0, 480, 60), Rect2(0, 144, 480, 126)]
## Bubbles stay in the picture band (y 58..PANEL_Y-2) and off the To-Do note (x >= 326, down to y 60) and the signpost.
const KEEP_CLEAR: Array[Rect2] = [Rect2(326, 0, 154, 62), Rect2(4, 118, 78, 28)]

var layout: Dictionary = {}
var crowd: Dictionary = {}
var rainy := false
var _world: Node2D
var _life: Node2D
var _view: Node
var _bubbles: Control
var _stands: Dictionary = {}  # neighbour id -> Villager (Barnaby, Rosie, Pip)
var _talk: Dictionary = {}  # "n<id>" -> scene time the neighbour talks until
var _wave: Dictionary = {}  # neighbour id -> scene time the neighbour waves until
var _t := 0.0


static func load_layout() -> Dictionary:
	if FileAccess.file_exists(FILE):
		var f := FileAccess.open(FILE, FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
		if d is Dictionary and (d as Dictionary).has("walk"):
			return d
	return {}


func _ready() -> void:
	name = "Square"
	mouse_filter = Control.MOUSE_FILTER_PASS
	size = Vector2(480, 270)
	layout = load_layout()
	var d: Dictionary = GameState.data
	rainy = String(d.get("weather", "sunny")) == "rainy"
	var save_seed := int(d.get("save_seed", 1))
	var day := int(d.get("day", 1))
	_world = Node2D.new()
	_world.name = "World"
	_world.y_sort_enabled = true
	add_child(_world)
	_life = Life.new()
	_life.name = "Life"
	add_child(_life)
	_view = View.new()
	_view.name = "Crowd"
	add_child(_view)
	_bubbles = Bubbles.new()
	_bubbles.name = "Bubbles"
	add_child(_bubbles)
	var blocked: Array[Rect2] = []
	for b in layout.get("bubble_blocked", []):
		blocked.append(Rect2(ML.rect(b)))
	if blocked.is_empty():
		blocked.assign(BLOCKED)
	blocked.append_array(KEEP_CLEAR)  # TOWN-NAV: the To-Do note's zone and the garden signpost
	_bubbles.set("blocked", blocked)
	if not layout.is_empty():
		_life.call("setup", _world, layout, Seeds.seed_for(save_seed, "town", day, "life"))
		if not Market.can_open(d):
			crowd = TownCrowd.build(save_seed, day, layout, rainy)
			_view.call("setup", _world, crowd, rainy)
			for n in crowd.neighbours:
				_add_stand(String(n.id), n.at)
	if rainy and ResourceLoader.exists(RAIN):
		add_child((load(RAIN) as PackedScene).instantiate())
	_step(0.0)


func _process(delta: float) -> void:
	_step(delta)


func _step(dt: float) -> void:
	var before := _t
	_t += dt
	if not crowd.is_empty():
		_view.call("step", _t)
		if dt > 0.0:
			_say_lines(before, _t)
		_step_stands()
	if _life.get("world") != null:
		_life.call("step", dt, _view.call("positions"))
	_bubbles.call("step", dt)


## Villagers and neighbours out now (smoke tests).
func out_count() -> int:
	return int(_view.call("visible_count")) + _stands.size()


func bubbles() -> Array:
	return _bubbles.call("shown")


# --- the neighbours who stand --------------------------------------------------------------------------------------

func _add_stand(id: String, at: Vector2) -> void:
	var l := Villager.vendor_look(id)
	l.umbrella = rainy and id == "postman"  # Barnaby has his awning, Rosie her doorway
	var v := Villager.new()
	v.name = "Stand_" + id
	v.setup(l)
	v.position = at.round()
	_world.add_child(v)
	_stands[id] = v


func _step_stands() -> void:
	var m := fposmod(_t, TownCrowd.LOOP)
	var i := 0
	for n in crowd.neighbours:
		var id := String(n.id)
		var v: Node2D = _stands.get(id)
		if v == null:
			continue
		var what := "idle"
		var t0 := 0.0
		for a in n.acts:
			if m >= float(a.t0) and m < float(a.t1):
				what = String(a.do)
				t0 = float(a.t0)
				break
		if float(_wave.get(id, -1.0)) > _t:
			what = "wave"
			t0 = float(_wave[id]) - 1.4
		if float(_talk.get("n" + id, -1.0)) > _t and what != "wave":
			what = "talk"
		var blink := fmod(_t + i * 0.9, 3.7) < 0.13
		match what:
			"wave":
				v.call("show_pose", "front", "wave", floori((m - t0) * 4.0) % 2)
			"wipe":
				v.call("show_pose", "front", "wipe", floori(_t * 3.0) % 2)
			"arrange":
				v.call("show_pose", "front", "look", floori(_t / 0.7) % 2)
			"talk":
				v.call("show_pose", "front", "talk", floori(_t * 5.0) % 2)
			_:
				v.call("show_pose", "front", "idle", floori(_t * 1.2 + i) % 2, blink)
		i += 1


func _stand_head(id: String) -> Vector2:
	var v: Node2D = _stands.get(id)
	if v == null or not is_instance_valid(v):
		return Vector2.INF
	return v.position - Vector2(0, int(v.call("head_height")))


func _stand_at(p: Vector2) -> String:
	for id: String in _stands:
		var v: Node2D = _stands[id]
		var h := float(v.call("head_height"))
		if absf(p.x - v.position.x) <= 8.0 and p.y <= v.position.y and p.y >= v.position.y - h:
			return id
	return ""


# --- lines and clicks ----------------------------------------------------------------------------------------------

## Says every line whose loop time falls in (t0, t1].
func _say_lines(t0: float, t1: float) -> void:
	var a := fposmod(t0, TownCrowd.LOOP)
	var b := fposmod(t1, TownCrowd.LOOP)
	for l in crowd.lines:
		var lt := float(l.t)
		var hit := (lt > a and lt <= b) if b >= a else (lt > a or lt <= b)
		if hit:
			_say(String(l.who), String(l.key), int(l.prio), float(l.dur))


func _say(who: String, key: String, prio: int, dur: float) -> void:
	var head: Callable
	if who.begins_with("n"):
		head = _stand_head.bind(who.substr(1))
		_talk[who] = _t + TALK
	else:
		var id := int(who.substr(1))
		head = Callable(_view, "head").bind(id)
		(_view.get("talk") as Dictionary)[id] = _t + TALK
	_bubbles.call("say", who, key, head, prio, dur)


## A click on a neighbour: Barnaby, Rosie or Pip waves back, and the town opens their page.
func poke(id: String) -> void:
	if _stands.has(id):
		_wave[id] = _t + 1.4
	neighbour_clicked.emit(id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var over := not crowd.is_empty() and (_stand_at(event.position) != "" or not (_view.call("person_at", event.position) as Dictionary).is_empty())
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over else Control.CURSOR_ARROW
		return
	if not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or crowd.is_empty():
		return
	var at: Vector2 = (event as InputEventMouseButton).position
	var id := _stand_at(at)
	if id != "":
		poke(id)
		accept_event()
		return
	var p: Dictionary = _view.call("person_at", at)
	if p.is_empty():
		return
	accept_event()
	if String(p.get("npc", "")) != "":
		neighbour_clicked.emit(String(p.npc))
		return
	_say("p%d" % int(p.id), "TOWN_CHAT_HELLO_%d" % (1 + int(p.id) % HELLOS), 4, 1.6)
