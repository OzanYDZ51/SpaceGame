shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Mining laser beam — scrolling energy pulse effect
// Applied to a CylinderMesh stretched along Y axis

uniform vec4 core_color : source_color = vec4(0.3, 1.0, 0.6, 1.0);
uniform vec4 edge_color : source_color = vec4(0.1, 0.6, 0.3, 0.4);
uniform float scroll_speed : hint_range(0.5, 10.0) = 3.0;
uniform float pulse_frequency : hint_range(1.0, 30.0) = 12.0;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float core_width : hint_range(0.0, 1.0) = 0.3;
uniform float flicker_speed : hint_range(0.0, 20.0) = 8.0;
uniform float energy_density : hint_range(1.0, 20.0) = 6.0;
uniform float beam_intensity : hint_range(0.5, 8.0) = 3.0;

void fragment() {
	// UV.x = radial (0 at edge, 1 at opposite edge, 0.5 = center)
	// UV.y = along beam length
	float radial = abs(UV.x - 0.5) * 2.0;  // 0 at center, 1 at edge

	// Core beam — bright narrow center
	float core = smoothstep(core_width + 0.05, core_width - 0.05, radial);

	// Outer glow — soft falloff
	float glow = 1.0 - smoothstep(0.0, 1.0, radial);
	glow = pow(glow, 2.0);

	// Scrolling energy pulses along beam length
	float scroll_uv = UV.y * energy_density - TIME * scroll_speed;
	float energy_pulse = sin(scroll_uv * TAU) * 0.5 + 0.5;
	energy_pulse = pow(energy_pulse, 2.0);

	// Secondary finer pulse (faster, offset)
	float fine_pulse = sin(scroll_uv * TAU * 3.0 + 1.5) * 0.5 + 0.5;
	fine_pulse = pow(fine_pulse, 3.0) * 0.4;

	// Overall flicker (subtle instability)
	float flicker = 0.85 + sin(TIME * flicker_speed) * 0.08 + sin(TIME * flicker_speed * 2.7 + 0.5) * 0.07;

	// Combine
	float pulse_contrib = mix(1.0, energy_pulse + fine_pulse, pulse_intensity);
	float intensity = (core * 1.5 + glow * 0.6) * pulse_contrib * flicker;

	// Color: core is bright, edges tinted
	vec3 col = mix(edge_color.rgb, core_color.rgb, core) * beam_intensity;

	ALBEDO = col * intensity;
	ALPHA = clamp(intensity * (core * 0.9 + glow * 0.5), 0.0, 1.0);
}
