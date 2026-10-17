extends RefCounted
## World-space feedback for walked scenes (GD-WILD, FEEL): text bubbles, leaf bursts, the whole tree shake, fruit
## that falls with a bounce and a shadow, picked things popping up and flying into the HUD bag, leaves kicked up by
## footsteps. Everything moves on whole pixels and frees itself. Visual randomness only, never game state.

const LEAF_COLORS := ["a22512", "c94d2e", "e19064", "b66813", "e5bd7f"]
const BURST_COLORS := ["c94d2e", "e19064", "e5bd7f", "dbcc83", "b66813"]  ## brighter: shaken leaves read on any canopy
const C_SHADOW := Color("3d1f29")  ## plum_900: hard ground shadow to the lower right
const C_CREAM := Color("f2d9c5")
const C_INK := Color("111010")
const FLIGHT_LAYER := 11  ## over the HUD (layer 10), so things fly into the bag icon
const FLIGHT_SECONDS := 0.36
const THUMP_DELAY := 0.27  ## the first fruit lands


## A paper bubble with `text` (already translated) centred above `at`; pops in, rises, goes away.
static func bubble(parent: Node, at: Vector2, text: String, seconds := 1.4) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PaperPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 50
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("50361e"))
	panel.add_child(label)
	parent.add_child(panel)
	var size := panel.get_combined_minimum_size()
	panel.size = size
	panel.position = Vector2(roundi(at.x - size.x * 0.5), roundi(at.y - size.y))
	panel.pivot_offset = Vector2(floori(size.x * 0.5), size.y)
	panel.scale = Vector2(0.6, 0.6)
	var t := panel.create_tween()
	t.tween_property(panel, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "position:y", panel.position.y - 4, 0.25)
	t.tween_interval(seconds)
	t.tween_callback(panel.queue_free)


## The whole tree-shake moment for any walked scene (the wild today; the garden can call it the same way, then drop
## its own leaf_burst / fruit_to_bag / camera.shake / sfx_fruit_drop lines): trunk wiggle (`tree.wiggle()` when it
## has one, else a 1 px wiggle of the node), a burst of leaves from `canopy`, `count` fruit falling to `ground_y`
## with a bounce and a shadow, then popping up as `icon` (when given) and flying into the HUD bag (to `target`
## without a HUD), a 2 px camera shake (`camera.shake(px, seconds)` when given) and a soft thump as fruit lands.
static func shake_tree(fx: Node, tree: Node2D, canopy: Vector2, ground_y: float, target: Node2D, color: Color,
		count: int, camera: Node = null, icon: Texture2D = null, leaves := 18, spread := Vector2i(16, 10)) -> void:
	if tree != null:
		if tree.has_method("wiggle"):
			tree.call("wiggle")
		else:
			Juice.wiggle(tree, 1)
	if camera != null and camera.has_method("shake") and not Juice.calm:
		camera.call("shake", 2, 0.2)
	leaf_burst(fx, canopy, leaves, spread)
	fruit_to_bag(fx, canopy, ground_y, target, color, count, icon)
	if count > 0 and fx.is_inside_tree():
		fx.get_tree().create_timer(THUMP_DELAY).timeout.connect(func() -> void: Audio.play_sfx("sfx_fruit_drop"))


