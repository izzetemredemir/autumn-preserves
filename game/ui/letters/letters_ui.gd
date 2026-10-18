class_name LettersUI
extends CanvasLayer
## Post office overlay (P1-LETTERS, spec §7.6): the letter reader and the parcel packing screen.
## Open with `LettersUI.open()` (static, finds or creates the overlay): the town Post office uses it, the garden
## mailbox can call it too. Rules come from Letters (game/sim/letters.gd); this only shows, asks and sends.
## Parcel: a 3x2 ArrangeBoard box fed from the ready jars in the inbox and the pantry. Jars stay in the save
## until Send (Letters.pack takes them), so Back or Close never loses anything.

signal closed

const SCENE := "res://ui/letters/letters_ui.tscn"
const THEME := "res://ui/theme/theme.tres"
const InboxView := preload("res://scenes/pantry/inbox_view.gd")
const PORTRAIT := "res://assets/sprites/portraits/portrait_%s.png"
const CELL := 24
const SOUNDS := {"pick": "sfx_pantry_pick", "place": "sfx_pantry_place", "wrong": "sfx_pantry_wrong", "rotate": "sfx_pantry_pick"}
const INK := Color("111010")
const GOLD := Color("e5bd7f")
const RED := Color("a22512")
const GREEN := Color("4e7664")
const BOARD_POS := Vector2(200, 78)
const PAPER_INK := Color("50361e")
## Letter paper: text left edge and width, column beside the child's drawing, ruled line pitch (UI-COMPACT: the
## body font, m5x7 16 px: 13 px line + 3).
const TEXT_X := 165
const TEXT_W := 290
const NARROW_W := 234
const LINE_PITCH := 16
const LINE_GAP := 3
const BODY_ASCENT := 11  ## m5x7 at 16 px: the rule sits right under the letters

var _start_id := -1
var _letter_id := -1
## POST-UNREAD (human, 18 Oct): opened from the post office, the list shows only the letters that were unread when it
## opened (so the one being read stays listed); the parlour's letters hotspot shows them all.
var _unread_only := false
var _shown_ids: Array = []
var _built := false
var _root: Control
var _read_page: Control
var _pack_page: Control
# reader
var _list: VBoxContainer
var _paper_text: VBoxContainer
var _top_text: VBoxContainer
var _card: Control
var _portrait: KidPortrait
var _kid_name: Label
var _hearts: HeartRow
var _love_label: Label
var _pack_btn: Button
var _status: Label
var _close_btn: Button
var _flash := ""
# parcel
var _board: ArrangeBoard
var _source_view: InboxView
var _source: Array = []
var _entries: Array = []
var _no_jars: Label
var _parcel_title: Label
var _checks: VBoxContainer
var _straw_btn: Button
var _send_btn: Button
var _hint: Label
var _love_preview: Label


## Finds the open overlay or creates one under the scene root, showing `letter_id` (-1: newest unread, else newest).
## unread_only: the post office view (read letters stay in the parlour).
static func open(letter_id: int = -1, unread_only: bool = false) -> LettersUI:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var ui := tree.get_first_node_in_group("letters_ui") as LettersUI
	if ui == null:
		ui = (load(SCENE) as PackedScene).instantiate() as LettersUI
		ui._start_id = letter_id
		ui._unread_only = unread_only
		tree.root.add_child(ui)  # _ready() shows it
	else:
		ui.show_letter(letter_id)
	return ui


func _ready() -> void:
	layer = 20
	add_to_group("letters_ui")
	var gs := get_node_or_null("/root/GameState")
	if gs != null and not gs.has_game():
		gs.start_temp(1)
	Letters.ensure(_data())
	_build()
	show_letter(_start_id)
	_sfx("sfx_page_turn")


## GameState.data (looked up by path so the script also compiles where autoloads are not registered yet).
func _data() -> Dictionary:
	var gs := get_node_or_null("/root/GameState")
	return gs.data if gs != null else {}


