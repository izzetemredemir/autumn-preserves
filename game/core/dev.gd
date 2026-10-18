class_name Dev
extends RefCounted
## RELEASE-CLEAN · The one place that decides "development tools visible?". True when the project runs in the editor
## binary (smokes, tests, demos, recordings) or when `--dev` is among the user arguments (`AutumnPreserves --dev`).
## Exported apps are clean even with a debug template. Scripted demos (`--demo`) count as dev.
## `--release-ui` (editor binary only) forces false, so smokes can shoot the player's view.


static func enabled() -> bool:
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("editor") and args.has("--release-ui"):
		return false
	return OS.has_feature("editor") or args.has("--dev") or args.has("--demo")
