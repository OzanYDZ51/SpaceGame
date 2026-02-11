shader_type spatial;
render_mode cull_disabled, shadows_disabled;

// =============================================================================
// Planetary Rings — Concentric bands with Cassini division, semi-transparent
// Flat disc in XZ plane, UV.x = radial position (0 = inner, 1 = outer)
// =============================================================================

uniform vec4 ring_color : source_color = vec4(0.8, 0.7, 0.5, 1.0);
uniform float ring_seed : hint_range(0.0, 1000.0) = 0.0;
uniform vec3 sun_direction = vec3(0.0, 0.3, -1.0);
uniform float ring_brightness : hint_range(0.5, 3.0) = 1.2;
uniform float cassini_position : hint_range(0.2, 0.8) = 0.45;
uniform float cassini_width : hint_range(0.01, 0.15) = 0.06;

varying float radial_pos;
varying vec3 world_pos;
varying vec3 world_normal;

// Simple 1D hash
float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract(p * (p + p));
}

// 1D noise
float noise1d(float p) {
	float i = floor(p);
	float f = fract(p);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), u);
}

// 1D FBM for ring bands
float ring_fbm(float p) {
	return noise1d(p) * 0.5
		 + noise1d(p * 2.0 + 5.3) * 0.25
		 + noise1d(p * 4.0 + 11.7) * 0.15
		 + noise1d(p * 8.0 + 23.1) * 0.10;
}

void vertex() {
	radial_pos = UV.x;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float r = radial_pos;
	float seed = ring_seed;

	// --- Band pattern (radial noise) ---
	float bands = ring_fbm(r * 30.0 + seed);
	float fine_bands = ring_fbm(r * 80.0 + seed * 2.3);
	float pattern = bands * 0.7 + fine_bands * 0.3;

	// --- Cassini division (gap) ---
	float cassini = smoothstep(cassini_position - cassini_width * 0.5, cassini_position - cassini_width * 0.1, r)
				  * (1.0 - smoothstep(cassini_position + cassini_width * 0.1, cassini_position + cassini_width * 0.5, r));
	float gap_opacity = 1.0 - cassini * 0.9;

	// --- Edge fade (rings thin at inner and outer edges) ---
	float edge_fade = smoothstep(0.0, 0.08, r) * smoothstep(1.0, 0.92, r);

	// --- Color variation per band ---
	vec3 color_a = ring_color.rgb * 1.1;
	vec3 color_b = ring_color.rgb * 0.7 + vec3(0.05, 0.04, 0.02);
	vec3 band_color = mix(color_a, color_b, smoothstep(0.3, 0.7, pattern));

	// --- Lighting: sun front + backlit (translucent) ---
	vec3 sun_dir = normalize(sun_direction);
	float ndotl = dot(world_normal, sun_dir);
	// Front-lit
	float front_light = max(ndotl, 0.0) * 0.7 + 0.3;
	// Back-lit (light passing through thin rings)
	float back_light = max(-ndotl, 0.0) * 0.4;
	float total_light = front_light + back_light;

	vec3 final_color = band_color * total_light * ring_brightness;

	// --- Alpha ---
	float density = pattern * 0.8 + 0.2;
	float alpha = density * gap_opacity * edge_fade * ring_color.a;

	ALBEDO = final_color;
	ALPHA = clamp(alpha, 0.0, 0.95);
}
