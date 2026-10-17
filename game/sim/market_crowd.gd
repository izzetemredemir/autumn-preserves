class_name MarketCrowd
extends RefCounted
## MARKET-LIVE · Who walks through the market and when (spec §7.7). Pure: no autoloads, no scenes. Seeded from
## Seeds.rng(save_seed, "market", day, "crowd"), so the same market day always plays the same crowd.
## Input: the visits of Market.plan (buyers and non-buyers, in order) and a market layout (market_layout.json: walk graph,
## entries, vendor stand/front points, Granny's stall and counter, pigeon zones). Output: every person's route over the
## walk graph as timed steps (walk from node to node, or stop: browse, buy, look, chat, play), the vendors' idle acts
## and call-outs, and the bubble lines. The scene only plays this back (position and pose at time t).
##
## build() -> {"people": [...], "vendors": [...], "lines": [...], "length": seconds, "graph": {"nodes", "edges"},
##   "lane": [node ids in front of Granny's counter]}
## person: {"id", "kind": buyer|browser|stroller|pair|parent|child|kid, "visit" (index into the visits or -1), "look",
##   "fancy", "arch", "speed" (px/s), "cadence" (walk frames/s), "offset" (Vector2 px), "partner" (id or -1),
##   "spawn", "end", "path": [node ids], "steps": [{"t0", "t1", "do", "a", "b", "from", "to", "face"}],
##   "buy_t" (-1 = no sale), "line_t", "line_key", "stall_x"}
## Steps: do = walk (a -> b) or a stop at a == b: browse (faces the stall), buy, look (looks around), chat, play.

const STREAM := "market"
const SUB := "crowd"
const T_MIN := 30.0
const T_MAX := 45.0
## Buyers stand this far below the stall's ground line (contract: granny_stall x,y = the stall's feet).
const LANE_DY := 7
## Seconds a buyer stays at Granny's counter; the jar hops after BUY_AT.
const PAUSE := 1.8
const BUY_AT := 0.45
const LINE_AT := 0.25
## On-screen people at most at once (plus vendors, Granny, musician and the animals: about 40 actors).
const CAP := 20
## Archetype weights (man, woman, elder, child) and walking speeds in px/s, stride px per walk frame.
const ARCHES := ["man", "woman", "elder", "child"]
const ARCH_WEIGHTS := [30, 32, 22, 16]
const SPEED := {"man": [34.0, 42.0], "woman": [32.0, 40.0], "elder": [21.0, 27.0], "child": [40.0, 48.0]}
const STRIDE := {"man": 3.6, "woman": 3.3, "elder": 2.6, "child": 2.3}
const RUN_SPEED := 66.0
const VENDOR_IDS := ["baker", "vintner", "grocer", "librarian", "postman"]
## Vendor call-out lines MARKET_CALL_<ID>_1.._N and chat lines MARKET_CHAT_1.._N.
const CALL_VARIANTS := 2
const CHAT_VARIANTS := 6


## Archetype of a villager look seed (Villager.look_for uses it too, so the speed always matches the body).
static func arch_for(look: int) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = Hash.fnv1a31("arch|%d" % look)
	return String(ARCHES[Seeds.pick_weighted(r, ARCH_WEIGHTS)])


## Parade length for n market visitors (Market's 30-45 s).
static func length_for(visits: int) -> float:
	return clampf(12.0 + visits * 1.6, T_MIN, T_MAX)


## How many strollers come besides the customers: 6-12, more with reputation, fewer in the rain.
static func strollers_for(reputation: int, rainy: bool) -> int:
	var n := 6 + clampi(reputation, 0, 6)
	return maxi(3, floori(n / 2.0)) if rainy else n


