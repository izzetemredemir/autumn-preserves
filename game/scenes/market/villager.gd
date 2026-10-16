extends Node2D
## A procedural market visitor (MARKET, PCG showcase). One look seed -> a 24x48 pixel villager built from palette
## parts: build (child, grown-up, elder), skin, hair style and colour, hat, coat or jacket, skirt or trousers, scarf,
## basket or bag, glasses, beard. Four walk frames facing right (contact, passing, contact, passing), ink outline
## around the silhouette. The node origin is the feet (frame pivot 12,47). Drawn 1:1 at foreground size (never
## scaled). Same seed -> same villager, every run.

const W := 24
const H := 48
const INK := "111010"
const SKINS := [["f2d9c5", "e5bd7f"], ["e5bd7f", "c58845"], ["e19064", "b66813"], ["c58845", "83571e"], ["83571e", "50361e"]]
const HAIRS := [["23282a", "111010"], ["50361e", "3d1f29"], ["83571e", "50361e"], ["b66813", "83571e"], ["dbcc83", "b1a13d"]]
const HAIRS_OLD := [["b4b3a0", "81746a"], ["f2d9c5", "b9a697"], ["81746a", "49423d"]]
## [base, shade]: coats and jackets.
const COATS := [["62272c", "3d1f29"], ["53612e", "314524"], ["4e7664", "2e3f3f"], ["9b8039", "83571e"],
	["b66813", "83571e"], ["415c5d", "2e3f3f"], ["747c37", "53612e"], ["81746a", "49423d"], ["a22512", "62272c"]]
const LOWERS := [["49423d", "23282a"], ["50361e", "3d1f29"], ["2e3f3f", "23282a"], ["62272c", "3d1f29"], ["53612e", "314524"]]
const SCARVES := [["c94d2e", "a22512"], ["e5bd7f", "b66813"], ["dbcc83", "9b8039"], ["b7b768", "747c37"], ["e19064", "c94d2e"]]
const HATS := [["83571e", "50361e"], ["62272c", "3d1f29"], ["4e7664", "2e3f3f"], ["c94d2e", "a22512"], ["9b8039", "83571e"]]
const HAT_KINDS := ["none", "none", "none", "beret", "cap", "beanie", "kerchief", "bonnet"]
const CARRY := ["none", "none", "basket", "bag"]

var frames: Array[Texture2D] = []
var _sprite: Sprite2D


## Four ImageTextures (walk cycle) for a look seed. `fancy` = a well-off visitor: top hat and a long coat.
static func make_frames(look: int, fancy := false) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for img in make_images(look, fancy):
		out.append(ImageTexture.create_from_image(img))
	return out


static func make_images(look: int, fancy := false) -> Array[Image]:
	var p := _parts(look, fancy)
	var out: Array[Image] = []
	for f in 4:
		out.append(_draw_frame(p, f))
	return out


func setup(look: int, fancy := false) -> void:
	frames = make_frames(look, fancy)
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		_sprite.offset = Vector2(-12, -47)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	_sprite.texture = frames[0]


func set_frame(i: int) -> void:
	if _sprite != null and not frames.is_empty():
		_sprite.texture = frames[posmod(i, frames.size())]


# --- look ---------------------------------------------------------------------------------------------------------

