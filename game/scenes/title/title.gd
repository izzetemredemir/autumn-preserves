extends Control
## Title (GD-META): name, slogan, New Game (with a seed field), Continue, Seed Lab, Settings.
## New Game -> premise (ui/premise) -> garden (kitchen until the garden exists). Continue loads the save; a save the
## farewell closed (spec §7.12) shows a "Completed" card and Continue becomes Memory (scenes/farewell, Memory mode).
## Also applies saved settings and adds the debug panel (F1) in debug builds. A language change in Settings reloads
## the title so every text is built again in the new language, with Settings open again (L10N-TR).

const MUSIC_DIR := "res://assets/audio/music/"
const MUSIC_FALLBACK := "res://assets/audio/music/candidates/mus_title_a.ogg"
const PREMISE := "res://ui/premise/premise.tscn"

var _new_panel: PanelContainer
var _seed_edit: LineEdit
var _overwrite: Label
var _settings: SettingsPanel
var _fallback_music: AudioStreamPlayer
var _starting := false
var _completed_card: Control
## Set before the language reload: the rebuilt title opens Settings again.
static var _reopen_settings := false


func _ready() -> void:
	GameSettings.apply()
	DevPanel.ensure()
	_play_music()
	_build_new_game_panel()
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_show_menu)
	_settings.language_changed.connect(_on_language_changed)
	_center(_settings)
	%NewGame.pressed.connect(_on_new_game)
	%Continue.pressed.connect(_on_continue)
	%SeedLab.pressed.connect(_on_seed_lab)
	%Settings.pressed.connect(_on_settings)
	%Continue.disabled = not Save.has_save()
	var saved := Save.load_game() if Save.has_save() else {}
	if Farewell.is_completed(saved):
		_show_completed(Farewell.completed_day(saved))
	%SeedLab.disabled = not Router.exists("seed_lab")
	if %Continue.disabled:
		%NewGame.grab_focus()
	else:
		%Continue.grab_focus()
	if _reopen_settings:
		_reopen_settings = false
		_on_settings()


func _play_music() -> void:
	if ResourceLoader.exists(MUSIC_DIR + "mus_title.ogg"):
		Audio.play_music("mus_title")
		return
	# Until the human picks a title theme, play candidate A on the Music bus.
	Audio.stop_music(0.5)
	if not ResourceLoader.exists(MUSIC_FALLBACK):
		return
	var stream: AudioStream = load(MUSIC_FALLBACK)
	if "loop" in stream:
		stream.loop = true
	_fallback_music = AudioStreamPlayer.new()
	_fallback_music.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	_fallback_music.stream = stream
	add_child(_fallback_music)
	_fallback_music.play()


func _center(panel: Control) -> void:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_top = 40
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	c.add_child(panel)


func _build_new_game_panel() -> void:
	_new_panel = PanelContainer.new()
	_new_panel.visible = false
	_center(_new_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_new_panel.add_child(box)
	var head := Label.new()
	head.text = tr("TITLE_NEW_GAME")
	head.theme_type_variation = &"Heading"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var label := Label.new()
	label.text = tr("TITLE_SEED")
	row.add_child(label)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = tr("TITLE_SEED_RANDOM")
	_seed_edit.max_length = 16
	_seed_edit.custom_minimum_size = Vector2(120, 0)
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _start())
	row.add_child(_seed_edit)
	_overwrite = Label.new()
	_overwrite.text = tr("TITLE_OVERWRITE")
	_overwrite.add_theme_color_override("font_color", Color("e19064"))
	_overwrite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_overwrite)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	var back := Button.new()
	back.text = tr("UI_BACK")
	back.pressed.connect(func() -> void:
		Audio.play_ui("ui_back")
		_show_menu())
	buttons.add_child(back)
	var start := Button.new()
	start.text = tr("TITLE_START")
	start.pressed.connect(_start)
	buttons.add_child(start)


func _show_menu() -> void:
	_new_panel.visible = false
	_settings.visible = false
	%Menu.visible = true
	%Slogan.visible = true
	if _completed_card != null:
		_completed_card.visible = true
	%NewGame.grab_focus()


func _open(panel: Control) -> void:
	Audio.play_ui("ui_click")
	%Menu.visible = false
	if _completed_card != null:
		_completed_card.visible = false
	panel.visible = true


func _on_new_game() -> void:
	_open(_new_panel)
	_overwrite.visible = Save.has_save()
	_seed_edit.grab_focus()


func _on_settings() -> void:
	_open(_settings)
	%Slogan.visible = false
	_settings.open()


func _on_language_changed() -> void:
	if get_tree().current_scene != self:
		return  # instanced by a test or tool: nothing to reload
	_reopen_settings = true
	get_tree().reload_current_scene.call_deferred()


func _on_seed_lab() -> void:
	Audio.play_ui("ui_click")
	Transition.go("seed_lab")


func _on_continue() -> void:
	if _starting:
		return
	if not GameState.load_saved():
		Audio.play_ui("ui_error")
		%Continue.disabled = true
		return
	_starting = true
	Audio.play_ui("ui_confirm")
	if GameState.is_memory():
		# A completed save opens only in Memory mode; a farewell not watched to the end plays first.
		Transition.go("farewell", {"mode": "memory" if Farewell.seen(GameState.data) else "play"})
		return
	GrannyTodo.ensure()
	Transition.go(Transition.home_scene())


## The save is closed (spec §7.12): Continue becomes Memory and a card under the menu says how long it lasted.
func _show_completed(days: int) -> void:
	%Continue.text = tr("UI_MEMORY_OPEN")
	var card := PanelContainer.new()
	card.theme_type_variation = &"PaperPanel"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := CenterContainer.new()
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.offset_top = 208
	row.offset_bottom = 238
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.add_child(card)
	var label := Label.new()
	label.theme_type_variation = &"PaperLabel"
	label.text = tr("UI_MEMORY_COMPLETED") % days
	card.add_child(label)
	_completed_card = row


## New Game: seed from the field (empty = random), fresh save, then the premise.
func _start() -> void:
	if _starting:
		return
	_starting = true
	Audio.play_ui("ui_confirm")
	var save_seed := SeedText.parse(_seed_edit.text)
	if save_seed < 0:
		save_seed = Seeds.random_save_seed()
	GameState.start_new(save_seed)
	_new_panel.visible = false
	var premise: Premise = (load(PREMISE) as PackedScene).instantiate()
	add_child(premise)
	premise.finished.connect(_after_premise, CONNECT_ONE_SHOT)


func _after_premise() -> void:
	GrannyTodo.ensure()
	Transition.go(Transition.home_scene())


func _unhandled_input(event: InputEvent) -> void:
	if _new_panel.visible and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		Audio.play_ui("ui_back")
		_show_menu()