static func build(save_seed: int, day: int, visits: Array, layout: Dictionary, reputation := 0, rainy := false) -> Dictionary:
	var r := Seeds.rng(save_seed, STREAM, day, SUB)
	var g := graph(layout)
	var length := length_for(visits.size())
	var people: Array = []
	var lines: Array = []
	var lane: Array = g.lane
	var vendor_nodes: Dictionary = g.vendors
	var entries: Array = g.entries
	var busy := {}  # lane node -> [[t0, t1], ...]
	# customers from Market.plan: everyone passes Granny's stall, buyers stop at their jar
	var n := visits.size()
	for i in n:
		var v: Dictionary = visits[i]
		var c: Dictionary = v.get("customer", {})
		var p := _person(r, people.size(), "buyer" if not (v.get("item", {}) as Dictionary).is_empty() else "browser",
			int(c.get("look", i)), bool(c.get("fancy", false)))
		p.visit = i
		p.line_key = String(v.get("line_key", ""))
		var arrive := 3.0 + i * (length - 9.0) / maxf(1.0, n - 1.0) + r.randf_range(-0.4, 0.4)
		var jar_x := _jar_x(layout, v.get("entry", {}))
		var stop := _lane_stop(g, lane, jar_x, arrive, busy)
		p.stall_x = jar_x
		var before := _vendor_stops(r, vendor_nodes, 0 if r.randf() < 0.55 else 1)
		var after := _vendor_stops(r, vendor_nodes, 0 if r.randf() < 0.6 else 1)
		var a := int(entries[r.randi_range(0, entries.size() - 1)])
		var z := int(entries[r.randi_range(0, entries.size() - 1)])
		var stops: Array = []
		for s in before:
			stops.append({"node": s, "do": "browse", "dur": r.randf_range(1.2, 2.4), "face": g.faces.get(s, "back")})
		var buyer := String(p.kind) == "buyer"
		stops.append({"node": stop, "do": "buy" if buyer else "browse", "dur": PAUSE if buyer else r.randf_range(1.6, 2.2), "granny": true})
		for s in after:
			stops.append({"node": s, "do": "browse", "dur": r.randf_range(1.0, 2.0), "face": g.faces.get(s, "back")})
		_route(p, g, a, stops, z, arrive)
		people.append(p)
		var t_at := _stop_time(p, stop)
		p.line_t = t_at + LINE_AT
		p.buy_t = t_at + BUY_AT if buyer else -1.0
		if p.line_key != "":
			lines.append({"t": p.line_t, "who": "p%d" % p.id, "key": p.line_key, "prio": 3, "dur": 1.9})
	# strollers: 1-3 vendor stalls; some walk in pairs and stop to chat, a parent with a child, kids run at the pigeons
	var zones: Array = g.zones
	var count := strollers_for(reputation, rainy)
	for k in count:
		var kind := "stroller"
		var roll := r.randf()
		if roll < 0.22:
			kind = "pair"
		elif roll < 0.38:
			kind = "parent"
		elif roll < 0.52 and not zones.is_empty():
			kind = "kid"
		var spawn := r.randf_range(-12.0, length - 10.0)
		var look := int(r.randi() & 0x7FFFFFFF)
		var p := _person(r, people.size(), kind if kind != "pair" else "stroller", look, false)
		if kind == "kid":
			p.arch = "child"
			p.speed = RUN_SPEED
			p.cadence = RUN_SPEED / 2.0
		elif kind == "parent" and String(p.arch) == "child":
			p.arch = "woman"
			_pace(r, p)
		var a := int(entries[r.randi_range(0, entries.size() - 1)])
		var z := int(entries[r.randi_range(0, entries.size() - 1)])
		var stops: Array = []
		if kind == "kid":
			stops.append({"node": int(zones[r.randi_range(0, zones.size() - 1)]), "do": "play", "dur": r.randf_range(1.2, 2.0)})
		else:
			for s in _vendor_stops(r, vendor_nodes, r.randi_range(1, 3)):
				stops.append({"node": s, "do": "browse", "dur": r.randf_range(1.4, 3.0), "face": g.faces.get(s, "back")})
		var chat_at := -1
		if kind == "pair":
			chat_at = r.randi_range(0, stops.size())
		_route_from(p, g, a, stops, z, spawn, chat_at, r)
		people.append(p)
		if chat_at >= 0:
			var chat_t := _first_stop(p, "chat")
			if chat_t >= 0.0:
				lines.append({"t": chat_t + 0.3, "who": "p%d" % p.id, "key": "MARKET_CHAT_%d" % r.randi_range(1, CHAT_VARIANTS), "prio": 2, "dur": 2.0})
		if kind == "pair" or kind == "parent":
			var q := _person(r, people.size(), "pair" if kind == "pair" else "child", int(r.randi() & 0x7FFFFFFF), false)
			if kind == "parent":
				q.arch = "child"
			q.partner = p.id
			p.partner = q.id
			q.speed = p.speed
			q.cadence = p.speed / float(STRIDE[q.arch])
			q.offset = p.offset + (Vector2(5, 4) if kind == "pair" else Vector2(7, 3))
			q.path = (p.path as Array).duplicate()
			q.steps = (p.steps as Array).duplicate(true)
			q.spawn = p.spawn
			q.end = p.end
			people.append(q)
			if kind == "pair":
				var t2 := _first_stop(q, "chat")
				if t2 >= 0.0:
					lines.append({"t": t2 + 1.3, "who": "p%d" % q.id, "key": "MARKET_CHAT_%d" % r.randi_range(1, CHAT_VARIANTS), "prio": 2, "dur": 1.8})
	_cap(people, lines)
	var vendors := _vendors(r, layout, people, length, lines)
	lines.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.t) < float(y.t))
	return {"people": people, "vendors": vendors, "lines": lines, "length": length,
		"graph": {"nodes": g.nodes, "edges": g.edges}, "lane": lane}


