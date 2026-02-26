shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 impact_point = vec3(0.0, 0.0, -1.0);
uniform float effect_time = 0.0;
uniform float shield_health = 1.0;
uniform float max_radius = 10.0;

varying vec3 frag_pos;

void vertex() {
	frag_pos = VERTEX;
}

void fragment() {
	// Euclidean distance from fragment to impact point, normalized by max_radius
	float dist = distance(frag_pos, impact_point);
	float norm_dist = dist / max_radius;

	// Only render a region around the impact (~40% of max_radius)
	float cap = smoothstep(0.4, 0.05, norm_dist);
	if (cap < 0.001) discard;

	// Smooth fade in
	float fade_in = smoothstep(0.0, 0.15, effect_time);

	// Overall fade out over duration
	float fade_out = max(0.0, 1.0 - effect_time * 1.5);

	// === Impact glow: concentrated at hit center ===
	float glow = exp(-norm_dist * norm_dist * 80.0) * max(0.0, 1.0 - effect_time * 2.5);

	// === Ripple ring 1 ===
	float r1 = effect_time * 0.8;
	float w1 = smoothstep(0.03, 0.0, abs(norm_dist - r1)) * max(0.0, 1.0 - effect_time * 1.6);

	// === Ripple ring 2: delayed ===
	float r2 = max(0.0, effect_time - 0.08) * 0.65;
	float w2 = smoothstep(0.02, 0.0, abs(norm_dist - r2)) * max(0.0, 1.0 - effect_time * 2.0) * 0.4;

	// === Fresnel edge glow at cap boundary ===
	// NORMAL and VIEW are both in view space in fragment()
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	float edge_glow = fresnel * cap * fade_in * fade_out * 0.15;

	float alpha = (glow + w1 + w2 + edge_glow) * cap * fade_in * fade_out;

	// Blue gradient: bright white-blue at impact center -> deep blue at cap edge
	vec3 c_center = vec3(0.4, 0.65, 1.0);
	vec3 c_edge = vec3(0.03, 0.12, 0.65);
	float grad_t = smoothstep(0.0, 1.0, norm_dist / 0.4);
	vec3 col = mix(c_center, c_edge, grad_t);

	// Shield health tint: shift toward warm red when depleted
	vec3 c_low = vec3(1.0, 0.18, 0.03);
	col = mix(c_low, col, clamp(shield_health, 0.0, 1.0));

	float emit = 0.5 + glow * 3.0 + (w1 + w2) * 1.5 + edge_glow * 2.0;

	ALBEDO = col;
	EMISSION = col * emit;
	ALPHA = clamp(alpha, 0.0, 0.38);
}
