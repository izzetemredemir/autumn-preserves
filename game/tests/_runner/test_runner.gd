extends SceneTree
## Zero-dependency test runner (no addon needed).
##   godot --headless --path <project> -s res://tests/_runner/test_runner.gd [-- --filter <text>]
## Runs every res://tests/**/test_*.gd that extends test_case.gd, calls each test_* method,
## prints only failures + a one-line summary, exits 1 if anything failed.

const TESTS_DIR := "res://tests"


func _init() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--filter" and i + 1 < args.size():
			filter = args[i + 1]

	var passed := 0
	var failed := 0
	for path in _collect(TESTS_DIR):
		var script = load(path)
		if script == null or not script.can_instantiate():
			printerr("LOAD FAIL %s" % path)
			failed += 1
			continue
		var inst = script.new()
		if not inst.has_method("_is_test_case"):
			continue
		for m in inst.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (filter in name or filter in path):
				continue
			inst._failures.clear()
			if inst.has_method("before_each"):
				inst.before_each()
			inst.call(name)
			if inst.has_method("after_each"):
				inst.after_each()
			if inst._failures.is_empty():
				passed += 1
			else:
				failed += 1
				for f in inst._failures:
					printerr("FAIL %s::%s  %s" % [path.get_file(), name, f])
	print("tests: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _collect(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		if not sub.begins_with("_") and not sub.begins_with("."):
			out.append_array(_collect(dir_path.path_join(sub)))
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	out.sort()
	return out
