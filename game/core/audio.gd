extends Node
## Autoload "Audio" (docs/audio.md §7, frozen in tech-spec §9). Ids map to files by prefix, no manifest:
##   mus_*/jgl_* -> res://assets/audio/music/<id>.ogg · amb_* -> res://assets/audio/ambient/<id>.ogg
##   sfx_*/ui_*  -> res://assets/audio/sfx/<id>.wav, or variations <id>_01.wav, <id>_02.wav ...
## A missing file warns once and plays nothing, so code can call ids before the assets exist.

const SFX_VOICES := 8
const SILENT_DB := -40.0

var _sfx_pool: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _music_id := ""
var _music_idx := 0
var _jingle: AudioStreamPlayer
var _ambient: Dictionary = {}
var _loops: Dictionary = {}
var _cache: Dictionary = {}
var _warned: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i in SFX_VOICES:
		_sfx_pool.append(_player("SFX"))
	_music = [_player("Music"), _player("Music")]
	_jingle = _player("Music")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		var paused := what == NOTIFICATION_APPLICATION_FOCUS_OUT
		for p in _music:
			p.stream_paused = paused


func play_sfx(id: String, vary := true) -> void:
	_play_one(id, "SFX", vary)


func play_ui(id: String) -> void:
	_play_one(id, "UI", false)


func play_music(id: String, crossfade_sec := 1.5) -> void:
	if id == _music_id:
		return
	var s := _streams(id)
	_music_id = id
	var old := _music[_music_idx]
	_music_idx = 1 - _music_idx
	var cur := _music[_music_idx]
	if not s.is_empty():
		cur.stream = _looping(s[0])
		cur.volume_db = SILENT_DB
		cur.play()
		create_tween().tween_property(cur, "volume_db", 0.0, crossfade_sec)
	if old.playing:
		var t := create_tween()
		t.tween_property(old, "volume_db", SILENT_DB, crossfade_sec)
		t.tween_callback(old.stop)


func stop_music(fade_sec := 1.5) -> void:
	_music_id = ""
	for p in _music:
		if p.playing:
			var t := create_tween()
			t.tween_property(p, "volume_db", SILENT_DB, fade_sec)
			t.tween_callback(p.stop)


## Plays a jingle and ducks the music under it.
func play_jingle(id: String) -> void:
	var s := _streams(id)
	if s.is_empty():
		return
	_jingle.stream = s[0]
	_jingle.play()
	var cur := _music[_music_idx]
	if cur.playing:
		var t := create_tween()
		t.tween_property(cur, "volume_db", -10.0, 0.2)
		t.tween_interval(maxf(s[0].get_length() - 0.4, 0.1))
		t.tween_property(cur, "volume_db", 0.0, 0.6)


func play_ambient(id: String, fade_sec := 2.0) -> void:
	if _ambient.has(id):
		return
	var s := _streams(id)
	if s.is_empty():
		return
	var p := _player("Ambient")
	p.stream = _looping(s[0])
	p.volume_db = SILENT_DB
	p.play()
	_ambient[id] = p
	create_tween().tween_property(p, "volume_db", 0.0, fade_sec)


func stop_ambient(id: String, fade_sec := 2.0) -> void:
	if not _ambient.has(id):
		return
	var p: AudioStreamPlayer = _ambient[id]
	_ambient.erase(id)
	var t := create_tween()
	t.tween_property(p, "volume_db", SILENT_DB, fade_sec)
	t.tween_callback(p.queue_free)


## Continuous effects such as sfx_stir_loop; speed scales pitch.
func set_loop_sfx(id: String, on: bool, speed := 1.0) -> void:
	if on:
		if not _loops.has(id):
			var s := _streams(id)
			if s.is_empty():
				return
			var p := _player("SFX")
			p.stream = _looping(s[0])
			p.play()
			_loops[id] = p
		_loops[id].pitch_scale = clampf(speed, 0.5, 2.0)
	elif _loops.has(id):
		_loops[id].queue_free()
		_loops.erase(id)


func set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


## Muffles ambience indoors (low-pass effect 0 on the Ambient bus, see default_bus_layout.tres).
func set_indoor(on: bool) -> void:
	var idx := AudioServer.get_bus_index("Ambient")
	if idx >= 0 and AudioServer.get_bus_effect_count(idx) > 0:
		AudioServer.set_bus_effect_enabled(idx, 0, on)


func _play_one(id: String, bus: String, vary: bool) -> void:
	var s := _streams(id)
	if s.is_empty():
		return
	var p := _free_voice()
	p.bus = _bus(bus)
	p.stream = s[_rng.randi_range(0, s.size() - 1)] if vary else s[0]
	p.pitch_scale = _rng.randf_range(0.94, 1.06) if vary else 1.0
	p.volume_db = 0.0
	p.play()


func _free_voice() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	return _sfx_pool[0]


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = _bus(bus)
	add_child(p)
	return p


func _bus(bus: String) -> String:
	return bus if AudioServer.get_bus_index(bus) >= 0 else "Master"


func _looping(stream: AudioStream) -> AudioStream:
	if "loop" in stream:
		stream.loop = true
	return stream


func _streams(id: String) -> Array:
	if _cache.has(id):
		return _cache[id]
	var out: Array = []
	var long := id.begins_with("mus_") or id.begins_with("jgl_") or id.begins_with("amb_")
	var ext := ".ogg" if long else ".wav"
	var dir := "res://assets/audio/sfx/"
	if id.begins_with("mus_") or id.begins_with("jgl_"):
		dir = "res://assets/audio/music/"
	elif id.begins_with("amb_"):
		dir = "res://assets/audio/ambient/"
	if ResourceLoader.exists(dir + id + ext):
		out.append(load(dir + id + ext))
	else:
		for n in range(1, 13):
			var path := "%s%s_%02d%s" % [dir, id, n, ext]
			if not ResourceLoader.exists(path):
				break
			out.append(load(path))
	if out.is_empty() and not _warned.has(id):
		_warned[id] = true
		push_warning("Audio: no file for id " + id)
	_cache[id] = out
	return out
