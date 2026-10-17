extends Node2D
## MARKET-LIVE · Life on the market square (cosmetic, seeded so a market day always looks the same): pigeons peck in
## their zones and scatter when someone comes close (flap, curve off-screen, land again later), sparrows on perches,
## a bird crossing the sky now and then, the dog trotting, sniffing and sitting by Barnaby, the fiddler with floating
## notes, falling leaves, two fluttering bunting swags and flickering lanterns. Ground actors go into the y-sorted
## `world`; this node draws the overlay (bunting, leaves, notes, sky birds, lanterns). The market calls step(dt, people)
## every frame with the scaled time and the people's feet positions.

const ML := preload("res://scenes/market/market_layout.gd")
const SCARE := 26.0
const PIGEONS_MAX := 8
const SPARROWS := 4
const LEAVES := 9
const C_GLOW := Color("dbcc83")
const C_GLOW_DIM := Color("e5bd7f")
const C_GLOW_HOT := Color("f2d9c5")

var world: Node2D
var layout: Dictionary
var _rng := RandomNumberGenerator.new()
var _pigeon_frames: Array[Texture2D] = []
var _pigeon: Dictionary = {}
var _pigeons: Array = []
var _sparrow: Dictionary = {}
var _sparrow_frames: Array[Texture2D] = []
var _sparrows: Array = []
var _sky: Array = []
var _sky_wait := 4.0
var _dog: Dictionary = {}
var _dog_frames: Array[Texture2D] = []
var _music: Dictionary = {}
var _music_frames: Array[Texture2D] = []
var _note_frames: Array[Texture2D] = []
var _notes: Array = []
var _note_wait := 0.5
var _fiddle_wait := 2.0
var _leaf_frames: Array[Texture2D] = []
var _leaves: Array = []
var _bunting: Array = []
var _bunting_frames: Array[Texture2D] = []
var _lamps: Array = []
var _flutter_cool := 0.0
var _last_flutter := -9.0
var _t := 0.0


func setup(w: Node2D, l: Dictionary, seed_value: int) -> void:
	world = w
	layout = l
	_rng.seed = seed_value
	_setup_pigeons()
	_setup_sparrows()
	_setup_dog()
	_setup_musician()
	_setup_leaves()
	_setup_bunting()
	for p in layout.get("lanterns", []):
		_lamps.append({"at": ML.v(p).round(), "on": 1, "wait": _rng.randf_range(0.1, 0.6)})


## Pigeons flying / scattered and the dog's feet, for the smoke test.
func pigeon_states() -> Array:
	var out: Array = []
	for p in _pigeons:
		out.append(String(p.state))
	return out


func step(dt: float, people: Array) -> void:
	_t += dt
	_step_pigeons(dt, people)
	_step_sparrows(dt)
	_step_sky(dt)
	_step_dog(dt)
	_step_music(dt)
	_step_leaves(dt)
	_flutter_cool -= dt
	if _flutter_cool <= 0.0 and not _bunting.is_empty():
		_flutter_cool = _rng.randf_range(0.18, 0.35)
		for k in 3:
			var b: Dictionary = _bunting[_rng.randi_range(0, _bunting.size() - 1)]
			b.flip = 1 - int(b.flip)
	for l in _lamps:
		l.wait = float(l.wait) - dt
		if float(l.wait) <= 0.0:
			l.on = [0, 1, 1, 2][_rng.randi_range(0, 3)]
			l.wait = _rng.randf_range(0.08, 0.5)
	queue_redraw()


# --- pigeons -------------------------------------------------------------------------------------------------------

