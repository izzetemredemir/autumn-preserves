class_name Seeds
extends RefCounted
## Seed streams (tech-spec §6): seed = fnv1a31("<save_seed>|<stream>|<day>|<sub>").
## Every stream gets its own RandomNumberGenerator, so changing draws in one never shifts another.


static func seed_for(save_seed: int, stream: String, day: int, sub: String = "") -> int:
	return Hash.fnv1a31("%d|%s|%d|%s" % [save_seed, stream, day, sub])


static func rng(save_seed: int, stream: String, day: int, sub: String = "") -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_for(save_seed, stream, day, sub)
	return r


## Index into `weights` (numbers, any scale), drawn from `r`.
static func pick_weighted(r: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var x := r.randf() * total
	for i in weights.size():
		x -= float(weights[i])
		if x < 0.0:
			return i
	return weights.size() - 1


static func random_save_seed() -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r.randi() & 0x7FFFFFFF
