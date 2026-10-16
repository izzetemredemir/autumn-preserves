extends Node
## Autoload "GameState": the live save model (tech-spec §4). Rules live in res://sim; scenes call them
## with `GameState.data`, then call notify() with the top-level keys they changed.

signal changed(keys: PackedStringArray)
signal day_started(day: int)

var data: Dictionary = {}


func has_game() -> bool:
	return not data.is_empty()


func notify(keys: PackedStringArray) -> void:
	changed.emit(keys)


func start_new(save_seed: int) -> void:
	data = State.new_game(save_seed)
	VarietyGen.ensure_types(data.varieties, save_seed)
	Save.save_game(data)
	changed.emit(PackedStringArray(["*"]))
	day_started.emit(int(data.day))


## A throwaway game (Seed Lab walks, scenes run alone): never written to disk, so it can't overwrite a real save.
func start_temp(save_seed: int) -> void:
	data = State.new_game(save_seed)
	VarietyGen.ensure_types(data.varieties, save_seed)
	data.flags["temp"] = true
	changed.emit(PackedStringArray(["*"]))
	day_started.emit(int(data.day))


func load_saved() -> bool:
	var d := Save.load_game()
	if d.is_empty():
		return false
	data = d
	VarietyGen.ensure_types(data.varieties, int(data.save_seed))  # P1 types (cabbage, grape...) for older saves
	changed.emit(PackedStringArray(["*"]))
	return true


## Runs the night (spec §9), autosaves, starts the next day. Returns the night's events.
func end_day() -> Array:
	var events := DayEnd.run(data)
	Save.save_game(data)
	changed.emit(PackedStringArray(["*"]))
	day_started.emit(int(data.day))
	return events
