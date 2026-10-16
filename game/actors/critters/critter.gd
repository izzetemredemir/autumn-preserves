class_name Critter
extends Node2D
## WILD-LIFE · One ambient little animal (art: assets/sprites/critters/, drawn with ascii_sprite.py from
## tools/sprites/critters/). No gameplay, never saved: it sits, fidgets, and gets out of Granny's way. All movement is
## on whole pixels; sprites are never rotated or scaled. Position is the feet (bottom-centre). CritterLayer ticks it.
## Weather (cosmetic): "windy" birds sit still, "foggy" hides what is far from Granny.

const SHEETS := {
	"sparrow": [preload("res://assets/sprites/critters/critter_sparrow.png"), 3, Vector2i(8, 8)],
	"robin": [preload("res://assets/sprites/critters/critter_robin.png"), 3, Vector2i(8, 8)],
	"squirrel": [preload("res://assets/sprites/critters/critter_squirrel.png"), 4, Vector2i(12, 12)],
	"hedgehog": [preload("res://assets/sprites/critters/critter_hedgehog.png"), 3, Vector2i(12, 8)],
	"frog": [preload("res://assets/sprites/critters/critter_frog.png"), 2, Vector2i(8, 8)],
	"ring": [preload("res://assets/sprites/critters/critter_ring.png"), 4, Vector2i(10, 6)],
}
const TILE := 16
const FOG_SEE := 72.0  ## px from Granny inside which things show in fog
const FLEE_PX := 44.0  ## birds fly off this close (windy: only when she is almost on them)
const FLEE_PX_WINDY := 18.0
const COMEBACK_PX := 120.0  ## Granny must be this far before a critter that left comes back
const COMEBACK_SEC := 12.0
const SQUIRREL_PX := 56.0
const CLIMB_PX := 34.0
const CLIMB_SPEED := 38.0
const HEDGEHOG_PX := 40.0
const FROG_PX := 34.0
const FLY_SEC := 1.3

var kind := ""
var species := ""  ## sheet key
var weather := ""
var home := Vector2.ZERO  ## feet at rest
var perch := false
var dive := Vector2.ZERO  ## frog: where it jumps to (the water beside its bank cell)

var state := "idle"
var _sprite := Sprite2D.new()
var _dy := 0.0  ## sprite drop below the feet (rings sit on the water; perched birds are lifted: negative)
var _t := 0.0  ## time in the current state
var _wait := 0.0
var _gone_for := 0.0
var _off := Vector2.ZERO  ## displacement from home, whole pixels applied
var _dir := -1.0  ## -1 faces left (as drawn), 1 right
var _fog_far := false
var _rng := RandomNumberGenerator.new()


## info: a CritterRules placement. `rng_seed` only drives fidgeting (visual randomness, never game state).
func setup(info: Dictionary, p_weather: String, rng_seed: int) -> void:
	kind = String(info.kind)
	weather = p_weather
	species = String(info.get("species", kind))
	perch = bool(info.get("perch", false))
	_rng.seed = rng_seed
	var c: Vector2i = info.cell
	home = Vector2(c.x * TILE + TILE / 2, (c.y + 1) * TILE)
	_dy = 0.0
	if kind == "ring":
		home.y = c.y * TILE
		_dy = 11.0
	elif perch:
		if info.has("feet"):
			home.y = c.y * TILE + int(info.feet)
		else:
			home.y += 1.0  # in front of the vine
			_dy = -float(info.get("lift", 0))
	elif kind == "squirrel":
		home += Vector2(7, 1)  # beside the trunk, in front of it
	elif kind == "bird" or kind == "hedgehog" or kind == "frog":
		home += Vector2(_rng.randi_range(-3, 3), _rng.randi_range(-3, 0))
	if info.has("dive"):
		dive = info.dive
	var sheet: Array = SHEETS[species]
	var size: Vector2i = sheet[2]
	_sprite.texture = sheet[0]
	_sprite.hframes = int(sheet[1])
	_sprite.centered = false
	_sprite.position = Vector2(-floori(size.x * 0.5), -size.y + _dy)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	position = home
	_wait = _rng.randf_range(1.0, 5.0)
	if kind == "ring":
		visible = false
		state = "gone"
		_wait = _rng.randf_range(0.5, 5.0)


func is_hidden_now() -> bool:
	return not visible


