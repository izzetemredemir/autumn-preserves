shader_type canvas_item;
// Recolor a value-map sprite and render it in a retro "era" — one sprite, many looks.
// Value map = 5 grays: 0 (#000) outline, 64/128/192/255 tones 0..3 (dark, mid, light, highlight).
// era: 0 bit1 (2 colors, dithered shadow) · 1 tone4 (4 greens) · 2 bit8 (outline + 2 ramp tones)
//      3 bit16 (full ramp) · 4 holo (bit16 + scrolling iridescent bands)
// Low eras use an outline-preserving 2x downsample (block opaque if >=2 of 4 texels; border -> outline).
// Sprite sheets: give each frame >=1 px transparent padding so neighbours don't bleed.

uniform sampler2D ramp : filter_nearest, repeat_disable;          // 4x1 px: dark, mid, light, highlight
uniform int era : hint_range(0, 4) = 3;
uniform vec4 outline_color : source_color = vec4(0.051, 0.043, 0.102, 1.0); // #0d0b1a
uniform vec4 paper_color : source_color = vec4(0.957, 0.925, 0.875, 1.0);   // #f4ecdf
uniform vec4 tone4_0 : source_color = vec4(0.059, 0.220, 0.059, 1.0);       // #0f380f
uniform vec4 tone4_1 : source_color = vec4(0.188, 0.384, 0.188, 1.0);       // #306230
uniform vec4 tone4_2 : source_color = vec4(0.545, 0.675, 0.059, 1.0);       // #8bac0f
uniform vec4 tone4_3 : source_color = vec4(0.608, 0.737, 0.059, 1.0);       // #9bbc0f
uniform sampler2D holo_bands : filter_nearest, repeat_enable;     // Nx1 px band colors
uniform bool use_holo_bands = false;
uniform float holo_rows_per_sec = 6.0;
uniform vec4 flash_color : source_color = vec4(1.0);              // juice: hit/select flash
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

varying vec4 vertex_modulate;

void vertex() {
	vertex_modulate = COLOR; // node modulate/self_modulate; lost in fragment() otherwise
}

int tone_of(float v) {
	return int(round(v * 4.0)) - 1; // -1 outline, 0..3 tones
}

// Built-ins like TEXTURE are only visible inside fragment(); helpers take the sampler as a parameter.
float block_cover(sampler2D tex, vec2 block, vec2 ts) {
	float c = 0.0;
	for (int dy = 0; dy < 2; dy++) {
		for (int dx = 0; dx < 2; dx++) {
			vec2 t = block * 2.0 + vec2(float(dx), float(dy));
			if (t.x < 0.0 || t.y < 0.0 || t.x >= ts.x || t.y >= ts.y) {
				continue;
			}
			c += step(0.5, texelFetch(tex, ivec2(t), 0).a);
		}
	}
	return c;
}

void fragment() {
	vec2 ts = vec2(textureSize(TEXTURE, 0));
	ivec2 tx = ivec2(floor(UV * ts));
	bool opaque;
	int t;
	if (era >= 3) {
		vec4 src = texelFetch(TEXTURE, tx, 0);
		opaque = src.a > 0.5;
		t = tone_of(src.r);
	} else {
		vec2 b = floor(vec2(tx) / 2.0);
		opaque = block_cover(TEXTURE, b, ts) >= 2.0;
		bool edge = block_cover(TEXTURE, b + vec2(1.0, 0.0), ts) < 2.0 || block_cover(TEXTURE, b - vec2(1.0, 0.0), ts) < 2.0
			|| block_cover(TEXTURE, b + vec2(0.0, 1.0), ts) < 2.0 || block_cover(TEXTURE, b - vec2(0.0, 1.0), ts) < 2.0;
		float sum = 0.0;
		float n = 0.0;
		for (int dy = 0; dy < 2; dy++) {
			for (int dx = 0; dx < 2; dx++) {
				vec4 s = texelFetch(TEXTURE, ivec2(b * 2.0) + ivec2(dx, dy), 0);
				int st = tone_of(s.r);
				if (s.a > 0.5 && st >= 0) {
					sum += float(st);
					n += 1.0;
				}
			}
		}
		t = (edge || n == 0.0) ? -1 : int(round(sum / n));
	}

	if (!opaque) {
		COLOR = vec4(0.0);
	} else {
		vec4 c;
		if (era == 0) {
			vec2 b = floor(vec2(tx) / 2.0);
			bool checker = mod(b.x + b.y, 2.0) < 1.0;
			c = t < 0 ? outline_color : (t == 0 ? (checker ? outline_color : paper_color) : paper_color);
		} else if (era == 1) {
			c = t < 0 ? tone4_0 : (t == 0 ? tone4_1 : (t == 1 ? tone4_2 : tone4_3));
		} else if (era == 2) {
			c = t < 0 ? outline_color : texelFetch(ramp, ivec2(t <= 1 ? 1 : 2, 0), 0);
		} else {
			c = t < 0 ? outline_color : texelFetch(ramp, ivec2(clamp(t, 0, 3), 0), 0);
			if (era == 4 && t >= 1) {
				float row = floor((float(tx.y) + TIME * holo_rows_per_sec) / 3.0);
				vec4 band = vec4(0.604, 0.941, 0.878, 1.0); // #9af0e0
				if (use_holo_bands) {
					int nb = textureSize(holo_bands, 0).x;
					band = texelFetch(holo_bands, ivec2(int(mod(row, float(nb))), 0), 0);
				}
				c = mix(c, band, 0.5);
			}
		}
		c.rgb = mix(c.rgb, flash_color.rgb, flash_amount);
		COLOR = vec4(c.rgb, 1.0) * vertex_modulate;
	}
}
