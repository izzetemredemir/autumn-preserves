extends Node
## Autoload "Save": JSON save file in user:// (tech-spec §4). Numbers come back as floats; State keeps ints small (31-bit seeds).

const PATH := "user://save.json"
## The save as it was at bedtime on the farewell night (spec §7.12): kept for support, never shown in a menu.
const DAY99_PATH := "user://save_day99.json"


func has_save(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


func save_game(state: Dictionary, path: String = PATH) -> bool:
	if state.get("flags", {}).get("temp", false):
		return true  # temporary games (GameState.start_temp) are never saved
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Save: cannot write " + path)
		return false
	f.store_string(JSON.stringify(state, "\t"))
	return true


func backup_day99(state: Dictionary) -> bool:
	return save_game(state, DAY99_PATH)


func load_game(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func delete(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