func close() -> void:
	if _board != null:
		_board.cancel_hold()
	_save(["letters"])
	visible = false
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("cancel") or event.is_action("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _pack_page.visible:
			if _board.is_holding():
				_board.cancel_hold()
			else:
				_on_back()
		else:
			close()


# --- reader ------------------------------------------------------------------------------------------------------

## Shows a letter in the reader (-1: newest unread, else the newest) and marks it read.
func show_letter(letter_id: int = -1) -> void:
	var inbox: Array = _data().letters.inbox
	if _unread_only and _shown_ids.is_empty():
		for l in inbox:
			if not bool(l.get("read", false)):
				_shown_ids.append(int(l.id))
	if _unread_only and letter_id < 0 and _shown_ids.is_empty():
		letter_id = -2  # nothing unread: the reader shows the "no new letters" paper
	if letter_id < 0:
		for i in range(inbox.size() - 1, -1, -1):
			if not bool(inbox[i].get("read", false)):
				letter_id = int(inbox[i].id)
				break
	if letter_id == -1 and not inbox.is_empty():
		letter_id = int(inbox[inbox.size() - 1].id)
	_letter_id = letter_id
	if _letter_id >= 0:
		Letters.mark_read(_data(), _letter_id)
	_pack_page.visible = false
	_read_page.visible = true
	_render_reader()


func _render_reader() -> void:
	var d := _data()
	_clear(_list)
	var inbox: Array = d.letters.inbox
	for i in range(inbox.size() - 1, -1, -1):
		var l: Dictionary = inbox[i]
		if _unread_only and not _shown_ids.has(int(l.id)):
			continue
		var b := Button.new()
		b.text = tr("LET_LIST_ITEM") % [Letters.kid_name(String(l.from)), int(l.day)]
		b.icon = _envelope(l)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 19)
		b.toggle_mode = true
		b.button_pressed = int(l.id) == _letter_id
		_style_row(b, not bool(l.get("read", false)))
		b.pressed.connect(_select.bind(int(l.id)))
		_list.add_child(b)
	_clear(_paper_text)
	_top_text = null
	var letter := Letters.find_letter(d, _letter_id)
	_card.visible = not letter.is_empty()
	_pack_btn.visible = false
	_status.text = _flash
	_status.add_theme_color_override("font_color", GOLD)
	_flash = ""
	if letter.is_empty():
		_paper(tr("LET_NO_NEW") if _unread_only and not inbox.is_empty() else tr("LET_EMPTY"))
		return
	if Letters.is_story(letter):
		_card.visible = false  # a letter from Nora: no child card, no love, no request, no Pack button
		for key in letter.get("lines", []):
			_paper(tr(String(key)))
		return
	var kid := String(letter.from)
	_portrait.kid = kid
	_kid_name.text = Letters.kid_name(kid)
	var love := int(d.letters.love.get(kid, 0))
	_hearts.love = love
	_hearts.queue_redraw()
	_love_label.text = "%s %d" % [tr("LET_LOVE_HEAD"), love]
	# Greeting and note run beside the child's drawing, the rest uses the full width. The top block is a whole
	# number of ruled lines tall, so every line below it still sits on a rule.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_text = VBoxContainer.new()
	_top_text.add_theme_constant_override("separation", LINE_GAP)
	_top_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_top_text)
	var sheet := DrawingSheet.new()
	sheet.texture = ImageTexture.create_from_image(KidDrawing.render(_drawing_seed(letter), _drawing_subject(d, letter)))
	sheet.custom_minimum_size = Vector2(52, LINE_PITCH * 4 - LINE_GAP)
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sheet)
	_paper_text.add_child(top)
	_paper(tr("LET_DEAR"), false)
	_paper(tr(String(letter.note)), false)
	if String(letter.kind) == "request":
		var lines := tr("LET_ASK")
		for req in letter.request:
			lines += "\n- " + _req_text(req)
		_paper(lines)
		var group := String(Letters.kid_info(kid).get("dislikes_group", ""))
		if group != "":
			_paper(tr("LET_PS_DISLIKE") % tr("LET_GROUP_" + group.to_upper()))
		if int(letter.get("ps_story", 0)) > 0:
			_paper(tr("LET_PS_STORY_%d" % int(letter.ps_story)))
		var done := bool(letter.get("done", false))
		_pack_btn.visible = not done
		if done and _status.text == "":
			var p := Letters.parcel_for(d, _letter_id)
			if not p.is_empty() and not bool(p.get("replied", false)):
				_status.text = tr("LET_STATUS_WAIT") % Letters.kid_name(kid)
			elif not p.is_empty():
				_status.text = tr("LET_STATUS_SENT") % int(p.day)
			_status.add_theme_color_override("font_color", Color("b9a697"))
	else:
		var jar_line := Letters.reply_line(d, letter)  # FUN-REACT: the kid names a jar from the parcel
		if jar_line != "":
			_paper(jar_line)
		if String(letter.get("care_note", "")) != "":
			_paper(tr(String(letter.care_note)))
		var names: Array = []
		for rid in letter.get("unlocked", []):
			names.append(tr("LET_RECIPE_" + String(rid).to_upper()))
		if not names.is_empty():
			var page := Kitchen.family_ids().find(String(letter.unlocked[0])) + 1
			_paper(tr("LET_PS_RECIPE") % [page, ", ".join(names)])
		if _status.text == "":
			_status.text = tr("LET_LOVE_PREVIEW") % int(letter.get("hearts", 0))
	_paper(tr("LET_SIGN") % Letters.kid_name(kid))


