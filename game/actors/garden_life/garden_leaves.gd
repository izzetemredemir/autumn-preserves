extends RefCounted
## GARDEN-LIFE · Granny walks through a leaf pile: a few outlined leaves (garden_leafburst.png, 4x4, four tints) pop
## up and flutter down. They free themselves; visual randomness only.

const SHEET := "res://assets/sprites/garden/garden_leafburst.png"
const SIZE := 4


## `count` leaves out of the pile whose feet are at `at` (garden px), added to `parent`.
static func burst(parent: Node, at: Vector2, count := 5) -> void:
	if not ResourceLoader.exists(SHEET):
		return
	var tex: Texture2D = load(SHEET)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var leaf := Sprite2D.new()
		leaf.texture = tex
		leaf.hframes = maxi(1, int(tex.get_width() / SIZE))
		leaf.frame = rng.randi_range(0, leaf.hframes - 1)
		leaf.centered = false
		leaf.z_index = 40
		leaf.position = (at + Vector2(rng.randi_range(-5, 5), rng.randi_range(-4, 0))).round()
		parent.add_child(leaf)
		var up := leaf.position + Vector2(rng.randi_range(-12, 12), rng.randi_range(-16, -8))
		var down := up + Vector2(rng.randi_range(-4, 4), rng.randi_range(10, 16))
		var t := leaf.create_tween()
		t.tween_property(leaf, "position", up.round(), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(leaf, "position", down.round(), rng.randf_range(0.5, 0.8)).set_ease(Tween.EASE_IN)
		t.tween_callback(leaf.queue_free)
