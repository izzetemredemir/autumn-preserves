class_name RoomBar
extends HBoxContainer
## HOUSE-DOORS · The house's room bar: four small plank buttons, Garden · Kitchen · Pantry · Parlour (ROOM_* strings,
## m5x7), bottom-left in the kitchen, the pantry and the parlour. The room Granny is in shows pressed (a ButtonGroup:
## pressing it again does nothing); another one walks there like a door does (door sound, outdoor sound for the
## garden, Transition's fade and autosave, then Router.goto). Real Buttons: click, touch, and keys (the arrows from
## the room's objects reach it, Tab, Enter / interact). It hides itself while a popup, card, mini-game, letters,
## book, fade or the menu shows (CanvasLayers 12-99 with visible content under the root or the room, as Granny's
## guide checks) and while the room says it is busy (`active` false).

signal leaving(target: String)

const ROOMS := [["garden", "ROOM_GARDEN"], ["kitchen", "ROOM_KITCHEN"], ["pantry", "ROOM_PANTRY"], ["parlor", "ROOM_PARLOR"]]
const TRANSITION_GD := "res://ui/transition/transition.gd"
const BTN := preload("res://assets/sprites/ui/ui_button.png")
const FONT := preload("res://assets/fonts/m5x7.ttf")
const POPUPS := Vector2i(12, 99)
## ui_button.png frames (48x16 each): normal, hover, pressed (dark), disabled.
const FRAMES := {"normal": 0, "hover": 1, "pressed": 2, "disabled": 3}
const H := 14  ## button height: m5x7's 13 px line + 1
const GAP := 2
const CREAM := Color("f2d9c5")
const GOLD := Color("e5bd7f")

## Room id of the scene the bar sits in ("kitchen" | "pantry" | "parlor").
var current := ""
## False while the room has a panel, dialog or mini-game of its own open (the room sets it).
var active := true
var buttons: Dictionary = {}  ## room id -> Button
var _room: Node


## Builds a bar for `room` at `at` (whole pixels) in `parent` and returns it.
static func attach(parent: Node, room: String, at: Vector2i) -> RoomBar:
	var bar := RoomBar.new()
	bar.current = room
	bar._room = parent
	bar.position = Vector2(at)
	parent.add_child(bar)
	return bar


func _ready() -> void:
	name = "RoomBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", GAP)
	var styles := {}
	for st: String in FRAMES:
		var sb := StyleBoxTexture.new()
		sb.texture = BTN
		sb.region_rect = Rect2(48 * int(FRAMES[st]), 0, 48, 16)
		sb.set_texture_margin_all(5)
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		sb.content_margin_top = 0
		sb.content_margin_bottom = 1
		styles[st] = sb
	var group := ButtonGroup.new()
	for r: Array in ROOMS:
		var b := Button.new()
		b.name = String(r[0]).capitalize()
		b.text = tr(String(r[1]))
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_override("font", FONT)
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_stylebox_override("normal", styles.normal)
		b.add_theme_stylebox_override("hover", styles.hover)
		b.add_theme_stylebox_override("pressed", styles.pressed)
		b.add_theme_stylebox_override("hover_pressed", styles.pressed)
		b.add_theme_stylebox_override("disabled", styles.disabled)
		for k in ["font_color", "font_hover_color", "font_focus_color"]:
			b.add_theme_color_override(k, CREAM)
		for k in ["font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, GOLD)
		b.custom_minimum_size = Vector2(0, H)
		b.button_pressed = String(r[0]) == current
		b.pressed.connect(_go.bind(String(r[0])))
		add_child(b)
		buttons[String(r[0])] = b
	reset_size()


## The room's own busy flag (panel, dialog, mini-game, drawing): the bar hides while it is false.
func set_active(on: bool) -> void:
	active = on
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var show := active and not _popup_open()
	if visible != show:
		visible = show


## A popup, card, mini-game, letters, book, fade or the menu is on screen.
func _popup_open() -> bool:
	if not is_inside_tree():
		return false
	var nodes: Array[Node] = get_tree().root.get_children()
	if _room != null and is_instance_valid(_room):
		nodes.append_array(_room.get_children())
	for n in nodes:
		var cl := n as CanvasLayer
		if cl == null or not cl.visible or cl.layer < POPUPS.x or cl.layer > POPUPS.y:
			continue
		for c in cl.get_children():
			if c is CanvasItem and (c as CanvasItem).visible:
				return true
	return false


func _go(target: String) -> void:
	if target == current or not visible:
		_keep_current()
		return
	if target == "garden" and not Router.exists("garden"):
		target = "wild"
	if not Router.exists(target):
		Audio.play_ui("ui_error")
		_keep_current()
		return
	leaving.emit(target)
	Audio.play_sfx("sfx_door_open")
	if target not in ["kitchen", "pantry", "parlor"]:
		Audio.set_indoor(false)
	active = false
	if ResourceLoader.exists(TRANSITION_GD):
		load(TRANSITION_GD).go(target)
	else:
		Router.goto(target)


## The current room's button stays the pressed one.
func _keep_current() -> void:
	if buttons.has(current):
		(buttons[current] as Button).set_pressed_no_signal(true)
