class_name TownCrowd
extends RefCounted
## LIVING-TOWN · Who is out in the town square on an ordinary day. Pure: no autoloads, no scenes. Seeded from
## Seeds.rng(save_seed, "town", day, "crowd"), so a day always plays the same square.
## The square runs on a loop of LOOP seconds that repeats without a seam: every villager has a spawn time in [0, LOOP)
## and a route shorter than the loop, so at scene time t a villager is out when spawn <= l <= end for one
## l = local_time(...). Barnaby, Rosie and Pip stand at their places (idle acts, a wave when someone stops by), Vito and
## Edith stroll between the shops on routes that start and end at the same stop and fill the whole loop.
## Input: a town layout (town_layout.json: walk graph, entries, the standing neighbours' stand and front points, the
## strollers' stops, the notice-board spots, pigeon zones). Routes use MarketCrowd's walk graph and route helpers.
##
## build() -> {"people": [...], "neighbours": [...], "lines": [...], "loop": LOOP, "graph": {"nodes", "edges"}}
## person: MarketCrowd's person plus "npc" (the neighbour id for Vito and Edith, else ""); kinds: reader (stops at the
##   notice board), shopper (stops by a neighbour), stroller, pair (two chatting), parent + child, kid (two children
##   playing by the pigeons), npc.
## neighbour: {"id", "at": Vector2, "acts": [{"t0", "t1", "do": idle | wipe | arrange | wave}]} (acts cover [0, LOOP))
## line: {"t" (in [0, LOOP)), "who": "p<id>" | "n<neighbour id>", "key", "prio", "dur"}

const STREAM := "town"
const SUB := "crowd"
const LOOP := 90.0
## Villagers out at once at most (besides the five neighbours and the animals).
const CAP := 10
## Groups (a villager, a pair, a parent with a child, two kids) per loop on a sunny and on a rainy day.
const GROUPS_SUNNY := 34
const GROUPS_RAINY := 15
const STAND_IDS := ["grocer", "baker", "postman"]
const STROLL_IDS := ["vintner", "librarian"]
## Lines: TOWN_CALL_<ID>_1..CALL_VARIANTS, TOWN_CHAT_1..CHAT_VARIANTS, TOWN_CHAT_RAIN_1..RAIN_VARIANTS,
## TOWN_CHAT_BOARD_1..BOARD_VARIANTS.
const CALL_VARIANTS := 2
const CHAT_VARIANTS := 6
const RAIN_VARIANTS := 3
const BOARD_VARIANTS := 3
## A speaker's feet must be above this y for a line (lower feet are hidden behind the shop panel).
const SEEN_Y := 170.0
## The neighbours' first calls follow each other this many seconds apart, so the square talks as soon as it opens.
const FIRST_CALL := 2.6
## Where the second of a group walks, from the first.
const PARTNER_AT := {"pair": Vector2(5, 4), "parent": Vector2(7, 3), "kid": Vector2(9, 2)}


## The person's own time at scene time t, or -1 when they are not out (the loop repeats every LOOP seconds).
static func local_time(p: Dictionary, t: float) -> float:
	var m := fposmod(t, LOOP)
	var l := m if m >= float(p.spawn) else m + LOOP
	return l if l <= float(p.end) else -1.0


