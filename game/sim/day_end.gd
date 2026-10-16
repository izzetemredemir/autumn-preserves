class_name DayEnd
extends RefCounted
## SIM-04 · Night pipeline, the 11 steps of spec §9, in order. Mutates state; returns events
## [{"type": "matured"|"spoiled"|"grown"|"order_new"|"weather"|...,  ...}] for the morning summary.


static func run(_state: Dictionary) -> Array:
	return []  # TODO SIM-04