## Seed of a letter's drawing: the same letter always shows the same picture.
func _drawing_seed(letter: Dictionary) -> int:
	return Hash.fnv1a31("%d|%s" % [int(letter.id), String(letter.from)])


## What the child drew: the jars from Granny's parcel (reply) or what they wish for (request).
func _drawing_subject(d: Dictionary, letter: Dictionary) -> Dictionary:
	var items: Array = []
	if String(letter.kind) == "request":
		for req in letter.get("request", []):
			var vessel := String(Data.recipes().get(String(req.get("recipe", "")), {}).get("vessel", "jam_jar"))
			items.append(KidDrawing.wish(vessel, String(req.get("taste", ""))))
	else:
		var parcel := Letters.parcel_for(d, int(letter.get("re", -1)))
		for key in parcel.get("keys", []):
			var look: Dictionary = ProductGen.describe(String(key), d.get("varieties", {})).appearance
			var lids: Array = look.get("lid_colors", ["9b8039"])
			items.append({"vessel": String(look.vessel), "fill": look.fill, "lid": String(lids[0]),
				"label": String(look.label_color)})
	return {"kind": String(letter.kind), "kid": String(letter.from), "care": bool(letter.get("care", false)),
		"items": items}


func _select(letter_id: int) -> void:
	if letter_id != _letter_id:
		_sfx("sfx_page_turn")
	show_letter(letter_id)


## `wide` = full paper width; false = beside the child's drawing (greeting and note).
func _paper(text: String, wide := true) -> void:
	var l := _label(text)
	l.theme_type_variation = &"BodyPaper"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if wide or _top_text == null:
		l.custom_minimum_size.x = TEXT_W
		_paper_text.add_child(l)
	else:
		l.custom_minimum_size.x = NARROW_W
		_top_text.add_child(l)


## "something sweet", "a jar of pickles", "a jar of jam, nice and sour".
func _req_text(req: Dictionary) -> String:
	var recipe := String(req.get("recipe", ""))
	var taste := String(req.get("taste", ""))
	var rname := ProductGen.recipe_name(recipe).to_lower()
	var tname := tr("UI_TASTE_" + taste.to_upper()).to_lower()
	if recipe != "" and taste != "":
		return tr("LET_REQ_BOTH") % [tname, rname]
	if recipe != "":
		return tr("LET_REQ_RECIPE") % rname
	if taste != "":
		return tr("LET_REQ_TASTE") % tname
	return tr("LET_REQ_ANY")


# --- parcel ------------------------------------------------------------------------------------------------------

## Switches to the packing screen for the shown request letter.
func open_pack() -> void:
	var letter := Letters.find_letter(_data(), _letter_id)
	if letter.is_empty() or String(letter.kind) != "request" or bool(letter.get("done", false)):
		return
	_source.clear()
	for s in Letters.parcel_sources(_data()):
		_source.append(s.item)
	_entries.clear()
	_board.setup(Letters.box_board(), _entries, {
		"item_size": PantryRules.item_size, "can_place": PantryRules.can_place, "can_rotate": PantryRules.can_rotate,
	}, {"cell": CELL, "zone_colors": {"box": ["50361e", "3d1f29"]}})
	_board.position = BOARD_POS
	_source_view.refresh()
	_parcel_title.text = tr("LET_PARCEL_FOR") % Letters.kid_name(String(letter.from))
	_hint.text = tr("LET_PACK_HINT")
	_hint.add_theme_color_override("font_color", Color("b9a697"))
	_read_page.visible = false
	_pack_page.visible = true
	_refresh_pack()
	_sfx("sfx_page_turn")


