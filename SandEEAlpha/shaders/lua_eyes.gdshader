shader_type canvas_item;

// Eye-only glow for the Lua robot. The sprite art already contains readable
// eye pixels in the front frames (blue normally, red in combat mode); this
// shader lifts those pixels above the world glow threshold and adds a small
// halo only inside the opaque face. It deliberately does not draw an outline
// around the silhouette.

uniform float brightness : hint_range(1.0, 4.0) = 2.8;
uniform float halo_strength : hint_range(0.0, 2.0) = 0.55;
uniform float halo_radius : hint_range(0.0, 3.0) = 2.0;
uniform float pulse_speed : hint_range(0.0, 6.0) = 1.5;
uniform float pulse_amount : hint_range(0.0, 0.4) = 0.05;

// Returns 1 for the two eye pixels in the 28x52 front frames, 0 elsewhere.
// The face-row/column limits keep the identically coloured antenna and chest
// accents dark. Back and side frames do not show eyes in the source art.
float eye_mask_pixel(vec4 c, vec2 pixel, vec2 tex_size) {
	if (tex_size.y < 50.5) {
		return 0.0;
	}
	if (pixel.x < 10.0 || pixel.x > 18.0 || pixel.y < 22.0 || pixel.y > 27.0) {
		return 0.0;
	}
	if (c.a < 0.5) {
		return 0.0;
	}
	// Blue eye (normal) and red eye (combat) are much more saturated than the
	// surrounding armour, so compare channel ratios rather than fixed values.
	float blue_eye = step(0.52, c.b)
		* step(1.55, c.b / max(c.r, 0.05))
		* step(1.45, c.b / max(c.g, 0.05));
	float red_eye = step(0.52, c.r)
		* step(1.55, c.r / max(c.g, 0.05))
		* step(1.55, c.r / max(c.b, 0.05));
	return max(blue_eye, red_eye);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec2 tex_size = 1.0 / texel;
	if (base.a < 0.01) {
		COLOR = base;
	} else {
		bool combat = base.r > base.g * 1.20 && base.r > base.b * 1.20;
		vec3 glow_tint = combat ? vec3(1.0, 0.28, 0.22) : vec3(0.34, 0.86, 1.0);
		float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;

		float eye = eye_mask_pixel(base, UV * tex_size, tex_size);
		if (eye > 0.5) {
			COLOR = vec4(glow_tint * brightness * pulse, 1.0);
		} else {
			// Soft local halo, accumulated only over existing opaque face pixels.
			float halo = 0.0;
			for (int i = -2; i <= 2; i++) {
				for (int j = -2; j <= 2; j++) {
					if (i == 0 && j == 0) {
						continue;
					}
					vec2 off = vec2(float(i), float(j)) * texel * halo_radius * 0.5;
					vec2 sample_pixel = (UV + off) * tex_size;
					vec4 sample_color = texture(TEXTURE, UV + off);
					float d = length(vec2(float(i), float(j)));
					halo = max(halo, eye_mask_pixel(sample_color, sample_pixel, tex_size) / d);
				}
			}
			halo = clamp(halo * halo_strength, 0.0, 1.0);
			COLOR = vec4(base.rgb + glow_tint * halo * 1.25, base.a);
		}
	}
}
