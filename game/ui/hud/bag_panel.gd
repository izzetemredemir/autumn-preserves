class_name BagPanel
extends PanelContainer
## BAG-VIEW: the small paper panel under the HUD bar that shows what Granny carries: "Bag n/cap" in the heading
## font, a grid of icon + count cells (8 per row; one cell per variety or nut type, stacks summed), a hint line that
## says where the bag empties. Reads the state only (rules stay in sim/forage.gd). The HUD owns it and toggles it.

const COLS := 8
const CELL_W := 22
const MAX_W := 200
const BODY := &"BodyPaper"

var _title: Label
var _grid: GridContainer
var _empty: Label
var _hint: Label


func _ready() -> void:
	theme_type_variation = &"PaperPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	_title = Label.new()
	_title.theme_type_variation = &"PaperLabel"
	box.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 1)
	_grid.add_theme_constant_override("v_separation", 1)
	box.add_child(_grid)
	_empty = Label.new()
	_empty.theme_type_variation = BODY
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(COLS * CELL_W, 0)
	box.add_child(_empty)
	_hint = Label.new()
	_hint.theme_type_variation = BODY
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(COLS * CELL_W, 0)
	box.add_child(_hint)
	refresh()


## What the bag holds, one entry per variety / nut type, stacks summed, in bag order: [{"id", "kind", "count"}].
static func cells(d: Dictionary) -> Array:
	var out: Array = []
	var at := {}
	for item: Dictionary in d.get("bag", []):
		var kind := String(item.get("kind", ""))
		var id := String(item.get("variety", "")) if kind == "fresh" else String(item.get("type", ""))
		if id == "" or int(item.get("count", 1)) <= 0:
			continue
		var key := kind + ":" + id
		if at.has(key):
			out[at[key]].count += int(item.get("count", 1))
		else:
			at[key] = out.size()
			out.append({"id": id, "kind": kind, "count": int(item.get("count", 1))})
	return out


static func is_full(d: Dictionary) -> bool:
	return not d.is_empty() and Forage.bag_count(d) >= Forage.bag_capacity(d)


func refresh() -> void:
	if _grid == null:
		return
	var d: Dictionary = GameState.data
	if d.is_empty():
		return
	_title.text = "%s %d/%d" % [tr("UI_BAG_TITLE"), Forage.bag_count(d), Forage.bag_capacity(d)]
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var items := cells(d)
	for it: Dictionary in items:
		_grid.add_child(_cell(d, it))
	_grid.visible = not items.is_empty()
	_empty.text = tr("UI_BAG_EMPTY")
	_empty.visible = items.is_empty()
	_hint.text = tr("UI_BAG_HINT")
	reset_size()


## Display name in the current language (the same resolver the stove's grid uses).
static func _name(d: Dictionary, it: Dictionary) -> String:
	if it.kind == "fresh":
		return VarietyGen.display_name(d.get("varieties", {}).get(it.id, {"type": State.type_of_variety(it.id)}))
	return VarietyGen.type_name(it.id)


func _cell(d: Dictionary, it: Dictionary) -> Control:
	var type := State.type_of_variety(it.id) if it.kind == "fresh" else String(it.id)
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(CELL_W, 0)
	cell.add_theme_constant_override("separation", 0)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.tooltip_text = _name(d, it)
	var icon := TextureRect.new()
	icon.texture = IconLib.ingredient(type)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	var n := Label.new()
	n.theme_type_variation = BODY
	n.text = str(it.count)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(n)
	return cell
