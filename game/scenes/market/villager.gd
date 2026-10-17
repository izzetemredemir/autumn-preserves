extends Node2D
## Market villager v2 (MARKET-LIVE, PCG showcase). A look (from a seed, or a vendor's fixed config) picks an archetype
## (man, woman, elder, child), hair, hats, glasses, beards, scarves, carried things and a colour ramp per role; the
## figure is layered from hand-drawn part sheets (game/assets/sprites/villagers/, sources in tools/style/src/villagers/)
## whose canonical role colours are swapped for the villager's ramps, then outlined in ink as one silhouette.
## Views: front, back, side (drawn facing left, flipped for right). Poses: walk 4, idle 2 (breath), look 1 (head
## turned), talk 2, wave 2, wipe 2 (vendors). Poses are composed on first use and cached per villager. The node origin
## is the feet (pivot PIVOT); never scaled. Same look -> same pixels, every run.

const DIR := "res://assets/sprites/villagers/"
const W := 24
const H := 56
const PIVOT := Vector2i(12, 55)
const INK := "111010"
const SHADOW := "3d1f29"

## Canonical colours of the part sheets, per role (shade -> light). The villager's ramp for a role has the same length.
const ROLES := {
	"skin": ["c58845", "e19064", "f2d9c5", "c94d2e"],
	"hair": ["50361e", "83571e", "b66813"],
	"coat": ["2e3f3f", "415c5d", "567c7d"],
	"lower": ["314524", "53612e", "747c37"],
	"shoes": ["23282a", "49423d"],
	"accent": ["9b8039", "e5bd7f", "dbcc83"],
	"hat": ["275e4c", "4e7664", "738c7a"],
	"shirt": ["b9a697", "b4b3a0"],
}
## Grip markers in the torso sheets (drawn as skin): left hand "+", right hand "*" (viewer's left/right).
const GRIP_L := "a22512"
const GRIP_R := "62272c"

## Autumn ramps per role (palette roles of art-bible §1), shade -> light.
const SKINS := [["e19064", "e5bd7f", "f2d9c5", "c94d2e"], ["c58845", "e19064", "e5bd7f", "c94d2e"],
	["b66813", "c58845", "e19064", "a22512"], ["83571e", "b66813", "c58845", "a22512"], ["50361e", "83571e", "b66813", "62272c"]]
const HAIRS := [["111010", "23282a", "49423d"], ["3d1f29", "50361e", "83571e"], ["50361e", "83571e", "c58845"],
	["62272c", "a22512", "c94d2e"], ["a22512", "c94d2e", "e19064"], ["b66813", "e5bd7f", "dbcc83"], ["83571e", "b66813", "e5bd7f"]]
const HAIRS_OLD := [["49423d", "81746a", "b4b3a0"], ["81746a", "b4b3a0", "f2d9c5"], ["81746a", "b9a697", "f2d9c5"], ["23282a", "49423d", "81746a"]]
const COATS := [["3d1f29", "62272c", "a22512"], ["62272c", "a22512", "c94d2e"], ["83571e", "b66813", "e19064"],
	["50361e", "83571e", "c58845"], ["83571e", "9b8039", "b1a13d"], ["314524", "53612e", "747c37"], ["53612e", "747c37", "b7b768"],
	["2e3f3f", "415c5d", "567c7d"], ["275e4c", "4e7664", "738c7a"], ["23282a", "49423d", "81746a"], ["81746a", "b9a697", "f2d9c5"],
	["9b8039", "c58845", "e5bd7f"]]
const LOWERS := [["23282a", "49423d", "81746a"], ["3d1f29", "50361e", "83571e"], ["2e3f3f", "415c5d", "567c7d"],
	["3d1f29", "62272c", "a22512"], ["314524", "53612e", "747c37"], ["50361e", "83571e", "c58845"], ["83571e", "9b8039", "b1a13d"]]
const SHOES := [["111010", "23282a"], ["23282a", "49423d"], ["3d1f29", "50361e"], ["50361e", "83571e"], ["3d1f29", "62272c"]]
const ACCENTS := [["a22512", "c94d2e", "e19064"], ["9b8039", "e5bd7f", "dbcc83"], ["b66813", "e19064", "f2d9c5"],
	["747c37", "b1a13d", "c5bf3f"], ["62272c", "c94d2e", "e19064"], ["4e7664", "738c7a", "b4b3a0"], ["53612e", "b7b768", "c5bf3f"],
	["b9a697", "f2d9c5", "f2d9c5"]]
