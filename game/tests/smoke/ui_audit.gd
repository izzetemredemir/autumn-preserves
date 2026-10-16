extends SceneTree
## QA-UI: loads every scene and overlay with the demo save, walks visible Label / RichTextLabel / Button nodes and reports
## text that overflows its rect, font sizes other than 18/36, text closer than 2 px to the screen edge and overlapping
## text boxes. Writes docs/qa/ui_audit.md. Exit 1 on any finding (CI runs it with --report=user://ui_audit.md).
##   godot --headless --path game -s res://tests/smoke/ui_audit.gd
## Extra args after `--`: `--report=<path>` to write elsewhere, `--locale=tr` to audit the Turkish texts (L10N-TR;
## default `en`, report docs/qa/ui_audit_tr.md). CI runs it once per language.

const SCREEN := Rect2(0, 0, 480, 270)
const EDGE := 2.0
const SIZES := [18, 36]
## Path fragments (scene file or script) whose findings must be zero; others are only listed.
const OWNED := ["scenes/garden/", "scenes/pantry/", "scenes/title/", "scenes/seed_lab/", "ui/book/", "ui/letters/", "ui/hud/", "ui/result_card/",
	"scenes/farewell/"]

var _gs: Node
var _findings: Array = []  ## {state, kind, path, origin, owned, detail}
var _states := 0
var _texts := 0
var _seen := {}
var _locale := "en"


func _initialize() -> void:
	# Headless windows are 64x64; 'keep' makes the viewport the real 480x270 the game targets.
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_gs = root.get_node("GameState")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--locale="):
			_locale = a.substr(9)
	GameSettings.apply_language(_locale)
	_run()