# --- the walk graph ----------------------------------------------------------------------------------------------

## The layout's walk graph plus: the entries, the vendors' front points, a lane of nodes in front of Granny's counter
## (one per stall column) and the pigeon zones, each joined to its nearest graph node.
## {"nodes": [Vector2], "edges": [[i, j]], "adj": {i: [j...]}, "entries": [ids], "vendors": {id: node}, "lane": [ids],
##  "zones": [ids]}
static func graph(layout: Dictionary) -> Dictionary:
	var walk: Dictionary = layout.get("walk", {})
	var nodes: Array = []
	for n in walk.get("nodes", []):
		nodes.append(_v(n))
	var base := nodes.size()
	var edges: Array = []
	for e in walk.get("edges", []):
		var i := int(e[0])
		var j := int(e[1])
		if i >= 0 and j >= 0 and i < base and j < base and i != j:
			edges.append([i, j])
	var out := {"nodes": nodes, "edges": edges, "entries": [], "vendors": {}, "lane": [], "zones": []}
	for p in layout.get("entries", []):
		out.entries.append(_spur(nodes, edges, base, _v(p)))
	out["faces"] = {}
	for vd in layout.get("vendors", []):
		var front: Vector2 = _v(vd.get("front", vd.get("stand", [0, 0])))
		var fn := int(vd.get("front_node", -1))
		var node := fn if fn >= 0 and fn < base else _spur(nodes, edges, base, front)
		out.vendors[String(vd.get("id", ""))] = node
		out.faces[node] = _face(nodes[node], _v(vd.get("stand", [0, 0])))
	var stall: Dictionary = layout.get("granny_stall", {})
	var jar_nodes: Array = stall.get("jar_nodes", [])
	var valid := jar_nodes.size() == Market.COLS
	for j in jar_nodes:
		valid = valid and int(j) >= 0 and int(j) < base
	if valid:
		for j in jar_nodes:
			out.lane.append(int(j))
	else:
		var counter: Array = stall.get("counter", [168, 140, 144, 48])
		var ly := lane_y(layout)
		var prev := -1
		for c in Market.COLS:
			var x := float(counter[0]) + (c + 0.5) * float(counter[2]) / Market.COLS
			nodes.append(Vector2(roundf(x), ly))
			var id := nodes.size() - 1
			if prev >= 0:
				edges.append([prev, id])
			prev = id
			out.lane.append(id)
		if base > 0:
			for k in [0, out.lane.size() - 1]:
				var id: int = out.lane[k]
				edges.append([id, _nearest(nodes, base, nodes[id])])
	for z in layout.get("pigeon_zones", []):
		var centre := Vector2(float(z[0]) + float(z[2]) / 2.0, float(z[1]) + float(z[3]) / 2.0).round()
		out.zones.append(_spur(nodes, edges, base, centre))
	var adj := {}
	for e in edges:
		for k in 2:
			var i := int(e[k])
			var j := int(e[1 - k])
			if not adj.has(i):
				adj[i] = []
			if not j in adj[i]:
				adj[i].append(j)
	out["adj"] = adj
	return out