const SHIRTS := [["b9a697", "f2d9c5"], ["9b8039", "e5bd7f"], ["81746a", "b4b3a0"], ["b66813", "e19064"], ["b1a13d", "dbcc83"]]

## Part sheets: frame size, whether role colours are swapped.
const SHEETS := {
	"head": {"size": Vector2i(16, 20), "swap": true},
	"hair": {"size": Vector2i(16, 20), "swap": true},
	"hats": {"size": Vector2i(16, 20), "swap": true},
	"beards": {"size": Vector2i(16, 20), "swap": true},
	"glasses": {"size": Vector2i(16, 20), "swap": false},
	"scarf": {"size": Vector2i(16, 20), "swap": true},
	"torso_man": {"size": Vector2i(22, 24), "swap": true},
	"torso_woman": {"size": Vector2i(22, 24), "swap": true},
	"torso_elder": {"size": Vector2i(22, 24), "swap": true},
	"torso_child": {"size": Vector2i(22, 16), "swap": true},
	"legs_trousers": {"size": Vector2i(22, 16), "swap": true},
	"legs_skirt": {"size": Vector2i(22, 18), "swap": true},
	"legs_child_trousers": {"size": Vector2i(22, 10), "swap": true},
	"legs_child_skirt": {"size": Vector2i(22, 10), "swap": true},
	"outfits": {"size": Vector2i(22, 24), "swap": true},
	"carry": {"size": Vector2i(12, 12), "swap": false},
	"cane": {"size": Vector2i(6, 20), "swap": false},
	"umbrella": {"size": Vector2i(22, 24), "swap": true},
}
const HAIR_STYLES := ["short", "tousled", "bob", "long", "bun", "bald", "pigtails"]
const HAT_KINDS := ["cap", "beret", "headscarf", "bonnet", "bowler", "postcap", "sunhat"]
## Body per archetype: sheets and anchors (top-left of each part sheet on the 24x56 canvas).
const BODIES := {
	"man": {"torso": "torso_man", "head": Vector2i(4, 8), "torso_at": Vector2i(1, 17), "legs_at": Vector2i(1, 39), "legs": "legs_trousers", "skirt": "legs_skirt", "skirt_at": Vector2i(1, 37)},
	"woman": {"torso": "torso_woman", "head": Vector2i(4, 9), "torso_at": Vector2i(1, 18), "legs_at": Vector2i(1, 39), "legs": "legs_trousers", "skirt": "legs_skirt", "skirt_at": Vector2i(1, 37)},
	"elder": {"torso": "torso_elder", "head": Vector2i(4, 12), "torso_at": Vector2i(1, 21), "legs_at": Vector2i(1, 39), "legs": "legs_trousers", "skirt": "legs_skirt", "skirt_at": Vector2i(1, 37)},
	"child": {"torso": "torso_child", "head": Vector2i(4, 21), "torso_at": Vector2i(1, 30), "legs_at": Vector2i(1, 45), "legs": "legs_child_trousers", "skirt": "legs_child_skirt", "skirt_at": Vector2i(1, 45)},
}
## Torso frame per view and pose name; children have no vendor poses (they fall back to stand).
const TORSO_FRAMES := {
	"front": {"stand": 0, "walk_a": 1, "walk_b": 2, "talk": 3, "wave_a": 4, "wave_b": 5, "wipe_a": 6, "wipe_b": 7},
	"side": {"stand": 8, "walk_a": 9, "walk_b": 10, "talk": 11},
	"back": {"stand": 12, "walk_a": 13, "walk_b": 14},
}
const TORSO_FRAMES_CHILD := {
	"front": {"stand": 0, "walk_a": 1, "walk_b": 2, "talk": 3},
	"side": {"stand": 4, "walk_a": 5, "walk_b": 6, "talk": 7},
	"back": {"stand": 8, "walk_a": 9, "walk_b": 10},
}
const VIEW_INDEX := {"front": 0, "side": 1, "back": 2}
## Outfit overlays (front view only): frame per archetype.
const OUTFITS := {"apron": {"man": 0, "woman": 1}, "satchel": {"man": 2}, "shawl": {"elder": 3, "woman": 4}}
## Carried things: carry sheet frames per view and the grip pixel inside the frame.
const CARRY := {"basket": [0, 1, 2], "bag": [3, 4, 5]}
## The hand pixel sits one pixel above the handle top.
const CARRY_GRIP := {"basket": Vector2i(5, -1), "bag": Vector2i(5, -1)}
const CANE_GRIP := Vector2i(4, 3)
## The umbrella sheet sits this far from the head anchor (canopy over the head, shaft on the right shoulder).
const UMBRELLA_AT := Vector2i(-3, -6)


