shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 impact_direction = vec3(0.0, 0.0, -1.0);
uniform float effect_time = 0.0;
uniform float shield_health = 1.0;

varying vec3 local_normal;

void vertex() {
	local_normal = VERTEX;
}

void fragment() {
	vec3 n = normalize(local_normal);
	vec3 imp = normalize(impact_direction);

	// Angular distance from impact point (0 = hit, PI = opposite)
	float ang = acos(clamp(dot(n, imp), -1.0, 1.0));

	// Only render a curved cap around the impact (~70 degrees)
	// Smooth rounded edge falloff — no hard boundary
	float cap = smoothstep(1.25, 0.2, ang);
	if (cap < 0.001) discard;

	// Smooth fade in (appears gracefully, not a pop)
	float fade_in = smoothstep(0.0, 0.15, effect_time);

	// Overall fade out over duration
	float fade_out = max(0.0, 1.0 - effect_time * 1.5);

	// === Impact glow: concentrated at hit center ===
	float glow = exp(-ang * ang * 8.0) * max(0.0, 1.0 - effect_time * 2.5);

	// === Ripple ring 1 ===
	float r1 = effect_time * 2.5;
	float w1 = smoothstep(0.05, 0.0, abs(ang - r1)) * max(0.0, 1.0 - effect_time * 1.6);

	// === Ripple ring 2: delayed ===
	float r2 = max(0.0, effect_time - 0.08) * 2.0;
	float w2 = smoothstep(0.035, 0.0, abs(ang - r2)) * max(0.0, 1.0 - effect_time * 2.0) * 0.4;

	float alpha = (glow + w1 + w2) * cap * fade_in * fade_out;

	// Blue gradient: bright white-blue at impact center → deep blue at cap edge
	vec3 c_center = vec3(0.4, 0.65, 1.0);
	vec3 c_edge = vec3(0.03, 0.12, 0.65);
	float grad_t = smoothstep(0.0, 1.0, ang / 1.25);
	vec3 col = mix(c_center, c_edge, grad_t);

	// Shield health tint: shift toward warm red when depleted
	vec3 c_low = vec3(1.0, 0.18, 0.03);
	col = mix(c_low, col, clamp(shield_health, 0.0, 1.0));

	float emit = 0.5 + glow * 3.0 + (w1 + w2) * 1.5;

	ALBEDO = col;
	EMISSION = col * emit;
	ALPHA = clamp(alpha, 0.0, 0.38);
}
