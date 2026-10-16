shader_type canvas_item;
// 1-px outline around the sprite's alpha: hover/selection highlight for interactable objects.
// The texture needs >=1 px transparent padding on every side (or the outline gets clipped).

uniform vec4 outline_color : source_color = vec4(1.0, 0.773, 0.420, 1.0); // #ffc56b
uniform bool enabled = false;
uniform bool diagonal = false; // also check corners (thicker look)

varying vec4 vertex_modulate;

void vertex() {
	vertex_modulate = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (enabled && c.a < 0.5) {
		vec2 p = TEXTURE_PIXEL_SIZE;
		float a = texture(TEXTURE, UV + vec2(p.x, 0.0)).a + texture(TEXTURE, UV - vec2(p.x, 0.0)).a
			+ texture(TEXTURE, UV + vec2(0.0, p.y)).a + texture(TEXTURE, UV - vec2(0.0, p.y)).a;
		if (diagonal) {
			a += texture(TEXTURE, UV + p).a + texture(TEXTURE, UV - p).a
				+ texture(TEXTURE, UV + vec2(p.x, -p.y)).a + texture(TEXTURE, UV + vec2(-p.x, p.y)).a;
		}
		if (a > 0.0) {
			c = outline_color;
		}
	}
	COLOR = c * vertex_modulate;
}