static var _sheets: Dictionary = {}
static var _solids: Dictionary = {}

var look: Dictionary = {}
var _sprite: Sprite2D
var _cache: Dictionary = {}
var _key := ""


# --- looks ----------------------------------------------------------------------------------------------------------

## A villager look from a seed: parts and colour ramps for its archetype. `fancy` = a well-off buyer (bowler, fine coat),
## `rainy` = some carry an umbrella.
## `arch` overrides the archetype (MarketCrowd decides it, so the walking speed always matches the body).
static func look_for(seed: int, fancy := false, rainy := false, arch := "") -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	if arch == "":
		arch = MarketCrowd.arch_for(seed)
	var fem := r.randf() < 0.5
	if arch == "man":
		fem = false
	elif arch == "woman":
		fem = true
	var skirt := fem and r.randf() < 0.85
	var style := _style(r, arch, fem)
	var hat := "none"
	var hat_roll := r.randf()
	if hat_roll < 0.42:
		var kinds: Array = ["cap", "beret"] if not fem else ["beret", "headscarf", "bonnet"]
		if arch == "child":
			kinds = ["cap", "beret"] if not fem else ["bonnet", "beret"]
		hat = String(kinds[r.randi_range(0, kinds.size() - 1)])
	var old := arch == "elder"
	var l := {
		"arch": arch, "fem": fem, "skirt": skirt, "hair": style, "hat": hat,
		"glasses": r.randf() < (0.5 if old else (0.04 if arch == "child" else 0.14)),
		"beard": not fem and arch != "child" and r.randf() < (0.3 if old else 0.18),
		"moustache": not fem and arch != "child" and r.randf() < 0.16,
		"scarf": r.randf() < 0.32,
		"carry": ["none", "none", "basket", "basket", "bag"][r.randi_range(0, 4)],
		"cane": old and r.randf() < 0.45,
		"umbrella": false,
		"outfit": "",
		"colors": {
			"skin": SKINS[r.randi_range(0, SKINS.size() - 1)],
			"hair": (HAIRS_OLD if old else HAIRS)[r.randi_range(0, (HAIRS_OLD if old else HAIRS).size() - 1)],
			"coat": COATS[r.randi_range(0, COATS.size() - 1)],
			"lower": LOWERS[r.randi_range(0, LOWERS.size() - 1)],
			"shoes": SHOES[r.randi_range(0, SHOES.size() - 1)],
			"accent": ACCENTS[r.randi_range(0, ACCENTS.size() - 1)],
			"hat": COATS[r.randi_range(0, COATS.size() - 1)],
			"shirt": SHIRTS[r.randi_range(0, SHIRTS.size() - 1)],
		},
	}
	if bool(l.beard) and bool(l.moustache):
		l.moustache = false
	if rainy and r.randf() < 0.55:
		l.umbrella = true
	if bool(l.cane) and String(l.carry) == "bag":
		l.carry = "none"
	if fancy:
		l.hat = "bowler" if not fem else "bonnet"
		l.colors.coat = [COATS[0], COATS[1], COATS[7], COATS[8]][r.randi_range(0, 3)]
		l.colors.hat = ["23282a", "49423d", "81746a"] if not fem else ["62272c", "a22512", "c94d2e"]
		l.scarf = true
	return l


static func _style(r: RandomNumberGenerator, arch: String, fem: bool) -> String:
	var opts: Array
	match arch:
		"man": opts = ["short", "short", "tousled", "tousled", "bald"]
		"woman": opts = ["bob", "bob", "long", "long", "bun", "short"]
		"elder": opts = ["bun", "bun", "bob", "short"] if fem else ["bald", "bald", "short", "tousled"]
		_: opts = ["pigtails", "pigtails", "bob", "long"] if fem else ["tousled", "tousled", "short"]
	return String(opts[r.randi_range(0, opts.size() - 1)])


