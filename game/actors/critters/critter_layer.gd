class_name CritterLayer
extends Node
## WILD-LIFE · Builds a map's critters from CritterRules placements and ticks them. The critters are added to
## `parent` (the y-sorted objects node, so they pass behind canopies and Granny); this node only drives them.
##   CritterLayer.attach(view.objects, CritterRules.wild(map, save_seed, day, weather), granny, weather, map)
## `map` (wild only) lets frogs find the water beside their bank cell. Not saved, no gameplay.

const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var target: Node2D
var critters: Array[Critter] = []


static func attach(parent: Node2D, placements: Array, p_target: Node2D, weather: String, map: Dictionary = {}) -> CritterLayer:
	var layer := CritterLayer.new()
	layer.name = "Critters"
	layer.target = p_target
	parent.add_child(layer)
	var i := 0
	for p in placements:
		var info: Dictionary = (p as Dictionary).duplicate()
		if info.kind == "frog" and not map.is_empty():
			var dive := _water_beside(map, info.cell)
			if dive != Vector2.ZERO:
				info["dive"] = dive
		var c := Critter.new()
		parent.add_child(c)
		var cell: Vector2i = info.cell
		c.setup(info, weather, hash([i, cell.x, cell.y, String(info.kind)]))
		layer.critters.append(c)
		i += 1
	return layer


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	for c in critters:
		c.tick(delta, target.position)


func _exit_tree() -> void:
	for c in critters:
		if is_instance_valid(c):
			c.queue_free()


## Feet position inside the water cell next to a bank cell, or ZERO.
static func _water_beside(map: Dictionary, cell: Vector2i) -> Vector2:
	var w := int(map.w)
	var h := int(map.h)
	for n in N4:
		var q: Vector2i = cell + n
		if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and int(map.ground[q.y * w + q.x]) == WildGen.T_WATER:
			return Vector2(q.x * 16 + 8, q.y * 16 + 12)
	return Vector2.ZERO
