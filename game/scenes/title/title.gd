extends Control
## Title (GD-META): name, slogan, Harvest Festival, New Game (with a seed field), Continue, Seed Lab, Settings.
## Harvest Festival (FESTIVAL, every build): the crafted showcase day as a temporary game (Festival.start).
## New Game -> premise (ui/premise) -> garden (kitchen until the garden exists). Continue loads the save; a save the
## farewell closed (spec §7.12) shows a "Completed" card and Continue becomes Memory (scenes/farewell, Memory mode).
## Also applies saved settings and adds the debug panel (F1) in debug builds. A language change in Settings reloads
## the title so every text is built again in the new language, with Settings open again (L10N-TR).

const MUSIC_DIR := "res://assets/audio/music/"
const MUSIC_FALLBACK := "res://assets/audio/music/candidates/mus_title_a.ogg"
const PREMISE := "res://ui/premise/premise.tscn"

var _new_panel: PanelContainer
var _seed_edit: LineEdit
var _seed_row: HBoxContainer
var _seed_link: Button
var _start_button: Button
var _lang_layer: Control
var _toggle: HBoxContainer
var _overwrite: Label
var _settings: SettingsPanel
var _fallback_music: AudioStreamPlayer
var _starting := false
var _completed_card: Control
## Set before the language reload: the rebuilt title opens Settings again.
static var _reopen_settings := false
## Tools that shoot or record the title set this so the first-launch language card stays out of the way.
static var skip_lang := false


func _ready() -> void:
	GameSettings.apply()
	DevPanel.ensure()
	_play_music()
	_build_new_game_panel()
	_build_lang_toggle()
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_show_menu)
	_settings.language_changed.connect(_on_language_changed)
	_center(_settings)
	%Festival.pressed.connect(_on_festival)
	_build_lab_hint()
	%Festival.disabled = not FileAccess.file_exists(FestivalFacts.SAVE)
	%NewGame.pressed.connect(_on_new_game)
	%Continue.pressed.connect(_on_continue)
	%SeedLab.pressed.connect(_on_seed_lab)
	%Settings.pressed.connect(_on_settings)
	%Continue.disabled = not Save.has_save()
	var saved := Save.load_game() if Save.has_save() else {}
	if Farewell.is_completed(saved):
		_show_completed(Farewell.completed_day(saved))
	%SeedLab.disabled = not Router.exists("seed_lab")
	%SeedLab.visible = false  # hidden from players (the human: it looks intimidating); L opens it for the talk
	if %Continue.disabled:
		%NewGame.grab_focus()
	else:
		%Continue.grab_focus()
	if _reopen_settings:
		_reopen_settings = false
		_on_settings()
	elif not skip_lang and get_tree().current_scene == self and not GameSettings.lang_chosen():
		_build_lang_picker()


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
	box.add_theme_constant_override("separation", 6)
	_new_panel.add_child(box)
	var head := Label.new()
	head.text = tr("TITLE_NEW_GAME")
	head.theme_type_variation = &"Heading"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var line := Label.new()
	line.text = tr("UI_NEWGAME_LINE")
	line.custom_minimum_size = Vector2(250, 0)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	_overwrite = Label.new()
	_overwrite.text = tr("TITLE_OVERWRITE")
	_overwrite.add_theme_color_override("font_color", Color("e19064"))
	_overwrite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_overwrite)
	_start_button = Button.new()
	_start_button.text = tr("TITLE_START")
	_start_button.custom_minimum_size = Vector2(0, 30)
	_start_button.pressed.connect(_start)
	box.add_child(_start_button)
	_seed_link = Button.new()
	_seed_link.text = tr("UI_NEWGAME_SEED_LINK")
	_seed_link.flat = true
	_seed_link.pressed.connect(func() -> void:
		Audio.play_ui("ui_click")
		_seed_link.visible = false
		_seed_row.visible = true
		_seed_edit.grab_focus())
	box.add_child(_seed_link)
	_seed_row = HBoxContainer.new()
	_seed_row.visible = false
	_seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_seed_row.add_theme_constant_override("separation", 6)
	box.add_child(_seed_row)
	var label := Label.new()
	label.text = tr("TITLE_SEED")
	_seed_row.add_child(label)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = tr("TITLE_SEED_RANDOM")
	_seed_edit.max_length = 16
	_seed_edit.custom_minimum_size = Vector2(120, 0)
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _start())
	_seed_row.add_child(_seed_edit)
	var back := Button.new()
	back.text = tr("UI_BACK")
	back.pressed.connect(func() -> void:
		Audio.play_ui("ui_back")
		_show_menu())
	box.add_child(back)


