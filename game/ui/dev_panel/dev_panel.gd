class_name DevPanel
extends CanvasLayer
## Debug-only panel (spec §10), toggled with F1 (action "dev_panel"). `DevPanel.ensure()` adds it to the tree
## root once, and only in debug builds. Coins, energy, items, skip a day, run the night, demo save, print seed,
## jump to day 99 (the next night is the farewell, spec §7.12).

const COINS := 100
const ENERGY := 20

var _panel: PanelContainer
var _status: Label
var _game_buttons: Array[Button] = []
var _demo: Button


static func ensure() -> void:
	if not OS.is_debug_build():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.get_first_node_in_group("dev_panel") != null:
		return
	var p := DevPanel.new()
	p.add_to_group("dev_panel")
	tree.root.add_child.call_deferred(p)


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/theme.tres")
	add_child(root)
	_panel = PanelContainer.new()
	_panel.position = Vector2(4, 64)
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_panel.add_child(box)
	var head := Label.new()
	head.text = "UI_DEV_TITLE"
	head.theme_type_variation = &"Heading"
	box.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	_add(grid, "UI_DEV_COINS", _on_coins, true)
	_add(grid, "UI_DEV_ENERGY", _on_energy, true)
	_add(grid, "UI_DEV_ITEMS", _on_items, true)
	_add(grid, "UI_DEV_SKIP_DAY", _on_skip_day, true)
	_add(grid, "UI_DEV_NIGHT", _on_night, true)
	_add(grid, "UI_DEV_SEED", _on_seed, true)
	_add(grid, "UI_DEV_UNLOCK_P1", _on_unlock_p1, true)
	_add(grid, "UI_DEV_DAY99", _on_day99, true)
	_demo = _add(grid, "UI_DEV_DEMO", _on_demo, false)
	_add(grid, "UI_DEV_CLOSE", func() -> void: _panel.visible = false, false)
	_status = Label.new()
	_status.custom_minimum_size = Vector2(150, 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


func _add(parent: Control, key: String, cb: Callable, needs_game: bool) -> Button:
	var b := Button.new()
	b.text = key
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	if needs_game:
		_game_buttons.append(b)
	return b


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("dev_panel"):
		_panel.visible = not _panel.visible
		if _panel.visible:
			_refresh()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	for b in _game_buttons:
		b.disabled = not GameState.has_game()
	_demo.disabled = not FileAccess.file_exists(DevTools.DEMO_SAVE)
	if GameState.has_game():
		_say(tr("UI_DEV_STATUS") % [int(GameState.data.day), int(GameState.data.save_seed)])
	else:
		_say(tr("UI_DEV_NO_GAME"))


func _say(text: String) -> void:
	_status.text = text


func _on_coins() -> void:
	GameState.data.coins = int(GameState.data.coins) + COINS
	GameState.notify(PackedStringArray(["coins"]))
	_refresh()


func _on_energy() -> void:
	var d := GameState.data
	d.energy = mini(int(d.energy) + ENERGY, int(d.energy_max))
	GameState.notify(PackedStringArray(["energy"]))
	_refresh()


func _on_items() -> void:
	var n := DevTools.give_items(GameState.data)
	GameState.notify(PackedStringArray(["inbox", "cupboard"]))
	_say(tr("UI_DEV_GAVE") % n)


func _on_skip_day() -> void:
	var events := GameState.end_day()
	print("[dev] day %d, %d night events: %s" % [int(GameState.data.day), events.size(), events])
	Hud.toast("UI_DEV_DAY", [int(GameState.data.day)])
	_refresh()


func _on_night() -> void:
	_panel.visible = false
	Night.start()


func _on_unlock_p1() -> void:
	var n := DevTools.unlock_p1(GameState.data)
	GameState.notify(PackedStringArray(["unlocks", "upgrades", "varieties", "cupboard", "inbox"]))
	_say(tr("UI_DEV_P1_DONE") % n)


## Spec §7.12: jump to day 99, so the next night is the farewell (the save is not closed, nothing else changes).
func _on_day99() -> void:
	var d := GameState.data
	if GameState.is_memory() or Farewell.is_completed(d):
		_say(tr("UI_DEV_DAY99_DONE"))
		return
	d.day = maxi(int(d.day), Farewell.LAST_DAY)
	GameState.notify(PackedStringArray(["day"]))
	_refresh()


func _on_seed() -> void:
	var s := int(GameState.data.save_seed)
	print("[dev] save_seed = %d" % s)
	DisplayServer.clipboard_set(str(s))
	_say(tr("UI_DEV_SEED_COPIED") % s)


func _on_demo() -> void:
	var d := DevTools.load_demo()
	if d.is_empty():
		_say(tr("UI_DEV_DEMO_BAD"))
		return
	GameState.data = d
	Save.save_game(d)
	GameState.notify(PackedStringArray(["*"]))
	_panel.visible = false
	GrannyTodo.ensure()
	Transition.go(Transition.home_scene())
