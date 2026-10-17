extends RefCounted
## MARKET-LIVE · The market square: game/assets/sprites/market/market_layout.json (ART-MARKET; format in the plan's
## shared market contract: Granny's stall and counter, vendors, walk graph, entries, pigeon zones, perches, musician,
## plus dog_sit, lanterns, garlands and the sprite sheets' frame sizes) and helpers for its sheets. When the file is
## missing a small layout on the town background keeps the scene playable.

const DIR := "res://assets/sprites/market/"
const FILE := DIR + "market_layout.json"
const TOWN_BG := "res://assets/sprites/scenes/bg_town.png"


static func load_layout() -> Dictionary:
	if FileAccess.file_exists(FILE):
		var f := FileAccess.open(FILE, FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
		if d is Dictionary and (d as Dictionary).has("walk"):
			return d
	return fallback()


## The town square with a stall in the middle (used only while the market art is missing).
static func fallback() -> Dictionary:
	return {
		"background": "",
		"granny_stall": {"x": 153, "y": 110, "size": [180, 125], "feet_y": 214, "counter": [168, 140, 144, 48],
			"sign": [190, 116, 100, 15], "granny": [322, 212]},
		"vendors": [
			{"id": "grocer", "stand": [70, 196], "front": [70, 230]},
			{"id": "postman", "stand": [420, 180], "front": [420, 230]},
		],
		"walk": {"nodes": [[0, 236], [70, 230], [140, 232], [240, 236], [340, 232], [420, 230], [479, 236], [240, 266]],
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [3, 7]]},
		"entries": [[0, 236], [479, 236], [240, 269]],
		"pigeon_zones": [[30, 244, 70, 16], [380, 244, 70, 16]],
		"perches": [],
		"musician": [460, 200],
		"sheets": {},
	}


static func background(layout: Dictionary) -> Texture2D:
	var name := String(layout.get("background", ""))
	if name != "" and ResourceLoader.exists(DIR + name):
		return load(DIR + name) as Texture2D
	return load(TOWN_BG) as Texture2D


## {"file", "frame": Vector2i, "feet": Vector2i, "anims": {name: [frame indices]}} of a sheet; {} when it is missing.
static func sheet(layout: Dictionary, id: String) -> Dictionary:
	var s: Dictionary = (layout.get("sheets", {}) as Dictionary).get(id, {})
	var file := DIR + String(s.get("file", id + ".png"))
	if s.is_empty() or not ResourceLoader.exists(file):
		return {}
	var fr: Array = s.get("frame", [16, 16])
	var feet: Array = s.get("feet", [int(fr[0]) / 2, int(fr[1]) - 1])
	return {"file": file, "frame": Vector2i(int(fr[0]), int(fr[1])), "feet": Vector2i(int(feet[0]), int(feet[1])),
		"anims": s.get("anims", {}), "texture": load(file) as Texture2D}


## Every frame of a sheet as an AtlasTexture (one horizontal row of frames).
static func frames(sh: Dictionary) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	if sh.is_empty():
		return out
	var tex: Texture2D = sh.texture
	var fr: Vector2i = sh.frame
	for i in floori(tex.get_width() / float(fr.x)):
		var a := AtlasTexture.new()
		a.atlas = tex
		a.region = Rect2(i * fr.x, 0, fr.x, fr.y)
		out.append(a)
	return out


static func v(a: Variant, fallback_v := Vector2.ZERO) -> Vector2:
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return fallback_v


static func rect(a: Variant) -> Rect2i:
	if a is Array and (a as Array).size() >= 4:
		return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
	return Rect2i()
