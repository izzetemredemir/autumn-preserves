extends "res://tests/_runner/test_case.gd"
## POLISH-SMALL: an item dragged from the inbox lands on the cell under the cursor (its left/top cell), even when the
## slot offset the inbox passes would have shifted a 2x1 by half a cell.


func _board(entries: Array) -> ArrangeBoard:
	var b := ArrangeBoard.new()
	var rules := {
		"item_size": func(item: Dictionary, rot: int) -> Vector2i:
			var s: Vector2i = item.size
			return Vector2i(s.y, s.x) if rot == 1 else s,
		"can_place": func(board: Dictionary, es: Array, item: Dictionary, c: Vector2i, rot: int, ignore: int) -> bool:
			var s: Vector2i = item.size if rot == 0 else Vector2i(item.size.y, item.size.x)
			if c.x < 0 or c.y < 0 or c.x + s.x > int(board.cols) or c.y + s.y > int(board.rows):
				return false
			for i in es.size():
				if i == ignore:
					continue
				var o: Dictionary = es[i]
				var os: Vector2i = o.item.size
				if c.x < int(o.x) + os.x and int(o.x) < c.x + s.x and c.y < int(o.y) + os.y and int(o.y) < c.y + s.y:
					return false
			return true,
	}
	b.setup({"cols": 5, "rows": 3, "zones": []}, entries, rules, {"cell": 24})
	return b


func test_inbox_two_by_one_lands_under_cursor() -> void:
	var entries := []
	var b := _board(entries)
	var item := {"id": "bread", "size": Vector2i(2, 1)}
	# pointer in the middle of cell (1,1); the right neighbour (2,1) is free
	var pointer := Vector2(24 * 1 + 12, 24 * 1 + 12)
	# the old inbox passed the offset inside its 24 px slot: a far corner here, which used to shift the anchor
	assert_true(b.begin_hold(item, {"where": "inbox", "index": 0}, pointer, Vector2(20, 20)))
	assert_eq(b._preview.get("cell"), Vector2i(1, 1), "ghost on the cell under the cursor")
	assert_true(bool(b._preview.get("fits")), "the 2x1 fits")
	b.drop_held()
	assert_eq(entries.size(), 1, "the drop placed it")
	assert_eq(Vector2i(int(entries[0].x), int(entries[0].y)), Vector2i(1, 1))
	b.free()


func test_inbox_two_by_one_blocked_right_neighbour_refused() -> void:
	var entries := [{"item": {"id": "jar", "size": Vector2i(1, 1)}, "x": 2, "y": 1, "rot": 0}]
	var b := _board(entries)
	var item := {"id": "bread", "size": Vector2i(2, 1)}
	assert_true(b.begin_hold(item, {"where": "inbox", "index": 0}, Vector2(36, 36), Vector2(20, 4)))
	assert_false(bool(b._preview.get("fits")), "right neighbour taken")
	b.cancel_hold()
	b.free()
