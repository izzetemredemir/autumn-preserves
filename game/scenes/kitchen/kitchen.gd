extends Control
## Gray kitchen (orchestrator, before GD-KITCHEN): pick a recipe, fill the slots from the inbox and pantry,
## play the recipe's mini-game, cook, show the result card. Optional parts (mini-games, JarIcon, result card)
## are loaded by path so the scene works before they are merged.

const RESULT_CARD := "res://ui/result_card/result_card.tscn"

var _recipe := ""
var _recipes: ItemList
var _main: OptionButton
var _second: OptionButton
var _addin: OptionButton
var _info: Label
var _cook: Button
var _inbox: ItemList
var _status: Label
var _busy := false


func _ready() -> void:
	if not GameState.has_game():
		GameState.start_new(1)
		_debug_fill()
	Forage.empty_bag_to_inbox(GameState.data)
	_build()
	GameState.changed.connect(func(_k: PackedStringArray) -> void: _refresh())
	Audio.play_music("mus_kitchen")
	Audio.play_ambient("amb_hearth")
	_refresh()


func _build() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	add_child(root)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(120, 0)
	root.add_child(left)
	left.add_child(_label("KITCHEN_RECIPES"))
	_recipes = ItemList.new()
	_recipes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for id in Data.ids_up_to("recipes", 0):
		_recipes.add_item(Data.recipes()[id].name)
		_recipes.set_item_metadata(_recipes.item_count - 1, id)
	_recipes.item_selected.connect(_on_recipe)
	left.add_child(_recipes)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	mid.add_child(_label("KITCHEN_MAIN"))
	_main = OptionButton.new()
	mid.add_child(_main)
	mid.add_child(_label("KITCHEN_SECOND"))
	_second = OptionButton.new()
	mid.add_child(_second)
	mid.add_child(_label("KITCHEN_ADDIN"))
	_addin = OptionButton.new()
	mid.add_child(_addin)
	for ob in [_main, _second, _addin]:
		ob.item_selected.connect(func(_i: int) -> void: _update_check())
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(_info)
	_cook = Button.new()
	_cook.text = "KITCHEN_COOK"
	_cook.pressed.connect(_on_cook)
	mid.add_child(_cook)
	var nav := HBoxContainer.new()
	mid.add_child(nav)
	for pair in [["KITCHEN_TO_PANTRY", "pantry"], ["KITCHEN_TO_GARDEN", "garden"]]:
		var b := Button.new()
		b.text = pair[0]
		var target: String = pair[1]
		b.pressed.connect(func() -> void: _go(target))
		nav.add_child(b)
	var bed := Button.new()
	bed.text = "KITCHEN_BED"
	bed.pressed.connect(_on_bed)
	nav.add_child(bed)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(130, 0)
	root.add_child(right)
	right.add_child(_label("KITCHEN_INBOX"))
	_inbox = ItemList.new()
	_inbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_inbox)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	right.add_child(_status)


func _label(key: String) -> Label:
	var l := Label.new()
	l.text = key
	return l


func _refresh() -> void:
	var d := GameState.data
	_inbox.clear()
	for item in d.inbox:
		_inbox.add_item(_item_text(item))
	_status.text = tr("KITCHEN_STATUS") % [int(d.day), int(d.energy), int(d.coins)]
	if _recipe != "":
		_fill_slots()


func _item_text(item: Dictionary) -> String:
	match item.kind:
		"fresh":
			var v: Dictionary = GameState.data.varieties.get(item.variety, {})
			return "%s x%d" % [v.get("name", item.variety), int(item.count)]
		"nut":
			return "%s x%d" % [item.type.capitalize(), int(item.count)]
		"product":
			return ProductGen.product_name(item.key, GameState.data.varieties)
	return "?"


func _on_recipe(index: int) -> void:
	_recipe = _recipes.get_item_metadata(index)
	_fill_slots()


## Varieties with enough fresh items (inbox + pantry) for a slot spec {"groups"|"types", "count"}.
func _candidates(spec: Variant) -> Array:
	if spec == null or typeof(spec) != TYPE_DICTIONARY or spec.has("recipe"):
		return []
	var totals := {}
	var d := GameState.data
	var items: Array = d.inbox.duplicate()
	for e in d.pantry.items:
		items.append(e.item)
	for item in items:
		if item.kind != "fresh":
			continue
		var t := State.type_of_variety(item.variety)
		var ok: bool = spec.has("types") and t in spec.types
		if spec.has("groups"):
			ok = ok or Data.ingredients()[t].group in spec.groups
		if ok:
			totals[item.variety] = int(totals.get(item.variety, 0)) + int(item.count)
	var out: Array = []
	for v in totals:
		if totals[v] >= int(spec.count):
			out.append(v)
	out.sort()
	return out