static func build(save_seed: int, day: int, layout: Dictionary, rainy := false) -> Dictionary:
	var r := Seeds.rng(save_seed, STREAM, day, SUB)
	var g := MarketCrowd.graph(layout)
	var people: Array = []
	var lines: Array = []
	var entries: Array = g.entries
	var board := _ids(layout, layout.get("board", []))
	var fronts: Array = []
	for id: String in STAND_IDS:
		if g.vendors.has(id):
			fronts.append(int(g.vendors[id]))
	var zones: Array = g.zones
	# Vito and Edith first: their ids stay 0 and 1 whatever the crowd does
	for sd in layout.get("strollers", []):
		var npc := _stroller(r, g, layout, sd, people.size(), rainy)
		if not npc.is_empty():
			people.append(npc)
	var groups := GROUPS_RAINY if rainy else GROUPS_SUNNY
	for i in groups:
		var spawn := (i + r.randf_range(0.0, 0.8)) * LOOP / groups
		var roll := r.randf()
		var kind := "stroller"
		if roll < 0.24 and not board.is_empty():
			kind = "reader"
		elif roll < 0.48 and not fronts.is_empty():
			kind = "shopper"
		elif roll < 0.64:
			kind = "pair"
		elif roll < 0.74:
			kind = "parent"
		elif roll < 0.86 and not rainy and not zones.is_empty():
			kind = "kid"
		var p := MarketCrowd._person(r, people.size(), kind, int(r.randi() & 0x7FFFFFFF), false)
		p["npc"] = ""
		if kind == "kid":
			p.arch = "child"
			p.speed = MarketCrowd.RUN_SPEED
			p.cadence = MarketCrowd.RUN_SPEED / 2.0
		elif kind == "parent" and String(p.arch) == "child":
			p.arch = "woman"
			MarketCrowd._pace(r, p)
		var a := int(entries[r.randi_range(0, entries.size() - 1)])
		var z := a
		if entries.size() > 1:
			while z == a:
				z = int(entries[r.randi_range(0, entries.size() - 1)])
		var stops := _stops(r, g, kind, board, fronts, zones)
		var chat_at := -1
		if kind == "pair":
			chat_at = r.randi_range(0, maxi(0, stops.size() - 1))
		MarketCrowd._route_from(p, g, a, stops, z, spawn, chat_at, r)
		people.append(p)
		if kind == "reader" and r.randf() < 0.35:
			var at := _first_stop_at(p, g, "browse")
			if at >= 0.0:
				lines.append(_line(at + 0.6, "p%d" % int(p.id), "TOWN_CHAT_BOARD_%d" % r.randi_range(1, BOARD_VARIANTS), 2, 1.9))
		if kind == "pair":
			var chat_t := _first_stop_at(p, g, "chat")
			if chat_t >= 0.0:
				lines.append(_line(chat_t + 0.3, "p%d" % int(p.id), _chat_key(r, rainy), 2, 2.0))
		if kind in ["pair", "parent", "kid"]:
			var q := MarketCrowd._person(r, people.size(), "pair" if kind == "pair" else ("child" if kind == "parent" else "kid"),
				int(r.randi() & 0x7FFFFFFF), false)
			q["npc"] = ""
			if kind != "pair":
				q.arch = "child"
			q.partner = p.id
			p.partner = q.id
			q.speed = p.speed
			q.cadence = p.cadence if kind == "kid" else float(p.speed) / float(MarketCrowd.STRIDE[q.arch])
			q.offset = p.offset + (PARTNER_AT[kind] as Vector2)
			q.path = (p.path as Array).duplicate()
			q.steps = (p.steps as Array).duplicate(true)
			q.spawn = p.spawn
			q.end = p.end
			people.append(q)
			if kind == "pair":
				var t2 := _first_stop_at(q, g, "chat")
				if t2 >= 0.0:
					lines.append(_line(t2 + 1.3, "p%d" % int(q.id), _chat_key(r, rainy), 2, 1.8))
	_cap(people, lines)
	var neighbours := _neighbours(r, layout, g, people, lines)
	for p in people:
		var npc := String(p.npc)
		if npc == "":
			continue
		var call := FIRST_CALL * (STAND_IDS.size() + STROLL_IDS.find(npc)) + r.randf_range(0.5, 2.0)
		while call < LOOP - 1.0:
			lines.append(_line(call, "p%d" % int(p.id), "TOWN_CALL_%s_%d" % [npc.to_upper(), r.randi_range(1, CALL_VARIANTS)], 1, 1.8))
			call += r.randf_range(15.0, 26.0)
	lines.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.t) < float(y.t))
	return {"people": people, "neighbours": neighbours, "lines": lines, "loop": LOOP,
		"graph": {"nodes": g.nodes, "edges": g.edges}}


## Villagers out at scene time t (Vito and Edith not counted).
static func out_at(crowd: Dictionary, t: float) -> int:
	var n := 0
	for p in crowd.get("people", []):
		if String(p.get("npc", "")) == "" and local_time(p, t) >= 0.0:
			n += 1
	return n


## True when feet at `at` are on screen and above the shop panel's lower part.
static func seen(at: Vector2) -> bool:
	return at.y < SEEN_Y and at.x > 8.0 and at.x < 472.0