## Feet y of the lane in front of Granny's counter.
static func lane_y(layout: Dictionary) -> float:
	var stall: Dictionary = layout.get("granny_stall", {})
	if stall.has("front"):
		return float(stall.front[1])
	if stall.has("feet_y"):
		return float(stall.feet_y) + LANE_DY + 5
	return float(stall.get("y", 210)) + LANE_DY


## True when every consecutive pair of the path is an edge of the graph.
static func on_graph(g: Dictionary, path: Array) -> bool:
	var adj: Dictionary = g.get("adj", {})
	if adj.is_empty():
		adj = {}
		for e in g.edges:
			for k in 2:
				if not adj.has(int(e[k])):
					adj[int(e[k])] = []
				adj[int(e[k])].append(int(e[1 - k]))
	for i in range(1, path.size()):
		var a := int(path[i - 1])
		if a != int(path[i]) and not (adj.get(a, []) as Array).has(int(path[i])):
			return false
	return true


## Shortest node path a -> b (Dijkstra on edge lengths), [a] when a == b, [] when unreachable.
static func shortest(g: Dictionary, a: int, b: int) -> Array:
	if a == b:
		return [a]
	var nodes: Array = g.nodes
	var adj: Dictionary = g.adj
	var dist := {a: 0.0}
	var prev := {}
	var open := [a]
	var done := {}
	while not open.is_empty():
		var best := 0
		for k in range(1, open.size()):
			if float(dist[open[k]]) < float(dist[open[best]]):
				best = k
		var u: int = open[best]
		open.remove_at(best)
		if u == b:
			break
		done[u] = true
		for w: int in adj.get(u, []):
			if done.has(w):
				continue
			var d := float(dist[u]) + (nodes[u] as Vector2).distance_to(nodes[w])
			if not dist.has(w) or d < float(dist[w]):
				dist[w] = d
				prev[w] = u
				if not w in open:
					open.append(w)
	if not prev.has(b):
		return []
	var path := [b]
	while path[0] != a:
		path.push_front(prev[path[0]])
	return path


# --- people ------------------------------------------------------------------------------------------------------

static func _person(r: RandomNumberGenerator, id: int, kind: String, look: int, fancy: bool) -> Dictionary:
	var p := {"id": id, "kind": kind, "visit": -1, "look": look, "fancy": fancy, "arch": arch_for(look),
		"speed": 0.0, "cadence": 0.0, "offset": Vector2(r.randi_range(-3, 3), r.randi_range(-2, 3)), "partner": -1,
		"spawn": 0.0, "end": 0.0, "path": [], "steps": [], "buy_t": -1.0, "line_t": -1.0, "line_key": "", "stall_x": -1.0}
	_pace(r, p)
	return p


static func _pace(r: RandomNumberGenerator, p: Dictionary) -> void:
	var span: Array = SPEED[p.arch]
	p.speed = snappedf(r.randf_range(float(span[0]), float(span[1])), 0.1)
	p.cadence = float(p.speed) / float(STRIDE[p.arch])


## 0..n distinct vendor stall nodes in a random order.
static func _vendor_stops(r: RandomNumberGenerator, vendor_nodes: Dictionary, n: int) -> Array:
	var ids: Array = vendor_nodes.keys()
	ids.sort()
	var out: Array = []
	for i in mini(n, ids.size()):
		var k := r.randi_range(0, ids.size() - 1)
		out.append(int(vendor_nodes[ids[k]]))
		ids.remove_at(k)
	return out


## A customer whose Granny stop is at time `arrive`: the walk before it is laid backwards so they reach it on time.
static func _route(p: Dictionary, g: Dictionary, a: int, stops: Array, z: int, arrive: float) -> void:
	var gi := 0
	for k in stops.size():
		if stops[k].has("granny"):
			gi = k
	# time from the entry to the Granny stop
	var lead := 0.0
	var at := a
	for k in gi + 1:
		lead += _walk_len(g, at, int(stops[k].node)) / float(p.speed)
		if k < gi:
			lead += float(stops[k].dur)
		at = int(stops[k].node)
	_route_from(p, g, a, stops, z, arrive - lead, -1, null)


