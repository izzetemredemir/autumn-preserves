extends Node2D
## Granny's look, feet at the origin. Uses ART-02's strips (res://assets/sprites/granny/, 16x32 frames,
## pivot 8,31, art-bible §3.2) when they are all there, else a 16x32 gray box with a facing marker.
## Granny sets `facing` and `walking`; act("shake" | "pick") plays a one-shot action.

const DIR := "res://assets/sprites/granny/granny_%s.png"
const STRIPS := {"walk_down": 4, "walk_up": 4, "walk_left": 4, "walk_right": 4, "idle": 2, "shake": 3, "pick": 3}
const SPEED := {"walk": 8.0, "idle": 2.0, "shake": 10.0, "pick": 10.0}

const C_INK := Color("111010")
const C_BODY := Color("81746a")  # stone_500
const C_HEAD := Color("b4b3a0")  # stone_300
const C_APRON := Color("f2d9c5")  # cream_100
const C_MARK := Color("c94d2e")  # leaf_red_500

static var _frames: SpriteFrames
static var _checked := false

var facing := Vector2i.DOWN:
	set(v):
		facing = v
		_update()
var walking := false:
	set(v):
		if v != walking:
			walking = v
			if v:
				_acting = false
			_update()
## Animation speed multiplier (Granny sets it: slower steps on days 90-99, spec §7.12).
var anim_scale := 1.0:
	set(v):
		anim_scale = v
		if _sprite != null:
			_sprite.speed_scale = v

var _sprite: AnimatedSprite2D
var _acting := false


func _ready() -> void:
	var frames := sprite_frames()
	if frames == null:
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.speed_scale = anim_scale
	_sprite.centered = false
	_sprite.offset = Vector2(-8, -32)
	_sprite.animation_finished.connect(_on_action_done)
	add_child(_sprite)
	_update()


func has_sprite() -> bool:
	return _sprite != null


func act(action: String) -> void:
	if _sprite == null or not _sprite.sprite_frames.has_animation(action):
		return
	_acting = true
	_sprite.play(action)
	_sprite.frame = 0


## Built once from the strips; null while any strip is missing (then the gray box is drawn).
static func sprite_frames() -> SpriteFrames:
	if _checked:
		return _frames
	_checked = true
	for anim in STRIPS:
		if not ResourceLoader.exists(DIR % anim):
			return null
	var sf := SpriteFrames.new()
	for anim in STRIPS:
		var tex: Texture2D = load(DIR % anim)
		sf.add_animation(anim)
		sf.set_animation_speed(anim, SPEED[String(anim).get_slice("_", 0)])
		sf.set_animation_loop(anim, anim == "idle" or String(anim).begins_with("walk"))
		for i in int(STRIPS[anim]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * 16, 0, 16, 32)
			sf.add_frame(anim, at)
	for d in ["up", "left", "right"]:  # standing still sideways or back: first walk frame
		sf.add_animation("stand_" + d)
		sf.add_frame("stand_" + d, sf.get_frame_texture("walk_" + d, 0))
	_frames = sf
	return sf


func _update() -> void:
	if _sprite == null:
		queue_redraw()
		return
	if _acting:
		return
	var d := _dir_name()
	if walking:
		_sprite.play("walk_" + d)
	elif d == "down":
		_sprite.play("idle")
	else:
		_sprite.play("stand_" + d)


func _on_action_done() -> void:
	if _acting:
		_acting = false
		_update()


func _dir_name() -> String:
	if facing == Vector2i.UP:
		return "up"
	if facing == Vector2i.LEFT:
		return "left"
	if facing == Vector2i.RIGHT:
		return "right"
	return "down"


func _draw() -> void:
	if _sprite != null:
		return
	draw_rect(Rect2(-8, -32, 16, 32), C_INK)
	draw_rect(Rect2(-7, -31, 14, 30), C_BODY)
	draw_rect(Rect2(-6, -30, 12, 11), C_HEAD)
	if facing != Vector2i.UP:
		draw_rect(Rect2(-4, -17, 8, 12), C_APRON)
		var look := facing.x * 2
		draw_rect(Rect2(-4 + look, -25, 2, 2), C_INK)
		draw_rect(Rect2(2 + look, -25, 2, 2), C_INK)
	if facing == Vector2i.DOWN:
		draw_rect(Rect2(-3, -3, 6, 3), C_MARK)
	elif facing == Vector2i.UP:
		draw_rect(Rect2(-3, -32, 6, 3), C_MARK)
	elif facing == Vector2i.LEFT:
		draw_rect(Rect2(-8, -20, 3, 6), C_MARK)
	else:
		draw_rect(Rect2(5, -20, 3, 6), C_MARK)