func _fresh() -> void:
	_gs.data = DevTools.load_demo()
	_gs.notify(PackedStringArray(["*"]))


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	await process_frame
	var scenes := {
		"title": "res://scenes/title/title.tscn",
		"garden": "res://scenes/garden/garden.tscn",
		"pantry": "res://scenes/pantry/pantry.tscn",
		"seed_lab": "res://scenes/seed_lab/seed_lab.tscn",
		"town": "res://scenes/town/town.tscn",
		"kitchen": "res://scenes/kitchen/kitchen.tscn",
		"wild": "res://scenes/wild/wild.tscn",
		"wild_map": "res://scenes/wild/wild_map.tscn",
	}
	for n in scenes:
		_fresh()
		var s := (load(scenes[n]) as PackedScene).instantiate()
		root.add_child(s)
		await _frames(6)
		await _audit(n, s)
		if n == "title":
			await _title_panels(s)
		elif n == "town":
			for tab in ["orders", "neighbours"]:
				s._on_tab(tab)
				await _frames(3)
				await _audit("town/" + tab, s)
		elif n == "garden":
			await _overlays("garden")
		s.queue_free()
		await _frames(2)
	await _farewell()
	# Overlays on top of a quiet backdrop
	_fresh()
	var bg := ColorRect.new()
	bg.color = Color("747c37")
	bg.size = SCREEN.size
	root.add_child(bg)
	var hud := (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await _frames(4)
	hud.show_toast("UI_TIRED")
	await create_timer(0.4).timeout
	await _audit("hud", hud)
	hud.queue_free()
	await _overlays("backdrop")
	for p in ["res://ui/premise/premise.tscn", "res://ui/transition/night.tscn"]:
		var o := (load(p) as PackedScene).instantiate()
		root.add_child(o)
		await _frames(8)
		await _audit(p.get_file().get_basename(), o)
		o.queue_free()
		await _frames(2)
	_write(Time.get_ticks_msec() - t0)
	var owned := _findings.filter(func(f): return f.owned).size()
	print("ui_audit [%s]: %d states, %d texts, %d findings (%d in owned folders)" % [_locale, _states, _texts, _findings.size(), owned])
	quit(1 if _findings.size() > 0 else 0)


func _title_panels(s: Node) -> void:
	s._on_new_game()
	await _frames(4)
	await _audit("title/new_game", s)
	s._show_menu()
	s._on_settings()
	await _frames(4)
	await _audit("title/settings", s)
	s._show_menu()
	if s.get("_completed_card") == null:
		s._show_completed(100)
	await _frames(4)
	await _audit("title/completed", s)


## P2-FAREWELL: each part of the farewell once its text is in (credits mid-scroll), the Memory screen and its shelf.
func _farewell() -> void:
	_fresh()
	root.get_node("Router").params = {"mode": "play"}
	var fw := (load("res://scenes/farewell/farewell.tscn") as PackedScene).instantiate()
	root.add_child(fw)
	await _frames(4)
	for part in fw.get("_timeline"):
		var into := 9.0 if part.id == "credits" else float(part.dur) - 1.5
		fw.seek(float(part.start) + into)
		await _frames(3)
		await _audit("farewell/" + String(part.id), fw)
	fw.open_memory()
	await _frames(4)
	await _audit("farewell/memory", fw)
	fw._open_browse()
	await _frames(4)
	await _audit("farewell/memory_pantry", fw)
	fw.queue_free()
	root.get_node("Router").params = {}
	await _frames(2)


func _overlays(tag: String) -> void:
	var b := Book.open()
	await _frames(10)
	for tab in 3:
		b.show_book(tab)
		await _frames(4)
		await _audit("%s/book_tab%d" % [tag, tab], b)
		if tab == 0:
			b._flip(1)
			await _frames(4)
			await _audit("%s/book_tab0_p2" % tag, b)
	b.queue_free()
	await _frames(2)
	var s: Dictionary = _gs.data
	Letters.ensure(s)
	if s.letters.inbox.is_empty():
		s.letters.inbox.append(Letters.make_request(s, "mia", Seeds.rng(1, "letters", 4)))
	var ui := LettersUI.open()
	await _frames(10)
	await _audit(tag + "/letters", ui)
	ui.queue_free()
	await _frames(2)
	var keys: Array = s.book.variants.keys()
	if not keys.is_empty():
		var desc := ProductGen.describe(keys[0], s.varieties)
		desc["value"] = 12
		var rc := (load("res://ui/result_card/result_card.tscn") as PackedScene).instantiate()
		root.add_child(rc)
		rc.show_result(desc, 3, true)
		await _frames(30)
		await _audit(tag + "/result_card", rc)
		rc.queue_free()
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


# ---------------------------------------------------------------- audit

func _audit(state: String, node: Node) -> void:
	_states += 1
	var items: Array = []  ## {node, rect, text}
	_collect(node, items)
	for it in items:
		_check(state, it)
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Dictionary = items[i]
			var b: Dictionary = items[j]
			var inter: Rect2 = (a.rect as Rect2).intersection(b.rect)
			if inter.size.x > 1.0 and inter.size.y > 1.0 and _layer(a.node) == _layer(b.node):
				_add(state, "overlap", a.node, "with %s (%dx%d px)" % [_short(b.node), inter.size.x, inter.size.y], b.node)


func _layer(n: Node) -> Node:
	var p := n.get_parent()
	while p != null:
		if p is CanvasLayer:
			return p
		p = p.get_parent()
	return null


func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if (n is Label or n is RichTextLabel or n is Button) and (n as Control).is_visible_in_tree():
		var c := n as Control
		var txt := _text_of(c)
		if txt.strip_edges() != "" and c.modulate.a > 0.05 and c.self_modulate.a > 0.05:
			out.append({"node": c, "rect": _text_rect(c, txt), "text": txt})
	for ch in n.get_children():
		_collect(ch, out)


func _text_of(c: Control) -> String:
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	var raw: String = c.get("text")
	return c.tr(raw) if raw != "" else ""


func _font_size(c: Control) -> int:
	if c is RichTextLabel:
		return c.get_theme_font_size("normal_font_size")
	return c.get_theme_font_size("font_size")


## Rect (global) of the text actually drawn.
func _text_rect(c: Control, txt: String) -> Rect2:
	var g := c.get_global_rect()
	var sz := _needed(c, txt)
	var pos := g.position
	if c is Label:
		var l := c as Label
		match l.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER:
				pos.x += (g.size.x - sz.x) * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT:
				pos.x += g.size.x - sz.x
		match l.vertical_alignment:
			VERTICAL_ALIGNMENT_CENTER:
				pos.y += (g.size.y - sz.y) * 0.5
			VERTICAL_ALIGNMENT_BOTTOM:
				pos.y += g.size.y - sz.y
	elif c is Button:
		var icon_w := 0.0
		if (c as Button).icon != null:
			icon_w = (c as Button).icon.get_width() + 2
		pos.x += (g.size.x - sz.x - icon_w) * 0.5 + icon_w
		pos.y += (g.size.y - sz.y) * 0.5
	return Rect2(pos, sz)


## Size the text needs (wrapped at the available width where the control wraps).
func _needed(c: Control, txt: String) -> Vector2:
	if c is RichTextLabel:
		var r := c as RichTextLabel
		return Vector2(r.get_content_width(), r.get_content_height())
	var font := c.get_theme_font("font")
	var fs := _font_size(c)
	var width := -1.0
	if c is Label and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
		width = c.size.x
	if c is Button and (c as Button).autowrap_mode != TextServer.AUTOWRAP_OFF:
		width = c.size.x - _button_pad(c as Button)
	var s := font.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, width, fs)
	if c is Label and (c as Label).max_lines_visible > 0:
		s.y = minf(s.y, font.get_height(fs) * (c as Label).max_lines_visible)
	return s


