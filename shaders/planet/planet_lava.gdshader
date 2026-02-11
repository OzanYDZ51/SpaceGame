shader_type spatial;
render_mode cull_back, unshaded;

// =============================================================================
// Planet Lava — Animated lava surface with emissive glow
// Sphere mesh at planet_radius * (1 + lava_level), scrolling magma texture.
// =============================================================================

uniform vec4 lava_color_hot : source_color = vec4(1.0, 0.6, 0.1, 1.0);
uniform vec4 lava_color_cool : source_color = vec4(0.6, 0.15, 0.02, 1.0);
uniform vec4 lava_color_crust : source_color = vec4(0.12, 0.06, 0.03, 1.0);
uniform float flow_speed : hint_range(0.0, 1.0) = 0.15;
uniform float flow_scale : hint_range(0.0001, 0.01) = 0.003;
uniform float emission_energy : hint_range(0.0, 10.0) = 3.0;
uniform float crust_threshold : hint_range(0.0, 1.0) = 0.4;

varying vec3 v_world_pos;

// Simple noise via sin mixing (no texture dependency)
float lava_noise(vec2 p) {
	return sin(p.x * 3.7 + sin(p.y * 2.1)) * 0.5 +
	       sin(p.y * 4.3 + sin(p.x * 1.9)) * 0.3 +
	       sin((p.x + p.y) * 5.1) * 0.2;
}

void vertex() {
	v_world_pos = VERTEX;
}

void fragment() {
	// Flow UV based on world position
	float t = TIME * flow_speed;
	vec2 flow_uv1 = v_world_pos.xz * flow_scale * 1000.0 + vec2(t * 0.3, t * 0.2);
	vec2 flow_uv2 = v_world_pos.xz * flow_scale * 700.0 - vec2(t * 0.15, -t * 0.25);

	// Dual-layer lava noise
	float n1 = lava_noise(flow_uv1) * 0.5 + 0.5;
	float n2 = lava_noise(flow_uv2) * 0.5 + 0.5;
	float lava_t = clamp(n1 * 0.6 + n2 * 0.4, 0.0, 1.0);

	// Hot lava in cracks, cooled crust on top
	vec3 col;
	if (lava_t > crust_threshold) {
		// Crust (dark, cooled rock)
		float crust_t = (lava_t - crust_threshold) / (1.0 - crust_threshold);
		col = mix(lava_color_cool.rgb, lava_color_crust.rgb, crust_t);
	} else {
		// Hot lava (bright, emissive)
		float hot_t = lava_t / max(crust_threshold, 0.01);
		col = mix(lava_color_hot.rgb, lava_color_cool.rgb, hot_t);
	}

	// Emission: hot areas glow
	float emission = (1.0 - clamp(lava_t / crust_threshold, 0.0, 1.0)) * emission_energy;

	ALBEDO = col * (1.0 + emission);
}
