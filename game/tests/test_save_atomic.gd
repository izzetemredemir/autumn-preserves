extends "res://tests/_runner/test_case.gd"
## FIX-TECH: atomic saves with a .bak; a corrupt or missing main file loads the backup.

const SaveScript := preload("res://core/save.gd")
const P := "user://test_atomic_save.json"


var S = SaveScript.new()


func _clean() -> void:
	S.delete(P)


func test_round_trip_leaves_no_tmp() -> void:
	_clean()
	assert_true(S.save_game({"day": 3, "coins": 10}, P))
	assert_eq(int(S.load_game(P).day), 3)
	assert_false(FileAccess.file_exists(P + ".tmp"), "tmp renamed away")
	_clean()


func test_second_save_keeps_the_first_as_backup() -> void:
	_clean()
	S.save_game({"day": 1}, P)
	S.save_game({"day": 2}, P)
	assert_eq(int(S.load_game(P).day), 2)
	assert_true(FileAccess.file_exists("user://test_atomic_save.bak"))
	_clean()


func test_corrupt_main_loads_the_backup() -> void:
	_clean()
	S.save_game({"day": 1}, P)
	S.save_game({"day": 2}, P)
	var f := FileAccess.open(P, FileAccess.WRITE)
	f.store_string("{\"day\": 5, \"coi")
	f.close()
	assert_eq(int(S.load_game(P).day), 1, "backup (the previous save)")
	S.save_game({"day": 3}, P)  # a corrupt main must not replace the good backup
	assert_eq(int(S.load_game(P).day), 3)
	_clean()


func test_missing_main_loads_the_backup_and_both_gone_is_empty() -> void:
	_clean()
	S.save_game({"day": 1}, P)
	S.save_game({"day": 2}, P)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(P))
	assert_eq(int(S.load_game(P).day), 1)
	_clean()
	assert_true(S.load_game(P).is_empty())