func _setup_pigeons() -> void:
	_pigeon = ML.sheet(layout, "pigeon")
	_pigeon_frames = ML.frames(_pigeon)
	if _pigeon_frames.is_empty():
		return
	var zones: Array = layout.get("pigeon_zones", [])
	for zi in zones.size():
		var z := ML.rect(zones[zi])
		var n := clampi(floori(z.size.x / 30.0), 1, 3)
		for k in n:
			if _pigeons.size() >= PIGEONS_MAX:
				return
			var node := _sprite(_pigeon_frames[0], _pigeon.feet)
			world.add_child(node)
			var pos := Vector2(_rng.randi_range(z.position.x + 4, z.end.x - 4), _rng.randi_range(z.position.y, z.end.y))
			_pigeons.append({"node": node, "zone": z, "zi": zi, "state": "ground", "act": "idle", "timer": _rng.randf_range(0.5, 2.0),
				"pos": pos, "to": pos, "vel": Vector2.ZERO, "frame": 0.0, "left": _rng.randf() < 0.5})
	_place_pigeons()


func _step_pigeons(dt: float, people: Array) -> void:
	var scattered := {}
	for p in _pigeons:
		var node: Node2D = p.node
		match String(p.state):
			"ground":
				if _near(p.pos, people):
					p.state = "fly_out"
					var away := -1.0 if _rng.randf() < 0.5 else 1.0
					p.vel = Vector2(away * _rng.randf_range(50.0, 80.0), _rng.randf_range(-70.0, -50.0))
					p.left = away < 0.0
					p.frame = 0.0
					scattered[p.zi] = true
					continue
				p.timer = float(p.timer) - dt
				if float(p.timer) <= 0.0:
					p.act = ["idle", "peck", "peck", "walk"][_rng.randi_range(0, 3)]
					p.timer = _rng.randf_range(0.8, 2.6)
					if p.act == "walk":
						var z: Rect2i = p.zone
						p.to = Vector2(_rng.randi_range(z.position.x + 4, z.end.x - 4), _rng.randi_range(z.position.y, z.end.y))
						p.left = (p.to as Vector2).x < (p.pos as Vector2).x
				if p.act == "walk":
					p.pos = (p.pos as Vector2).move_toward(p.to, 9.0 * dt)
					if (p.pos as Vector2).distance_to(p.to) < 0.5:
						p.act = "idle"
				p.frame = float(p.frame) + dt * (4.0 if p.act == "peck" else 6.0)
			"fly_out":
				p.vel = (p.vel as Vector2).rotated((0.9 if p.left else -0.9) * dt * 0.6)
				p.pos = (p.pos as Vector2) + (p.vel as Vector2) * dt
				p.frame = float(p.frame) + dt * 14.0
				if (p.pos as Vector2).y < -16.0 or (p.pos as Vector2).x < -20.0 or (p.pos as Vector2).x > 500.0:
					p.state = "away"
					p.timer = _rng.randf_range(5.0, 10.0)
			"away":
				p.timer = float(p.timer) - dt
				if float(p.timer) <= 0.0:
					var z: Rect2i = p.zone
					p.to = Vector2(_rng.randi_range(z.position.x + 4, z.end.x - 4), _rng.randi_range(z.position.y, z.end.y))
					p.pos = Vector2(-16.0 if (p.to as Vector2).x < 240.0 else 496.0, _rng.randf_range(10.0, 60.0))
					p.left = (p.to as Vector2).x < (p.pos as Vector2).x
					p.state = "fly_in"
			"fly_in":
				p.pos = (p.pos as Vector2).move_toward(p.to, 70.0 * dt)
				p.frame = float(p.frame) + dt * 12.0
				if (p.pos as Vector2).distance_to(p.to) < 1.0:
					if _near(p.to, people):
						p.state = "away"
						p.timer = _rng.randf_range(3.0, 6.0)
						p.pos = Vector2(p.pos.x, -20)
					else:
						p.state = "ground"
						p.act = "idle"
						p.timer = _rng.randf_range(0.5, 1.5)
	if not scattered.is_empty() and _flutter_ok():
		_sfx("sfx_pigeon_flutter")
	_place_pigeons()



func _flutter_ok() -> bool:
	if _t - _last_flutter < 1.5:
		return false
	_last_flutter = _t
	return true


