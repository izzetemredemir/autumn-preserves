extends Node
## Autoload "DemoDirector" (DEMO-02, from the game-showcase skill's demo_director.gd): replays a scripted demo so
## recordings and live pitches are repeatable. Without `--demo` it does nothing and stops processing.
##   godot --path game --audio-driver Dummy -- --demo res://demo/pitch.json     (live, muted dev run)
##   bash tools/scripts/record.sh pitch                                          (Movie Maker recording)
##
## Timeline JSON, a list of events run in time order:
##   {"t": 1.0, ...}   seconds since start; or {"dt": 2.5, ...} seconds after the previous event
##   {"do": "seed_lab", "args": [452]}                 a route step of res://demo/demo_steps.gd (game methods)
##   {"call": "@scene/%Grow", "method": "grab_focus"}  a node method; "@scene" is the current scene
##   {"tap": [240, 150]}  a click at base-res coords · {"action": "ui_accept"} · {"quit": true}
##   "note": free text, ignored (says what the viewer sees)
## Events at t <= 0 run in _ready(), before the main scene loads (start a recording inside a scene).
## Time is counted in frames of unscaled time, so a step that fast-forwards (Engine.time_scale) keeps the
## timeline in step.

const STEPS := "res://demo/demo_steps.gd"

var steps: Node = null
var _events: Array = []
var _time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var i := args.find("--demo")
	if i == -1 or i + 1 >= args.size():
		set_process(false)
		return
	var path := args[i + 1]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("DemoDirector: bad timeline %s" % path)
		set_process(false)
		return
	_events = _timed(parsed)
	if ResourceLoader.exists(STEPS):
		steps = (load(STEPS) as GDScript).new()
		steps.name = "Steps"
		add_child(steps)
	print("DemoDirector: %s, %d events, %.1f s" % [path, _events.size(), _end_time()])
	while not _events.is_empty() and float(_events[0]["t"]) <= 0.0:
		_run(_events.pop_front())


## Resolves "dt" into absolute "t" (in file order), then sorts by time (stable for equal times).
static func _timed(list: Array) -> Array:
	var out: Array = []
	var prev := 0.0
	for e: Variant in list:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var ev: Dictionary = e
		var t: float = prev + float(ev["dt"]) if ev.has("dt") else float(ev.get("t", prev))
		ev["t"] = t
		ev["_i"] = out.size()
		prev = t
		out.append(ev)
	out.sort_custom(_before)
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	return float(a.t) < float(b.t) or (float(a.t) == float(b.t) and int(a._i) < int(b._i))


func _end_time() -> float:
	return float(_events[-1]["t"]) if not _events.is_empty() else 0.0


func _process(delta: float) -> void:
	_time += delta / maxf(Engine.time_scale, 0.001)
	while not _events.is_empty() and float(_events[0]["t"]) <= _time:
		_run(_events.pop_front())


func _run(e: Dictionary) -> void:
	if e.has("quit"):
		Engine.time_scale = 1.0
		get_tree().quit()
	elif e.has("do"):
		var m := String(e["do"])
		if steps != null and steps.has_method(m):
			steps.callv(m, e.get("args", []))
		else:
			push_warning("DemoDirector: no step %s" % m)
	elif e.has("call"):
		var node := _node(String(e["call"]))
		if node and node.has_method(e["method"]):
			node.callv(e["method"], e.get("args", []))
		else:
			push_warning("DemoDirector: missing %s.%s" % [e["call"], e["method"]])
	elif e.has("tap"):
		var pos := Vector2(float(e["tap"][0]), float(e["tap"][1]))
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = pos
			ev.global_position = pos
			Input.parse_input_event(ev)
	elif e.has("action"):
		for pressed in [true, false]:
			var ev := InputEventAction.new()
			ev.action = e["action"]
			ev.pressed = pressed
			Input.parse_input_event(ev)


## "@scene" and "@scene/<path>" start at the current scene (unique names work: "@scene/%Grow"); else a tree path.
func _node(path: String) -> Node:
	if path == "@scene" or path.begins_with("@scene/"):
		var scene := get_tree().current_scene
		if scene == null:
			return null
		return scene if path == "@scene" else scene.get_node_or_null(NodePath(path.substr(7)))
	return get_node_or_null(NodePath(path))