## Lays the steps from `spawn`: entry -> stops (walking the shortest graph paths) -> exit. A pair stops to chat before
## stop number `chat_at` (at the node they reach there).
static func _route_from(p: Dictionary, g: Dictionary, a: int, stops: Array, z: int, spawn: float, chat_at: int,
		r: RandomNumberGenerator) -> void:
	var t := spawn
	var at := a
	var path: Array = [a]
	var steps: Array = []
	var nodes: Array = g.nodes
	var targets: Array = stops.duplicate()
	targets.append({"node": z, "do": "", "dur": 0.0})
	for k in targets.size():
		var to := int(targets[k].node)
		var leg := shortest(g, at, to)
		if leg.is_empty():
			leg = [at]
		for i in range(1, leg.size()):
			var u := int(leg[i - 1])
			var w := int(leg[i])
			var d: float = (nodes[u] as Vector2).distance_to(nodes[w])
			var dt := d / float(p.speed)
			steps.append({"t0": t, "t1": t + dt, "do": "walk", "a": u, "b": w, "from": nodes[u], "to": nodes[w], "face": _face(nodes[u], nodes[w])})
			path.append(w)
			t += dt
			if k == chat_at and i == floori(leg.size() / 2.0) and r != null:
				var dur := r.randf_range(2.4, 3.2)
				steps.append({"t0": t, "t1": t + dur, "do": "chat", "a": w, "b": w, "from": nodes[w], "to": nodes[w], "face": "right"})
				t += dur
				chat_at = -1
		at = to
		var what := String(targets[k].do)
		if what != "":
			var dur := float(targets[k].dur)
			var face := String(targets[k].get("face", "back"))
			if what == "play":
				face = "front"
			if what == "browse" and dur > 1.6:
				var look := minf(0.8, dur * 0.35)
				steps.append({"t0": t, "t1": t + dur - look, "do": "browse", "a": at, "b": at, "from": nodes[at], "to": nodes[at], "face": face})
				steps.append({"t0": t + dur - look, "t1": t + dur, "do": "look", "a": at, "b": at, "from": nodes[at], "to": nodes[at], "face": "front"})
			else:
				steps.append({"t0": t, "t1": t + dur, "do": what, "a": at, "b": at, "from": nodes[at], "to": nodes[at], "face": face})
			t += dur
	p.path = path
	p.steps = steps
	p.spawn = spawn
	p.end = t


static func _walk_len(g: Dictionary, a: int, b: int) -> float:
	var leg := shortest(g, a, b)
	var d := 0.0
	for i in range(1, leg.size()):
		d += (g.nodes[leg[i - 1]] as Vector2).distance_to(g.nodes[leg[i]])
	return d


static func _face(a: Vector2, b: Vector2) -> String:
	var d := b - a
	if absf(d.x) >= absf(d.y):
		return "left" if d.x < 0.0 else "right"
	return "front" if d.y > 0.0 else "back"


## Start time of the person's stop at `node` (the Granny stop).
static func _stop_time(p: Dictionary, node: int) -> float:
	for s in p.steps:
		if String(s.do) != "walk" and int(s.a) == node:
			return float(s.t0)
	return float(p.spawn)


static func _first_stop(p: Dictionary, what: String) -> float:
	for s in p.steps:
		if String(s.do) == what:
			return float(s.t0)
	return -1.0


## X of the middle of a stall entry's cells on the counter.
static func _jar_x(layout: Dictionary, entry: Variant) -> float:
	var stall: Dictionary = layout.get("granny_stall", {})
	var counter: Array = stall.get("counter", [168, 140, 144, 48])
	var cw := float(counter[2]) / Market.COLS
	if typeof(entry) != TYPE_DICTIONARY or (entry as Dictionary).is_empty():
		return float(counter[0]) + float(counter[2]) / 2.0
	var e: Dictionary = entry
	var span := 1
	if e.has("item"):
		span = PantryRules.item_size(e.item, int(e.get("rot", 0))).x
	return float(counter[0]) + (float(e.get("x", 0)) + span / 2.0) * cw


