extends Node
## Autoload "Save": JSON save file in user:// (tech-spec §4). Numbers come back as floats; State keeps ints small (31-bit seeds).

const PATH := "user://save.json"
## The save as it was at bedtime on the farewell night (spec §7.12): kept for support, never shown in a menu.
const DAY99_PATH := "user://save_day99.json"


func has_save(path: String = PATH) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(_bak(path))


func _bak(path: String) -> String:
	return path.get_basename() + ".bak"


func _read_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Atomic: write path.tmp, keep the previous good file as .bak, then rename the tmp over the save.
func save_game(state: Dictionary, path: String = PATH) -> bool:
	if state.get("flags", {}).get("temp", false):
		return true  # temporary games (GameState.start_temp) are never saved
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Save: cannot write " + tmp)
		return false
	f.store_string(JSON.stringify(state, "\t"))
	f.close()
	var g_tmp := ProjectSettings.globalize_path(tmp)
	var g_path := ProjectSettings.globalize_path(path)
	if _read_dict(tmp).is_empty():
		push_error("Save: temp file did not verify, keeping the old save")
		DirAccess.remove_absolute(g_tmp)
		return false
	if not _read_dict(path).is_empty():  # never let a corrupt main file replace a good backup
		DirAccess.copy_absolute(g_path, ProjectSettings.globalize_path(_bak(path)))
	if DirAccess.rename_absolute(g_tmp, g_path) != OK:
		DirAccess.remove_absolute(g_path)
		if DirAccess.rename_absolute(g_tmp, g_path) != OK:
			push_error("Save: cannot rename " + tmp)
			return false
	return true


func backup_day99(state: Dictionary) -> bool:
	return save_game(state, DAY99_PATH)


func load_game(path: String = PATH) -> Dictionary:
	var d := _read_dict(path)
	if not d.is_empty():
		State.normalize_stacks(d)
		return d
	var bak := _read_dict(_bak(path))
	if not bak.is_empty():
		print("Save: %s missing or unreadable, loaded the backup %s" % [path, _bak(path)])
		State.normalize_stacks(bak)
		return bak
	return {}


func delete(path: String = PATH) -> void:
	for p in [path, _bak(path), path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
