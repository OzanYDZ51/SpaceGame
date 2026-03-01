shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 impact_point = vec3(0.0, 0.0, -1.0);
uniform float effect_time = 0.0;
uniform float shield_health = 1.0;
uniform float max_radius = 10.0;

varying vec3 frag_pos;
varying vec3 model_normal;

void vertex() {
	frag_pos = VERTEX;
	model_normal = NORMAL;
}

// Hexagonal SDF
float hex_dist(vec2 p) {
	p = abs(p);
	return max(p.x * 0.866025 + p.y * 0.5, p.y);
}

// Hexagonal grid — returns distance to nearest hex cell edge
float hex_grid(vec2 p, float s) {
	p *= s;
	vec2 r = vec2(1.0, 1.732051);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p + h, r) - h;
	vec2 g = (dot(a, a) < dot(b, b)) ? a : b;
	return hex_dist(g);
}

void fragment() {
	float dist = distance(frag_pos, impact_point);
	float norm_dist = dist / max_radius;

	float fade_in = smoothstep(0.0, 0.08, effect_time);
	float fade_out = max(0.0, 1.0 - effect_time * 0.8);

	// === Hex grid pattern (triplanar mapping for 3D mesh) ===
	float hs = 5.0 / max(max_radius, 1.0);
	vec3 blend = abs(model_normal);
	blend /= (blend.x + blend.y + blend.z + 0.001);
	float hex = hex_grid(frag_pos.yz, hs) * blend.x
	          + hex_grid(frag_pos.xz, hs) * blend.y
	          + hex_grid(frag_pos.xy, hs) * blend.z;
	float hex_edge = smoothstep(0.47, 0.39, hex);

	// Hex visibility: strong near impact, subtle across entire shield
	float hex_near = smoothstep(0.9, 0.0, norm_dist) * 0.55;
	float hex_far = 0.06;
	float hex_alpha = hex_edge * (hex_near + hex_far);

	// === Impact glow: bright concentrated flash at hit point ===
	float glow = exp(-norm_dist * norm_dist * 18.0) * max(0.0, 1.0 - effect_time * 1.8);

	// === 3 ripple rings expanding outward across the whole shield ===
	float r1 = effect_time * 1.5;
	float w1 = smoothstep(0.06, 0.0, abs(norm_dist - r1)) * max(0.0, 1.0 - effect_time * 0.85);

	float r2 = max(0.0, effect_time - 0.08) * 1.15;
	float w2 = smoothstep(0.045, 0.0, abs(norm_dist - r2)) * max(0.0, 1.0 - effect_time * 1.0) * 0.6;

	float r3 = max(0.0, effect_time - 0.18) * 0.9;
	float w3 = smoothstep(0.03, 0.0, abs(norm_dist - r3)) * max(0.0, 1.0 - effect_time * 1.3) * 0.35;

	// Ripples light up hex cells they pass through
	float ripple_hex = (w1 + w2 + w3) * hex_edge * 0.9;

	// === Fresnel edge glow across ENTIRE shield ===
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float edge_glow = fresnel * 0.22;

	// === Ambient whole-shield flash (brief bright then subtle) ===
	float ambient = 0.05 * max(0.0, 1.0 - effect_time * 1.0);

	float alpha = (glow + w1 + w2 + w3 + edge_glow + hex_alpha + ripple_hex + ambient) * fade_in * fade_out;

	// Discard only truly invisible fragments
	if (alpha < 0.001) discard;

	// Blue gradient: bright white-blue at center, deep blue at edges
	vec3 c_center = vec3(0.55, 0.8, 1.0);
	vec3 c_edge = vec3(0.06, 0.18, 0.75);
	float grad_t = smoothstep(0.0, 1.0, norm_dist);
	vec3 col = mix(c_center, c_edge, grad_t);

	// Shield health tint: shift toward orange-red when depleted
	vec3 c_low = vec3(1.0, 0.2, 0.05);
	col = mix(c_low, col, clamp(shield_health, 0.0, 1.0));

	// Hex edges tinted slightly brighter near impact
	col = mix(col, vec3(0.7, 0.9, 1.0), hex_edge * hex_near * 0.4);

	float emit = 0.6 + glow * 5.0 + (w1 + w2 + w3) * 2.5 + edge_glow * 2.0 + hex_alpha * 2.0 + ripple_hex * 3.0;

	ALBEDO = col;
	EMISSION = col * emit;
	ALPHA = clamp(alpha, 0.0, 0.55);
}
