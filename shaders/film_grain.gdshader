shader_type canvas_item;

// =============================================================================
// Film Grain - Subtle animated noise overlay that breaks color banding.
// Strength is slightly higher in dark areas (where banding is most visible).
// Force: 0.025 — barely perceptible, purely technical anti-banding.
// =============================================================================

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float grain_strength : hint_range(0.0, 0.1) = 0.025;
uniform float time_scale : hint_range(0.0, 10.0) = 1.0;

// Hash function for per-pixel noise
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;

	// Animated noise seeded by pixel position + time
	float t = TIME * time_scale;
	float noise = hash(SCREEN_UV * vec2(1920.0, 1080.0) + vec2(t * 37.7, t * 53.3));
	noise = noise * 2.0 - 1.0; // -1 to 1

	// Stronger grain in shadows (where banding is worst)
	float luminance = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float shadow_boost = mix(1.5, 0.8, smoothstep(0.0, 0.4, luminance));

	col += noise * grain_strength * shadow_boost;

	COLOR = vec4(col, 1.0);
}