## Leaves bursting out of a canopy centred at `at`; they start within `spread` px of it (half width, half height),
## then flutter down side to side. Each leaf (3x2 or 2x3) has a 1 px ink edge on its lower right so it reads on any
## canopy or ground.
static func leaf_burst(parent: Node, at: Vector2, count := 10, spread := Vector2i(8, 6)) -> void:
	var rng := Juice.rng()
	for i in count:
		var leaf := ColorRect.new()  # the dark edge; the leaf colour sits on its upper left
		leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		leaf.color = C_INK
		leaf.size = Vector2(4, 3) if i % 2 == 0 else Vector2(3, 4)
		var face := ColorRect.new()
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.color = Color(BURST_COLORS[rng.randi_range(0, BURST_COLORS.size() - 1)])
		face.size = leaf.size - Vector2.ONE
		leaf.add_child(face)
		leaf.z_index = 40
		leaf.position = (at + Vector2(rng.randi_range(-spread.x, spread.x), rng.randi_range(-spread.y, spread.y))).round()
		parent.add_child(leaf)
		var dir := signf(leaf.position.x - at.x) if leaf.position.x != at.x else (1.0 if i % 2 == 0 else -1.0)
		var out := leaf.position + Vector2(dir * rng.randi_range(10, spread.x + 18), rng.randi_range(-spread.y - 12, 0))
		var fall := rng.randf_range(0.5, 0.8)
		var sway := 2 if rng.randf() < 0.5 else -2
		var t := leaf.create_tween()
		t.tween_property(leaf, "position", out.round(), 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		var p := out.round()
		for k in 3:  # flutter: whole-pixel steps left and right on the way down
			p += Vector2(sway if k % 2 == 0 else -sway, rng.randi_range(5, 9))
			t.tween_property(leaf, "position", p, fall / 3.0).set_trans(Tween.TRANS_SINE)
		t.tween_callback(leaf.queue_free)


## `count` fruit drop from `from` to the ground at `ground_y` (a shadow under each, a little bounce), pop up (as
## `icon` when given) and fly into the HUD bag icon, which bumps; without a HUD they hop into `target` (Granny).
static func fruit_to_bag(parent: Node, from: Vector2, ground_y: float, target: Node2D, color: Color, count: int,
		icon: Texture2D = null) -> void:
	var rng := Juice.rng()
	for i in count:
		var f := _fruit_dot(color)
		f.position = (from + Vector2(rng.randi_range(-10, 10), rng.randi_range(-4, 4))).round()
		var side := -1 if i % 2 == 0 else 1  # left and right of the trunk, clear of whoever stands at its foot
		var land := Vector2(from.x + side * rng.randi_range(9, 20), ground_y - 5 - rng.randi_range(0, 6)).round()
		var shadow := ColorRect.new()
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.size = Vector2(4, 1)
		shadow.color = C_SHADOW
		shadow.z_index = 39
		shadow.position = land + Vector2(2, 5)
		shadow.visible = false
		parent.add_child(shadow)
		parent.add_child(f)
		var t := f.create_tween()
		t.tween_interval(i * 0.07)
		t.tween_callback(shadow.show)
		t.tween_property(f, "position", land, 0.26).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		for hop in [4, 1]:  # bounce
			t.tween_property(f, "position:y", land.y - hop, 0.06 + hop * 0.01).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			t.tween_property(f, "position:y", land.y, 0.06 + hop * 0.01).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.tween_interval(0.1 + i * 0.04)
		t.tween_callback(shadow.queue_free)
		if icon != null:
			t.tween_callback(_pop_as_icon.bind(f, icon, target))
		else:
			t.tween_property(f, "position:y", land.y - 6, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			t.tween_callback(_fly_to_bag.bind(f, target, Vector2(2, 2)))


## A 5x5 fruit: ink rim, its colour, a cream glint on the upper left.
static func _fruit_dot(color: Color) -> ColorRect:
	var f := ColorRect.new()
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.size = Vector2(5, 5)
	f.color = C_INK
	f.z_index = 41
	var face := ColorRect.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.color = color
	face.position = Vector2.ONE
	face.size = Vector2(3, 3)
	f.add_child(face)
	var glint := ColorRect.new()
	glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glint.color = C_CREAM
	glint.position = Vector2.ONE
	glint.size = Vector2.ONE
	f.add_child(glint)
	return f


## The landed fruit `f` turns into its 16x16 icon, which pops, rises a little and flies into the bag.
static func _pop_as_icon(f: Control, icon: Texture2D, target: Node2D) -> void:
	if not is_instance_valid(f) or f.get_parent() == null:
		return
	var n := TextureRect.new()
	n.texture = icon
	n.size = Vector2(16, 16)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.z_index = 42
	n.position = (f.position + Vector2(2, 2) - Vector2(8, 12)).round()
	f.get_parent().add_child(n)
	f.queue_free()
	Juice.pop(n, 1.4, 0.12)
	var t := n.create_tween()
	t.tween_property(n, "position:y", n.position.y - 6, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_interval(0.04)
	t.tween_callback(_fly_to_bag.bind(n, target, Vector2(8, 8)))


## A picked thing (its 16x16 icon, or a colour square without one) pops up from `at` (its feet) and flies into the
## HUD bag icon, which bumps.
static func item_to_bag(parent: Node, at: Vector2, icon: Texture2D, color: Color) -> void:
	var n: Control
	if icon != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = icon
		tex_rect.size = Vector2(16, 16)
		n = tex_rect
	else:
		var cr := ColorRect.new()
		cr.color = color
		cr.size = Vector2(4, 4)
		n = cr
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.z_index = 45
	n.position = (at - Vector2(floorf(n.size.x * 0.5), n.size.y)).round()
	parent.add_child(n)
	var t := n.create_tween()
	t.tween_property(n, "position:y", n.position.y - 10, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_interval(0.08)
	t.tween_callback(_fly_to_bag.bind(n, null, (n.size * 0.5).floor()))


## A leaf or two kicked up behind Granny's feet (`feet`, walking `dir`) on leafy ground.
static func kick_leaf(parent: Node, feet: Vector2, dir: Vector2i) -> void:
	var rng := Juice.rng()
	var b := Juice.Burst.make(parent, feet, 38)
	for i in rng.randi_range(1, 2):
		var vx := -dir.x * rng.randf_range(10.0, 22.0) + rng.randf_range(-10.0, 10.0)
		b.add(Juice.DUST, Vector2(rng.randi_range(-3, 3), -1), Vector2(vx, -rng.randf_range(30.0, 46.0) - dir.y * 6.0),
			150.0, rng.randf_range(0.32, 0.42), Color(LEAF_COLORS[rng.randi_range(0, LEAF_COLORS.size() - 1)]))


## Moves world-space `n` onto a layer over the HUD and arcs it into the bag icon (centre `half` px into `n`);
## without a HUD it hops into `fallback` (or just goes).
static func _fly_to_bag(n: Control, fallback: Node2D, half: Vector2) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree():
		return
	var bag := Hud.bag_point()
	if bag.x < 0.0:
		var from := n.position
		var t0 := n.create_tween()
		if is_instance_valid(fallback):
			var hop := func(k: float) -> void:
				if is_instance_valid(fallback):
					n.position = from.lerp(fallback.position + Vector2(-1, -14), k).round()
			t0.tween_method(hop, 0.0, 1.0, 0.22)
		t0.tween_callback(n.queue_free)
		return
	var start := n.get_global_transform_with_canvas().origin.round()
	var layer := _flight_layer(n.get_parent())
	n.reparent(layer, false)
	n.z_index = 0
	n.position = start
	var end := bag - half
	var arc := func(k: float) -> void:
		n.position = (start.lerp(end, k) + Vector2(0, -sin(k * PI) * 16.0)).round()
	var t := n.create_tween()
	t.tween_method(arc, 0.0, 1.0, FLIGHT_SECONDS).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(func() -> void: Hud.bump_bag())
	t.tween_callback(n.queue_free)


## One screen-space layer per fx parent for things in flight; it goes away with the scene.
static func _flight_layer(parent: Node) -> CanvasLayer:
	var layer := parent.get_node_or_null("BagFlight") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "BagFlight"
		layer.layer = FLIGHT_LAYER
		parent.add_child(layer)
	return layer
