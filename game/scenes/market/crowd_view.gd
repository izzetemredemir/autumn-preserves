extends Node
## MARKET-LIVE · Plays a MarketCrowd back: one villager v2 per person, created when they enter and freed when they
## leave, placed and posed for parade time t (walk cycle at their own cadence, browsing with their back to the stall,
## looking around, turning to say their line, chatting in pairs, a kid waving at the pigeons). Rules stay in
## MarketCrowd; this only reads the steps.

const Villager := preload("res://scenes/market/villager.gd")
const TALK := 1.3

var world: Node2D
var rainy := false
var _people: Array = []
var _by_id := {}
var _nodes := {}


func setup(w: Node2D, crowd: Dictionary, is_rainy: bool) -> void:
	world = w
	rainy = is_rainy
	_people = crowd.get("people", [])
	for p in _people:
		_by_id[int(p.id)] = p


func clear() -> void:
	for id in _nodes:
		(_nodes[id] as Node2D).queue_free()
	_nodes.clear()


func step(t: float) -> void:
	for p in _people:
		var id := int(p.id)
		var on := t >= float(p.spawn) and t <= float(p.end)
		if not on:
			if _nodes.has(id):
				(_nodes[id] as Node2D).queue_free()
				_nodes.erase(id)
			continue
		var node := _node(p)
		var st := _step_at(p, t)
		if st.is_empty():
			continue
		var at: Vector2
		var k := 0.0
		if String(st.do) == "walk":
			var span := maxf(0.001, float(st.t1) - float(st.t0))
			k = clampf((t - float(st.t0)) / span, 0.0, 1.0)
			at = (st.from as Vector2).lerp(st.to, k)
		else:
			at = st.from
		node.position = (at + (p.offset as Vector2)).round()
		_pose(node, p, st, t)


## Feet positions of everyone on screen (the pigeons watch these).
func positions() -> Array:
	var out: Array = []
	for id in _nodes:
		out.append((_nodes[id] as Node2D).position)
	return out


func node_of(id: int) -> Node2D:
	return _nodes.get(id)


## Head-top point of a person (bubbles), Vector2.INF when not on screen.
func head(id: int) -> Vector2:
	var n: Node2D = _nodes.get(id)
	if n == null or not is_instance_valid(n):
		return Vector2.INF
	return n.position - Vector2(0, (n as Object).call("head_height"))


func visible_count() -> int:
	return _nodes.size()


## The person whose body is under a screen point (clicks), {} when none.
func person_at(p: Vector2) -> Dictionary:
	var best := {}
	var best_y := -1.0
	for id in _nodes:
		var n: Node2D = _nodes[id]
		var h := float(n.call("head_height"))
		if absf(p.x - n.position.x) <= 8.0 and p.y <= n.position.y and p.y >= n.position.y - h and n.position.y > best_y:
			best = _by_id[id]
			best_y = n.position.y
	return best


func _node(p: Dictionary) -> Node2D:
	var id := int(p.id)
	if _nodes.has(id):
		return _nodes[id]
	var v := Villager.new()
	v.name = "P%d" % id
	v.setup(Villager.look_for(int(p.look), bool(p.fancy), rainy, String(p.arch)))
	world.add_child(v)
	_nodes[id] = v
	return v


func _step_at(p: Dictionary, t: float) -> Dictionary:
	var steps: Array = p.steps
	for s in steps:
		if t < float(s.t1):
			return s
	return steps.back() if not steps.is_empty() else {}


func _pose(node: Node2D, p: Dictionary, st: Dictionary, t: float) -> void:
	var id := int(p.id)
	var what := String(st.do)
	var face := String(st.face)
	var blink := fmod(t + id * 0.71, 3.4) < 0.13
	var line_t := float(p.line_t)
	var talking := line_t >= 0.0 and t >= line_t and t < line_t + TALK and what != "walk"
	match what:
		"walk":
			node.call("show_pose", face, "walk", floori((t - float(p.spawn)) * float(p.cadence) + id) % 4)
		"look":
			node.call("show_pose", "front", "look", floori((t - float(st.t0)) / 0.55) % 2)
		"chat":
			var partner := int(p.partner) >= 0 and int(p.partner) < id
			var mid := (float(st.t0) + float(st.t1)) / 2.0
			var mine := (t < mid) != partner
			node.call("show_pose", "left" if partner else "right", "talk" if mine else "idle", floori(t * 5.0) % 2 if mine else 0, blink)
		"play":
			node.call("show_pose", "front", "talk", floori(t * 4.0) % 2)
		_:
			if talking:
				node.call("show_pose", "front", "talk", floori(t * 5.0) % 2)
			else:
				var turned := line_t >= 0.0 and t >= line_t + TALK and what == "buy"
				node.call("show_pose", "front" if turned else face, "idle", floori(t * 1.3 + id) % 2, blink)
