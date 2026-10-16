class_name KidDrawing
extends RefCounted
## POLISH-LETTERS · A grandchild's crayon drawing in a letter (spec §7.6 P2 idea, pulled forward).
## Pure and deterministic, no autoloads: render(seed, subject) -> 48x48 RGBA8 Image, Vintage Autumn colours only,
## fully opaque (paper background, no partial alpha). Wobbly 1 px crayon outlines, hatched crayon colouring.
## subject: {"kind": "reply"|"request", "kid": kid id, "care": bool,
##           "items": [{"vessel": jam_jar|pickle_jar|bottle|pie|bread, "fill": [3 hex, dark..light], "lid": hex,
##                      "label": hex}]}
##   reply:   the jar(s) the child got (ProductGen.describe(key).appearance colours) beside a Granny stick figure,
##            with a sun, falling leaves, maybe a house; hearts when the parcel was packed with care.
##   request: the child under a thought bubble holding what they wish for (wish() turns a request into an item).
## Seed: Hash.fnv1a31("<letter id>|<from>"), so a letter always shows the same drawing.

const SIZE := 48
const PAPER := "f2d9c5"
## Outline crayons (one per drawing).
const INKS := ["49423d", "50361e", "62272c"]
const SKIN := "e19064"
const MOUTH := "a22512"
const GRANNY_HAIR := "b4b3a0"
const DRESSES := ["a22512", "4e7664", "62272c", "567c7d", "b66813"]
const KIDS := {"mia": {"hair": "c94d2e", "shirt": "c5bf3f"}, "leo": {"hair": "50361e", "shirt": "a22512"}}
const LEAVES := ["c94d2e", "b66813", "9b8039", "a22512", "c58845"]
const GRASS := ["747c37", "9b8039", "53612e"]
const SUN_RIM := "b66813"
const SUN_FILL := "c5bf3f"
const HEART := "c94d2e"
const BUBBLE := "81746a"
const PLAIN_FILL := ["b66813", "c58845", "e5bd7f"]
## Wish colours per taste axis (dark, mid, light).
const TASTE_FILL := {
	"sweet": ["a22512", "c94d2e", "e19064"], "sour": ["747c37", "b7b768", "c5bf3f"],
	"spicy": ["a22512", "b66813", "e19064"], "salty": ["415c5d", "738c7a", "b4b3a0"],
	"earthy": ["50361e", "83571e", "c58845"],
}
## Drawn size per vessel: [big (reply), small (inside the thought bubble)].
const VESSEL := {
	"jam_jar": [Vector2i(12, 14), Vector2i(8, 9)], "pickle_jar": [Vector2i(12, 17), Vector2i(8, 11)],
	"bottle": [Vector2i(8, 20), Vector2i(6, 12)], "pie": [Vector2i(18, 9), Vector2i(12, 6)],
	"bread": [Vector2i(18, 10), Vector2i(12, 7)],
}
const HEART_PATTERN := [".X.X.", "XXXXX", ".XXX.", "..X.."]
const LEAF_PATTERNS := [[".X.", "XXX", ".X.", "X.."], ["XX.", "XXX", ".XX", "..X"], [".XX", "XXX", "XX.", "X.."]]


## A request item as a drawable wish: the recipe's vessel coloured by the asked taste ("" = any).
static func wish(vessel: String, taste: String) -> Dictionary:
	var fill: Array = TASTE_FILL.get(taste, PLAIN_FILL)
	return {"vessel": vessel if VESSEL.has(vessel) else "jam_jar", "fill": fill.duplicate(), "lid": "9b8039",
		"label": "e5bd7f"}


static func render(seed_v: int, subject: Dictionary) -> Image:
	var pen := Pen.new(seed_v)
	var items: Array = subject.get("items", [])
	if items.is_empty():
		items = [wish("jam_jar", "")]
	if String(subject.get("kind", "reply")) == "request":
		_request(pen, items, String(subject.get("kid", "mia")))
	else:
		_reply(pen, items, bool(subject.get("care", false)))
	return pen.img


