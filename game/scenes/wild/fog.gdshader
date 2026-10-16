shader_type canvas_item;
// Foggy wild (CALENDAR-WEATHER): a palette fog closing in around Granny with a 4x4 ordered dither. Every pixel is either
// exactly fog_color or untouched (discard): no partial alpha, no blending. The dither is anchored to world pixels so the
// pattern stays put on the ground while the camera moves.

uniform vec4 fog_color = vec4(0.949, 0.851, 0.773, 1.0);  // f2d9c5
uniform vec2 rect_size = vec2(480.0, 270.0);
uniform vec2 center = vec2(240.0, 135.0);  // Granny on screen, viewport pixels
uniform vec2 anchor = vec2(0.0);  // world pixel under the screen's top-left corner
uniform float clear_r = 80.0;  // fully clear inside this radius
uniform float full_r = 200.0;  // densest from this radius on
uniform float max_level = 10.0;  // densest dither level, of 16: the far wild still shows through

const int BAYER[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);

void fragment() {
	vec2 px = floor(UV * rect_size);
	float t = clamp((distance(px + 0.5, center) - clear_r) / (full_r - clear_r), 0.0, 1.0);
	float level = floor(t * max_level + 0.5);
	ivec2 q = ivec2(mod(px + anchor, 4.0));
	if (float(BAYER[q.y * 4 + q.x]) >= level) {
		discard;
	}
	COLOR = fog_color;
}