func _refresh_pack() -> void:
	var d := _data()
	var letter := Letters.find_letter(d, _letter_id)
	if letter.is_empty():
		return
	var kid := String(letter.from)
	var ev := Letters.evaluate(d, letter, _entries)
	_clear(_checks)
	_check_head(tr("LET_ASKED") % Letters.kid_name(kid))
	var reqs: Array = letter.request
	for i in reqs.size():
		_check_row(_req_text(reqs[i]), bool(ev.ticks[i]))
	_check_head(tr("LET_CARE_HEAD"))
	_check_row(tr("LET_CARE_REQUEST"), bool(ev.met))
	_check_row(tr("LET_CARE_STRAW"), bool(ev.straw))
	var likes: Array = Letters.kid_info(kid).get("likes", [])
	var names: Array = []
	for a in likes:
		names.append(tr("UI_TASTE_" + String(a).to_upper()).to_lower())
	var liked := tr("LET_OR") % [names[0], names[1]] if names.size() >= 2 else ", ".join(names)
	_check_row(tr("LET_CARE_SURPRISE") % liked, bool(ev.surprise))
	_love_preview.text = tr("LET_LOVE_PREVIEW") % int(ev.hearts)
	_love_preview.add_theme_color_override("font_color", Color("e19064") if bool(ev.care) else GOLD)
	var has_straw := false
	for e in _entries:
		has_straw = has_straw or Letters.is_straw(e.item)
	_straw_btn.text = tr("LET_STRAW_OFF") if bool(ev.full) and has_straw else tr("LET_STRAW")
	_send_btn.disabled = int(ev.products) == 0
	_no_jars.visible = _source.is_empty() and not _board.is_holding()


func _check_head(text: String) -> void:
	var l := _label(text)
	l.theme_type_variation = &"PaperLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 144
	_checks.add_child(l)