# --- villagers ----------------------------------------------------------------------------------------------------

## The stops of a villager's walk (MarketCrowd._route_from format).
static func _stops(r: RandomNumberGenerator, g: Dictionary, kind: String, board: Array, fronts: Array, zones: Array) -> Array:
	var stops: Array = []
	match kind:
		"reader":
			var b := int(board[r.randi_range(0, board.size() - 1)])
			stops.append({"node": b, "do": "browse", "dur": r.randf_range(2.6, 4.6), "face": "back"})
		"shopper":
			var picks := fronts.duplicate()
			for k in mini(r.randi_range(1, 2), picks.size()):
				var f := int(picks[r.randi_range(0, picks.size() - 1)])
				picks.erase(f)
				stops.append({"node": f, "do": "browse", "dur": r.randf_range(1.6, 3.0), "face": g.faces.get(f, "back")})
		"kid":
			stops.append({"node": int(zones[r.randi_range(0, zones.size() - 1)]), "do": "play", "dur": r.randf_range(1.8, 3.0)})
		"pair", "parent":
			if r.randf() < 0.5 and not board.is_empty():
				stops.append({"node": int(board[r.randi_range(0, board.size() - 1)]), "do": "browse", "dur": r.randf_range(2.0, 3.4), "face": "back"})
			elif not fronts.is_empty():
				var f2 := int(fronts[r.randi_range(0, fronts.size() - 1)])
				stops.append({"node": f2, "do": "browse", "dur": r.randf_range(1.6, 2.8), "face": g.faces.get(f2, "back")})
		_:
			if r.randf() < 0.4:
				var n := r.randi_range(0, (g.nodes as Array).size() - 1)
				if seen(g.nodes[n]):
					stops.append({"node": n, "do": "look", "dur": r.randf_range(1.0, 2.0), "face": "front"})
	return stops


## Start time of the person's first stop of kind `what` where they can be seen, -1 when none.
static func _first_stop_at(p: Dictionary, g: Dictionary, what: String) -> float:
	for s in p.steps:
		if String(s.do) == what and seen(g.nodes[int(s.a)]):
			return float(s.t0)
	return -1.0


static func _chat_key(r: RandomNumberGenerator, rainy: bool) -> String:
	if rainy and r.randf() < 0.6:
		return "TOWN_CHAT_RAIN_%d" % r.randi_range(1, RAIN_VARIANTS)
	return "TOWN_CHAT_%d" % r.randi_range(1, CHAT_VARIANTS)


static func _line(t: float, who: String, key: String, prio: int, dur: float) -> Dictionary:
	return {"t": fposmod(t, LOOP), "who": who, "key": key, "prio": prio, "dur": dur}


## Drops lone villagers (never Vito, Edith or anyone in a group) while more than CAP are out at once.
static func _cap(people: Array, lines: Array) -> void:
	for guard in 60:
		var worst := 0.0
		var worst_n := 0
		for k in int(LOOP * 2.0):
			var t := k * 0.5
			var n := out_at({"people": people}, t)
			if n > worst_n:
				worst_n = n
				worst = t
		if worst_n <= CAP:
			return
		var drop := -1
		for i in range(people.size() - 1, -1, -1):
			var p: Dictionary = people[i]
			if String(p.npc) == "" and int(p.partner) < 0 and local_time(p, worst) >= 0.0:
				drop = i
				break
		if drop < 0:
			return
		var gone := "p%d" % int(people[drop].id)
		people.remove_at(drop)
		for j in range(lines.size() - 1, -1, -1):
			if String(lines[j].who) == gone:
				lines.remove_at(j)


# --- the neighbours -------------------------------------------------------------------------------------------------

