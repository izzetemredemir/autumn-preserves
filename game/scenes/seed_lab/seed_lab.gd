extends Control
## Seed Lab (GD-WILD, spec §10): type a seed, pick a biome, generate the day-1 map and pan over all of it.
## A number is used as the save seed as is; any other text is hashed. Empty = random.
## "Walk" opens the wild scene with that seed (it starts a test game when none is running).
## Uses the same renderer as the wild scene, with clearings and the special place outlined.

const BIOMES := ["forest"]  ## P1: vineyard, creek
const PAN_SPEED := 240.0
const DAY := 1

var save_seed := 0
var map: Dictionary = {}
var _pan := Vector2.ZERO
var _dragging := false

@onready var seed_edit: LineEdit = %SeedEdit
@onready var biome_pick: OptionButton = %Biome
@onready var area: Control = %MapArea
@onready var view: WildMapView = %Map
@onready var info: Label = %Info


func _ready() -> void:
	for b in BIOMES:
		biome_pick.add_item(tr("WILD_BIOME_" + String(b).to_upper()))
	%Generate.pressed.connect(_generate)
	%Random.pressed.connect(_random)
	%Walk.pressed.connect(_walk)
	%Back.pressed.connect(func() -> void: Router.goto("title"))
	seed_edit.text_submitted.connect(func(_t: String) -> void: _generate())
	area.resized.connect(_apply_pan)
	view.show_marks = true
	if Router.params.has("seed"):
		seed_edit.text = str(int(Router.params.seed))
	_generate()
	Audio.play_music("mus_seedlab")


func _process(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if v != Vector2.ZERO:
		_pan += v * PAN_SPEED * delta
		_apply_pan()


## Mouse arrives as emulated touch (project: emulate_touch_from_mouse), so drag works the same on phones.
## A press that no button took starts the drag; the drag itself is read here, before the GUI, because
## drag events are routed by their own position, which can land on the bars.
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventScreenDrag:
		_pan -= event.relative
		_apply_pan()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not event.pressed:
		_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_dragging = true
		get_viewport().gui_release_focus()


static func seed_from_text(text: String) -> int:
	var t := text.strip_edges()
	if t.is_empty():
		return Seeds.random_save_seed()
	if t.is_valid_int():
		return absi(t.to_int()) & 0x7FFFFFFF
	return Hash.fnv1a31(t)


func biome() -> String:
	return String(BIOMES[maxi(biome_pick.selected, 0)])


func _generate() -> void:
	save_seed = seed_from_text(seed_edit.text)
	seed_edit.text = str(save_seed)
	var varieties := VarietyGen.generate_all(save_seed, 0)
	map = WildGen.generate(save_seed, DAY, biome(), "sunny", varieties)
	view.show_map(map, varieties)
	_pan = Vector2.ZERO
	_apply_pan()
	if map.is_empty():
		info.text = ""
		return
	var bushes := 0
	for p in map.pickups:
		if String(p.get("kind", "")) == "bush":
			bushes += 1
	var text := tr("WILD_LAB_INFO") % [int(map.seed), map.fruit_trees.size(), bushes, map.pickups.size() - bushes]
	var sp: Dictionary = map.get("special", {})
	if not sp.is_empty():
		text += "  " + tr("WILD_SPECIAL_" + String(sp.get("kind", "")).to_upper())
	info.text = text


func _random() -> void:
	seed_edit.text = str(Seeds.random_save_seed())
	_generate()


func _walk() -> void:
	Router.goto("wild", {"biome": biome(), "seed": save_seed})


## Integer pan, clamped to the map; a map smaller than the area is centred.
func _apply_pan() -> void:
	var view_size := area.size
	var map_size := Vector2(view.size_px())
	var lim := (map_size - view_size).max(Vector2.ZERO)
	_pan = _pan.clamp(Vector2.ZERO, lim)
	var centre := ((view_size - map_size) * 0.5).max(Vector2.ZERO).floor()
	view.position = (centre - _pan).round()
