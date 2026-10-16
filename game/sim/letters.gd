class_name Letters
extends RefCounted
## P1-LETTERS · Grandchild letters and care parcels (spec §6.7, §7.6). Pure rules, stream "letters", no autoloads.
## state.letters is created lazily by ensure(), so saves from before this card still load:
##   {"inbox": [letter], "sent": [parcel], "love": {"leo": int, "mia": int}, "unlocked_recipes": [family recipe id],
##    "next_id": int, "next_day": int (day the next request letter is due), "last_from": kid id}
## letter  {"id", "kind": "request"|"reply", "from": kid id, "day", "note": i18n key, "read": bool, plus
##          request: "request": [{"recipe": recipe id or "", "taste": axis or ""}], "done": bool
##          reply:   "re": request letter id, "care": bool, "hearts": int, "unlocked": [recipe ids], "care_note": key
## parcel  {"letter", "to", "day", "reply_day", "keys": [product keys], "care", "hearts", "unlocked", "replied"}
## Kids come from Data.npcs().grandkids ({"likes": [2 axes], "dislikes_group": ingredient group}).
## A parcel is a 3x2 box of ArrangeBoard entries ({"item","x","y","rot"}); straw is the item {"kind": "straw"}.

## Days between request letters (the postman's reward shortens the upper end).
const GAP := [3, 4]
## The first letter comes with the first market, on day 7 (spec §8.4); a save that is already past it gets one tomorrow.
const FIRST_DAY := 7
const REQUEST_SIZE := [2, 3]
const REPLY_DAYS := 2
const CARE_HEARTS := 2
## Love per kid that unlocks the kid's family recipes, in order.
const LOVE_STEPS := [3, 6, 10]
## Family recipe ids: recipes.json family rows (KITCHEN-P1C, Kitchen.family_*); names are LET_RECIPE_<ID>.
const FAMILY_RECIPES := {
	"mia": ["grannys_quince_butter", "blackberry_honey_jam", "crabapple_jelly"],
	"leo": ["pepper_relish", "chili_pickles", "salted_porcini"],
}
const BOX_COLS := 3
const BOX_ROWS := 2
## Note keys LET_NOTE_<KID>_1..NOTE_COUNT, replies LET_REPLY_<KID>_1..REPLY_COUNT, care line LET_REPLY_CARE_<KID>.
## On days 90-99 request notes are worried ones instead (Farewell.note_key, same draw: the stream is unchanged).
const NOTE_COUNT := 6
const REPLY_COUNT := 3
## Request draw: P(taste) and P(recipe) per item (both can hold), P(liked axis | taste), tries before the fallback.
const TASTE_CHANCE := 0.75
const RECIPE_CHANCE := 0.55
const LIKED_CHANCE := 0.7
const REQUEST_TRIES := 10


## Creates state.letters (and any key an older version lacked). Returns it.
static func ensure(state: Dictionary) -> Dictionary:
	if typeof(state.get("letters")) != TYPE_DICTIONARY:
		state["letters"] = {"inbox": [], "sent": [], "love": {}, "unlocked_recipes": [], "next_id": 1,
			"next_day": maxi(FIRST_DAY, int(state.day) + 1), "last_from": ""}
	var l: Dictionary = state.letters
	for k in ["inbox", "sent", "unlocked_recipes"]:
		if typeof(l.get(k)) != TYPE_ARRAY:
			l[k] = []
	if typeof(l.get("love")) != TYPE_DICTIONARY:
		l["love"] = {}
	for kid in kids():
		if not l.love.has(kid):
			l.love[kid] = 0
	if not l.has("next_id"):
		l["next_id"] = l.inbox.size() + 1
	if not l.has("next_day"):
		l["next_day"] = int(state.day) + GAP[0]
	if not l.has("last_from"):
		l["last_from"] = ""
	return l


## Sorted grandchild ids.
static func kids() -> Array:
	var out: Array = Data.npcs().get("grandkids", {}).keys()
	out.sort()
	return out


static func kid_info(kid: String) -> Dictionary:
	return Data.npcs().get("grandkids", {}).get(kid, {})


static func kid_name(kid: String) -> String:
	return String(kid_info(kid).get("name", kid.capitalize()))


