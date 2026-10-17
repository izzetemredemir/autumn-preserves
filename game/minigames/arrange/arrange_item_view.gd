class_name ArrangeItemView
extends Control
## How a game item looks in a placement footprint or an inbox slot (pantry, parcel, stall).
## Products: JarIcon, shelf view bottom-centred (icon view centred when the shelf view does not fit), on a wooden
## crate when the footprint is bigger than the jar (pie, bread). Fresh items and nuts: the 16x16 icon from
## res://assets/sprites/icons/<type>.png, or a palette blob for types without one, plus the stack count.

const ICON_DIR := "res://assets/sprites/icons/"
const INK := Color("111010")
const CREAM := Color("f2d9c5")
const CRATE := Color("83571e")
const CRATE_EDGE := Color("50361e")
const CRATE_HI := Color("c58845")
const DEFAULT_RAMP := ["50361e", "83571e", "b66813", "c58845", "e5bd7f"]
## 3x5 pixel digits, row-major.
const DIGITS := ["111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
	"111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111"]

var item: Dictionary = {}
var _icon: Texture2D
var _ramp: Array = DEFAULT_RAMP
var _crate := false
var _count := 0


static func make(p_item: Dictionary, _rot: int, px: Vector2i, varieties: Dictionary = {}) -> ArrangeItemView:
	var v := ArrangeItemView.new()
	v.item = p_item
	v.size = Vector2(px)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if String(p_item.get("kind", "")) == "product":
		var desc := ProductGen.describe(String(p_item.get("key", "")), varieties)
		var jar := JarIcon.new()
		jar.show_product(desc)
		var js := JarIcon.pixel_size(desc, "shelf")
		if js.x <= px.x and js.y <= px.y:
			jar.position = Vector2(floori((px.x - js.x) / 2.0), px.y - js.y)
		else:
			jar.view = "icon"
			js = JarIcon.pixel_size(desc, "icon")
			jar.position = Vector2(floori((px.x - js.x) / 2.0), floori((px.y - js.y) / 2.0))
		v._crate = px.x > js.x or px.y > js.y
		v.add_child(jar)
	else:
		var type := State.item_type(p_item)
		var path := ICON_DIR + type + ".png"
		if ResourceLoader.exists(path):
			v._icon = load(path)
		elif IconLib.is_generated(type):  # SPECIES-GEN: generated species icons (pantry, inbox)
			v._icon = IconLib.ingredient(type)
		var ing: Dictionary = Data.ingredients().get(type, {})
		v._ramp = ing.get("ramp", DEFAULT_RAMP)
		v._count = int(p_item.get("count", 1))
	return v


## Draws `n` in 3x5 digits on `ci` with its top-right corner at `top_right`, on a 1-px ink plate.
static func draw_number(ci: CanvasItem, n: int, top_right: Vector2i, col: Color = CREAM) -> void:
	var s := str(n)
	var w := s.length() * 4 - 1
	var x0 := top_right.x - w
	ci.draw_rect(Rect2(x0 - 1, top_right.y - 1, w + 2, 7), INK)
	for k in s.length():
		var bits: String = DIGITS[int(s[k])]
		for i in 15:
			if bits[i] == "1":
				ci.draw_rect(Rect2(x0 + k * 4 + i % 3, top_right.y + floori(i / 3.0), 1, 1), col)


func _draw() -> void:
	var w := int(size.x)
	var h := int(size.y)
	if _crate:
		draw_rect(Rect2(1, 1, w - 2, h - 2), CRATE_EDGE)
		draw_rect(Rect2(2, 2, w - 4, h - 4), CRATE)
		draw_rect(Rect2(2, 2, w - 4, 1), CRATE_HI)
		for y in range(8, h - 3, 8):
			draw_rect(Rect2(2, y, w - 4, 1), CRATE_EDGE)
	if String(item.get("kind", "")) == "product":
		return
	if _icon != null:
		draw_texture(_icon, Vector2(floori((w - 16) / 2.0), floori((h - 16) / 2.0)))
	else:
		var r := maxf(4.0, minf(w, h) * 0.5 - 3.0)
		_blob(w * 0.5, h * 0.5 + 1.0, r, r * 0.85)
	if _count > 1:
		draw_number(self, _count, Vector2i(w - 2, h - 7))


## Shaded palette ellipse (light top-left, dark bottom-right, ink rim) for items without an icon.
func _blob(cx: float, cy: float, rx: float, ry: float) -> void:
	var tones: Array[Color] = []
	for hex in _ramp:
		tones.append(Color(String(hex)))
	for y in range(floori(cy - ry), ceili(cy + ry)):
		for x in range(floori(cx - rx), ceili(cx + rx)):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var inner := (x + 0.5 - cx) / (rx - 1.0)
			var inner_y := (y + 0.5 - cy) / (ry - 1.0)
			var col := tones[2]
			if inner * inner + inner_y * inner_y > 1.0:
				col = INK
			elif dx + dy < -0.7:
				col = tones[3]
			elif dx + dy > 0.6:
				col = tones[1]
			draw_rect(Rect2(x, y, 1, 1), col)