## The five neighbours at their stalls, matching their portraits.
static func vendor_look(id: String) -> Dictionary:
	var base := {"fem": false, "skirt": false, "glasses": false, "beard": false, "moustache": false, "scarf": false,
		"carry": "none", "cane": false, "umbrella": false, "outfit": ""}
	var l: Dictionary = base.duplicate()
	match id:
		"grocer":  # Barnaby: flat cap, moustache, cream shirt, green apron
			l.merge({"arch": "man", "hair": "short", "hat": "cap", "moustache": true, "outfit": "apron", "colors": {
				"skin": SKINS[1], "hair": HAIRS[2], "coat": COATS[10], "lower": LOWERS[1], "shoes": SHOES[2],
				"accent": ["314524", "53612e", "747c37"], "hat": ["50361e", "83571e", "9b8039"], "shirt": SHIRTS[0]}}, true)
		"baker":  # Rosie: red hair, red headscarf, teal top, floury cream apron
			l.merge({"arch": "woman", "fem": true, "skirt": true, "hair": "bob", "hat": "headscarf", "outfit": "apron", "colors": {
				"skin": SKINS[0], "hair": HAIRS[4], "coat": COATS[8], "lower": LOWERS[1], "shoes": SHOES[2],
				"accent": ["b9a697", "f2d9c5", "f2d9c5"], "hat": ["62272c", "a22512", "c94d2e"], "shirt": SHIRTS[0]}}, true)
		"postman":  # Pip: postman cap, satchel, blue-green coat
			l.merge({"arch": "man", "hair": "tousled", "hat": "postcap", "outfit": "satchel", "colors": {
				"skin": SKINS[1], "hair": HAIRS[2], "coat": COATS[7], "lower": LOWERS[2], "shoes": SHOES[1],
				"accent": ["50361e", "83571e", "c58845"], "hat": ["2e3f3f", "415c5d", "567c7d"], "shirt": SHIRTS[0]}}, true)
		"vintner":  # Vito: straw hat, moustache, plum vest
			l.merge({"arch": "man", "hair": "short", "hat": "sunhat", "moustache": true, "colors": {
				"skin": SKINS[2], "hair": HAIRS[0], "coat": COATS[0], "lower": LOWERS[1], "shoes": SHOES[2],
				"accent": ["9b8039", "e5bd7f", "dbcc83"], "hat": ["9b8039", "e5bd7f", "dbcc83"], "shirt": SHIRTS[0]}}, true)
		_:  # librarian Edith: white bun, glasses, shawl
			l.merge({"arch": "elder", "fem": true, "skirt": true, "hair": "bun", "hat": "none", "glasses": true, "outfit": "shawl", "colors": {
				"skin": SKINS[0], "hair": HAIRS_OLD[2], "coat": COATS[2], "lower": LOWERS[3], "shoes": SHOES[2],
				"accent": ["62272c", "c94d2e", "e19064"], "hat": COATS[0], "shirt": SHIRTS[0]}}, true)
	return l


# --- node -----------------------------------------------------------------------------------------------------------

func setup(l: Dictionary) -> void:
	look = l
	_cache.clear()
	_key = ""
	if _sprite == null:
		# a hard ground shadow under the feet, a pixel to the lower right (art-bible §2.5)
		var shadow := Node2D.new()
		shadow.name = "Shadow"
		shadow.draw.connect(func() -> void:
			var w := 9 if String(look.get("arch", "")) == "child" else 12
			shadow.draw_rect(Rect2(-floori(w / 2.0) + 1, 0, w, 2), Color(SHADOW)))
		add_child(shadow)
		_sprite = Sprite2D.new()
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	(get_node("Shadow") as Node2D).queue_redraw()
	show_pose("front", "idle", 0)


## view: front | back | left | right; anim: walk (0-3), idle (0-1), look (0-1: left, right), talk, wave, wipe (0-1).
func show_pose(view: String, anim: String, frame: int, blink := false) -> void:
	var flip := view == "right"
	var v := "side" if view in ["left", "right"] else view
	var key := "%s|%s|%d|%d" % [v, anim, frame, int(blink)]
	if key + str(flip) == _key:
		return
	_key = key + str(flip)
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(compose(look, v, anim, frame, blink))
	_sprite.texture = _cache[key]
	_sprite.flip_h = flip
	_sprite.offset = Vector2(-PIVOT.x if not flip else -(W - PIVOT.x), -PIVOT.y)


## Height of the figure's head top above the feet (for bubbles), in pixels.
func head_height() -> int:
	return head_top(look)


static func head_top(l: Dictionary) -> int:
	var body: Dictionary = BODIES[String(l.get("arch", "man"))]
	var top: int = Vector2i(body.head).y + 3
	if String(l.get("hat", "none")) != "none":
		top -= 2
	return PIVOT.y - top