## Night step (spec §9 "letters and parcels", runs after the day number moved on): replies whose day has come,
## then a new request letter when one is due. Returns [{"type": "letter", "letter": letter}].
static func night(state: Dictionary) -> Array:
	var l := ensure(state)
	var day := int(state.day)
	var events: Array = []
	for p in l.sent:
		if not bool(p.get("replied", false)) and day >= int(p.reply_day):
			p.replied = true
			var reply := _reply(state, p)
			l.inbox.append(reply)
			events.append({"type": "letter", "letter": reply})
	if day >= int(l.next_day):
		var r := Seeds.rng(int(state.save_seed), "letters", day)
		var kid := _pick_kid(state, r)
		if kid == "":
			l.next_day = day + 1  # both kids still wait for a parcel; look again tomorrow
		else:
			var letter := make_request(state, kid, r)
			l.inbox.append(letter)
			l.last_from = kid
			l.next_day = day + gap(state, r)
			events.append({"type": "letter", "letter": letter})
	return events


## Days until the next request letter: GAP, upper end shortened by the postman's "letters_more_often" reward.
static func gap(state: Dictionary, r: RandomNumberGenerator) -> int:
	var hi := int(GAP[1])
	var npcs := Data.npcs()
	for npc_id in npcs:
		var reward: Variant = npcs[npc_id].get("reward")
		if typeof(reward) == TYPE_DICTIONARY and reward.get("kind", "") == "letters_more_often" \
				and Economy.hearts(state, npc_id) >= int(reward.hearts):
			hi -= int(reward.value)
	return r.randi_range(int(GAP[0]), maxi(int(GAP[0]), hi))


## A new request letter from `kid` (not committed to the inbox). Every item is satisfiable with unlocked P0
## recipes, common varieties and shop add-ins, never with the kid's disliked group (see kid_candidates).
static func make_request(state: Dictionary, kid: String, r: RandomNumberGenerator, taste_fn: Callable = Callable()) -> Dictionary:
	var l := ensure(state)
	var cands := kid_candidates(state, kid, taste_fn)
	var n := r.randi_range(int(REQUEST_SIZE[0]), int(REQUEST_SIZE[1]))
	var reqs: Array = []
	var seen := {}
	for i in n:
		var req := _draw_request(r, kid, cands, seen)
		seen[_req_id(req)] = true
		reqs.append(req)
	var letter := {"id": int(l.next_id), "kind": "request", "from": kid, "day": int(state.day),
		"note": Farewell.note_key(kid, r.randi_range(1, NOTE_COUNT), int(state.day)),  # days 90-99: worried notes
		"request": reqs, "done": false, "read": false}
	l.next_id = int(l.next_id) + 1
	return letter


## Orders.candidates without products holding the kid's disliked group.
static func kid_candidates(state: Dictionary, kid: String, taste_fn: Callable = Callable()) -> Array:
	var fn := taste_fn if taste_fn.is_valid() else Orders.product_taste()
	var out: Array = []
	for c in Orders.candidates(state, fn):
		if not dislikes(kid, String(c.key)):
			out.append(c)
	return out


## Can one of `cands` meet the request item?
static func satisfiable(req: Dictionary, cands: Array) -> bool:
	for c in cands:
		if meets(req, String(c.recipe), c.taste):
			return true
	return false


## The request rule on plain values: recipe (when named) and taste axis >= rules.orders.axis_threshold (when named).
static func meets(req: Dictionary, recipe_id: String, taste: Array) -> bool:
	if String(req.get("recipe", "")) != "" and String(req.recipe) != recipe_id:
		return false
	var axis := String(req.get("taste", ""))
	if axis != "":
		var i := ProductGen.AXES.find(axis)
		if i < 0 or i >= taste.size() or int(taste[i]) < int(Data.rules().orders.axis_threshold):
			return false
	return true


## Does the product key hold a variety of the kid's disliked group?
static func dislikes(kid: String, key: String) -> bool:
	var group := String(kid_info(kid).get("dislikes_group", ""))
	if group == "":
		return false
	var ings := Data.ingredients()
	for v in ProductGen.parse_key(key).varieties:
		if String(ings.get(State.type_of_variety(String(v)), {}).get("group", "")) == group:
			return true
	return false


## A ready product (no waiting left) the kid does not dislike.
static func giftable(kid: String, item: Dictionary) -> bool:
	return String(item.get("kind", "")) == "product" and int(item.get("wait_left", 0)) <= 0 \
		and not dislikes(kid, String(item.get("key", "")))


## Does the product meet one request item for this kid?
static func item_meets(kid: String, req: Dictionary, item: Dictionary, varieties: Dictionary) -> bool:
	return giftable(kid, item) and meets(req, State.item_type(item), ProductGen.taste(String(item.key), varieties))