func _check_row(text: String, on: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var box := CheckIcon.new()
	box.on = on
	box.custom_minimum_size = Vector2(9, 9)
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(box)
	var l := _label(text)
	l.theme_type_variation = &"PaperLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 132
	if on:
		l.add_theme_color_override("font_color", GREEN)
	row.add_child(l)
	_checks.add_child(row)


func _on_entry_added(_index: int, from: Dictionary) -> void:
	if String(from.get("where", "")) != "inbox":
		return
	var i := int(from.get("index", -1))
	if i >= 0 and i < _source.size():
		_source.remove_at(i)
	_source_view.refresh()


## A box item dragged out of the box comes out: jars go back to the jar column, straw just goes.
func _on_released_outside(item: Dictionary, from: Dictionary, _global_pos: Vector2) -> void:
	if String(from.get("where", "")) != "board":
		return
	_board.remove_entry(int(from.index))
	if not Letters.is_straw(item):
		_source.append(item)
		_source_view.refresh()


func _on_straw() -> void:
	_board.cancel_hold()
	if Letters.fill_straw(_entries) == 0:
		Letters.clear_straw(_entries)
		_sfx("sfx_pantry_pick")
	else:
		_sfx("sfx_bush_rustle")
	_board.notify_changed()
	_board.pop_all()


func _on_send() -> void:
	_board.cancel_hold()
	var d := _data()
	var letter := Letters.find_letter(d, _letter_id)
	var res := Letters.pack(d, _letter_id, _entries)
	if not bool(res.ok):
		_hint.text = tr(String(res.reason))
		_hint.add_theme_color_override("font_color", Color("e19064"))
		_ui("ui_error")
		return
	_save(["letters", "inbox", "pantry"])
	var who := Letters.kid_name(String(letter.from))
	_flash = tr("LET_SENT_CARE") % who if bool(res.care) else tr("LET_SENT") % who
	for rid in res.unlocked:
		_flash += "\n" + tr("LET_UNLOCKED") % tr("LET_RECIPE_" + String(rid).to_upper())
	_entries.clear()
	if bool(res.care):
		_sfx("sfx_sparkle")
	else:
		_ui("ui_confirm")
	show_letter(_letter_id)


func _on_back() -> void:
	_board.cancel_hold()
	_entries.clear()
	_ui("ui_back")
	show_letter(_letter_id)


func _on_board_changed() -> void:
	_refresh_pack()


func _on_hold_ended(_item: Dictionary, _placed: bool) -> void:
	_refresh_pack()


# --- build -------------------------------------------------------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = load(THEME)
	add_child(_root)
	var di := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	di.fill(Color(0, 0, 0, 0))
	di.set_pixel(0, 0, INK)
	di.set_pixel(1, 1, INK)
	var dim := TextureRect.new()
	dim.texture = ImageTexture.create_from_image(di)
	dim.stretch_mode = TextureRect.STRETCH_TILE
	dim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var desk := Panel.new()
	desk.position = Vector2(8, 8)
	desk.size = Vector2(464, 254)
	_root.add_child(desk)
	_build_reader()
	_build_pack()


func _build_reader() -> void:
	_read_page = _page()
	var head := _label(tr("LET_TITLE"))
	head.theme_type_variation = &"Heading"
	head.position = Vector2(18, 13)
	_read_page.add_child(head)
	# Letter list: envelopes on a sheet of note paper, the open one marked like a bookmark.
	_paper_sheet(_read_page, Vector2(14, 30), Vector2(130, 108))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(19, 35)
	scroll.size = Vector2(120, 98)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(scroll.get_v_scroll_bar())
	_read_page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	# Sender card: the grandchild's portrait, name and love hearts (10 hearts = every family recipe).
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_read_page.add_child(_card)
	_paper_sheet(_card, Vector2(14, 144), Vector2(130, 80))
	_portrait = KidPortrait.new()
	_portrait.position = Vector2(21, 160)
	_portrait.size = Vector2(48, 48)
	_card.add_child(_portrait)
	_kid_name = _label("")
	_kid_name.theme_type_variation = &"PaperLabel"
	_kid_name.position = Vector2(76, 152)
	_card.add_child(_kid_name)
	_hearts = HeartRow.new()
	_hearts.position = Vector2(77, 176)
	_hearts.size = Vector2(HeartRow.SIZE)
	_card.add_child(_hearts)
	_love_label = _label("")
	_love_label.theme_type_variation = &"PaperLabel"
	_love_label.position = Vector2(76, 194)
	_card.add_child(_love_label)
	# Letter: ruled note paper with a red margin line; text lines sit on the rules.
	_paper_sheet(_read_page, Vector2(150, 12), Vector2(316, 212))
	var rules := RuledLines.new()
	rules.position = Vector2(155, 17)
	rules.size = Vector2(306, 202)
	rules.first = 18 + BODY_ASCENT - 17  # text top + font ascent, in the rules' own coordinates
	rules.margin_x = TEXT_X - 4 - 155
	_read_page.add_child(rules)
	_paper_text = VBoxContainer.new()
	_paper_text.position = Vector2(TEXT_X, 18)
	_paper_text.size = Vector2(TEXT_W, 200)
	_paper_text.add_theme_constant_override("separation", LINE_GAP)
	_paper_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_read_page.add_child(_paper_text)
	_pack_btn = _button(tr("LET_PACK"), open_pack)
	_pack_btn.position = Vector2(150, 236)
	_pack_btn.size = Vector2(104, 20)
	_read_page.add_child(_pack_btn)
	_status = _label("")
	_status.position = Vector2(150, 226)
	_status.size = Vector2(250, 36)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_read_page.add_child(_status)
	_close_btn = _button(tr("LET_CLOSE"), close)
	_close_btn.position = Vector2(406, 236)
	_close_btn.size = Vector2(60, 20)
	_read_page.add_child(_close_btn)


func _build_pack() -> void:
	_pack_page = _page()
	var head := _label(tr("LET_YOUR_JARS"))
	head.theme_type_variation = &"Heading"
	head.position = Vector2(18, 13)
	_pack_page.add_child(head)
	_board = ArrangeBoard.new()
	_board.name = "Box"
	_board.sounds = SOUNDS
	_board.view_factory = _make_view
	_board.changed.connect(_on_board_changed)
	_board.entry_added.connect(_on_entry_added)
	_board.released_outside.connect(_on_released_outside)
	_board.hold_ended.connect(_on_hold_ended)
	var frame := BoxFrame.new()
	frame.position = Vector2(BOARD_POS) - Vector2(BoxFrame.PAD, BoxFrame.PAD + BoxFrame.FLAP)
	frame.size = Vector2(Letters.BOX_COLS * CELL, Letters.BOX_ROWS * CELL) + Vector2(BoxFrame.PAD * 2, BoxFrame.PAD * 2 + BoxFrame.FLAP)
	_pack_page.add_child(frame)
	_pack_page.add_child(_board)
	_board.position = BOARD_POS
	_source_view = InboxView.new()
	_source_view.position = Vector2(16, 34)
	_source_view.size = Vector2(152, 176)
	_pack_page.add_child(_source_view)
	_source_view.setup(_source, _board, _make_view)
	_no_jars = _label(tr("LET_NO_JARS"))
	_no_jars.position = Vector2(22, 40)
	_no_jars.size = Vector2(140, 60)
	_no_jars.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_jars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pack_page.add_child(_no_jars)
	_parcel_title = _label("")
	_parcel_title.theme_type_variation = &"Heading"
	_parcel_title.position = Vector2(172, 34)
	_parcel_title.size = Vector2(128, 18)
	_parcel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pack_page.add_child(_parcel_title)
	_straw_btn = _button(tr("LET_STRAW"), _on_straw)
	_straw_btn.position = Vector2(178, 142)
	_straw_btn.size = Vector2(116, 20)
	_pack_page.add_child(_straw_btn)
	_send_btn = _button(tr("LET_SEND"), _on_send)
	_send_btn.position = Vector2(178, 166)
	_send_btn.size = Vector2(116, 20)
	_love_preview = _label("")
	_love_preview.position = Vector2(172, 189)
	_love_preview.size = Vector2(128, 18)
	_love_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pack_page.add_child(_love_preview)
	_pack_page.add_child(_send_btn)
	_hint = _label("")
	_hint.position = Vector2(172, 210)
	_hint.size = Vector2(128, 48)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pack_page.add_child(_hint)
	var back := _button(tr("LET_BACK"), _on_back)
	back.position = Vector2(16, 236)
	back.size = Vector2(60, 20)
	_pack_page.add_child(back)
	var paper := PanelContainer.new()
	paper.theme_type_variation = &"PaperPanel"
	paper.position = Vector2(306, 10)
	paper.size = Vector2(160, 248)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pack_page.add_child(paper)
	_checks = VBoxContainer.new()
	_checks.position = Vector2(313, 16)
	_checks.size = Vector2(146, 236)
	_checks.add_theme_constant_override("separation", 1)
	_pack_page.add_child(_checks)
	_pack_page.visible = false


func _page() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(c)
	return c


## A UI-kit paper panel (mouse passes through).
func _paper_sheet(parent: Control, pos: Vector2, sz: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"PaperPanel"
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


## Letter list row on paper: ruled underline, gold fill with a red bookmark edge when open, red text while unread.
func _style_row(b: Button, unread: bool) -> void:
	var normal := _row_box(false, Color("e5bd7f"))
	normal.border_width_bottom = 1
	var hover := _row_box(true, Color("c58845"))
	hover.bg_color = Color("dbcc83")
	hover.border_width_bottom = 1
	var open := _row_box(true, Color("c94d2e"))
	open.bg_color = Color("e5bd7f")
	open.border_width_left = 2
	open.content_margin_left = 2
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, normal)
	b.add_theme_stylebox_override("hover", hover)
	for st in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, open)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := RED if unread else PAPER_INK
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, ink)
	b.add_theme_constant_override("h_separation", 4)