# --- composing -----------------------------------------------------------------------------------------------------

## One outlined pose of a look as a W x H image (feet at PIVOT). view: front | side | back (side faces left).
static func compose(l: Dictionary, view: String, anim: String, frame: int, blink := false) -> Image:
	var colors := _color_map(l)
	var arch := String(l.get("arch", "man"))
	var body: Dictionary = BODIES[arch]
	var child := arch == "child"
	var vi: int = VIEW_INDEX[view]
	var f := posmod(frame, 4 if anim == "walk" else 2)
	# legs, torso and head frames for the pose; bob lifts everything above the legs
	var legs_f := 0
	var torso := "stand"
	var bob := 0
	var head_f := 0
	var head_view := view
	var head_flip := false
	match anim:
		"walk":
			legs_f = [1, 0, 2, 0][f]
			torso = ["walk_a", "stand", "walk_b", "stand"][f]
			bob = [0, -1, 0, -1][f]
		"idle":
			bob = -1 if f == 1 else 0
		"look":
			if view == "front":
				head_view = "side"
				head_flip = f == 1
		"talk":
			torso = "talk"
			head_f = 2 if f == 0 else 0
		"wave":
			torso = "wave_a" if f == 0 else "wave_b"
		"wipe":
			torso = "wipe_a" if f == 0 else "wipe_b"
	if blink and head_f == 0:
		head_f = 1
	var frames: Dictionary = (TORSO_FRAMES_CHILD if child else TORSO_FRAMES)[view]
	var torso_f: int = int(frames.get(torso, frames.stand))
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var lift := Vector2i(0, bob)
	var torso_sheet := String(body.torso)
	var torso_at: Vector2i = body.torso_at + lift
	var grips := _grips(torso_sheet, torso_f)
	var carry := String(l.get("carry", "none"))
	var carry_hand: Vector2i = torso_at + Vector2i(grips.get("L", Vector2i(-99, -99)))
	# a basket seen from the back hangs in front of the body: drawn first
	if carry != "none" and view == "back" and grips.has("L"):
		_draw_carry(img, carry, vi, carry_hand)
	# legs (trousers or skirt)
	var skirt := bool(l.get("skirt", false))
	var legs_sheet := String(body.skirt if skirt else body.legs)
	var legs_at: Vector2i = body.skirt_at if skirt else body.legs_at
	_layer(img, legs_sheet, vi * 3 + legs_f, legs_at, colors)
	_layer(img, torso_sheet, torso_f, torso_at, colors)
	var outfit := String(l.get("outfit", ""))
	if outfit != "" and view == "front" and OUTFITS.has(outfit) and (OUTFITS[outfit] as Dictionary).has(arch):
		_layer(img, "outfits", int(OUTFITS[outfit][arch]), torso_at, colors)
	# head group: head, beard, hair, glasses, hat, scarf under the chin
	var head := Image.create(16, 20, false, Image.FORMAT_RGBA8)
	var hv: int = VIEW_INDEX[head_view]
	var hf: int = [0, 3, 6][hv] + (head_f if hv < 2 else 0)
	_layer(head, "head", hf, Vector2i.ZERO, colors)
	if hv < 2:
		if bool(l.get("beard", false)):
			_layer(head, "beards", hv, Vector2i.ZERO, colors)
		elif bool(l.get("moustache", false)):
			_layer(head, "beards", 2 + hv, Vector2i.ZERO, colors)
	var style := HAIR_STYLES.find(String(l.get("hair", "short")))
	_layer(head, "hair", maxi(style, 0) * 3 + hv, Vector2i.ZERO, colors)
	if bool(l.get("glasses", false)) and hv < 2:
		_layer(head, "glasses", hv, Vector2i.ZERO, colors)
	var hat := HAT_KINDS.find(String(l.get("hat", "none")))
	if hat >= 0:
		_layer(head, "hats", hat * 3 + hv, Vector2i.ZERO, colors)
	if head_flip:
		head.flip_x()
	var head_at: Vector2i = body.head + lift
	if bool(l.get("scarf", false)):
		_layer(img, "scarf", vi, head_at, colors)
	img.blit_rect_mask(head, head, Rect2i(0, 0, 16, 20), head_at)
	if bool(l.get("scarf", false)) and view == "back":
		_layer(img, "scarf", 2, head_at, colors)
	# carried things in the hands
	if carry != "none" and view != "back" and grips.has("L"):
		_draw_carry(img, carry, vi, carry_hand)
	if bool(l.get("cane", false)) and grips.has("R") and view != "back":
		var hand: Vector2i = torso_at + Vector2i(grips.R)
		_layer(img, "cane", 0, hand - CANE_GRIP, colors)
	if bool(l.get("umbrella", false)):
		_layer(img, "umbrella", 0, head_at + UMBRELLA_AT, colors)
	return _outlined(img)


