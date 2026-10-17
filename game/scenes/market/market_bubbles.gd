extends Control
## MARKET-LIVE · The one speech-bubble manager of the market: at most MAX bubbles at a time, above the speaker's head
## with a tail pointing at them, or beside the head when that would cover Granny's counter, another bubble or the HUD.
## A line that finds no free spot waits a moment, then is dropped (a higher priority line pushes out a lower one).
## Speakers are given as a Callable returning their head-top point (Vector2.INF when gone).
## UI-COMPACT: the bubbles are SpeechBubble (body font, at most 168 px wide and 3 lines), one per speaker.

const MAX := 3
const WAIT := 0.8

## Rects no bubble may cover (Granny's counter, the HUD).
var blocked: Array[Rect2] = []
var _active: Array = []
var _pending: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(480, 270)


func clear() -> void:
	for b in _active:
		(b.node as Control).queue_free()
	_active.clear()
	_pending.clear()


func count() -> int:
	return _active.size()


## Every shown bubble: [{"who", "rect": Rect2, "key"}] (smoke tests).
func shown() -> Array:
	var out: Array = []
	for b in _active:
		out.append({"who": b.who, "rect": Rect2((b.node as Control).position, (b.node as Control).size), "key": b.key})
	return out


func say(who: String, key: String, head: Callable, prio := 1, dur := 1.8) -> void:
	for b in _active + _pending:
		if String(b.who) == who:
			return
	_pending.append({"who": who, "key": key, "head": head, "prio": prio, "dur": dur, "age": 0.0})


func step(dt: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var b: Dictionary = _active[i]
		b.life = float(b.life) - dt
		var h: Vector2 = (b.head as Callable).call()
		if float(b.life) <= 0.0 or h == Vector2.INF:
			(b.node as Control).queue_free()
			_active.remove_at(i)
			continue
		_follow(b, h)
	_pending.sort_custom(func(a: Dictionary, z: Dictionary) -> bool: return int(a.prio) > int(z.prio))
	for i in range(_pending.size() - 1, -1, -1):
		var p: Dictionary = _pending[i]
		p.age = float(p.age) + dt
		var h: Vector2 = (p.head as Callable).call()
		if h == Vector2.INF or float(p.age) > WAIT:
			_pending.remove_at(i)
			continue
		if _active.size() >= MAX:
			var low := -1
			for k in _active.size():
				if int(_active[k].prio) < int(p.prio) and (low < 0 or int(_active[k].prio) < int(_active[low].prio)):
					low = k
			if low < 0:
				continue
			(_active[low].node as Control).queue_free()
			_active.remove_at(low)
		if _show(p, h):
			_pending.remove_at(i)


func _show(p: Dictionary, h: Vector2) -> bool:
	var node := SpeechBubble.new()
	add_child(node)
	node.say(tr(String(p.key)))
	var bs := node.size
	var spot := _place(h, bs, null)
	if spot.is_empty():
		node.queue_free()
		return false
	var b := {"who": p.who, "key": p.key, "head": p.head, "prio": p.prio, "life": p.dur, "node": node, "side": spot.side,
		"rel": (spot.pos as Vector2) - h}
	node.position = spot.pos
	node.side = String(spot.side)
	node.tail = h - node.position
	node.pivot_offset = (bs / 2.0).floor()
	node.scale = Vector2(0.6, 0.6)
	node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active.append(b)
	node.queue_redraw()
	return true


## Keeps a bubble next to a moving speaker; re-places it when its spot became bad.
func _follow(b: Dictionary, h: Vector2) -> void:
	var node: Control = b.node
	var want := (h + (b.rel as Vector2)).round()
	want = _clamp(want, node.size)
	if want != node.position:
		if _free(Rect2(want, node.size), b):
			node.position = want
		else:
			var spot := _place(h, node.size, b)
			if not spot.is_empty():
				node.position = spot.pos
				b.side = spot.side
				b.rel = (spot.pos as Vector2) - h
	node.set("side", String(b.side))
	node.set("tail", h - node.position)
	node.queue_redraw()


## First free spot: above the head (centred, then shifted), else beside the head (right, left).
func _place(h: Vector2, bs: Vector2, me: Variant) -> Dictionary:
	var cands := [
		[Vector2(h.x - floorf(bs.x / 2.0), h.y - 5 - bs.y), "below"],
		[Vector2(h.x - bs.x + 8, h.y - 5 - bs.y), "below"],
		[Vector2(h.x - 8, h.y - 5 - bs.y), "below"],
		[Vector2(h.x + 9, h.y + 6), "left"],
		[Vector2(h.x - 9 - bs.x, h.y + 6), "right"],
		[Vector2(h.x + 9, h.y - 4), "left"],
		[Vector2(h.x - 9 - bs.x, h.y - 4), "right"],
	]
	for c in cands:
		var pos := _clamp((c[0] as Vector2).round(), bs)
		if _free(Rect2(pos, bs), me):
			return {"pos": pos, "side": c[1]}
	return {}


func _clamp(pos: Vector2, bs: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 3.0, 477.0 - bs.x), clampf(pos.y, 3.0, 267.0 - bs.y))


func _free(r: Rect2, me: Variant) -> bool:
	var grown := r.grow(1.0)
	for x in blocked:
		if grown.intersects(x):
			return false
	for b in _active:
		if me != null and is_same(b, me):
			continue
		var n: Control = b.node
		if grown.intersects(Rect2(n.position, n.size)):
			return false
	return true
