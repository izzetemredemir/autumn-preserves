extends "res://scenes/market/crowd_view.gd"
## LIVING-TOWN · Plays a TownCrowd back. Like the market's CrowdView, but every person runs on their own clock of the
## repeating loop (TownCrowd.local_time), Vito and Edith wear their own looks, and whoever has a bubble turns to talk.

## Person id -> scene time until which they talk (set by the square when their line is said).
var talk: Dictionary = {}


func step(t: float) -> void:
	for p in _people:
		var id := int(p.id)
		var lt := TownCrowd.local_time(p, t)
		if lt < 0.0:
			if _nodes.has(id):
				(_nodes[id] as Node2D).queue_free()
				_nodes.erase(id)
			continue
		var node := _node(p)
		var st := _step_at(p, lt)
		if st.is_empty():
			continue
		var at: Vector2 = st.from
		if String(st.do) == "walk":
			var span := maxf(0.001, float(st.t1) - float(st.t0))
			at = (st.from as Vector2).lerp(st.to, clampf((lt - float(st.t0)) / span, 0.0, 1.0))
		node.position = (at + (p.offset as Vector2)).round()
		_pose(node, p, st, lt)
		if float(talk.get(id, -1.0)) > t and String(st.do) not in ["walk", "chat"]:
			var face := String(st.face)
			node.call("show_pose", "front" if face == "back" else face, "talk", floori(t * 5.0) % 2)


## True for Vito and Edith.
func is_neighbour(p: Dictionary) -> bool:
	return String(p.get("npc", "")) != ""


func _node(p: Dictionary) -> Node2D:
	var npc := String(p.get("npc", ""))
	var id := int(p.id)
	if npc == "" or _nodes.has(id):
		return super(p)
	var l := Villager.vendor_look(npc)
	l.umbrella = bool(p.get("umbrella", false))
	var v := Villager.new()
	v.name = "Npc_" + npc
	v.setup(l)
	world.add_child(v)
	_nodes[id] = v
	return v