## Ground row: Granny beside the jar(s), maybe a house on the free side; sun, leaves and care hearts above.
static func _reply(pen: Pen, items: Array, care: bool) -> void:
	var ground := 40 + pen.r.randi_range(0, 2)
	var fig_w := 11
	var gap := 3
	var shown: Array = items.slice(0, 2)
	var total := _row_width(shown, fig_w, gap)
	while shown.size() > 1 and total > SIZE - 4:
		shown.pop_back()
		total = _row_width(shown, fig_w, gap)
	var fig_left := pen.r.randf() < 0.5
	var house := SIZE - total - gap - 4 >= 14 and pen.r.randf() < 0.7
	var x0 := floori((SIZE - total) / 2.0) + pen.r.randi_range(-2, 2)
	if house:
		x0 = SIZE - 2 - total if fig_left else 2
	x0 = clampi(x0, 2, SIZE - 2 - total)
	_ground(pen, ground)
	var sun_left := pen.r.randf() < 0.5
	if house:
		var hx := 2 if fig_left else SIZE - 14
		_house(pen, hx, ground)
		sun_left = not fig_left  # the sun goes over the jars, away from the chimney smoke
	var x := x0
	var jar_tops: Array = []
	var order: Array = ["fig"] + shown if fig_left else shown + ["fig"]
	for part in order:
		if typeof(part) == TYPE_STRING:
			_granny(pen, x + 5, ground, 1 if fig_left else -1)
			x += fig_w + gap
			continue
		var sz := _size(part, 0)
		var rect := Rect2i(x, ground - sz.y + 1, sz.x, sz.y)
		_vessel(pen, part, rect)
		jar_tops.append(rect)
		x += sz.x + gap
	_sun(pen, Vector2i(6 if sun_left else SIZE - 7, 6))
	var skip := Rect2i(0, 0, 14, 14) if sun_left else Rect2i(SIZE - 14, 0, 14, 14)
	if house:
		skip = skip.merge(Rect2i(0 if fig_left else SIZE - 16, 14, 16, 12))
	_leaves(pen, pen.r.randi_range(2, 4), Rect2i(2, 2, SIZE - 6, 18), skip)
	if care and not jar_tops.is_empty():
		var top: Rect2i = jar_tops[0]
		_heart(pen, top.position.x + floori(top.size.x / 2.0) - 2, maxi(top.position.y - 7, 14))
		if pen.r.randf() < 0.6:
			_heart(pen, top.position.x + top.size.x - 1, maxi(top.position.y - 11, 12))


## The child under a thought bubble with the wished-for jars inside.
static func _request(pen: Pen, items: Array, kid: String) -> void:
	var ground := 41 + pen.r.randi_range(0, 1)
	var kid_left := pen.r.randf() < 0.5
	var kx := 8 + pen.r.randi_range(0, 1) if kid_left else SIZE - 9 - pen.r.randi_range(0, 1)
	_ground(pen, ground)
	var c := Vector2(29 if kid_left else 18, 13)
	var rx := 16.0
	var ry := 10.5
	pen.oval(c, rx, ry, BUBBLE, true)
	# Trail of little bubbles from the child's head up to the cloud.
	var dir := 1 if kid_left else -1
	pen.blob(Vector2i(kx + dir, ground - 20), BUBBLE)
	pen.blob(Vector2i(kx + dir * 3, ground - 23), BUBBLE)
	var shown: Array = items.slice(0, 3)
	var width := 0
	while true:
		width = 0
		for it in shown:
			width += _size(it, 1).x
		width += 2 * (shown.size() - 1)
		if width <= int(rx * 2) - 6 or shown.size() == 1:
			break
		shown.pop_back()
	var x := roundi(c.x - width / 2.0)
	var bottom := roundi(c.y + 5)
	for it in shown:
		var sz := _size(it, 1)
		_vessel(pen, it, Rect2i(x, bottom - sz.y + 1, sz.x, sz.y))
		x += sz.x + 2
	_kid(pen, kx, ground, kid, dir)
	var sun_c := Vector2i(5 if kid_left else SIZE - 6, 5)
	if pen.r.randf() < 0.5:
		_sun(pen, sun_c, 1)
	var free_x := SIZE - 16 if kid_left else 4
	_leaves(pen, pen.r.randi_range(1, 2), Rect2i(free_x, 26, 12, ground - 30), Rect2i())
	if pen.r.randf() < 0.6:
		_heart(pen, kx - 2 - dir * 6, ground - 24)