static func _draw_carry(img: Image, carry: String, vi: int, hand: Vector2i) -> void:
	var f: int = CARRY[carry][vi]
	_layer(img, "carry", f, hand - Vector2i(CARRY_GRIP[carry]), {})


## canonical hex -> Color for a look's ramps.
static func _color_map(l: Dictionary) -> Dictionary:
	var out := {}
	var cols: Dictionary = l.get("colors", {})
	for role: String in ROLES:
		var canon: Array = ROLES[role]
		var ramp: Array = cols.get(role, canon)
		for i in canon.size():
			out[String(canon[i])] = Color(String(ramp[mini(i, ramp.size() - 1)]))
	return out


## Draws one frame of a part sheet at `at`: fixed colours as they are, canonical colours swapped (swap sheets).
static func _layer(dst: Image, sheet_name: String, frame: int, at: Vector2i, colors: Dictionary) -> void:
	var s := _sheet(sheet_name)
	if s.is_empty() or frame < 0 or frame >= int(s.n):
		return
	var size: Vector2i = s.size
	var rect := Rect2i(frame * size.x, 0, size.x, size.y)
	var fixed: Image = s.fixed
	dst.blit_rect_mask(fixed, fixed, rect, at)
	var masks: Dictionary = s.masks
	for hex: String in masks:
		var c: Color = colors.get(hex, Color(hex))
		dst.blit_rect_mask(_solid(c, Vector2i(fixed.get_width(), fixed.get_height())), masks[hex], rect, at)


## Grip pixels {"L", "R"} of a torso frame (frame-local).
static func _grips(sheet_name: String, frame: int) -> Dictionary:
	var s := _sheet(sheet_name)
	if s.is_empty():
		return {}
	return (s.grips as Dictionary).get(frame, {})


## Loads and splits a part sheet once: fixed-colour pixels, one mask per canonical colour, grip markers.
static func _sheet(sheet_name: String) -> Dictionary:
	if _sheets.has(sheet_name):
		return _sheets[sheet_name]
	var path := DIR + sheet_name + ".png"
	var src: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			src = tex.get_image()
	if src == null:
		_sheets[sheet_name] = {}
		return {}
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var def: Dictionary = SHEETS[sheet_name]
	var size: Vector2i = def.size
	var swap := bool(def.swap)
	var canon := {}
	if swap:
		for role: String in ROLES:
			for hex: String in ROLES[role]:
				canon[hex] = true
	var w := src.get_width()
	var h := src.get_height()
	var fixed := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var masks := {}
	var grips := {}
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var hex := c.to_html(false)
			if swap and (hex == GRIP_L or hex == GRIP_R):
				var fr := floori(float(x) / size.x)
				if not grips.has(fr):
					grips[fr] = {}
				grips[fr]["L" if hex == GRIP_L else "R"] = Vector2i(x - fr * size.x, y)
				hex = "e19064"
			if canon.has(hex):
				if not masks.has(hex):
					masks[hex] = Image.create(w, h, false, Image.FORMAT_RGBA8)
				(masks[hex] as Image).set_pixel(x, y, Color(1, 1, 1, 1))
			else:
				fixed.set_pixel(x, y, Color(hex))
	var s := {"size": size, "n": floori(float(w) / size.x), "fixed": fixed, "masks": masks, "grips": grips}
	_sheets[sheet_name] = s
	return s


static func _solid(c: Color, size: Vector2i) -> Image:
	var key := "%s|%d|%d" % [c.to_html(false), size.x, size.y]
	if not _solids.has(key):
		var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		img.fill(Color(c, 1.0))
		_solids[key] = img
	return _solids[key]


## Ink outline around the whole figure (4-neighbours), as one silhouette.
static func _outlined(fig: Image) -> Image:
	var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var ink := _solid(Color(INK), Vector2i(W, H))
	var full := Rect2i(0, 0, W, H)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		out.blit_rect_mask(ink, fig, full, d)
	out.blit_rect_mask(fig, fig, full, Vector2i.ZERO)
	return out
