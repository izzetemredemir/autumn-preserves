class_name MiniGame
extends Node2D
## Mini-game contract (tech-spec §8). A mini-game never touches GameState; the host applies the result.
## ctx keys: "seed" (int), "recipe" (String), "varieties" (Array of variety ids), "addin" (String),
## "desc" (ProductGen.describe() of the variant being made), plus game-specific keys.

## result: {"stars": 1..3, ...game-specific extras}. Emit exactly once.
signal finished(result: Dictionary)


func start(_ctx: Dictionary) -> void:
	pass