static func _row_width(shown: Array, fig_w: int, gap: int) -> int:
	var w := fig_w
	for it in shown:
		w += gap + _size(it, 0).x
	return w


static func _size(item: Dictionary, which: int) -> Vector2i:
	var sizes: Array = VESSEL.get(String(item.get("vessel", "jam_jar")), VESSEL.jam_jar)
	return sizes[which]


# --- things a child draws ----------------------------------------------------------------------------------------

static func _ground(pen: Pen, y: int) -> void:
	var col := String(GRASS[pen.r.randi_range(0, GRASS.size() - 1)])
	pen.line(Vector2i(1, y + 1), Vector2i(SIZE - 2, y + 1), col)
	var x := pen.r.randi_range(2, 5)
	while x < SIZE - 2:
		pen.dot(x, y, col)
		if pen.r.randf() < 0.5:
			pen.dot(x + 1, y - 1, col)
		x += pen.r.randi_range(4, 7)


static func _vessel(pen: Pen, item: Dictionary, rect: Rect2i) -> void:
	match String(item.get("vessel", "jam_jar")):
		"bottle":
			_bottle(pen, item, rect)
		"pie":
			_pie(pen, item, rect)
		"bread":
			_bread(pen, item, rect)
		_:
			_jar(pen, item, rect)


static func _fill(item: Dictionary) -> Array:
	var f: Array = item.get("fill", [])
	return f if f.size() >= 3 else PLAIN_FILL


static func _jar(pen: Pen, item: Dictionary, rect: Rect2i) -> void:
	var f := _fill(item)
	var big := rect.size.y >= 12
	var lid_h := 3 if big else 2
	var lid := Rect2i(rect.position.x + 1, rect.position.y, rect.size.x - 2, lid_h)
	var body := Rect2i(rect.position.x, rect.position.y + lid_h, rect.size.x, rect.size.y - lid_h)
	var inner := body.grow(-1)
	inner.position.y += 1
	inner.size.y -= 1
	pen.hatch_rect(inner, String(f[1]), 4)
	pen.hatch_rect(Rect2i(inner.position.x, inner.end.y - maxi(2, floori(inner.size.y / 3.0)), inner.size.x,
		maxi(2, floori(inner.size.y / 3.0))), String(f[0]), 3)
	for y in range(inner.position.y + 1, inner.end.y - 2):
		if pen.r.randf() < 0.6:
			pen.dot(inner.position.x, y, String(f[2]))
	if big:
		var lh := 4 if rect.size.y >= 16 else 3
		var label := Rect2i(body.position.x + 2, body.position.y + floori((body.size.y - lh) / 2.0), body.size.x - 4, lh)
		pen.hatch_rect(label, String(item.get("label", "e5bd7f")), 0)
		for i in range(1, label.size.x - 1):
			pen.dot(label.position.x + i, label.position.y + 1 + (i % 2), pen.ink if i % 3 != 0 else String(f[0]))
	pen.hatch_rect(lid, String(item.get("lid", "9b8039")), 0)
	pen.box(lid, pen.ink)
	pen.box(body, pen.ink, true)


static func _bottle(pen: Pen, item: Dictionary, rect: Rect2i) -> void:
	var f := _fill(item)
	var neck_w := maxi(2, floori(rect.size.x / 3.0))
	var neck_h := maxi(3, floori(rect.size.y / 4.0))
	var nx := rect.position.x + floori((rect.size.x - neck_w) / 2.0)
	var cork := Rect2i(nx, rect.position.y, neck_w, 2)
	var neck := Rect2i(nx, rect.position.y + 2, neck_w, neck_h)
	var body := Rect2i(rect.position.x, neck.end.y + 1, rect.size.x, rect.end.y - neck.end.y - 1)
	pen.hatch_rect(body.grow(-1), String(f[1]), 4)
	pen.hatch_rect(Rect2i(body.position.x + 1, body.end.y - 3, body.size.x - 2, 2), String(f[0]), 3)
	pen.hatch_rect(cork, String(item.get("lid", "9b8039")), 0)
	pen.line(Vector2i(neck.position.x - 1, neck.position.y), Vector2i(neck.position.x - 1, neck.end.y - 1), pen.ink)
	pen.line(Vector2i(neck.end.x, neck.position.y), Vector2i(neck.end.x, neck.end.y - 1), pen.ink)
	pen.line(Vector2i(neck.position.x - 1, neck.end.y), Vector2i(body.position.x, body.position.y), pen.ink)
	pen.line(Vector2i(neck.end.x, neck.end.y), Vector2i(body.end.x - 1, body.position.y), pen.ink)
	pen.line(Vector2i(body.position.x, body.position.y), Vector2i(body.position.x, body.end.y - 1), pen.ink)
	pen.line(Vector2i(body.end.x - 1, body.position.y), Vector2i(body.end.x - 1, body.end.y - 1), pen.ink)
	pen.line(Vector2i(body.position.x, body.end.y - 1), Vector2i(body.end.x - 1, body.end.y - 1), pen.ink)