func _place_pigeons() -> void:
	var anims: Dictionary = _pigeon.get("anims", {})
	for p in _pigeons:
		var node: Node2D = p.node
		var spr: Sprite2D = node.get_child(0)
		var flying := String(p.state) in ["fly_out", "fly_in"]
		node.visible = String(p.state) != "away"
		node.position = (p.pos as Vector2).round()
		# flying birds leave the y-sorted ground for the overlay (above people and stalls, below the UI)
		var parent: Node = self if flying else world
		if node.get_parent() != parent:
			node.reparent(parent, false)
		var seq: Array = anims.get("flap" if flying else String(p.act), anims.get("idle", [0]))
		if String(p.act) == "idle" and not flying:
			seq = anims.get("idle", [0])
		spr.texture = _pigeon_frames[int(seq[floori(float(p.frame)) % seq.size()]) % _pigeon_frames.size()]
		spr.flip_h = not bool(p.left)


func _near(at: Vector2, people: Array) -> bool:
	for q: Vector2 in people:
		if absf(q.x - at.x) < SCARE and absf(q.y - at.y) < SCARE * 0.6:
			return true
	return false


# --- sparrows and the sky bird -------------------------------------------------------------------------------------

func _setup_sparrows() -> void:
	_sparrow = ML.sheet(layout, "sparrow")
	_sparrow_frames = ML.frames(_sparrow)
	if _sparrow_frames.is_empty():
		return
	var perches: Array = (layout.get("perches", []) as Array).duplicate()
	for k in mini(SPARROWS, perches.size()):
		var i := _rng.randi_range(0, perches.size() - 1)
		var at := ML.v(perches[i]).round()
		perches.remove_at(i)
		var node := _sprite(_sparrow_frames[0], _sparrow.feet)
		node.position = at
		add_child(node)
		_sparrows.append({"node": node, "timer": _rng.randf_range(1.0, 5.0), "flap": 0.0})


func _step_sparrows(dt: float) -> void:
	for s in _sparrows:
		var spr: Sprite2D = (s.node as Node2D).get_child(0)
		s.timer = float(s.timer) - dt
		if float(s.flap) > 0.0:
			s.flap = float(s.flap) - dt
			spr.texture = _sparrow_frames[1 + floori(float(s.flap) * 12.0) % 2]
			if float(s.flap) <= 0.0:
				spr.texture = _sparrow_frames[0]
		elif float(s.timer) <= 0.0:
			s.timer = _rng.randf_range(2.0, 6.0)
			if _rng.randf() < 0.6:
				s.flap = 0.35
			else:
				spr.flip_h = not spr.flip_h


func _step_sky(dt: float) -> void:
	_sky_wait -= dt
	if _sky_wait <= 0.0 and not _sparrow_frames.is_empty():
		_sky_wait = _rng.randf_range(7.0, 13.0)
		var ltr := _rng.randf() < 0.5
		var node := _sprite(_sparrow_frames[1], _sparrow.feet)
		add_child(node)
		(node.get_child(0) as Sprite2D).flip_h = ltr
		_sky.append({"node": node, "pos": Vector2(-10.0 if ltr else 490.0, _rng.randf_range(14.0, 52.0)),
			"vx": (1.0 if ltr else -1.0) * _rng.randf_range(55.0, 75.0), "f": 0.0})
	for i in range(_sky.size() - 1, -1, -1):
		var b: Dictionary = _sky[i]
		b.pos = (b.pos as Vector2) + Vector2(float(b.vx) * dt, sin(_t * 5.0 + i) * 6.0 * dt)
		b.f = float(b.f) + dt * 10.0
		var node: Node2D = b.node
		node.position = (b.pos as Vector2).round()
		(node.get_child(0) as Sprite2D).texture = _sparrow_frames[1 + floori(float(b.f)) % 2]
		if (b.pos as Vector2).x < -20.0 or (b.pos as Vector2).x > 500.0:
			node.queue_free()
			_sky.remove_at(i)


# --- the dog -------------------------------------------------------------------------------------------------------