## Surprise candidate: a giftable product with one of the kid's liked axes >= rules.friendship.gift_like_min (4).
static func is_surprise(kid: String, item: Dictionary, varieties: Dictionary) -> bool:
	if not giftable(kid, item):
		return false
	var t := ProductGen.taste(String(item.key), varieties)
	var need := int(Data.rules().friendship.gift_like_min)
	for axis in kid_info(kid).get("likes", []):
		var i := ProductGen.AXES.find(axis)
		if i >= 0 and i < t.size() and int(t[i]) >= need:
			return true
	return false


# --- parcel ------------------------------------------------------------------------------------------------------

static func box_board() -> Dictionary:
	var zones: Array = []
	for i in BOX_COLS * BOX_ROWS:
		zones.append("box")
	return {"name": "parcel", "cols": BOX_COLS, "rows": BOX_ROWS, "zones": zones}


static func straw() -> Dictionary:
	return {"kind": "straw"}


static func is_straw(item: Dictionary) -> bool:
	return String(item.get("kind", "")) == "straw"


## Every entry inside the box, no overlaps.
static func fits_box(entries: Array) -> bool:
	var b := box_board()
	var taken := {}
	for e in entries:
		for c in PantryRules.entry_cells(e):
			if PantryRules.zone_at(b, c) == "" or taken.has(c):
				return false
			taken[c] = true
	return true


## Fills every empty box cell with straw (appended to `entries`). Returns how many were added.
static func fill_straw(entries: Array) -> int:
	var taken := PantryRules.occupancy(entries)
	var n := 0
	for y in BOX_ROWS:
		for x in BOX_COLS:
			if not taken.has(Vector2i(x, y)):
				entries.append({"item": straw(), "x": x, "y": y, "rot": 0})
				n += 1
	return n


## Removes every straw entry. Returns how many were removed.
static func clear_straw(entries: Array) -> int:
	var n := 0
	for i in range(entries.size() - 1, -1, -1):
		if is_straw(entries[i].item):
			entries.remove_at(i)
			n += 1
	return n


## Read-only check of a parcel against a request letter (live UI ticks and pack()):
## {"ticks": [bool per request item], "matched", "met", "products", "full", "straw", "surprise", "care", "hearts"}.
## Requests are matched to products one to one (best matching); a surprise is a product left over after that.
static func evaluate(state: Dictionary, letter: Dictionary, entries: Array) -> Dictionary:
	var kid := String(letter.get("from", ""))
	var reqs: Array = letter.get("request", [])
	var varieties: Dictionary = state.get("varieties", {})
	var products: Array = []
	var cells := 0
	for e in entries:
		var it: Dictionary = e.item
		var sz := PantryRules.item_size(it, int(e.get("rot", 0)))
		cells += sz.x * sz.y
		if String(it.get("kind", "")) == "product":
			products.append(it)
	var can: Array = []
	for req in reqs:
		var list: Array = []
		for p in products.size():
			if item_meets(kid, req, products[p], varieties):
				list.append(p)
		can.append(list)
	var surprise: Array = []
	for p in products:
		surprise.append(is_surprise(kid, p, varieties))
	var best := {}
	var assign: Array = []
	assign.resize(reqs.size())
	assign.fill(-1)
	_search(0, can, {}, assign, surprise, best)
	var ticks: Array = []
	for a in best.get("assign", assign):
		ticks.append(int(a) >= 0)
	var matched := int(best.get("matched", 0))
	var met := not reqs.is_empty() and matched == reqs.size()
	var full := cells >= BOX_COLS * BOX_ROWS
	var has_surprise := bool(best.get("surprise", false))
	var care := met and full and has_surprise
	return {"ticks": ticks, "matched": matched, "met": met, "products": products.size(), "full": full,
		"straw": full, "surprise": has_surprise, "care": care, "hearts": matched + (CARE_HEARTS if care else 0)}