## A round lattice pie: the filling coloured in, crust strips criss-crossing it, a dish band below.
static func _pie(pen: Pen, item: Dictionary, rect: Rect2i) -> void:
	var f := _fill(item)
	var dish_h := maxi(2, floori(rect.size.y / 3.0))
	var dome := Rect2i(rect.position.x, rect.position.y, rect.size.x, rect.size.y - dish_h)
	var c := Vector2(dome.position.x + (dome.size.x - 1) / 2.0, dome.end.y - 0.5)
	var rx := dome.size.x / 2.0 - 0.5
	var ry := float(dome.size.y) - 0.5
	pen.hatch_oval(c, rx, ry, String(f[1]), 0, true)
	pen.lattice(c, rx, ry, "e5bd7f", 4 if rect.size.x >= 16 else 3)
	pen.oval_top(c, rx, ry, pen.ink)
	var dish := Rect2i(rect.position.x, dome.end.y, rect.size.x, dish_h)
	pen.hatch_rect(dish.grow(-1), "c58845", 0)
	pen.box(dish, pen.ink, true)


static func _bread(pen: Pen, item: Dictionary, rect: Rect2i) -> void:
	var f := _fill(item)
	var c := Vector2(rect.position.x + (rect.size.x - 1) / 2.0, rect.end.y - 1.5)
	var rx := rect.size.x / 2.0 - 0.5
	var ry := rect.size.y - 1.5
	pen.hatch_oval(c, rx, ry, String(f[1]), 4, true)
	pen.oval_top(c, rx, ry, pen.ink)
	pen.line(Vector2i(rect.position.x, rect.end.y - 1), Vector2i(rect.end.x - 1, rect.end.y - 1), pen.ink)
	for i in range(1, 4):
		var sx := rect.position.x + roundi(rect.size.x * i / 4.0)
		pen.line(Vector2i(sx - 1, rect.position.y + 3), Vector2i(sx + 1, rect.position.y + 1), String(f[0]))


## Granny: grey bun, round face, triangle dress, stick arms (one reaching toward `dir`) and legs. ~21 px tall.
static func _granny(pen: Pen, cx: int, ground: int, dir: int) -> void:
	var dress := String(DRESSES[pen.r.randi_range(0, DRESSES.size() - 1)])
	var neck := ground - 12
	for y in range(neck, ground - 3):
		var t := float(y - neck) / float(ground - 4 - neck)
		var hw := roundi(lerpf(1.0, 5.0, t))
		pen.hatch_rect(Rect2i(cx - hw, y, hw * 2 + 1, 1), dress, 3)
	pen.line(Vector2i(cx - 1, neck), Vector2i(cx - 5, ground - 4), pen.ink)
	pen.line(Vector2i(cx + 1, neck), Vector2i(cx + 5, ground - 4), pen.ink)
	pen.line(Vector2i(cx - 5, ground - 3), Vector2i(cx + 5, ground - 3), pen.ink)
	pen.line(Vector2i(cx - 2, ground - 2), Vector2i(cx - 2, ground), pen.ink)
	pen.line(Vector2i(cx + 2, ground - 2), Vector2i(cx + 2, ground), pen.ink)
	pen.dot(cx - 3, ground, pen.ink)
	pen.dot(cx + 3, ground, pen.ink)
	pen.line(Vector2i(cx + dir * 2, neck + 2), Vector2i(cx + dir * 6, neck + 4), pen.ink)
	if pen.r.randf() < 0.5:
		pen.line(Vector2i(cx - dir * 2, neck + 2), Vector2i(cx - dir * 5, neck - 1), pen.ink)  # waving
	else:
		pen.line(Vector2i(cx - dir * 2, neck + 2), Vector2i(cx - dir * 5, neck + 5), pen.ink)
	_face(pen, Vector2i(cx, neck - 4), GRANNY_HAIR, false)
	pen.blob(Vector2i(cx, neck - 9), GRANNY_HAIR)