## One step: `granny` is her feet position in the same space.
func tick(delta: float, granny: Vector2) -> void:
	_t += delta
	var d := granny.distance_to(home)
	_fog_far = weather == "foggy" and d > FOG_SEE
	match kind:
		"bird":
			_tick_bird(delta, d, granny)
		"squirrel":
			_tick_squirrel(delta, d)
		"hedgehog":
			_tick_hedgehog(d)
		"frog":
			_tick_frog(delta, d)
		"ring":
			_tick_ring(delta)
	position = (home + _off).round()
	_sprite.flip_h = _dir > 0.0
	if state == "gone":
		visible = false
	else:
		visible = not _fog_far


func _go(s: String) -> void:
	state = s
	_t = 0.0


func _tick_bird(delta: float, d: float, granny: Vector2) -> void:
	var still := weather == "windy"
	match state:
		"idle", "peck", "hop":
			if d < (FLEE_PX_WINDY if still else FLEE_PX):
				_dir = 1.0 if granny.x < home.x else -1.0
				_go("fly")
				_sprite.frame = 2
				return
			_sprite.frame = 1 if state == "peck" else 0
			if state != "idle" and _t > (0.45 if state == "peck" else 0.18):
				_off = Vector2.ZERO
				_go("idle")
				return
			if state == "hop":
				_off = Vector2(0, -2.0 if _t < 0.12 else -1.0)
			_wait -= delta
			if _wait <= 0.0 and not still:
				_wait = _rng.randf_range(1.5, 5.0)
				if perch or _rng.randf() < 0.55:
					_go("peck")
				else:
					_dir = -1.0 if _rng.randf() < 0.5 else 1.0
					_go("hop")
		"fly":
			var k := _t / FLY_SEC
			_off = Vector2(_dir * 70.0 * k, -64.0 * k * (2.0 - k)).round()
			_sprite.frame = 2
			if _t >= FLY_SEC:
				_gone_for = 0.0
				_go("gone")
		"gone":
			_comeback(delta, d, "idle")


func _tick_squirrel(delta: float, d: float) -> void:
	match state:
		"idle":
			_sprite.frame = 0
			_off = Vector2.ZERO
			if d < SQUIRREL_PX:
				_go("climb")
		"climb":
			var up := minf(_t * CLIMB_SPEED, CLIMB_PX)
			var to_trunk := minf(_t * 40.0, 7.0)
			_off = Vector2(-to_trunk, -up).round()
			_sprite.frame = 2 + (int(_t / 0.12) % 2)
			if up >= CLIMB_PX:
				_gone_for = 0.0
				_go("gone")
		"gone":
			_off = Vector2.ZERO
			_comeback(delta, d, "idle")


func _tick_hedgehog(d: float) -> void:
	if d < HEDGEHOG_PX:
		_go_if("curl")
	elif state == "curl" and d > HEDGEHOG_PX + 14.0 and _t > 1.5:
		_go("idle")
	_sprite.frame = 2 if state == "curl" else int(_t / 0.9) % 2


func _go_if(s: String) -> void:
	if state != s:
		_go(s)


func _tick_frog(delta: float, d: float) -> void:
	match state:
		"idle", "hop":
			if d < FROG_PX and dive != Vector2.ZERO:
				_dir = -1.0 if dive.x <= home.x else 1.0
				_go("dive")
				return
			_sprite.frame = 1 if state == "hop" else 0
			if state == "hop":
				_off = Vector2(0, -2.0 if _t < 0.12 else 0.0)
				if _t > 0.25:
					_off = Vector2.ZERO
					_go("idle")
				return
			_wait -= delta
			if _wait <= 0.0:
				_wait = _rng.randf_range(3.0, 8.0)
				_go("hop")
		"dive":
			var k := minf(_t / 0.4, 1.0)
			_off = ((dive - home) * k + Vector2(0, -6.0 * sin(k * PI))).round()
			_sprite.frame = 1
			if k >= 1.0:
				_gone_for = 0.0
				_go("gone")
		"gone":
			_comeback(delta, d, "idle")


func _tick_ring(delta: float) -> void:
	if state == "gone":
		_wait -= delta
		if _wait <= 0.0:
			_go("play")
			_sprite.frame = 0
	elif state == "play":
		var f := int(_t / 0.4)
		if f >= 4:
			_wait = _rng.randf_range(2.0, 7.0)
			_go("gone")
		else:
			_sprite.frame = f


## After it left: back at home once Granny has been far for COMEBACK_SEC.
func _comeback(delta: float, d: float, to: String) -> void:
	_gone_for = _gone_for + delta if d > COMEBACK_PX else 0.0
	if _gone_for >= COMEBACK_SEC:
		_off = Vector2.ZERO
		_wait = _rng.randf_range(1.0, 4.0)
		_go(to)
		_sprite.frame = 0