## Sends the parcel for request letter `letter_id`. The products must be the very item Dictionaries held in
## state.inbox or state.pantry (identity); they leave the state. Hearts: +1 per met request item, +2 for care;
## crossing LOVE_STEPS unlocks the kid's next family recipe. The reply arrives REPLY_DAYS later (night()).
## {"ok", "reason", ...evaluate(), "love": int, "unlocked": [ids], "reply_day": int}
static func pack(state: Dictionary, letter_id: int, parcel_entries: Array) -> Dictionary:
	var l := ensure(state)
	var letter := find_letter(state, letter_id)
	if letter.is_empty() or String(letter.kind) != "request" or bool(letter.get("done", false)):
		return {"ok": false, "reason": "LET_NO_LETTER"}
	if not fits_box(parcel_entries):
		return {"ok": false, "reason": "LET_BOX_BAD"}
	var products: Array = []
	for e in parcel_entries:
		var it: Dictionary = e.item
		if is_straw(it):
			continue
		if String(it.get("kind", "")) != "product":
			return {"ok": false, "reason": "LET_ONLY_JARS"}
		if int(it.get("wait_left", 0)) > 0:
			return {"ok": false, "reason": "LET_NOT_READY"}
		for q in products:
			if is_same(q, it):
				return {"ok": false, "reason": "UI_NOT_AVAILABLE"}
		if _locate(state, it).is_empty():
			return {"ok": false, "reason": "UI_NOT_AVAILABLE"}
		products.append(it)
	if products.is_empty():
		return {"ok": false, "reason": "LET_BOX_EMPTY"}
	var res := evaluate(state, letter, parcel_entries)
	var keys: Array = []
	for it in products:
		keys.append(String(it.key))
		var ref := _locate(state, it)
		State.take(state, ref)
	letter.done = true
	letter.read = true
	var kid := String(letter.from)
	var before := int(l.love.get(kid, 0))
	var after := before + int(res.hearts)
	l.love[kid] = after
	var unlocked: Array = []
	var family: Array = FAMILY_RECIPES.get(kid, [])
	for i in mini(LOVE_STEPS.size(), family.size()):
		if before < int(LOVE_STEPS[i]) and after >= int(LOVE_STEPS[i]) and not family[i] in l.unlocked_recipes:
			l.unlocked_recipes.append(family[i])
			unlocked.append(family[i])
	var day := int(state.day)
	l.sent.append({"letter": letter_id, "to": kid, "day": day, "reply_day": day + REPLY_DAYS, "keys": keys,
		"care": bool(res.care), "hearts": int(res.hearts), "unlocked": unlocked, "replied": false})
	res["ok"] = true
	res["reason"] = ""
	res["love"] = after
	res["unlocked"] = unlocked
	res["reply_day"] = day + REPLY_DAYS
	return res


# --- queries -------------------------------------------------------------------------------------------------------

static func find_letter(state: Dictionary, letter_id: int) -> Dictionary:
	if typeof(state.get("letters")) != TYPE_DICTIONARY:
		return {}
	for letter in state.letters.get("inbox", []):
		if int(letter.id) == letter_id:
			return letter
	return {}


static func mark_read(state: Dictionary, letter_id: int) -> void:
	var letter := find_letter(state, letter_id)
	if not letter.is_empty():
		letter.read = true


static func unread_count(state: Dictionary) -> int:
	var n := 0
	if typeof(state.get("letters")) == TYPE_DICTIONARY:
		for letter in state.letters.get("inbox", []):
			if not bool(letter.get("read", false)):
				n += 1
	return n


## Request letters still waiting for a parcel.
static func open_requests(state: Dictionary) -> Array:
	var out: Array = []
	if typeof(state.get("letters")) == TYPE_DICTIONARY:
		for letter in state.letters.get("inbox", []):
			if String(letter.kind) == "request" and not bool(letter.get("done", false)):
				out.append(letter)
	return out


## The parcel sent for a request letter, {} if none.
static func parcel_for(state: Dictionary, letter_id: int) -> Dictionary:
	if typeof(state.get("letters")) == TYPE_DICTIONARY:
		for p in state.letters.get("sent", []):
			if int(p.letter) == letter_id:
				return p
	return {}


## Ready products the parcel screen offers: [{"ref", "item"}], inbox first, then the pantry.
static func parcel_sources(state: Dictionary) -> Array:
	var out: Array = []
	for i in state.inbox.size():
		var it: Dictionary = state.inbox[i]
		if String(it.get("kind", "")) == "product" and int(it.get("wait_left", 0)) <= 0:
			out.append({"ref": {"where": "inbox", "index": i}, "item": it})
	for i in state.pantry.items.size():
		var it: Dictionary = state.pantry.items[i].item
		if String(it.get("kind", "")) == "product" and int(it.get("wait_left", 0)) <= 0:
			out.append({"ref": {"where": "pantry", "index": i}, "item": it})
	return out