func _fill_slots() -> void:
	var r: Dictionary = Data.recipes()[_recipe]
	_fill_option(_main, _candidates(r.get("main")))
	_fill_option(_second, _candidates(r.get("second")))
	_second.disabled = not r.has("second")
	_addin.clear()
	_addin.add_item(tr("KITCHEN_NO_ADDIN"))
	_addin.set_item_metadata(0, "")
	var d := GameState.data
	for a in Data.ids_up_to("addins", 0):
		var have := int(d.cupboard.get(a, 0))
		for item in d.inbox:
			if item.kind == "nut" and item.type == a:
				have += int(item.count)
		for e in d.pantry.items:
			if e.item.kind == "nut" and e.item.type == a:
				have += int(e.item.count)
		if have > 0:
			_addin.add_item("%s (%d)" % [Data.addins()[a].adjective, have])
			_addin.set_item_metadata(_addin.item_count - 1, a)
	_update_check()


func _fill_option(ob: OptionButton, ids: Array) -> void:
	ob.clear()
	for id in ids:
		var v: Dictionary = GameState.data.varieties.get(id, {})
		ob.add_item(v.get("name", id))
		ob.set_item_metadata(ob.item_count - 1, id)


func _selected(ob: OptionButton) -> String:
	if ob.disabled or ob.item_count == 0 or ob.selected < 0:
		return ""
	return str(ob.get_item_metadata(ob.selected))


func _update_check() -> void:
	if _recipe == "":
		_info.text = tr("KITCHEN_PICK_RECIPE")
		_cook.disabled = true
		return
	var c := Kitchen.check(GameState.data, _recipe, _selected(_main), _selected(_second), _selected(_addin))
	var key := ProductGen.make_key(_recipe, _slot_varieties(), _selected(_addin))
	var known: bool = GameState.data.book.variants.has(key)
	var preview := ProductGen.product_name(key, GameState.data.varieties) if known else tr("KITCHEN_NEW_VARIANT")
	_info.text = preview if c.ok else "%s\n%s" % [preview, tr(str(c.reason))]
	_cook.disabled = not c.ok or _busy


func _slot_varieties() -> Array:
	var out: Array = []
	for ob in [_main, _second]:
		var v := _selected(ob)
		if v != "":
			out.append(v)
	return out


func _on_cook() -> void:
	if _busy:
		return
	_busy = true
	_cook.disabled = true
	var d := GameState.data
	var key := ProductGen.make_key(_recipe, _slot_varieties(), _selected(_addin))
	var method: String = Data.recipes()[_recipe].method
	var types: Array = []
	for v in _slot_varieties():
		types.append(State.type_of_variety(v))
	var ctx := {"seed": Seeds.seed_for(int(d.save_seed), "minigame", int(d.day), key), "recipe": _recipe,
		"varieties": _slot_varieties(), "addin": _selected(_addin), "desc": ProductGen.describe(key, d.varieties),
		"ingredient_types": types}
	var path := "res://minigames/%s/%s.tscn" % [method, method]
	if ResourceLoader.exists(path):
		var mg: Node = load(path).instantiate()
		add_child(mg)
		mg.finished.connect(_on_minigame_done.bind(mg), CONNECT_ONE_SHOT)
		mg.start(ctx)
	else:
		_on_minigame_done({"stars": 2}, null)


func _on_minigame_done(result: Dictionary, mg: Node) -> void:
	if mg != null:
		mg.queue_free()
	var stars := clampi(int(result.get("stars", 1)), 1, 3)
	var res := Kitchen.cook(GameState.data, _recipe, _selected(_main), _selected(_second), _selected(_addin), stars)
	_busy = false
	GameState.notify(PackedStringArray(["inbox", "pantry", "cupboard", "energy", "book", "stats"]))
	if not res.get("ok", false):
		_info.text = tr(str(res.get("reason", "KITCHEN_COOK_FAILED")))
		return
	Save.save_game(GameState.data)
	if ResourceLoader.exists(RESULT_CARD):
		var card: Node = load(RESULT_CARD).instantiate()
		add_child(card)
		card.show_result(res.desc, stars, res.is_new)
		card.closed.connect(card.queue_free, CONNECT_ONE_SHOT)
	else:
		_info.text = "%s (%d)" % [res.desc.get("name", "?"), stars]


func _on_bed() -> void:
	var events := GameState.end_day()
	_status.text = tr("KITCHEN_MORNING") % [int(GameState.data.day), events.size()]
	_refresh()


func _go(target: String) -> void:
	if Router.exists(target):
		Router.goto(target)
	elif Router.exists("wild"):
		Router.goto("wild")


## Debug-only sample inventory when the scene runs alone.
func _debug_fill() -> void:
	var d := GameState.data
	for v in d.varieties:
		var t := State.type_of_variety(v)
		if Data.ingredients()[t].group != "nut" and v.ends_with("_1"):
			d.inbox.append(State.fresh(v, 5, int(Data.ingredients()[t].shelf_days)))
	d.inbox.append(State.nut("walnut", 3))
	d.cupboard["cinnamon"] = 1
