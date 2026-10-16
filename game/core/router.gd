extends Node
## Autoload "Router": scene flow by id (tech-spec §7). The next scene reads Router.params in _ready().

signal scene_changed(id: String)

const SCENES := {
	"title": "res://scenes/title/title.tscn",
	"seed_lab": "res://scenes/seed_lab/seed_lab.tscn",
	"garden": "res://scenes/garden/garden.tscn",
	"wild": "res://scenes/wild/wild.tscn",
	"kitchen": "res://scenes/kitchen/kitchen.tscn",
	"pantry": "res://scenes/pantry/pantry.tscn",
	"town": "res://scenes/town/town.tscn",
}

var params: Dictionary = {}
var current := ""


func exists(id: String) -> bool:
	return SCENES.has(id) and ResourceLoader.exists(SCENES[id])


func goto(id: String, p: Dictionary = {}) -> void:
	if not exists(id):
		push_warning("Router: no scene for '%s' yet" % id)
		return
	params = p
	current = id
	get_tree().change_scene_to_file(SCENES[id])
	scene_changed.emit(id)


## Global hotkey: the recipe book opens from any in-game scene (the open overlay closes itself first).
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("book") or current in ["", "title"] or not GameState.has_game():
		return
	var path := "res://ui/book/book.gd"
	if ResourceLoader.exists(path):
		load(path).open()
		get_viewport().set_input_as_handled()
