extends Control
## GD-KITCHEN · The window sill over the counter, where jars that are still waiting (wait_left > 0) stand,
## days left under each. show_items([{"desc": ProductGen.describe(), "wait_left": int}]), caller sorts.
## Hovering a jar reports a line ("" when the pointer leaves).

signal hovered(text: String)

const Art := preload("res://scenes/kitchen/kitchen_art.gd")
const PITCH := 18
const MAX_SHOWN := 4

var _slots: Array[Control] = []


func _ready() -> void:
	position = Vector2(Art.SILL.position)
	size = Vector2(Art.SILL.size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_items(items: Array) -> void:
	for s in _slots:
		remove_child(s)
		s.queue_free()
	_slots.clear()
	var n := items.size() if items.size() <= MAX_SHOWN else MAX_SHOWN - 1
	for i in n:
		var it: Dictionary = items[i]
		var slot := Control.new()
		slot.position = Vector2(4 + i * PITCH, 1)
		slot.size = Vector2(PITCH - 1, 34)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		var jar := JarIcon.new()
		jar.view = "icon"
		slot.add_child(jar)
		jar.show_product(it.desc)
		var wl := int(it.wait_left)
		slot.tooltip_text = tr("KITCHEN_DAYS_TIP") % wl  # "3 days"
		slot.set_meta("days", wl)
		var line := tr("KITCHEN_WAITING_TIP") % [str(it.desc.get("name", "?")), int(it.wait_left)]
		slot.mouse_entered.connect(func() -> void: hovered.emit(line))
		slot.mouse_exited.connect(func() -> void: hovered.emit(""))
		add_child(slot)
		_slots.append(slot)
	queue_redraw()
	if items.size() > n:
		var more := Label.new()
		more.text = tr("KITCHEN_MORE") % (items.size() - n)
		more.position = Vector2(4 + n * PITCH, 2)
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(more)
		_slots.append(more)


func _draw() -> void:
	draw_rect(Rect2(0, 17, size.x, 4), Art.TAN)
	draw_rect(Rect2(0, 17, size.x, 1), Art.GOLD)
	draw_rect(Rect2(0, 21, size.x, 1), Art.BARK)
	for s: Control in _slots:  # one gold pip per day left (max 5) on the sill under each waiting jar
		if s.has_meta("days"):
			for i in mini(int(s.get_meta("days")), 5):
				draw_rect(Rect2(s.position.x + 1 + i * 3, 24, 2, 2), Art.GOLD)
