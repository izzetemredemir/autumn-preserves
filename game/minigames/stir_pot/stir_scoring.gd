class_name StirScoring
extends RefCounted
## Pure helpers for the stir_pot mini-game (unit-tested in tests/test_mg_stir.gd).

const BAND_LO := 0.38
const BAND_HI := 0.62
const RISE := 0.10  ## needle rise per second without stirring
const FALL := 0.30  ## needle fall per second at stir speed 1.0
const STAR2 := 0.5
const STAR3 := 0.85


## Pure scoring: bar is a fraction 0..1. Below 50% = 1 star, 50-85% = 2, 85%+ = 3.
static func stars_for_bar(b: float) -> int:
	if b >= STAR3:
		return 3
	if b >= STAR2:
		return 2
	return 1


## Pure needle step: rises when idle, falls with stir speed, plus a wobble. Result clamped to 0..1.
static func needle_step(n: float, speed: float, wobble: float, dt: float) -> float:
	return clampf(n + (RISE - FALL * speed) * dt + wobble * dt, 0.0, 1.0)


static func in_band(n: float) -> bool:
	return n >= BAND_LO and n <= BAND_HI