## The grandchild: hair in the kid's colour (Mia with bunches), shirt box, arms up toward the dream when `dir` set.
static func _kid(pen: Pen, cx: int, ground: int, kid: String, dir: int) -> void:
	var look: Dictionary = KIDS.get(kid, KIDS.mia)
	var shirt := Rect2i(cx - 3, ground - 9, 7, 6)
	pen.hatch_rect(shirt.grow(-1), String(look.shirt), 3)
	pen.box(shirt, pen.ink)
	pen.line(Vector2i(cx - 2, ground - 3), Vector2i(cx - 2, ground), pen.ink)
	pen.line(Vector2i(cx + 2, ground - 3), Vector2i(cx + 2, ground), pen.ink)
	pen.line(Vector2i(cx + dir * 4, ground - 8), Vector2i(cx + dir * 7, ground - 12), pen.ink)
	pen.line(Vector2i(cx - dir * 4, ground - 8), Vector2i(cx - dir * 6, ground - 5), pen.ink)
	_face(pen, Vector2i(cx, ground - 13), String(look.hair), kid == "mia")


## Round face with a hair cap, two dot eyes and a smile. `bunches`: a tuft each side.
static func _face(pen: Pen, c: Vector2i, hair: String, bunches: bool) -> void:
	pen.hatch_oval(Vector2(c), 2.6, 2.6, SKIN, 0)
	pen.oval(Vector2(c), 3.2, 3.2, pen.ink, false)
	for x in range(c.x - 2, c.x + 3):
		pen.dot(x, c.y - 3, hair)
		if absi(x - c.x) < 2:
			pen.dot(x, c.y - 4, hair)
	pen.dot(c.x - 3, c.y - 2, hair)
	pen.dot(c.x + 3, c.y - 2, hair)
	if bunches:
		pen.dot(c.x - 4, c.y - 1, hair)
		pen.dot(c.x - 5, c.y, hair)
		pen.dot(c.x + 4, c.y - 1, hair)
		pen.dot(c.x + 5, c.y, hair)
	pen.dot(c.x - 1, c.y - 1, pen.ink)
	pen.dot(c.x + 1, c.y - 1, pen.ink)
	pen.dot(c.x - 1, c.y + 1, MOUTH)
	pen.dot(c.x, c.y + 2, MOUTH)
	pen.dot(c.x + 1, c.y + 1, MOUTH)


static func _house(pen: Pen, x: int, ground: int) -> void:
	var walls := Rect2i(x, ground - 9, 12, 10)
	pen.hatch_rect(walls.grow(-1), "e5bd7f", 3)
	pen.box(walls, pen.ink)
	var apex := Vector2i(x + 6, ground - 16)
	for y in range(apex.y + 1, walls.position.y):
		var hw := roundi(float(y - apex.y) * 6.5 / float(walls.position.y - apex.y))
		pen.hatch_rect(Rect2i(apex.x - hw + 1, y, hw * 2 - 1, 1), "a22512", 3)
	pen.line(Vector2i(x - 1, walls.position.y), apex, pen.ink)
	pen.line(apex, Vector2i(x + 12, walls.position.y), pen.ink)
	pen.hatch_rect(Rect2i(x + 2, ground - 5, 3, 5), "50361e", 0)
	pen.box(Rect2i(x + 7, ground - 7, 3, 3), "b66813")
	pen.line(Vector2i(x + 9, apex.y + 2), Vector2i(x + 9, apex.y + 4), pen.ink)
	var sy := apex.y + 1
	for i in 4:
		pen.dot(x + 9 + (i % 2), sy - i, "81746a")


