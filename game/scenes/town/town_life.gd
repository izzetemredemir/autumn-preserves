extends "res://scenes/market/market_life.gd"
## LIVING-TOWN · The market's square life on the town square (same sheets): pigeons pecking by the notice board and the
## flower pots, sparrows on the board roof and the fence, the dog trotting between its own spots (layout "dog_spots"),
## the lantern by the post office and falling leaves. The shop panels hide the lower half of the screen, so the leaves
## start again as soon as they pass the panel's top edge and a few more fall.

const MORE_LEAVES := 4
const LEAF_END := 150.0


func _setup_dog() -> void:
	super()
	if _dog.is_empty():
		return
	var spots: Array = []
	for p in layout.get("dog_spots", []):
		spots.append(ML.v(p))
	if not spots.is_empty():
		_dog.spots = spots


func _setup_leaves() -> void:
	super()
	if _leaf_frames.is_empty():
		return
	for i in MORE_LEAVES:
		_leaves.append(_new_leaf(_rng.randf_range(-20.0, LEAF_END)))
	for l in _leaves:
		l.y = fposmod(float(l.y), LEAF_END)


func _step_leaves(dt: float) -> void:
	for i in _leaves.size():
		var l: Dictionary = _leaves[i]
		l.y = float(l.y) + float(l.v) * dt
		l.ph = float(l.ph) + dt * 2.2
		if float(l.y) > LEAF_END:
			_leaves[i] = _new_leaf(-6.0)