func _row_box(fill: bool, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = fill
	s.border_color = border
	s.anti_aliasing = false
	s.content_margin_left = 4
	s.content_margin_right = 2
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	return s


## Thin palette scrollbar for the letter list (shows once the letters outgrow the sheet).
func _style_scrollbar(bar: ScrollBar) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("e5bd7f")
	track.anti_aliasing = false
	track.content_margin_left = 2
	track.content_margin_right = 2
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	for pair in [["grabber", "c58845"], ["grabber_highlight", "b66813"], ["grabber_pressed", "83571e"]]:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(String(pair[1]))
		g.anti_aliasing = false
		g.content_margin_left = 2
		g.content_margin_right = 2
		bar.add_theme_stylebox_override(String(pair[0]), g)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _clear(c: Node) -> void:
	for n in c.get_children():
		c.remove_child(n)
		n.queue_free()


func _make_view(item: Dictionary, rot: int, px: Vector2i) -> Control:
	if Letters.is_straw(item):
		var s := StrawView.new()
		s.size = Vector2(px)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return s
	return ArrangeItemView.make(item, rot, px, _data().get("varieties", {}))


## Letter list icon: an envelope (red seal while a request waits) or a heart for a thank-you note.
func _envelope(letter: Dictionary) -> Texture2D:
	var img := Image.create(11, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var reply := String(letter.kind) == "reply"
	img.fill_rect(Rect2i(0, 0, 11, 8), Color("83571e"))
	img.fill_rect(Rect2i(1, 1, 9, 6), Color("f2d9c5"))
	for i in 5:
		img.set_pixel(1 + i, 1 + floori(i * 0.8), Color("b9a697"))
		img.set_pixel(9 - i, 1 + floori(i * 0.8), Color("b9a697"))
	if reply:
		for p in [Vector2i(4, 3), Vector2i(6, 3), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(5, 5)]:
			img.set_pixel(p.x, p.y, Color("c94d2e"))
	elif String(letter.kind) == "request" and not bool(letter.get("done", false)):
		img.fill_rect(Rect2i(4, 4, 3, 2), RED)
	return ImageTexture.create_from_image(img)


func _save(keys: Array) -> void:
	var save := get_node_or_null("/root/Save")
	if save != null:
		save.save_game(_data())
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.notify(PackedStringArray(keys))


func _sfx(id: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play_sfx(id)


func _ui(id: String) -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		audio.play_ui(id)


# --- palette drawings --------------------------------------------------------------------------------------------

## Grandchild portrait on a framed backdrop: portrait_<kid>.png, else a 48x48 placeholder from palette rects.
## The texture is loaded when `kid` is set, not inside _draw (a texture first loaded mid-draw renders white).
class KidPortrait:
	extends Control
	const LOOKS := {
		"mia": {"bg": "738c7a", "hair": "c94d2e", "shirt": "dbcc83", "extra": "a22512"},
		"leo": {"bg": "567c7d", "hair": "50361e", "shirt": "a22512", "extra": "275e4c"},
	}
	var kid := "mia":
		set(v):
			kid = v
			var path := LettersUI.PORTRAIT % kid
			_tex = load(path) as Texture2D if ResourceLoader.exists(path) else null
			queue_redraw()
	var _tex: Texture2D

	func _draw() -> void:
		var look: Dictionary = LOOKS.get(kid, LOOKS.mia)
		draw_rect(Rect2(-1, -1, 50, 50), Color("50361e"))
		_r(0, 0, 24, 24, look.bg)
		if _tex != null:
			draw_texture(_tex, Vector2.ZERO)
			return
		if kid == "mia":
			_r(3, 7, 3, 7, look.hair)
			_r(18, 7, 3, 7, look.hair)
		_r(4, 18, 16, 6, look.shirt)
		_r(10, 16, 4, 3, "e19064")
		_r(7, 6, 10, 11, "e19064")
		_r(6, 3, 12, 4, look.hair)
		_r(6, 6, 2, 5, look.hair)
		_r(16, 6, 2, 5, look.hair)
		_r(9, 10, 1, 2, "111010")
		_r(14, 10, 1, 2, "111010")
		_r(11, 14, 2, 1, "a22512")
		_r(8, 13, 1, 1, "c94d2e")
		_r(15, 13, 1, 1, "c94d2e")
		if kid == "mia":
			_r(16, 2, 4, 2, look.extra)
		else:
			_r(6, 2, 12, 3, look.extra)
			_r(12, 5, 8, 1, look.extra)

	## Design grid 24x24, 2 px per unit.
	func _r(x: int, y: int, w: int, h: int, c: String) -> void:
		draw_rect(Rect2(x * 2, y * 2, w * 2, h * 2), Color(c))


## Love meter: 10 hearts in two rows of five, filled up to the kid's love, the rest drawn as empty outlines.
class HeartRow:
	extends Control
	const PATTERN := [".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]
	const SIZE := Vector2i(43, 14)
	var love := 0

	func _draw() -> void:
		for i in 10:
			var o := Vector2i((i % 5) * 9, floori(i / 5.0) * 8)
			var full := i < love
			for y in PATTERN.size():
				for x in 7:
					if PATTERN[y][x] != "X":
						continue
					if full:
						draw_rect(Rect2(o.x + x, o.y + y, 1, 1), Color("c94d2e"))
					elif _edge(x, y):
						draw_rect(Rect2(o.x + x, o.y + y, 1, 1), Color("b9a697"))

	func _edge(x: int, y: int) -> bool:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= 7 or ny >= PATTERN.size() or PATTERN[ny][nx] != "X":
				return true
		return false


## Ruled note paper: a rule under every text line (`first`, then every LINE_PITCH) and a red margin line.
class RuledLines:
	extends Control
	var first := 16
	var margin_x := 6

	func _draw() -> void:
		var y := first
		while y < int(size.y) - 1:
			draw_rect(Rect2(0, y, size.x, 1), Color("e5bd7f"))
			y += LettersUI.LINE_PITCH
		draw_rect(Rect2(margin_x, 0, 1, size.y), Color("e19064"))


## The child's drawing tucked into the letter: own sheet with a shadow, held on by a strip of tape.
class DrawingSheet:
	extends Control
	var texture: Texture2D

	func _draw() -> void:
		if texture == null:
			return
		var o := Vector2(1, 5)
		draw_rect(Rect2(o.x, o.y + 49, 50, 1), Color("b9a697"))
		draw_rect(Rect2(o.x + 49, o.y, 1, 50), Color("b9a697"))
		draw_rect(Rect2(o.x - 1, o.y - 1, 50, 50), Color("c58845"))
		draw_texture(texture, o)
		draw_rect(Rect2(o.x + 16, o.y - 4, 16, 6), Color("e5bd7f"))
		draw_rect(Rect2(o.x + 17, o.y - 3, 14, 4), Color("dbcc83"))


class CheckIcon:
	extends Control
	var on := false

	func _draw() -> void:
		draw_rect(Rect2(0, 4, 9, 9), Color("83571e"))
		draw_rect(Rect2(1, 5, 7, 7), Color("f2d9c5"))
		if on:
			for p in [Vector2i(2, 6), Vector2i(3, 7), Vector2i(4, 8), Vector2i(5, 7), Vector2i(6, 6), Vector2i(7, 5), Vector2i(7, 4)]:
				draw_rect(Rect2(p.x, p.y + 1, 1, 2), Color("4e7664"))


## Straw filling one box cell: dark bed, light and mid strands in a fixed pattern.
class StrawView:
	extends Control

	func _draw() -> void:
		var w := int(size.x)
		var h := int(size.y)
		draw_rect(Rect2(1, 1, w - 2, h - 2), Color("9b8039"))
		var tones := [Color("dbcc83"), Color("e5bd7f"), Color("b1a13d")]
		var k := 0
		for y in range(2, h - 2, 3):
			for x in range(2 + (y * 3) % 5, w - 4, 6):
				draw_rect(Rect2(x, y, 4, 1), tones[k % 3])
				draw_rect(Rect2(x + 1, y + 1, 2, 1), tones[(k + 1) % 3])
				k += 1


## Cardboard parcel around the board: walls, open flaps above.
class BoxFrame:
	extends Control
	const PAD := 6
	const FLAP := 10

	func _draw() -> void:
		var w := int(size.x)
		var h := int(size.y)
		var top := FLAP
		var half := floori(w / 2.0)
		for i in FLAP:
			var inset := floori((FLAP - 1 - i) / 2.0)
			var col := Color("e5bd7f") if i > 0 else Color("83571e")
			draw_rect(Rect2(inset, i, half - 1 - inset, 1), col)
			draw_rect(Rect2(half + 1, i, half - 1 - inset, 1), col)
			draw_rect(Rect2(inset, i, 1, 1), Color("83571e"))
			draw_rect(Rect2(w - inset - 1, i, 1, 1), Color("83571e"))
		draw_rect(Rect2(0, top, w, h - top), Color("83571e"))
		draw_rect(Rect2(1, top + 1, w - 2, h - top - 2), Color("c58845"))
		draw_rect(Rect2(1, top + 1, w - 2, 1), Color("e5bd7f"))
		draw_rect(Rect2(PAD - 1, top + PAD - 1, w - PAD * 2 + 2, h - top - PAD * 2 + 2), Color("50361e"))
		draw_rect(Rect2(half - 6, h - 4, 12, 2), Color("b9a697"))
