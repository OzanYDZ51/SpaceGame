shader_type canvas_item;

// =============================================================================
// Damage Overlay — Red vignette flash + directional hit indicator
// Driven by DamageScreenEffect script via uniforms.
// =============================================================================

uniform float damage_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float hit_angle : hint_range(-3.14159, 3.14159) = 0.0;
uniform float hit_intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 center = UV - 0.5;
	float dist = length(center);

	// --- Red damage vignette (pulsing from edges) ---
	float vignette = smoothstep(0.15, 0.75, dist);
	float damage = vignette * damage_intensity;

	// --- Directional hit indicator (bright arc at screen edge toward attacker) ---
	float angle = atan(center.y, center.x);
	float angle_diff = mod(angle - hit_angle + PI, TAU) - PI;
	float dir_arc = smoothstep(0.5, 0.0, abs(angle_diff)) * smoothstep(0.25, 0.65, dist);
	float dir = dir_arc * hit_intensity;

	// Combine: red vignette + brighter directional arc
	float alpha = max(damage * 0.8, dir * 0.95);
	vec3 col = vec3(0.75, 0.04, 0.0);

	// Directional arc is brighter/whiter for visibility
	vec3 dir_col = vec3(1.0, 0.15, 0.05);
	col = mix(col, dir_col, clamp(dir * 1.5, 0.0, 1.0));

	COLOR = vec4(col, alpha);
}