static func _parts(look: int, fancy: bool) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = look
	var roll := r.randf()
	var age := "child" if roll < 0.15 else ("elder" if roll < 0.38 else "adult")
	var hairs: Array = HAIRS_OLD if age == "elder" else HAIRS
	var p := {
		"age": age,
		"tall": r.randi_range(0, 1),
		"round": r.randf() < 0.3,
		"skin": _pick(r, SKINS),
		"hair": _pick(r, hairs),
		"style": r.randi_range(0, 3),
		"hat": String(HAT_KINDS[r.randi_range(0, HAT_KINDS.size() - 1)]),
		"hat_col": _pick(r, HATS),
		"coat": _pick(r, COATS),
		"long": r.randf() < 0.45,
		"lower": _pick(r, LOWERS),
		"skirt": r.randf() < 0.45,
		"scarf": _pick(r, SCARVES) if r.randf() < 0.4 else [],
		"carry": String(CARRY[r.randi_range(0, CARRY.size() - 1)]),
		"glasses": r.randf() < (0.5 if age == "elder" else 0.15),
		"beard": r.randf() < 0.18,
		"shoes": "50361e" if r.randf() < 0.5 else INK,
	}
	if age == "child":
		p.glasses = false
		p.beard = false
		p.long = false
		p.round = false
		if p.hat == "bonnet":
			p.hat = "beanie"
	if fancy:
		p.hat = "top"
		p.long = true
		p.hat_col = ["23282a", "111010"]
		p.carry = "none" if p.carry == "bag" else p.carry
	if p.beard and (p.skirt or age == "child"):
		p.beard = false
	return p


static func _pick(r: RandomNumberGenerator, list: Array) -> Array:
	return list[r.randi_range(0, list.size() - 1)]


# --- drawing ------------------------------------------------------------------------------------------------------

