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


## PAUSE-MENU: writes the save now (Save and back to title, Quit). Temporary games and Memory mode are never
## written (Save.save_game skips flags.temp). False when nothing was written.
func save_now() -> bool:
	if not has_game() or bool(data.get("flags", {}).get("temp", false)):
		return false
	return Save.save_game(data)


## Loads the save. A completed one (the farewell, spec §7.12) opens only in Memory mode: see is_memory().
func load_saved() -> bool:
	var d := Save.load_game()
	if d.is_empty():
		return false
	data = d
	VarietyGen.ensure_types(data.varieties, int(data.save_seed))  # P1 types (cabbage, grape...) for older saves
	if Farewell.is_completed(data):
		data.flags["memory"] = true
		data.flags["temp"] = true  # Save.save_game skips it: the closed save is never written back
	changed.emit(PackedStringArray(["*"]))
	return true


## Memory mode: a completed save, pantry and book to browse; the day never moves on and nothing is saved.
func is_memory() -> bool:
	return Farewell.is_memory(data)


## The farewell has been watched once (from then on it can be skipped). Written even in Memory mode.
func save_farewell_seen() -> void:
	if not has_game():
		return
	data.flags["farewell_seen"] = true
	if not is_memory():
		Save.save_game(data)
		return
	var disk := data.duplicate(true)
	disk.flags.erase("memory")
	disk.flags.erase("temp")
	Save.save_game(disk)


## Runs the night (spec §9), autosaves, starts the next day. Returns the night's events.
## Memory mode: nothing happens. The night from day 99 to 100 is the farewell (spec §7.12): the day-99 save is kept
## as Save.DAY99_PATH, the save is closed (flags.completed) and the farewell scene takes over under the night cover.
func end_day() -> Array:
	var night := Farewell.night(data)  # DayEnd, or the farewell night, or nothing in Memory mode
	match String(night.kind):
		"memory":
			return []
		"farewell":
			Save.backup_day99(night.backup)
			Save.save_game(data)
			changed.emit(PackedStringArray(["*"]))
			Router.goto.call_deferred("farewell", {"mode": "play"})
			return []
	Save.save_game(data)
	changed.emit(PackedStringArray(["*"]))
	day_started.emit(int(data.day))
	return night.events