## Vito or Edith: from their first stop round their stops and back, filling the loop exactly (spawn 0, end LOOP).
static func _stroller(r: RandomNumberGenerator, g: Dictionary, layout: Dictionary, sd: Dictionary, id: int, rainy: bool) -> Dictionary:
	var npc := String(sd.get("id", ""))
	var seq := _ids(layout, sd.get("stops", []))
	if npc == "" or seq.is_empty():
		return {}
	var arch := "elder" if npc == "librarian" else "man"
	var p := MarketCrowd._person(r, id, "npc", 0, false)
	p.arch = arch
	MarketCrowd._pace(r, p)
	p.speed = float(p.speed) * 0.85
	p.cadence = float(p.speed) / float(MarketCrowd.STRIDE[arch])
	p.offset = Vector2(0, 1)
	p["npc"] = npc
	p["umbrella"] = rainy
	var home := int(seq[0])
	var stops: Array = []
	var t := 0.0
	var at := home
	var k := 0
	while k < 40:
		var node := int(seq[k % seq.size()])
		var dur := r.randf_range(3.5, 7.0)
		var walk := MarketCrowd._walk_len(g, at, node) / float(p.speed)
		var back := MarketCrowd._walk_len(g, node, home) / float(p.speed)
		if k > 0 and t + walk + dur + back > LOOP - 2.0:
			break
		stops.append(_npc_stop(g, layout, node, dur))
		t += walk + dur
		at = node
		k += 1
	MarketCrowd._route_from(p, g, home, stops, home, 0.0, -1, null)
	var first: Dictionary = stops[0]
	var nodes: Array = g.nodes
	(p.steps as Array).append({"t0": p.end, "t1": LOOP, "do": String(first.do), "a": home, "b": home, "from": nodes[home],
		"to": nodes[home], "face": String(first.face)})
	p.end = LOOP
	return p


## Vito and Edith visit a neighbour (facing them), read the notice board or look around.
static func _npc_stop(g: Dictionary, layout: Dictionary, node: int, dur: float) -> Dictionary:
	if g.faces.has(node):
		return {"node": node, "do": "browse", "dur": dur, "face": g.faces[node]}
	if node in _ids(layout, layout.get("board", [])):
		return {"node": node, "do": "browse", "dur": dur, "face": "back"}
	return {"node": node, "do": "look", "dur": dur, "face": "front"}


## Barnaby, Rosie and Pip stand still: idle acts (wipe, arrange), a wave when someone stops in front of them, a call now
## and then.
static func _neighbours(r: RandomNumberGenerator, layout: Dictionary, g: Dictionary, people: Array, lines: Array) -> Array:
	var out: Array = []
	for vd in layout.get("vendors", []):
		var id := String(vd.get("id", ""))
		if not id in STAND_IDS:
			continue
		var node: int = g.vendors.get(id, -1)
		var visits: Array = []
		for p in people:
			for s in p.steps:
				if String(s.do) == "browse" and int(s.a) == node:
					visits.append(fposmod(float(s.t0), LOOP))
		visits.sort()
		var acts: Array = []
		var t := 0.0
		while t < LOOP:
			var what: String = ["idle", "idle", "wipe", "arrange"][r.randi_range(0, 3)]
			var dur := r.randf_range(1.6, 3.6)
			for vt: float in visits:
				if vt >= t and vt < t + dur:
					what = "wave"
					dur = maxf(1.2, vt - t + 1.2)
					break
			acts.append({"t0": t, "t1": minf(LOOP, t + dur), "do": what})
			t += dur
		var call := FIRST_CALL * STAND_IDS.find(id) + r.randf_range(0.5, 2.0)
		while call < LOOP - 1.0:
			lines.append(_line(call, "n" + id, "TOWN_CALL_%s_%d" % [id.to_upper(), r.randi_range(1, CALL_VARIANTS)], 1, 1.8))
			call += r.randf_range(15.0, 26.0)
		out.append({"id": id, "at": MarketCrowd._v(vd.get("stand", [0, 0])), "acts": acts})
	return out


# --- helpers ------------------------------------------------------------------------------------------------------

## Node ids of a list of walk node names or indices (unknown names are skipped).
static func _ids(layout: Dictionary, list: Variant) -> Array:
	var names: Array = (layout.get("walk", {}) as Dictionary).get("names", [])
	var count: int = ((layout.get("walk", {}) as Dictionary).get("nodes", []) as Array).size()
	var out: Array = []
	if typeof(list) != TYPE_ARRAY:
		return out
	for v in list:
		var i := names.find(String(v)) if v is String else int(v)
		if i >= 0 and i < count:
			out.append(i)
	return out
