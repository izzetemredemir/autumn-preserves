class_name ForestSurpriseLayer
extends Node
## FUN-FOREST · Builds today's forest surprises (ForestSurprises.plan) into the wild map's y-sorted objects node and
## plays what happens when one is taken: rustling bush (E / tap: a critter hops away or a bonus pickup), leaf pile
## (walk through it or use it: FEEL's leaf burst and a soft crunch, some hide a mushroom or a coin), lucky sparkle
## (at most one a day, a small celebration). The wild scene only forwards input:
##   at_point(p) / at_cell(c) / use(n) / interact(cell) / stepped(cell).
## `species_cb(type)` opens the "New species!" card. Consumed ones stay gone for the day (state.wild_today).

## Loaded at run time: wild_fx.gd reaches the autoloads, which a standalone parse check (--check-only) does not have.
var Fx: GDScript = load("res://scenes/wild/wild_fx.gd")
const SHEETS := {
	"squirrel": [preload("res://assets/sprites/critters/critter_squirrel.png"), 4, Vector2i(12, 12)],
	"hedgehog": [preload("res://assets/sprites/critters/critter_hedgehog.png"), 3, Vector2i(12, 8)],
}

var view: WildMapView
var granny: Node2D  ## the Granny (untyped: her script reaches the autoloads, see Fx)
var species_cb := Callable()
var notify_cb := Callable()  ## GameState.notify (the autoload is not visible to class_name scripts in -s smoke runs)
var state: Dictionary = {}
var entries: Array = []  ## the day's whole plan
var nodes: Array[ForestSurprise] = []


static func attach(view_: WildMapView, granny_: Node2D, map: Dictionary, state: Dictionary,
		species_cb_ := Callable(), notify_cb_ := Callable()) -> ForestSurpriseLayer:
	var layer := ForestSurpriseLayer.new()
	layer.name = "Surprises"
	layer.view = view_
	layer.granny = granny_
	layer.species_cb = species_cb_
	layer.notify_cb = notify_cb_
	layer.state = state
	view_.objects.add_child(layer)
	layer.entries = ForestSurprises.plan(map, int(state.save_seed), int(state.day), state.get("varieties", {}))
	for e: Dictionary in ForestSurprises.remaining(state, layer.entries):
		var n := ForestSurprise.new()
		n.setup(e)
		view_.objects.add_child(n)
		layer.nodes.append(n)
	return layer


func _process(_delta: float) -> void:
	if granny == null or not is_instance_valid(granny):
		return
	var facing: Vector2i = granny.facing_cell() if not granny.is_moving() else Vector2i(-1000, -1000)
	for n in nodes:
		if is_instance_valid(n):
			n.highlighted = not n.gone and n.cell == facing


func at_cell(cell: Vector2i) -> ForestSurprise:
	for n in nodes:
		if is_instance_valid(n) and n.usable() and n.cell == cell:
			return n
	return null


func at_point(p: Vector2) -> ForestSurprise:
	var best: ForestSurprise = null
	for n in nodes:
		if is_instance_valid(n) and n.usable() and n.hit_rect().has_point(p):
			if best == null or n.position.y > best.position.y:
				best = n
	return best


## E on `cell` (the tile Granny faces): true when a surprise was there and got used.
func interact(cell: Vector2i) -> bool:
	var n := at_cell(cell)
	if n == null:
		return false
	use(n)
	return true


## Granny entered `cell`: a pile bursts, a sparkle is picked up. (A bush is only used on purpose.)
func stepped(cell: Vector2i) -> void:
	var n := at_cell(cell)
	if n != null and n.kind != "bush":
		use(n)


func use(n: ForestSurprise) -> void:
	if not is_instance_valid(n) or not n.usable():
		return
	var res := ForestSurprises.collect(state, n.entry)
	if not bool(res.ok):
		if String(res.reason) == "UI_BAG_FULL":
			if n.kind == "bush":
				n.nudge()
			_sfx("sfx_bag_full")
			Fx.bubble(view.fx, n.top(), tr("UI_BAG_FULL"))
		return
	n.take()
	var rw: Dictionary = res.reward
	var fx := view.fx
	match n.kind:
		"bush":
			granny.act("pick")
			_sfx("sfx_bush_rustle")
			Fx.leaf_burst(fx, n.position + Vector2(0, -9), 7, Vector2i(7, 5))
		"pile":
			_sfx("sfx_step_leaves")
			Fx.leaf_burst(fx, n.position + Vector2(0, -4), 14, Vector2i(8, 3))
			Juice.dust_puff(fx, n.position, 6)
		"sparkle":
			_sfx("sfx_sparkle")
			Juice.sparkle(fx, Rect2(n.position + Vector2(-14, -26), Vector2(28, 24)), 12)
			Juice.dither_flash(fx, Rect2(n.position + Vector2(-16, -24), Vector2(32, 24)))
	_reward_fx(n, res)
	if notify_cb.is_valid():
		notify_cb.call(PackedStringArray(["bag", "coins", "wild_today", "found_varieties", "species_seen", "stats"]))


