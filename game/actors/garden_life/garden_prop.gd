class_name GardenProp
extends Node2D
## GARDEN-LIFE · One prop of garden_props.json (ART-GARDEN2): Walter's truck and its gravel, the hen house and the two
## halves of its run, a hive, the clothesline, the scarecrow, the bench. Position is its feet (the bottom of its
## blocked cells, else of its cell) so the y-sorted objects layer orders it against Granny. Moves the ones that move by
## themselves (clothesline flutter, scarecrow sway, bees at the hive door) and carries the truck's load for the week.
## No rules here.

const Props := preload("res://scenes/garden/garden_props.gd")
const OUTLINE := preload("res://shaders/outline_highlight.gdshader")
const C_GOLD := Color("e5bd7f")
const LOAD_SHEET := "res://assets/sprites/garden/garden_truck_bed.png"
const LOAD_FRAMES := 4  ## hay and pumpkins, grape crates, apple baskets, pumpkins and a blanket
## Frame order and seconds per frame [calm, windy] of the props that move by themselves.
const ANIM := {
	"clothesline": [[0, 1, 2, 1], 0.34, 0.14],
	"scarecrow": [[0, 1], 0.9, 0.45],
	"hive": [[0, 0, 1], 0.5, 0.5],
}

var id := ""
var kind := ""  ## id without its number: "hive_2" -> "hive"
var info: Dictionary
var windy := false
var highlighted := false:
	set(v):
		if v != highlighted:
			highlighted = v
			_restyle()

var _sprite: Sprite2D
var _rect := Rect2i()  ## sprite rect, local px
var _t := 0.0
var _frame := 0


func setup(p: Dictionary, p_weather: String) -> void:
	info = p
	id = String(p.id)
	kind = id.rstrip("0123456789").trim_suffix("_")
	windy = p_weather == "windy"
	var world := Props.sprite_rect(p)
	position = Vector2(world.position.x + floori(world.size.x * 0.5), Props.feet_y(p))
	_rect = Rect2i(world.position - Vector2i(position), world.size)
	var tex := _tex(String(p.sheet))
	if tex != null:
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		_sprite.centered = false
		_sprite.hframes = maxi(1, int(tex.get_width() / maxi(1, int(p.frame.x))))
		_sprite.position = Vector2(_rect.position)
		var mat := ShaderMaterial.new()
		mat.shader = OUTLINE
		_sprite.material = mat
		add_child(_sprite)
	# bees stay in on rainy days: the hive door is quiet
	set_process(ANIM.has(kind) and not (kind == "hive" and p_weather == "rainy"))
	_restyle()


## Click/tap area in garden px (at least 16x16).
func hit_rect() -> Rect2:
	var r := Rect2(position + Vector2(_rect.position), Vector2(_rect.size))
	var dx := maxf(0.0, (16.0 - r.size.x) * 0.5)
	return r.grow_individual(dx, maxf(0.0, 16.0 - r.size.y), dx, 0.0)


## Truck bed: load frame `f` of garden_truck_bed.png with its top-left at `at` (garden px).
func set_load(f: int, at: Vector2i) -> void:
	var tex := _tex(LOAD_SHEET)
	if tex == null:
		return
	var load_sprite := Sprite2D.new()
	load_sprite.centered = false
	load_sprite.texture = tex
	load_sprite.hframes = LOAD_FRAMES
	load_sprite.frame = clampi(f, 0, LOAD_FRAMES - 1)
	load_sprite.position = Vector2(at) - position
	add_child(load_sprite)


func pop() -> void:
	scale = Vector2(1.08, 0.94)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	var a: Array = ANIM[kind]
	_t += delta
	var seq: Array = a[0]
	var f := int(seq[int(_t / float(a[2] if windy else a[1])) % seq.size()])
	if f != _frame:
		_frame = f
		_restyle()


func _restyle() -> void:
	if _sprite == null:
		return
	_sprite.frame = clampi(_frame, 0, _sprite.hframes - 1)
	var mat := _sprite.material as ShaderMaterial
	mat.set_shader_parameter("enabled", highlighted)
	mat.set_shader_parameter("outline_color", C_GOLD)


static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