## Frame f: 0/2 = contact (legs apart, arm swings), 1/3 = passing (legs together, body 1 px up).
## Chunky Granny proportions at the foreground size: a big head, an A-line body, short legs, shoes on rows 45-46.
static func _draw_frame(p: Dictionary, f: int) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var child: bool = p.age == "child"
	var bob := -1 if f % 2 == 1 else 0
	var top_hat := String(p.hat) == "top"
	var t: int = (17 if child else 5 - int(p.tall) * 2) + bob
	if top_hat:
		t = maxi(t, 10 + bob)
	var head := 12 if child else 14
	var hx0 := 6 if child else 5
	var hx1 := hx0 + head - 1
	var body_top := t + head
	var leg_top := 40
	var skin: Array = p.skin
	var hair: Array = p.hair
	var coat: Array = p.coat
	var lower: Array = p.lower
	var long: bool = p.long
	var skirt: bool = p.skirt and not long
	# legs and shoes; the far leg in the shade colour
	var near_x := 14
	var far_x := 7
	if f % 2 == 1:
		near_x = 10
		far_x = 10
	elif f == 2:
		near_x = 7
		far_x = 14
	var leg: String = skin[1] if skirt else lower[0]
	var leg_far: String = skin[1] if skirt else lower[1]
	if f % 2 == 0:
		_r(img, far_x, leg_top, 3, 45 - leg_top, leg_far)
		_r(img, far_x, 45, 4, 2, p.shoes)
	_r(img, near_x, leg_top, 3, 45 - leg_top, leg)
	_r(img, near_x, 45, 4, 2, p.shoes)
	_r(img, near_x + 1, 45, 2, 1, "83571e" if String(p.shoes) == INK else "c58845")
	# body: narrow shoulders, then an A-line coat, jacket over trousers or a skirt
	var jacket_end := leg_top + 2 if long else body_top + maxi(5, int((leg_top - body_top) * 0.6))
	var bottom := leg_top + 2 if long else leg_top
	for y in range(body_top, bottom):
		var row := y - body_top
		var x0: int
		var x1: int
		if child:
			x0 = 8 if row < 2 else 7
			x1 = 15 if row < 2 else 16
		else:
			x0 = 7 if row < 2 else (6 if row < 5 else 5)
			x1 = 16 if row < 2 else (17 if row < 5 else 18)
			if bool(p.round) and row >= 4 and y < jacket_end - 2:
				x1 += 1
		var col: Array = coat if y < jacket_end else lower
		if not long and not skirt and y >= jacket_end:
			x0 = 7 if child else 6
			x1 = 15 if child else 17
		if skirt and y >= jacket_end:
			x0 -= 1 + (1 if y >= bottom - 3 else 0)
			x1 += 1 + (1 if y >= bottom - 3 else 0)
		_r(img, x0, y, x1 - x0 + 1, 1, col[0])
		_r(img, x1 - 1, y, 2, 1, col[1])
		if y == bottom - 1 or y == jacket_end - 1:
			_r(img, x0, y, x1 - x0 + 1, 1, col[1])
	if long or top_hat:
		for y in range(body_top + 4, bottom - 2, 4):
			_r(img, 15, y, 1, 1, coat[1])  # buttons
	# scarf
	var scarf: Array = p.scarf
	if not scarf.is_empty():
		_r(img, 6, body_top, 12, 3, scarf[0])
		_r(img, 6, body_top + 2, 12, 1, scarf[1])
		_r(img, 4, body_top + 2, 3, 7, scarf[0])
		_r(img, 4, body_top + 2, 1, 7, scarf[1])
	# arm swings with the stride; hand; basket or bag
	var arm_x := 11 if child else 10
	var dx := 2 if f == 0 else (-2 if f == 2 else 0)
	var arm_len := 7 if child else 11
	_r(img, arm_x + dx, body_top + 3, 3, arm_len, coat[1])
	_r(img, arm_x + dx, body_top + 3, 1, arm_len, coat[0])
	_r(img, arm_x + dx, body_top + 3 + arm_len, 3, 2, skin[0])
	var hy: int = body_top + 3 + arm_len
	if String(p.carry) == "basket":
		var bx := arm_x + dx
		_r(img, bx, hy - 1, 1, 2, "83571e")
		_r(img, bx + 6, hy - 1, 1, 2, "83571e")
		_r(img, bx, hy - 2, 7, 1, "83571e")
		_r(img, bx + 1, hy + 1, 6, 1, "e5bd7f")
		_r(img, bx + 2, hy, 3, 1, "c94d2e")
		_r(img, bx, hy + 2, 7, 4, "c58845")
		_r(img, bx, hy + 3, 7, 1, "83571e")
		_r(img, bx, hy + 5, 7, 1, "83571e")
	elif String(p.carry) == "bag":
		_r(img, arm_x + dx + 1, hy - 4, 1, 4, "81746a")
		_r(img, arm_x + dx - 1, hy + 1, 5, 6, "b9a697")
		_r(img, arm_x + dx + 3, hy + 1, 1, 6, "81746a")
		_r(img, arm_x + dx - 1, hy + 1, 5, 1, "f2d9c5")
	# head: skin, jaw shade, nose, eye with a highlight, cheek
	_r(img, hx0, t + 1, head, head - 1, skin[0])
	_r(img, hx0 + 1, t, head - 2, 1, skin[0])
	_r(img, hx0 + 1, t + head - 1, head - 3, 1, skin[1])
	_r(img, hx1 + 1, t + head - 7, 1, 2, skin[1])
	var eye_x := hx1 - 4
	var eye_y := t + head - 8
	_r(img, eye_x, eye_y, 2, 3, INK)
	_r(img, eye_x, eye_y, 1, 1, "f2d9c5")
	var cheek := "c94d2e" if String(skin[0]) in ["e19064", "c58845", "83571e"] else "e19064"
	_r(img, eye_x + 1, eye_y + 4, 2, 1, cheek)
	_r(img, eye_x - 1, eye_y + 5 if not child else eye_y + 4, 1, 1, skin[1])
	if bool(p.glasses):
		_r(img, eye_x - 1, eye_y - 1, 4, 5, "49423d")
		_r(img, eye_x, eye_y, 2, 3, "b4b3a0")
		_r(img, eye_x, eye_y + 1, 2, 2, INK)
		_r(img, hx0 + 4, eye_y + 1, eye_x - hx0 - 5, 1, "49423d")
	if bool(p.beard):
		_r(img, hx1 - 7, t + head - 5, 8, 5, hair[0])
		_r(img, hx1 - 7, t + head - 1, 8, 1, hair[1])
		_r(img, hx1 - 2, t + head - 4, 2, 1, "62272c")
	# hair: crown, back of the head, style
	_r(img, hx0 + 1, t - 1, head - 3, 1, hair[0])
	_r(img, hx0, t, head, 4, hair[0])
	_r(img, hx0, t + 4, 5, 6, hair[0])
	_r(img, hx0, t + 4, 1, 6, hair[1])
	_r(img, hx0 + 5, t + 4, 1, 2, hair[0])
	_r(img, hx0 + 2, t, head - 4, 1, hair[1] if String(hair[0]) in ["23282a", "50361e"] else hair[0])
	match int(p.style):
		1:  # bun
			_r(img, hx0 - 3, t - 2, 5, 5, hair[0])
			_r(img, hx0 - 3, t + 2, 5, 1, hair[1])
		2:  # long, down the back
			_r(img, hx0 - 1, t + 9, 5, 11, hair[0])
			_r(img, hx0 - 1, t + 9, 1, 11, hair[1])
		3:  # fringe
			_r(img, hx0 + 6, t + 4, head - 8, 2, hair[0])
			_r(img, hx0 + 6, t + 5, head - 8, 1, hair[1])
	# hat
	var hc: Array = p.hat_col
	match String(p.hat):
		"beret":
			_r(img, hx0 - 1, t - 2, head + 2, 4, hc[0])
			_r(img, hx0 - 1, t + 1, head + 2, 1, hc[1])
			_r(img, hx0 + 6, t - 4, 2, 2, hc[1])
		"cap":
			_r(img, hx0, t - 2, head, 5, hc[0])
			_r(img, hx0, t + 1, head, 1, hc[1])
			_r(img, hx1 - 2, t + 2, 6, 1, hc[1])
		"beanie":
			_r(img, hx0, t - 3, head, 6, hc[0])
			_r(img, hx0, t + 2, head, 2, hc[1])
			for x in range(hx0 + 1, hx1, 3):
				_r(img, x, t - 2, 1, 3, hc[1])
			_r(img, hx0 + 5, t - 5, 4, 2, "f2d9c5")
		"kerchief":
			_r(img, hx0, t - 2, head - 1, 6, hc[0])
			_r(img, hx0 - 1, t + 3, 5, 10, hc[0])
			_r(img, hx0 - 1, t + 3, 1, 10, hc[1])
			_r(img, hx0 + 3, t + 3, head - 5, 1, hc[1])
			_r(img, hx0 + 1, t, 2, 1, "f2d9c5")
		"bonnet":
			_r(img, hx0, t - 2, head - 1, 7, hc[0])
			_r(img, hx1 - 2, t - 2, 3, 10, hc[1])
			_r(img, hx0 + 5, t + 5, 1, 6, hc[1])
			_r(img, hx0, t + 4, 5, 1, hc[1])
		"top":
			_r(img, hx0 + 2, t - 9, 10, 9, hc[0])
			_r(img, hx0 + 2, t - 3, 10, 2, "62272c")
			_r(img, hx0 - 1, t, head + 3, 1, hc[0])
			_r(img, hx0 + 3, t - 9, 1, 6, "49423d")
	return _outlined(img)


## Ink outline on every empty pixel that touches the figure (4-neighbours).
static func _outlined(src: Image) -> Image:
	var out := src.duplicate() as Image
	var ink := Color(INK)
	for y in H:
		for x in W:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < W and n.y < H and src.get_pixel(n.x, n.y).a > 0.5:
					out.set_pixel(x, y, ink)
					break
	return out


static func _r(img: Image, x: int, y: int, w: int, h: int, hex: Variant) -> void:
	var c := Color(String(hex))
	for yy in range(maxi(y, 0), mini(y + h, H)):
		for xx in range(maxi(x, 0), mini(x + w, W)):
			img.set_pixel(xx, yy, c)
