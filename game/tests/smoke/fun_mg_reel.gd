extends Node
## FUN-MG recording reel (12 s): stir, press, knead, pack jar, each driven by its own autoplay. Run through Movie Maker:
##   bash tools/pipeline/capture.sh game builds/media/fun_mg --seconds 12 --png --gif --gif-scale 2 --gif-fps 15 \
##     --scene res://tests/smoke/fun_mg_reel.tscn -- --sound
const P := "res://minigames/%s/%s.tscn"


var _sync: Node  ## press / knead run on the wall clock; Movie Maker renders slower than real time, so pin them to frames
var _sync_t := 0.0
var _sync_start := 0.0


func _process(delta: float) -> void:
	if _sync != null and is_instance_valid(_sync):
		_sync_t += delta
		var us := int(Time.get_ticks_usec() - (_sync_start + _sync_t) * 1e6)
		if "_t0_usec" in _sync:
			_sync._t0_usec = us
		else:
			_sync._t0 = us


func _pin(n: Node, start_s: float) -> void:
	_sync = n
	_sync_t = 0.0
	_sync_start = start_s


func _ready() -> void:
	Juice.rng().seed = 5
	var stir := _spawn("stir_pot")
	stir.start({"seed": 7, "recipe": "jam", "duration": 8.0, "autoplay": true,
		"desc": {"appearance": {"fill": ["a22512", "c94d2e", "e19064"]}}})
	stir.ready_left = 0.05
	stir.bar = 0.5
	await get_tree().create_timer(3.4).timeout
	stir.queue_free()
	var press := _spawn("press")
	press.start({"seed": 7, "recipe": "juice", "autoplay": true, "desc": {"appearance": {"fill": ["a22512", "c94d2e", "e19064"]}}})
	_pin(press, 1.1)  # skip most of the lead-in
	await get_tree().create_timer(3.8).timeout
	press.queue_free()
	var knead := _spawn("knead")
	knead.start({"seed": 7, "recipe": "pie", "autoplay": true, "knead_time": 6.0, "trace_time": 4.0,
		"desc": {"appearance": {"fill": ["62272c", "a22512", "c94d2e"]}}})
	knead._set_phase(2)  # Knead.Phase.KNEAD (no class refs: the parse check loads this without autoloads)
	_pin(knead, 0.0)
	await get_tree().create_timer(2.6).timeout
	knead.queue_free()
	var jar := _spawn("pack_jar")
	jar.start({"seed": 7, "recipe": "pickle", "ingredient_types": ["cucumber", "carrot", "beet", "cabbage"],
		"desc": {"appearance": {"fill": "7a9a3a"}}})
	for i in 40:
		jar._set_piece_x([0, 3, 1, 4, 2, 5][i % 6])
		jar._drop_piece()
		await get_tree().create_timer(0.3).timeout


func _spawn(game: String) -> Node:
	var n: Node = (load(P % [game, game]) as PackedScene).instantiate()
	add_child(n)
	return n
