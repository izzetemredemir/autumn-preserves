class_name SpeciesPage
extends RefCounted
## SPECIES-GEN · The book's forest species pages, after the ingredient types in the Varieties tab: every species the
## save knows by today (SpeciesGen.known), in the order they appeared. Met ones show their icon, name, a small taste
## chart and a "New" tag for NEW_DAYS days (SpeciesGen.is_new); the others are "???". The left page starts with a
## heading and the met / known count. Book hooks: pages() into the tab's page count, fill() for a species spread.

const LEFT_ROWS := 7
const RIGHT_ROWS := 8
const ROW_H := 18


## Spreads the species need (0 while the save knows none).
static func pages(state: Dictionary) -> int:
	var n := _known(state).size()
	return 0 if n == 0 else ceili(float(n) / (LEFT_ROWS + RIGHT_ROWS))


## Fills spread `page` (0 = the first species spread) of the book's two pages.
static func fill(book: Book, left: VBoxContainer, right: VBoxContainer, state: Dictionary, page: int) -> void:
	var list := _known(state)
	for pg in [left, right]:
		pg.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	var tl := book._label(Book.FONT_TITLE, 18, Book.GOLD_DK)
	tl.text = book.tr("SPECIES_BOOK_TITLE")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var met := 0
	for sp: Dictionary in list:
		if SpeciesGen.seen(state, String(sp.id)):
			met += 1
	var cl := book._label(Book.FONT_BODY, 18, Book.TEXT)
	cl.text = "%d/%d" % [met, list.size()]
	head.add_child(cl)
	left.add_child(head)
	left.add_child(book._rule())
	var start := page * (LEFT_ROWS + RIGHT_ROWS)
	for i in LEFT_ROWS + RIGHT_ROWS:
		if start + i >= list.size():
			break
		(left if i < LEFT_ROWS else right).add_child(_row(book, state, list[start + i]))


## Icon, name, mini taste chart and the "New" tag; "???" before Granny met it.
static func _row(book: Book, state: Dictionary, sp: Dictionary) -> Control:
	var id := String(sp.id)
	var met := SpeciesGen.seen(state, id)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.custom_minimum_size = Vector2(0, ROW_H)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_KEEP
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if met:
		icon.texture = IconLib.ingredient(id)
	h.add_child(icon)
	var rar := String(sp.get("rarity", "common"))
	var col: Color = {"common": Book.TEXT, "uncommon": Book.GREEN, "rare": Book.RED}.get(rar, Book.TEXT)
	var nm := book._label(Book.FONT_BODY, 18, col if met else Book.PAPER_DK)
	nm.text = SpeciesGen.display_name(sp) if met else book.tr("BOOK_UNKNOWN")
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	h.add_child(nm)
	if met:
		if SpeciesGen.is_new(state, id):
			var tag := book._label(Book.FONT_BODY, 18, Book.RED)
			tag.text = book.tr("SPECIES_NEW_TAG")
			h.add_child(tag)
		h.add_child(MiniTaste.new().setup(sp.get("taste", [0, 0, 0, 0, 0])))
	return h


static func _known(state: Dictionary) -> Array:
	if state.is_empty():
		return []
	return SpeciesGen.known(int(state.get("save_seed", 0)), int(state.get("day", 1)))


## 5 bars, 2 px wide, 1 px per taste step (0..9), on a paper base line; the values in the tooltip.
class MiniTaste extends Control:
	var taste: Array = [0, 0, 0, 0, 0]

	func _init() -> void:
		custom_minimum_size = Vector2(14, 12)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_PASS

	func setup(t: Array) -> MiniTaste:
		taste = t
		var parts: PackedStringArray = []
		for i in 5:
			parts.append("%s %d" % [tr("UI_TASTE_" + ResultCard.AXES[i].to_upper()), int(t[i])])
		tooltip_text = ", ".join(parts)
		queue_redraw()
		return self

	func _draw() -> void:
		draw_rect(Rect2(0, 11, 14, 1), Book.PAPER_DK)
		for i in 5:
			var v := clampi(int(taste[i]), 0, 9)
			if v > 0:
				draw_rect(Rect2(i * 3, 11 - v - 1, 2, v + 1), ResultCard.AXIS_COLORS[i])
