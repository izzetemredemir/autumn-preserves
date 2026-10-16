extends RefCounted
## Base class for zero-dependency tests.
## In a test file:  extends "res://tests/_runner/test_case.gd"
## Methods named test_* run in file order; optional before_each()/after_each().
## Tests are synchronous (pure logic). For scene/frame tests, run the game via MCP or a smoke script.

var _failures: Array[String] = []


func _is_test_case() -> bool:
	return true


func fail(msg: String) -> void:
	_failures.append(msg)


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		fail("expected true. %s" % msg)


func assert_false(cond: bool, msg := "") -> void:
	if cond:
		fail("expected false. %s" % msg)


func assert_eq(actual, expected, msg := "") -> void:
	if not _same(actual, expected):
		fail("expected %s, got %s. %s" % [var_to_str(expected), var_to_str(actual), msg])


func assert_ne(actual, unexpected, msg := "") -> void:
	if _same(actual, unexpected):
		fail("did not expect %s. %s" % [var_to_str(unexpected), msg])


func assert_near(actual: float, expected: float, eps := 0.0001, msg := "") -> void:
	if absf(actual - expected) > eps:
		fail("expected %f ± %f, got %f. %s" % [expected, eps, actual, msg])


func assert_has(container, item, msg := "") -> void:
	if not container.has(item):
		fail("expected %s to contain %s. %s" % [var_to_str(container), var_to_str(item), msg])


# == between different Variant types raises a runtime error in Godot 4; compare safely.
func _same(a, b) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	var numeric := [TYPE_INT, TYPE_FLOAT]
	if ta != tb and not (ta in numeric and tb in numeric):
		return false
	return a == b