# --- internals ---------------------------------------------------------------------------------------------------

## Kids without an open request; when both are free, the one who did not write last (first letter: drawn).
static func _pick_kid(state: Dictionary, r: RandomNumberGenerator) -> String:
	var busy := {}
	for letter in open_requests(state):
		busy[String(letter.from)] = true
	var free: Array = []
	for kid in kids():
		if not busy.has(kid):
			free.append(kid)
	if free.is_empty():
		return ""
	if free.size() == 1:
		return free[0]
	var last := String(state.letters.get("last_from", ""))
	var others: Array = free.filter(func(k: String) -> bool: return k != last)
	if others.size() == 1:
		return others[0]
	return free[r.randi_range(0, free.size() - 1)]


static func _draw_request(r: RandomNumberGenerator, kid: String, cands: Array, seen: Dictionary) -> Dictionary:
	var likes: Array = kid_info(kid).get("likes", [])
	var recipes: Array = []
	for c in cands:
		if not c.recipe in recipes:
			recipes.append(c.recipe)
	recipes.sort()
	for t in REQUEST_TRIES:
		var req := {"recipe": "", "taste": ""}
		if r.randf() < TASTE_CHANCE:
			var pool: Array = likes if r.randf() < LIKED_CHANCE and not likes.is_empty() else ProductGen.AXES
			req.taste = String(pool[r.randi_range(0, pool.size() - 1)])
		if (req.taste == "" or r.randf() < RECIPE_CHANCE) and not recipes.is_empty():
			req.recipe = String(recipes[r.randi_range(0, recipes.size() - 1)])
		if req.taste == "" and req.recipe == "":
			continue
		if not seen.has(_req_id(req)) and satisfiable(req, cands):
			return req
	if cands.is_empty():
		return {"recipe": "", "taste": ""}  # nothing provable (stub tastes): "anything you made"
	var c: Dictionary = cands[r.randi_range(0, cands.size() - 1)]
	return {"recipe": String(c.recipe), "taste": ""}


static func _req_id(req: Dictionary) -> String:
	return "%s|%s" % [req.get("recipe", ""), req.get("taste", "")]


## Depth-first over request items: each takes an unused matching product or none. Best = most matched, then a
## surprise left over.
static func _search(i: int, can: Array, used: Dictionary, assign: Array, surprise: Array, best: Dictionary) -> void:
	if i == can.size():
		var matched := 0
		for a in assign:
			if int(a) >= 0:
				matched += 1
		var s := false
		for p in surprise.size():
			if bool(surprise[p]) and not used.has(p):
				s = true
		var score := matched * 2 + (1 if s else 0)
		if best.is_empty() or score > int(best.score):
			best["score"] = score
			best["matched"] = matched
			best["surprise"] = s
			best["assign"] = assign.duplicate()
		return
	for p in can[i]:
		if used.has(p):
			continue
		used[p] = true
		assign[i] = p
		_search(i + 1, can, used, assign, surprise, best)
		used.erase(p)
	assign[i] = -1
	_search(i + 1, can, used, assign, surprise, best)


## {"where", "index"} of the very item Dictionary in the inbox or the pantry, {} when it is not there.
static func _locate(state: Dictionary, item: Dictionary) -> Dictionary:
	for i in state.inbox.size():
		if is_same(state.inbox[i], item):
			return {"where": "inbox", "index": i}
	for i in state.pantry.items.size():
		if is_same(state.pantry.items[i].item, item):
			return {"where": "pantry", "index": i}
	return {}


static func _reply(state: Dictionary, parcel: Dictionary) -> Dictionary:
	var l: Dictionary = state.letters
	var kid := String(parcel.to)
	var r := Seeds.rng(int(state.save_seed), "letters", int(state.day), "reply:%d" % int(parcel.letter))
	var letter := {"id": int(l.next_id), "kind": "reply", "from": kid, "day": int(state.day),
		"note": "LET_REPLY_%s_%d" % [kid.to_upper(), r.randi_range(1, REPLY_COUNT)],
		"care_note": "LET_REPLY_CARE_%s" % kid.to_upper() if bool(parcel.care) else "",
		"re": int(parcel.letter), "care": bool(parcel.care), "hearts": int(parcel.hearts),
		"unlocked": parcel.get("unlocked", []).duplicate(), "read": false}
	l.next_id = int(l.next_id) + 1
	return letter