## Crayon sun: hatched disc, rim, short rays, sometimes a smile.
static func _sun(pen: Pen, c: Vector2i, rays := 2) -> void:
	pen.hatch_oval(Vector2(c), 3.0, 3.0, SUN_FILL, 0)
	pen.oval(Vector2(c), 3.6, 3.6, SUN_RIM, false)
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		var p0 := Vector2i(roundi(c.x + cos(a) * 5.0), roundi(c.y + sin(a) * 5.0))
		var p1 := Vector2i(roundi(c.x + cos(a) * (5.0 + rays)), roundi(c.y + sin(a) * (5.0 + rays)))
		pen.line(p0, p1, SUN_RIM)
	if rays >= 2 and pen.r.randf() < 0.5:
		pen.dot(c.x - 1, c.y - 1, pen.ink)
		pen.dot(c.x + 1, c.y - 1, pen.ink)
		pen.dot(c.x, c.y + 1, MOUTH)


static func _leaves(pen: Pen, n: int, area: Rect2i, avoid: Rect2i) -> void:
	var placed := 0
	var tries := 0
	while placed < n and tries < 20:
		tries += 1
		var p := Vector2i(pen.r.randi_range(area.position.x, area.end.x - 3), pen.r.randi_range(area.position.y, area.end.y - 4))
		if avoid.has_area() and avoid.intersects(Rect2i(p, Vector2i(3, 4))):
			continue
		var pat: Array = LEAF_PATTERNS[pen.r.randi_range(0, LEAF_PATTERNS.size() - 1)]
		var col := String(LEAVES[pen.r.randi_range(0, LEAVES.size() - 1)])
		var flip := pen.r.randf() < 0.5
		for y in pat.size():
			for x in 3:
				if String(pat[y])[x] == "X":
					pen.dot(p.x + (2 - x if flip else x), p.y + y, col)
		placed += 1


static func _heart(pen: Pen, x: int, y: int) -> void:
	for yy in HEART_PATTERN.size():
		for xx in 5:
			if String(HEART_PATTERN[yy])[xx] == "X":
				pen.dot(x + xx, y + yy, HEART)


# --- crayon ------------------------------------------------------------------------------------------------------