func _setup_dog() -> void:
	var sh := ML.sheet(layout, "dog")
	_dog_frames = ML.frames(sh)
	if _dog_frames.is_empty():
		return
	var home := ML.v(layout.get("dog_sit", [54, 236]))
	var node := _sprite(_dog_frames[0], sh.feet)
	world.add_child(node)
	var spots: Array = []
	for n in (layout.get("walk", {}) as Dictionary).get("nodes", []):
		var p := ML.v(n)
		if p.y > 200.0 and p.x > 20.0 and p.x < 460.0:
			spots.append(p)
	_dog = {"node": node, "sheet": sh, "home": home, "pos": home, "to": home, "state": "sit", "timer": _rng.randf_range(2.0, 4.0),
		"f": 0.0, "spots": spots, "right": true}


func _step_dog(dt: float) -> void:
	if _dog.is_empty():
		return
	var anims: Dictionary = (_dog.sheet as Dictionary).get("anims", {})
	var seq: Array = anims.get("sit", [4])
	_dog.f = float(_dog.f) + dt
	_dog.timer = float(_dog.timer) - dt
	match String(_dog.state):
		"sit", "wag", "sniff":
			seq = anims.get(String(_dog.state), [0])
			if float(_dog.timer) <= 0.0:
				if String(_dog.state) == "sit" and _rng.randf() < 0.45:
					_dog.state = "wag"
					_dog.timer = _rng.randf_range(1.0, 2.0)
					if _rng.randf() < 0.25:
						_sfx("sfx_dog_woof_soft")
				else:
					var spots: Array = _dog.spots
					var home_now := String(_dog.state) == "sniff" or spots.is_empty()
					_dog.to = _dog.home if home_now else spots[_rng.randi_range(0, spots.size() - 1)]
					_dog.state = "trot"
		"trot":
			seq = anims.get("trot", [0, 1, 2, 3])
			var to: Vector2 = _dog.to
			var pos: Vector2 = _dog.pos
			_dog.right = to.x >= pos.x
			_dog.pos = pos.move_toward(to, 38.0 * dt)
			if (_dog.pos as Vector2).distance_to(to) < 0.5:
				var home: Vector2 = _dog.home
				if to.distance_to(home) < 1.0:
					_dog.state = "sit"
					_dog.right = true
					_dog.timer = _rng.randf_range(3.0, 6.0)
				else:
					_dog.state = "sniff"
					_dog.timer = _rng.randf_range(1.4, 2.4)
	var node: Node2D = _dog.node
	node.position = (_dog.pos as Vector2).round()
	var spr: Sprite2D = node.get_child(0)
	var fps := 8.0 if String(_dog.state) == "trot" else 3.0
	spr.texture = _dog_frames[int(seq[floori(float(_dog.f) * fps) % seq.size()]) % _dog_frames.size()]
	spr.flip_h = not bool(_dog.right)


# --- the fiddler ---------------------------------------------------------------------------------------------------

func _setup_musician() -> void:
	var sh := ML.sheet(layout, "musician")
	_music_frames = ML.frames(sh)
	_note_frames = ML.frames(ML.sheet(layout, "note"))
	if _music_frames.is_empty() or not layout.has("musician"):
		return
	var node := _sprite(_music_frames[0], sh.feet)
	node.position = ML.v(layout.musician).round()
	world.add_child(node)
	_music = {"node": node, "at": node.position, "f": 0.0}


func _step_music(dt: float) -> void:
	if _music.is_empty():
		return
	_music.f = float(_music.f) + dt * 6.0
	((_music.node as Node2D).get_child(0) as Sprite2D).texture = _music_frames[floori(float(_music.f)) % _music_frames.size()]
	_fiddle_wait -= dt
	if _fiddle_wait <= 0.0:
		_fiddle_wait = _rng.randf_range(7.0, 11.0)
		_sfx("sfx_fiddle_phrase")
	_note_wait -= dt
	if _note_wait <= 0.0 and not _note_frames.is_empty():
		_note_wait = _rng.randf_range(0.7, 1.3)
		var at: Vector2 = _music.at
		_notes.append({"pos": at + Vector2(_rng.randi_range(4, 12), -40), "life": 0.0, "f": _rng.randi_range(0, _note_frames.size() - 1),
			"side": _rng.randf_range(-1.0, 1.0)})
	for i in range(_notes.size() - 1, -1, -1):
		var n: Dictionary = _notes[i]
		n.life = float(n.life) + dt
		n.pos = (n.pos as Vector2) + Vector2(float(n.side) * 4.0 * dt, -11.0 * dt)
		if float(n.life) > 1.7:
			_notes.remove_at(i)


