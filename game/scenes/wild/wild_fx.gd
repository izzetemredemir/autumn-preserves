extends RefCounted
## World-space feedback for walked scenes (GD-WILD): text bubbles, leaf bursts, fruit flying into the bag.
## Everything moves on whole pixels and frees itself. Visual randomness only, never game state.

const LEAF_COLORS := ["a22512", "c94d2e", "e19064", "b66813", "e5bd7f"]


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


## Leaves bursting out of a canopy centred at `at`; they start within `spread` px of it (half width, half height).
static func leaf_burst(parent: Node, at: Vector2, count := 10, spread := Vector2i(8, 6)) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var leaf := ColorRect.new()
		leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		leaf.size = Vector2(2, 2)
		leaf.color = Color(LEAF_COLORS[rng.randi_range(0, LEAF_COLORS.size() - 1)])
		leaf.z_index = 40
		leaf.position = at + Vector2(rng.randi_range(-spread.x, spread.x), rng.randi_range(-spread.y, spread.y))
		parent.add_child(leaf)
		var out := leaf.position + Vector2(rng.randi_range(-spread.x - 14, spread.x + 14), rng.randi_range(-spread.y - 8, 4))
		var down := out + Vector2(rng.randi_range(-4, 4), rng.randi_range(14, 26))
		var t := leaf.create_tween()
		t.tween_property(leaf, "position", out.round(), 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(leaf, "position", down.round(), rng.randf_range(0.45, 0.7)).set_ease(Tween.EASE_IN)
		t.tween_callback(leaf.queue_free)


## `count` fruit squares drop from `from` to the ground at `ground_y`, then hop into `target` (Granny).
static func fruit_to_bag(parent: Node, from: Vector2, ground_y: float, target: Node2D, color: Color, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var f := ColorRect.new()
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		f.size = Vector2(3, 3)
		f.color = color
		f.z_index = 41
		f.position = from + Vector2(rng.randi_range(-10, 10), rng.randi_range(-4, 4))
		parent.add_child(f)
		var land := Vector2(f.position.x + rng.randi_range(-6, 6), ground_y - rng.randi_range(0, 4))
		var t := f.create_tween()
		t.tween_interval(i * 0.08)
		t.tween_property(f, "position", land.round(), 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.tween_interval(0.15)
		var fly := func(k: float) -> void:
			if is_instance_valid(target):
				f.position = land.lerp(target.position + Vector2(-1, -14), k).round()
		t.tween_method(fly, 0.0, 1.0, 0.22)
		t.tween_callback(f.queue_free)