## The free lane node nearest the jar for [arrive, arrive + PAUSE] (a busy one is skipped).
static func _lane_stop(g: Dictionary, lane: Array, x: float, arrive: float, busy: Dictionary) -> int:
	var order := lane.duplicate()
	order.sort_custom(func(i: int, j: int) -> bool:
		return absf((g.nodes[i] as Vector2).x - x) < absf((g.nodes[j] as Vector2).x - x))
	for id: int in order:
		var free := true
		for span: Array in busy.get(id, []):
			if arrive < float(span[1]) + 0.3 and arrive + PAUSE > float(span[0]) - 0.3:
				free = false
		if free:
			if not busy.has(id):
				busy[id] = []
			busy[id].append([arrive, arrive + PAUSE])
			return id
	return int(order[0])


## Drops strollers (never customers) while more than CAP people are on screen at once.
static func _cap(people: Array, lines: Array) -> void:
	for guard in 40:
		var worst := 0.0
		var worst_n := 0
		for k in 120:
			var t := -5.0 + k * 0.5
			var n := 0
			for p in people:
				if t >= float(p.spawn) and t <= float(p.end):
					n += 1
			if n > worst_n:
				worst_n = n
				worst = t
		if worst_n <= CAP:
			return
		var drop := -1
		for i in range(people.size() - 1, -1, -1):
			var p: Dictionary = people[i]
			if int(p.visit) < 0 and int(p.partner) < 0 and worst >= float(p.spawn) and worst <= float(p.end):
				drop = i
				break
		if drop < 0:
			return
		var gone := "p%d" % int(people[drop].id)
		people.remove_at(drop)
		for j in range(lines.size() - 1, -1, -1):
			if String(lines[j].who) == gone:
				lines.remove_at(j)


# --- vendors -----------------------------------------------------------------------------------------------------

## The five neighbours stand still at their stalls: idle acts (wipe, arrange, wave), a wave when someone browses at
## their stall, a call-out now and then. [{"id", "at": Vector2, "acts": [{"t0", "t1", "do"}]}]
static func _vendors(r: RandomNumberGenerator, layout: Dictionary, people: Array, length: float, lines: Array) -> Array:
	var out: Array = []
	var g := graph(layout)
	for vd in layout.get("vendors", []):
		var id := String(vd.get("id", ""))
		var at := _v(vd.get("stand", [0, 0]))
		var node: int = g.vendors.get(id, -1)
		var visits: Array = []
		for p in people:
			for s in p.steps:
				if String(s.do) == "browse" and int(s.a) == node:
					visits.append(float(s.t0))
		visits.sort()
		var acts: Array = []
		var t := -12.0
		while t < length + 2.0:
			var what: String = ["idle", "idle", "wipe", "arrange"][r.randi_range(0, 3)]
			var dur := r.randf_range(1.6, 3.4)
			for vt: float in visits:
				if vt >= t and vt < t + dur:
					what = "wave"
					dur = maxf(1.2, vt - t + 1.2)
					break
			acts.append({"t0": t, "t1": t + dur, "do": what})
			t += dur
		var call := r.randf_range(1.0, 7.0)
		while call < length - 2.0:
			lines.append({"t": call, "who": "v" + id, "key": "MARKET_CALL_%s_%d" % [id.to_upper(), r.randi_range(1, CALL_VARIANTS)], "prio": 1, "dur": 1.7})
			call += r.randf_range(7.0, 13.0)
		out.append({"id": id, "at": at, "acts": acts})
	return out


# --- helpers -----------------------------------------------------------------------------------------------------

static func _v(a: Variant) -> Vector2:
	if a is Vector2:
		return a
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


static func _nearest(nodes: Array, count: int, p: Vector2) -> int:
	var best := 0
	for i in count:
		if (nodes[i] as Vector2).distance_squared_to(p) < (nodes[best] as Vector2).distance_squared_to(p):
			best = i
	return best


## Adds point p as a node joined to its nearest base graph node; returns its id (or the base node when p is on it).
static func _spur(nodes: Array, edges: Array, base: int, p: Vector2) -> int:
	if base == 0:
		nodes.append(p)
		return nodes.size() - 1
	var near := _nearest(nodes, base, p)
	if (nodes[near] as Vector2).distance_to(p) < 2.0:
		return near
	nodes.append(p)
	var id := nodes.size() - 1
	edges.append([id, near])
	return id
