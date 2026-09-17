shader_type canvas_item;
render_mode particles;

// ── Desert sand particle shader ────────────────────────────────────
// Handles BOTH simulation and sprite-sheet rendering.
// Simulation: position, velocity, gravity, rotation, age tracking.
// Rendering: selects one 32×32 frame from a 7-frame horizontal sheet,
//            applies color-ramp fade-out.

uniform int h_frames = 7;
uniform float anim_speed = 1.0;

// Particle behavior
uniform vec3 direction = vec3(0.0, -1.0, 0.0);
uniform float spread = 200.0;
uniform vec3 gravity = vec3(0.0, -30.0, 0.0);
uniform float initial_velocity_min = 10.0;
uniform float initial_velocity_max = 35.0;
uniform float angular_velocity_min = -90.0;
uniform float angular_velocity_max = 90.0;
uniform float scale_min = 0.7;
uniform float scale_max = 1.3;
uniform float emission_radius = 8.0;

// Fade-out ramp
uniform sampler2D color_ramp : hint_default_white;

void vertex() {
	if (PROCESS_PARTICLES) {
		// ── SIMULATION PASS ─────────────────────────────────────
		bool fresh = LIFETIME > (LIFETIME_MAX - DELTA * 1.5);

		if (fresh) {
			float r1 = INSTANCE_CUSTOM.x;
			float r2 = INSTANCE_CUSTOM.y;
			float r3 = INSTANCE_CUSTOM.z;

			// Random position in emission sphere
			float a = r1 * 6.28318;
			float d = sqrt(r2) * emission_radius;
			TRANSFORM[3] = vec4(cos(a) * d, sin(a) * d, 0.0, 1.0);

			// Random direction within spread cone
			float sa = (r3 - 0.5) * radians(spread);
			float da = atan(direction.y, direction.x) + sa;
			vec2 dir = vec2(cos(da), sin(da));
			float spd = mix(initial_velocity_min, initial_velocity_max, r1);
			VELOCITY = vec3(dir * spd, 0.0);

			// Random rotation and scale
			float rot = r2 * 6.28318;
			float s = mix(scale_min, scale_max, r3);
			TRANSFORM[0] = vec4(cos(rot) * s, sin(rot) * s, 0.0, 0.0);
			TRANSFORM[1] = vec4(-sin(rot) * s, cos(rot) * s, 0.0, 0.0);
			TRANSFORM[2] = vec4(0.0, 0.0, s, 0.0);

			CUSTOM.x = mix(angular_velocity_min, angular_velocity_max, r1);
		} else {
			// Advance
			VELOCITY += gravity * DELTA;

			float rot = atan(TRANSFORM[0][1], TRANSFORM[0][0]) + CUSTOM.x * DELTA;
			float s = length(TRANSFORM[0].xyz);
			TRANSFORM[0] = vec4(cos(rot) * s, sin(rot) * s, 0.0, 0.0);
			TRANSFORM[1] = vec4(-sin(rot) * s, cos(rot) * s, 0.0, 0.0);

			TRANSFORM[3].xyz += VELOCITY * DELTA;
		}

		// Store normalized age (0→1) in CUSTOM.w for the render pass.
		// LIFETIME counts down from LIFETIME_MAX to 0.
		CUSTOM.w = 1.0 - LIFETIME / LIFETIME_MAX;

	} else {
		// ── RENDER PASS ─────────────────────────────────────────
		// Read age from CUSTOM.w (set during simulation).
		float progress = CUSTOM.w;

		// Sample fade-out color ramp
		COLOR = texture(color_ramp, vec2(clamp(progress, 0.0, 1.0), 0.0));

		// Select frame: shift UV.x into the correct 32px slice
		float fp = progress * float(h_frames) * anim_speed;
		int frame = int(mod(fp, float(h_frames)));
		UV.x = (UV.x + float(frame)) / float(h_frames);
	}
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
}
