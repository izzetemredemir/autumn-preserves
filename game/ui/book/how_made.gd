class_name HowMadeCard
extends PanelContainer
## P1-SEEDLAB · "How it was made" card of the recipe book (spec §7.9, §7.3): one variant's generation, step by step.
## PLAIN-WORDS: written as Granny's notebook. Variety (size, colour, taste shift) -> fruit + method + add-in = result
## (5 bars each) -> harmony and why -> where the name came from -> the look (label and lid). The appearance seed
## and the raw recipe key show only with Settings > Show seed; the Forest Lab keeps the engineering view.
## Values come from ProductGen, VarietyGen and the data tables. The explanations (chutney average, the sum before
## clamping, harmony reasons, which name fallback fired) are display-only re-derivations; each is checked against
## ProductGen's own answer and left out when they disagree.
## Opened by Book.open_how(key); closes on X, Esc or cancel and emits `closed`.

signal closed

const LEFT_W := 210
const RIGHT_W := 224
const PANEL_PAPER := preload("res://assets/sprites/ui/ui_panel_paper.png")
const LINE_GAP := -4  ## 18 px labels on a 14 px pitch: the glyphs are 11 px tall

var key := ""
var _book: Book
var _close: Button


func build(book: Book, p_key: String, varieties: Dictionary, rec: Dictionary) -> void:
	_book = book
	key = p_key
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxTexture.new()  # UI-kit paper panel: wood frame, paper fill
	sb.texture = PANEL_PAPER
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_texture_margin(side, 5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(456, 256)

	var p := ProductGen.parse_key(key)
	var desc := ProductGen.describe(key, varieties)
	var mains: Array = []
	for id in p.varieties:
		mains.append(_variety(String(id), varieties))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	add_child(vb)
	_header(vb, desc)
	var rule := ColorRect.new()
	rule.color = Book.PAPER_DK
	rule.custom_minimum_size = Vector2(0, 1)
	vb.add_child(rule)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 4)
	vb.add_child(cols)
	var left := _column(LEFT_W)
	cols.add_child(left)
	var spine := ColorRect.new()
	spine.color = Book.PAPER_DK
	spine.custom_minimum_size = Vector2(2, 0)
	cols.add_child(spine)
	var right := _column(RIGHT_W)
	cols.add_child(right)

	_variety_lines(left, mains)
	_name_lines(left, ProductGen.name_parts(key, varieties), desc)
	_taste_lines(right, p, desc, mains)
	_harmony_lines(right, desc, rec)
	_look_lines(right, desc)
	if GameSettings.show_seed():
		var foot := _book._label(Book.FONT_BODY, 18, Book.FRAME)  # the raw recipe key, small, at the bottom
		foot.text = "%s: %s" % [tr("BOOK_HOW_KEY"), key]
		foot.clip_text = true
		vb.add_child(foot)
	_close.grab_focus()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("cancel") or event.is_action("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# ---------- sections ----------

func _header(vb: VBoxContainer, desc: Dictionary) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	vb.add_child(top)
	var jb := CenterContainer.new()
	jb.custom_minimum_size = Vector2(28, 30)
	var jar := JarIcon.new()
	jar.view = "shelf"
	jb.add_child(jar)
	jar.show_product(desc)
	top.add_child(jb)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	var title := _book._label(Book.FONT_TITLE, 18, Book.GOLD_DK)
	title.text = tr("BOOK_HOW_TITLE")
	names.add_child(title)
	var name_l := _book._label(Book.FONT_TITLE, 18, Book.TEXT)
	name_l.text = String(desc.name)
	name_l.clip_text = true
	names.add_child(name_l)
	_close = _book._button(tr("BOOK_CLOSE"))
	_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close.pressed.connect(close)
	top.add_child(_close)


func _variety_lines(box: VBoxContainer, mains: Array) -> void:
	_head(box, tr("BOOK_HOW_VARIETY"))
	for v: Dictionary in mains:
		var rar := String(v.get("rarity", "common"))
		_line(box, "%s, %s" % [VarietyGen.display_name(v),
			tr("BOOK_RARITY_" + rar.to_upper())])
		var shift := int(v.get("color_shift", 0))
		var shift_key := "BOOK_HOW_SHIFT_UP" if shift > 0 else ("BOOK_HOW_SHIFT_DOWN" if shift < 0 else "BOOK_HOW_SHIFT_NONE")
		_line(box, tr("BOOK_HOW_TRAITS") % [tr("BOOK_HOW_SIZE_" + String(v.get("size", "medium")).to_upper()), tr(shift_key)])
		_line(box, tr("BOOK_HOW_DELTA") % _delta_text(v.get("taste_delta", [0, 0, 0, 0, 0])))


## The grammar "[Adjective] [Feature] [Type] [Recipe]" and which rule shaped this name (spec §7.3), from
## ProductGen.name_parts in the shown language (L10N-TR: Turkish names have their own parts and fallbacks).
func _name_lines(box: VBoxContainer, np: Dictionary, desc: Dictionary) -> void:
	_head(box, tr("BOOK_HOW_NAME"))
	var max_len := int(Data.grammar().product_name_max)
	var adjective := String(np.adjective)
	var adj_line := ""
	match String(np.adjective_kind):
		"family":  # KITCHEN-P1C: a family recipe always says "Granny's"; its short already names the dish
			adj_line = tr("UI_FAMILY_HOW_ADJ") % adjective
		"addin":
			adj_line = tr("BOOK_HOW_ADJ_ADDIN") % adjective
		"mild":
			adj_line = tr("BOOK_HOW_ADJ_MILD") % adjective
		_:
			adj_line = tr("BOOK_HOW_ADJ_PROFILE") % adjective
	if bool(np.adjective_long):
		adj_line = tr("BOOK_HOW_ADJ_DROPPED") % adjective
	var feature := String(np.feature)
	var feature_line := tr("BOOK_HOW_FEATURE_NONE")
	if feature != "" and bool(np.repeat):
		feature_line = tr("BOOK_HOW_FEATURE_REPEAT") % feature
	elif feature != "" and bool(np.feature_long):
		feature_line = tr("BOOK_HOW_FEATURE_LONG") % feature
	elif feature != "":
		feature_line = tr("BOOK_HOW_FEATURE") % feature
	var final_name := String(desc.name)
	if String(np.name) == final_name:
		_line(box, adj_line)
		_line(box, feature_line)
	_line(box, tr("BOOK_HOW_LENGTH") % [final_name.length(), max_len])


func _look_lines(box: VBoxContainer, desc: Dictionary) -> void:
	_head(box, tr("BOOK_HOW_LOOK"))
	var ap: Dictionary = desc.appearance
	_line(box, tr("BOOK_HOW_PARTS") % [tr("BOOK_HOW_MOTIF_" + String(ap.get("motif", "leaf")).to_upper()),
		tr("BOOK_HOW_LID_" + String(ap.get("lid", "metal")).to_upper())])
	if GameSettings.show_seed():
		_line(box, tr("BOOK_HOW_SEED") % ProductGen.appearance_seed(key), Book.GOLD_DK)


## Base + method effect + add-in effect = final, five bars each.
func _taste_lines(box: VBoxContainer, p: Dictionary, desc: Dictionary, mains: Array) -> void:
	_head(box, tr("BOOK_HOW_TASTE"))
	var base := [0, 0, 0, 0, 0]
	if mains.size() == 1:
		base = VarietyGen.taste_of(mains[0])
	elif mains.size() >= 2:
		var a := VarietyGen.taste_of(mains[0])
		var b := VarietyGen.taste_of(mains[1])
		for i in 5:
			base[i] = ceili((int(a[i]) + int(b[i])) / 2.0)
	var recipe: Dictionary = Data.recipes().get(p.recipe, {})
	var method := _effect(recipe.get("effect"))
	var addin := [0, 0, 0, 0, 0]
	var addin_name := tr("BOOK_HOW_NO_ADDIN")
	if p.addin != "":
		var ad: Dictionary = Data.addins().get(p.addin, {})
		addin = _effect(ad.get("effect"))
		addin_name = ProductGen.addin_adjective(String(p.addin))
	var final: Array = desc.taste
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	box.add_child(row)
	_chart(row, base, tr("BOOK_HOW_AVERAGE") if mains.size() >= 2 else tr("BOOK_HOW_BASE"))
	_op(row, "+")
	var method_id := String(recipe.get("family_of", p.recipe))  # family: its base
	_chart(row, method, ProductGen.recipe_short(method_id))
	_op(row, "+")
	_chart(row, addin, addin_name)
	_op(row, "=")
	_chart(row, final, tr("BOOK_HOW_FINAL"))
	var cfg: Dictionary = Data.rules().taste
	for i in 5:
		if int(base[i]) + int(method[i]) + int(addin[i]) != int(final[i]):
			_line(box, tr("BOOK_HOW_CLAMPED") % [int(cfg.min), int(cfg.max)], Book.GOLD_DK)
			break
	_line(box, tr("BOOK_HOW_PROFILE") % String(desc.profile_label))


## Harmony 0-2 and the two independent reasons (spec §7.3), then the best jar's stars.
func _harmony_lines(box: VBoxContainer, desc: Dictionary, rec: Dictionary) -> void:
	var t: Array = desc.taste
	var h := int(desc.harmony)
	_head(box, tr("BOOK_HOW_HARMONY") % h)
	var cfg: Dictionary = Data.rules().taste
	var order := [0, 1, 2, 3, 4]
	order.sort_custom(func(x: int, y: int) -> bool: return int(t[x]) > int(t[y]) or (int(t[x]) == int(t[y]) and x < y))
	var a: int = order[0]
	var b: int = order[1]
	var pair_ok := false
	if int(t[a]) >= int(cfg.harmony_pair_min) and int(t[b]) >= int(cfg.harmony_pair_min):
		for pair: Array in cfg.liked_pairs:
			if (pair[0] == ProductGen.AXES[a] and pair[1] == ProductGen.AXES[b]) or (pair[0] == ProductGen.AXES[b] and pair[1] == ProductGen.AXES[a]):
				pair_ok = true
	var high := 0
	for v in t:
		if int(v) >= int(cfg.balance_axis_min):
			high += 1
	var top := int(t[a])
	var calm := top < int(cfg.balance_max_exclusive)
	var bal_ok := calm and high >= int(cfg.balance_axes_min_count)
	if int(pair_ok) + int(bal_ok) == h:
		_line(box, (tr("BOOK_HOW_PAIR_YES") if pair_ok else tr("BOOK_HOW_PAIR_NO")) % [_axis(a), _axis(b)])
		if bal_ok:
			_line(box, tr("BOOK_HOW_BALANCE_YES"))
		elif not calm:
			_line(box, tr("BOOK_HOW_BALANCE_HIGH") % _axis(a))
		else:
			_line(box, tr("BOOK_HOW_BALANCE_FEW"))
	if not rec.is_empty():  # the best jar's stars, drawn as stars: quality first, then harmony
		var q := clampi(int(rec.get("best_q", 0)), 0, 3)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var lab := _book._label(Book.FONT_BODY, 18, Book.TEXT)
		lab.text = tr("BOOK_HOW_STARS")
		row.add_child(lab)
		var sr := ResultCard.StarRow.new()
		sr.set_stars(q, h)
		row.add_child(sr)
		box.add_child(row)


# ---------- widgets ----------

func _column(width: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(width, 0)
	v.add_theme_constant_override("separation", LINE_GAP)
	return v


func _head(box: Control, text: String) -> void:
	var l := Head.new()
	l.add_theme_font_override("font", Book.FONT_BODY)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Book.GOLD_DK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	box.add_child(l)


func _line(box: Control, text: String, color := Book.TEXT) -> void:
	var l := _book._label(Book.FONT_BODY, 18, color)
	l.text = text
	l.clip_text = true
	l.custom_minimum_size.x = box.custom_minimum_size.x
	box.add_child(l)


func _chart(row: HBoxContainer, values: Array, caption: String) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.custom_minimum_size = Vector2(54, 0)  # fits the longest add-in caption ("Cinnamon", "Hazelnut")
	row.add_child(col)
	var cb := CenterContainer.new()
	col.add_child(cb)
	cb.add_child(TasteBars.new().setup(values))
	var cap := _book._label(Book.FONT_BODY, 18, Book.TEXT)
	cap.text = caption
	cap.clip_text = true
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.custom_minimum_size.x = 54
	col.add_child(cap)


func _op(row: HBoxContainer, text: String) -> void:
	var l := _book._label(Book.FONT_BODY, 18, Book.GOLD_DK)
	l.text = text
	l.custom_minimum_size = Vector2(6, TasteBars.BAR_H)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(l)


func _axis(i: int) -> String:
	return tr("UI_TASTE_" + String(ProductGen.AXES[i]).to_upper())


## "Sweet +1, Sour -1" from a taste delta; "none" when it is all zeros.
func _delta_text(delta: Array) -> String:
	var parts: Array = []
	for i in mini(5, delta.size()):
		var d := int(delta[i])
		if d != 0:
			parts.append("%s %+d" % [_axis(i), d])
	return tr("BOOK_HOW_NONE") if parts.is_empty() else ", ".join(parts)


static func _effect(e: Variant) -> Array:
	var out := [0, 0, 0, 0, 0]
	if typeof(e) == TYPE_ARRAY:
		for i in mini(5, e.size()):
			out[i] = int(e[i])
	return out


static func _variety(id: String, varieties: Dictionary) -> Dictionary:
	if varieties.has(id):
		return varieties[id]
	var type := State.type_of_variety(id)
	return {"id": id, "type": type, "name": VarietyGen.en_type_name(type)}


## Section heading: gold text and a thin rule running to the column edge.
class Head extends Label:
	func _draw() -> void:
		var w := int(get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x)
		if size.x - w > 8:
			draw_rect(Rect2(w + 4, 8, size.x - w - 4, 1), Book.GOLD)


## Five 6-px bars (0..9, 2 px a step) with the value under each.
class TasteBars extends Control:
	const BAR_H := 19
	const PITCH := 7
	var values: Array = [0, 0, 0, 0, 0]

	func _init() -> void:
		custom_minimum_size = Vector2(PITCH * 5, BAR_H + 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(v: Array) -> TasteBars:
		values = v
		queue_redraw()
		return self

	func _draw() -> void:
		var font: Font = Book.FONT_BODY
		var asc := int(font.get_ascent(18))
		for i in 5:
			var v := clampi(int(values[i]), 0, 9)
			var x := i * PITCH
			draw_rect(Rect2(x, 0, PITCH - 1, BAR_H), ResultCard.EMPTY)
			if v > 0:
				draw_rect(Rect2(x, BAR_H - v * 2 - 1, PITCH - 1, v * 2 + 1), ResultCard.AXIS_COLORS[i])
			draw_string(font, Vector2(x, BAR_H + asc - 3), str(int(values[i])), HORIZONTAL_ALIGNMENT_CENTER, PITCH, 18, Book.TEXT)