func _reward_fx(n: ForestSurprise, res: Dictionary) -> void:
	var rw: Dictionary = res.reward
	var from := n.position + Vector2(0, -6)
	match String(rw.get("t", "none")):
		"critter":
			var kind := String(rw.critter)
			_critter_away(kind, n.position)
			Fx.bubble(view.fx, n.top(), tr("WILD_SURPRISE_" + kind.to_upper()))
		"coins":
			_sfx("sfx_coins_gain")
			Fx.bubble(view.fx, n.top(), "+%d" % int(rw.n), 0.6)
			_toast("WILD_SURPRISE_COIN", [int(rw.n)])
		"nut", "item":
			var item: Dictionary = (res.items as Array)[0]
			var type := String(rw.get("type", ""))
			var variety := String(rw.get("variety", ""))
			if variety != "":
				type = String(state.varieties.get(variety, {}).get("type", rw.get("species", "")))
			Fx.item_to_bag(view.fx, from, IconLib.ingredient(type), Color("c94d2e"))
			_sfx("sfx_bag_add")
			Fx.bubble(view.fx, n.top(), "+%d" % int(item.count), 0.6)
			var species := String(rw.get("species", ""))
			if species != "" and SpeciesGen.mark_seen(state, species):
				if species_cb.is_valid():
					species_cb.call(species)
			elif n.kind == "sparkle":
				_toast("WILD_SURPRISE_SPARKLE", [_name(variety)])
			elif not (res.new as Array).is_empty():
				_toast("WILD_NEW_VARIETY", [_name(variety)])
				_sfx("sfx_sparkle")
			elif n.kind == "pile":
				_toast("WILD_SURPRISE_MUSHROOM", [_name(variety)])
			elif String(rw.t) == "nut":
				_toast("WILD_SURPRISE_NUTS", [int(item.count)])
			else:
				_toast("WILD_SURPRISE_FOUND", [_name(variety)])
		_:
			pass


## Audio is an autoload; class_name scripts reach it through the tree (scripted smoke runs compile them first).
func _sfx(id: String) -> void:
	var a := get_tree().root.get_node_or_null("Audio")
	if a != null:
		a.play_sfx(id)


func _name(variety: String) -> String:
	var v: Dictionary = state.varieties.get(variety, {})
	return VarietyGen.display_name(v) if not v.is_empty() else variety


## The critter pops out and hops (squirrel) or scuttles (hedgehog) away from Granny, then vanishes in a puff of dust.
func _critter_away(kind: String, feet: Vector2) -> void:
	var sheet: Array = SHEETS[kind]
	var fsz: Vector2i = sheet[2]
	var s := Sprite2D.new()
	s.texture = sheet[0]
	s.hframes = int(sheet[1])
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.centered = false
	s.offset = Vector2(-fsz.x * 0.5, -fsz.y)
	s.position = feet + Vector2(0, -2)
	var dir := 1.0 if feet.x >= granny.position.x else -1.0
	s.flip_h = dir > 0.0  # the sheets face left
	s.frame = 2 if kind == "squirrel" else 0
	view.objects.add_child(s)
	var hops := 5 if kind == "squirrel" else 8
	var step := 9.0 if kind == "squirrel" else 5.0
	var per := 0.15 if kind == "squirrel" else 0.12
	var y0 := s.position.y
	var tx := s.create_tween()
	tx.tween_property(s, "position:x", s.position.x + dir * step * hops, per * hops)
	var ty := s.create_tween()
	for i in hops:
		if kind == "squirrel":
			ty.tween_callback(func() -> void: s.frame = 3)
			ty.tween_property(s, "position:y", y0 - 6, per * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			ty.tween_property(s, "position:y", y0, per * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			ty.tween_callback(func() -> void: s.frame = 2)
		else:
			ty.tween_callback(func() -> void: s.frame = i % 2)
			ty.tween_property(s, "position:y", y0 - 1, per * 0.5)
			ty.tween_property(s, "position:y", y0, per * 0.5)
	ty.tween_callback(func() -> void:
		Juice.dust_puff(view.fx, Vector2(s.position.x, y0 + 2), 4)
		s.queue_free())


func _toast(key: String, args := []) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.show_toast(key, args)
