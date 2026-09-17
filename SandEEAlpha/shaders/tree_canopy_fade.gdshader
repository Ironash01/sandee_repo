shader_type canvas_item;

// Fades the tree LEAVES to translucent while the player is hidden behind
// them (see world.gd _update_tree_fade), leaving the trunk fully opaque.
//
// The tree art is a single texture whose vertical middle sits on the trunk
// base (Sprite2D offset in world.gd _spawn_tree), so in texture space
// UV.y=0 is the canopy top and UV.y=1 is the trunk bottom. A smoothstep
// mask keeps the lower band (the trunk) opaque and fades only the top band
// (the leaves). fade is driven from code; the mask stays in the shader so
// no per-node bookkeeping or re-anchoring is needed.
uniform float fade : hint_range(0.0, 1.0) = 0.0;

// Normalised trunk line in UV.y — everything ABOVE this (smaller UV.y value)
// is leaves; everything below (larger UV.y) is trunk. The tree sprite is
// centered on the trunk base (offset in world.gd _spawn_tree), so the base
// sits at UV.y ~0.5 and the visible trunk occupies ~0.5..0.7; the leaves are
// the top band at UV.y below ~0.5.
uniform float trunk_uv_y : hint_range(0.0, 1.0) = 0.60;

void fragment() {
	// 1.0 over the leaves (UV.y below the trunk line), 0.0 over the trunk.
	float leaf_mask = 1.0 - smoothstep(trunk_uv_y - 0.10, trunk_uv_y, UV.y);
	// Fade only the leaves; alpha fades toward the trunk's own alpha scaled.
	float a = mix(COLOR.a, COLOR.a * (1.0 - fade), leaf_mask);
	COLOR = vec4(COLOR.rgb, a);
}
