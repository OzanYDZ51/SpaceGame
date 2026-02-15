shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

// =============================================================================
// Lens Flare - Anamorphic streak + circular halo
// Billboard quad placed at the sun position. Fades based on viewing angle.
// =============================================================================

uniform vec3 flare_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float flare_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float streak_width : hint_range(0.0, 1.0) = 0.12;

void vertex() {
	// Billboard facing camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), MODELVIEW_MATRIX[2].xyz)), 0.0),
		vec4(vec3(0.0, 1.0, 0.0), 0.0),
		vec4(normalize(MODELVIEW_MATRIX[2].xyz), 0.0),
		MODELVIEW_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);

	// Central glow (soft circle)
	float core = exp(-dist * dist * 60.0);

	// Circular halo ring
	float ring_dist = abs(dist - 0.35);
	float halo = exp(-ring_dist * ring_dist * 800.0) * 0.3;

	// Anamorphic horizontal streak
	float streak = exp(-uv.y * uv.y / (streak_width * streak_width * 0.01)) *
	               exp(-uv.x * uv.x * 3.0) * 0.5;

	// Secondary ghost (smaller, off-center)
	vec2 ghost_uv = uv + vec2(0.12, 0.03);
	float ghost = exp(-dot(ghost_uv, ghost_uv) * 200.0) * 0.15;

	float total = (core + halo + streak + ghost) * flare_intensity;

	ALBEDO = flare_color * total;
	ALPHA = clamp(total, 0.0, 1.0);
}
