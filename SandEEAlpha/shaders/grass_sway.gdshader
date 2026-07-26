shader_type canvas_item;

// Wind sway as a GPU vertex shear — costs nothing per instance, so density
// doesn't cost animation CPU time the way per-node AnimatedSprite2D did.
uniform float sway_speed  : hint_range(0.0, 5.0)  = 1.6;
uniform float sway_amount : hint_range(0.0, 30.0) = 4.0;
uniform float sway_freq   : hint_range(0.0, 1.0)  = 0.08;

// Ruffle — grass leans + trembles away from the player when they're close.
// player_pos is written once per frame onto this one shared material (see
// world.gd _process), not per grass instance — a single CPU write regardless
// of how many tufts exist; every instance reads it here on the GPU for free.
uniform vec2  player_pos                           = vec2(0.0, -100000.0);
// Kept tight (close to the player's own footprint, ~1 tile) — a wide radius
// meant many overlapping tufts reacted at once, each recalculating its own
// lean direction toward the player every frame as they moved, which read as
// a chaotic "wobble" instead of a localized contact reaction.
uniform float push_radius : hint_range(0.0, 300.0) = 28.0;
uniform float push_amount : hint_range(0.0, 150.0) = 42.0;
uniform float shake_speed : hint_range(0.0, 40.0)  = 20.0;
uniform float shake_amount : hint_range(0.0, 30.0) = 5.0;

// Per-instance anchor position, set once at spawn (see world.gd
// _spawn_grass_at → set_instance_shader_parameter). Falloff MUST be measured
// from this, not from each vertex's own world position: the top two vertices
// (which carry all the bend weight below) sit ~half the sprite's height above
// the tuft's own anchor, so measuring distance per-vertex left them outside
// push_radius even when the player was standing right on top of the tuft —
// that mismatch is why the effect was barely perceptible before.
instance uniform vec2 root_pos = vec2(0.0, 0.0);

void vertex() {
	float phase = root_pos.x * sway_freq + root_pos.y * sway_freq * 0.5;
	// UV.y is 0 at the top of the sprite (blades) and 1 at the bottom (roots) —
	// bend increases toward the top so the base stays anchored to the ground.
	float top_weight = 1.0 - UV.y;
	vec2 offset = vec2(sin(TIME * sway_speed + phase) * sway_amount * top_weight, 0.0);

	// Ease-out falloff from the tuft's own root, strongest at 0 distance.
	float dist   = distance(root_pos, player_pos);
	float push_t = clamp(1.0 - dist / max(push_radius, 0.001), 0.0, 1.0);
	push_t *= push_t;
	vec2 away_dir = dist > 0.001 ? normalize(root_pos - player_pos) : vec2(1.0, 0.0);

	// Lean away, plus a fast small tremble layered on top so it reads as a
	// startled shake rather than just a slow static bend.
	float shake = sin(TIME * shake_speed + root_pos.x * 0.6) * shake_amount;
	offset += away_dir * push_amount * push_t * top_weight;
	offset.x += shake * push_t * top_weight;

	VERTEX += offset;
}
