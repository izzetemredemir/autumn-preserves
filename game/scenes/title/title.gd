extends Control
## Placeholder title (CORE-01). GD-META replaces it with the real title, premise and New Game flow.


func _ready() -> void:
	%NewGame.pressed.connect(_on_new_game)
	%SeedLab.pressed.connect(func() -> void: Router.goto("seed_lab"))
	%Continue.disabled = not Save.has_save()
	%Continue.pressed.connect(func() -> void:
		if GameState.load_saved():
			Router.goto("garden"))


func _on_new_game() -> void:
	GameState.start_new(Seeds.random_save_seed())
	Router.goto("garden")
