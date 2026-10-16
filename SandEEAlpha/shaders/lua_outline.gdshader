shader_type canvas_item;

// Glowing outline around the Lua robot (now a floating entity). Pixels just
// OUTSIDE the sprite's silhouette are filled with a bright cyan; the overworld
// WorldEnvironment glow (HDR threshold 1.25) then blooms that into a soft halo.
// Sampling the sprite's own texture means the outline tracks whatever
// direction frame is showing, with no second node to keep in sync.

uniform vec4 glow_color : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform float thickness : hint_range(0.0, 4.0) = 1.4;
// Multiplier pushes the halo above 1.0 so the glow threshold catches it.
uniform float brightness : hint_range(1.0, 4.0) = 2.2;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (base.a > 0.15) {
		COLOR = base;
		return;
	}
	float a = 0.0;
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			if (i == 0 && j == 0) {
				continue;
			}
			vec2 off = vec2(float(i), float(j)) * TEXTURE_PIXEL_SIZE * thickness;
			a = max(a, texture(TEXTURE, UV + off).a);
		}
	}
	COLOR = vec4(glow_color.rgb * brightness, a);
}
