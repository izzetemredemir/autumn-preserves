extends RefCounted
## FORMULA-KITCHEN · The book's "Creations" tab (Book tab 2): every invention made (state.formulas), first made first,
## PER_PAGE on each page: its jar, name, best stars and times made, what went in (icons, + add-ins) and its taste
## chart. Built with the book's own widgets and helpers; the book only routes its tab here.

const PER_PAGE := 2
const ROW_H := 68
const NAME_H := 36


## Invention keys in the order they were first made (then by key).
static func keys(d: Dictionary) -> Array:
	var made: Dictionary = d.get("formulas", {})
	var out: Array = made.keys()
	out.sort_custom(func(a: String, b: String) -> bool:
		var da := int(made[a].get("day", 0))
		var db := int(made[b].get("day", 0))
		return da < db or (da == db and a < b))
	return out


static func page_count(d: Dictionary) -> int:
	return maxi(ceili(keys(d).size() / float(PER_PAGE * 2)), 1)


## The bottom line: how many inventions so far.
static func milestone(d: Dictionary) -> String:
	return TranslationServer.translate("UI_FORMULA_BOOK_COUNT") % keys(d).size()


## Fills the spread `page` of the open book.
static func fill(book: Book, left: VBoxContainer, right: VBoxContainer, page: int) -> void:
	var d: Dictionary = book._data()
	for pg in [left, right]:
		pg.add_theme_constant_override("separation", 0)
	book._heading(left, TranslationServer.translate("UI_FORMULA_TAB"))
	var ks := keys(d)
	if ks.is_empty():
		var l := book._label(Book.FONT_BODY, 18, Book.TEXT)
		l.text = TranslationServer.translate("UI_FORMULA_BOOK_EMPTY")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(Book.PAGE_W, 0)
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left.add_child(l)
		return
	var first := page * PER_PAGE * 2
	for i in range(first, mini(ks.size(), first + PER_PAGE * 2)):
		var pg: VBoxContainer = left if i < first + PER_PAGE else right
		if i != first and i != first + PER_PAGE:
			pg.add_child(book._rule())
		pg.add_child(entry(book, String(ks[i]), d.formulas[ks[i]], d.get("varieties", {})))


## One invention: jar | name, stars + "x<made>", what went in | taste bars.
static func entry(book: Book, key: String, rec: Dictionary, varieties: Dictionary) -> Control:
	var desc := ProductGen.describe(key, varieties)
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, ROW_H)
	h.add_theme_constant_override("separation", 4)
	var jb := CenterContainer.new()
	jb.custom_minimum_size = Vector2(28, ROW_H)
	var jar := JarIcon.new()
	jar.view = "shelf"
	jb.add_child(jar)
	jar.show_product(desc)
	h.add_child(jb)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(mid)
	var nm := book._label(Book.FONT_BODY, 18, Book.TEXT)
	nm.text = String(desc.name)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.max_lines_visible = 2
	nm.custom_minimum_size = Vector2(0, NAME_H)
	var notes: PackedStringArray = []
	for id in desc.get("notes", []):
		notes.append(TranslationServer.translate("FX_NOTE_" + String(id).to_upper()))
	nm.tooltip_text = String(desc.name) + ("\n" + ", ".join(notes) if not notes.is_empty() else "")
	nm.mouse_filter = Control.MOUSE_FILTER_PASS
	mid.add_child(nm)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	mid.add_child(line)
	var best := clampi(int(rec.get("best", 1)), 1, 5)
	var hm := clampi(int(desc.harmony), 0, 2)
	var bq := clampi(best - hm, 0, 3)
	var sr := ResultCard.StarRow.new()
	sr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.add_child(sr)
	sr.set_stars(bq, clampi(best - bq, 0, 2))
	var made := book._label(Book.FONT_BODY, 18, Book.TEXT)
	made.text = "x%d" % int(rec.get("made", 1))
	made.custom_minimum_size = Vector2(0, 14)
	made.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(made)
	var parts := HBoxContainer.new()
	parts.add_theme_constant_override("separation", 0)
	parts.custom_minimum_size = Vector2(0, 18)
	mid.add_child(parts)
	var p := FormulaGen.parse(key)
	for comp: Dictionary in p.components:
		_part_icon(book, parts, comp, varieties)
	if not p.addins.is_empty():
		book._plus(parts)
		for a: String in p.addins:
			book._icon(parts, a).tooltip_text = ProductGen.addin_name(a)
	var ch := Book.BarChart.new()
	ch.set_taste(desc.taste)
	var side := CenterContainer.new()
	side.add_child(ch)
	h.add_child(side)
	return h


## A component's 16x16 icon with its name as tooltip: the ingredient, or the product's own little jar.
static func _part_icon(book: Book, row: Control, comp: Dictionary, varieties: Dictionary) -> void:
	var id := String(comp.id)
	match String(comp.kind):
		"product":
			var t := TextureRect.new()
			t.custom_minimum_size = Vector2(16, 16)
			t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			t.stretch_mode = TextureRect.STRETCH_KEEP
			t.texture = ImageTexture.create_from_image(JarIcon.render(ProductGen.describe(id, varieties), "icon"))
			t.tooltip_text = ProductGen.product_name(id, varieties)
			row.add_child(t)
		"nut":
			book._icon(row, id).tooltip_text = VarietyGen.type_name(id)
		_:
			var v: Dictionary = varieties.get(id, {"type": State.type_of_variety(id)})
			book._icon(row, State.type_of_variety(id)).tooltip_text = VarietyGen.display_name(v)
