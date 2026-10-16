class_name Hash
extends RefCounted
## FNV-1a 32-bit over UTF-8, masked to 31 bits: exact in JSON (float64) and safe as an RNG seed.


static func fnv1a31(text: String) -> int:
	var h: int = 2166136261
	for b in text.to_utf8_buffer():
		h = h ^ b
		h = (h * 16777619) & 0xFFFFFFFF
	return h & 0x7FFFFFFF
