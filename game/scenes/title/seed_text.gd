class_name SeedText
extends RefCounted
## New Game seed field -> save seed (31 bit). Empty = -1 (caller draws Seeds.random_save_seed()).
## A number is used as-is (masked to 31 bits); any other text is hashed, so "granny" is a valid seed too.


static func parse(text: String) -> int:
	var t := text.strip_edges()
	if t == "":
		return -1
	if t.is_valid_int():
		return absi(t.to_int()) & 0x7FFFFFFF
	return Hash.fnv1a31(t.to_lower())
