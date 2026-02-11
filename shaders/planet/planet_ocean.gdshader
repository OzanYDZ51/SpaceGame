shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// =============================================================================
// Planet Ocean — Animated water surface at the ocean level
// Sphere mesh at planet_radius * (1 + ocean_level), with wave animation.
// =============================================================================

uniform vec4 ocean_color_shallow : source_color = vec4(0.1, 0.35, 0.6, 0.9);
uniform vec4 ocean_color_deep : source_color = vec4(0.03, 0.12, 0.35, 0.95);
uniform float wave_speed : hint_range(0.0, 2.0) = 0.3;
uniform float wave_scale : hint_range(0.0001, 0.01) = 0.002;
uniform float wave_amplitude : hint_range(0.0, 50.0) = 5.0;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.8;
uniform float foam_threshold : hint_range(0.0, 1.0) = 0.7;

varying vec3 v_world_pos;
varying float v_wave_height;

void vertex() {
	v_world_pos = VERTEX;

	// Simple dual-wave displacement
	float t = TIME * wave_speed;
	float wave1 = sin(VERTEX.x * wave_scale * 1000.0 + t * 1.3) * cos(VERTEX.z * wave_scale * 800.0 + t * 0.9);
	float wave2 = sin(VERTEX.x * wave_scale * 600.0 - t * 0.7 + 2.0) * cos(VERTEX.z * wave_scale * 1200.0 + t * 1.1);
	v_wave_height = (wave1 + wave2) * 0.5;

	// Displace along surface normal (radial direction for sphere)
	vec3 radial = normalize(VERTEX);
	VERTEX += radial * v_wave_height * wave_amplitude;
}

void fragment() {
	// Depth-based color (fresnel approximation for shallow/deep)
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float fresnel = 1.0 - abs(dot(NORMAL, view_dir));
	fresnel = pow(abs(fresnel), 2.0);

	vec3 col = mix(ocean_color_deep.rgb, ocean_color_shallow.rgb, fresnel);

	// Foam on wave crests
	if (v_wave_height > foam_threshold * wave_amplitude) {
		float foam_t = clamp((v_wave_height - foam_threshold * wave_amplitude) / (wave_amplitude * 0.3), 0.0, 1.0);
		col = mix(col, vec3(0.9, 0.95, 1.0), foam_t * 0.6);
	}

	ALBEDO = col;
	ALPHA = mix(ocean_color_deep.a, ocean_color_shallow.a, fresnel);
	ROUGHNESS = 0.05 + (1.0 - specular_strength) * 0.3;
	METALLIC = 0.02;
	SPECULAR = specular_strength;
}
