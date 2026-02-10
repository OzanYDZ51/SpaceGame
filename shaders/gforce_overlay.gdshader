shader_type canvas_item;

// =============================================================================
// G-Force Overlay - Blackout (positive G) / Redout (negative G) vignette
// Intensity driven by GForceEffects script via uniform.
// =============================================================================

uniform float blackout_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float redout_intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 center = UV - 0.5;
	float dist = length(center);

	// Vignette shape: stronger at edges, clear center
	float vignette = smoothstep(0.2, 0.85, dist);

	// Blackout: dark tunnel vision from edges (positive G / hard turns)
	float black = vignette * blackout_intensity;
	vec3 black_col = vec3(0.0);

	// Redout: red tint from edges (negative G / sudden deceleration)
	float red = vignette * redout_intensity;
	vec3 red_col = vec3(0.6, 0.02, 0.0) * red;

	// Combine: darken + red tint
	float alpha = max(black * 0.9, red * 0.7);
	vec3 col = mix(black_col, red_col, step(black, red));

	COLOR = vec4(col, alpha);
}
