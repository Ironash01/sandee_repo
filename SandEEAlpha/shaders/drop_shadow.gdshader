shader_type canvas_item;

// Pixel offset of the shadow relative to the sprite (positive = right / down).
uniform float shadow_x : hint_range(-24.0, 24.0) = 7.0;
uniform float shadow_y : hint_range(-24.0, 24.0) = 4.0;
// How dark / transparent the shadow is (0 = invisible, 1 = fully black).
uniform float shadow_alpha : hint_range(0.0, 1.0) = 0.35;

void fragment() {
    // TEXTURE_PIXEL_SIZE is 1/textureSize — converts pixel offset to UV offset.
    vec2 shadow_uv = UV - vec2(shadow_x, shadow_y) * TEXTURE_PIXEL_SIZE;

    vec4 col  = texture(TEXTURE, UV);
    vec4 shad = texture(TEXTURE, shadow_uv);

    // Shadow is a semi-transparent black, composited underneath the real sprite.
    vec4 shadow_col = vec4(0.0, 0.0, 0.0, shad.a * shadow_alpha);
    COLOR = mix(shadow_col, col, col.a);
}
