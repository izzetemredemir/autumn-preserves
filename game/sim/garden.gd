class_name Garden
extends RefCounted
## SIM-04 · Garden actions (spec §5, §7.5, §8.1). Trees refill rules.garden.tree_refill_days after shaking.


static func shake_tree(_state: Dictionary, _tree_index: int) -> Dictionary:
	return {"ok": false}  # TODO SIM-04 · {"ok","reason","items"}


static func plant(_state: Dictionary, _bed_index: int, _crop: String, _use_fertilizer: bool = false) -> Dictionary:
	return {"ok": false}  # TODO SIM-04 · uses a "seed_<crop>" from the cupboard


static func harvest(_state: Dictionary, _bed_index: int) -> Dictionary:
	return {"ok": false}  # TODO SIM-04
