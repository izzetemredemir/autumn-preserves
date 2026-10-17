extends SceneTree
## Smoke shot (FUN-REACT): people react to the jar you made. A seed-1 day-7 game in memory (flags.temp: nothing is
## saved). Shots in user://shots: react_market.png (a buyer says a line about the jar they buy), react_town.png (a gift
## to Barnaby: his line beside his portrait, heart pop when he likes it), react_kitchen.png and react_kitchen_fx.png
## (Granny's line under the result card: a new recipe, an invention), react_letter.png (Mia's reply names a jar).
## `-- --locale=tr` plays it in Turkish and adds "_tr". Exit 1 when a check fails.
##   godot --audio-driver Dummy --path game -s res://tests/smoke/react_shot.gd [-- --locale=tr]

const RV := preload("res://scenes/market/react_view.gd")

var _gs: Node
var _suffix := ""
var _fails := 0


func _initialize() -> void:
	_gs = root.get_node("GameState")
	_run()


func _run() -> void:
	await process_frame
	if "--locale=tr" in OS.get_cmdline_user_args():
		GameSettings.apply_language("tr")
		_suffix = "_tr"
	await _market()
	await _town()
	await _kitchen(false)
	await _kitchen(true)
	await _letter()
	print("react_shot: %s" % ("OK" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _state() -> Dictionary:
	var s := State.new_game(1)
	s.day = 7
	s.flags["temp"] = true
	_gs.set("data", s)
	return s


# --- market: a buyer's line as they buy ----------------------------------------------------------------------------

func _market() -> void:
	var s := _state()
	s.inbox = (load("res://scenes/market/market.gd") as GDScript).call("sample_items")
	var m: Control = (load("res://scenes/market/market.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await _frames(8)
	m.call("_on_fill")
	await _frames(4)
	m.call("_on_open")
	await _frames(4)
	var crowd: Dictionary = m.get("_crowd")
	var plan: Dictionary = m.get("_plan")
	# the first buyer who speaks, better one whose line names the jar (the line the market will build)
	var at := -1.0
	var named_at := -1.0
	for l in crowd.lines:
		var who := String(l.who)
		if not who.begins_with("p"):
			continue
		for p in crowd.people:
			if "p%d" % int(p.id) == who and String(p.kind) == "buyer":
				var v: Dictionary = plan.visits[int(p.visit)]
				var sd := Reactions.seed_for(1, 7, String(v.item.key), "buyer%d" % int(p.visit))
				if Reactions.speaks(sd):
					var desc := Reactions.describe(String(v.item.key), s.varieties, int(v.item.q))
					var line := Reactions.line(desc, "buyer", "", sd, {"likes": v.customer.wants})
					if at < 0.0:
						at = float(l.t)
					if named_at < 0.0 and float(l.t) > 1.5 and line.contains(String((desc.names as Array).back())):
						named_at = float(l.t)
	if named_at >= 0.0:
		at = named_at
	_check("a buyer who speaks", at >= 0.0)
	m.set("_t", maxf(0.0, at - 0.05))
	var bubble: SpeechBubble = null
	for i in 300:
		await process_frame
		for b in (m.get("_bubbles") as Control).get("_active"):
			if String(b.key) == "REACT_LINE":
				bubble = b.node
		if bubble != null:
			break
	await create_timer(0.35).timeout  # the pop-in
	var text := bubble.label.text if bubble != null else ""
	_check("a reaction SpeechBubble: %s" % text, text != "" and bubble.label.get_theme_font_size("font_size") == 16)
	if bubble != null:
		_check("within %d lines, %d px (%d, %d)" % [SpeechBubble.LINES, SpeechBubble.MAX_W, bubble.line_count(), bubble.size.x],
			bubble.line_count() <= SpeechBubble.LINES and bubble.size.x <= SpeechBubble.MAX_W)
	_shot("react_market")
	m.queue_free()
	await _frames(3)


# --- town: a gift to Barnaby ---------------------------------------------------------------------------------------

func _town() -> void:
	var s := _state()
	var key := ""
	for c in Orders.candidates(s, Orders.product_taste()):
		var desc := Reactions.describe(String(c.key), s.varieties, 3)
		if Reactions.liked(desc, "grocer") != "" and String(desc.name).length() >= 18:
			key = String(c.key)
			break
	_check("a jar Barnaby likes", key != "")
	s.inbox.append(State.product(key, 3, 0))
	var town: Control = (load("res://scenes/town/town.tscn") as PackedScene).instantiate()
	root.add_child(town)
	await _frames(8)
	town.call("_on_tab", "neighbours")
	await _frames(4)
	town.set("_picker", {"kind": "gift", "id": "grocer"})
	town.call("_do_gift", {"where": "inbox", "index": s.inbox.size() - 1})
	await create_timer(0.3).timeout
	var card: Control = town.get_node_or_null("Reaction")
	_check("delivery card up", card != null)
	if card != null:
		var line := String(card.call("text"))
		_check("Barnaby's line: %s" % line.replace("\n", " "), line != "")
		var r := Rect2(card.position, card.size)
		_check("card on screen, over the square %s" % r, r.position.y >= 60.0 and r.end.y <= 146.0 and r.end.x <= 477.0)
		var heart := false
		for ch in card.get_children():
			heart = heart or ch.get_script() == RV.HeartPop
		_check("heart pop for a liked jar", heart)
	_shot("react_town")
	await create_timer(4.2).timeout
	_check("card goes by itself", town.get_node_or_null("Reaction") == null)
	town.queue_free()
	await _frames(3)


# --- kitchen: Granny under the result card -------------------------------------------------------------------------

func _kitchen(invention: bool) -> void:
	var s := _state()
	var vids: Array = s.varieties.keys()
	vids.sort()
	var key := ""
	if invention:  # a pair whose line plays with the invention's own words (most do)
		for i in range(1, vids.size()):
			key = FormulaGen.make_key("stir_pot", [vids[0], vids[i]], ["cinnamon"])
			var desc := Reactions.describe(key, s.varieties, 3)
			var line := Reactions.line(desc, "granny", "", Reactions.seed_for(1, 7, key, "granny"), {"max": 44})
			if line.contains(String(desc.noun)) or line.contains(String((desc.words as Array)[0])):
				break
	else:
		for c in Orders.candidates(s, Orders.product_taste()):
			if String(c.recipe) == "jam":
				key = String(c.key)
	var k: Control = (load("res://scenes/kitchen/kitchen.tscn") as PackedScene).instantiate()
	root.add_child(k)
	await _frames(8)
	var item := State.product(key, 3, 0)
	k.call("_show_result", {"ok": true, "item": item, "items": [item], "desc": ProductGen.describe(key, s.varieties),
		"is_new": true, "quality": 3, "mastered": false, "formula": invention, "key": key})
	await create_timer(1.2).timeout
	var card: Node = k.get("_card")
	var gl: Control = card.get_node_or_null("GrannyLine") if card != null else null
	_check("Granny's line under the card", gl != null)
	if gl != null:
		var line := String(gl.call("text"))
		_check("one short line: %s" % line, line != "" and not line.contains("\n") and gl.size.x <= 320.0)
		var panel: Control = null
		for c in card.get_children():
			if c is PanelContainer:
				panel = c
		var gr := gl.get_global_rect()
		_check("clear of the card %s" % gr, panel != null and not gr.intersects(panel.get_global_rect()))
		_check("on screen", gr.position.y >= 2.0 and gr.end.y <= 268.0)
	_shot("react_kitchen_fx" if invention else "react_kitchen")
	k.queue_free()
	await _frames(3)


# --- letters: Mia's reply names a jar ------------------------------------------------------------------------------

func _letter() -> void:
	var s := _state()
	var l := Letters.ensure(s)
	var keys: Array = []
	for c in Letters.kid_candidates(s, "mia"):
		if keys.size() < 2:
			keys.append(String(c.key))
	l.sent.append({"letter": 1, "to": "mia", "day": 5, "reply_day": 7, "keys": keys, "care": true, "hearts": 3,
		"unlocked": [], "replied": true})
	var reply := {"id": 2, "kind": "reply", "from": "mia", "day": 7, "note": "LET_REPLY_MIA_1", "re": 1, "care": true,
		"care_note": "LET_REPLY_CARE_MIA", "hearts": 3, "unlocked": [], "read": false}
	l.inbox.append(reply)
	l.next_id = 3
	var line := Letters.reply_line(s, reply)
	var name := String(Reactions.describe(Letters.reply_jar(s, reply), s.varieties, 2).names[0])
	_check("the reply names the jar: %s" % line, line != "" and line.contains(name.split(" ")[name.split(" ").size() - 1]))
	var ui := LettersUI.open(2)
	await _frames(12)
	_shot("react_letter")
	ui.queue_free()
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(n: String) -> void:
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("%s/%s%s.png" % [dir, n, _suffix])
	print("saved ", n, _suffix)


func _check(what: String, ok: bool) -> void:
	print("react_shot: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
