shader_type canvas_item;
// Full-screen retro filter: pixelate into `block`-sized cells and snap each to a palette.
// Put it on a ColorRect (anchors full rect, mouse_filter ignore) on a CanvasLayer above the game.
// Uses: photo filters, era transitions, "glitch" moments, pause screens.
// palette: Nx1 px texture (N <= 64), e.g. made with palette_png.py from a .hex file.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D palette : filter_nearest, repeat_disable;
uniform int block : hint_range(1, 8) = 2;
uniform bool dither = false;                         // 2x2 ordered dither before snapping (1-bit look)
uniform float strength : hint_range(0.0, 1.0) = 1.0; // tween this for transitions

void fragment() {
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	float bs = float(block);
	vec2 cell = floor(SCREEN_UV * screen_px / bs);
	vec3 col = texture(screen_tex, (cell * bs + bs * 0.5) / screen_px).rgb;
	if (dither) {
		int idx = int(mod(cell.x, 2.0)) + 2 * int(mod(cell.y, 2.0));
		float bayer[4] = float[4](0.0, 0.5, 0.75, 0.25);
		col += (bayer[idx] - 0.375) * 0.25;
	}
	int n = textureSize(palette, 0).x;
	vec3 best = col;
	float best_d = 1e9;
	for (int i = 0; i < 64; i++) {
		if (i >= n) {
			break;
		}
		vec3 p = texelFetch(palette, ivec2(i, 0), 0).rgb;
		vec3 d = col - p;
		float dd = dot(d, d);
		if (dd < best_d) {
			best_d = dd;
			best = p;
		}
	}
	COLOR = vec4(mix(texture(screen_tex, SCREEN_UV).rgb, best, strength), 1.0);
}