func _button_pad(b: Button) -> float:
	var sb := b.get_theme_stylebox("normal")
	var pad := 0.0
	if sb != null:
		pad = sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
	if b.icon != null:
		pad += b.icon.get_width() + 2
	return pad


func _check(state: String, it: Dictionary) -> void:
	var c: Control = it.node
	_texts += 1
	var fs := _font_size(c)
	if not SIZES.has(fs):
		_add(state, "font-size", c, "%d px" % fs)
	var g := c.get_global_rect()
	var need := _needed(c, it.text)
	var avail := c.size
	if c is Button:
		var sb := c.get_theme_stylebox("normal")
		avail.x -= _button_pad(c as Button)
		if sb != null:
			avail.y -= sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM)
	if need.x > avail.x + 0.5 or need.y > avail.y + 0.5:
		if not _in_scroll(c):
			_add(state, "overflow", c, "needs %dx%d, has %dx%d: \"%s\"" % [need.x, need.y, avail.x, avail.y, _clip(it.text)])
	var r: Rect2 = it.rect
	if r.position.x < SCREEN.position.x + EDGE or r.position.y < SCREEN.position.y + EDGE \
			or r.end.x > SCREEN.end.x - EDGE or r.end.y > SCREEN.end.y - EDGE:
		if _visible_rect(c).intersects(SCREEN):
			_add(state, "edge", c, "text rect %s \"%s\"" % [_fmt(r), _clip(it.text)])


func _in_scroll(c: Control) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _visible_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null:
		if p is Control and (p as Control).clip_contents:
			r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r


func _fmt(r: Rect2) -> String:
	return "(%d,%d)-(%d,%d)" % [r.position.x, r.position.y, r.end.x, r.end.y]


func _clip(s: String) -> String:
	s = s.replace("\n", " ").replace("|", "/")
	return s if s.length() <= 40 else s.substr(0, 37) + "..."


func _short(n: Node) -> String:
	var parts := str(n.get_path()).split("/")
	return "/".join(parts.slice(maxi(parts.size() - 3, 0)))


## Script or scene file that most likely owns the node; prefers one inside an owned folder.
func _origin(n: Node) -> String:
	var first := ""
	var p := n
	while p != null:
		var sc = p.get_script()
		var cand: String = (sc as Script).resource_path if sc != null else ""
		if cand == "":
			cand = p.scene_file_path
		if cand != "":
			if _is_owned(cand):
				return cand
			if first == "":
				first = cand
		p = p.get_parent()
	return first


func _is_owned(path: String) -> bool:
	for f in OWNED:
		if path.contains(f):
			return true
	return false


func _add(state: String, kind: String, n: Node, detail: String, other: Node = null) -> void:
	var path := "/".join(str(n.get_path()).split("/").slice(2))
	var origin := _origin(n)
	var owned := _is_owned(origin)
	if other != null and not owned and _is_owned(_origin(other)):
		owned = false  # overlap with an owned node from foreign code: the foreign side owns it
	var key := "%s|%s|%s|%s" % [state, kind, path, detail]
	if _seen.has(key):
		return
	_seen[key] = true
	_findings.append({"state": state, "kind": kind, "path": path, "origin": origin.replace("res://", ""), "owned": owned, "detail": detail})


func _write(ms: int) -> void:
	var out := PackedStringArray()
	var owned: Array = _findings.filter(func(f): return f.owned)
	var other: Array = _findings.filter(func(f): return not f.owned)
	out.append("# UI audit")
	out.append("")
	out.append("Generated by `godot --headless --path game -s res://tests/smoke/ui_audit.gd -- --locale=%s` (demo save, %d states, %d text nodes, %.1f s)." % [_locale, _states, _texts, ms / 1000.0])
	out.append("")
	out.append("Checks: text larger than its rect (overflow), font size not 18/36, text rect closer than %d px to the 480x270 screen edge, overlapping text boxes on the same layer." % int(EDGE))
	out.append("")
	out.append("- Owned folders (garden, pantry, title, seed_lab, book, letters, hud, result_card): **%d findings**." % owned.size())
	out.append("- Other folders (kitchen, town, wild, market, shared; listed only, not fixed here): **%d findings**." % other.size())
	for part in [["Findings in owned folders", owned], ["Findings elsewhere", other]]:
		out.append("")
		out.append("## " + part[0])
		out.append("")
		if part[1].is_empty():
			out.append("None.")
			continue
		out.append("| State | Check | Node path | Source | Detail |")
		out.append("|---|---|---|---|---|")
		for f in part[1]:
			out.append("| %s | %s | `%s` | %s | %s |" % [f.state, f.kind, f.path, f.origin, f.detail.replace("|", "/")])
	var report := "ui_audit.md" if _locale == "en" else "ui_audit_%s.md" % _locale
	var path := ProjectSettings.globalize_path("res://").path_join("../docs/qa/" + report).simplify_path()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--report="):
			path = a.substr(9)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