## Drawing state: the paper image, the seeded RNG and the drawing's outline crayon.
class Pen:
	extends RefCounted
	var img: Image
	var r := RandomNumberGenerator.new()
	var ink: String
	var _cols := {}

	func _init(seed_v: int) -> void:
		r.seed = seed_v
		img = Image.create(KidDrawing.SIZE, KidDrawing.SIZE, false, Image.FORMAT_RGBA8)
		img.fill(_col(KidDrawing.PAPER))
		ink = String(KidDrawing.INKS[r.randi_range(0, KidDrawing.INKS.size() - 1)])

	func _col(hex: String) -> Color:
		if not _cols.has(hex):
			_cols[hex] = Color(hex)
		return _cols[hex]

	func dot(x: int, y: int, hex: String) -> void:
		if x >= 0 and y >= 0 and x < KidDrawing.SIZE and y < KidDrawing.SIZE:
			img.set_pixel(x, y, _col(hex))

	## Crayon stroke: a 1 px line that drifts one pixel off course now and then and skips the odd pixel.
	func line(a: Vector2i, b: Vector2i, hex: String) -> void:
		var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
		var horiz := absi(b.x - a.x) >= absi(b.y - a.y)
		var wobble := steps >= 6
		var off := 0
		for i in steps + 1:
			var t := 0.0 if steps == 0 else float(i) / float(steps)
			var x := roundi(lerpf(a.x, b.x, t))
			var y := roundi(lerpf(a.y, b.y, t))
			if wobble and i > 1 and i < steps - 1 and r.randf() < 0.2:
				off = clampi(off + (1 if r.randf() < 0.5 else -1), -1, 1)
			if i >= steps - 1:
				off = 0
			if horiz:
				y += off
			else:
				x += off
			if wobble and i > 0 and i < steps and r.randf() < 0.04:
				continue
			dot(x, y, hex)

	## Rectangle outline, corners sometimes overshot like a quick hand. `open_top`: jar body under its lid.
	func box(rect: Rect2i, hex: String, open_top := false) -> void:
		var x0 := rect.position.x
		var y0 := rect.position.y
		var x1 := rect.end.x - 1
		var y1 := rect.end.y - 1
		if not open_top:
			line(Vector2i(x0 - (1 if r.randf() < 0.3 else 0), y0), Vector2i(x1, y0), hex)
		line(Vector2i(x1, y0), Vector2i(x1, y1 + (1 if r.randf() < 0.2 else 0)), hex)
		line(Vector2i(x1, y1), Vector2i(x0, y1), hex)
		line(Vector2i(x0, y1), Vector2i(x0, y0 - (1 if r.randf() < 0.3 and not open_top else 0)), hex)

	## Closed oval outline through jittered points; `wobble` adds the crayon drift on longer sides.
	func oval(c: Vector2, rx: float, ry: float, hex: String, wobble: bool) -> void:
		var n := maxi(10, roundi((rx + ry) * 1.6))
		var start := r.randf() * TAU
		var pts: Array = []
		for i in n + 1:
			var a := start + TAU * float(i) / float(n)
			var jr := r.randf_range(-0.3, 0.3) if wobble else 0.0
			pts.append(Vector2i(roundi(c.x + cos(a) * (rx + jr)), roundi(c.y + sin(a) * (ry + jr))))
		pts[n] = pts[0]
		for i in n:
			_seg(pts[i], pts[i + 1], hex)

	## Upper half of an oval (dome of a pie or a loaf).
	func oval_top(c: Vector2, rx: float, ry: float, hex: String) -> void:
		var n := maxi(8, roundi((rx + ry) * 1.2))
		var prev := Vector2i(roundi(c.x - rx), roundi(c.y))
		for i in range(1, n + 1):
			var a := PI + PI * float(i) / float(n)
			var p := Vector2i(roundi(c.x + cos(a) * rx), roundi(c.y + sin(a) * ry))
			_seg(prev, p, hex)
			prev = p

	## Small round blob (bun, bubble trail).
	func blob(c: Vector2i, hex: String) -> void:
		for p in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			dot(c.x + p.x, c.y + p.y, hex)

	## Criss-cross strips over the upper half of an oval (pie crust).
	func lattice(c: Vector2, rx: float, ry: float, hex: String, step: int) -> void:
		for y in range(floori(c.y - ry), floori(c.y) + 1):
			for x in range(floori(c.x - rx), ceili(c.x + rx) + 1):
				var dx := (x - c.x) / maxf(rx, 0.5)
				var dy := (y - c.y) / maxf(ry, 0.5)
				if dx * dx + dy * dy <= 1.0 and (posmod(x + y, step) == 0 or posmod(x - y, step) == 0):
					dot(x, y, hex)

	## Crayon colouring: diagonal strokes leaving every `gap`-th diagonal blank (0 = solid), drifting row by row.
	func hatch_rect(rect: Rect2i, hex: String, gap: int) -> void:
		_hatch(rect, func(_x: int, _y: int) -> bool: return true, hex, gap)

	## Oval colouring; `top_only` keeps to the upper half (pie and loaf domes).
	func hatch_oval(c: Vector2, rx: float, ry: float, hex: String, gap: int, top_only := false) -> void:
		var area := Rect2i(floori(c.x - rx), floori(c.y - ry), ceili(rx * 2) + 2, ceili(ry * 2) + 2)
		var inside := func(x: int, y: int) -> bool:
			if top_only and y > c.y:
				return false
			var dx := (x - c.x) / maxf(rx, 0.5)
			var dy := (y - c.y) / maxf(ry, 0.5)
			return dx * dx + dy * dy <= 1.0
		_hatch(area, inside, hex, gap)

	func _hatch(rect: Rect2i, inside: Callable, hex: String, gap: int) -> void:
		var phase := r.randi_range(0, maxi(gap, 1) - 1)
		for y in range(rect.position.y, rect.end.y):
			if gap > 0 and r.randf() < 0.3:
				phase = (phase + 1) % gap
			for x in range(rect.position.x, rect.end.x):
				if not inside.call(x, y):
					continue
				if gap > 0 and posmod(x - y + phase, gap) == 0:
					continue
				if gap > 0 and r.randf() < 0.05:
					continue
				dot(x, y, hex)

	## Straight segment without drift (short pieces of curves).
	func _seg(a: Vector2i, b: Vector2i, hex: String) -> void:
		var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for i in steps + 1:
			var t := 0.0 if steps == 0 else float(i) / float(steps)
			dot(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)), hex)