# --- leaves, bunting, lanterns -------------------------------------------------------------------------------------

func _setup_leaves() -> void:
	_leaf_frames = ML.frames(ML.sheet(layout, "leaf"))
	if _leaf_frames.is_empty():
		return
	for i in LEAVES:
		_leaves.append(_new_leaf(_rng.randf_range(-20.0, 250.0)))


func _new_leaf(y: float) -> Dictionary:
	return {"x": _rng.randf_range(0.0, 478.0), "y": y, "v": _rng.randf_range(9.0, 17.0), "amp": _rng.randf_range(2.0, 5.0),
		"ph": _rng.randf_range(0.0, TAU), "f": _rng.randi_range(0, _leaf_frames.size() - 1), "flip": _rng.randf() < 0.5}


func _step_leaves(dt: float) -> void:
	for i in _leaves.size():
		var l: Dictionary = _leaves[i]
		l.y = float(l.y) + float(l.v) * dt
		l.ph = float(l.ph) + dt * 2.2
		if float(l.y) > 272.0:
			_leaves[i] = _new_leaf(-6.0)


func _setup_bunting() -> void:
	var sh := ML.sheet(layout, "bunting")
	_bunting_frames = ML.frames(sh)
	if _bunting_frames.is_empty():
		return
	var raw: Dictionary = (layout.get("sheets", {}) as Dictionary).get("bunting", {})
	var stepx := int(raw.get("step", 6))
	var hang := ML.v(raw.get("hang", [0, 0]))
	var colours: Array = []
	for k in (sh.anims as Dictionary):
		colours.append(sh.anims[k])
	var c := 0
	for g in layout.get("garlands", []):
		var a := Vector2(float(g[0]), float(g[1]))
		var b := Vector2(float(g[2]), float(g[3]))
		var sag := float(g[4])
		var n := floori(a.distance_to(b) / stepx)
		for k in range(1, n):
			var t := float(k) / n
			var p := a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t))
			var pair: Array = colours[c % colours.size()] if not colours.is_empty() else [0, 1]
			_bunting.append({"at": (p - hang).round(), "frames": pair, "flip": _rng.randi_range(0, 1)})
			c += 1


func _draw() -> void:
	for b in _bunting:
		var pair: Array = b.frames
		draw_texture(_bunting_frames[int(pair[int(b.flip) % pair.size()]) % _bunting_frames.size()], b.at)
	for l in _leaves:
		var x := roundi(float(l.x) + sin(float(l.ph)) * float(l.amp))
		var tex: Texture2D = _leaf_frames[int(l.f)]
		draw_texture_rect(tex, Rect2(x, roundi(float(l.y)), 4, 4) if not bool(l.flip) else Rect2(x + 4, roundi(float(l.y)), -4, 4), false)
	for n in _notes:
		draw_texture(_note_frames[int(n.f)], (n.pos as Vector2).round())
	for l in _lamps:
		var at: Vector2 = l.at
		var on := int(l.on)
		if on == 0:
			draw_rect(Rect2(at.x - 1, at.y - 1, 2, 2), C_GLOW_DIM)
		else:
			draw_rect(Rect2(at.x - 1, at.y - 2, 2, 4), C_GLOW)
			draw_rect(Rect2(at.x - 1, at.y - 1, 2, 2), C_GLOW_HOT if on == 2 else C_GLOW)


# --- helpers -------------------------------------------------------------------------------------------------------

## A Node2D at the feet with a Sprite2D child offset by the sheet's feet pixel.
func _sprite(tex: Texture2D, feet: Vector2i) -> Node2D:
	var holder := Node2D.new()
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = -Vector2(feet)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(s)
	return holder


func _sfx(id: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play_sfx(id)