## ONBOARD-TITLE · First launch: a paper card with the two languages over the title art. The pick is stored and the
## title reloads in that language, so the intro plays in it. Left/Right move between the buttons, Enter picks.
func _build_lang_picker() -> void:
	_lang_layer = Control.new()
	_lang_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_lang_layer)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lang_layer.add_child(c)
	var card := PanelContainer.new()
	card.theme_type_variation = &"PaperPanel"
	c.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	for key: String in ["UI_LANG_CHOOSE_EN", "UI_LANG_CHOOSE_TR"]:
		var l := Label.new()
		l.theme_type_variation = &"PaperLabel"
		l.text = tr(key)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var first: Button = null
	for code: String in GameSettings.LANGUAGES:
		var b := Button.new()
		b.name = "Lang_" + code
		b.text = String(GameSettings.LANGUAGES[code])
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.custom_minimum_size = Vector2(110, 40)
		b.pressed.connect(_pick_language.bind(code))
		row.add_child(b)
		if first == null:
			first = b
	first.grab_focus()
	%Menu.visible = false
	%Slogan.visible = false
	_toggle.visible = false


func _pick_language(code: String) -> void:
	Audio.play_ui("ui_confirm")
	GameSettings.set_language(code)
	_reload()


## A small EN | TR switch in the top right corner: instant, the title is built again in the new language.
func _build_lang_toggle() -> void:
	_toggle = HBoxContainer.new()
	_toggle.name = "LangToggle"
	_toggle.add_theme_constant_override("separation", 0)
	for code: String in GameSettings.LANGUAGES:
		var b := Button.new()
		b.text = code.to_upper()
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = code == GameSettings.language()
		b.pressed.connect(func() -> void:
			if code == GameSettings.language():
				b.button_pressed = true
				return
			Audio.play_ui("ui_click")
			GameSettings.set_language(code)
			_reload())
		_toggle.add_child(b)
	add_child(_toggle)
	_toggle.position = Vector2(480 - 8 - _toggle.get_combined_minimum_size().x, 6)


func _reload() -> void:
	if get_tree().current_scene != self:
		return  # instanced by a test or tool: nothing to reload
	get_tree().reload_current_scene.call_deferred()


func _show_menu() -> void:
	_new_panel.visible = false
	_settings.visible = false
	_toggle.visible = true
	%Menu.visible = true
	%Slogan.visible = true
	if _completed_card != null:
		_completed_card.visible = true
	%NewGame.grab_focus()


func _open(panel: Control) -> void:
	Audio.play_ui("ui_click")
	%Menu.visible = false
	_toggle.visible = false
	if _completed_card != null:
		_completed_card.visible = false
	panel.visible = true


func _on_new_game() -> void:
	_open(_new_panel)
	%Slogan.visible = false
	_overwrite.visible = Save.has_save()
	_seed_row.visible = false
	_seed_link.visible = true
	_start_button.grab_focus()


func _on_settings() -> void:
	_open(_settings)
	%Slogan.visible = false
	_settings.open()


func _on_language_changed() -> void:
	if get_tree().current_scene != self:
		return
	_reopen_settings = true
	_reload()


## The Harvest Festival: never touches the player's save (a temporary game, see Festival).
func _on_festival() -> void:
	if _starting:
		return
	_starting = true
	Audio.play_ui("ui_confirm")
	if not Festival.start():
		_starting = false
		Audio.play_ui("ui_error")


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
	row.offset_top = 224
	row.offset_bottom = 254
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
	# The Forest Lab is a behind-the-scenes view for presenting, not part of the game: no menu button, the L key opens it.
	if %Menu.visible and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_L and Router.exists("seed_lab"):
		get_viewport().set_input_as_handled()
		_on_seed_lab()
		return
	if _new_panel.visible and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		Audio.play_ui("ui_back")
		_show_menu()


## "Watch a forest grow from any seed." under the menu while the Forest Lab button is hovered or focused.
func _build_lab_hint() -> void:
	var box := PanelContainer.new()
	box.name = "LabHint"
	box.theme_type_variation = &"DarkPanel"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	var hint := Label.new()
	hint.text = tr("TITLE_SEED_LAB_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)
	add_child(box)
	var place := func() -> void:
		var sz := box.get_combined_minimum_size()
		box.size = sz
		box.position = Vector2(floori((480 - sz.x) / 2.0), 236)
	place.call()
	var lab: Button = %SeedLab
	lab.tooltip_text = tr("TITLE_SEED_LAB_HINT")
	var show := func() -> void:
		box.visible = %Menu.visible and (lab.is_hovered() or lab.has_focus())
		place.call()
	for sig: Signal in [lab.mouse_entered, lab.mouse_exited, lab.focus_entered, lab.focus_exited]:
		sig.connect(show)
