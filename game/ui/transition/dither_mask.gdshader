shader_type canvas_item;
// FIRST-60 · Ordered-dither reveal for whole layers (intro beats, the world-grow overlay): a screen pixel is drawn
// only while its 4x4 Bayer threshold is below `level` (0 = hidden, 16 = whole). No alpha blending anywhere; the
// colours stay the drawn palette colours. Children share it with use_parent_material.

uniform int level : hint_range(0, 16) = 16;

const int BAYER[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);

void fragment() {
	int x = int(FRAGCOORD.x) % 4;
	int y = int(FRAGCOORD.y) % 4;
	if (BAYER[y * 4 + x] >= level) {
		discard;
	}
}
